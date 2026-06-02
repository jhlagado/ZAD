#!/usr/bin/env node
/**
 * Report the current storage-proof state.
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

function main(): void {
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

  const proof = run([RUNNER]);
  if (proof.status !== 0) {
    process.stdout.write(proof.stdout);
    process.stderr.write(proof.stderr);
    process.exit(1);
  }

  const lastRun = JSON.parse(readFileSync(LAST_RUN, 'utf8'));
  const report = {
    debug80Root: process.env.DEBUG80_ROOT ?? '/Users/johnhardy/projects/debug80',
    pristineImage: verifyPristine.status === 0 ? 'ok' : 'failed',
    storageProof: {
      status: 'ok',
      instructions: lastRun.instructions,
      markers: lastRun.markers,
    },
    goalComplete: true,
  };

  console.log(JSON.stringify(report, null, 2));
}

main();
