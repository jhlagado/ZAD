#!/usr/bin/env node
/**
 * Assemble and run the TECM8 editor entry in Debug80's TEC-1G runtime.
 */

const { execFileSync } = require('node:child_process');
const { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } = require('node:fs');
const { tmpdir } = require('node:os');
const { dirname, resolve } = require('node:path');

const TECM8_ROOT = resolve(__dirname, '..');
const DEBUG80_ROOT = resolve(process.env.DEBUG80_ROOT ?? '/Users/johnhardy/projects/debug80');
const AZM_ROOT = process.env.AZM_ROOT ? resolve(process.env.AZM_ROOT) : undefined;
const SESSION_DIR = resolve(TECM8_ROOT, 'demos/debug80');
const IMAGE_PATH = resolve(SESSION_DIR, 'editor-session-fat32.img');
const GLCD_CAPTURE_PATH = resolve(SESSION_DIR, 'editor-session-glcd.pgm');
const SUMMARY_PATH = resolve(SESSION_DIR, 'editor-session-last-run.json');
const IMAGE_TOOL = resolve(TECM8_ROOT, 'tools/create-storage-proof-image.ts');
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

const SOURCE_FILE = resolve(TECM8_ROOT, 'src/main.asm');
const SCRIPT_SOURCE_FILE = resolve(TECM8_ROOT, 'src/editor-session-script.main.asm');
const MON3_INTERFACE = resolve(TECM8_ROOT, 'src/mon3.asmi');
const APP_START = 0x4000;
const PASS = 0x42;
const SYS_CTRL = 0xff;
const SHADOW_OFF = 0x01;
const MCB = 0x0888;
const MCB_SD_CARD = 0x80;
const MON3_SYS_MODE = 0x089d;
const TM8_VOLUME_BYTES = 4 * 1024 * 1024;
const FIXED_SYMBOLS: Record<string, number> = {
  EditorNavCachePageBuffer: 0x3000,
  EditorNavPageBuffer: 0x3200,
  EditorNavNextPageBuffer: 0x3400,
  EditorNavBackupPageBuffer: 0x3600,
};

type Runtime = {
  cpu: { pc: number; sp: number; halted: boolean };
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

function requireFromDebug80(modulePath: string): unknown {
  return require(resolve(DEBUG80_ROOT, modulePath));
}

async function compileMain(sourceFile = SOURCE_FILE): Promise<{ bytes: Uint8Array; symbols: D8Symbol[] }> {
  const { compile, defaultFormatWriters } = AZM_ROOT
    ? await import(resolve(AZM_ROOT, 'dist/src/api-compile.js'))
    : await import('@jhlagado/azm/compile');
  const result = await compile(
    sourceFile,
    {
      emitBin: true,
      emitD8m: true,
      outputType: 'bin',
      sourceRoot: TECM8_ROOT,
      d8mInputs: { bin: 'build/main.bin' },
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
  const address = symbol?.address ?? symbol?.value ?? FIXED_SYMBOLS[name];
  if (typeof address !== 'number') {
    throw new Error(`missing address symbol: ${name}`);
  }
  return address;
}

function readWord(memory: Uint8Array, address: number): number {
  return memory[address] | (memory[address + 1] << 8);
}

function readRuntimeByte(runtime: Runtime, address: number): number {
  return runtime.hardware.memory[address] ?? 0;
}

function readCString(memory: Uint8Array, address: number): string {
  const bytes: number[] = [];
  for (let offset = address; offset < memory.length && memory[offset] !== 0; offset += 1) {
    bytes.push(memory[offset]);
  }
  return Buffer.from(bytes).toString('ascii');
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

function encodeProjectConfig(mainFile: string): Buffer {
  return Buffer.from(['tm8project=1', `main=${mainFile}`, ''].join('\n'), 'ascii');
}

function manifestPath(imagePath: string): string {
  return imagePath.replace(/\.[^.]*$/, '.json');
}

function defaultSessionSourceLines(): string[] {
  return [
    'R0 LINE 00',
    'R0 LINE 01',
    'R0 LINE 02',
    'R0 LINE 03',
    'R0 LINE 04',
    'R0 LINE 05',
    'R0 LINE 06',
    'R0 LINE 07',
    'R0 LINE 08',
    'R0 LINE 09',
    'R0 LINE 10',
    'R0 LINE 11',
    'R0 LINE 12',
    'R0 LINE 13',
    'R0 LINE 14',
    '',
    'R1 LINE 00',
    'R1 LINE 01',
    'R1 LINE 02',
    'R1 LINE 03',
    'R1 LINE 04',
    'R1 LINE 05',
    'R1 LINE 06',
    'R1 LINE 07',
    'R1 LINE 08',
    'R1 LINE 09',
    'R1 LINE 10',
    'R1 LINE 11',
    'R1 LINE 12',
    'R1 LINE 13',
    'R1 LINE 14',
    'R1 LINE 15',
  ];
}

function blockSmokeSourceLines(): string[] {
  return [
    'B0 LINE 00',
    'B0 LINE 01',
    'B0 LINE 02',
    'B0 LINE 03',
    'B0 LINE 04',
    'B0 LINE 05',
    'B0 LINE 06',
    'B0 LINE 07',
    'B0 LINE 08',
    'B0 LINE 09',
    '',
    '',
    '',
    '',
    '',
    '',
  ];
}

function ensureSessionImageWithSourceLines(imagePath: string, sourceLines: string[]): void {
  mkdirSync(dirname(imagePath), { recursive: true });
  execFileSync(process.execPath, ['--experimental-strip-types', IMAGE_TOOL, imagePath], {
    cwd: TECM8_ROOT,
    stdio: 'ignore',
  });

  const { createVolumeImage, importFileIntoVolumeImage, readFileFromVolumeImage } =
    require(resolve(TECM8_ROOT, 'tools/tm8/format.ts'));
  let volume = createVolumeImage() as Buffer;
  const sourceRecords = encodeSourceRecords(sourceLines);
  volume = importFileIntoVolumeImage(volume, '/tecm8.prj', encodeProjectConfig('/src/main.asm'));
  volume = importFileIntoVolumeImage(volume, '/src/main.asm', sourceRecords);

  const storedProject = readFileFromVolumeImage(volume, '/tecm8.prj') as Buffer;
  if (!storedProject.equals(encodeProjectConfig('/src/main.asm'))) {
    throw new Error('generated project config was not stored exactly');
  }

  const manifest = JSON.parse(readFileSync(manifestPath(imagePath), 'utf8'));
  const image = Buffer.from(readFileSync(imagePath));
  volume.copy(image, manifest.volume_start_byte_offset);
  writeFileSync(imagePath, image);
}

function ensureSessionImage(imagePath: string): void {
  ensureSessionImageWithSourceLines(imagePath, defaultSessionSourceLines());
}

function ensureBlockSmokeSessionImage(imagePath: string): void {
  ensureSessionImageWithSourceLines(imagePath, blockSmokeSourceLines());
}

function makeConfig(imagePath: string, startAddress = APP_START, matrixMode = false) {
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
    entry: startAddress,
    updateMs: 100,
    yieldMs: 0,
    gimpSignal: false,
    expansionBankHi: false,
    matrixMode,
    protectOnReset: false,
    rtcEnabled: false,
    sdEnabled: true,
    sdHighCapacity: true,
    sdImagePath: imagePath,
  };
}

function loadRuntime(
  bytes: Uint8Array,
  imagePath: string,
  startAddress = APP_START,
  matrixMode = false,
): { runtime: Runtime; platformRuntime: PlatformRuntime } {
  const { createTec1gRuntime } = requireFromDebug80('out/platforms/tec1g/runtime.js') as {
    createTec1gRuntime: Function;
  };
  const { createTec1gMemoryHooks } = requireFromDebug80(
    'out/platforms/tec1g/tec1g-memory.js',
  ) as { createTec1gMemoryHooks: Function };
  const { createZ80Runtime } = requireFromDebug80('out/z80/runtime.js') as {
    createZ80Runtime: Function;
  };

  const config = makeConfig(imagePath, startAddress, matrixMode);
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

  tec1gRuntime.ioHandlers.write?.(SYS_CTRL, SHADOW_OFF);
  runtime.hardware.memory.set(runtime.hardware.memory.subarray(0xc000, 0xc100), 0x0000);
  runtime.hardware.forceMemWrite?.(MCB, MCB_SD_CARD);
  runtime.hardware.forceMemWrite?.(MON3_SYS_MODE, SHADOW_OFF);
  runtime.cpu.sp = 0x7ff0;
  runtime.cpu.pc = startAddress;
  return { runtime, platformRuntime: tec1gRuntime };
}

function runUntil(runtime: Runtime, platformRuntime: PlatformRuntime, doneAddr: number): number {
  const maxInstructions = 80_000_000;
  for (let i = 0; i < maxInstructions; i += 1) {
    if ((runtime.cpu.pc & 0xffff) === doneAddr) {
      return i;
    }
    const result = runtime.step();
    platformRuntime.recordCycles(result.cycles ?? 0);
  }
  throw new Error(`session did not reach done at 0x${doneAddr.toString(16)}; pc=0x${runtime.cpu.pc.toString(16)}`);
}

function stepRuntime(runtime: Runtime, platformRuntime: PlatformRuntime): void {
  const result = runtime.step();
  platformRuntime.recordCycles(result.cycles ?? 0);
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

function tapMatrixKey(
  platformRuntime: PlatformRuntime,
  runtime: Runtime,
  row: number,
  col: number,
  settleInstructions = 20000,
  releaseInstructions = 20000,
): void {
  if (!platformRuntime.applyMatrixKey) {
    throw new Error('Debug80 runtime does not expose matrix key injection');
  }
  platformRuntime.applyMatrixKey(row, col, true);
  runInstructions(runtime, platformRuntime, settleInstructions);
  platformRuntime.applyMatrixKey(row, col, false);
  runInstructions(runtime, platformRuntime, releaseInstructions);
}

function tapMatrixCombo(
  platformRuntime: PlatformRuntime,
  runtime: Runtime,
  modifier: { row: number; col: number },
  key: { row: number; col: number },
  settleInstructions = 20000,
  releaseInstructions = 20000,
): void {
  if (!platformRuntime.applyMatrixKey) {
    throw new Error('Debug80 runtime does not expose matrix key injection');
  }
  platformRuntime.applyMatrixKey(modifier.row, modifier.col, true);
  platformRuntime.applyMatrixKey(key.row, key.col, true);
  runInstructions(runtime, platformRuntime, settleInstructions);
  platformRuntime.applyMatrixKey(key.row, key.col, false);
  platformRuntime.applyMatrixKey(modifier.row, modifier.col, false);
  runInstructions(runtime, platformRuntime, releaseInstructions);
}

function pressMatrixCombo(platformRuntime: PlatformRuntime, modifier: { row: number; col: number }, key: { row: number; col: number }): void {
  if (!platformRuntime.applyMatrixKey) {
    throw new Error('Debug80 runtime does not expose matrix key injection');
  }
  platformRuntime.applyMatrixKey(modifier.row, modifier.col, true);
  platformRuntime.applyMatrixKey(key.row, key.col, true);
}

function releaseMatrixCombo(
  platformRuntime: PlatformRuntime,
  runtime: Runtime,
  modifier: { row: number; col: number },
  key: { row: number; col: number },
  releaseInstructions = 20000,
): void {
  if (!platformRuntime.applyMatrixKey) {
    throw new Error('Debug80 runtime does not expose matrix key injection');
  }
  platformRuntime.applyMatrixKey(key.row, key.col, false);
  platformRuntime.applyMatrixKey(modifier.row, modifier.col, false);
  runInstructions(runtime, platformRuntime, releaseInstructions);
}

function readTm8File(imagePath: string, tm8Path: string): Buffer {
  const { readFileFromVolumeImage } = require(resolve(TECM8_ROOT, 'tools/tm8/format.ts'));
  const manifest = JSON.parse(readFileSync(manifestPath(imagePath), 'utf8'));
  const image = readFileSync(imagePath);
  const volume = image.subarray(manifest.volume_start_byte_offset, manifest.volume_start_byte_offset + TM8_VOLUME_BYTES);
  return readFileFromVolumeImage(Buffer.from(volume), tm8Path) as Buffer;
}

function readSourceRecord(records: Buffer, record: number): string {
  const start = record * 32;
  const length = records[start] & 0x1f;
  return records.subarray(start + 1, start + 1 + length).toString('ascii');
}

function readRuntimeSourceRecord(memory: Uint8Array, address: number, record: number): string {
  const start = address + record * 32;
  const length = memory[start] & 0x1f;
  return Buffer.from(memory.subarray(start + 1, start + 1 + length)).toString('ascii');
}

function assertRuntimeSourceRecord(
  runtime: Runtime,
  pageBufferAddr: number,
  record: number,
  expected: string,
  label: string,
): void {
  const actual = readRuntimeSourceRecord(runtime.hardware.memory, pageBufferAddr, record);
  if (actual !== expected) {
    throw new Error(`${label} record ${record} "${actual}", expected "${expected}"`);
  }
}

function assertRuntimeCString(
  runtime: Runtime,
  address: number,
  expected: string,
  label: string,
): void {
  const actual = readCString(runtime.hardware.memory, address);
  if (actual !== expected) {
    throw new Error(`${label} "${actual}", expected "${expected}"`);
  }
}

function glcdBytes(platformRuntime: PlatformRuntime): number[] {
  return Array.from(platformRuntime.state.display?.glcdCtrl?.glcd ?? []);
}

function glcdDisplayRowHasPixels(glcd: number[], displayRow: number): boolean {
  const rowTop = 2 + displayRow * 6;
  for (let y = rowTop; y < rowTop + 6; y += 1) {
    const start = y * 16;
    const end = start + 16;
    if (glcd.slice(start, end).some((value) => value !== 0)) {
      return true;
    }
  }
  return false;
}

function assertGlcdDisplayRows(
  platformRuntime: PlatformRuntime,
  rows: number[],
  label: string,
): void {
  const glcd = glcdBytes(platformRuntime);
  for (const row of rows) {
    if (!glcdDisplayRowHasPixels(glcd, row)) {
      throw new Error(`${label} did not render GLCD display row ${row}`);
    }
  }
}

function writeGlcdCapture(glcd: number[]): void {
  mkdirSync(dirname(GLCD_CAPTURE_PATH), { recursive: true });
  const pixels = Buffer.alloc(128 * 64);
  for (let y = 0; y < 64; y += 1) {
    for (let byteX = 0; byteX < 16; byteX += 1) {
      const value = glcd[y * 16 + byteX] ?? 0;
      for (let bit = 0; bit < 8; bit += 1) {
        const x = byteX * 8 + bit;
        pixels[y * 128 + x] = (value & (0x80 >> bit)) !== 0 ? 0 : 255;
      }
    }
  }
  writeFileSync(GLCD_CAPTURE_PATH, Buffer.concat([Buffer.from('P5\n128 64\n255\n', 'ascii'), pixels]));
}

async function main(): Promise<void> {
  if (process.argv.includes('--prepare-only')) {
    if (process.argv.includes('--block-fixture')) {
      ensureBlockSmokeSessionImage(IMAGE_PATH);
    } else {
      ensureSessionImage(IMAGE_PATH);
    }
    const summary = {
      result: 'ok',
      preparedOnly: true,
      blockFixture: process.argv.includes('--block-fixture'),
      image: IMAGE_PATH,
    };
    writeFileSync(SUMMARY_PATH, `${JSON.stringify(summary, null, 2)}\n`);
    console.log(JSON.stringify(summary, null, 2));
    return;
  }

  const tempSessionDir = mkdtempSync(resolve(tmpdir(), 'tecm8-editor-session-'));
  const sessionImagePath = resolve(tempSessionDir, 'editor-session-fat32.img');

  try {
    if (process.argv.includes('--block-smoke')) {
      ensureBlockSmokeSessionImage(sessionImagePath);
    } else {
      ensureSessionImage(sessionImagePath);
    }

    const sourceFile = process.argv.includes('--live-smoke') || process.argv.includes('--block-smoke')
      ? SOURCE_FILE
      : SCRIPT_SOURCE_FILE;
    const { bytes, symbols } = await compileMain(sourceFile);
    if (process.argv.includes('--block-smoke')) {
    const liveLoopAddr = symbolAddress(symbols, 'EditorLiveLoop');
    const cursorRowAddr = symbolAddress(symbols, 'EditorCursorRow');
    const dirtyAddr = symbolAddress(symbols, 'EditorNavDirty');
    const pageBufferAddr = symbolAddress(symbols, 'EditorNavPageBuffer');
    const selectionActiveAddr = symbolAddress(symbols, 'EditorBlockSelectionActive');
    const selectionAnchorLoAddr = symbolAddress(symbols, 'EditorBlockSelectionAnchorLo');
    const selectionActiveLoAddr = symbolAddress(symbols, 'EditorBlockSelectionActiveLo');
    const pendingBlockModeAddr = symbolAddress(symbols, 'EditorPendingBlockMode');
    const pendingCharAddr = symbolAddress(symbols, 'EditorPendingChar');
    const pendingModifierAddr = symbolAddress(symbols, 'EditorPendingModifier');
    const mainDoneAddr = symbolAddress(symbols, 'MainDone');
    const mainErrorAddr = symbolAddress(symbols, 'MainErrorMarker');
    const translatedKeyAddr = symbolAddress(symbols, 'BiosInputTranslatedKey');
    const rawTranslatedKeyAddr = symbolAddress(symbols, 'BiosInputTranslatedRawKey');
    const rawPrimaryAddr = symbolAddress(symbols, 'BiosInputRawPrimary');
    const rawSecondaryAddr = symbolAddress(symbols, 'BiosInputRawSecondary');
    const modifierBitsAddr = symbolAddress(symbols, 'BiosInputModifierBits');
    const { runtime, platformRuntime } = loadRuntime(bytes, sessionImagePath, APP_START, true);
    platformRuntime.setMatrixMode?.(true);
    const bootInstructions = runUntilPc(runtime, platformRuntime, liveLoopAddr, 60_000_000);

    tapMatrixCombo(platformRuntime, runtime, { row: 0, col: 0 }, { row: 0, col: 4 }, 200_000, 200_000); // Shift+Down
    stepThenRunUntilPc(runtime, platformRuntime, liveLoopAddr, 20_000_000);
    const selectionActiveAfterShiftDown = readRuntimeByte(runtime, selectionActiveAddr);
    const selectionAnchorAfterShiftDown = readRuntimeByte(runtime, selectionAnchorLoAddr);
    const selectionEndAfterShiftDown = readRuntimeByte(runtime, selectionActiveLoAddr);
    if (
      selectionActiveAfterShiftDown !== 1 ||
      selectionAnchorAfterShiftDown !== 0 ||
      selectionEndAfterShiftDown !== 1
    ) {
      throw new Error(
        `block smoke selection active=${selectionActiveAfterShiftDown} anchor=${selectionAnchorAfterShiftDown} activeLo=${selectionEndAfterShiftDown}, expected 0..1`,
      );
    }

    tapMatrixCombo(platformRuntime, runtime, { row: 0, col: 1 }, { row: 4, col: 6 }, 200_000, 200_000); // Ctrl+C
    stepRuntime(runtime, platformRuntime);
    const afterCopyPc = runUntilAnyPc(runtime, platformRuntime, [liveLoopAddr, mainDoneAddr], 20_000_000);
    if (afterCopyPc === mainDoneAddr) {
      throw new Error(`block smoke Ctrl-C exited editor error=0x${readRuntimeByte(runtime, mainErrorAddr).toString(16)}`);
    }
    const copyModifierBits = runtime.hardware.memory[modifierBitsAddr];
    const copyTranslatedKey = runtime.hardware.memory[translatedKeyAddr];
    const copyRawTranslatedKey = runtime.hardware.memory[rawTranslatedKeyAddr];
    const copyRawPrimary = runtime.hardware.memory[rawPrimaryAddr];
    const copyRawSecondary = runtime.hardware.memory[rawSecondaryAddr];
    const pendingAfterCopy = readRuntimeByte(runtime, pendingBlockModeAddr);
    const selectionAfterCopy = readRuntimeByte(runtime, selectionActiveAddr);
    const selectionAnchorAfterCopy = readRuntimeByte(runtime, selectionAnchorLoAddr);
    const selectionEndAfterCopy = readRuntimeByte(runtime, selectionActiveLoAddr);
    const editorPendingCharAfterCopy = readRuntimeByte(runtime, pendingCharAddr);
    const editorPendingModifierAfterCopy = readRuntimeByte(runtime, pendingModifierAddr);
    if (copyModifierBits !== 0x02 || copyTranslatedKey !== 0x03 || copyRawTranslatedKey !== 0x03 || copyRawPrimary === 0x03) {
      throw new Error(
        `block smoke Ctrl-C modifier=0x${copyModifierBits.toString(16)} translated=0x${copyTranslatedKey.toString(16)} rawTranslated=0x${copyRawTranslatedKey.toString(16)} rawSecondary=0x${copyRawSecondary.toString(16)} rawPrimary=0x${copyRawPrimary.toString(16)}, expected ctrl-modified control-C with non-arrow raw primary`,
      );
    }
    if (
      pendingAfterCopy !== 1 ||
      selectionAfterCopy !== 0
    ) {
      throw new Error(
        `block smoke Ctrl-C pending=${pendingAfterCopy} selection=${selectionAfterCopy} range=${selectionAnchorAfterCopy}..${selectionEndAfterCopy} editorPending=0x${editorPendingCharAfterCopy.toString(16)}/0x${editorPendingModifierAfterCopy.toString(16)} modifier=0x${copyModifierBits.toString(16)} translated=0x${copyTranslatedKey.toString(16)} rawTranslated=0x${copyRawTranslatedKey.toString(16)} rawSecondary=0x${copyRawSecondary.toString(16)} rawPrimary=0x${copyRawPrimary.toString(16)}, expected pending copy`,
      );
    }

    for (let i = 0; i < 6 && runtime.hardware.memory[cursorRowAddr] < 4; i += 1) {
      tapMatrixKey(platformRuntime, runtime, 0, 4, 200_000, 200_000); // ArrowDown
      stepThenRunUntilPc(runtime, platformRuntime, liveLoopAddr, 20_000_000);
    }
    if (runtime.hardware.memory[cursorRowAddr] !== 4) {
      throw new Error(`block smoke cursor row before paste ${runtime.hardware.memory[cursorRowAddr]}, expected 4`);
    }

    tapMatrixCombo(platformRuntime, runtime, { row: 0, col: 1 }, { row: 7, col: 1 }, 200_000, 200_000); // Ctrl+V
    stepThenRunUntilPc(runtime, platformRuntime, liveLoopAddr, 20_000_000);
    const pasteModifierBits = runtime.hardware.memory[modifierBitsAddr];
    const pasteTranslatedKey = runtime.hardware.memory[translatedKeyAddr];
    const pendingAfterPaste = readRuntimeByte(runtime, pendingBlockModeAddr);
    const selectionAfterPaste = readRuntimeByte(runtime, selectionActiveAddr);
    const selectionAnchorAfterPaste = readRuntimeByte(runtime, selectionAnchorLoAddr);
    const selectionEndAfterPaste = readRuntimeByte(runtime, selectionActiveLoAddr);
    if (pasteModifierBits !== 0x02 || pasteTranslatedKey !== 0x16) {
      throw new Error(
        `block smoke Ctrl-V modifier=0x${pasteModifierBits.toString(16)} translated=0x${pasteTranslatedKey.toString(16)}, expected ctrl-modified V`,
      );
    }
    if (
      pendingAfterPaste !== 0 ||
      selectionAfterPaste !== 1 ||
      selectionAnchorAfterPaste !== 4 ||
      selectionEndAfterPaste !== 5
    ) {
      throw new Error(
        `block smoke Ctrl-V pending=${pendingAfterPaste} selection=${selectionAfterPaste} anchor=${selectionAnchorAfterPaste} activeLo=${selectionEndAfterPaste}, expected pasted selection 4..5`,
      );
    }
    assertRuntimeSourceRecord(runtime, pageBufferAddr, 0, 'B0 LINE 00', 'block smoke row 0 after copy insert');
    assertRuntimeSourceRecord(runtime, pageBufferAddr, 1, 'B0 LINE 01', 'block smoke row 1 after copy insert');
    assertRuntimeSourceRecord(runtime, pageBufferAddr, 4, 'B0 LINE 00', 'block smoke row 4 after copy insert');
    assertRuntimeSourceRecord(runtime, pageBufferAddr, 5, 'B0 LINE 04', 'block smoke row 5 after copy insert');
    assertRuntimeSourceRecord(runtime, pageBufferAddr, 6, 'B0 LINE 05', 'block smoke row 6 after copy insert');

    tapMatrixCombo(platformRuntime, runtime, { row: 0, col: 1 }, { row: 6, col: 6 }, 200_000, 200_000); // Ctrl+S
    stepThenRunUntilPc(runtime, platformRuntime, liveLoopAddr, 120_000_000);
    if (runtime.hardware.memory[dirtyAddr] !== 0) {
      throw new Error(`block smoke dirty after save ${runtime.hardware.memory[dirtyAddr]}, expected 0`);
    }
    const savedSource = readTm8File(sessionImagePath, '/src/main.asm');
    const savedRows = [0, 1, 4, 5, 6].map((row) => readSourceRecord(savedSource, row));
    const expectedRows = ['B0 LINE 00', 'B0 LINE 01', 'B0 LINE 00', 'B0 LINE 04', 'B0 LINE 05'];
    if (JSON.stringify(savedRows) !== JSON.stringify(expectedRows)) {
      throw new Error(`block smoke saved rows ${JSON.stringify(savedRows)}, expected ${JSON.stringify(expectedRows)}`);
    }

    const summary = {
      result: 'ok',
      blockSmoke: true,
      manualImage: IMAGE_PATH,
      temporaryImage: true,
      temporaryImageRetained: false,
      bootInstructions,
      copyModifierBits,
      copyTranslatedKey,
      pasteModifierBits,
      pasteTranslatedKey,
      savedRows,
    };
    writeFileSync(SUMMARY_PATH, `${JSON.stringify(summary, null, 2)}\n`);
    console.log(JSON.stringify(summary, null, 2));
    return;
  }
    if (process.argv.includes('--live-smoke')) {
    const liveLoopAddr = symbolAddress(symbols, 'EditorLiveLoop');
    const doneAddr = symbolAddress(symbols, 'MainDone');
    const cursorRowAddr = symbolAddress(symbols, 'EditorCursorRow');
    const cursorColAddr = symbolAddress(symbols, 'EditorCursorCol');
    const dirtyAddr = symbolAddress(symbols, 'EditorNavDirty');
    const currentPageAddr = symbolAddress(symbols, 'EditorNavCurrentPage');
    const pageBufferAddr = symbolAddress(symbols, 'EditorNavPageBuffer');
    const rowText0Addr = symbolAddress(symbols, 'EditorRowText0');
    const rowText9Addr = symbolAddress(symbols, 'EditorRowText9');
    const promptActiveAddr = symbolAddress(symbols, 'EditorPromptActive');
    const promptResultAddr = symbolAddress(symbols, 'EditorPromptResult');
    const promptActionAddr = symbolAddress(symbols, 'EditorPromptAction');
    const pendingCharAddr = symbolAddress(symbols, 'EditorPendingChar');
    const pendingModifierAddr = symbolAddress(symbols, 'EditorPendingModifier');
    const nextPageValidAddr = symbolAddress(symbols, 'EditorNavNextPageValid');
    const nextPageSyntheticAddr = symbolAddress(symbols, 'EditorNavNextPageSynthetic');
    const dirtySectorsAddr = symbolAddress(symbols, 'EditorNavDirtySectors');
    const quitRequestedAddr = symbolAddress(symbols, 'EditorQuitRequested');
    const modifierBitsAddr = symbolAddress(symbols, 'BiosInputModifierBits');
    const rawPrimaryAddr = symbolAddress(symbols, 'BiosInputRawPrimary');
    const rawSecondaryAddr = symbolAddress(symbols, 'BiosInputRawSecondary');
    const translatedKeyAddr = symbolAddress(symbols, 'BiosInputTranslatedKey');
    const { runtime, platformRuntime } = loadRuntime(bytes, sessionImagePath, APP_START, true);
    platformRuntime.setMatrixMode?.(true);
    const tapCursorKeyAndWait = (row: number, col: number, label: string): void => {
      if (!platformRuntime.applyMatrixKey) {
        throw new Error('Debug80 runtime does not expose matrix key injection');
      }
      const beforePage = runtime.hardware.memory[currentPageAddr];
      const beforeRow = runtime.hardware.memory[cursorRowAddr];
      for (let attempt = 0; attempt < 5; attempt += 1) {
        platformRuntime.applyMatrixKey(row, col, false);
        runInstructions(runtime, platformRuntime, 200_000);
        platformRuntime.applyMatrixKey(row, col, true);
        let changed = false;
        for (let step = 0; step < 20_000; step += 1) {
          runInstructions(runtime, platformRuntime, 1_000);
          if (runtime.hardware.memory[currentPageAddr] !== beforePage || runtime.hardware.memory[cursorRowAddr] !== beforeRow) {
            changed = true;
            break;
          }
        }
        platformRuntime.applyMatrixKey(row, col, false);
        runUntilPc(runtime, platformRuntime, liveLoopAddr, 20_000_000);
        if (changed) {
          return;
        }
      }
      throw new Error(
        `live editor ${label} did not move cursor from page=${beforePage} row=${beforeRow}`,
      );
    };
    const bootInstructions = runUntilPc(runtime, platformRuntime, liveLoopAddr, 60_000_000);
    tapMatrixKey(platformRuntime, runtime, 0, 4); // ArrowDown: raw key 04h
    runUntilPc(runtime, platformRuntime, liveLoopAddr, 20_000_000);
    tapMatrixKey(platformRuntime, runtime, 0, 3); // ArrowUp: raw key 03h
    runUntilPc(runtime, platformRuntime, liveLoopAddr, 20_000_000);
    tapMatrixKey(platformRuntime, runtime, 0, 4); // ArrowDown: raw key 04h
    runUntilPc(runtime, platformRuntime, liveLoopAddr, 20_000_000);
    tapMatrixKey(platformRuntime, runtime, 0, 6); // ArrowRight: raw key 06h
    runUntilPc(runtime, platformRuntime, liveLoopAddr, 20_000_000);
    tapMatrixCombo(platformRuntime, runtime, { row: 0, col: 1 }, { row: 0, col: 4 }); // Ctrl+ArrowDown
    runUntilPc(runtime, platformRuntime, liveLoopAddr, 20_000_000);
    const pageAfterCtrlDown = runtime.hardware.memory[currentPageAddr];
    const rowAfterCtrlDown = runtime.hardware.memory[cursorRowAddr];
    if (pageAfterCtrlDown !== 1 || rowAfterCtrlDown !== 0) {
      throw new Error(
        `live editor after Ctrl+ArrowDown page=${pageAfterCtrlDown} row=${rowAfterCtrlDown}, expected page=1 row=0`,
      );
    }
    assertRuntimeSourceRecord(runtime, pageBufferAddr, 0, 'R1 LINE 00', 'after Ctrl+ArrowDown');
    assertRuntimeSourceRecord(runtime, pageBufferAddr, 9, 'R1 LINE 09', 'after Ctrl+ArrowDown');
    assertRuntimeCString(runtime, rowText0Addr, 'R1 LINE 00', 'rendered row 0 after Ctrl+ArrowDown');
    assertRuntimeCString(runtime, rowText9Addr, 'R1 LINE 09', 'rendered row 9 after Ctrl+ArrowDown');
    assertGlcdDisplayRows(platformRuntime, [0, 1, 9], 'after Ctrl+ArrowDown');
    tapMatrixCombo(platformRuntime, runtime, { row: 0, col: 1 }, { row: 0, col: 4 }); // Ctrl+ArrowDown at EOF
    runUntilPc(runtime, platformRuntime, liveLoopAddr, 20_000_000);
    const pageAfterSecondCtrlDown = runtime.hardware.memory[currentPageAddr];
    if (pageAfterSecondCtrlDown !== 1) {
      throw new Error(`live editor after second Ctrl+ArrowDown page=${pageAfterSecondCtrlDown}, expected to remain on page 1`);
    }
    assertRuntimeSourceRecord(runtime, pageBufferAddr, 0, 'R1 LINE 00', 'after second Ctrl+ArrowDown');
    assertRuntimeCString(runtime, rowText0Addr, 'R1 LINE 00', 'rendered row 0 after second Ctrl+ArrowDown');
    assertGlcdDisplayRows(platformRuntime, [0, 1], 'after second Ctrl+ArrowDown');
    if (
      runtime.hardware.memory[nextPageValidAddr] !== 1 ||
      runtime.hardware.memory[nextPageSyntheticAddr] !== 1 ||
      runtime.hardware.memory[dirtySectorsAddr] !== 0
    ) {
      throw new Error(
        `live editor second Ctrl+ArrowDown synthetic state valid=${runtime.hardware.memory[nextPageValidAddr]} synthetic=${runtime.hardware.memory[nextPageSyntheticAddr]} dirtySectors=0x${runtime.hardware.memory[dirtySectorsAddr].toString(16)}, expected valid synthetic clean EOF page`,
      );
    }
    tapMatrixCombo(platformRuntime, runtime, { row: 0, col: 1 }, { row: 0, col: 3 }); // Ctrl+ArrowUp
    runUntilPc(runtime, platformRuntime, liveLoopAddr, 20_000_000);
    const pageAfterCtrlUp = runtime.hardware.memory[currentPageAddr];
    if (pageAfterCtrlUp !== 0) {
      throw new Error(`live editor page after Ctrl+ArrowUp ${pageAfterCtrlUp}, expected 0`);
    }
    assertRuntimeSourceRecord(runtime, pageBufferAddr, 0, 'R0 LINE 00', 'after Ctrl+ArrowUp');
    assertRuntimeSourceRecord(runtime, pageBufferAddr, 9, 'R0 LINE 09', 'after Ctrl+ArrowUp');
    assertRuntimeCString(runtime, rowText0Addr, 'R0 LINE 00', 'rendered row 0 after Ctrl+ArrowUp');
    assertRuntimeCString(runtime, rowText9Addr, 'R0 LINE 09', 'rendered row 9 after Ctrl+ArrowUp');
    assertGlcdDisplayRows(platformRuntime, [0, 1, 9], 'after Ctrl+ArrowUp');
    for (let move = 0; move < 16; move += 1) {
      tapCursorKeyAndWait(0, 4, `plain ArrowDown ${move + 1}`);
    }
    const pageAfterPlainDownCross = runtime.hardware.memory[currentPageAddr];
    const rowAfterPlainDownCross = runtime.hardware.memory[cursorRowAddr];
    if (pageAfterPlainDownCross !== 1 || rowAfterPlainDownCross !== 0) {
      throw new Error(
        `live editor after plain ArrowDown cross page=${pageAfterPlainDownCross} row=${rowAfterPlainDownCross}, expected page=1 row=0`,
      );
    }
    assertRuntimeSourceRecord(runtime, pageBufferAddr, 0, 'R1 LINE 00', 'after plain ArrowDown cross');
    assertRuntimeCString(runtime, rowText0Addr, 'R1 LINE 00', 'rendered row 0 after plain ArrowDown cross');
    tapCursorKeyAndWait(0, 3, 'plain ArrowUp cross');
    const pageAfterPlainUpCross = runtime.hardware.memory[currentPageAddr];
    const rowAfterPlainUpCross = runtime.hardware.memory[cursorRowAddr];
    if (pageAfterPlainUpCross !== 0 || rowAfterPlainUpCross !== 15) {
      throw new Error(
        `live editor after plain ArrowUp cross page=${pageAfterPlainUpCross} row=${rowAfterPlainUpCross}, expected page=0 row=15`,
      );
    }
    assertRuntimeSourceRecord(runtime, pageBufferAddr, 0, 'R0 LINE 00', 'after plain ArrowUp cross');
    assertRuntimeCString(runtime, rowText0Addr, 'R0 LINE 06', 'rendered row 0 after plain ArrowUp cross');
    tapCursorKeyAndWait(0, 4, 'second plain ArrowDown cross');
    const pageAfterSecondPlainDownCross = runtime.hardware.memory[currentPageAddr];
    const rowAfterSecondPlainDownCross = runtime.hardware.memory[cursorRowAddr];
    if (pageAfterSecondPlainDownCross !== 1 || rowAfterSecondPlainDownCross !== 0) {
      throw new Error(
        `live editor after second plain ArrowDown cross page=${pageAfterSecondPlainDownCross} row=${rowAfterSecondPlainDownCross}, expected page=1 row=0`,
      );
    }
    assertRuntimeSourceRecord(runtime, pageBufferAddr, 0, 'R1 LINE 00', 'after second plain ArrowDown cross');
    tapCursorKeyAndWait(0, 3, 'second plain ArrowUp cross');
    for (let move = 0; move < 15; move += 1) {
      tapCursorKeyAndWait(0, 3, `plain ArrowUp reset ${move + 1}`);
    }
    if (runtime.hardware.memory[currentPageAddr] !== 0 || runtime.hardware.memory[cursorRowAddr] !== 0) {
      throw new Error(
        `live editor after plain ArrowUp reset page=${runtime.hardware.memory[currentPageAddr]} row=${runtime.hardware.memory[cursorRowAddr]}, expected page=0 row=0`,
      );
    }
    tapMatrixCombo(platformRuntime, runtime, { row: 0, col: 1 }, { row: 0, col: 6 }); // Ctrl+ArrowRight
    runUntilPc(runtime, platformRuntime, liveLoopAddr, 20_000_000);
    const ctrlArrowModifierBits = runtime.hardware.memory[modifierBitsAddr];
    const ctrlArrowRawPrimary = runtime.hardware.memory[rawPrimaryAddr];
    const ctrlArrowRawSecondary = runtime.hardware.memory[rawSecondaryAddr];
    const ctrlArrowTranslatedKey = runtime.hardware.memory[translatedKeyAddr];
    if (
      ctrlArrowModifierBits !== 0x02 ||
      ctrlArrowRawPrimary !== 0x06 ||
      ctrlArrowRawSecondary !== 0x01 ||
      ctrlArrowTranslatedKey !== 0x06
    ) {
      throw new Error(
        `live editor ctrl event modifier=0x${ctrlArrowModifierBits.toString(16)} raw=${ctrlArrowRawSecondary.toString(16)}/${ctrlArrowRawPrimary.toString(16)} translated=0x${ctrlArrowTranslatedKey.toString(16)}`,
      );
    }
    tapMatrixKey(platformRuntime, runtime, 0, 7); // CapsLock toggles caps state, no editor action
    runUntilPc(runtime, platformRuntime, liveLoopAddr, 20_000_000);
    tapMatrixKey(platformRuntime, runtime, 0, 4); // ArrowDown with caps state set
    runUntilPc(runtime, platformRuntime, liveLoopAddr, 20_000_000);
    const cursorRow = readRuntimeByte(runtime, cursorRowAddr);
    const cursorCol = readRuntimeByte(runtime, cursorColAddr);
    const modifierBits = runtime.hardware.memory[modifierBitsAddr];
    const rawPrimary = runtime.hardware.memory[rawPrimaryAddr];
    const rawSecondary = runtime.hardware.memory[rawSecondaryAddr];
    const translatedKey = runtime.hardware.memory[translatedKeyAddr];
    if (cursorRow !== 1 || cursorCol !== 1) {
      throw new Error(`live editor cursor row=${cursorRow} col=${cursorCol}, expected row=1 col=1`);
    }
    if (modifierBits !== 0x10 || rawPrimary !== 0x04 || rawSecondary !== 0xff || translatedKey !== 0x04) {
      throw new Error(
        `live editor key event modifier=0x${modifierBits.toString(16)} raw=${rawSecondary.toString(16)}/${rawPrimary.toString(16)} translated=0x${translatedKey.toString(16)}`,
      );
    }
    tapMatrixKey(platformRuntime, runtime, 0, 7); // CapsLock toggles caps state back off before command chords
    runUntilPc(runtime, platformRuntime, liveLoopAddr, 20_000_000);
    tapMatrixKey(platformRuntime, runtime, 7, 5); // z
    stepThenRunUntilPc(runtime, platformRuntime, liveLoopAddr, 20_000_000);
    const dirtyAfterEdit = runtime.hardware.memory[dirtyAddr];
    if (dirtyAfterEdit !== 1) {
      throw new Error(`live editor dirty after z ${dirtyAfterEdit}, expected 1`);
    }
    tapMatrixCombo(platformRuntime, runtime, { row: 0, col: 1 }, { row: 0, col: 4 }, 200_000, 200_000); // dirty Ctrl+ArrowDown within RAM window
    stepThenRunUntilPc(runtime, platformRuntime, liveLoopAddr, 20_000_000);
    const pageAfterDirtyPageDown = readRuntimeByte(runtime, currentPageAddr);
    const dirtyAfterDirtyPageDown = runtime.hardware.memory[dirtyAddr];
    if (pageAfterDirtyPageDown !== 1 || dirtyAfterDirtyPageDown !== 1) {
      throw new Error(
        `live editor dirty Ctrl+ArrowDown page=${pageAfterDirtyPageDown} dirty=${dirtyAfterDirtyPageDown}, expected page=1 dirty=1`,
      );
    }
    assertRuntimeSourceRecord(runtime, pageBufferAddr, 0, 'R1 LINE 00', 'after dirty Ctrl+ArrowDown');
    assertRuntimeSourceRecord(runtime, pageBufferAddr, 9, 'R1 LINE 09', 'after dirty Ctrl+ArrowDown');
    assertRuntimeCString(runtime, rowText0Addr, 'R1 LINE 00', 'rendered row 0 after dirty Ctrl+ArrowDown');
    assertRuntimeCString(runtime, rowText9Addr, 'R1 LINE 09', 'rendered row 9 after dirty Ctrl+ArrowDown');
    assertGlcdDisplayRows(platformRuntime, [0, 1, 9], 'after dirty Ctrl+ArrowDown');
    tapMatrixCombo(platformRuntime, runtime, { row: 0, col: 1 }, { row: 0, col: 3 }, 200_000, 200_000); // dirty Ctrl+ArrowUp back to edited page
    stepThenRunUntilPc(runtime, platformRuntime, liveLoopAddr, 60_000_000);
    const pageAfterDirtyPageUp = runtime.hardware.memory[currentPageAddr];
    const dirtyAfterDirtyPageUp = runtime.hardware.memory[dirtyAddr];
    if (pageAfterDirtyPageUp !== 0 || dirtyAfterDirtyPageUp !== 1) {
      throw new Error(
        `live editor dirty Ctrl+ArrowUp page=${pageAfterDirtyPageUp} dirty=${dirtyAfterDirtyPageUp}, expected page=0 dirty=1`,
      );
    }
    assertRuntimeSourceRecord(runtime, pageBufferAddr, 0, 'R0 LINE 00', 'after dirty Ctrl+ArrowUp');
    assertRuntimeSourceRecord(runtime, pageBufferAddr, 9, 'R0 LINE 09', 'after dirty Ctrl+ArrowUp');
    assertRuntimeCString(runtime, rowText0Addr, 'R0 LINE 00', 'rendered row 0 after dirty Ctrl+ArrowUp');
    assertRuntimeCString(runtime, rowText9Addr, 'R0 LINE 09', 'rendered row 9 after dirty Ctrl+ArrowUp');
    assertGlcdDisplayRows(platformRuntime, [0, 1, 9], 'after dirty Ctrl+ArrowUp');
    tapMatrixKey(platformRuntime, runtime, 1, 2); // Enter: split line
    stepThenRunUntilPc(runtime, platformRuntime, liveLoopAddr, 20_000_000);
    const cursorRowAfterEnter = readRuntimeByte(runtime, cursorRowAddr);
    const cursorColAfterEnter = readRuntimeByte(runtime, cursorColAddr);
    if (cursorRowAfterEnter !== 1 || cursorColAfterEnter !== 0) {
      const enterModifierBits = runtime.hardware.memory[modifierBitsAddr];
      const enterRawPrimary = runtime.hardware.memory[rawPrimaryAddr];
      const enterRawSecondary = runtime.hardware.memory[rawSecondaryAddr];
      const enterTranslatedKey = runtime.hardware.memory[translatedKeyAddr];
      throw new Error(
        `live editor cursor after Enter ${cursorRowAfterEnter},${cursorColAfterEnter}; expected 1,0; modifier=0x${enterModifierBits.toString(16)} raw=${enterRawSecondary.toString(16)}/${enterRawPrimary.toString(16)} translated=0x${enterTranslatedKey.toString(16)}`,
      );
    }
    assertRuntimeSourceRecord(runtime, pageBufferAddr, 0, '', 'after Enter split');
    assertRuntimeSourceRecord(runtime, pageBufferAddr, 1, 'R0 LINE 00', 'after Enter split');
    assertRuntimeSourceRecord(runtime, pageBufferAddr, 2, 'Rz0 LINE 01', 'after Enter split');
    assertRuntimeSourceRecord(runtime, pageBufferAddr, 15, 'R0 LINE 14', 'after Enter split');
    tapMatrixCombo(platformRuntime, runtime, { row: 0, col: 1 }, { row: 6, col: 6 }, 200_000, 200_000); // Ctrl+S
    stepThenRunUntilPc(runtime, platformRuntime, liveLoopAddr, 120_000_000);
    const dirtyAfterSave = runtime.hardware.memory[dirtyAddr];
    const saveTranslatedKey = runtime.hardware.memory[translatedKeyAddr];
    const saveModifierBits = runtime.hardware.memory[modifierBitsAddr];
    if (dirtyAfterSave !== 0 || saveTranslatedKey !== 0x13 || (saveModifierBits & 0x02) === 0) {
      throw new Error(
        `live editor Ctrl-S save dirty=${dirtyAfterSave} modifier=0x${saveModifierBits.toString(16)} translated=0x${saveTranslatedKey.toString(16)}, expected dirty=0 ctrl-save`,
      );
    }
    tapMatrixCombo(platformRuntime, runtime, { row: 0, col: 1 }, { row: 0, col: 4 }, 200_000, 200_000); // Ctrl+ArrowDown
    stepThenRunUntilPc(runtime, platformRuntime, liveLoopAddr, 60_000_000);
    const pageAfterSplitSaveDown = readRuntimeByte(runtime, currentPageAddr);
    if (pageAfterSplitSaveDown !== 1) {
      throw new Error(`live editor page after saved split Ctrl+ArrowDown ${pageAfterSplitSaveDown}, expected 1`);
    }
    tapMatrixCombo(platformRuntime, runtime, { row: 0, col: 1 }, { row: 0, col: 3 }, 200_000, 200_000); // Ctrl+ArrowUp
    stepThenRunUntilPc(runtime, platformRuntime, liveLoopAddr, 60_000_000);
    const pageAfterSplitSaveUp = runtime.hardware.memory[currentPageAddr];
    if (pageAfterSplitSaveUp !== 0) {
      throw new Error(`live editor page after saved split Ctrl+ArrowUp ${pageAfterSplitSaveUp}, expected 0`);
    }
    assertRuntimeSourceRecord(runtime, pageBufferAddr, 0, '', 'after saved split page return');
    assertRuntimeSourceRecord(runtime, pageBufferAddr, 1, 'R0 LINE 00', 'after saved split page return');
    assertRuntimeSourceRecord(runtime, pageBufferAddr, 2, 'Rz0 LINE 01', 'after saved split page return');
    tapMatrixKey(platformRuntime, runtime, 0, 4); // ArrowDown: move to split tail for join
    stepThenRunUntilPc(runtime, platformRuntime, liveLoopAddr, 20_000_000);
    tapMatrixKey(platformRuntime, runtime, 1, 0); // Backspace: join with previous line
    stepThenRunUntilPc(runtime, platformRuntime, liveLoopAddr, 20_000_000);
    const cursorRowAfterJoin = runtime.hardware.memory[cursorRowAddr];
    const cursorColAfterJoin = runtime.hardware.memory[cursorColAddr];
    if (cursorRowAfterJoin !== 0 || cursorColAfterJoin !== 0) {
      throw new Error(
        `live editor cursor after Backspace join ${cursorRowAfterJoin},${cursorColAfterJoin}; expected 0,0`,
      );
    }
    assertRuntimeSourceRecord(runtime, pageBufferAddr, 0, 'R0 LINE 00', 'after Backspace join');
    assertRuntimeSourceRecord(runtime, pageBufferAddr, 1, 'Rz0 LINE 01', 'after Backspace join');
    assertRuntimeSourceRecord(runtime, pageBufferAddr, 15, '', 'after Backspace join');
    tapMatrixCombo(platformRuntime, runtime, { row: 0, col: 1 }, { row: 6, col: 6 }, 200_000, 200_000); // save joined page
    stepThenRunUntilPc(runtime, platformRuntime, liveLoopAddr, 120_000_000);
    const dirtyAfterJoinSave = runtime.hardware.memory[dirtyAddr];
    if (dirtyAfterJoinSave !== 0) {
      throw new Error(`live editor dirty after join save ${dirtyAfterJoinSave}, expected 0`);
    }
    tapMatrixCombo(platformRuntime, runtime, { row: 0, col: 1 }, { row: 6, col: 6 }, 200_000, 200_000); // clean Ctrl+S no-op
    stepThenRunUntilPc(runtime, platformRuntime, liveLoopAddr, 20_000_000);
    const dirtyAfterCleanSave = runtime.hardware.memory[dirtyAddr];
    if (dirtyAfterCleanSave !== 0) {
      throw new Error(`live editor clean save dirty=${dirtyAfterCleanSave}, expected 0`);
    }
    tapMatrixKey(platformRuntime, runtime, 7, 5); // z after save: editor should still accept input
    stepThenRunUntilPc(runtime, platformRuntime, liveLoopAddr, 20_000_000);
    const dirtyAfterPostSaveEdit = runtime.hardware.memory[dirtyAddr];
    if (dirtyAfterPostSaveEdit !== 1) {
      const postSaveModifierBits = runtime.hardware.memory[modifierBitsAddr];
      const postSaveRawPrimary = runtime.hardware.memory[rawPrimaryAddr];
      const postSaveRawSecondary = runtime.hardware.memory[rawSecondaryAddr];
      const postSaveTranslatedKey = runtime.hardware.memory[translatedKeyAddr];
      throw new Error(
        `live editor post-save edit dirty=${dirtyAfterPostSaveEdit}, expected 1; modifier=0x${postSaveModifierBits.toString(16)} raw=${postSaveRawSecondary.toString(16)}/${postSaveRawPrimary.toString(16)} translated=0x${postSaveTranslatedKey.toString(16)}`,
      );
    }
    const promptBeforeCtrlQ = runtime.hardware.memory[promptActiveAddr];
    if (promptBeforeCtrlQ !== 0) {
      throw new Error(`live editor prompt before Ctrl-Q active=${promptBeforeCtrlQ}, expected 0`);
    }
    pressMatrixCombo(platformRuntime, { row: 0, col: 1 }, { row: 6, col: 4 }); // Ctrl+Q dirty quit prompt
    stepThenRunUntilPc(runtime, platformRuntime, liveLoopAddr, 20_000_000);
    const promptAfterCtrlQ = runtime.hardware.memory[promptActiveAddr];
    const actionAfterCtrlQ = runtime.hardware.memory[promptActionAddr];
    const pendingAfterCtrlQ = runtime.hardware.memory[pendingCharAddr];
    const pendingModifierAfterCtrlQ = runtime.hardware.memory[pendingModifierAddr];
    const ctrlQuitTranslatedKey = runtime.hardware.memory[translatedKeyAddr];
    const ctrlQuitModifierBits = runtime.hardware.memory[modifierBitsAddr];
    if (
      promptAfterCtrlQ !== 1 ||
      actionAfterCtrlQ !== 2 ||
      pendingAfterCtrlQ !== 0x11 ||
      (pendingModifierAfterCtrlQ & 0x02) === 0
    ) {
      throw new Error(
        `live editor Ctrl-Q prompt active=${promptAfterCtrlQ} action=${actionAfterCtrlQ} pending=0x${pendingAfterCtrlQ.toString(16)} pendingMod=0x${pendingModifierAfterCtrlQ.toString(16)} modifier=0x${ctrlQuitModifierBits.toString(16)} translated=0x${ctrlQuitTranslatedKey.toString(16)}, expected ctrl quit prompt`,
      );
    }
    releaseMatrixCombo(platformRuntime, runtime, { row: 0, col: 1 }, { row: 6, col: 4 }, 200_000);
    tapMatrixKey(platformRuntime, runtime, 6, 1, 200_000, 200_000); // n: cancel quit prompt
    stepThenRunUntilPc(runtime, platformRuntime, liveLoopAddr, 20_000_000);
    const promptAfterCtrlQNo = runtime.hardware.memory[promptActiveAddr];
    const ctrlQuitNoResult = runtime.hardware.memory[promptResultAddr];
    const dirtyAfterCtrlQNo = runtime.hardware.memory[dirtyAddr];
    const quitAfterCtrlQNo = runtime.hardware.memory[quitRequestedAddr];
    if (promptAfterCtrlQNo !== 0 || ctrlQuitNoResult !== 2 || dirtyAfterCtrlQNo !== 1 || quitAfterCtrlQNo !== 0) {
      throw new Error(
        `live editor Ctrl-Q cancel prompt=${promptAfterCtrlQNo} result=${ctrlQuitNoResult} dirty=${dirtyAfterCtrlQNo} quit=${quitAfterCtrlQNo}, expected prompt=0 result=2 dirty=1 quit=0`,
      );
    }
    pressMatrixCombo(platformRuntime, { row: 0, col: 1 }, { row: 7, col: 5 }); // Ctrl+Z
    stepThenRunUntilPc(runtime, platformRuntime, liveLoopAddr, 20_000_000);
    const promptAfterCtrlZ = runtime.hardware.memory[promptActiveAddr];
    const actionAfterCtrlZ = runtime.hardware.memory[promptActionAddr];
    const pendingAfterCtrlZ = runtime.hardware.memory[pendingCharAddr];
    const pendingModifierAfterCtrlZ = runtime.hardware.memory[pendingModifierAddr];
    const ctrlRestoreTranslatedKey = runtime.hardware.memory[translatedKeyAddr];
    const ctrlRestoreModifierBits = runtime.hardware.memory[modifierBitsAddr];
    if (
      promptAfterCtrlZ !== 1 ||
      actionAfterCtrlZ !== 1 ||
      pendingAfterCtrlZ !== 0x1a ||
      (pendingModifierAfterCtrlZ & 0x02) === 0
    ) {
      throw new Error(
        `live editor Ctrl-Z prompt active=${promptAfterCtrlZ} action=${actionAfterCtrlZ} pending=0x${pendingAfterCtrlZ.toString(16)} pendingMod=0x${pendingModifierAfterCtrlZ.toString(16)} modifier=0x${ctrlRestoreModifierBits.toString(16)} translated=0x${ctrlRestoreTranslatedKey.toString(16)}, expected ctrl restore prompt`,
      );
    }
    releaseMatrixCombo(platformRuntime, runtime, { row: 0, col: 1 }, { row: 7, col: 5 }, 200_000);
    tapMatrixKey(platformRuntime, runtime, 6, 1, 200_000, 200_000); // n: cancel restore prompt
    stepThenRunUntilPc(runtime, platformRuntime, liveLoopAddr, 20_000_000);
    const promptAfterCtrlZNo = runtime.hardware.memory[promptActiveAddr];
    const ctrlRestoreNoResult = runtime.hardware.memory[promptResultAddr];
    const dirtyAfterCtrlZNo = runtime.hardware.memory[dirtyAddr];
    if (promptAfterCtrlZNo !== 0 || ctrlRestoreNoResult !== 2 || dirtyAfterCtrlZNo !== 1) {
      throw new Error(
        `live editor Ctrl-Z cancel prompt=${promptAfterCtrlZNo} result=${ctrlRestoreNoResult} dirty=${dirtyAfterCtrlZNo}, expected prompt=0 result=2 dirty=1`,
      );
    }
    tapMatrixCombo(platformRuntime, runtime, { row: 0, col: 1 }, { row: 6, col: 6 }, 200_000, 200_000); // Ctrl+S save post-save edit
    stepThenRunUntilPc(runtime, platformRuntime, liveLoopAddr, 120_000_000);
    const dirtyAfterSecondSave = runtime.hardware.memory[dirtyAddr];
    const ctrlSaveTranslatedKey = runtime.hardware.memory[translatedKeyAddr];
    const ctrlSaveModifierBits = runtime.hardware.memory[modifierBitsAddr];
    if (dirtyAfterSecondSave !== 0 || ctrlSaveTranslatedKey !== 0x13 || (ctrlSaveModifierBits & 0x02) === 0) {
      throw new Error(
        `live editor Ctrl-S save dirty=${dirtyAfterSecondSave} modifier=0x${ctrlSaveModifierBits.toString(16)} translated=0x${ctrlSaveTranslatedKey.toString(16)}, expected dirty=0 ctrl-save`,
      );
    }
    tapMatrixCombo(platformRuntime, runtime, { row: 0, col: 1 }, { row: 7, col: 5 }, 200_000, 200_000); // Ctrl+Z
    stepThenRunUntilPc(runtime, platformRuntime, liveLoopAddr, 20_000_000);
    const promptAfterSecondCtrlZ = runtime.hardware.memory[promptActiveAddr];
    if (promptAfterSecondCtrlZ !== 1) {
      const secondRestoreModifierBits = runtime.hardware.memory[modifierBitsAddr];
      const restoreTranslatedKey = runtime.hardware.memory[translatedKeyAddr];
      throw new Error(
        `live editor Ctrl-Z prompt active=${promptAfterSecondCtrlZ}, expected 1; modifier=0x${secondRestoreModifierBits.toString(16)} translated=0x${restoreTranslatedKey.toString(16)}`,
      );
    }
    tapMatrixKey(platformRuntime, runtime, 6, 1, 200_000, 200_000); // n: cancel restore prompt
    stepThenRunUntilPc(runtime, platformRuntime, liveLoopAddr, 20_000_000);
    const promptAfterRestoreNo = runtime.hardware.memory[promptActiveAddr];
    const restoreNoResult = runtime.hardware.memory[promptResultAddr];
    const dirtyAfterRestoreNo = runtime.hardware.memory[dirtyAddr];
    if (promptAfterRestoreNo !== 0 || restoreNoResult !== 2 || dirtyAfterRestoreNo !== 0) {
      throw new Error(
        `live editor restore cancel prompt=${promptAfterRestoreNo} result=${restoreNoResult} dirty=${dirtyAfterRestoreNo}, expected prompt=0 result=2 dirty=0`,
      );
    }
    tapMatrixCombo(platformRuntime, runtime, { row: 0, col: 1 }, { row: 6, col: 4 }, 200_000, 200_000); // Ctrl+Q
    stepRuntime(runtime, platformRuntime);
    let afterQuitPc = runUntilAnyPc(runtime, platformRuntime, [doneAddr, liveLoopAddr], 20_000_000);
    if (afterQuitPc === liveLoopAddr && runtime.hardware.memory[quitRequestedAddr] === 1) {
      stepRuntime(runtime, platformRuntime);
      afterQuitPc = runUntilAnyPc(runtime, platformRuntime, [doneAddr, liveLoopAddr], 20_000_000);
    }
    const quitTranslatedKey = runtime.hardware.memory[translatedKeyAddr];
    if (afterQuitPc !== doneAddr) {
      const quitModifierBits = runtime.hardware.memory[modifierBitsAddr];
      const quitRawPrimary = runtime.hardware.memory[rawPrimaryAddr];
      const quitRawSecondary = runtime.hardware.memory[rawSecondaryAddr];
      throw new Error(
        `live editor Ctrl-Q returned to loop instead of exiting: modifier=0x${quitModifierBits.toString(16)} raw=${quitRawSecondary.toString(16)}/${quitRawPrimary.toString(16)} translated=0x${quitTranslatedKey.toString(16)}`,
      );
    }
    const quitModifierBits = runtime.hardware.memory[modifierBitsAddr];
    if (quitTranslatedKey !== 0x11 || (quitModifierBits & 0x02) === 0) {
      throw new Error(
        `live editor quit modifier=0x${quitModifierBits.toString(16)} translated=0x${quitTranslatedKey.toString(16)}, expected ctrl-quit`,
      );
    }
    const summary = {
      result: 'ok',
      liveSmoke: true,
      manualImage: IMAGE_PATH,
      temporaryImage: true,
      temporaryImageRetained: false,
      bootInstructions,
      cursorRow,
      cursorCol,
      pageAfterCtrlDown,
      rowAfterCtrlDown,
      pageAfterCtrlUp,
      pageAfterPlainDownCross,
      rowAfterPlainDownCross,
      pageAfterPlainUpCross,
      rowAfterPlainUpCross,
      pageAfterSecondPlainDownCross,
      rowAfterSecondPlainDownCross,
      dirtyAfterEdit,
      pageAfterDirtyPageDown,
      cursorRowAfterEnter,
      cursorColAfterEnter,
      cursorRowAfterJoin,
      cursorColAfterJoin,
      dirtyAfterSave,
      pageAfterSplitSaveDown,
      pageAfterSplitSaveUp,
      dirtyAfterCleanSave,
      dirtyAfterPostSaveEdit,
      dirtyAfterJoinSave,
      dirtyAfterSecondSave,
      promptAfterCtrlQ,
      actionAfterCtrlQ,
      pendingAfterCtrlQ,
      pendingModifierAfterCtrlQ,
      promptAfterCtrlQNo,
      dirtyAfterCtrlQNo,
      quitAfterCtrlQNo,
      promptAfterSecondCtrlZ,
      actionAfterCtrlZ,
      pendingAfterCtrlZ,
      pendingModifierAfterCtrlZ,
      promptAfterCtrlZNo,
      dirtyAfterCtrlZNo,
      promptAfterCtrlZ,
      promptAfterRestoreNo,
      dirtyAfterRestoreNo,
      saveModifierBits,
      ctrlSaveModifierBits,
      ctrlQuitModifierBits,
      ctrlRestoreModifierBits,
      modifierBits,
      rawPrimary,
      rawSecondary,
      translatedKey,
      saveTranslatedKey,
      ctrlSaveTranslatedKey,
      ctrlQuitTranslatedKey,
      ctrlRestoreTranslatedKey,
      quitTranslatedKey,
    };
    writeFileSync(SUMMARY_PATH, `${JSON.stringify(summary, null, 2)}\n`);
    console.log(JSON.stringify(summary, null, 2));
    return;
  }

  const scriptStartAddr = symbolAddress(symbols, 'ScriptStart');
  const doneAddr = symbolAddress(symbols, 'MainDone');
  const resultAddr = symbolAddress(symbols, 'MainResultMarker');
  const errorAddr = symbolAddress(symbols, 'MainErrorMarker');
  const caseAddr = symbolAddress(symbols, 'MainCaseMarker');
  const { runtime, platformRuntime } = loadRuntime(bytes, sessionImagePath, scriptStartAddr);
  const instructions = runUntil(runtime, platformRuntime, doneAddr);
  const resultMarker = runtime.hardware.memory[resultAddr];
  if (resultMarker !== PASS) {
    const catalogSector = symbolAddress(symbols, 'EditorLoadCatalogSectorOffset');
    const catalogEntry = symbolAddress(symbols, 'EditorLoadCatalogEntryOffset');
    const sourcePathPtr = symbolAddress(symbols, 'EditorLoadSourcePathPtr');
    const catalogSectorValue = readWord(runtime.hardware.memory, catalogSector);
    const catalogEntryValue = readWord(runtime.hardware.memory, catalogEntry);
    const sourcePathValue = readWord(runtime.hardware.memory, sourcePathPtr);
    throw new Error(
      `Debug80 editor session failed result=0x${resultMarker.toString(16)} case=${runtime.hardware.memory[caseAddr]} error=0x${runtime.hardware.memory[errorAddr].toString(16)} catalogSector=0x${catalogSectorValue.toString(16)} catalogEntry=0x${catalogEntryValue.toString(16)} sourcePath=${JSON.stringify(readCString(runtime.hardware.memory, sourcePathValue))}`,
    );
  }

  const source = readTm8File(sessionImagePath, '/src/main.asm');
  const backup = readTm8File(sessionImagePath, '/src/.main.asm.b');
  const savedRecord0 = readSourceRecord(source, 0);
  const backupRecord0 = readSourceRecord(backup, 0);
  if (savedRecord0 !== 'ABR0 LINE 00') {
    throw new Error(`saved source record 0 "${savedRecord0}", expected "ABR0 LINE 00"`);
  }
  if (backupRecord0 !== 'R0 LINE 00') {
    throw new Error(`backup source record 0 "${backupRecord0}", expected "R0 LINE 00"`);
  }

  const glcd = glcdBytes(platformRuntime);
  if (!glcd.some((value) => value !== 0)) {
    throw new Error('Debug80 editor session left the GLCD blank');
  }
  writeGlcdCapture(glcd);

  const summary = {
    result: 'ok',
    instructions,
    manualImage: IMAGE_PATH,
    temporaryImage: true,
    temporaryImageRetained: false,
    glcdCapture: GLCD_CAPTURE_PATH,
    savedRecord0,
    backupRecord0,
  };
  writeFileSync(SUMMARY_PATH, `${JSON.stringify(summary, null, 2)}\n`);
  console.log(JSON.stringify(summary, null, 2));
  } finally {
    rmSync(tempSessionDir, { recursive: true, force: true });
  }
}

main().catch((error: unknown) => {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 1;
});
