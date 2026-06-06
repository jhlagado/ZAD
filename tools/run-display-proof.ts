#!/usr/bin/env node
/**
 * Assemble and run the GLCD display smoke proof in Debug80's TEC-1G runtime
 * with MON3 ROM loaded.
 */

const { existsSync, readFileSync, writeFileSync } = require('node:fs');
const { resolve } = require('node:path');

const TECM8_ROOT = resolve(__dirname, '..');
const DEBUG80_ROOT = resolve(process.env.DEBUG80_ROOT ?? '/Users/johnhardy/projects/debug80');
const AZM_ROOT = resolve(process.env.AZM_ROOT ?? '/Users/johnhardy/projects/AZM');
const MON3_ROM_CANDIDATES = [
  resolve(DEBUG80_ROOT, 'resources/bundles/tec1g/mon3/v1/mon3.bin'),
  '/Users/johnhardy/projects/debug80-tec1g-mon3/roms/tec1g/mon-3/mon3.bin',
  '/Users/johnhardy/projects/2026/debug80-tec1g-mon3/roms/tec1g/mon-3/mon3.bin',
];
const MON3_ROM_PATH = resolve(
  process.env.MON3_ROM_PATH ??
    MON3_ROM_CANDIDATES.find((path: string) => existsSync(path)) ??
    MON3_ROM_CANDIDATES[0],
);

const proofName = process.argv[2] ?? 'glcd-smoke-proof';
if (!/^[a-z0-9-]+$/.test(proofName)) {
  throw new Error(`invalid display proof name: ${proofName}`);
}

const PROOF_SOURCE = resolve(TECM8_ROOT, `proofs/display/${proofName}.asm`);
const MON3_INTERFACE = resolve(TECM8_ROOT, 'src/mon3.asmi');
const LAST_RUN = resolve(TECM8_ROOT, `proofs/display/${proofName}-last-run.json`);
const APP_START = 0x4000;
const PROOF_PASS = 0x42;
const SYS_CTRL = 0xff;
const SHADOW_OFF = 0x01;

type Runtime = {
  cpu: {
    pc: number;
    sp: number;
    halted: boolean;
  };
  hardware: {
    memory: Uint8Array;
    memRead?: (addr: number) => number;
    memWrite?: (addr: number, value: number) => void;
    forceMemWrite?: (addr: number, value: number) => void;
    isMemoryWritable?: (addr: number) => boolean;
  };
  step: () => { halted: boolean; pc: number; cycles?: number };
};

type PlatformRuntime = {
  recordCycles: (cycles: number) => void;
  state: {
    display?: {
      glcdCtrl?: {
        glcd?: number[] | Uint8Array;
      };
    };
  };
};

type D8Symbol = {
  name: string;
  kind: string;
  address?: number;
  value?: number;
};

type CompileResult = {
  diagnostics: Array<{ id?: string; message?: string; severity?: string }>;
  artifacts: Array<{ kind: string; bytes?: Uint8Array; json?: { symbols?: D8Symbol[] } }>;
};

function requireFromDebug80(modulePath: string): unknown {
  return require(resolve(DEBUG80_ROOT, modulePath));
}

async function compileProof(): Promise<{ bytes: Uint8Array; symbols: D8Symbol[] }> {
  const { compile, defaultFormatWriters } = await import(resolve(AZM_ROOT, 'dist/src/api-compile.js'));
  const result = await compile(
    PROOF_SOURCE,
    {
      emitBin: true,
      emitD8m: true,
      outputType: 'bin',
      sourceRoot: TECM8_ROOT,
      d8mInputs: {
        bin: `build/${proofName}.bin`,
      },
      registerCare: 'strict',
      registerCareProfile: 'mon3',
      registerCareInterfaces: [MON3_INTERFACE],
    },
    { formats: defaultFormatWriters },
  ) as CompileResult;

  if (result.diagnostics.length > 0) {
    throw new Error(`AZM diagnostics:\n${JSON.stringify(result.diagnostics, null, 2)}`);
  }

  const bin = result.artifacts.find((artifact) => artifact.kind === 'bin');
  const d8m = result.artifacts.find((artifact) => artifact.kind === 'd8m');
  if (!bin?.bytes) {
    throw new Error('AZM did not emit bin artifact');
  }
  return { bytes: bin.bytes, symbols: d8m?.json?.symbols ?? [] };
}

function symbolAddress(symbols: D8Symbol[], name: string): number {
  const symbol = symbols.find((entry) => entry.name === name);
  if (!symbol || typeof symbol.address !== 'number') {
    throw new Error(`missing address symbol: ${name}`);
  }
  return symbol.address;
}

function makeConfig() {
  return {
    regions: [
      { start: 0x0000, end: 0x07ff, kind: 'rom' },
      { start: 0x0800, end: 0x7fff, kind: 'ram' },
      { start: 0xc000, end: 0xffff, kind: 'rom' },
    ],
    romRanges: [
      { start: 0x0000, end: 0x07ff },
      { start: 0xc000, end: 0xffff },
    ],
    appStart: APP_START,
    entry: APP_START,
    updateMs: 100,
    yieldMs: 0,
    gimpSignal: false,
    expansionBankHi: false,
    matrixMode: false,
    protectOnReset: false,
    rtcEnabled: false,
    sdEnabled: false,
    sdHighCapacity: true,
  };
}

function loadRuntime(bytes: Uint8Array): { runtime: Runtime; platformRuntime: PlatformRuntime } {
  const { createTec1gRuntime } = requireFromDebug80('out/platforms/tec1g/runtime.js') as {
    createTec1gRuntime: Function;
  };
  const { createTec1gMemoryHooks } = requireFromDebug80(
    'out/platforms/tec1g/tec1g-memory.js',
  ) as { createTec1gMemoryHooks: Function };
  const { createZ80Runtime } = requireFromDebug80('out/z80/runtime.js') as {
    createZ80Runtime: Function;
  };

  const config = makeConfig();
  const tec1gRuntime = createTec1gRuntime(config, () => {});
  const memory = new Uint8Array(0x10000);
  const rom = readFileSync(MON3_ROM_PATH);
  memory.set(rom.subarray(0, 0x4000), 0xc000);
  memory.set(bytes, APP_START);

  const runtime = createZ80Runtime({ memory, startAddress: APP_START }, APP_START, tec1gRuntime.ioHandlers, {
    romRanges: config.romRanges,
  }) as Runtime;

  const hooks = createTec1gMemoryHooks(
    runtime.hardware.memory,
    config.romRanges,
    tec1gRuntime.state.system,
  );
  runtime.hardware.memRead = hooks.memRead;
  runtime.hardware.memWrite = hooks.memWrite;
  runtime.hardware.forceMemWrite = hooks.forceMemWrite;
  runtime.hardware.isMemoryWritable = hooks.isMemoryWritable;

  tec1gRuntime.ioHandlers.write?.(SYS_CTRL, SHADOW_OFF);
  runtime.hardware.memory.set(runtime.hardware.memory.subarray(0xc000, 0xc100), 0x0000);
  runtime.cpu.sp = 0x7ff0;
  runtime.cpu.pc = APP_START;
  return { runtime, platformRuntime: tec1gRuntime };
}

function runUntil(runtime: Runtime, platformRuntime: PlatformRuntime, doneAddr: number): number {
  const maxInstructions = 5_000_000;
  for (let i = 0; i < maxInstructions; i += 1) {
    if ((runtime.cpu.pc & 0xffff) === doneAddr) {
      return i;
    }
    const result = runtime.step();
    platformRuntime.recordCycles(result.cycles ?? 0);
  }
  throw new Error(`proof did not reach done at 0x${doneAddr.toString(16)}; pc=0x${runtime.cpu.pc.toString(16)}`);
}

function resultToString(value: number): string {
  return `0x${value.toString(16).padStart(2, '0')}`;
}

function hasVisibleGlcdPixels(platformRuntime: PlatformRuntime): boolean {
  return getGlcdBytes(platformRuntime).some((value) => value !== 0);
}

function getGlcdBytes(platformRuntime: PlatformRuntime): number[] {
  return Array.from(platformRuntime.state.display?.glcdCtrl?.glcd ?? []);
}

const DISPLAY_Y_ORIGIN = 2;

function glcdRowHasPixels(glcd: number[], displayRow: number): boolean {
  const firstPixelRow = displayRow * 6 + DISPLAY_Y_ORIGIN;
  for (let y = firstPixelRow; y < firstPixelRow + 6; y += 1) {
    const start = y * 16;
    const end = start + 16;
    if (glcd.slice(start, end).some((value) => value !== 0)) {
      return true;
    }
  }
  return false;
}

function verifyStructuredScreen(runtime: Runtime, platformRuntime: PlatformRuntime): void {
  const glcd = getGlcdBytes(platformRuntime);
  const missingRows = [];
  for (let row = 0; row < 10; row += 1) {
    if (!glcdRowHasPixels(glcd, row)) {
      missingRows.push(row);
    }
  }
  if (missingRows.length > 0) {
    throw new Error(`structured display proof did not render rows: ${missingRows.join(', ')}`);
  }

  const mon3Tgbuf = 0x13c0;
  const rowBytes = 16;
  const textColumnByte = 1;
  const expectedMarkers = [
    { row: 0, pattern: 0xf0, name: 'breakpoint' },
    { row: 1, pattern: 0x80, name: 'current' },
    { row: 2, pattern: 0xc0, name: 'selected' },
    { row: 5, pattern: 0xf0, name: 'breakpoint-current' },
    { row: 7, pattern: 0xc0, name: 'selected' },
  ];

  for (const marker of expectedMarkers) {
    for (let y = 0; y < 6; y += 1) {
      const address = mon3Tgbuf + (marker.row * 6 + DISPLAY_Y_ORIGIN + y) * rowBytes;
      const value = runtime.hardware.memory[address];
      if ((value & marker.pattern) !== marker.pattern) {
        throw new Error(
          `structured display proof missing ${marker.name} gutter bits at 0x${address.toString(16)}: got ${resultToString(value)} expected mask ${resultToString(marker.pattern)}`,
        );
      }

      const glcdOffset = (marker.row * 6 + DISPLAY_Y_ORIGIN + y) * rowBytes;
      const visibleValue = glcd[glcdOffset] ?? 0;
      if ((visibleValue & marker.pattern) !== marker.pattern) {
        throw new Error(
          `structured display proof missing visible ${marker.name} gutter bits at GLCD offset 0x${glcdOffset.toString(16)}: got ${resultToString(visibleValue)} expected mask ${resultToString(marker.pattern)}`,
        );
      }
    }
  }

  const cursorMask = 0x02;
  for (let y = 0; y < 6; y += 1) {
    const address = mon3Tgbuf + (DISPLAY_Y_ORIGIN + y) * rowBytes;
    const value = runtime.hardware.memory[address];
    if ((value & cursorMask) !== cursorMask) {
      throw new Error(
        `structured display proof missing row-0 cursor bit at 0x${address.toString(16)}: got ${resultToString(value)} expected mask ${resultToString(cursorMask)}`,
      );
    }

    const glcdOffset = (DISPLAY_Y_ORIGIN + y) * rowBytes;
    const visibleValue = glcd[glcdOffset] ?? 0;
    if ((visibleValue & cursorMask) !== cursorMask) {
      throw new Error(
        `structured display proof missing visible row-0 cursor bit at GLCD offset 0x${glcdOffset.toString(16)}: got ${resultToString(visibleValue)} expected mask ${resultToString(cursorMask)}`,
      );
    }
  }

  const expectedTextRows = [
    { row: 0, name: 'first source row' },
    { row: 1, name: 'second source row' },
    { row: 9, name: 'tenth source row' },
  ];

  for (const row of expectedTextRows) {
    let hasTextPixels = false;
    for (let y = 0; y < 6; y += 1) {
      const address = mon3Tgbuf + (row.row * 6 + DISPLAY_Y_ORIGIN + y) * rowBytes + textColumnByte;
      const memoryValue = runtime.hardware.memory[address];
      const glcdOffset = (row.row * 6 + DISPLAY_Y_ORIGIN + y) * rowBytes + textColumnByte;
      const visibleValue = glcd[glcdOffset] ?? 0;
      if (memoryValue !== 0 && visibleValue !== 0) {
        hasTextPixels = true;
      }
    }
    if (!hasTextPixels) {
      throw new Error(`structured display proof did not render ${row.name} text pixels in TGBUF`);
    }
  }

  for (let column = 'ORG 4000H'.length; column < 20; column += 1) {
    if (cellHasPixels(runtime.hardware.memory, 0, column)) {
      throw new Error(`structured display proof left stale pixels after shorter row redraw at column ${column}`);
    }
  }
}

function verifyEditorViewport(runtime: Runtime, platformRuntime: PlatformRuntime, symbols: D8Symbol[]): void {
  const glcd = getGlcdBytes(platformRuntime);
  for (let row = 0; row < 10; row += 1) {
    if (!glcdRowHasPixels(glcd, row)) {
      throw new Error(`editor viewport proof did not render display row: ${row}`);
    }
  }

  const expectedRows = [
    { symbol: 'EditorRowText0', text: 'ORG 4000H' },
    { symbol: 'EditorRowText1', text: 'CALL INIT' },
    { symbol: 'EditorRowText7', text: 'RET' },
    { symbol: 'EditorRowText9', text: 'END' },
  ];
  for (const row of expectedRows) {
    const address = symbolAddress(symbols, row.symbol);
    const actual = readCString(runtime.hardware.memory, address);
    if (actual !== row.text) {
      throw new Error(`editor viewport proof copied ${row.symbol} as "${actual}", expected "${row.text}"`);
    }
  }

  const mon3Tgbuf = 0x13c0;
  const rowBytes = 16;
  const expectedMarkers = [
    { row: 0, pattern: 0xf0, name: 'breakpoint' },
    { row: 1, pattern: 0x80, name: 'current' },
    { row: 3, pattern: 0xc0, name: 'selected' },
  ];

  for (const marker of expectedMarkers) {
    for (let y = 0; y < 6; y += 1) {
      const address = mon3Tgbuf + (marker.row * 6 + DISPLAY_Y_ORIGIN + y) * rowBytes;
      const value = runtime.hardware.memory[address];
      if ((value & marker.pattern) !== marker.pattern) {
        throw new Error(
          `editor viewport proof missing ${marker.name} gutter bits at 0x${address.toString(16)}: got ${resultToString(value)} expected mask ${resultToString(marker.pattern)}`,
        );
      }

      const glcdOffset = (marker.row * 6 + DISPLAY_Y_ORIGIN + y) * rowBytes;
      const visibleValue = glcd[glcdOffset] ?? 0;
      if ((visibleValue & marker.pattern) !== marker.pattern) {
        throw new Error(
          `editor viewport proof missing visible ${marker.name} gutter bits at GLCD offset 0x${glcdOffset.toString(16)}: got ${resultToString(visibleValue)} expected mask ${resultToString(marker.pattern)}`,
        );
      }
    }
  }
}

function cellHasPixels(memory: Uint8Array, row: number, column: number): boolean {
  const mon3Tgbuf = 0x13c0;
  const rowBytes = 16;
  const textX = 6;
  const cellX = textX + column * 6;
  for (let y = row * 6 + DISPLAY_Y_ORIGIN; y < row * 6 + DISPLAY_Y_ORIGIN + 6; y += 1) {
    for (let x = cellX; x < cellX + 6; x += 1) {
      const address = mon3Tgbuf + y * rowBytes + Math.floor(x / 8);
      const mask = 0x80 >> (x % 8);
      if ((memory[address] & mask) !== 0) {
        return true;
      }
    }
  }
  return false;
}

function readCellRows(memory: Uint8Array, row: number, column: number): number[] {
  const mon3Tgbuf = 0x13c0;
  const rowBytes = 16;
  const textX = 6;
  const cellX = textX + column * 6;
  const rows = [];
  for (let y = row * 6 + DISPLAY_Y_ORIGIN; y < row * 6 + DISPLAY_Y_ORIGIN + 6; y += 1) {
    let rowBits = 0;
    for (let x = cellX; x < cellX + 6; x += 1) {
      rowBits <<= 1;
      const address = mon3Tgbuf + y * rowBytes + Math.floor(x / 8);
      const mask = 0x80 >> (x % 8);
      if ((memory[address] & mask) !== 0) {
        rowBits |= 1;
      }
    }
    rows.push(rowBits);
  }
  return rows;
}

function readFontRows(memory: Uint8Array, charCode: number): number[] {
  const fontData = 0xdd9b;
  const offset = fontData + (charCode - 1) * 6;
  return Array.from(memory.subarray(offset, offset + 6), (value) => value & 0x3f);
}

function assertCellMatchesFont(memory: Uint8Array, row: number, column: number, charCode: number): void {
  const actual = readCellRows(memory, row, column);
  const expected = readFontRows(memory, charCode);
  if (actual.join(',') !== expected.join(',')) {
    throw new Error(
      `GLCD tile proof rendered ${String.fromCharCode(charCode)} as [${actual.join(',')}], expected font rows [${expected.join(',')}]`,
    );
  }
}

function verifyGlcdTile(runtime: Runtime, platformRuntime: PlatformRuntime): void {
  if (cellHasPixels(runtime.hardware.memory, 1, 0)) {
    throw new Error('GLCD tile proof left stale pixels in a cleared cell');
  }
  if (!cellHasPixels(runtime.hardware.memory, 1, 1)) {
    throw new Error('GLCD tile proof did not draw the adjacent cell');
  }
  if (!cellHasPixels(runtime.hardware.memory, 2, 0) || !cellHasPixels(runtime.hardware.memory, 2, 1)) {
    throw new Error('GLCD tile proof did not draw a text run');
  }
  assertCellMatchesFont(runtime.hardware.memory, 1, 1, 'B'.charCodeAt(0));
  assertCellMatchesFont(runtime.hardware.memory, 2, 0, 'O'.charCodeAt(0));
  assertCellMatchesFont(runtime.hardware.memory, 2, 1, 'K'.charCodeAt(0));

  const glcd = getGlcdBytes(platformRuntime);
  if (!glcdRowHasPixels(glcd, 1) || !glcdRowHasPixels(glcd, 2)) {
    throw new Error('GLCD tile proof did not flush tile rows to the visible GLCD');
  }
}

function readCString(memory: Uint8Array, address: number): string {
  const bytes = [];
  for (let current = address; current < memory.length; current += 1) {
    const value = memory[current];
    if (value === 0) {
      return Buffer.from(bytes).toString('ascii');
    }
    bytes.push(value);
  }
  throw new Error(`unterminated string at 0x${address.toString(16)}`);
}

async function main(): Promise<void> {
  if (!existsSync(MON3_ROM_PATH)) {
    throw new Error(`MON3 ROM not found: ${MON3_ROM_PATH}`);
  }

  const { bytes, symbols } = await compileProof();
  const doneAddr = symbolAddress(symbols, 'ProofDone');
  const resultAddr = symbolAddress(symbols, 'ResultMarker');
  const { runtime, platformRuntime } = loadRuntime(bytes);
  const instructions = runUntil(runtime, platformRuntime, doneAddr);
  const result = runtime.hardware.memory[resultAddr];
  const visiblePixels = hasVisibleGlcdPixels(platformRuntime);
  const requiresVisiblePixels = proofName !== 'editor-viewport-bad-record-proof';

  if (result !== PROOF_PASS) {
    throw new Error(`display proof failed: marker=${resultToString(result)}`);
  }
  if (requiresVisiblePixels && !visiblePixels) {
    throw new Error('display proof did not update Debug80 GLCD pixels');
  }
  if (proofName === 'structured-screen-proof') {
    verifyStructuredScreen(runtime, platformRuntime);
  }
  if (proofName === 'glcd-tile-proof') {
    verifyGlcdTile(runtime, platformRuntime);
  }
  if (proofName === 'editor-viewport-proof') {
    verifyEditorViewport(runtime, platformRuntime, symbols);
  }

  const report = {
    result: 'ok',
    proof: proofName,
    instructions,
    resultMarker: resultToString(result),
    visiblePixels,
  };
  writeFileSync(LAST_RUN, JSON.stringify(report, null, 2) + '\n', 'ascii');
  console.log(JSON.stringify(report, null, 2));
}

main().catch((error: unknown) => {
  const message = error instanceof Error ? error.message : String(error);
  console.error(`error: ${message}`);
  process.exit(1);
});
