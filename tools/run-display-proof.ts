#!/usr/bin/env node
/**
 * Assemble and run the GLCD display smoke proof in Debug80's TEC-1G runtime
 * with MON3 ROM loaded.
 */

const { existsSync, writeFileSync } = require('node:fs');
const { resolve } = require('node:path');

import type { D8Symbol, PlatformRuntime, ProofHarness, Runtime } from './proof/harness';

const harness: ProofHarness = require('./proof/harness.ts');
const {
  TECM8_ROOT,
  MON3_ROM_PATH,
  MON3_INTERFACE,
  PROOF_PASS,
  DISPLAY_Y_ORIGIN,
  compileAzm,
  symbolAddress,
  loadTec1gRuntime,
  runUntil,
  resultToString,
  readCString,
  getGlcdBytes,
  glcdRowHasPixels,
  readCellRows,
  readFontRows,
  assertCellMatchesInvertedFont,
  assertGlcdCellMatchesInvertedFont,
} = harness;

const proofName = process.argv[2] ?? 'glcd-smoke-proof';
if (!/^[a-z0-9-]+$/.test(proofName)) {
  throw new Error(`invalid display proof name: ${proofName}`);
}

const PROOF_SOURCE = resolve(TECM8_ROOT, `proofs/display/${proofName}.asm`);
const LAST_RUN = resolve(TECM8_ROOT, `proofs/display/${proofName}-last-run.json`);
const MAX_INSTRUCTIONS = 5_000_000;

function hasVisibleGlcdPixels(platformRuntime: PlatformRuntime): boolean {
  return getGlcdBytes(platformRuntime).some((value) => value !== 0);
}

function verifyStructuredScreen(runtime: Runtime, platformRuntime: PlatformRuntime): void {
  const glcd = getGlcdBytes(platformRuntime);
  const missingRows = [];
  for (let row = 0; row < 10; row += 1) {
    if (!glcdRowHasPixels(glcd, row)) {
      missingRows.push(row);
    }
  }
  if (missingRows.length > 0) {
    throw new Error(`structured display proof did not render rows: ${missingRows.join(', ')}`);
  }

  const mon3Tgbuf = 0x13c0;
  const rowBytes = 16;
  const textColumnByte = 1;
  const expectedMarkers = [
    { row: 0, pattern: 0xf0, name: 'breakpoint' },
    { row: 1, pattern: 0x80, name: 'current' },
    { row: 2, pattern: 0xc0, name: 'selected' },
    { row: 5, pattern: 0xf0, name: 'breakpoint-current' },
    { row: 7, pattern: 0xc0, name: 'selected' },
  ];

  for (const marker of expectedMarkers) {
    for (let y = 0; y < 6; y += 1) {
      const address = mon3Tgbuf + (marker.row * 6 + DISPLAY_Y_ORIGIN + y) * rowBytes;
      const value = runtime.hardware.memory[address];
      if ((value & marker.pattern) !== marker.pattern) {
        throw new Error(
          `structured display proof missing ${marker.name} gutter bits at 0x${address.toString(16)}: got ${resultToString(value)} expected mask ${resultToString(marker.pattern)}`,
        );
      }

      const glcdOffset = (marker.row * 6 + DISPLAY_Y_ORIGIN + y) * rowBytes;
      const visibleValue = glcd[glcdOffset] ?? 0;
      if ((visibleValue & marker.pattern) !== marker.pattern) {
        throw new Error(
          `structured display proof missing visible ${marker.name} gutter bits at GLCD offset 0x${glcdOffset.toString(16)}: got ${resultToString(visibleValue)} expected mask ${resultToString(marker.pattern)}`,
        );
      }
    }
  }

  assertCellMatchesInvertedFont(runtime.hardware.memory, 1, 0, 'C'.charCodeAt(0));
  assertGlcdCellMatchesInvertedFont(runtime.hardware.memory, glcd, 1, 0, 'C'.charCodeAt(0));
  assertCursorAdjacentMarkerPreserved(runtime.hardware.memory, glcd);

  const expectedTextRows = [
    { row: 0, name: 'first source row' },
    { row: 1, name: 'second source row' },
    { row: 9, name: 'tenth source row' },
  ];

  for (const row of expectedTextRows) {
    let hasTextPixels = false;
    for (let y = 0; y < 6; y += 1) {
      const address = mon3Tgbuf + (row.row * 6 + DISPLAY_Y_ORIGIN + y) * rowBytes + textColumnByte;
      const memoryValue = runtime.hardware.memory[address];
      const glcdOffset = (row.row * 6 + DISPLAY_Y_ORIGIN + y) * rowBytes + textColumnByte;
      const visibleValue = glcd[glcdOffset] ?? 0;
      if (memoryValue !== 0 && visibleValue !== 0) {
        hasTextPixels = true;
      }
    }
    if (!hasTextPixels) {
      throw new Error(`structured display proof did not render ${row.name} text pixels in TGBUF`);
    }
  }

  for (let column = 'ORG 4000H'.length; column < 20; column += 1) {
    if (cellHasPixels(runtime.hardware.memory, 0, column)) {
      throw new Error(`structured display proof left stale pixels after shorter row redraw at column ${column}`);
    }
  }
}

function verifyEditorViewport(runtime: Runtime, platformRuntime: PlatformRuntime, symbols: D8Symbol[]): void {
  const glcd = getGlcdBytes(platformRuntime);
  for (let row = 0; row < 10; row += 1) {
    if (!glcdRowHasPixels(glcd, row)) {
      throw new Error(`editor viewport proof did not render display row: ${row}`);
    }
  }

  const expectedRows = [
    { symbol: 'EditorRowText0', text: 'ORG 4000H' },
    { symbol: 'EditorRowText1', text: 'CALL INIT' },
    { symbol: 'EditorRowText7', text: 'RET' },
    { symbol: 'EditorRowText9', text: 'END' },
  ];
  for (const row of expectedRows) {
    const address = symbolAddress(symbols, row.symbol);
    const actual = readCString(runtime.hardware.memory, address);
    if (actual !== row.text) {
      throw new Error(`editor viewport proof copied ${row.symbol} as "${actual}", expected "${row.text}"`);
    }
  }

  const mon3Tgbuf = 0x13c0;
  const rowBytes = 16;
  const expectedMarker = { row: 9, pattern: 0x80 };
  for (let row = 0; row < 10; row += 1) {
    for (let y = 0; y < 6; y += 1) {
      const address = mon3Tgbuf + (row * 6 + DISPLAY_Y_ORIGIN + y) * rowBytes;
      const value = runtime.hardware.memory[address];
      const glcdOffset = (row * 6 + DISPLAY_Y_ORIGIN + y) * rowBytes;
      const visibleValue = glcd[glcdOffset] ?? 0;
      if (row === expectedMarker.row && (value & expectedMarker.pattern) !== expectedMarker.pattern) {
        throw new Error(
          `editor viewport proof missing current-row gutter bits at 0x${address.toString(16)}: got ${resultToString(value)} expected mask ${resultToString(expectedMarker.pattern)}`,
        );
      }
      if (row === expectedMarker.row && (visibleValue & expectedMarker.pattern) !== expectedMarker.pattern) {
        throw new Error(
          `editor viewport proof missing visible current-row gutter bits at GLCD offset 0x${glcdOffset.toString(16)}: got ${resultToString(visibleValue)} expected mask ${resultToString(expectedMarker.pattern)}`,
        );
      }
      if (row !== expectedMarker.row && (value & 0xf0) !== 0) {
        throw new Error(`editor viewport proof unexpected stale gutter bits at row ${row}: ${resultToString(value)}`);
      }
      if (row !== expectedMarker.row && (visibleValue & 0xf0) !== 0) {
        throw new Error(
          `editor viewport proof unexpected visible stale gutter bits at row ${row}: ${resultToString(visibleValue)}`,
        );
      }
    }
  }
}

function cellHasPixels(memory: Uint8Array, row: number, column: number): boolean {
  const mon3Tgbuf = 0x13c0;
  const rowBytes = 16;
  const textX = 6;
  const cellX = textX + column * 6;
  for (let y = row * 6 + DISPLAY_Y_ORIGIN; y < row * 6 + DISPLAY_Y_ORIGIN + 6; y += 1) {
    for (let x = cellX; x < cellX + 6; x += 1) {
      const address = mon3Tgbuf + y * rowBytes + Math.floor(x / 8);
      const mask = 0x80 >> (x % 8);
      if ((memory[address] & mask) !== 0) {
        return true;
      }
    }
  }
  return false;
}

function assertCellMatchesFont(memory: Uint8Array, row: number, column: number, charCode: number): void {
  const actual = readCellRows(memory, row, column);
  const expected = readFontRows(memory, charCode);
  if (actual.join(',') !== expected.join(',')) {
    throw new Error(
      `GLCD tile proof rendered ${String.fromCharCode(charCode)} as [${actual.join(',')}], expected font rows [${expected.join(',')}]`,
    );
  }
}

function assertCursorAdjacentMarkerPreserved(memory: Uint8Array, glcd: number[]): void {
  const markers = [
    { address: 0x13e4, glcdOffset: 36, expected: 0x5a, name: 'one-byte cursor adjacent byte' },
    { address: 0x13f0, glcdOffset: 48, expected: 0xf5, name: 'far-right cursor next scanline byte' },
  ];
  for (const marker of markers) {
    const memoryValue = memory[marker.address];
    if (memoryValue !== marker.expected) {
      throw new Error(
        `structured display proof did not preserve ${marker.name} in TGBUF: got ${resultToString(memoryValue)} expected ${resultToString(marker.expected)}`,
      );
    }
    const glcdValue = glcd[marker.glcdOffset] ?? 0;
    if (glcdValue !== marker.expected) {
      throw new Error(
        `structured display proof did not preserve visible ${marker.name}: got ${resultToString(glcdValue)} expected ${resultToString(marker.expected)}`,
      );
    }
  }
}

function verifyGlcdTile(runtime: Runtime, platformRuntime: PlatformRuntime): void {
  if (cellHasPixels(runtime.hardware.memory, 1, 0)) {
    throw new Error('GLCD tile proof left stale pixels in a cleared cell');
  }
  if (!cellHasPixels(runtime.hardware.memory, 1, 1)) {
    throw new Error('GLCD tile proof did not draw the adjacent cell');
  }
  if (!cellHasPixels(runtime.hardware.memory, 2, 0) || !cellHasPixels(runtime.hardware.memory, 2, 1)) {
    throw new Error('GLCD tile proof did not draw a text run');
  }
  assertCellMatchesFont(runtime.hardware.memory, 1, 1, 'B'.charCodeAt(0));
  assertCellMatchesFont(runtime.hardware.memory, 2, 0, 'O'.charCodeAt(0));
  assertCellMatchesFont(runtime.hardware.memory, 2, 1, 'K'.charCodeAt(0));

  const glcd = getGlcdBytes(platformRuntime);
  if (!glcdRowHasPixels(glcd, 1) || !glcdRowHasPixels(glcd, 2)) {
    throw new Error('GLCD tile proof did not flush tile rows to the visible GLCD');
  }
}

async function main(): Promise<void> {
  if (!existsSync(MON3_ROM_PATH)) {
    throw new Error(`MON3 ROM not found: ${MON3_ROM_PATH}`);
  }

  const { bytes, symbols } = await compileAzm(PROOF_SOURCE, proofName, {
    interfaces: [MON3_INTERFACE],
  });
  const doneAddr = symbolAddress(symbols, 'ProofDone');
  const resultAddr = symbolAddress(symbols, 'ResultMarker');
  const { runtime, platformRuntime } = loadTec1gRuntime(bytes);
  const instructions = runUntil(runtime, platformRuntime, doneAddr, MAX_INSTRUCTIONS);
  const result = runtime.hardware.memory[resultAddr];
  const visiblePixels = hasVisibleGlcdPixels(platformRuntime);

  if (result !== PROOF_PASS) {
    throw new Error(`display proof failed: marker=${resultToString(result)}`);
  }
  if (!visiblePixels) {
    throw new Error('display proof did not update Debug80 GLCD pixels');
  }
  if (proofName === 'structured-screen-proof') {
    verifyStructuredScreen(runtime, platformRuntime);
  }
  if (proofName === 'glcd-tile-proof') {
    verifyGlcdTile(runtime, platformRuntime);
  }
  if (proofName === 'editor-viewport-proof') {
    verifyEditorViewport(runtime, platformRuntime, symbols);
  }

  const report = {
    result: 'ok',
    proof: proofName,
    instructions,
    resultMarker: resultToString(result),
    visiblePixels,
  };
  writeFileSync(LAST_RUN, JSON.stringify(report, null, 2) + '\n', 'ascii');
  console.log(JSON.stringify(report, null, 2));
}

main().catch((error: unknown) => {
  const message = error instanceof Error ? error.message : String(error);
  console.error(`error: ${message}`);
  process.exit(1);
});
