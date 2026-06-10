#!/usr/bin/env node
/**
 * Assemble and run the TEC-side shell command resolver proof.
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

const PROOF_SOURCE = resolve(TECM8_ROOT, 'proofs/shell-commands/shell-commands-proof.asm');
const LAST_RUN = resolve(TECM8_ROOT, 'proofs/shell-commands/last-run.json');

async function main(): Promise<void> {
  const { bytes, symbols } = await compileAzm(PROOF_SOURCE, 'shell-commands-proof');
  const runtime = loadBareZ80Runtime(bytes);
  const instructions = runUntilHalt(runtime);
  const resultAddr = symbolAddress(symbols, 'ResultMarker');
  const caseAddr = symbolAddress(symbols, 'CaseMarker');
  const pathAddr = symbolAddress(symbols, 'PathOut');
  const result = runtime.hardware.memory[resultAddr];
  const proofCase = runtime.hardware.memory[caseAddr];
  const pathOut = readAsciiZ(runtime.hardware.memory, pathAddr);

  if (result !== PROOF_PASS) {
    throw new Error(`shell commands proof failed: marker=0x${result.toString(16)} case=${proofCase} pathOut=${JSON.stringify(pathOut)}`);
  }

  const report = {
    result: 'ok',
    instructions,
    resultMarker: resultToString(result),
    proofCase,
    pathOut,
  };
  writeFileSync(LAST_RUN, JSON.stringify(report, null, 2) + '\n', 'ascii');
  console.log(JSON.stringify(report, null, 2));
}

main().catch((error: unknown) => {
  const message = error instanceof Error ? error.message : String(error);
  console.error(`error: ${message}`);
  process.exit(1);
});
