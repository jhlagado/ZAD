/**
 * Shared Debug80/TEC-1G proof harness for TECM8 proof runners.
 *
 * Every `tools/run-*` proof script drives the same stack: compile AZM proof
 * source, load Debug80's TEC-1G (or bare Z80) runtime with MON3 ROM, run to a
 * done marker, then inspect memory/GLCD/TM8 state. This module owns that
 * shared plumbing so individual runners only contain proof-specific fixtures
 * and verification logic.
 *
 * Runtime module shape: this file is consumed through CommonJS `require` from
 * the proof runners. The single `export type` below is erased by Node's type
 * stripping, so at runtime this remains a plain CJS module.
 */

const { execFileSync } = require('node:child_process');
const { existsSync, readFileSync, writeFileSync } = require('node:fs');
const { resolve } = require('node:path');

const TECM8_ROOT = resolve(__dirname, '../..');
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
const IMAGE_TOOL = resolve(TECM8_ROOT, 'tools/create-storage-proof-image.ts');
const NODE_TS_ARGS = ['--experimental-strip-types'];
const MON3_INTERFACE = resolve(TECM8_ROOT, 'src/mon3.asmi');

const APP_START = 0x4000;
const PROOF_PASS = 0x42;
const SYS_CTRL = 0xff;
const SHADOW_OFF = 0x01;
const MCB = 0x0888;
const MCB_SD_CARD = 0x80;
const MON3_SYS_MODE = 0x089d;
const TM8_VOLUME_BYTES = 4 * 1024 * 1024;
const DISPLAY_Y_ORIGIN = 2;

type Runtime = {
  cpu: {
    pc: number;
    sp: number;
    halted: boolean;
    a: number;
    b: number;
    c: number;
    d: number;
    e: number;
    h: number;
    l: number;
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
  applyMatrixKey?: (row: number, col: number, pressed: boolean) => void;
  setMatrixMode?: (enabled: boolean) => void;
  recordCycles: (cycles: number) => void;
  state: {
    display?: { glcdCtrl?: { glcd?: number[] | Uint8Array } };
    system?: unknown;
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

type LoadedRuntime = { runtime: Runtime; platformRuntime: PlatformRuntime };

type Tec1gRuntimeOptions = {
  imagePath?: string;
  startAddress?: number;
  matrixMode?: boolean;
  sysModeShadowOff?: boolean;
};

function requireFromDebug80(modulePath: string): unknown {
  return require(resolve(DEBUG80_ROOT, modulePath));
}

function requireTm8Format(): any {
  return require(resolve(TECM8_ROOT, 'tools/tm8/format.ts'));
}

async function compileAzm(
  sourcePath: string,
  binName: string,
  options: { interfaces?: string[] } = {},
): Promise<{ bytes: Uint8Array; symbols: D8Symbol[] }> {
  const { compile, defaultFormatWriters } = await import(resolve(AZM_ROOT, 'dist/src/api-compile.js'));
  const interfaces = options.interfaces;
  const result = await compile(
    sourcePath,
    {
      emitBin: true,
      emitD8m: true,
      outputType: 'bin',
      sourceRoot: TECM8_ROOT,
      d8mInputs: {
        bin: `build/${binName}.bin`,
      },
      registerContracts: 'strict',
      registerContractsProfile: 'mon3',
      ...(interfaces && interfaces.length > 0 ? { registerContractsInterfaces: interfaces } : {}),
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
  const address = symbol?.address ?? symbol?.value;
  if (typeof address !== 'number') {
    throw new Error(`missing address symbol: ${name}`);
  }
  return address;
}

function optionalSymbolAddress(symbols: D8Symbol[], name: string): number | undefined {
  const symbol = symbols.find((entry) => entry.name === name);
  return typeof symbol?.address === 'number' ? symbol.address : undefined;
}

function makeTec1gConfig(options: Tec1gRuntimeOptions = {}) {
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
    entry: options.startAddress ?? APP_START,
    updateMs: 100,
    yieldMs: 0,
    gimpSignal: false,
    expansionBankHi: false,
    matrixMode: options.matrixMode ?? false,
    protectOnReset: false,
    rtcEnabled: false,
    sdEnabled: options.imagePath !== undefined,
    sdHighCapacity: true,
    ...(options.imagePath !== undefined ? { sdImagePath: options.imagePath } : {}),
  };
}

function loadTec1gRuntime(bytes: Uint8Array, options: Tec1gRuntimeOptions = {}): LoadedRuntime {
  const { createTec1gRuntime } = requireFromDebug80('out/platforms/tec1g/runtime.js') as {
    createTec1gRuntime: Function;
  };
  const { createTec1gMemoryHooks } = requireFromDebug80(
    'out/platforms/tec1g/tec1g-memory.js',
  ) as { createTec1gMemoryHooks: Function };
  const { createZ80Runtime } = requireFromDebug80('out/z80/runtime.js') as {
    createZ80Runtime: Function;
  };

  const startAddress = options.startAddress ?? APP_START;
  const config = makeTec1gConfig(options);
  const tec1gRuntime = createTec1gRuntime(config, () => {});
  const memory = new Uint8Array(0x10000);
  const rom = readFileSync(MON3_ROM_PATH);
  memory.set(rom.subarray(0, 0x4000), 0xc000);
  memory.set(bytes, APP_START);

  const runtime = createZ80Runtime({ memory, startAddress }, startAddress, tec1gRuntime.ioHandlers, {
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

  // Minimal MON3 startup state: shadow ROM off, low vectors copied to RAM.
  tec1gRuntime.ioHandlers.write?.(SYS_CTRL, SHADOW_OFF);
  runtime.hardware.memory.set(runtime.hardware.memory.subarray(0xc000, 0xc100), 0x0000);
  if (options.imagePath !== undefined) {
    runtime.hardware.forceMemWrite?.(MCB, MCB_SD_CARD);
  }
  if (options.sysModeShadowOff) {
    runtime.hardware.forceMemWrite?.(MON3_SYS_MODE, SHADOW_OFF);
  }
  runtime.cpu.sp = 0x7ff0;
  runtime.cpu.pc = startAddress;
  return { runtime, platformRuntime: tec1gRuntime };
}

function loadBareZ80Runtime(bytes: Uint8Array): Runtime {
  const { createZ80Runtime } = requireFromDebug80('out/z80/runtime.js') as {
    createZ80Runtime: Function;
  };
  const memory = new Uint8Array(0x10000);
  memory.set(bytes, APP_START);
  const runtime = createZ80Runtime({ memory, startAddress: APP_START }, APP_START, {}, {
    romRanges: [],
  }) as Runtime;
  runtime.cpu.sp = 0x7ff0;
  runtime.cpu.pc = APP_START;
  return runtime;
}

function stepRuntime(runtime: Runtime, platformRuntime: PlatformRuntime): void {
  const result = runtime.step();
  platformRuntime.recordCycles(result.cycles ?? 0);
}

function runUntil(
  runtime: Runtime,
  platformRuntime: PlatformRuntime,
  doneAddr: number,
  maxInstructions = 80_000_000,
): number {
  for (let i = 0; i < maxInstructions; i += 1) {
    if ((runtime.cpu.pc & 0xffff) === doneAddr) {
      return i;
    }
    stepRuntime(runtime, platformRuntime);
  }
  throw new Error(`proof did not reach done at 0x${doneAddr.toString(16)}; pc=0x${runtime.cpu.pc.toString(16)}`);
}

function runUntilPc(
  runtime: Runtime,
  platformRuntime: PlatformRuntime,
  targetAddr: number,
  maxInstructions: number,
): number {
  for (let i = 0; i < maxInstructions; i += 1) {
    if ((runtime.cpu.pc & 0xffff) === targetAddr) {
      return i;
    }
    stepRuntime(runtime, platformRuntime);
  }
  throw new Error(`live smoke did not reach 0x${targetAddr.toString(16)}; pc=0x${runtime.cpu.pc.toString(16)}`);
}

function stepThenRunUntilPc(
  runtime: Runtime,
  platformRuntime: PlatformRuntime,
  targetAddr: number,
  maxInstructions: number,
): number {
  stepRuntime(runtime, platformRuntime);
  return runUntilPc(runtime, platformRuntime, targetAddr, maxInstructions);
}

function runUntilAnyPc(
  runtime: Runtime,
  platformRuntime: PlatformRuntime,
  targetAddrs: number[],
  maxInstructions: number,
): number {
  for (let i = 0; i < maxInstructions; i += 1) {
    const pc = runtime.cpu.pc & 0xffff;
    if (targetAddrs.includes(pc)) {
      return pc;
    }
    stepRuntime(runtime, platformRuntime);
  }
  throw new Error(
    `live smoke did not reach any target ${targetAddrs.map((addr) => `0x${addr.toString(16)}`).join(', ')}; pc=0x${runtime.cpu.pc.toString(16)}`,
  );
}

function runInstructions(runtime: Runtime, platformRuntime: PlatformRuntime, count: number): void {
  for (let i = 0; i < count; i += 1) {
    stepRuntime(runtime, platformRuntime);
  }
}

function runUntilHalt(runtime: Runtime, maxInstructions = 100_000): number {
  for (let i = 0; i < maxInstructions; i += 1) {
    const result = runtime.step();
    if (runtime.cpu.halted || result.halted) {
      return i + 1;
    }
  }
  throw new Error(`proof did not halt; pc=0x${runtime.cpu.pc.toString(16)}`);
}

function resultToString(value: number): string {
  return `0x${value.toString(16).padStart(2, '0')}`;
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

function readAsciiZ(memory: Uint8Array, address: number): string {
  let end = address;
  while (end < memory.length && memory[end] !== 0) {
    end += 1;
  }
  return Buffer.from(memory.subarray(address, end)).toString('ascii');
}

function readWord(memory: Uint8Array, address: number): number {
  return memory[address] | (memory[(address + 1) & 0xffff] << 8);
}

function encodeSourceRecords(lines: string[]): Buffer {
  const records = Buffer.alloc(lines.length * 32);
  lines.forEach((line, index) => {
    const bytes = Buffer.from(line, 'ascii');
    if (bytes.length > 31) {
      throw new Error(`line too long: ${line}`);
    }
    records[index * 32] = bytes.length;
    bytes.copy(records, index * 32 + 1);
  });
  return records;
}

function readSourceRecord(memory: Uint8Array, address: number, record: number): string {
  const start = address + record * 32;
  const length = memory[start] & 0x1f;
  return Buffer.from(memory.subarray(start + 1, start + 1 + length)).toString('ascii');
}

function createProofImage(imagePath: string): void {
  execFileSync(process.execPath, [...NODE_TS_ARGS, IMAGE_TOOL, imagePath], {
    cwd: TECM8_ROOT,
    stdio: 'ignore',
  });
}

function imageManifest(imagePath: string): { volume_start_byte_offset: number } {
  return JSON.parse(readFileSync(imagePath.replace(/\.[^.]*$/, '.json'), 'utf8'));
}

function writeVolumeIntoImage(imagePath: string, volume: Buffer): void {
  const manifest = imageManifest(imagePath);
  const image = Buffer.from(readFileSync(imagePath));
  volume.copy(image, manifest.volume_start_byte_offset);
  writeFileSync(imagePath, image);
}

function readVolumeFromImage(imagePath: string): Buffer {
  const manifest = imageManifest(imagePath);
  const image = readFileSync(imagePath);
  return Buffer.from(
    image.subarray(manifest.volume_start_byte_offset, manifest.volume_start_byte_offset + TM8_VOLUME_BYTES),
  );
}

function readFileFromImage(imagePath: string, tm8Path: string): Buffer {
  const { readFileFromVolumeImage } = requireTm8Format();
  return readFileFromVolumeImage(readVolumeFromImage(imagePath), tm8Path) as Buffer;
}

function getGlcdBytes(platformRuntime: PlatformRuntime): number[] {
  return Array.from(platformRuntime.state.display?.glcdCtrl?.glcd ?? []);
}

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

function readSixPixelRows(readByte: (offset: number) => number, row: number, column: number): number[] {
  const rowBytes = 16;
  const textX = 6;
  const cellX = textX + column * 6;
  const rows = [];
  for (let y = row * 6 + DISPLAY_Y_ORIGIN; y < row * 6 + DISPLAY_Y_ORIGIN + 6; y += 1) {
    let rowBits = 0;
    for (let x = cellX; x < cellX + 6; x += 1) {
      rowBits <<= 1;
      const offset = y * rowBytes + Math.floor(x / 8);
      const mask = 0x80 >> (x % 8);
      if ((readByte(offset) & mask) !== 0) {
        rowBits |= 1;
      }
    }
    rows.push(rowBits);
  }
  return rows;
}

function readCellRows(memory: Uint8Array, row: number, column: number): number[] {
  const mon3Tgbuf = 0x13c0;
  return readSixPixelRows((offset) => memory[mon3Tgbuf + offset] ?? 0, row, column);
}

function readGlcdCellRows(glcd: number[], row: number, column: number): number[] {
  return readSixPixelRows((offset) => glcd[offset] ?? 0, row, column);
}

function readFontRows(memory: Uint8Array, charCode: number): number[] {
  const fontData = 0xdd9b;
  const offset = fontData + (charCode - 1) * 6;
  return Array.from(memory.subarray(offset, offset + 6), (value) => value & 0x3f);
}

function assertCellMatchesInvertedFont(memory: Uint8Array, row: number, column: number, charCode: number): void {
  const actual = readCellRows(memory, row, column);
  const expected = readFontRows(memory, charCode).map((value) => value ^ 0x3f);
  assertRowsEqual('GLCD cursor proof', charCode, actual, expected);
}

function assertGlcdCellMatchesInvertedFont(
  memory: Uint8Array,
  glcd: number[],
  row: number,
  column: number,
  charCode: number,
): void {
  const actual = readGlcdCellRows(glcd, row, column);
  const expected = readFontRows(memory, charCode).map((value) => value ^ 0x3f);
  assertRowsEqual('visible GLCD cursor proof', charCode, actual, expected);
}

function assertRowsEqual(label: string, charCode: number, actual: number[], expected: number[]): void {
  if (actual.join(',') !== expected.join(',')) {
    throw new Error(
      `${label} rendered inverted ${String.fromCharCode(charCode)} as [${actual.join(',')}], expected [${expected.join(',')}]`,
    );
  }
}

const harnessExports = {
  TECM8_ROOT,
  DEBUG80_ROOT,
  AZM_ROOT,
  MON3_ROM_PATH,
  MON3_INTERFACE,
  IMAGE_TOOL,
  NODE_TS_ARGS,
  APP_START,
  PROOF_PASS,
  SYS_CTRL,
  SHADOW_OFF,
  MCB,
  MCB_SD_CARD,
  MON3_SYS_MODE,
  TM8_VOLUME_BYTES,
  DISPLAY_Y_ORIGIN,
  requireFromDebug80,
  requireTm8Format,
  compileAzm,
  symbolAddress,
  optionalSymbolAddress,
  makeTec1gConfig,
  loadTec1gRuntime,
  loadBareZ80Runtime,
  stepRuntime,
  runUntil,
  runUntilPc,
  stepThenRunUntilPc,
  runUntilAnyPc,
  runInstructions,
  runUntilHalt,
  resultToString,
  readCString,
  readAsciiZ,
  readWord,
  encodeSourceRecords,
  readSourceRecord,
  createProofImage,
  imageManifest,
  writeVolumeIntoImage,
  readVolumeFromImage,
  readFileFromImage,
  getGlcdBytes,
  glcdRowHasPixels,
  readCellRows,
  readGlcdCellRows,
  readFontRows,
  assertCellMatchesInvertedFont,
  assertGlcdCellMatchesInvertedFont,
};

export type ProofHarness = typeof harnessExports;
export type { Runtime, PlatformRuntime, D8Symbol };

module.exports = harnessExports;
