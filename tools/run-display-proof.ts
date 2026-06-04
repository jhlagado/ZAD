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

const PROOF_SOURCE = resolve(TECM8_ROOT, 'proofs/display/glcd-smoke-proof.asm');
const TECM8_BIOS_INTERFACE = resolve(TECM8_ROOT, 'src/tecm8-bios.asmi');
const LAST_RUN = resolve(TECM8_ROOT, 'proofs/display/glcd-last-run.json');
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
        bin: 'build/glcd-smoke-proof.bin',
      },
      registerCare: 'strict',
      registerCareProfile: 'mon3',
      registerCareInterfaces: [TECM8_BIOS_INTERFACE],
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
  const glcd = platformRuntime.state.display?.glcdCtrl?.glcd;
  return Array.from(glcd ?? []).some((value) => value !== 0);
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

  if (result !== PROOF_PASS) {
    throw new Error(`display proof failed: marker=${resultToString(result)}`);
  }
  if (!visiblePixels) {
    throw new Error('display proof did not update Debug80 GLCD pixels');
  }

  const report = {
    result: 'ok',
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
