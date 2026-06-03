#!/usr/bin/env node
/**
 * Run the TM8 storage-proof audit against the current Debug80 runtime.
 */

const { readFileSync } = require('node:fs');
const { resolve } = require('node:path');
const { spawnSync } = require('node:child_process');

const TECM8_ROOT = resolve(__dirname, '..');
const STATUS_TOOL = resolve(TECM8_ROOT, 'tools/check-storage-proof-status.ts');
const LAST_RUN = resolve(TECM8_ROOT, 'proofs/storage/last-run.json');
const NODE_TS_ARGS = ['--experimental-strip-types'];

type CommandResult = {
  status: number | null;
  stdout: string;
  stderr: string;
};

type ProofMarker = {
  sector: number;
  offset: number;
  marker: string;
};

function runNode(args: string[]): CommandResult {
  const result = spawnSync(process.execPath, [...NODE_TS_ARGS, ...args], {
    cwd: TECM8_ROOT,
    encoding: 'utf8',
  });
  return {
    status: result.status,
    stdout: result.stdout ?? '',
    stderr: result.stderr ?? '',
  };
}

function requireSuccess(result: CommandResult, label: string): void {
  if (result.status !== 0) {
    process.stdout.write(result.stdout);
    process.stderr.write(result.stderr);
    throw new Error(`${label} failed with exit ${result.status}`);
  }
}

function requirementReport(markers: ProofMarker[]) {
  const sectors = new Set(markers.map((marker) => marker.sector));
  const layoutSectorsCovered = [0, 8, 16, 79, 80].every((sector) => sectors.has(sector));

  return [
    {
      requirement: 'Host-created VOLUME.TM8 exists on emulated/card FAT32 volume',
      status: 'proven',
      evidence: 'tools/create-storage-proof-image.ts generated and verified the FAT32 image.',
    },
    {
      requirement: 'MON3 or Debug80/MON3 path opens the existing file',
      status: 'proven',
      evidence: 'tools/run-storage-proof.ts opened VOLUME.TM8 through MON3 openFile.',
    },
    {
      requirement: 'TEC-side code reads arbitrary 512-byte sectors inside VOLUME.TM8',
      status: layoutSectorsCovered ? 'proven' : 'not-proven',
      evidence: `verified sectors: ${[...sectors].sort((a, b) => a - b).join(', ')}`,
    },
    {
      requirement: 'TEC-side code writes back sectors that were previously read',
      status: layoutSectorsCovered ? 'proven' : 'not-proven',
      evidence: 'MON3 writeSector markers were verified from host-side image bytes.',
    },
    {
      requirement: 'Host can verify writes afterward',
      status: markers.length >= 5 ? 'proven' : 'not-proven',
      evidence: markers,
    },
    {
      requirement: 'Version 1 layout offsets are reliable',
      status: layoutSectorsCovered ? 'proven' : 'not-proven',
      evidence: 'superblock, allocation table, catalog start/end, and first data sector markers verified.',
    },
  ];
}

function main(): void {
  const statusResult = runNode([STATUS_TOOL, '--strict']);
  requireSuccess(statusResult, 'storage proof status check');

  const lastRun = JSON.parse(readFileSync(LAST_RUN, 'utf8'));
  console.log(
    JSON.stringify(
      {
        result: 'ok',
        debug80Root: process.env.DEBUG80_ROOT ?? '/Users/johnhardy/projects/debug80',
        storageProof: {
          status: 'ok',
          instructions: lastRun.instructions,
          markers: lastRun.markers,
        },
        requirements: requirementReport(lastRun.markers),
      },
      null,
      2,
    ),
  );
}

main();
