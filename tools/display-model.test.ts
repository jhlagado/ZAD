const { strict: assert } = require('node:assert');
const { existsSync, readFileSync } = require('node:fs');
const { resolve } = require('node:path');
const { test } = require('node:test');

const root = resolve(__dirname, '..');

function readRepoFile(path: string): string {
  return readFileSync(resolve(root, path), 'utf8');
}

test('editor design documents the structured display model constants', () => {
  const docs = readRepoFile('docs/editor-design.md');

  for (const phrase of [
    'TECM8_DISPLAY_GLCD_COLUMNS',
    'TECM8_DISPLAY_GLCD_ROWS',
    'TECM8_DISPLAY_EDIT_ROWS',
    'TECM8_DISPLAY_GUTTER_PIXELS',
    'TECM8_DISPLAY_Y_ORIGIN',
    'TECM8_DISPLAY_STATUS_ROW',
    'TECM8_DISPLAY_MARKER_BREAKPOINT',
    'TECM8_DISPLAY_MARKER_CURRENT',
  ]) {
    assert.match(docs, new RegExp(`\\b${phrase}\\b`));
  }
});

test('structured display model has assembly entry points and contracts', () => {
  const source = readRepoFile('src/display-model.asm');

  for (const label of [
    'DisplayInit',
    'DisplayRenderScreen',
    'DisplayRenderLine',
    'DisplayRenderGutter',
    'DisplayRenderCursorCell',
    'DisplayEraseCursorCell',
  ]) {
    assert.match(source, new RegExp(`^@${label}:`, 'm'));
  }
  assert.match(source, /;!\s+out\s+carry\n;!\s+clobbers\s+A,BC,DE,HL,zero,sign,parity,halfCarry\n@DisplayInit:/);
  assert.match(source, /;!\s+in\s+HL\n;!\s+out\s+carry\n;!\s+clobbers\s+A,BC,DE,HL,zero,sign,parity,halfCarry\n@DisplayRenderScreen:/);
  assert.match(source, /;!\s+in\s+A,C,HL\n;!\s+out\s+carry\n;!\s+clobbers\s+A,BC,DE,HL,zero,sign,parity,halfCarry\n@DisplayRenderLine:/);
  assert.match(source, /;!\s+in\s+A,C\n;!\s+out\s+carry\n;!\s+clobbers\s+A,BC,DE,HL,zero,sign,parity,halfCarry\n@DisplayRenderGutter:/);

  for (const constant of [
    'TECM8_DISPLAY_GLCD_COLUMNS',
    'TECM8_DISPLAY_GLCD_ROWS',
    'TECM8_DISPLAY_EDIT_ROWS',
    'TECM8_DISPLAY_GUTTER_PIXELS',
    'TECM8_DISPLAY_Y_ORIGIN',
    'TECM8_DISPLAY_Y_ORIGIN_BYTES',
    'TECM8_DISPLAY_STATUS_ROW',
  ]) {
    assert.match(source, new RegExp(`^${constant}\\s+\\.equ`, 'm'));
  }
  assert.match(source, /^TECM8_DISPLAY_Y_ORIGIN\s+\.equ\s+2$/m);
  assert.match(source, /^TECM8_DISPLAY_EDIT_ROWS\s+\.equ\s+10$/m);
  assert.match(source, /^TECM8_DISPLAY_STATUS_ROW\s+\.equ\s+9$/m);
  assert.match(source, /^TECM8_DISPLAY_Y_ORIGIN_BYTES\s+\.equ\s+TECM8_DISPLAY_Y_ORIGIN \* TECM8_DISPLAY_ROW_BYTES$/m);
  assert.match(source, /^MON3_TGBUF\s+\.equ\s+0x13C0$/m);
  assert.match(source, /@DisplayRenderGutter:\n\s+LD\s+\(DisplayRow\),A/);
  assert.match(source, /@DisplayRenderScreen:\n\s+LD\s+A,\(DisplayRenderScreenCount\)\n\s+INC\s+A\n\s+LD\s+\(DisplayRenderScreenCount\),A\n\s+LD\s+\(DisplayCursor\),HL\n\s+LD\s+A,TECM8_DISPLAY_EDIT_ROWS/);
  assert.match(source, /@DisplayInit:\n\s+CALL\s+BiosDisplayInit\n\s+RET\s+C\n\s+CALL\s+BiosDisplayClear/);
  assert.doesNotMatch(source, /TECM8_DISPLAY_TOP_ROW/);
  assert.doesNotMatch(source, /TECM8_DISPLAY_FIRST_EDIT_ROW/);
  assert.doesNotMatch(source, /TECM8_DISPLAY_BOTTOM_ROW/);
  assert.match(source, /AND\s+0x0F/);
  assert.match(source, /@DisplayRenderCursorCell:/);
  assert.match(source, /@DisplayEraseCursorCell:/);
  assert.match(source, /CP\s+TECM8_DISPLAY_EDIT_ROWS/);
  assert.match(source, /CP\s+TECM8_DISPLAY_MAX_TEXT_CHARS/);
  assert.doesNotMatch(source, /CALL\s+GlcdTileFlushRow/);
  assert.match(source, /CALL\s+GlcdTileMarkCellDirty/);
  assert.match(source, /DisplayCursorSavedBytes:/);
  assert.match(source, /DisplayRenderScreenCount:/);
  assert.match(source, /LD\s+\(DisplayCursorOriginalByte\),A/);
  assert.match(source, /CALL\s+GlcdTileClearTextRow/);
  assert.match(source, /CALL\s+GlcdTileDrawTextRun/);
  assert.doesNotMatch(source, /CALL\s+BiosDisplayDrawCharAt/);
  assert.match(source, /LD\s+HL,MON3_TGBUF\n\s+LD\s+DE,TECM8_DISPLAY_Y_ORIGIN_BYTES\n\s+ADD\s+HL,DE\n\s+LD\s+DE,TECM8_DISPLAY_ROW_STRIDE/);
  assert.doesNotMatch(source, /CALL\s+BiosDisplayPutString/);
});

test('structured GLCD proof calls the display model and renders markers', () => {
  assert.ok(existsSync(resolve(root, 'proofs/display/structured-screen-proof.asm')));
  const source = readRepoFile('proofs/display/structured-screen-proof.asm');

  assert.match(source, /CALL\s+DisplayInit/);
  assert.match(source, /CALL\s+DisplayRenderScreen/);
  assert.match(source, /CALL\s+DisplayRenderLine/);
  assert.match(source, /LD\s+HL,0x1000\n\s+LD\s+\(MON3_VPORT\),HL/);
  assert.match(source, /CALL\s+GlcdTileFlushFull/);
  assert.match(source, /\.include\s+"..\/..\/src\/glcd-tile\.asm"/);
  assert.match(source, /\bTECM8_DISPLAY_MARKER_BREAKPOINT\b/);
  assert.match(source, /\bTECM8_DISPLAY_MARKER_CURRENT\b/);
  assert.match(source, /\.include\s+"..\/..\/src\/display-model\.asm"/);
});

test('structured display proof is wired into package checks', () => {
  const packageJson = readRepoFile('package.json');
  const runner = readRepoFile('tools/run-display-proof.ts');

  assert.match(packageJson, /"proof:display:structured"/);
  assert.match(packageJson, /proof:display:structured/);
  assert.match(runner, /verifyStructuredScreen/);
  assert.match(runner, /mon3Tgbuf = 0x13c0/);
  assert.match(runner, /visible .*gutter bits/);
  assert.match(runner, /did not render .* text pixels in TGBUF/);
  assert.match(runner, /left stale pixels after shorter row redraw/);
});

test('display proofs do not write stale MON3 scroll-buffer addresses', () => {
  const smokeProof = readRepoFile('proofs/display/glcd-smoke-proof.asm');

  assert.doesNotMatch(smokeProof, /\b0x1000\b/);
});
