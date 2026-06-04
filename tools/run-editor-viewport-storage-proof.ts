#!/usr/bin/env node
/**
 * Assemble and run the storage-backed editor viewport proof in Debug80's
 * TEC-1G runtime with MON3 ROM and a FAT32-backed VOLUME.TM8 image.
 */

const { execFileSync } = require('node:child_process');
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

const PROOF_SOURCE = resolve(TECM8_ROOT, 'proofs/display/editor-viewport-storage-proof.asm');
const LAST_RUN = resolve(TECM8_ROOT, 'proofs/display/editor-viewport-storage-proof-last-run.json');
const IMAGE_PATH = resolve(TECM8_ROOT, 'proofs/display/editor-viewport-storage-fat32.img');
const IMAGE_TOOL = resolve(TECM8_ROOT, 'tools/create-storage-proof-image.ts');
const INTERFACES = [
  resolve(TECM8_ROOT, 'src/tecm8-bios.asmi'),
  resolve(TECM8_ROOT, 'src/display-model.asmi'),
  resolve(TECM8_ROOT, 'src/editor-viewport.asmi'),
  resolve(TECM8_ROOT, 'src/editor-storage-loader.asmi'),
];
const NODE_TS_ARGS = ['--experimental-strip-types'];
const APP_START = 0x4000;
const PROOF_PASS = 0x42;
const SYS_CTRL = 0xff;
const SHADOW_OFF = 0x01;
const MCB = 0x0888;
const MCB_SD_CARD = 0x80;

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
  state: { display?: { glcdCtrl?: { glcd?: number[] | Uint8Array } } };
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
      d8mInputs: { bin: 'build/editor-viewport-storage-proof.bin' },
      registerCare: 'strict',
      registerCareProfile: 'mon3',
      registerCareInterfaces: INTERFACES,
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

function ensureImage(): string {
  execFileSync(process.execPath, [...NODE_TS_ARGS, IMAGE_TOOL, IMAGE_PATH], {
    cwd: TECM8_ROOT,
    stdio: 'ignore',
  });

  const { createVolumeImage, importFileIntoVolumeImage, readFileFromVolumeImage } =
    require(resolve(TECM8_ROOT, 'tools/tm8/format.ts'));
  const manifest = JSON.parse(readFileSync(IMAGE_PATH.replace(/\.[^.]*$/, '.json'), 'utf8'));
  const sourceRecords = encodeSourceRecords([
    'ORG 4000H',
    'CALL INIT',
    'LD HL,MSG',
    'CALL PRINT',
    'JP DONE',
    "MSG DB 'OK'",
    'DONE:',
    'RET',
  ]);
  let volume = createVolumeImage() as Buffer;
  volume = importFileIntoVolumeImage(volume, '/src/main.asm', sourceRecords);

  const stored = readFileFromVolumeImage(volume, '/src/main.asm') as Buffer;
  if (!stored.equals(sourceRecords)) {
    throw new Error('generated source records were not stored exactly');
  }

  const image = Buffer.from(readFileSync(IMAGE_PATH));
  volume.copy(image, manifest.volume_start_byte_offset);
  writeFileSync(IMAGE_PATH, image);
  return IMAGE_PATH;
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
  const maxInstructions = 20_000_000;
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

function getGlcdBytes(platformRuntime: PlatformRuntime): number[] {
  return Array.from(platformRuntime.state.display?.glcdCtrl?.glcd ?? []);
}

function glcdRowHasPixels(glcd: number[], displayRow: number): boolean {
  const firstPixelRow = displayRow * 6;
  for (let y = firstPixelRow; y < firstPixelRow + 6; y += 1) {
    const start = y * 16;
    const end = start + 16;
    if (glcd.slice(start, end).some((value) => value !== 0)) {
      return true;
    }
  }
  return false;
}

function verifyProof(runtime: Runtime, platformRuntime: PlatformRuntime, symbols: D8Symbol[]): void {
  const expectedRows = [
    { symbol: 'EditorRowText0', text: 'ORG 4000H' },
    { symbol: 'EditorRowText1', text: 'CALL INIT' },
    { symbol: 'EditorRowText7', text: 'RET' },
  ];
  for (const row of expectedRows) {
    const actual = readCString(runtime.hardware.memory, symbolAddress(symbols, row.symbol));
    if (actual !== row.text) {
      throw new Error(`storage viewport copied ${row.symbol} as "${actual}", expected "${row.text}"`);
    }
  }

  const sourceSector = symbolAddress(symbols, 'EditorSourceSector');
  if (runtime.hardware.memory[sourceSector] !== 9) {
    throw new Error(`source sector was not loaded as source records: first byte ${runtime.hardware.memory[sourceSector]}`);
  }

  const glcd = getGlcdBytes(platformRuntime);
  for (let row = 0; row < 10; row += 1) {
    if (!glcdRowHasPixels(glcd, row)) {
      throw new Error(`storage viewport proof did not render display row: ${row}`);
    }
  }
}

async function main(): Promise<void> {
  if (!existsSync(MON3_ROM_PATH)) {
    throw new Error(`MON3 ROM not found: ${MON3_ROM_PATH}`);
  }

  const imagePath = ensureImage();
  const { bytes, symbols } = await compileProof();
  const doneAddr = symbolAddress(symbols, 'ProofDone');
  const resultAddr = symbolAddress(symbols, 'ResultMarker');
  const { runtime, platformRuntime } = loadRuntime(bytes, imagePath);
  const instructions = runUntil(runtime, platformRuntime, doneAddr);
  const result = runtime.hardware.memory[resultAddr];
  if (result !== PROOF_PASS) {
    throw new Error(`editor viewport storage proof failed: marker=${resultToString(result)}`);
  }
  verifyProof(runtime, platformRuntime, symbols);

  const report = {
    result: 'ok',
    instructions,
    resultMarker: resultToString(result),
    image: imagePath,
  };
  writeFileSync(LAST_RUN, JSON.stringify(report, null, 2) + '\n', 'ascii');
  console.log(JSON.stringify(report, null, 2));
}

main().catch((error: unknown) => {
  const message = error instanceof Error ? error.message : String(error);
  console.error(`error: ${message}`);
  process.exit(1);
});
