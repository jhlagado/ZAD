const { strict: assert } = require('node:assert');
const { existsSync, readFileSync } = require('node:fs');
const { resolve } = require('node:path');
const { test } = require('node:test');

const root = resolve(__dirname, '..');

function readRepoFile(path: string): string {
  return readFileSync(resolve(root, path), 'utf8');
}

test('editor file listing exposes visible files and hides leading-dot names', () => {
  const source = readRepoFile('src/editor-file-list.asm');
  const proof = readRepoFile('proofs/display/editor-file-list-proof.asm');
  const runner = readRepoFile('tools/run-editor-viewport-storage-proof.ts');
  const packageJson = readRepoFile('package.json');

  assert.match(source, /^@EditorListVisibleFiles:/m);
  assert.match(source, /^@EditorListMaybeCopyEntry:/m);
  assert.match(source, /CP\s+"\."/);
  assert.match(source, /JR\s+Z,EditorListEntryDone/);
  assert.match(source, /LD\s+C,A\n\s+INC\s+B/);
  assert.match(source, /LD\s+A,0x0A/);
  assert.match(source, /EditorListOutPtr:/);
  assert.match(source, /EDITOR_LIST_ERR_PATH\s+\.equ/);
  assert.match(source, /EDITOR_LIST_ERR_LONG\s+\.equ/);

  assert.ok(existsSync(resolve(root, 'proofs/display/editor-file-list-proof.asm')));
  assert.match(proof, /CALL\s+EditorListVisibleFiles/);
  assert.match(proof, /CALL\s+FillListBuffer/);
  assert.match(proof, /NestedListPrefix:\n\s+\.db\s+"\/projects\/demo",0/);
  assert.match(proof, /RootListPrefix:\n\s+\.db\s+"\/",0/);
  assert.match(proof, /\.include\s+"..\/..\/src\/editor-file-list\.asm"/);
  assert.match(runner, /editor-file-list-proof/);
  assert.match(runner, /verifyEditorFileListProof/);
  assert.match(runner, /verifyListOutput/);
  assert.match(runner, /NestedListOut', 'app\.asm\\n'/);
  assert.match(runner, /RootListOut', 'root\.asm\\n'/);
  assert.match(runner, /\/src\/\.main\.asm\.b/);
  assert.match(runner, /main\.asm\\nnotes\.asm\\n/);
  assert.match(packageJson, /"proof:display:editor-file-list"/);
  assert.match(packageJson, /proof:display:editor-file-list/);
});
