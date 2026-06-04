const { strict: assert } = require('node:assert');
const { existsSync, readFileSync } = require('node:fs');
const { resolve } = require('node:path');
const { test } = require('node:test');

const root = resolve(__dirname, '..');

function readRepoFile(path: string): string {
  return readFileSync(resolve(root, path), 'utf8');
}

test('editor viewport module exposes a source-record render entry point', () => {
  const source = readRepoFile('src/editor-viewport.asm');
  const iface = readRepoFile('src/editor-viewport.asmi');

  assert.match(source, /^@TECM8_EDITOR_VIEWPORT_RENDER:/m);
  assert.match(iface, /^extern TECM8_EDITOR_VIEWPORT_RENDER$/m);

  for (const constant of [
    'TECM8_EDITOR_RECORD_BYTES',
    'TECM8_EDITOR_VISIBLE_ROWS',
    'TECM8_EDITOR_MAX_RECORD_TEXT',
    'TECM8_EDITOR_ROW_TEXT_BYTES',
  ]) {
    assert.match(source, new RegExp(`^${constant}\\s+\\.equ`, 'm'));
  }

  assert.match(source, /CP\s+TECM8_EDITOR_MAX_RECORD_TEXT \+ 1/);
  assert.match(source, /CALL\s+TECM8_DISPLAY_RENDER_SCREEN/);
});

test('editor viewport proof builds records and renders through the display model', () => {
  assert.ok(existsSync(resolve(root, 'proofs/display/editor-viewport-proof.asm')));
  const source = readRepoFile('proofs/display/editor-viewport-proof.asm');

  assert.match(source, /CALL\s+TECM8_EDITOR_VIEWPORT_RENDER/);
  assert.match(source, /\.include\s+"..\/..\/src\/editor-viewport\.asm"/);
  assert.match(source, /EditorSourceRecords:/);
  assert.match(source, /\.db\s+9,"ORG 4000H"\n\s+\.ds\s+22/);
});

test('editor viewport proof is wired into package checks with content verification', () => {
  const packageJson = readRepoFile('package.json');
  const runner = readRepoFile('tools/run-display-proof.ts');

  assert.match(packageJson, /"proof:display:editor-viewport"/);
  assert.match(packageJson, /proof:display:editor-viewport/);
  assert.match(runner, /verifyEditorViewport/);
  assert.match(runner, /requiresVisiblePixels = proofName !== 'editor-viewport-bad-record-proof'/);
  assert.match(runner, /EditorRowText0/);
  assert.match(runner, /editor viewport proof copied/);
  assert.match(runner, /editor viewport proof missing .* gutter bits/);
  assert.match(runner, /editor viewport proof missing visible .* gutter bits/);
});

test('editor viewport malformed-record proof is wired into package checks', () => {
  assert.ok(existsSync(resolve(root, 'proofs/display/editor-viewport-bad-record-proof.asm')));
  const packageJson = readRepoFile('package.json');
  const source = readRepoFile('proofs/display/editor-viewport-bad-record-proof.asm');

  assert.match(packageJson, /"proof:display:editor-viewport:bad-record"/);
  assert.match(packageJson, /proof:display:editor-viewport:bad-record/);
  assert.match(source, /CALL\s+TECM8_EDITOR_VIEWPORT_RENDER/);
  assert.match(source, /JR\s+NC,ProofFailed/);
  assert.match(source, /CP\s+TECM8_EDITOR_ERR_RECORD_LENGTH/);
  assert.match(source, /\.db\s+32/);
});
