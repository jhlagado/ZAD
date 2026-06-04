const { strict: assert } = require('node:assert');
const { existsSync, readFileSync } = require('node:fs');
const { resolve } = require('node:path');
const { test } = require('node:test');

const root = resolve(__dirname, '..');

function readRepoFile(path: string): string {
  return readFileSync(resolve(root, path), 'utf8');
}

test('editor interaction module exposes a key-stream runner', () => {
  const source = readRepoFile('src/editor-interaction.asm');
  const iface = readRepoFile('src/editor-interaction.asmi');

  assert.match(source, /^@TECM8_EDITOR_RUN_KEYS:/m);
  assert.match(source, /^@TECM8_EDITOR_CURSOR_RESET:/m);
  assert.match(iface, /^extern TECM8_EDITOR_RUN_KEYS$/m);
  assert.match(iface, /^extern TECM8_EDITOR_CURSOR_RESET$/m);
  assert.match(iface, /^in HL$/m);
  assert.match(source, /CALL\s+TECM8_EDITOR_PAGE_DOWN/);
  assert.match(source, /CALL\s+TECM8_EDITOR_PAGE_UP/);
  assert.match(source, /EditorCursorRow:\n\s+\.db\s+0/);
  assert.match(source, /EditorCursorCol:\n\s+\.db\s+0/);
  assert.match(source, /LD\s+\(EditorCursorRow\),A\n\s+LD\s+\(EditorCursorCol\),A/);
  assert.match(source, /TECM8_EDITOR_CURSOR_MAX_ROW\s+\.equ\s+9/);
  assert.match(source, /TECM8_EDITOR_CURSOR_MAX_COL\s+\.equ\s+31/);
  assert.match(source, /EditorKeyCursorLeft:/);
  assert.match(source, /EditorKeyCursorDown:/);
  assert.match(source, /EditorKeyCursorUp:/);
  assert.match(source, /EditorKeyCursorRight:/);
  assert.match(source, /CP\s+TECM8_EDITOR_NAV_ERR_PAGE/);
  assert.match(source, /CP\s+TECM8_EDITOR_INTERACTION_ERR_EOF/);
});

test('shell-launched editor interaction proof is wired into storage proof runner', () => {
  assert.ok(existsSync(resolve(root, 'proofs/display/shell-edit-interaction-proof.asm')));
  const proof = readRepoFile('proofs/display/shell-edit-interaction-proof.asm');
  const runner = readRepoFile('tools/run-editor-viewport-storage-proof.ts');
  const packageJson = readRepoFile('package.json');

  assert.match(proof, /CALL\s+TECM8_SHELL_RUN_EDITOR_SESSION/);
  assert.match(proof, /\.include\s+"..\/..\/src\/editor-interaction\.asm"/);
  assert.match(runner, /shell-edit-interaction-proof/);
  assert.match(runner, /verifyShellEditInteractionProof/);
  assert.match(runner, /EditorCursorRow/);
  assert.match(runner, /EditorCursorCol/);
  assert.match(packageJson, /"proof:display:shell-edit-interaction"/);
  assert.match(packageJson, /proof:display:shell-edit-interaction/);
});
