#!/usr/bin/env node
/**
 * Assemble and run the /tecm8.prj parser proof in Debug80's Z80 runtime.
 */

const { writeFileSync } = require('node:fs');
const { resolve } = require('node:path');

import type { ProofHarness } from './proof/harness';

const harness: ProofHarness = require('./proof/harness.ts');
const {
  TECM8_ROOT,
  PROOF_PASS,
  compileAzm,
  symbolAddress,
  loadBareZ80Runtime,
  runUntilHalt,
  readAsciiZ,
  resultToString,
} = harness;

const PROOF_SOURCE = resolve(TECM8_ROOT, 'proofs/project-config/project-config-proof.asm');
const LAST_RUN = resolve(TECM8_ROOT, 'proofs/project-config/last-run.json');

async function main(): Promise<void> {
  const { bytes, symbols } = await compileAzm(PROOF_SOURCE, 'project-config-proof');
  const runtime = loadBareZ80Runtime(bytes);
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
    resultMarker: resultToString(result),
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
