#!/usr/bin/env node
/**
 * Assemble and run the TECM8 editor entry in Debug80's TEC-1G runtime.
 */

const { execFileSync } = require('node:child_process');
const { existsSync, mkdirSync, readFileSync, writeFileSync } = require('node:fs');
const { dirname, resolve } = require('node:path');

const TECM8_ROOT = resolve(__dirname, '..');
const DEBUG80_ROOT = resolve(process.env.DEBUG80_ROOT ?? '/Users/johnhardy/projects/debug80');
const AZM_ROOT = resolve(process.env.AZM_ROOT ?? '/Users/johnhardy/projects/AZM');
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
const MON3_INTERFACE = resolve(TECM8_ROOT, 'src/mon3.asmi');
const APP_START = 0x4000;
const PASS = 0x42;
const SYS_CTRL = 0xff;
const SHADOW_OFF = 0x01;
const MCB = 0x0888;
const MCB_SD_CARD = 0x80;
const MON3_SYS_MODE = 0x089d;
const TM8_VOLUME_BYTES = 4 * 1024 * 1024;

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

async function compileMain(): Promise<{ bytes: Uint8Array; symbols: D8Symbol[] }> {
  const { compile, defaultFormatWriters } = await import(resolve(AZM_ROOT, 'dist/src/api-compile.js'));
  const result = await compile(
    SOURCE_FILE,
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
  if (!symbol || typeof symbol.address !== 'number') {
    throw new Error(`missing address symbol: ${name}`);
  }
  return symbol.address;
}

function readWord(memory: Uint8Array, address: number): number {
  return memory[address] | (memory[address + 1] << 8);
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

function ensureSessionImage(): void {
  mkdirSync(SESSION_DIR, { recursive: true });
  execFileSync(process.execPath, ['--experimental-strip-types', IMAGE_TOOL, IMAGE_PATH], {
    cwd: TECM8_ROOT,
    stdio: 'ignore',
  });

  const { createVolumeImage, importFileIntoVolumeImage, readFileFromVolumeImage } =
    require(resolve(TECM8_ROOT, 'tools/tm8/format.ts'));
  let volume = createVolumeImage() as Buffer;
  const sourceRecords = encodeSourceRecords([
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
  ]);
  volume = importFileIntoVolumeImage(volume, '/tecm8.prj', encodeProjectConfig('/src/main.asm'));
  volume = importFileIntoVolumeImage(volume, '/src/main.asm', sourceRecords);

  const storedProject = readFileFromVolumeImage(volume, '/tecm8.prj') as Buffer;
  if (!storedProject.equals(encodeProjectConfig('/src/main.asm'))) {
    throw new Error('generated project config was not stored exactly');
  }

  const manifest = JSON.parse(readFileSync(IMAGE_PATH.replace(/\.[^.]*$/, '.json'), 'utf8'));
  const image = Buffer.from(readFileSync(IMAGE_PATH));
  volume.copy(image, manifest.volume_start_byte_offset);
  writeFileSync(IMAGE_PATH, image);
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

function readTm8File(tm8Path: string): Buffer {
  const { readFileFromVolumeImage } = require(resolve(TECM8_ROOT, 'tools/tm8/format.ts'));
  const manifest = JSON.parse(readFileSync(IMAGE_PATH.replace(/\.[^.]*$/, '.json'), 'utf8'));
  const image = readFileSync(IMAGE_PATH);
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

function glcdBytes(platformRuntime: PlatformRuntime): number[] {
  return Array.from(platformRuntime.state.display?.glcdCtrl?.glcd ?? []);
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
  ensureSessionImage();
  if (process.argv.includes('--prepare-only')) {
    const summary = {
      result: 'ok',
      preparedOnly: true,
      image: IMAGE_PATH,
    };
    writeFileSync(SUMMARY_PATH, `${JSON.stringify(summary, null, 2)}\n`);
    console.log(JSON.stringify(summary, null, 2));
    return;
  }

  const { bytes, symbols } = await compileMain();
  if (process.argv.includes('--live-smoke')) {
    const liveLoopAddr = symbolAddress(symbols, 'EditorLiveLoop');
    const doneAddr = symbolAddress(symbols, 'MainDone');
    const cursorRowAddr = symbolAddress(symbols, 'EditorCursorRow');
    const cursorColAddr = symbolAddress(symbols, 'EditorCursorCol');
    const dirtyAddr = symbolAddress(symbols, 'EditorNavDirty');
    const currentPageAddr = symbolAddress(symbols, 'EditorNavCurrentPage');
    const pageBufferAddr = symbolAddress(symbols, 'EditorNavPageBuffer');
    const promptActiveAddr = symbolAddress(symbols, 'EditorPromptActive');
    const promptResultAddr = symbolAddress(symbols, 'EditorPromptResult');
    const quitRequestedAddr = symbolAddress(symbols, 'EditorQuitRequested');
    const modifierBitsAddr = symbolAddress(symbols, 'BiosInputModifierBits');
    const rawPrimaryAddr = symbolAddress(symbols, 'BiosInputRawPrimary');
    const rawSecondaryAddr = symbolAddress(symbols, 'BiosInputRawSecondary');
    const translatedKeyAddr = symbolAddress(symbols, 'BiosInputTranslatedKey');
    const { runtime, platformRuntime } = loadRuntime(bytes, IMAGE_PATH, APP_START, true);
    platformRuntime.setMatrixMode?.(true);
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
    tapMatrixCombo(platformRuntime, runtime, { row: 0, col: 1 }, { row: 0, col: 3 }); // Ctrl+ArrowUp
    runUntilPc(runtime, platformRuntime, liveLoopAddr, 20_000_000);
    const pageAfterCtrlUp = runtime.hardware.memory[currentPageAddr];
    if (pageAfterCtrlUp !== 0) {
      throw new Error(`live editor page after Ctrl+ArrowUp ${pageAfterCtrlUp}, expected 0`);
    }
    tapMatrixCombo(platformRuntime, runtime, { row: 0, col: 3 }, { row: 0, col: 6 }); // Alt+ArrowRight
    runUntilPc(runtime, platformRuntime, liveLoopAddr, 20_000_000);
    const altModifierBits = runtime.hardware.memory[modifierBitsAddr];
    const altRawPrimary = runtime.hardware.memory[rawPrimaryAddr];
    const altRawSecondary = runtime.hardware.memory[rawSecondaryAddr];
    const altTranslatedKey = runtime.hardware.memory[translatedKeyAddr];
    if (
      altModifierBits !== 0x08 ||
      altRawPrimary !== 0x06 ||
      altRawSecondary !== 0x03 ||
      altTranslatedKey !== 0x06
    ) {
      throw new Error(
        `live editor alt event modifier=0x${altModifierBits.toString(16)} raw=${altRawSecondary.toString(16)}/${altRawPrimary.toString(16)} translated=0x${altTranslatedKey.toString(16)}`,
      );
    }
    tapMatrixKey(platformRuntime, runtime, 0, 7); // CapsLock toggles caps state, no editor action
    runUntilPc(runtime, platformRuntime, liveLoopAddr, 20_000_000);
    tapMatrixKey(platformRuntime, runtime, 0, 4); // ArrowDown with caps state set
    runUntilPc(runtime, platformRuntime, liveLoopAddr, 20_000_000);
    const cursorRow = runtime.hardware.memory[cursorRowAddr];
    const cursorCol = runtime.hardware.memory[cursorColAddr];
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
    tapMatrixKey(platformRuntime, runtime, 7, 5); // z
    stepThenRunUntilPc(runtime, platformRuntime, liveLoopAddr, 20_000_000);
    const dirtyAfterEdit = runtime.hardware.memory[dirtyAddr];
    if (dirtyAfterEdit !== 1) {
      throw new Error(`live editor dirty after z ${dirtyAfterEdit}, expected 1`);
    }
    tapMatrixCombo(platformRuntime, runtime, { row: 0, col: 3 }, { row: 0, col: 4 }, 200_000, 200_000); // dirty Alt+ArrowDown within RAM window
    stepThenRunUntilPc(runtime, platformRuntime, liveLoopAddr, 20_000_000);
    const pageAfterDirtyPageDown = runtime.hardware.memory[currentPageAddr];
    const dirtyAfterDirtyPageDown = runtime.hardware.memory[dirtyAddr];
    if (pageAfterDirtyPageDown !== 1 || dirtyAfterDirtyPageDown !== 1) {
      throw new Error(
        `live editor dirty Alt+ArrowDown page=${pageAfterDirtyPageDown} dirty=${dirtyAfterDirtyPageDown}, expected page=1 dirty=1`,
      );
    }
    tapMatrixCombo(platformRuntime, runtime, { row: 0, col: 1 }, { row: 0, col: 3 }, 200_000, 200_000); // dirty Ctrl+ArrowUp back to edited page
    stepThenRunUntilPc(runtime, platformRuntime, liveLoopAddr, 60_000_000);
    const pageAfterDirtyPageUp = runtime.hardware.memory[currentPageAddr];
    const dirtyAfterDirtyPageUp = runtime.hardware.memory[dirtyAddr];
    if (pageAfterDirtyPageUp !== 0 || dirtyAfterDirtyPageUp !== 1) {
      throw new Error(
        `live editor dirty Alt+ArrowUp page=${pageAfterDirtyPageUp} dirty=${dirtyAfterDirtyPageUp}, expected page=0 dirty=1`,
      );
    }
    tapMatrixKey(platformRuntime, runtime, 1, 2); // Enter: split line
    stepThenRunUntilPc(runtime, platformRuntime, liveLoopAddr, 20_000_000);
    const cursorRowAfterEnter = runtime.hardware.memory[cursorRowAddr];
    const cursorColAfterEnter = runtime.hardware.memory[cursorColAddr];
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
    assertRuntimeSourceRecord(runtime, pageBufferAddr, 2, 'RZ0 LINE 01', 'after Enter split');
    assertRuntimeSourceRecord(runtime, pageBufferAddr, 15, 'R0 LINE 14', 'after Enter split');
    tapMatrixCombo(platformRuntime, runtime, { row: 0, col: 3 }, { row: 6, col: 6 }, 200_000, 200_000); // Alt+S
    stepThenRunUntilPc(runtime, platformRuntime, liveLoopAddr, 120_000_000);
    const dirtyAfterSave = runtime.hardware.memory[dirtyAddr];
    const saveTranslatedKey = runtime.hardware.memory[translatedKeyAddr];
    const saveModifierBits = runtime.hardware.memory[modifierBitsAddr];
    if (
      dirtyAfterSave !== 0 ||
      (saveTranslatedKey !== 0x53 && saveTranslatedKey !== 0x73) ||
      (saveModifierBits & 0x08) === 0
    ) {
      throw new Error(
        `live editor Alt-S save dirty=${dirtyAfterSave} modifier=0x${saveModifierBits.toString(16)} translated=0x${saveTranslatedKey.toString(16)}, expected dirty=0 alt-modified S/s`,
      );
    }
    tapMatrixCombo(platformRuntime, runtime, { row: 0, col: 3 }, { row: 0, col: 4 }, 200_000, 200_000); // Alt+ArrowDown
    stepThenRunUntilPc(runtime, platformRuntime, liveLoopAddr, 60_000_000);
    const pageAfterSplitSaveDown = runtime.hardware.memory[currentPageAddr];
    if (pageAfterSplitSaveDown !== 1) {
      throw new Error(`live editor page after saved split Alt+ArrowDown ${pageAfterSplitSaveDown}, expected 1`);
    }
    tapMatrixCombo(platformRuntime, runtime, { row: 0, col: 1 }, { row: 0, col: 3 }, 200_000, 200_000); // Ctrl+ArrowUp
    stepThenRunUntilPc(runtime, platformRuntime, liveLoopAddr, 60_000_000);
    const pageAfterSplitSaveUp = runtime.hardware.memory[currentPageAddr];
    if (pageAfterSplitSaveUp !== 0) {
      throw new Error(`live editor page after saved split Alt+ArrowUp ${pageAfterSplitSaveUp}, expected 0`);
    }
    assertRuntimeSourceRecord(runtime, pageBufferAddr, 0, '', 'after saved split page return');
    assertRuntimeSourceRecord(runtime, pageBufferAddr, 1, 'R0 LINE 00', 'after saved split page return');
    assertRuntimeSourceRecord(runtime, pageBufferAddr, 2, 'RZ0 LINE 01', 'after saved split page return');
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
    assertRuntimeSourceRecord(runtime, pageBufferAddr, 1, 'RZ0 LINE 01', 'after Backspace join');
    assertRuntimeSourceRecord(runtime, pageBufferAddr, 15, '', 'after Backspace join');
    tapMatrixCombo(platformRuntime, runtime, { row: 0, col: 3 }, { row: 6, col: 6 }, 200_000, 200_000); // save joined page
    stepThenRunUntilPc(runtime, platformRuntime, liveLoopAddr, 120_000_000);
    const dirtyAfterJoinSave = runtime.hardware.memory[dirtyAddr];
    if (dirtyAfterJoinSave !== 0) {
      throw new Error(`live editor dirty after join save ${dirtyAfterJoinSave}, expected 0`);
    }
    tapMatrixCombo(platformRuntime, runtime, { row: 0, col: 3 }, { row: 6, col: 6 }, 200_000, 200_000); // clean Alt+S no-op
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
    tapMatrixCombo(platformRuntime, runtime, { row: 0, col: 3 }, { row: 6, col: 6 }, 200_000, 200_000); // save post-save edit
    stepThenRunUntilPc(runtime, platformRuntime, liveLoopAddr, 120_000_000);
    const dirtyAfterSecondSave = runtime.hardware.memory[dirtyAddr];
    if (dirtyAfterSecondSave !== 0) {
      throw new Error(`live editor second save dirty=${dirtyAfterSecondSave}, expected 0`);
    }
    tapMatrixCombo(platformRuntime, runtime, { row: 0, col: 3 }, { row: 6, col: 5 }, 200_000, 200_000); // Alt+R
    stepThenRunUntilPc(runtime, platformRuntime, liveLoopAddr, 20_000_000);
    const promptAfterAltR = runtime.hardware.memory[promptActiveAddr];
    if (promptAfterAltR !== 1) {
      const restoreModifierBits = runtime.hardware.memory[modifierBitsAddr];
      const restoreTranslatedKey = runtime.hardware.memory[translatedKeyAddr];
      throw new Error(
        `live editor Alt-R prompt active=${promptAfterAltR}, expected 1; modifier=0x${restoreModifierBits.toString(16)} translated=0x${restoreTranslatedKey.toString(16)}`,
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
    tapMatrixCombo(platformRuntime, runtime, { row: 0, col: 3 }, { row: 7, col: 3 }, 200_000, 200_000); // Alt+X
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
        `live editor Alt-X returned to loop instead of exiting: modifier=0x${quitModifierBits.toString(16)} raw=${quitRawSecondary.toString(16)}/${quitRawPrimary.toString(16)} translated=0x${quitTranslatedKey.toString(16)}`,
      );
    }
    const quitModifierBits = runtime.hardware.memory[modifierBitsAddr];
    if ((quitTranslatedKey !== 0x58 && quitTranslatedKey !== 0x78) || (quitModifierBits & 0x08) === 0) {
      throw new Error(
        `live editor quit modifier=0x${quitModifierBits.toString(16)} translated=0x${quitTranslatedKey.toString(16)}, expected alt-modified X/x`,
      );
    }
    const summary = {
      result: 'ok',
      liveSmoke: true,
      bootInstructions,
      cursorRow,
      cursorCol,
      pageAfterCtrlDown,
      rowAfterCtrlDown,
      pageAfterCtrlUp,
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
      promptAfterAltR,
      promptAfterRestoreNo,
      dirtyAfterRestoreNo,
      saveModifierBits,
      modifierBits,
      rawPrimary,
      rawSecondary,
      translatedKey,
      saveTranslatedKey,
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
  const { runtime, platformRuntime } = loadRuntime(bytes, IMAGE_PATH, scriptStartAddr);
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

  const source = readTm8File('/src/main.asm');
  const backup = readTm8File('/src/.main.asm.b');
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
    image: IMAGE_PATH,
    glcdCapture: GLCD_CAPTURE_PATH,
    savedRecord0,
    backupRecord0,
  };
  writeFileSync(SUMMARY_PATH, `${JSON.stringify(summary, null, 2)}\n`);
  console.log(JSON.stringify(summary, null, 2));
}

main().catch((error: unknown) => {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 1;
});
