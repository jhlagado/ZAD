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

  assert.match(source, /^@ShellRunEditorLine:/m);
  assert.match(source, /^@ShellRunEditorSession:/m);
  assert.match(source, /;!\s+in\s+HL\n;!\s+out\s+A,carry\n;!\s+clobbers\s+A,BC,DE,HL,zero,sign,parity,halfCarry\n@ShellRunEditorLine:/);
  assert.match(source, /;!\s+in\s+DE,HL\n;!\s+out\s+A,carry\n;!\s+clobbers\s+A,BC,DE,HL,zero,sign,parity,halfCarry\n@ShellRunEditorSession:/);
  assert.match(source, /CALL\s+RunShellCommandLine/);
  assert.match(source, /LD\s+A,\(ShellLastExecAction\)\n\s+CP\s+SHELL_CMD_EDIT/);
  assert.match(source, /CALL\s+EditorOpenPath/);
  assert.match(source, /CALL\s+EditorCursorReset/);
  assert.doesNotMatch(source, /LD\s+DE,ShellMainPath/);
  assert.doesNotMatch(source, /CALL\s+EditorOpenMain/);
});

test('Debug80 main entry separates live launch from scripted verification', () => {
  const mainSource = readRepoFile('src/main.asm');
  const runner = readRepoFile('tools/run-debug80-editor-session.ts');
  const packageJson = readRepoFile('package.json');

  assert.match(mainSource, /^@Start:\n\s+JP\s+LiveStart/m);
  assert.match(mainSource, /^@ScriptStart:/m);
  assert.match(mainSource, /^@LiveStart:/m);
  assert.match(mainSource, /CALL\s+ShellRunEditorLine\n\s+JP\s+C,MainFailed\n\s+CALL\s+EditorCursorReset\n\s+CALL\s+EditorRunLive/);
  assert.match(runner, /symbolAddress\(symbols, 'ScriptStart'\)/);
  assert.match(runner, /process\.argv\.includes\('--live-smoke'\)/);
  assert.match(runner, /const MON3_SYS_MODE = 0x089d/);
  assert.match(runner, /forceMemWrite\?\.\(MON3_SYS_MODE, SHADOW_OFF\)/);
  assert.match(runner, /tapMatrixKey\(platformRuntime, runtime, 0, 4\)/);
  assert.match(runner, /tapMatrixKey\(platformRuntime, runtime, 0, 3\)/);
  assert.match(runner, /tapMatrixKey\(platformRuntime, runtime, 0, 6\)/);
  assert.match(runner, /tapMatrixCombo\(platformRuntime, runtime, \{ row: 0, col: 1 \}, \{ row: 0, col: 4 \}\)/);
  assert.match(runner, /tapMatrixCombo\(platformRuntime, runtime, \{ row: 0, col: 3 \}, \{ row: 0, col: 6 \}\)/);
  assert.match(runner, /tapMatrixKey\(platformRuntime, runtime, 0, 7\)/);
  assert.match(runner, /tapMatrixKey\(platformRuntime, runtime, 7, 5\)/);
  assert.match(runner, /tapMatrixKey\(platformRuntime, runtime, 1, 2\)/);
  assert.match(runner, /tapMatrixKey\(platformRuntime, runtime, 1, 0\)/);
  assert.match(runner, /assertRuntimeSourceRecord\(runtime, pageBufferAddr, 0, '', 'after Enter split'\)/);
  assert.match(runner, /assertRuntimeSourceRecord\(runtime, pageBufferAddr, 1, 'R0 LINE 00', 'after Enter split'\)/);
  assert.match(runner, /assertRuntimeSourceRecord\(runtime, pageBufferAddr, 2, 'RZ0 LINE 01', 'after Enter split'\)/);
  assert.match(runner, /assertRuntimeSourceRecord\(runtime, pageBufferAddr, 15, 'R0 LINE 14', 'after Enter split'\)/);
  assert.match(runner, /assertRuntimeSourceRecord\(runtime, pageBufferAddr, 0, '', 'after saved split page return'\)/);
  assert.match(runner, /assertRuntimeSourceRecord\(runtime, pageBufferAddr, 2, 'RZ0 LINE 01', 'after saved split page return'\)/);
  assert.match(runner, /tapMatrixKey\(platformRuntime, runtime, 0, 4\); \/\/ ArrowDown: move to split tail for join/);
  assert.match(runner, /assertRuntimeSourceRecord\(runtime, pageBufferAddr, 0, 'R0 LINE 00', 'after Backspace join'\)/);
  assert.match(runner, /assertRuntimeSourceRecord\(runtime, pageBufferAddr, 1, 'RZ0 LINE 01', 'after Backspace join'\)/);
  assert.match(runner, /assertRuntimeSourceRecord\(runtime, pageBufferAddr, 15, '', 'after Backspace join'\)/);
  assert.match(runner, /tapMatrixCombo\(platformRuntime, runtime, \{ row: 0, col: 3 \}, \{ row: 6, col: 6 \}/);
  assert.match(runner, /tapMatrixCombo\(platformRuntime, runtime, \{ row: 0, col: 3 \}, \{ row: 6, col: 5 \}/);
  assert.match(runner, /promptAfterAltR/);
  assert.match(runner, /dirtyAfterRestoreNo/);
  assert.match(runner, /tapMatrixCombo\(platformRuntime, runtime, \{ row: 0, col: 3 \}, \{ row: 7, col: 3 \}/);
  assert.match(runner, /cursorRowAfterEnter !== 1 \|\| cursorColAfterEnter !== 0/);
  assert.match(runner, /cursorRowAfterJoin !== 0 \|\| cursorColAfterJoin !== 0/);
  assert.match(runner, /altModifierBits !== 0x08/);
  assert.match(runner, /saveModifierBits & 0x08/);
  assert.match(runner, /quitModifierBits & 0x08/);
  assert.match(runner, /modifierBits !== 0x10/);
  assert.match(packageJson, /"debug80:editor-live-smoke"/);
  assert.match(packageJson, /debug80:editor-live-smoke/);
});

test('shell edit navigation proof drives shell command into storage-backed editor', () => {
  assert.ok(existsSync(resolve(root, 'proofs/display/shell-edit-navigation-proof.asm')));
  const proof = readRepoFile('proofs/display/shell-edit-navigation-proof.asm');
  const runner = readRepoFile('tools/run-editor-viewport-storage-proof.ts');
  const packageJson = readRepoFile('package.json');

  assert.match(proof, /CALL\s+ShellRunEditorLine/);
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
