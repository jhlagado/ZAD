#!/usr/bin/env node
/**
 * Assemble the standalone TECM8 keyboard tester target.
 */

const { mkdirSync, writeFileSync } = require('node:fs');
const { dirname, resolve } = require('node:path');

const TECM8_ROOT = resolve(__dirname, '..');
const AZM_ROOT = process.env.AZM_ROOT ? resolve(process.env.AZM_ROOT) : undefined;
const SOURCE_FILE = resolve(TECM8_ROOT, 'src/keyboard-tester.main.asm');
const MON3_INTERFACE = resolve(TECM8_ROOT, 'src/mon3.asmi');
const BIN_PATH = resolve(TECM8_ROOT, 'build/keyboard-tester.bin');
const D8M_PATH = resolve(TECM8_ROOT, 'build/keyboard-tester.d8m.json');

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

async function main(): Promise<void> {
  const { compile, defaultFormatWriters } = AZM_ROOT
    ? await import(resolve(AZM_ROOT, 'dist/src/api-compile.js'))
    : await import('@jhlagado/azm/compile');

  const result = await compile(
    SOURCE_FILE,
    {
      emitBin: true,
      emitD8m: true,
      outputType: 'bin',
      sourceRoot: TECM8_ROOT,
      d8mInputs: { bin: 'build/keyboard-tester.bin' },
      registerContracts: 'strict',
      registerContractsProfile: 'mon3',
      registerContractsInterfaces: [MON3_INTERFACE],
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

  mkdirSync(dirname(BIN_PATH), { recursive: true });
  writeFileSync(BIN_PATH, Buffer.from(bin.bytes));
  writeFileSync(D8M_PATH, JSON.stringify(d8m?.json ?? {}, null, 2));

  console.log(JSON.stringify({
    result: 'ok',
    source: SOURCE_FILE,
    bin: BIN_PATH,
    d8m: D8M_PATH,
    bytes: bin.bytes.length,
  }, null, 2));
}

main().catch((error: unknown) => {
  console.error(error);
  process.exitCode = 1;
});
