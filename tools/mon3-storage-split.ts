const { writeFileSync } = require('node:fs');

import type { Mon3Support } from './mon3/support';

const {
  defaultMon3BundleRoot,
  readText,
  readDebugMap,
  runMon3MarkdownCli,
}: Mon3Support = require('./mon3/support.ts');

type StorageSplitOptions = {
  bundleRoot?: string;
};

type WriteStorageSplitOptions = StorageSplitOptions & {
  outputPath: string;
};

type DebugMapSymbol = {
  name: string;
  kind: string;
  address: number;
  file: string;
  line: number;
};

type DebugMap = {
  symbols: DebugMapSymbol[];
};

type StorageRange = {
  start: string;
  end: string;
  startAddress: number;
  endAddress: number;
  bytes: number;
};

type StorageCategory = {
  id: string;
  name: string;
  disposition: 'remove' | 'keep' | 'optional';
  bytes: number;
  bytesHex: string;
  ranges: StorageRange[];
  notes: string;
};

type StorageLabel = {
  name: string;
  address: number;
  addressHex: string;
  source: string;
};

type SdOnlyMinimum = {
  keepCategories: string[];
  keepBytes: number;
  optionalBytes: number;
  pataOnlyBytes: number;
  plausibleReclaimBytes: number;
  keyLabels: StorageLabel[];
};

type StorageSplit = {
  generatedFrom: string;
  sourceFile: string;
  totalBytes: number;
  totalBytesHex: string;
  categories: StorageCategory[];
  sdOnlyMinimum: SdOnlyMinimum;
};

type CategoryDefinition = {
  id: string;
  name: string;
  disposition: StorageCategory['disposition'];
  ranges: Array<[string, string]>;
  notes: string;
};

const STORAGE_SOURCE = 'pata_fat32.z80';

const CATEGORY_DEFINITIONS: CategoryDefinition[] = [
  {
    id: 'pata-specific',
    name: 'PATA-specific hardware path',
    disposition: 'remove',
    ranges: [
      ['initPata1', 'IDEreadSector'],
      ['readPATA', 'doERR'],
      ['writePATA', 'AtoLCD'],
    ],
    notes: 'PATA status polling, PATA data loops, and LBA register setup. SD-only TECM8 should remove this path.',
  },
  {
    id: 'block-device-shared',
    name: 'Shared block-device/error glue',
    disposition: 'keep',
    ranges: [
      ['IDEreadSector', 'readPATA'],
      ['doERR', 'writePATA'],
      ['AtoLCD', 'FATmount'],
    ],
    notes: 'Current read/write wrappers, MON3 LCD error output, and byte-to-LCD helper. Needs refactoring if PATA is cut.',
  },
  {
    id: 'fat-core',
    name: 'FAT32/file-sector core',
    disposition: 'keep',
    ranges: [
      ['FATmount', 'FATgetRootDir'],
      ['FATreadSector', 'saveFileName'],
      ['getFirstCluster', 'loadRAM'],
      ['BCDEtimeA', 'RTCAPI'],
    ],
    notes: 'Mount, cluster math, open/read/write sector services, and small arithmetic helpers needed for TECM8 storage.',
  },
  {
    id: 'storage-ui',
    name: 'Storage UI/load-save workflows',
    disposition: 'optional',
    ranges: [
      ['loadFromDisk', 'initPata1'],
      ['FATgetRootDir', 'FATreadSector'],
      ['saveFileName', 'getFirstCluster'],
      ['loadRAM', 'checkSDCardPresent'],
      ['LOAD_CFG', 'BCDEtimeA'],
    ],
    notes: 'MON3 menu loader, Intel HEX load path, RAM backup/restore, LCD progress UI, and storage configuration strings.',
  },
  {
    id: 'sd-spi',
    name: 'SD/SPI hardware path',
    disposition: 'keep',
    ranges: [
      ['checkSDCardPresent', 'MSG_TIMEOUT'],
      ['spiCMD0', 'LOAD_CFG'],
    ],
    notes: 'SD card detection, command setup, SPI read/write, block read/write, initialization, and SD command tables.',
  },
  {
    id: 'messages',
    name: 'Storage messages',
    disposition: 'optional',
    ranges: [['MSG_TIMEOUT', 'spiCMD0']],
    notes: 'MON3-facing storage error messages. A TECM8 BIOS may keep compact error codes and move text elsewhere.',
  },
];

const SD_ONLY_KEY_LABELS = [
  'openFile',
  'readSector',
  'writeSector',
  'FATmount',
  'FATreadSector',
  'FATgetSector',
  'FATgetFAT',
  'checkSDCardPresent',
  'sendSPICommand',
  'readSPIBlock',
  'writeSPIBlock',
  'initSD',
];

function storageSymbols(debugMap: DebugMap): DebugMapSymbol[] {
  return debugMap.symbols
    .filter((symbol) => symbol.kind === 'label' && symbol.file === STORAGE_SOURCE)
    .sort((a, b) => a.address - b.address);
}

function findSymbol(symbols: DebugMapSymbol[], name: string): DebugMapSymbol {
  const symbol = symbols.find((candidate) => candidate.name === name);
  if (!symbol) {
    throw new Error(`missing storage symbol: ${name}`);
  }
  return symbol;
}

function rangeFor(storageLabels: DebugMapSymbol[], allLabels: DebugMapSymbol[], startName: string, endName: string): StorageRange {
  const start = findSymbol(storageLabels, startName);
  const end = findSymbol(allLabels, endName);
  if (end.address <= start.address) {
    throw new Error(`invalid storage range: ${startName}..${endName}`);
  }
  return {
    start: startName,
    end: endName,
    startAddress: start.address,
    endAddress: end.address,
    bytes: end.address - start.address,
  };
}

function analyzeMon3StorageSplit(options: StorageSplitOptions = {}): StorageSplit {
  const bundleRoot = options.bundleRoot ?? defaultMon3BundleRoot();
  const debugMap: DebugMap = readDebugMap(bundleRoot);
  const symbols = storageSymbols(debugMap);
  const allLabels = debugMap.symbols
    .filter((symbol) => symbol.kind === 'label')
    .sort((a, b) => a.address - b.address);

  const categories = CATEGORY_DEFINITIONS.map((definition) => {
    const ranges = definition.ranges.map(([start, end]) => rangeFor(symbols, allLabels, start, end));
    const bytes = ranges.reduce((total, range) => total + range.bytes, 0);
    return {
      id: definition.id,
      name: definition.name,
      disposition: definition.disposition,
      bytes,
      bytesHex: hex(bytes, 4),
      ranges,
      notes: definition.notes,
    };
  });

  const totalBytes = categories.reduce((total, category) => total + category.bytes, 0);
  const keepCategories = categories.filter((category) => category.disposition === 'keep');
  const optionalCategories = categories.filter((category) => category.disposition === 'optional');
  const pataCategory = categories.find((category) => category.id === 'pata-specific');
  if (!pataCategory) {
    throw new Error('missing PATA category');
  }

  return {
    generatedFrom: bundleRoot,
    sourceFile: STORAGE_SOURCE,
    totalBytes,
    totalBytesHex: hex(totalBytes, 4),
    categories,
    sdOnlyMinimum: {
      keepCategories: keepCategories.map((category) => category.id),
      keepBytes: keepCategories.reduce((total, category) => total + category.bytes, 0),
      optionalBytes: optionalCategories.reduce((total, category) => total + category.bytes, 0),
      pataOnlyBytes: pataCategory.bytes,
      plausibleReclaimBytes:
        pataCategory.bytes + optionalCategories.reduce((total, category) => total + category.bytes, 0),
      keyLabels: SD_ONLY_KEY_LABELS.map((label) => {
        const symbol = findSymbol(symbols, label);
        return {
          name: label,
          address: symbol.address,
          addressHex: hex(symbol.address, 4),
          source: `${symbol.file}:${symbol.line}`,
        };
      }),
    },
  };
}

function renderMon3StorageSplitMarkdown(split: StorageSplit): string {
  const lines = [
    '# MON3 Storage Split Report',
    '',
    'Generated from Debug80 MON3 bundle source and `mon3.d8.json`.',
    '',
    'This is a rough label-range measurement of `pata_fat32.z80`. It measures',
    'address ranges between known labels, so the numbers include code and data',
    'inside those ranges. The categories are planning aids for an SD-only TECM8',
    'profile, not linker-enforced boundaries.',
    '',
    `Measured storage module span: ${split.totalBytes} bytes (\`${split.totalBytesHex}\`).`,
    '',
    '## Category Split',
    '',
    '| Category | ID | Bytes | Hex | Disposition | Ranges | Notes |',
    '| --- | --- | ---: | --- | --- | --- | --- |',
  ];

  for (const category of split.categories) {
    lines.push(
      `| ${category.name} | \`${category.id}\` | ${category.bytes} | \`${category.bytesHex}\` | \`${category.disposition}\` | ${category.ranges.map(renderRange).join('<br>')} | ${escapeMarkdownTableText(category.notes)} |`,
    );
  }

  lines.push(
    '',
    '## SD-only Minimum',
    '',
    `SD-only minimum keep set: ${split.sdOnlyMinimum.keepCategories.map((id) => `\`${id}\``).join(', ')}.`,
    '',
    `Estimated resident keep bytes: ${split.sdOnlyMinimum.keepBytes} bytes.`,
    '',
    `PATA-only bytes: ${split.sdOnlyMinimum.pataOnlyBytes} bytes.`,
    '',
    `Optional storage UI/message bytes: ${split.sdOnlyMinimum.optionalBytes} bytes.`,
    '',
    `Plausible reclaim from PATA + optional storage UI/messages: ${split.sdOnlyMinimum.plausibleReclaimBytes} bytes.`,
    '',
    'The important result is that PATA-only code is small. Most practical savings',
    'come from removing PATA plus relocating MON3 storage UI, RAM backup/restore,',
    'Intel HEX loading, and human-readable storage messages. FAT32/file-sector',
    'services and SD/SPI access remain the TECM8-critical surface.',
    '',
    'Key labels for the SD-only service set:',
    '',
    '| Label | Address | Source |',
    '| --- | --- | --- |',
  );

  for (const label of split.sdOnlyMinimum.keyLabels) {
    lines.push(`| \`${label.name}\` | \`${label.addressHex}\` | \`${label.source}\` |`);
  }

  lines.push('');
  return `${lines.join('\n')}\n`;
}

function renderRange(range: StorageRange): string {
  return `\`${range.start}\`-\`${range.end}\` (${range.bytes} bytes)`;
}

function escapeMarkdownTableText(text: string): string {
  return text.replace(/\|/g, '\\|');
}

function writeMon3StorageSplitMarkdown(options: WriteStorageSplitOptions): void {
  const split = analyzeMon3StorageSplit(options);
  writeFileSync(options.outputPath, renderMon3StorageSplitMarkdown(split));
}

function checkMon3StorageSplitMarkdown(options: WriteStorageSplitOptions): void {
  const split = analyzeMon3StorageSplit(options);
  const expected = renderMon3StorageSplitMarkdown(split);
  const actual = readText(options.outputPath);
  if (actual !== expected) {
    throw new Error(`${options.outputPath} is stale; run npm run mon3:storage-split`);
  }
}

function hex(value: number, width: number): string {
  return value.toString(16).toUpperCase().padStart(width, '0');
}

if (require.main === module) {
  runMon3MarkdownCli(process.argv.slice(2), 'docs/mon3-storage-split.md', {
    write: writeMon3StorageSplitMarkdown,
    check: checkMon3StorageSplitMarkdown,
  });
}

module.exports = {
  analyzeMon3StorageSplit,
  checkMon3StorageSplitMarkdown,
  defaultMon3BundleRoot,
  renderMon3StorageSplitMarkdown,
  writeMon3StorageSplitMarkdown,
};
