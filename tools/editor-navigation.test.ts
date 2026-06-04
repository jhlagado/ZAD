const { strict: assert } = require('node:assert');
const { existsSync, readFileSync } = require('node:fs');
const { resolve } = require('node:path');
const { test } = require('node:test');

const root = resolve(__dirname, '..');

function readRepoFile(path: string): string {
  return readFileSync(resolve(root, path), 'utf8');
}

test('editor navigation module exposes open, render, and page movement entries', () => {
  const source = readRepoFile('src/editor-navigation.asm');
  const iface = readRepoFile('src/editor-navigation.asmi');

  for (const name of [
    'TECM8_EDITOR_OPEN_MAIN',
    'TECM8_EDITOR_RENDER_CURRENT',
    'TECM8_EDITOR_PAGE_DOWN',
    'TECM8_EDITOR_PAGE_UP',
  ]) {
    assert.match(source, new RegExp(`^@${name}:`, 'm'));
    assert.match(iface, new RegExp(`^extern ${name}$`, 'm'));
  }

  assert.match(source, /EditorNavCurrentPage:\n\s+\.db\s+0/);
  assert.match(source, /EditorNavPageBuffer:\n\s+\.ds\s+512/);
});

test('editor navigation commits page movement only after successful render', () => {
  const source = readRepoFile('src/editor-navigation.asm');

  assert.match(source, /CALL\s+EditorNavRenderPage\n\s+RET\s+C\n\s+LD\s+A,\(EditorNavPendingPage\)\n\s+LD\s+\(EditorNavCurrentPage\),A/);
  assert.match(source, /CALL\s+TECM8_EDITOR_LOAD_MAIN_SOURCE_PAGE/);
  assert.match(source, /CALL\s+TECM8_EDITOR_VIEWPORT_RENDER/);
  assert.match(source, /CALL\s+TECM8_BIOS_DISPLAY_UPDATE/);
  assert.match(source, /TECM8_EDITOR_NAV_ERR_PAGE\s+\.equ\s+0x50/);
});

test('editor navigation proof drives page state over storage-backed source', () => {
  assert.ok(existsSync(resolve(root, 'proofs/display/editor-navigation-proof.asm')));
  const proof = readRepoFile('proofs/display/editor-navigation-proof.asm');
  const runner = readRepoFile('tools/run-editor-viewport-storage-proof.ts');
  const packageJson = readRepoFile('package.json');

  assert.match(proof, /CALL\s+TECM8_EDITOR_OPEN_MAIN/);
  assert.match(proof, /CALL\s+TECM8_EDITOR_PAGE_DOWN/);
  assert.match(proof, /CALL\s+TECM8_EDITOR_PAGE_UP/);
  assert.match(proof, /\.include\s+"..\/..\/src\/editor-navigation\.asm"/);
  assert.match(runner, /editor-navigation-proof/);
  assert.match(runner, /verifyNavigationProof/);
  assert.match(runner, /maxInstructions = 80_000_000/);
  assert.match(runner, /P7 LINE 07/);
  assert.match(packageJson, /"proof:display:editor-navigation"/);
  assert.match(packageJson, /proof:display:editor-navigation/);
});
