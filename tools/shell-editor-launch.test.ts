const { strict: assert } = require('node:assert');
const { existsSync, readFileSync } = require('node:fs');
const { resolve } = require('node:path');
const { test } = require('node:test');

const root = resolve(__dirname, '..');

function readRepoFile(path: string): string {
  return readFileSync(resolve(root, path), 'utf8');
}

test('shell editor launcher exposes a contracted edit launch entry', () => {
  const source = readRepoFile('src/shell-editor-launch.asm');
  const iface = readRepoFile('src/shell-editor-launch.asmi');

  assert.match(source, /^@TECM8_SHELL_RUN_EDITOR_LINE:/m);
  assert.match(iface, /^extern TECM8_SHELL_RUN_EDITOR_LINE$/m);
  assert.match(source, /CALL\s+RunShellCommandLine/);
  assert.match(source, /LD\s+A,\(ShellLastExecAction\)\n\s+CP\s+SHELL_CMD_EDIT/);
  assert.match(source, /CALL\s+TECM8_EDITOR_OPEN_PATH/);
  assert.doesNotMatch(source, /LD\s+DE,ShellMainPath/);
  assert.doesNotMatch(source, /CALL\s+TECM8_EDITOR_OPEN_MAIN/);
});

test('shell edit navigation proof drives shell command into storage-backed editor', () => {
  assert.ok(existsSync(resolve(root, 'proofs/display/shell-edit-navigation-proof.asm')));
  const proof = readRepoFile('proofs/display/shell-edit-navigation-proof.asm');
  const runner = readRepoFile('tools/run-editor-viewport-storage-proof.ts');
  const packageJson = readRepoFile('package.json');

  assert.match(proof, /CALL\s+TECM8_SHELL_RUN_EDITOR_LINE/);
  assert.match(proof, /\.include\s+"..\/..\/src\/shell-commands\.asm"/);
  assert.match(proof, /\.include\s+"..\/..\/src\/editor-interaction\.asm"/);
  assert.match(proof, /\.include\s+"..\/..\/src\/shell-editor-launch\.asm"/);
  assert.match(runner, /shell-edit-navigation-proof/);
  assert.match(runner, /shell-edit-explicit-navigation-proof/);
  assert.match(runner, /verifyShellEditNavigationProof/);
  assert.match(runner, /verifyShellEditExplicitNavigationProof/);
  assert.match(runner, /\/projects\/demo\/app\.asm/);
  assert.match(runner, /\/root\.asm/);
  assert.match(packageJson, /"proof:display:shell-edit-navigation"/);
  assert.match(packageJson, /"proof:display:shell-edit-explicit-navigation"/);
  assert.match(packageJson, /proof:display:shell-edit-navigation/);
  assert.match(packageJson, /proof:display:shell-edit-explicit-navigation/);
});
