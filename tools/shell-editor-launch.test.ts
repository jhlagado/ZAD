const { strict: assert } = require('node:assert');
const { existsSync, readFileSync } = require('node:fs');
const { resolve } = require('node:path');
const { test } = require('node:test');

const root = resolve(__dirname, '..');

function readRepoFile(path: string): string {
  return readFileSync(resolve(root, path), 'utf8');
}

test('shell editor launcher exposes edit launch entries', () => {
  const source = readRepoFile('src/shell-editor-launch.asm');

  assert.match(source, /^@ShellRunEditorLine:/m);
  assert.match(source, /^@ShellRunEditorSession:/m);
  assert.match(source, /CALL\s+RunShellCommandLine/);
  assert.match(source, /LD\s+A,\(ShellLastExecAction\)\n\s+CP\s+SHELL_CMD_EDIT/);
  assert.match(source, /CALL\s+EditorOpenPath/);
  assert.match(source, /CP\s+EDITOR_LOAD_ERR_FIND\n\s+JR\s+NZ,ShellEditorLaunchOpenError/);
  assert.match(source, /CALL\s+EditorCreateSourceFile/);
  assert.match(source, /ShellEditorLaunchPathPtr:\n\s+\.dw\s+0/);
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
  assert.match(mainSource, /LD\s+HL,MainShellReadyText\n\s+CALL\s+EditorKeyShowStatus/);
  assert.match(mainSource, /MainShellReadyText:\n\s+\.db\s+"Shell",0/);
  assert.match(runner, /symbolAddress\(symbols, 'ScriptStart'\)/);
  assert.match(runner, /process\.argv\.includes\('--live-smoke'\)/);
  assert.match(runner, /const MON3_SYS_MODE = 0x089d/);
  assert.match(runner, /forceMemWrite\?\.\(MON3_SYS_MODE, SHADOW_OFF\)/);
  assert.match(runner, /tapMatrixKey\(platformRuntime, runtime, 0, 4\)/);
  assert.match(runner, /tapMatrixKey\(platformRuntime, runtime, 0, 3\)/);
  assert.match(runner, /tapMatrixKey\(platformRuntime, runtime, 0, 6\)/);
  assert.match(runner, /tapMatrixCombo\(platformRuntime, runtime, \{ row: 0, col: 1 \}, \{ row: 0, col: 4 \}\)/);
  assert.match(runner, /tapMatrixCombo\(platformRuntime, runtime, \{ row: 0, col: 1 \}, \{ row: 0, col: 6 \}\)/);
  assert.match(runner, /tapMatrixKey\(platformRuntime, runtime, 0, 7\)/);
  assert.match(runner, /tapMatrixKey\(platformRuntime, runtime, 7, 5\)/);
  assert.match(runner, /tapMatrixKey\(platformRuntime, runtime, 1, 2\)/);
  assert.match(runner, /tapMatrixKey\(platformRuntime, runtime, 1, 0\)/);
  assert.match(runner, /assertRuntimeSourceRecord\(runtime, pageBufferAddr, 0, '', 'after Enter split'\)/);
  assert.match(runner, /assertRuntimeSourceRecord\(runtime, pageBufferAddr, 1, 'R0 LINE 00', 'after Enter split'\)/);
  assert.match(runner, /assertRuntimeSourceRecord\(runtime, pageBufferAddr, 2, 'Rz0 LINE 01', 'after Enter split'\)/);
  assert.match(runner, /assertRuntimeSourceRecord\(runtime, pageBufferAddr, 15, 'R0 LINE 14', 'after Enter split'\)/);
  assert.match(runner, /assertRuntimeSourceRecord\(runtime, pageBufferAddr, 0, '', 'after saved split page return'\)/);
  assert.match(runner, /assertRuntimeSourceRecord\(runtime, pageBufferAddr, 2, 'Rz0 LINE 01', 'after saved split page return'\)/);
  assert.match(runner, /tapMatrixKey\(platformRuntime, runtime, 0, 4\); \/\/ ArrowDown: move to split tail for join/);
  assert.match(runner, /assertRuntimeSourceRecord\(runtime, pageBufferAddr, 0, 'R0 LINE 00', 'after Backspace join'\)/);
  assert.match(runner, /assertRuntimeSourceRecord\(runtime, pageBufferAddr, 1, 'Rz0 LINE 01', 'after Backspace join'\)/);
  assert.match(runner, /assertRuntimeSourceRecord\(runtime, pageBufferAddr, 15, '', 'after Backspace join'\)/);
  assert.match(runner, /tapMatrixCombo\(platformRuntime, runtime, \{ row: 0, col: 1 \}, \{ row: 6, col: 6 \}/);
  assert.match(runner, /tapMatrixCombo\(platformRuntime, runtime, \{ row: 0, col: 1 \}, \{ row: 6, col: 6 \}/);
  assert.match(runner, /tapMatrixCombo\(platformRuntime, runtime, \{ row: 0, col: 1 \}, \{ row: 7, col: 5 \}/);
  assert.match(runner, /pressMatrixCombo\(platformRuntime, \{ row: 0, col: 1 \}, \{ row: 7, col: 5 \}/);
  assert.match(runner, /promptAfterCtrlZ/);
  assert.match(runner, /promptAfterSecondCtrlZ/);
  assert.match(runner, /dirtyAfterRestoreNo/);
  assert.match(runner, /tapMatrixCombo\(platformRuntime, runtime, \{ row: 0, col: 1 \}, \{ row: 6, col: 4 \}/);
  assert.match(runner, /pressMatrixCombo\(platformRuntime, \{ row: 0, col: 1 \}, \{ row: 6, col: 4 \}/);
  assert.match(runner, /promptAfterCtrlQ/);
  assert.match(runner, /cursorRowAfterEnter !== 1 \|\| cursorColAfterEnter !== 0/);
  assert.match(runner, /cursorRowAfterJoin !== 0 \|\| cursorColAfterJoin !== 0/);
  assert.match(runner, /ctrlArrowModifierBits !== 0x02/);
  assert.match(runner, /saveModifierBits & 0x02/);
  assert.match(runner, /actionAfterCtrlQ !== 2/);
  assert.match(runner, /pendingAfterCtrlQ !== 0x11/);
  assert.match(runner, /actionAfterCtrlZ !== 1/);
  assert.match(runner, /pendingAfterCtrlZ !== 0x1a/);
  assert.match(runner, /ctrlSaveTranslatedKey !== 0x13/);
  assert.match(runner, /dirtyAfterSecondSave !== 0/);
  assert.match(runner, /quitModifierBits & 0x02/);
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
  assert.match(runner, /shell-edit-named-navigation-proof/);
  assert.match(runner, /shell-edit-create-source-proof/);
  assert.match(runner, /verifyShellEditNavigationProof/);
  assert.match(runner, /verifyShellEditExplicitNavigationProof/);
  assert.match(runner, /verifyShellEditNamedNavigationProof/);
  assert.match(runner, /verifyShellEditCreateSourceProof/);
  assert.match(runner, /\/projects\/demo\/app\.asm/);
  assert.match(runner, /\/root\.asm/);
  assert.match(runner, /\/src\/notes\.asm/);
  assert.match(runner, /\/src\/fresh\.asm/);
  assert.match(runner, /N0 LINE/);
  assert.match(packageJson, /"proof:display:shell-edit-navigation"/);
  assert.match(packageJson, /"proof:display:shell-edit-explicit-navigation"/);
  assert.match(packageJson, /"proof:display:shell-edit-named-navigation"/);
  assert.match(packageJson, /"proof:display:shell-edit-create-source"/);
  assert.match(packageJson, /proof:display:shell-edit-navigation/);
  assert.match(packageJson, /proof:display:shell-edit-explicit-navigation/);
  assert.match(packageJson, /proof:display:shell-edit-named-navigation/);
  assert.match(packageJson, /proof:display:shell-edit-create-source/);
});

test('shell command loop proves edit asm run sequence', () => {
  const source = readRepoFile('src/shell-commands.asm');
  const stringSource = readRepoFile('src/tecm8-string.asm');
  const proof = readRepoFile('proofs/shell-commands/shell-commands-proof.asm');

  assert.match(source, /^@RunShellProgramCycles:/m);
  assert.match(source, /^@ShellRecordExecAction:/m);
  assert.match(source, /SHELL_EXEC_LOG_LEN\s+\.equ\s+8/);
  assert.match(source, /ShellExecActionLog:\n\s+\.ds\s+SHELL_EXEC_LOG_LEN/);
  assert.match(source, /CALL\s+RunShellPromptCycle/);
  assert.match(source, /CP\s+SHELL_PROMPT_ERROR/);
  assert.match(source, /CALL\s+Tecm8StringFindLocalName/);
  assert.match(source, /CALL\s+Tecm8StringCopyNulBounded/);
  assert.match(source, /CALL\s+Tecm8StringSkipSpaces/);
  assert.doesNotMatch(source, /^@ShellFindLocalName:/m);
  assert.doesNotMatch(source, /^@ShellSkipSpaces:/m);
  assert.match(stringSource, /^@Tecm8StringFindLocalName:/m);
  assert.match(stringSource, /^@Tecm8StringCopyNulBounded:/m);
  assert.match(stringSource, /^@Tecm8StringSkipSpaces:/m);
  assert.match(proof, /\.include\s+"..\/..\/src\/tecm8-string\.asm"/);
  assert.ok(
    proof.indexOf('@Start:') < proof.indexOf('.include "../../src/tecm8-string.asm"'),
    'byte-emitting shared string helpers must not be included before proof entry'
  );
  assert.match(proof, /AssertShellProgramCommandLoop/);
  assert.match(proof, /AssertShellProgramCyclesInitErr/);
  assert.match(proof, /AssertShellProgramCyclesPromptErr/);
  assert.match(proof, /AssertShellProgramCyclesZero/);
  assert.match(proof, /AssertShellExecLogSaturates/);
  assert.match(proof, /KeyEditAsmRun:/);
  assert.match(proof, /KeyEditBadRun:/);
  assert.match(proof, /CP\s+SHELL_CMD_EDIT/);
  assert.match(proof, /CP\s+SHELL_CMD_ASM/);
  assert.match(proof, /CP\s+SHELL_CMD_RUN/);
});
