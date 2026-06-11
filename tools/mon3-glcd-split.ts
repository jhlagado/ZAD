const { readFileSync, writeFileSync } = require('node:fs');
const { resolve } = require('node:path');

type GlcdSplitOptions = {
  bundleRoot?: string;
};

type WriteGlcdSplitOptions = GlcdSplitOptions & {
  outputPath: string;
};

type DebugMapSymbol = {
  name: string;
  kind: string;
  address?: number;
  value?: number;
  file: string;
  line: number;
};

type DebugMap = {
  files: Record<string, { segments: Array<{ start: number; end: number; kind: string }> }>;
  symbols: DebugMapSymbol[];
};

type GlcdRange = {
  start: string;
  end: string;
  startAddress: number;
  endAddress: number;
  bytes: number;
};

type GlcdCategory = {
  id: string;
  name: string;
  disposition: 'keep-reference' | 'rewrite' | 'relocate';
  bytes: number;
  bytesHex: string;
  ranges: GlcdRange[];
  notes: string;
};

type GlcdLabel = {
  name: string;
  addressHex: string;
  source: string;
};

type GlcdRamBuffer = {
  id: string;
  name: string;
  startHex: string;
  endHex: string;
  bytes: number;
  bytesHex: string;
  notes: string;
};

type GlcdRamSplit = {
  totalPracticalBytes: number;
  totalPracticalBytesHex: string;
  buffers: GlcdRamBuffer[];
};

type GlcdSplit = {
  generatedFrom: string;
  sourceFile: string;
  totalBytes: number;
  totalBytesHex: string;
  categories: GlcdCategory[];
  keyLabels: GlcdLabel[];
  ram: GlcdRamSplit;
};

type CategoryDefinition = {
  id: string;
  name: string;
  disposition: GlcdCategory['disposition'];
  ranges: Array<[string, string]>;
  notes: string;
};

const GLCD_SOURCE = 'glcd_library.z80';
const FIRST_NEXT_PACKAGE_LABEL = 'disStart';

const CATEGORY_DEFINITIONS: CategoryDefinition[] = [
  {
    id: 'hardware-init-clear-mode',
    name: 'Hardware init, clear, and mode setup',
    disposition: 'keep-reference',
    ranges: [['initLCD', 'drawBox']],
    notes: 'ST7920 setup, graphics/text mode switching, and full-screen clear routines. This is useful low-level hardware reference material.',
  },
  {
    id: 'drawing-primitives',
    name: 'Drawing primitives',
    disposition: 'rewrite',
    ranges: [['drawBox', 'plotToLCD']],
    notes: 'Box, line, circle, fill, pixel, and GBUF addressing routines. TECM8 should preserve bitmap capability, but can split these from the editor text path.',
  },
  {
    id: 'plot-text-mode',
    name: 'Plot and native text-mode helpers',
    disposition: 'keep-reference',
    ranges: [['plotToLCD', 'delayUS']],
    notes: 'GBUF-to-LCD transfer plus direct ST7920 text-mode string helpers.',
  },
  {
    id: 'timing-buffer-policy',
    name: 'Timing and buffer policy',
    disposition: 'rewrite',
    ranges: [['delayUS', 'initTerminal']],
    notes: 'LCD delay and clear/no-clear policy. TECM8 should keep timing knowledge but make buffer policy display-layer owned.',
  },
  {
    id: 'terminal-core',
    name: 'Terminal text core',
    disposition: 'rewrite',
    ranges: [
      ['initTerminal', 'setCursor'],
      ['displayCursor', 'drawGraphic'],
    ],
    notes: 'Terminal initialization, character/control handling, ASCII hex output, cursor visibility, inverse, underline, auto-LF, and plot policy.',
  },
  {
    id: 'cursor-scroll',
    name: 'Cursor and scrollback viewport',
    disposition: 'rewrite',
    ranges: [['setCursor', 'displayCursor']],
    notes: 'Cursor movement, six-pixel character cells, scroll-buffer shifting, and viewport movement. This is the part least aligned with a sector/page editor.',
  },
  {
    id: 'glyph-renderer',
    name: 'Glyph and cursor renderer',
    disposition: 'rewrite',
    ranges: [['drawGraphic', 'ROWS']],
    notes: '6x6 font/sprite rendering, inverse, underline, cursor XOR, and blanking primitives.',
  },
  {
    id: 'font-data',
    name: 'Font and text constants',
    disposition: 'keep-reference',
    ranges: [['ROWS', 'GLCD_BANNER']],
    notes: 'ST7920 text row table, init table, and 256-character 6-byte font data.',
  },
  {
    id: 'banner-data',
    name: 'MON3 GLCD banner bitmap',
    disposition: 'relocate',
    ranges: [['GLCD_BANNER', FIRST_NEXT_PACKAGE_LABEL]],
    notes: 'A 1024-byte startup bitmap. Useful as a demo asset, but not resident BIOS functionality.',
  },
];

const KEY_LABELS = [
  'initLCD',
  'clearGBUF',
  'clearGrLCD',
  'setGrMode',
  'setTxtMode',
  'drawPixel',
  'clearPixel',
  'flipPixel',
  'plotToLCD',
  'initTerminal',
  'sendCharToLCD',
  'sendStringToLCD',
  'setCursor',
  'SHIFT_BUFFER',
  'MOVE_VPORT',
  'drawGraphic',
  'FONT_DATA',
];

function defaultMon3BundleRoot(): string {
  return resolve(
    process.env.DEBUG80_ROOT ?? '/Users/johnhardy/projects/debug80',
    'resources/bundles/tec1g/mon3/v1',
  );
}

function repoRoot(): string {
  return resolve(__dirname, '..');
}

function readText(path: string): string {
  return readFileSync(path, 'utf8');
}

function readDebugMap(bundleRoot: string): DebugMap {
  return JSON.parse(readText(resolve(bundleRoot, 'mon3.d8.json')));
}

function labels(debugMap: DebugMap): DebugMapSymbol[] {
  return debugMap.symbols
    .filter((symbol) => symbol.kind === 'label')
    .sort((a, b) => addressOf(a) - addressOf(b));
}

function constants(debugMap: DebugMap): DebugMapSymbol[] {
  return debugMap.symbols.filter((symbol) => symbol.kind === 'constant');
}

function addressOf(symbol: DebugMapSymbol): number {
  if (typeof symbol.address === 'number') {
    return symbol.address;
  }
  if (typeof symbol.value === 'number') {
    return symbol.value;
  }
  throw new Error(`symbol has no address/value: ${symbol.name}`);
}

function findLabel(symbols: DebugMapSymbol[], name: string): DebugMapSymbol {
  const symbol = symbols.find((candidate) => candidate.name === name);
  if (!symbol) {
    throw new Error(`missing GLCD label: ${name}`);
  }
  return symbol;
}

function findConstant(symbols: DebugMapSymbol[], name: string): DebugMapSymbol {
  const symbol = symbols.find((candidate) => candidate.name === name);
  if (!symbol) {
    throw new Error(`missing GLCD constant: ${name}`);
  }
  return symbol;
}

function rangeFor(allLabels: DebugMapSymbol[], startName: string, endName: string): GlcdRange {
  const start = findLabel(allLabels, startName);
  const end = findLabel(allLabels, endName);
  const startAddress = addressOf(start);
  const endAddress = addressOf(end);
  if (endAddress <= startAddress) {
    throw new Error(`invalid GLCD range: ${startName}..${endName}`);
  }
  return {
    start: startName,
    end: endName,
    startAddress,
    endAddress,
    bytes: endAddress - startAddress,
  };
}

function analyzeMon3GlcdSplit(options: GlcdSplitOptions = {}): GlcdSplit {
  const bundleRoot = options.bundleRoot ?? defaultMon3BundleRoot();
  const debugMap = readDebugMap(bundleRoot);
  const allLabels = labels(debugMap);
  const allConstants = constants(debugMap);

  const categories = CATEGORY_DEFINITIONS.map((definition) => {
    const ranges = definition.ranges.map(([start, end]) => rangeFor(allLabels, start, end));
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

  const keyLabels = KEY_LABELS.map((name) => {
    const label = findLabel(allLabels, name);
    return {
      name,
      addressHex: hex(addressOf(label), 4),
      source: `${label.file}:${label.line}`,
    };
  });

  const totalBytes = categories.reduce((total, category) => total + category.bytes, 0);

  return {
    generatedFrom: bundleRoot,
    sourceFile: GLCD_SOURCE,
    totalBytes,
    totalBytesHex: hex(totalBytes, 4),
    categories,
    keyLabels,
    ram: ramSplit(allConstants),
  };
}

function ramSplit(allConstants: DebugMapSymbol[]): GlcdRamSplit {
  const gbuf = addressOf(findConstant(allConstants, 'GBUF'));
  const endpt = addressOf(findConstant(allConstants, 'ENDPT'));
  const sbufBytes = addressOf(findConstant(allConstants, 'SBUF'));
  const tgbuf = addressOf(findConstant(allConstants, 'TGBUF'));
  const stateEndExclusive = addressOf(findConstant(allConstants, 'PLOT_ALWAYS')) + 1;
  const practicalStart = gbuf;
  const practicalEndExclusive = 0x1800;

  const buffers = [
    buffer('gbuf', 'Graphics framebuffer (GBUF)', gbuf, endpt, 'Primary 128x64 one-bit graphics framebuffer, 16 bytes by 64 rows.'),
    buffer('scratch-state', 'Drawing scratch and terminal state', endpt, stateEndExclusive, 'Line/circle scratch values, clear-buffer flag, cursor state, viewport pointer, and terminal flags.'),
    buffer('unassigned-gap', 'Unassigned gap before scroll buffer', stateEndExclusive, 0x1000, 'Not named by the current GLCD constants, but inside the practical GLCD workspace.'),
    buffer('sbuf', 'Terminal scroll history (SBUF)', 0x1000, 0x1000 + sbufBytes, '960-byte scroll history: 16 bytes by 60 pixel rows, enough for ten 6-pixel terminal rows.'),
    buffer('tgbuf', 'Terminal viewport framebuffer (TGBUF)', tgbuf, tgbuf + 0x400, '1024-byte terminal graphics viewport used as the displayed text buffer.'),
    buffer('tail-headroom', 'Tail headroom', tgbuf + 0x400, practicalEndExclusive, 'Small remaining tail in the documented 0A00h-17FFh practical GLCD area.'),
  ];

  return {
    totalPracticalBytes: practicalEndExclusive - practicalStart,
    totalPracticalBytesHex: hex(practicalEndExclusive - practicalStart, 4),
    buffers,
  };
}

function buffer(id: string, name: string, start: number, endExclusive: number, notes: string): GlcdRamBuffer {
  return {
    id,
    name,
    startHex: hex(start, 4),
    endHex: hex(endExclusive - 1, 4),
    bytes: endExclusive - start,
    bytesHex: hex(endExclusive - start, 4),
    notes,
  };
}

function renderMon3GlcdSplitMarkdown(split: GlcdSplit): string {
  const lines = [
    '# MON3 GLCD Split Report',
    '',
    'Generated from Debug80 MON3 bundle source and `mon3.d8.json`.',
    '',
    `This is a label-range measurement of \`${split.sourceFile}\`. Code ranges are`,
    'taken from Debug80 map labels. Data ranges use the following package label',
    'as the end boundary where the GLCD source hands off to the next included package.',
    '',
    `Measured GLCD package span: ${split.totalBytes} bytes (\`${split.totalBytesHex}\`).`,
    '',
    '## ROM Category Split',
    '',
    '| Category | ID | Bytes | Hex | Disposition | Ranges | Notes |',
    '| --- | --- | ---: | --- | --- | --- | --- |',
  ];

  for (const category of split.categories) {
    lines.push(
      `| ${category.name} | \`${category.id}\` | ${category.bytes} | \`${category.bytesHex}\` | \`${category.disposition}\` | ${renderRanges(category.ranges)} | ${category.notes} |`,
    );
  }

  lines.push(
    '',
    '## RAM Workspace',
    '',
    `Practical GLCD RAM workspace: ${split.ram.totalPracticalBytes} bytes (\`${split.ram.totalPracticalBytesHex}\`) from \`0A00\` through \`17FF\`.`,
    '',
    '| Buffer | ID | Address Range | Bytes | Hex | Notes |',
    '| --- | --- | --- | ---: | --- | --- |',
  );

  for (const buffer of split.ram.buffers) {
    lines.push(
      `| ${buffer.name} | \`${buffer.id}\` | \`${buffer.startHex}\`-\`${buffer.endHex}\` | ${buffer.bytes} | \`${buffer.bytesHex}\` | ${buffer.notes} |`,
    );
  }

  lines.push(
    '',
    '## TECM8 Replacement Reading',
    '',
    'The ROM split supports the current design direction: keep the low-level ST7920',
    'hardware knowledge and the 6x6 font as reference material, but replace the',
    'terminal-centric scrollback model with TECM8-owned display modes.',
    '',
    'For the editor, the source sector/window should be the truth and the GLCD',
    'framebuffer should be a rendering target. A single 1024-byte framebuffer is',
    'non-negotiable for full bitmap output. The extra SBUF/TGBUF terminal buffers',
    'are useful for MON3 terminal history, but should become optional mode-specific',
    'RAM rather than a global requirement for every TECM8 text/editor view.',
    '',
    'The 1024-byte MON3 banner is the clearest ROM relocation candidate. The',
    'drawing primitives are useful, but should be decomposed so editor text,',
    'status rows, gutter markers, inverse text, and bitmap drawing do not all',
    'force the same terminal scrollback implementation.',
    '',
    'Key GLCD labels:',
    '',
    '| Label | Address | Source |',
    '| --- | --- | --- |',
  );

  for (const label of split.keyLabels) {
    lines.push(`| \`${label.name}\` | \`${label.addressHex}\` | \`${label.source}\` |`);
  }

  lines.push('');
  return `${lines.join('\n')}`;
}

function renderRanges(ranges: GlcdRange[]): string {
  return ranges
    .map((range) => `\`${range.start}\`-\`${range.end}\` (${range.bytes} bytes)`)
    .join('<br>');
}

function writeMon3GlcdSplitMarkdown(options: WriteGlcdSplitOptions): void {
  const split = analyzeMon3GlcdSplit({ bundleRoot: options.bundleRoot });
  writeFileSync(options.outputPath, renderMon3GlcdSplitMarkdown(split));
}

function checkMon3GlcdSplitMarkdown(options: WriteGlcdSplitOptions): void {
  const split = analyzeMon3GlcdSplit({ bundleRoot: options.bundleRoot });
  const expected = renderMon3GlcdSplitMarkdown(split);
  const actual = readText(options.outputPath);
  if (actual !== expected) {
    throw new Error(`${options.outputPath} is stale; run npm run mon3:glcd-split`);
  }
}

function hex(value: number, width: number): string {
  return value.toString(16).toUpperCase().padStart(width, '0');
}

if (require.main === module) {
  const args = process.argv.slice(2);
  const outputIndex = args.indexOf('--output');
  const bundleRootIndex = args.indexOf('--bundle-root');
  const outputPath = resolve(outputIndex === -1 ? 'docs/mon3/glcd-split.md' : args[outputIndex + 1]);
  const bundleRoot = bundleRootIndex === -1 ? defaultMon3BundleRoot() : resolve(args[bundleRootIndex + 1]);

  if (args.includes('--check')) {
    checkMon3GlcdSplitMarkdown({ bundleRoot, outputPath });
  } else {
    writeMon3GlcdSplitMarkdown({ bundleRoot, outputPath });
  }
}

module.exports = {
  analyzeMon3GlcdSplit,
  checkMon3GlcdSplitMarkdown,
  defaultMon3BundleRoot,
  renderMon3GlcdSplitMarkdown,
  writeMon3GlcdSplitMarkdown,
};
