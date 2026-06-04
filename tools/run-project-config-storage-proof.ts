#!/usr/bin/env node
/**
 * Assemble and run the /tecm8.prj storage loader proof in Debug80's TEC-1G
 * runtime with MON3 ROM and FAT32-backed SD image.
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

const PROOF_SOURCE = resolve(TECM8_ROOT, 'proofs/project-config/project-config-storage-proof.asm');
const MON3_INTERFACE = resolve(TECM8_ROOT, 'src/mon3.asmi');
const LAST_RUN = resolve(TECM8_ROOT, 'proofs/project-config/storage-last-run.json');
const IMAGE_TOOL = resolve(TECM8_ROOT, 'tools/create-storage-proof-image.ts');
const NODE_TS_ARGS = ['--experimental-strip-types'];
const APP_START = 0x4000;
const PROOF_PASS = 0x42;
const PROOF_FAIL = 0xe0;
const SYS_CTRL = 0xff;
const SHADOW_OFF = 0x01;
const MCB = 0x0888;
const MCB_SD_CARD = 0x80;
const PROJECT_CFG_ERR_HEADER = 0x01;

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

type ProofCase = {
  name: string;
  imageName: string;
  configBytes: Buffer;
  mutateVolume?: (volume: Buffer) => void;
  expectedResult: number;
  expectedMainPath?: string;
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
        bin: 'build/project-config-storage-proof.bin',
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

function readAsciiZ(memory: Uint8Array, address: number): string {
  let end = address;
  while (end < memory.length && memory[end] !== 0) {
    end += 1;
  }
  return Buffer.from(memory.subarray(address, end)).toString('ascii');
}

function ensureImage(proofCase: ProofCase): string {
  const imagePath = resolve(TECM8_ROOT, `proofs/project-config/${proofCase.imageName}.img`);
  execFileSync(process.execPath, [...NODE_TS_ARGS, IMAGE_TOOL, imagePath], {
    cwd: TECM8_ROOT,
    stdio: 'ignore',
  });

  const { createVolumeImage, importFileIntoVolumeImage, readFileFromVolumeImage } =
    require(resolve(TECM8_ROOT, 'tools/tm8/format.ts'));
  const manifest = JSON.parse(readFileSync(imagePath.replace(/\.[^.]*$/, '.json'), 'utf8'));
  let volume = createVolumeImage() as Buffer;
  volume = importFileIntoVolumeImage(
    volume,
    '/tecm8.prj',
    proofCase.configBytes,
  );
  volume = importFileIntoVolumeImage(
    volume,
    '/src/main.asm',
    Buffer.from('; project config storage proof fixture\n', 'ascii'),
  );

  const storedConfig = readFileFromVolumeImage(volume, '/tecm8.prj').toString('ascii');
  if (storedConfig !== proofCase.configBytes.toString('ascii')) {
    throw new Error(`bad generated project config: ${JSON.stringify(storedConfig)}`);
  }
  proofCase.mutateVolume?.(volume);

  const image = Buffer.from(readFileSync(imagePath));
  volume.copy(image, manifest.volume_start_byte_offset);
  writeFileSync(imagePath, image);
  return imagePath;
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

function proofCases(): ProofCase[] {
  return [
    {
      name: 'valid project config',
      imageName: 'project-config-valid-fat32',
      configBytes: Buffer.from('tm8project=1\nmain=/src/main.asm\n', 'ascii'),
      expectedResult: PROOF_PASS,
      expectedMainPath: '/src/main.asm',
    },
    {
      name: 'zero-length project config',
      imageName: 'project-config-empty-fat32',
      configBytes: Buffer.alloc(0),
      expectedResult: PROOF_FAIL | PROJECT_CFG_ERR_HEADER,
    },
  ];
}

async function runProofCase(
  proofCase: ProofCase,
  bytes: Uint8Array,
  symbols: D8Symbol[],
): Promise<{ name: string; instructions: number; resultMarker: string; mainPath: string; image: string }> {
  const imagePath = ensureImage(proofCase);
  const doneAddr = symbolAddress(symbols, 'ProofDone');
  const resultAddr = symbolAddress(symbols, 'ResultMarker');
  const mainPathAddr = symbolAddress(symbols, 'MainPathOut');
  const { runtime, platformRuntime } = loadRuntime(bytes, imagePath);
  const instructions = runUntil(runtime, platformRuntime, doneAddr);
  const result = runtime.hardware.memory[resultAddr];
  const mainPath = readAsciiZ(runtime.hardware.memory, mainPathAddr);

  if (result !== proofCase.expectedResult) {
    throw new Error(
      `${proofCase.name} failed: marker=${resultToString(result)} expected=${resultToString(proofCase.expectedResult)} mainPath=${JSON.stringify(mainPath)}`,
    );
  }
  if (proofCase.expectedMainPath !== undefined && mainPath !== proofCase.expectedMainPath) {
    throw new Error(`${proofCase.name} main path mismatch: ${JSON.stringify(mainPath)}`);
  }

  return {
    name: proofCase.name,
    instructions,
    resultMarker: resultToString(result),
    mainPath,
    image: imagePath,
  };
}

async function main(): Promise<void> {
  if (!existsSync(MON3_ROM_PATH)) {
    throw new Error(`MON3 ROM not found: ${MON3_ROM_PATH}`);
  }
  const caseName = process.argv[process.argv.indexOf('--case') + 1];
  if (process.argv.includes('--case')) {
    const proofCase = proofCases().find((entry) => entry.imageName === caseName);
    if (!proofCase) {
      throw new Error(`unknown proof case: ${caseName}`);
    }
    const { bytes, symbols } = await compileProof();
    console.log(JSON.stringify(await runProofCase(proofCase, bytes, symbols), null, 2));
    return;
  }

  const cases = proofCases().map((proofCase) => {
    const stdout = execFileSync(
      process.execPath,
      [...NODE_TS_ARGS, __filename, '--case', proofCase.imageName],
      {
        cwd: TECM8_ROOT,
        encoding: 'utf8',
      },
    );
    return JSON.parse(stdout);
  });

  const report = {
    result: 'ok',
    cases,
  };
  writeFileSync(LAST_RUN, JSON.stringify(report, null, 2) + '\n', 'ascii');
  console.log(JSON.stringify(report, null, 2));
}

main().catch((error: unknown) => {
  const message = error instanceof Error ? error.message : String(error);
  console.error(`error: ${message}`);
  process.exit(1);
});
