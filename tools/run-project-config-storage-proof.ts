#!/usr/bin/env node
/**
 * Assemble and run the /tecm8.prj storage loader proof in Debug80's TEC-1G
 * runtime with MON3 ROM and FAT32-backed SD image.
 */

const { execFileSync } = require('node:child_process');
const { existsSync, writeFileSync } = require('node:fs');
const { resolve } = require('node:path');

import type { D8Symbol, ProofHarness } from './proof/harness';

const harness: ProofHarness = require('./proof/harness.ts');
const {
  TECM8_ROOT,
  MON3_ROM_PATH,
  MON3_INTERFACE,
  NODE_TS_ARGS,
  PROOF_PASS,
  compileAzm,
  symbolAddress,
  loadTec1gRuntime,
  runUntil,
  readAsciiZ,
  resultToString,
  requireTm8Format,
  createProofImage,
  writeVolumeIntoImage,
} = harness;

const PROOF_SOURCE = resolve(TECM8_ROOT, 'proofs/project-config/project-config-storage-proof.asm');
const LAST_RUN = resolve(TECM8_ROOT, 'proofs/project-config/storage-last-run.json');
const PROOF_FAIL = 0xe0;
const PROJECT_CFG_ERR_HEADER = 0x01;
const MAX_INSTRUCTIONS = 20_000_000;

type ProofCase = {
  name: string;
  imageName: string;
  configBytes: Buffer;
  mutateVolume?: (volume: Buffer) => void;
  expectedResult: number;
  expectedMainPath?: string;
};

function compileProof(): Promise<{ bytes: Uint8Array; symbols: D8Symbol[] }> {
  return compileAzm(PROOF_SOURCE, 'project-config-storage-proof', {
    interfaces: [MON3_INTERFACE],
  });
}

function ensureImage(proofCase: ProofCase): string {
  const imagePath = resolve(TECM8_ROOT, `proofs/project-config/${proofCase.imageName}.img`);
  createProofImage(imagePath);

  const { createVolumeImage, importFileIntoVolumeImage, readFileFromVolumeImage } = requireTm8Format();
  let volume = createVolumeImage() as Buffer;
  volume = importFileIntoVolumeImage(
    volume,
    '/tecm8.prj',
    proofCase.configBytes,
  );
  volume = importFileIntoVolumeImage(
    volume,
    '/src/main.asm',
    Buffer.from('; project config storage proof fixture\n', 'ascii'),
  );

  const storedConfig = readFileFromVolumeImage(volume, '/tecm8.prj').toString('ascii');
  if (storedConfig !== proofCase.configBytes.toString('ascii')) {
    throw new Error(`bad generated project config: ${JSON.stringify(storedConfig)}`);
  }
  proofCase.mutateVolume?.(volume);

  writeVolumeIntoImage(imagePath, volume);
  return imagePath;
}

function proofCases(): ProofCase[] {
  return [
    {
      name: 'valid project config',
      imageName: 'project-config-valid-fat32',
      configBytes: Buffer.from('tm8project=1\nmain=/src/main.asm\n', 'ascii'),
      expectedResult: PROOF_PASS,
      expectedMainPath: '/src/main.asm',
    },
    {
      name: 'zero-length project config',
      imageName: 'project-config-empty-fat32',
      configBytes: Buffer.alloc(0),
      expectedResult: PROOF_FAIL | PROJECT_CFG_ERR_HEADER,
    },
  ];
}

async function runProofCase(
  proofCase: ProofCase,
  bytes: Uint8Array,
  symbols: D8Symbol[],
): Promise<{ name: string; instructions: number; resultMarker: string; mainPath: string; image: string }> {
  const imagePath = ensureImage(proofCase);
  const doneAddr = symbolAddress(symbols, 'ProofDone');
  const resultAddr = symbolAddress(symbols, 'ResultMarker');
  const mainPathAddr = symbolAddress(symbols, 'MainPathOut');
  const { runtime, platformRuntime } = loadTec1gRuntime(bytes, { imagePath });
  const instructions = runUntil(runtime, platformRuntime, doneAddr, MAX_INSTRUCTIONS);
  const result = runtime.hardware.memory[resultAddr];
  const mainPath = readAsciiZ(runtime.hardware.memory, mainPathAddr);

  if (result !== proofCase.expectedResult) {
    throw new Error(
      `${proofCase.name} failed: marker=${resultToString(result)} expected=${resultToString(proofCase.expectedResult)} mainPath=${JSON.stringify(mainPath)}`,
    );
  }
  if (proofCase.expectedMainPath !== undefined && mainPath !== proofCase.expectedMainPath) {
    throw new Error(`${proofCase.name} main path mismatch: ${JSON.stringify(mainPath)}`);
  }

  return {
    name: proofCase.name,
    instructions,
    resultMarker: resultToString(result),
    mainPath,
    image: imagePath,
  };
}

async function main(): Promise<void> {
  if (!existsSync(MON3_ROM_PATH)) {
    throw new Error(`MON3 ROM not found: ${MON3_ROM_PATH}`);
  }
  const caseName = process.argv[process.argv.indexOf('--case') + 1];
  if (process.argv.includes('--case')) {
    const proofCase = proofCases().find((entry) => entry.imageName === caseName);
    if (!proofCase) {
      throw new Error(`unknown proof case: ${caseName}`);
    }
    const { bytes, symbols } = await compileProof();
    console.log(JSON.stringify(await runProofCase(proofCase, bytes, symbols), null, 2));
    return;
  }

  const cases = proofCases().map((proofCase) => {
    const stdout = execFileSync(
      process.execPath,
      [...NODE_TS_ARGS, __filename, '--case', proofCase.imageName],
      {
        cwd: TECM8_ROOT,
        encoding: 'utf8',
      },
    );
    return JSON.parse(stdout);
  });

  const report = {
    result: 'ok',
    cases,
  };
  writeFileSync(LAST_RUN, JSON.stringify(report, null, 2) + '\n', 'ascii');
  console.log(JSON.stringify(report, null, 2));
}

main().catch((error: unknown) => {
  const message = error instanceof Error ? error.message : String(error);
  console.error(`error: ${message}`);
  process.exit(1);
});
