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
    'R0 LINE 15',
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

function makeConfig(imagePath: string) {
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
    sdEnabled: true,
    sdHighCapacity: true,
    sdImagePath: imagePath,
  };
}

function loadRuntime(bytes: Uint8Array, imagePath: string): { runtime: Runtime; platformRuntime: PlatformRuntime } {
  const { createTec1gRuntime } = requireFromDebug80('out/platforms/tec1g/runtime.js') as {
    createTec1gRuntime: Function;
  };
  const { createTec1gMemoryHooks } = requireFromDebug80(
    'out/platforms/tec1g/tec1g-memory.js',
  ) as { createTec1gMemoryHooks: Function };
  const { createZ80Runtime } = requireFromDebug80('out/z80/runtime.js') as {
    createZ80Runtime: Function;
  };

  const config = makeConfig(imagePath);
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
  runtime.hardware.forceMemWrite?.(MCB, MCB_SD_CARD);
  runtime.cpu.sp = 0x7ff0;
  runtime.cpu.pc = APP_START;
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

function readTm8File(tm8Path: string): Buffer {
  const { readFileFromVolumeImage } = require(resolve(TECM8_ROOT, 'tools/tm8/format.ts'));
  const manifest = JSON.parse(readFileSync(IMAGE_PATH.replace(/\.[^.]*$/, '.json'), 'utf8'));
  const image = readFileSync(IMAGE_PATH);
  const volume = image.subarray(manifest.volume_start_byte_offset, manifest.volume_start_byte_offset + TM8_VOLUME_BYTES);
  return readFileFromVolumeImage(Buffer.from(volume), tm8Path) as Buffer;
}

function readSourceRecord(records: Buffer, record: number): string {
  const start = record * 32;
  const length = records[start];
  return records.subarray(start + 1, start + 1 + length).toString('ascii');
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
  const doneAddr = symbolAddress(symbols, 'MainDone');
  const resultAddr = symbolAddress(symbols, 'MainResultMarker');
  const errorAddr = symbolAddress(symbols, 'MainErrorMarker');
  const caseAddr = symbolAddress(symbols, 'MainCaseMarker');
  const { runtime, platformRuntime } = loadRuntime(bytes, IMAGE_PATH);
  const instructions = runUntil(runtime, platformRuntime, doneAddr);
  const resultMarker = runtime.hardware.memory[resultAddr];
  if (resultMarker !== PASS) {
    throw new Error(
      `Debug80 editor session failed result=0x${resultMarker.toString(16)} case=${runtime.hardware.memory[caseAddr]} error=0x${runtime.hardware.memory[errorAddr].toString(16)}`,
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
