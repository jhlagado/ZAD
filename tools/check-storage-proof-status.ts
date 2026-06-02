#!/usr/bin/env node
/**
 * Report the current storage-proof state.
 *
 * This intentionally distinguishes two things:
 * - the MON3 storage model proof, currently passing with the local SD shim;
 * - the unmodified compiled Debug80 gate, currently expected to fail until
 *   patches/debug80-mon3-sd-spi.patch is ported and Debug80 is rebuilt.
 */

const { readFileSync } = require('node:fs');
const { resolve } = require('node:path');
const { spawnSync } = require('node:child_process');

const ZAD_ROOT = resolve(__dirname, '..');
const IMAGE_TOOL = resolve(ZAD_ROOT, 'tools/create-storage-proof-image.ts');
const RUNNER = resolve(ZAD_ROOT, 'tools/run-storage-proof.ts');
const LAST_RUN = resolve(ZAD_ROOT, 'proofs/storage/last-run.json');
const NODE_TS_ARGS = ['--experimental-strip-types'];

type CommandResult = {
  command: string[];
  status: number | null;
  stdout: string;
  stderr: string;
};

function run(args: string[]): CommandResult {
  const result = spawnSync(process.execPath, [...NODE_TS_ARGS, ...args], {
    cwd: ZAD_ROOT,
    encoding: 'utf8',
  });
  return {
    command: [process.execPath, ...NODE_TS_ARGS, ...args],
    status: result.status,
    stdout: result.stdout ?? '',
    stderr: result.stderr ?? '',
  };
}

function summarizeFailure(result: CommandResult): string | null {
  const text = `${result.stdout}\n${result.stderr}`;
  const fatError = text.match(/FATerror\d+:[^\n]+/);
  if (fatError) {
    return fatError[0];
  }
  const error = text.match(/Error: ([^\n]+)/);
  if (error?.[1]) {
    return error[1];
  }
  return result.status === 0 ? null : `exit ${result.status}`;
}

function main(): void {
  const strict = process.argv.includes('--strict');

  const createImage = run([IMAGE_TOOL]);
  if (createImage.status !== 0) {
    process.stderr.write(createImage.stderr);
    process.exit(1);
  }

  const verifyPristine = run([IMAGE_TOOL, '--verify-only']);
  if (verifyPristine.status !== 0) {
    process.stderr.write(verifyPristine.stderr);
    process.exit(1);
  }

  const noShim = run([RUNNER, '--no-sd-compat-patch']);
  const shimmed = run([RUNNER]);
  if (shimmed.status !== 0) {
    process.stderr.write(shimmed.stderr);
    process.exit(1);
  }

  const lastRun = JSON.parse(readFileSync(LAST_RUN, 'utf8'));
  const report = {
    debug80Root: process.env.DEBUG80_ROOT ?? '/Users/johnhardy/projects/debug80',
    pristineImage: verifyPristine.status === 0 ? 'ok' : 'failed',
    noShimDebug80: {
      status: noShim.status === 0 ? 'ok' : 'failed',
      failure: summarizeFailure(noShim),
    },
    shimmedMon3Proof: {
      status: 'ok',
      instructions: lastRun.instructions,
      markers: lastRun.markers,
    },
    goalCompleteWithoutShim: noShim.status === 0,
  };

  console.log(JSON.stringify(report, null, 2));
  if (strict && noShim.status !== 0) {
    process.exit(2);
  }
}

main();
