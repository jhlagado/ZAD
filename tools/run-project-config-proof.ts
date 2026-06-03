#!/usr/bin/env node
/**
 * Assemble and run the /tecm8.prj parser proof in Debug80's Z80 runtime.
 */

const { readFileSync, writeFileSync } = require('node:fs');
const { resolve } = require('node:path');

const TECM8_ROOT = resolve(__dirname, '..');
const DEBUG80_ROOT = resolve(process.env.DEBUG80_ROOT ?? '/Users/johnhardy/projects/debug80');
const AZM_ROOT = resolve(process.env.AZM_ROOT ?? '/Users/johnhardy/projects/AZM');
const PROOF_SOURCE = resolve(TECM8_ROOT, 'proofs/project-config/project-config-proof.asm');
const LAST_RUN = resolve(TECM8_ROOT, 'proofs/project-config/last-run.json');
const APP_START = 0x4000;
const PROOF_PASS = 0x42;

type Runtime = {
  cpu: {
    pc: number;
    sp: number;
    halted: boolean;
  };
  hardware: {
    memory: Uint8Array;
  };
  step: () => { halted: boolean; pc: number; cycles?: number };
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
        bin: 'build/project-config-proof.bin',
      },
      registerCare: 'strict',
      registerCareProfile: 'mon3',
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

function loadRuntime(bytes: Uint8Array): Runtime {
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

function runUntilHalt(runtime: Runtime): number {
  const maxInstructions = 100_000;
  for (let i = 0; i < maxInstructions; i += 1) {
    const result = runtime.step();
    if (runtime.cpu.halted || result.halted) {
      return i + 1;
    }
  }
  throw new Error(`proof did not halt; pc=0x${runtime.cpu.pc.toString(16)}`);
}

function readAsciiZ(memory: Uint8Array, address: number): string {
  let end = address;
  while (end < memory.length && memory[end] !== 0) {
    end += 1;
  }
  return Buffer.from(memory.subarray(address, end)).toString('ascii');
}

async function main(): Promise<void> {
  const { bytes, symbols } = await compileProof();
  const runtime = loadRuntime(bytes);
  const instructions = runUntilHalt(runtime);
  const resultAddr = symbolAddress(symbols, 'ResultMarker');
  const mainPathAddr = symbolAddress(symbols, 'MainPathOut');
  const result = runtime.hardware.memory[resultAddr];
  const mainPath = readAsciiZ(runtime.hardware.memory, mainPathAddr);

  if (result !== PROOF_PASS) {
    throw new Error(`project config proof failed: marker=0x${result.toString(16)} mainPath=${JSON.stringify(mainPath)}`);
  }
  if (mainPath !== '/src/main.asm') {
    throw new Error(`main path mismatch: ${JSON.stringify(mainPath)}`);
  }

  const report = {
    result: 'ok',
    instructions,
    resultMarker: `0x${result.toString(16).padStart(2, '0')}`,
    mainPath,
  };
  writeFileSync(LAST_RUN, JSON.stringify(report, null, 2) + '\n', 'ascii');
  console.log(JSON.stringify(report, null, 2));
}

main().catch((error: unknown) => {
  const message = error instanceof Error ? error.message : String(error);
  console.error(`error: ${message}`);
  process.exit(1);
});
