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
    'TECM8_DISPLAY_MARKER_BREAKPOINT',
    'TECM8_DISPLAY_MARKER_CURRENT',
  ]) {
    assert.match(docs, new RegExp(`\\b${phrase}\\b`));
  }
});

test('structured display model has assembly entry points and contracts', () => {
  const source = readRepoFile('src/display-model.asm');
  const iface = readRepoFile('src/display-model.asmi');

  for (const label of [
    'TECM8_DISPLAY_INIT',
    'TECM8_DISPLAY_RENDER_SCREEN',
    'TECM8_DISPLAY_RENDER_LINE',
    'TECM8_DISPLAY_RENDER_GUTTER',
    'TECM8_DISPLAY_RENDER_CURSOR_CELL',
    'TECM8_DISPLAY_ERASE_CURSOR_CELL',
  ]) {
    assert.match(source, new RegExp(`^@${label}:`, 'm'));
    assert.match(iface, new RegExp(`^extern ${label}$`, 'm'));
  }

  for (const constant of [
    'TECM8_DISPLAY_GLCD_COLUMNS',
    'TECM8_DISPLAY_GLCD_ROWS',
    'TECM8_DISPLAY_EDIT_ROWS',
    'TECM8_DISPLAY_GUTTER_PIXELS',
  ]) {
    assert.match(source, new RegExp(`^${constant}\\s+\\.equ`, 'm'));
  }
  assert.match(source, /^MON3_TGBUF\s+\.equ\s+0x13C0$/m);
  assert.match(source, /@TECM8_DISPLAY_RENDER_GUTTER:\n\s+LD\s+\(DisplayRow\),A/);
  assert.match(source, /@TECM8_DISPLAY_RENDER_SCREEN:\n\s+LD\s+\(DisplayCursor\),HL\n\s+CALL\s+TECM8_BIOS_DISPLAY_CLEAR/);
  assert.match(source, /AND\s+0x0F/);
  assert.match(source, /@TECM8_DISPLAY_RENDER_CURSOR_CELL:/);
  assert.match(source, /@TECM8_DISPLAY_ERASE_CURSOR_CELL:/);
  assert.match(source, /CP\s+TECM8_DISPLAY_EDIT_ROWS/);
  assert.match(source, /CP\s+TECM8_DISPLAY_MAX_TEXT_CHARS/);
  assert.match(source, /CALL\s+TECM8_BIOS_DISPLAY_UPDATE/);
  assert.match(source, /DisplayCursorSavedBytes:/);
  assert.match(source, /LD\s+\(DisplayCursorOriginalByte\),A/);
  assert.match(source, /CALL\s+TECM8_BIOS_DISPLAY_DRAW_CHAR_AT/);
  assert.doesNotMatch(source, /CALL\s+TECM8_BIOS_DISPLAY_PUT_STRING/);
});

test('structured GLCD proof calls the display model and renders markers', () => {
  assert.ok(existsSync(resolve(root, 'proofs/display/structured-screen-proof.asm')));
  const source = readRepoFile('proofs/display/structured-screen-proof.asm');

  assert.match(source, /CALL\s+TECM8_DISPLAY_INIT/);
  assert.match(source, /CALL\s+TECM8_DISPLAY_RENDER_SCREEN/);
  assert.match(source, /LD\s+HL,0x1000\n\s+LD\s+\(MON3_VPORT\),HL/);
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
});

test('display proofs do not write stale MON3 scroll-buffer addresses', () => {
  const smokeProof = readRepoFile('proofs/display/glcd-smoke-proof.asm');

  assert.doesNotMatch(smokeProof, /\b0x1000\b/);
});
