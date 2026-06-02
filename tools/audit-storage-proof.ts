#!/usr/bin/env node
/**
 * Run the storage-proof audit end to end.
 *
 * The audit checks the current real Debug80 runtime, prepares an isolated
 * patched runtime, then checks the no-shim proof against that patched runtime.
 * It emits a requirement-by-requirement status report for Goal 1.
 */

const { spawnSync } = require('node:child_process');
const { existsSync, readFileSync } = require('node:fs');
const { join, resolve } = require('node:path');

const ZAD_ROOT = resolve(__dirname, '..');
const PATCHED_ROOT = process.env.DEBUG80_PATCHED_ROOT ?? '/private/tmp/zad-debug80-patched-tool';
const REAL_DEBUG80_ROOT = process.env.DEBUG80_ROOT ?? '/Users/johnhardy/projects/debug80';
const PATCH_PATH = resolve(ZAD_ROOT, 'patches/debug80-mon3-sd-spi.patch');
const NODE_TS_ARGS = ['--experimental-strip-types'];

type CommandResult = {
  status: number | null;
  stdout: string;
  stderr: string;
};

type ProofStatus = {
  debug80Root: string;
  pristineImage: 'ok' | 'failed';
  noShimDebug80: { status: 'ok' | 'failed'; failure: string | null };
  shimmedMon3Proof: {
    status: 'ok' | 'failed';
    instructions?: number;
    markers?: Array<{ sector: number; offset: number; marker: string }>;
  };
  goalCompleteWithoutShim: boolean;
};

function runNode(args: string[], env: Record<string, string> = {}): CommandResult {
  const result = spawnSync(process.execPath, [...NODE_TS_ARGS, ...args], {
    cwd: ZAD_ROOT,
    encoding: 'utf8',
    env: { ...process.env, ...env },
  });
  return {
    status: result.status,
    stdout: result.stdout ?? '',
    stderr: result.stderr ?? '',
  };
}

function runCommand(command: string, args: string[], cwd: string): CommandResult {
  const result = spawnSync(command, args, {
    cwd,
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
    process.stderr.write(result.stdout);
    process.stderr.write(result.stderr);
    throw new Error(`${label} failed with exit ${result.status}`);
  }
}

function parseJsonObject<T>(stdout: string, label: string): T {
  const start = stdout.lastIndexOf('\n{');
  const jsonText = (start >= 0 ? stdout.slice(start + 1) : stdout).trim();
  try {
    return JSON.parse(jsonText) as T;
  } catch (error) {
    throw new Error(`could not parse ${label} JSON: ${(error as Error).message}`);
  }
}

function readTextIfPresent(path: string): string | null {
  return existsSync(path) ? readFileSync(path, 'utf8') : null;
}

function inspectSdSpiText(text: string | null) {
  const value = text ?? '';
  return {
    present: text !== null,
    misoBit7: value.includes('return this.ioOut ? 0x80 : 0x00'),
    highCapacityOcrValid: value.includes('this.highCapacity ? 0xc0 : 0x80'),
    preservesMon3ByteIdleCs: value.includes('hasActiveTransaction'),
    resetsOnInactiveCs: /if \(!nextCsActive\) \{\s+this\.resetTransaction\(\);/.test(value),
  };
}

function inspectDebug80Root(root: string) {
  const patchCheck = runCommand('git', ['apply', '--check', PATCH_PATH], root);
  const sourceSdSpi = inspectSdSpiText(readTextIfPresent(join(root, 'src/platforms/tec1g/sd-spi.ts')));
  const compiledSdSpi = inspectSdSpiText(readTextIfPresent(join(root, 'out/platforms/tec1g/sd-spi.js')));
  const patchState =
    patchCheck.status === 0
      ? 'can-apply'
      : sourceSdSpi.preservesMon3ByteIdleCs && !sourceSdSpi.resetsOnInactiveCs
        ? 'already-present'
        : 'does-not-apply';
  return {
    root,
    patchState,
    patchAppliesCleanly: patchCheck.status === 0,
    patchCheckFailure:
      patchCheck.status === 0 ? null : `${patchCheck.stdout}${patchCheck.stderr}`.trim(),
    sourceSdSpi,
    compiledSdSpi,
  };
}

function statusToRequirementReport(real: ProofStatus, patched: ProofStatus) {
  const proofStatus = real.goalCompleteWithoutShim ? real : patched;
  const proofMarkers = proofStatus.shimmedMon3Proof.markers ?? [];
  const sectors = new Set(proofMarkers.map((marker) => marker.sector));
  const layoutSectorsCovered = [0, 8, 16, 79, 80].every((sector) => sectors.has(sector));
  const noShimOk = proofStatus.goalCompleteWithoutShim && proofStatus.noShimDebug80.status === 'ok';

  return [
    {
      requirement: 'Host-created VOLUME.ZAD exists on emulated/card FAT32 volume',
      status: patched.pristineImage === 'ok' ? 'proven' : 'failed',
      evidence: 'tools/create-storage-proof-image.ts generated and verified the FAT32 image.',
    },
    {
      requirement: 'MON3 or Debug80/MON3 path opens the existing file',
      status: noShimOk ? 'proven' : 'not-proven',
      evidence: noShimOk
        ? `no-shim proof passed with DEBUG80_ROOT=${proofStatus.debug80Root}`
        : proofStatus.noShimDebug80.failure,
    },
    {
      requirement: 'TEC-side code reads arbitrary 512-byte sectors inside VOLUME.ZAD',
      status: noShimOk && layoutSectorsCovered ? 'proven' : 'not-proven',
      evidence: `verified sectors: ${[...sectors].sort((a, b) => a - b).join(', ')}`,
    },
    {
      requirement: 'TEC-side code writes back sectors that were previously read',
      status: noShimOk && layoutSectorsCovered ? 'proven' : 'not-proven',
      evidence: 'MON3 writeSector markers were verified from host-side image bytes.',
    },
    {
      requirement: 'Host can verify writes afterward',
      status: proofMarkers.length >= 5 ? 'proven' : 'not-proven',
      evidence: proofMarkers,
    },
    {
      requirement: 'Proposed layout offsets are reliable',
      status: layoutSectorsCovered ? 'proven' : 'not-proven',
      evidence: 'superblock, allocation table, catalog start/end, and first data sector markers verified.',
    },
    {
      requirement: 'Real Debug80 checkout passes no-shim path',
      status: real.goalCompleteWithoutShim ? 'proven' : 'pending-debug80-fix',
      evidence: real.noShimDebug80.failure,
    },
  ];
}

function main(): void {
  const realStatusResult = runNode(['tools/check-storage-proof-status.ts']);
  requireSuccess(realStatusResult, 'real Debug80 status check');
  const realStatus = parseJsonObject<ProofStatus>(realStatusResult.stdout, 'real Debug80 status');

  const prepResult = runNode(['tools/prepare-patched-debug80-runtime.ts', '--target', PATCHED_ROOT]);
  requireSuccess(prepResult, 'patched Debug80 preparation');

  const patchedStatusResult = runNode(['tools/check-storage-proof-status.ts', '--strict'], {
    DEBUG80_ROOT: PATCHED_ROOT,
  });
  requireSuccess(patchedStatusResult, 'patched Debug80 status check');
  const patchedStatus = parseJsonObject<ProofStatus>(patchedStatusResult.stdout, 'patched Debug80 status');

  console.log(
    JSON.stringify(
      {
        result: 'ok',
        realDebug80: realStatus,
        realDebug80Diagnostics: inspectDebug80Root(REAL_DEBUG80_ROOT),
        patchedDebug80: patchedStatus,
        patchedDebug80Diagnostics: inspectDebug80Root(PATCHED_ROOT),
        requirements: statusToRequirementReport(realStatus, patchedStatus),
      },
      null,
      2,
    ),
  );
}

main();
