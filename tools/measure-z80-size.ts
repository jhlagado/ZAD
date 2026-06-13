#!/usr/bin/env node
/**
 * Assemble the TECM8 Z80 entry and report rough binary/module size pressure.
 */

const { existsSync, readFileSync, statSync } = require('node:fs');
const { resolve } = require('node:path');

const TECM8_ROOT = resolve(__dirname, '..');
const AZM_ROOT = process.env.AZM_ROOT ? resolve(process.env.AZM_ROOT) : undefined;
const SOURCE_FILE = resolve(TECM8_ROOT, 'src/main.asm');
const MON3_INTERFACE = resolve(TECM8_ROOT, 'src/mon3.asmi');
const BUILD_BIN = resolve(TECM8_ROOT, 'build/main.bin');
const BANK_BYTES = 16 * 1024;
const BANK_START = 0x4000;
const BANK_END = BANK_START + BANK_BYTES;

type Diagnostic = {
  id?: string;
  message?: string;
  severity?: string;
};

type D8Segment = {
  start: number;
  end: number;
  kind?: string;
};

type D8File = {
  segments?: D8Segment[];
};

type D8Map = {
  files?: Record<string, D8File>;
};

type CompileResult = {
  diagnostics: Diagnostic[];
  artifacts: Array<{ kind: string; bytes?: Uint8Array; json?: D8Map }>;
};

type Interval = {
  start: number;
  end: number;
};

function toHex(value: number): string {
  return `0x${value.toString(16).toUpperCase().padStart(4, '0')}`;
}

function mergeIntervals(intervals: Interval[]): Interval[] {
  const sorted = intervals
    .filter((interval) => interval.end > interval.start)
    .sort((left, right) => left.start - right.start || left.end - right.end);
  const merged: Interval[] = [];

  for (const interval of sorted) {
    const last = merged[merged.length - 1];
    if (!last || interval.start > last.end) {
      merged.push({ ...interval });
      continue;
    }
    if (interval.end > last.end) {
      last.end = interval.end;
    }
  }

  return merged;
}

function summarizeFile(file: string, entry: D8File): {
  file: string;
  mappedBytes: number;
  segments: number;
  start?: string;
  endExclusive?: string;
} {
  const segments = entry.segments ?? [];
  const intervals = mergeIntervals(segments.map((segment) => ({
    start: segment.start,
    end: segment.end,
  })));
  const mappedBytes = intervals.reduce((total, interval) => total + interval.end - interval.start, 0);
  const start = intervals.length > 0 ? Math.min(...intervals.map((interval) => interval.start)) : undefined;
  const end = intervals.length > 0 ? Math.max(...intervals.map((interval) => interval.end)) : undefined;

  return {
    file,
    mappedBytes,
    segments: segments.length,
    ...(start === undefined ? {} : { start: toHex(start) }),
    ...(end === undefined ? {} : { endExclusive: toHex(end) }),
  };
}

function summarizeAddressSpan(files: Record<string, D8File>): {
  addressStart?: number;
  addressEndExclusive?: number;
  addressSpanBytes?: number;
} {
  const intervals = mergeIntervals(Object.values(files).flatMap((file) => (
    file.segments ?? []
  )).map((segment) => ({
    start: segment.start,
    end: segment.end,
  })));
  if (intervals.length === 0) {
    return {};
  }

  const addressStart = Math.min(...intervals.map((interval) => interval.start));
  const addressEndExclusive = Math.max(...intervals.map((interval) => interval.end));
  return {
    addressStart,
    addressEndExclusive,
    addressSpanBytes: addressEndExclusive - addressStart,
  };
}

async function compileMain(): Promise<{ bytes: Uint8Array; d8m: D8Map }> {
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
      d8mInputs: { bin: 'build/main.bin' },
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

  return { bytes: bin.bytes, d8m: d8m?.json ?? {} };
}

async function main(): Promise<void> {
  const { bytes, d8m } = await compileMain();
  const fileSummaries = Object.entries(d8m.files ?? {})
    .map(([file, entry]) => summarizeFile(file, entry))
    .filter((entry) => entry.mappedBytes > 0)
    .sort((left, right) => right.mappedBytes - left.mappedBytes || left.file.localeCompare(right.file));
  const existingBuildBytes = existsSync(BUILD_BIN) ? statSync(BUILD_BIN).size : undefined;
  const existingBuild = existsSync(BUILD_BIN) ? readFileSync(BUILD_BIN) : undefined;
  const addressSpan = summarizeAddressSpan(d8m.files ?? {});
  const fitsIn16KBank = addressSpan.addressStart === undefined ||
    addressSpan.addressEndExclusive === undefined
    ? bytes.length <= BANK_BYTES
    : addressSpan.addressStart >= BANK_START && addressSpan.addressEndExclusive <= BANK_END;
  const remainingIn16KBank = addressSpan.addressEndExclusive === undefined
    ? BANK_BYTES - bytes.length
    : BANK_END - addressSpan.addressEndExclusive;

  console.log(JSON.stringify({
    result: 'ok',
    source: SOURCE_FILE,
    bytes: bytes.length,
    bankBytes: BANK_BYTES,
    bankStart: toHex(BANK_START),
    bankEndExclusive: toHex(BANK_END),
    addressStart: addressSpan.addressStart === undefined ? undefined : toHex(addressSpan.addressStart),
    addressEndExclusive: addressSpan.addressEndExclusive === undefined ? undefined : toHex(addressSpan.addressEndExclusive),
    addressSpanBytes: addressSpan.addressSpanBytes,
    fitsIn16KBank,
    remainingIn16KBank,
    existingBuildBytes,
    buildMatchesSource: existingBuild === undefined ? undefined : Buffer.from(bytes).equals(existingBuild),
    sourceMapCoverageNote: 'mappedBytes are non-exclusive D8 source-map coverage, not module ownership; include-line mappings can overlap.',
    sourceMapCoverage: fileSummaries,
  }, null, 2));
}

main().catch((error: unknown) => {
  console.error(error);
  process.exitCode = 1;
});
