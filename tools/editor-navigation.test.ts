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

  for (const name of [
    'EditorOpenMain',
    'EditorOpenPath',
    'EditorRenderCurrent',
    'EditorRenderPageBuffer',
    'EditorSaveCurrentPage',
    'EditorBackupCurrentPage',
    'EditorClearDirty',
    'EditorPageDown',
    'EditorPageUp',
    'EditorNavDeriveBackupPath',
  ]) {
    assert.match(source, new RegExp(`^@${name}:`, 'm'));
  }
  assert.match(source, /;!\s+out\s+A,carry\n;!\s+clobbers\s+A,BC,DE,HL,zero,sign,parity,halfCarry\n@EditorOpenMain:/);
  assert.match(source, /;!\s+in\s+HL\n;!\s+out\s+A,carry\n;!\s+clobbers\s+A,BC,DE,HL,zero,sign,parity,halfCarry\n@EditorOpenPath:/);

  assert.match(source, /EditorNavCurrentPage:\n\s+\.db\s+0/);
  assert.match(source, /EditorNavDirty:\n\s+\.db\s+0/);
  assert.match(source, /TECM8_EDITOR_NAV_ERR_BACKUP\s+\.equ\s+0x52/);
  assert.match(source, /EditorNavBackupPathBuffer:\n\s+\.ds\s+TECM8_EDITOR_NAV_PATH_LEN/);
  assert.match(source, /EditorNavBackupPageBuffer:\n\s+\.ds\s+512/);
  assert.match(source, /EditorNavBackupSourcePtr:\n\s+\.dw\s+0/);
  assert.match(source, /EditorNavPageBuffer:\n\s+\.ds\s+512/);
});

test('editor navigation commits page movement only after successful render', () => {
  const source = readRepoFile('src/editor-navigation.asm');

  assert.match(source, /CALL\s+EditorNavRenderPage\n\s+RET\s+C\n\s+LD\s+A,\(EditorNavPendingPage\)\n\s+LD\s+\(EditorNavCurrentPage\),A/);
  assert.match(source, /CALL\s+EditorLoadSourcePage/);
  assert.match(source, /@EditorRenderCurrent:\n\s+LD\s+A,\(EditorNavCurrentPage\)\n\s+CALL\s+EditorNavRenderPage\n\s+RET\s+C\n\s+JP\s+EditorClearDirty/);
  assert.match(source, /@EditorSaveCurrentPage:\n\s+CALL\s+EditorBackupCurrentPage\n\s+RET\s+C/);
  assert.match(source, /CALL\s+EditorNavDeriveBackupPath/);
  assert.match(source, /LD\s+DE,EditorNavBackupPathBuffer/);
  assert.match(source, /LD\s+HL,EditorNavBackupPageBuffer/);
  assert.match(source, /CALL\s+EditorSaveSourcePage/);
  assert.match(source, /JP\s+EditorClearDirty/);
  assert.match(source, /JP\s+EditorRenderPageBuffer/);
  assert.match(source, /EditorNavPathPtr:\n\s+\.dw\s+0/);
  assert.match(source, /EditorNavPathBuffer:\n\s+\.ds\s+TECM8_EDITOR_NAV_PATH_LEN/);
  assert.match(source, /CALL\s+EditorNavCopyPath/);
  assert.match(source, /CALL\s+EditorViewportRender/);
  assert.match(source, /CALL\s+BiosDisplayUpdate/);
  assert.match(source, /TECM8_EDITOR_NAV_ERR_PAGE\s+\.equ\s+0x50/);
});

test('editor navigation proof drives page state over storage-backed source', () => {
  assert.ok(existsSync(resolve(root, 'proofs/display/editor-navigation-proof.asm')));
  const proof = readRepoFile('proofs/display/editor-navigation-proof.asm');
  const runner = readRepoFile('tools/run-editor-viewport-storage-proof.ts');
  const packageJson = readRepoFile('package.json');

  assert.match(proof, /CALL\s+EditorOpenMain/);
  assert.match(proof, /CALL\s+EditorPageDown/);
  assert.match(proof, /CALL\s+EditorPageUp/);
  assert.match(proof, /\.include\s+"..\/..\/src\/editor-navigation\.asm"/);
  assert.match(runner, /editor-navigation-proof/);
  assert.match(runner, /verifyNavigationProof/);
  assert.match(runner, /maxInstructions = 80_000_000/);
  assert.match(runner, /P7 LINE 07/);
  assert.match(packageJson, /"proof:display:editor-navigation"/);
  assert.match(packageJson, /proof:display:editor-navigation/);
});
