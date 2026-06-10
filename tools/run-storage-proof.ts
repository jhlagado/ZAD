#!/usr/bin/env node
/**
 * Run the TM8 storage proof against Debug80's TEC-1G runtime and MON3 ROM.
 *
 * This intentionally drives the same MON3 file API path TECM8 expects to use:
 * openFile -> readSector -> writeSector. It does not implement TM8 FS logic.
 */

const { existsSync, readFileSync, writeFileSync } = require('node:fs');
const { resolve } = require('node:path');

import type { PlatformRuntime, ProofHarness, Runtime } from './proof/harness';

const harness: ProofHarness = require('./proof/harness.ts');
const {
  TECM8_ROOT,
  MON3_ROM_PATH,
  APP_START,
  createProofImage,
  imageManifest,
  loadTec1gRuntime,
} = harness;

const IMAGE_PATH = resolve(TECM8_ROOT, 'proofs/storage/tm8proof-fat32.img');

const MON3_OPEN_FILE_ADDR = 0xf5a1;
const MON3_READ_SECTOR_ADDR = 0xf5d5;
const MON3_WRITE_SECTOR_ADDR = 0xf66d;
const DISK_BUFF = 0x0600;
const SECTOR_SIZE = 512;

const MARKERS = [
  { sector: 0, label: 'markerSuperblock', text: 'TM8 MON3 WRITE SUPERBLOCK 0000' },
  { sector: 8, label: 'markerAlloc', text: 'TM8 MON3 WRITE ALLOC 0008' },
  { sector: 16, label: 'markerCatalogFirst', text: 'TM8 MON3 WRITE CATALOG 0016' },
  { sector: 79, label: 'markerCatalogLast', text: 'TM8 MON3 WRITE CATALOG 0079' },
  { sector: 80, label: 'markerDataFirst', text: 'TM8 MON3 WRITE DATA 0080' },
] as const;
const TRACE_POINTS: Record<number, string> = {
  0xf197: 'FATmount',
  0xf255: 'FATerror1: MBR read error',
  0xf25a: 'FATerror2: bad MBR signature',
  0xf25f: 'FATerror3: BPB read error',
  0xf264: 'FATerror4: BPB bytes-per-sector error',
  0xf269: 'FATerror5: root/file sector read/write error',
  0xf26e: 'FATerror6: file not found',
  0xf273: 'FATerror7: bad Intel HEX checksum',
  0xf278: 'FATerror8: no SD card',
  0xf27d: 'FATerror9: OCR read fail',
  0xf282: 'FATerror10: invalid SD card',
  0xf287: 'FATerror11: CMD16 failed',
  0xf28c: 'FATerror12: address too large',
  0xf291: 'FATerror dispatch',
  0xf02c: 'initDisk',
  0xf18b: 'FATmount',
  0xf296: 'FATgetRootDir',
  0xf3ea: 'FATgetRootDir done/error check',
  0xf5a1: 'openFile',
  0xf5d5: 'readSector',
  0xf66d: 'writeSector',
  0xf771: 'checkSDCardPresent',
  0xf803: 'initSD',
  0xc5d1: 'scanKeys',
  0xc656: 'scanKeysWait',
  0xc575: 'display delay loop',
};

function low(value: number): number {
  return value & 0xff;
}

function high(value: number): number {
  return (value >> 8) & 0xff;
}

function asciiZ(text: string): number[] {
  return [...Buffer.from(text, 'ascii'), 0x00];
}

function buildProofProgram(): { bytes: Uint8Array; doneAddr: number } {
  const bytes: number[] = [];
  const push = (...values: number[]): void => {
    bytes.push(...values.map((value) => value & 0xff));
  };
  const ldHl = (addr: number): void => push(0x21, low(addr), high(addr));
  const ldDe = (addr: number): void => push(0x11, low(addr), high(addr));
  const ldBc = (value: number): void => push(0x01, low(value), high(value));
  const call = (addr: number): void => push(0xcd, low(addr), high(addr));
  const ldir = (): void => push(0xed, 0xb0);

  const placeholders: Record<string, number> = {};
  const labels: Record<string, number> = {};
  const label = (name: string): void => {
    labels[name] = APP_START + bytes.length;
  };
  const ldHlLabel = (name: string): void => {
    push(0x21, 0x00, 0x00);
    placeholders[`${name}:${bytes.length - 2}`] = bytes.length - 2;
  };
  const jpLabel = (name: string): void => {
    push(0xc3, 0x00, 0x00);
    placeholders[`${name}:${bytes.length - 2}`] = bytes.length - 2;
  };

  ldHlLabel('volumeName');
  call(MON3_OPEN_FILE_ADDR);

  for (const marker of MARKERS) {
    const byteOffset = marker.sector * SECTOR_SIZE;
    ldHl((byteOffset >>> 16) & 0xffff);
    ldDe(byteOffset & 0xffff);
    call(MON3_READ_SECTOR_ADDR);

    ldHlLabel(marker.label);
    ldDe(DISK_BUFF);
    ldBc(marker.text.length + 1);
    ldir();
    call(MON3_WRITE_SECTOR_ADDR);
  }

  label('done');
  jpLabel('done');

  label('volumeName');
  push(...asciiZ('VOLUME.TM8'));
  for (const marker of MARKERS) {
    label(marker.label);
    push(...asciiZ(marker.text));
  }

  for (const [key, offset] of Object.entries(placeholders)) {
    const [name] = key.split(':');
    const addr = labels[name ?? ''];
    if (addr === undefined) {
      throw new Error(`missing label ${name}`);
    }
    bytes[offset] = low(addr);
    bytes[offset + 1] = high(addr);
  }
  if (labels.done === undefined) {
    throw new Error('missing done label');
  }
  return { bytes: Uint8Array.from(bytes), doneAddr: labels.done };
}

function ensureImage(): void {
  createProofImage(IMAGE_PATH);
}

function loadRuntime(): { runtime: Runtime; platformRuntime: PlatformRuntime; doneAddr: number } {
  const proofProgram = buildProofProgram();
  const { runtime, platformRuntime } = loadTec1gRuntime(proofProgram.bytes, { imagePath: IMAGE_PATH });
  return { runtime, platformRuntime, doneAddr: proofProgram.doneAddr };
}

function runProof(runtime: Runtime, platformRuntime: PlatformRuntime, doneAddr: number): number {
  const maxInstructions = 20_000_000;
  const seenTracePoints = new Set<number>();
  const recentPcs: number[] = [];
  for (let i = 0; i < maxInstructions; i += 1) {
    const pc = runtime.cpu.pc & 0xffff;
    recentPcs.push(pc);
    if (recentPcs.length > 48) {
      recentPcs.shift();
    }
    const trace = TRACE_POINTS[pc];
    if (trace !== undefined && !seenTracePoints.has(pc)) {
      seenTracePoints.add(pc);
      console.error(
        `[trace] ${i} pc=0x${pc.toString(16).padStart(4, '0')} ${trace}`,
      );
      if (pc === 0xf282) {
        const ocr = [...runtime.hardware.memory.subarray(DISK_BUFF, DISK_BUFF + 4)]
          .map((value) => `0x${value.toString(16).padStart(2, '0')}`)
          .join(' ');
        throw new Error(`MON3 rejected SD OCR at instruction ${i}; DISK_BUFF=${ocr}`);
      }
      if (pc === 0xc575 || pc === 0xc5d1 || pc === 0xc656) {
        const stack = [];
        for (let offset = 0; offset < 16; offset += 2) {
          const lo = runtime.hardware.memRead?.((runtime.cpu.sp + offset) & 0xffff) ?? 0;
          const hi = runtime.hardware.memRead?.((runtime.cpu.sp + offset + 1) & 0xffff) ?? 0;
          stack.push(`0x${((hi << 8) | lo).toString(16).padStart(4, '0')}`);
        }
        const recent = recentPcs.map((entry) => `0x${entry.toString(16).padStart(4, '0')}`).join(' ');
        throw new Error(
          `entered MON3 UI wait path (${trace}) at instruction ${i}; regs=` +
            `AF? A=0x${runtime.cpu.a.toString(16)} BC=0x${(((runtime.cpu.b << 8) | runtime.cpu.c) & 0xffff).toString(16)} ` +
            `DE=0x${(((runtime.cpu.d << 8) | runtime.cpu.e) & 0xffff).toString(16)} ` +
            `HL=0x${(((runtime.cpu.h << 8) | runtime.cpu.l) & 0xffff).toString(16)} ` +
            `SP=0x${runtime.cpu.sp.toString(16)} stack=${stack.join(',')} recent=${recent}`,
        );
      }
    }
    if (pc === doneAddr) {
      return i;
    }
    const result = runtime.step();
    platformRuntime.recordCycles(result.cycles ?? 0);
  }
  const recent = recentPcs.map((pc) => `0x${pc.toString(16).padStart(4, '0')}`).join(' ');
  throw new Error(
    `proof did not reach done at 0x${doneAddr.toString(16)}; pc=0x${runtime.cpu.pc.toString(16)} recent=${recent}`,
  );
}

function verifyMarkers(): Array<{ sector: number; offset: number; marker: string }> {
  const manifest = imageManifest(IMAGE_PATH);
  const image = readFileSync(IMAGE_PATH);
  return MARKERS.map((marker) => {
    const offset = manifest.volume_start_byte_offset + marker.sector * SECTOR_SIZE;
    const actual = image.subarray(offset, offset + marker.text.length).toString('ascii');
    if (actual !== marker.text) {
      throw new Error(`sector ${marker.sector} marker mismatch: ${JSON.stringify(actual)}`);
    }
    return { sector: marker.sector, offset, marker: marker.text };
  });
}

function main(): void {
  if (!existsSync(MON3_ROM_PATH)) {
    throw new Error(`MON3 ROM not found: ${MON3_ROM_PATH}`);
  }
  ensureImage();
  const { runtime, platformRuntime, doneAddr } = loadRuntime();
  const instructions = runProof(runtime, platformRuntime, doneAddr);
  const markers = verifyMarkers();
  writeFileSync(
    resolve(TECM8_ROOT, 'proofs/storage/last-run.json'),
    JSON.stringify({ instructions, doneAddr, markers }, null, 2) + '\n',
    'ascii',
  );
  console.log(
    JSON.stringify(
      {
        result: 'ok',
        instructions,
        doneAddr,
        markers,
      },
      null,
      2,
    ),
  );
}

main();
