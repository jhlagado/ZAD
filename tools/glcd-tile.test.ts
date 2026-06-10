const { strict: assert } = require('node:assert');
const { test } = require('node:test');

import type { TestSupport } from './test-support';

const { readRepoFile, repoFileExists }: TestSupport = require('./test-support.ts');

test('GLCD tile layer exposes direct cell primitives and contracts', () => {
  const source = readRepoFile('src/glcd-tile.asm');

  for (const label of [
    'GlcdTileClearCell',
    'GlcdTileDrawCell',
    'GlcdTileDrawTextRun',
    'GlcdTileClearTextRow',
    'GlcdTileFlushFull',
    'GlcdTilePrepareCell',
  ]) {
    assert.match(source, new RegExp(`^@${label}:`, 'm'));
  }

  assert.match(source, /^TECM8_GLCD_TILE_COLUMNS\s+\.equ\s+20$/m);
  assert.match(source, /^TECM8_GLCD_TILE_ROWS\s+\.equ\s+10$/m);
  assert.match(source, /^TECM8_GLCD_TILE_WIDTH\s+\.equ\s+6$/m);
  assert.match(source, /^TECM8_GLCD_TILE_HEIGHT\s+\.equ\s+6$/m);
  assert.match(source, /^TECM8_GLCD_TILE_TEXT_X\s+\.equ\s+6$/m);
  assert.match(source, /^TECM8_GLCD_TILE_Y_ORIGIN\s+\.equ\s+2$/m);
  assert.match(source, /^TECM8_GLCD_TILE_TGBUF\s+\.equ\s+0x13C0$/m);
  assert.match(source, /^TECM8_GLCD_TILE_VPORT\s+\.equ\s+0x0E13$/m);
  assert.match(source, /^TECM8_GLCD_TILE_FONT_DATA\s+\.equ\s+0xDD9B$/m);
  assert.match(source, /GlcdTileSetMaskTable:/);
  assert.match(source, /GlcdTileClearMaskTable:/);
  assert.match(source, /LD\s+HL,TECM8_GLCD_TILE_TGBUF\n\s+LD\s+\(TECM8_GLCD_TILE_VPORT\),HL\n\s+CALL\s+BiosDisplayUpdate/);
  assert.match(source, /CALL\s+BiosDisplayUpdate/);
});

test('GLCD tile layer does not call MON3 terminal glyph policy', () => {
  const source = readRepoFile('src/glcd-tile.asm');

  assert.doesNotMatch(source, /BiosDisplayDrawCharAt/);
  assert.doesNotMatch(source, /MON3_GLCD_DRAW_GRAPHIC/);
  assert.doesNotMatch(source, /MON3_GLCD_SEND_CHAR_TO_LCD/);
  assert.doesNotMatch(source, /MON3_GLCD_SEND_STRING_TO_LCD/);
});

test('GLCD tile proof is wired into package checks', () => {
  assert.ok(repoFileExists('proofs/display/glcd-tile-proof.asm'));
  const proof = readRepoFile('proofs/display/glcd-tile-proof.asm');
  const runner = readRepoFile('tools/run-display-proof.ts');
  const packageJson = readRepoFile('package.json');

  assert.match(proof, /CALL\s+GlcdTileDrawCell/);
  assert.match(proof, /LD\s+A,'A'\n\s+LD\s+B,1\n\s+LD\s+C,0\n\s+CALL\s+GlcdTileDrawCell[\s\S]*LD\s+A,'B'\n\s+LD\s+B,1\n\s+LD\s+C,0\n\s+CALL\s+GlcdTileDrawCell/);
  assert.match(proof, /CALL\s+GlcdTileClearCell/);
  assert.match(proof, /CALL\s+GlcdTileDrawTextRun/);
  assert.match(proof, /CALL\s+GlcdTileFlushFull/);
  assert.match(proof, /\.include\s+"..\/..\/src\/glcd-tile\.asm"/);
  assert.match(runner, /verifyGlcdTile/);
  assert.match(packageJson, /"proof:display:glcd-tile"/);
  assert.match(packageJson, /proof:display:glcd-tile/);
});
