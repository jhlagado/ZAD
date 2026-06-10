const { writeFileSync } = require('node:fs');
const { resolve } = require('node:path');

import type { Mon3Support } from './mon3/support';

const {
  defaultMon3BundleRoot,
  readText,
  readDebugMap,
  runMon3MarkdownCli,
}: Mon3Support = require('./mon3/support.ts');

type Mon3InventoryOptions = {
  bundleRoot?: string;
};

type WriteInventoryOptions = Mon3InventoryOptions & {
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

type ServiceClassification =
  | 'classic-core'
  | 'bios-keep'
  | 'extension-rewrite'
  | 'optional-relocate'
  | 'candidate-remove'
  | 'unknown';

type Mon3Service = {
  tableId: string;
  tableLabel: string;
  selector: number;
  selectorHex: string;
  service: string;
  address: number;
  addressHex: string;
  sourceFile: string;
  sourceLine: number;
  module: string;
  classification: ServiceClassification;
  notes: string;
};

type Mon3ServiceTable = {
  id: string;
  label: string;
  selectorRegister: string;
  tableSymbol: string;
  services: Mon3Service[];
};

type Mon3ServiceInventory = {
  generatedFrom: string;
  tables: Mon3ServiceTable[];
};

type TableDefinition = {
  id: string;
  label: string;
  selectorRegister: string;
  tableSymbol: string;
  countSymbol: string;
};

type ClassificationRule = {
  classification: ServiceClassification;
  notes: string;
};

const TABLES: TableDefinition[] = [
  {
    id: 'rst18-glcd',
    label: 'RST 18h',
    selectorRegister: 'A',
    tableSymbol: 'APITable2',
    countSymbol: 'API_COUNT2',
  },
  {
    id: 'rst10-main',
    label: 'RST 10h',
    selectorRegister: 'C',
    tableSymbol: 'APITable',
    countSymbol: 'API_COUNT',
  },
];

const CLASSIFICATIONS: Record<string, ClassificationRule> = {
  softwareID: core('Stable monitor identity call.'),
  versionID: core('Stable monitor identity call.'),
  preInit: core('Boot/reset helper used by MON3 itself.'),
  beepAlways: keep('Small audio feedback service.'),
  convAToSeg: keep('Seven-segment conversion utility.'),
  regAToASCII: keep('Hex formatting utility used by monitor and BIOS services.'),
  ASCIItoSegment: keep('LCD/seven-segment display utility.'),
  stringCompare: keep('Small utility routine.'),
  HLToString: keep('Word-to-ASCII utility.'),
  AToString: keep('Byte-to-ASCII utility.'),
  scanSegments: keep('Seven-segment hardware service.'),
  displayError: core('Classic monitor status display.'),
  LCDBusy: keep('Character LCD hardware service.'),
  stringToLCD: keep('Character LCD output service.'),
  charToLCD: keep('Character LCD output service.'),
  commandToLCD: keep('Character LCD command service.'),
  scanKeys: keep('Hex keypad service.'),
  scanKeysWait: keep('Hex keypad wait service.'),
  matrixScan: keep('Matrix keyboard raw scan service.'),
  joystickScan: keep('Hardware input service.'),
  serialEnable: keep('Bit-bang serial setup service.'),
  serialDisable: keep('Bit-bang serial setup service.'),
  txByte: keep('Bit-bang serial transmit service.'),
  rxByte: keep('Bit-bang serial receive service.'),
  intelHexLoad: remove('Legacy transfer workflow; SD and project flows should replace normal use.'),
  sendToSerialAPI: keep('Serial byte/range export service; monitor UI may be shaved later.'),
  receiveFromSerialAPI: keep('Serial receive service; monitor UI may be shaved later.'),
  sendAssemblyAPI: remove('Monitor export workflow rather than core BIOS service.'),
  sendHexAPI: remove('Monitor export workflow rather than core BIOS service.'),
  genDataDump: core('Classic memory inspection formatter.'),
  checkStartEnd: keep('Small range utility shared by monitor tools.'),
  menuDriver: relocate('Useful MON3 UI framework, but bulky for fixed BIOS.'),
  paramDriver: relocate('Useful MON3 UI framework, but bulky for fixed BIOS.'),
  timeDelay: keep('Timing utility.'),
  playNote: keep('Sound service.'),
  playTune: keep('Sound service.'),
  playTuneMenu: relocate('Interactive sound menu is optional.'),
  getCaps: keep('System state service.'),
  getShadow: keep('System state service.'),
  getProtect: keep('System state service.'),
  getExpand: keep('System state service.'),
  setCaps: keep('System state service.'),
  setShadow: keep('System state service.'),
  setProtect: keep('System state service.'),
  setExpand: keep('System state service.'),
  stringToSerial: keep('Serial string output service.'),
  RTCAPI: relocate('Keep compact RTC services; consider moving interactive RTC setup/viewer.'),
  menuPop: relocate('Menu framework helper.'),
  toggleCaps: keep('System state service.'),
  random: keep('Small utility service.'),
  setDisStart: core('Disassembler is classic MON3 core for now.'),
  getDisNext: core('Disassembler is classic MON3 core for now.'),
  getDisassembly: core('Disassembler is classic MON3 core for now.'),
  matrixScanASCII: keep('Matrix keyboard ASCII service.'),
  parseMatrixScan: keep('Matrix keyboard parsing service.'),
  LCDConfirm: relocate('Interactive LCD confirmation helper.'),
  getGLCDTerm: rewrite('GLCD terminal state should be replaced by TECM8 display policy.'),
  setGLCDTerm: rewrite('GLCD terminal state should be replaced by TECM8 display policy.'),
  loadFromDisk: remove('Storage user workflow; keep lower SD/file sector services.'),
  openFile: keep('SD-backed FAT32 file open service for TECM8 storage wrappers.'),
  readSector: keep('SD-backed FAT32 sector read service for TECM8 storage wrappers.'),
  writeSector: keep('SD-backed FAT32 sector write service for TECM8 storage wrappers.'),
  RGBScan: keep('RGB LED matrix hardware service.'),

  initLCD: rewrite('Keep GLCD hardware knowledge; replace terminal/editor layer.'),
  clearGBUF: rewrite('GLCD buffer primitive for future TECM8 display renderer.'),
  clearGrLCD: rewrite('GLCD clear primitive for future TECM8 display renderer.'),
  clearTxtLCD: rewrite('GLCD text clear primitive; terminal ownership should move to TECM8.'),
  setGrMode: rewrite('GLCD mode primitive.'),
  setTxtMode: rewrite('GLCD mode primitive.'),
  drawBox: rewrite('GLCD drawing primitive.'),
  drawLine: rewrite('GLCD drawing primitive.'),
  drawCircle: rewrite('GLCD drawing primitive.'),
  drawPixel: rewrite('GLCD drawing primitive.'),
  fillBox: rewrite('GLCD drawing primitive.'),
  fillCircle: rewrite('GLCD drawing primitive.'),
  plotToLCD: rewrite('GLCD plot/update primitive.'),
  printString: rewrite('Text renderer primitive; likely replaced or wrapped.'),
  printChars: rewrite('Text renderer primitive; likely replaced or wrapped.'),
  delayUS: keep('Timing service used by GLCD and other hardware paths.'),
  delayMS: keep('Timing service used by GLCD and other hardware paths.'),
  setBufClear: rewrite('MON3 GLCD buffer policy; TECM8 should own display policy.'),
  setBufNoClear: rewrite('MON3 GLCD buffer policy; TECM8 should own display policy.'),
  clearPixel: rewrite('GLCD drawing primitive.'),
  flipPixel: rewrite('GLCD drawing primitive.'),
  drawGraphic: rewrite('GLCD glyph/sprite primitive.'),
  invGraphic: rewrite('GLCD glyph/sprite primitive.'),
  initTerminal: rewrite('MON3 terminal layer is a replacement candidate.'),
  sendCharToLCD: rewrite('MON3 terminal layer is a replacement candidate.'),
  sendStringToLCD: rewrite('MON3 terminal layer is a replacement candidate.'),
  sendRegToLCD: rewrite('MON3 terminal/debug display helper.'),
  sendHLToLCD: rewrite('MON3 terminal/debug display helper.'),
  setCursor: rewrite('Display cursor primitive.'),
  getCursor: rewrite('Display cursor primitive.'),
  displayCursor: rewrite('Display cursor primitive.'),
  autoLF: rewrite('MON3 terminal policy.'),
  underline: rewrite('MON3 terminal policy.'),
  plotAlways: rewrite('MON3 terminal policy.'),
};

function core(notes: string): ClassificationRule {
  return { classification: 'classic-core', notes };
}

function keep(notes: string): ClassificationRule {
  return { classification: 'bios-keep', notes };
}

function rewrite(notes: string): ClassificationRule {
  return { classification: 'extension-rewrite', notes };
}

function relocate(notes: string): ClassificationRule {
  return { classification: 'optional-relocate', notes };
}

function remove(notes: string): ClassificationRule {
  return { classification: 'candidate-remove', notes };
}

function parseApiTable(source: string, table: TableDefinition): string[] {
  const lines = source.split(/\r?\n/);
  const start = lines.findIndex((line) => line.trim() === `${table.tableSymbol}:`);
  if (start < 0) {
    throw new Error(`missing ${table.tableSymbol}`);
  }

  const services: string[] = [];
  for (let index = start + 1; index < lines.length; index += 1) {
    const line = lines[index];
    if (line.includes(`${table.countSymbol}:`)) {
      return services;
    }
    const match = line.match(/^\s*\.dw\s+([A-Za-z_][A-Za-z0-9_]*)\b/);
    if (match) {
      services.push(match[1]);
    }
  }

  throw new Error(`missing ${table.countSymbol}`);
}

function findSymbol(debugMap: DebugMap, service: string): DebugMapSymbol {
  const matches = debugMap.symbols.filter((symbol) => symbol.kind === 'label' && symbol.name === service);
  if (matches.length === 0) {
    throw new Error(`missing symbol for ${service}`);
  }
  return matches[0];
}

function hex(value: number, width: number): string {
  return value.toString(16).toUpperCase().padStart(width, '0');
}

function sourceModule(sourceFile: string): string {
  return sourceFile.replace(/\.[^.]+$/, '');
}

function classify(service: string): ClassificationRule {
  return CLASSIFICATIONS[service] ?? {
    classification: 'unknown',
    notes: 'Needs manual classification.',
  };
}

function buildMon3ServiceInventory(options: Mon3InventoryOptions = {}): Mon3ServiceInventory {
  const bundleRoot = options.bundleRoot ?? defaultMon3BundleRoot();
  const source = readText(resolve(bundleRoot, 'mon3.z80'));
  const debugMap: DebugMap = readDebugMap(bundleRoot);

  return {
    generatedFrom: bundleRoot,
    tables: TABLES.map((table) => {
      const serviceNames = parseApiTable(source, table);
      const services = serviceNames.map((service, selector) => {
        const symbol = findSymbol(debugMap, service);
        const rule = classify(service);
        return {
          tableId: table.id,
          tableLabel: table.label,
          selector,
          selectorHex: hex(selector, 2),
          service,
          address: symbol.address,
          addressHex: hex(symbol.address, 4),
          sourceFile: symbol.file,
          sourceLine: symbol.line,
          module: sourceModule(symbol.file),
          classification: rule.classification,
          notes: rule.notes,
        };
      });

      return {
        id: table.id,
        label: table.label,
        selectorRegister: table.selectorRegister,
        tableSymbol: table.tableSymbol,
        services,
      };
    }),
  };
}

function renderMon3ServiceInventoryMarkdown(inventory: Mon3ServiceInventory): string {
  const lines = [
    '# MON3 Service Inventory',
    '',
    'Generated from Debug80 MON3 bundle source and `mon3.d8.json`.',
    '',
    'Classification is an initial planning aid, not a compatibility promise.',
    'The current strategy is to keep classic MON3 identity first, then reclaim',
    'space from GLCD replacement, PATA removal while preserving SD access, RTC',
    'UI relocation, and optional text/extensions.',
    '',
  ];

  for (const table of inventory.tables) {
    lines.push(
      `## ${table.label} API`,
      '',
      `Selector register: \`${table.selectorRegister}\`. Table symbol: \`${table.tableSymbol}\`.`,
      '',
      '| Table | Selector | Service | Address | Module | Source | Classification | Notes |',
      '| --- | --- | --- | --- | --- | --- | --- | --- |',
    );
    for (const service of table.services) {
      lines.push(
        `| ${table.label} | \`${service.selectorHex}h\` | \`${service.service}\` | \`${service.addressHex}\` | \`${service.module}\` | \`${service.sourceFile}:${service.sourceLine}\` | \`${service.classification}\` | ${escapeMarkdownTableText(service.notes)} |`,
      );
    }
    lines.push('');
  }

  lines.push(
    '## Classification Keys',
    '',
    '- `classic-core`: keep as part of recognisable MON3 behaviour.',
    '- `bios-keep`: keep as a compact resident hardware or utility service.',
    '- `extension-rewrite`: preserve the capability, but expect TECM8 to replace or wrap the MON3 implementation.',
    '- `optional-relocate`: useful, but a candidate for banked ROM, disk, or optional tools.',
    '- `candidate-remove`: likely removable from a TECM8-focused profile after compatibility review.',
    '- `unknown`: not yet classified.',
    '',
  );

  return `${lines.join('\n')}\n`;
}

function escapeMarkdownTableText(text: string): string {
  return text.replace(/\|/g, '\\|');
}

function writeMon3ServiceInventoryMarkdown(options: WriteInventoryOptions): void {
  const inventory = buildMon3ServiceInventory(options);
  writeFileSync(options.outputPath, renderMon3ServiceInventoryMarkdown(inventory));
}

function checkMon3ServiceInventoryMarkdown(options: WriteInventoryOptions): void {
  const inventory = buildMon3ServiceInventory(options);
  const expected = renderMon3ServiceInventoryMarkdown(inventory);
  const actual = readText(options.outputPath);
  if (actual !== expected) {
    throw new Error(`${options.outputPath} is stale; run npm run mon3:inventory`);
  }
}

if (require.main === module) {
  runMon3MarkdownCli(process.argv.slice(2), 'docs/mon3-service-inventory.md', {
    write: writeMon3ServiceInventoryMarkdown,
    check: checkMon3ServiceInventoryMarkdown,
  });
}

module.exports = {
  buildMon3ServiceInventory,
  checkMon3ServiceInventoryMarkdown,
  defaultMon3BundleRoot,
  renderMon3ServiceInventoryMarkdown,
  writeMon3ServiceInventoryMarkdown,
};
