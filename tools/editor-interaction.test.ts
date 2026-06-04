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
  assert.match(source, /^@TECM8_EDITOR_RENDER_CURSOR:/m);
  assert.match(iface, /^extern TECM8_EDITOR_RUN_KEYS$/m);
  assert.match(iface, /^extern TECM8_EDITOR_CURSOR_RESET$/m);
  assert.match(iface, /^extern TECM8_EDITOR_RENDER_CURSOR$/m);
  assert.match(iface, /^in HL$/m);
  assert.match(source, /CALL\s+TECM8_EDITOR_PAGE_DOWN/);
  assert.match(source, /CALL\s+TECM8_EDITOR_PAGE_UP/);
  assert.match(source, /CALL\s+TECM8_DISPLAY_RENDER_CURSOR_CELL/);
  assert.match(source, /CALL\s+TECM8_DISPLAY_ERASE_CURSOR_CELL/);
  assert.match(source, /CALL\s+TECM8_EDITOR_RENDER_PAGE_BUFFER/);
  assert.match(source, /EditorCursorRow:\n\s+\.db\s+0/);
  assert.match(source, /EditorCursorCol:\n\s+\.db\s+0/);
  assert.match(source, /EditorCursorRendered:\n\s+\.db\s+0/);
  assert.match(source, /LD\s+\(EditorCursorRow\),A\n\s+LD\s+\(EditorCursorCol\),A/);
  assert.match(source, /TECM8_EDITOR_CURSOR_MAX_ROW\s+\.equ\s+9/);
  assert.match(source, /TECM8_EDITOR_CURSOR_MAX_COL\s+\.equ\s+31/);
  assert.match(source, /TECM8_EDITOR_KEY_BACKSPACE\s+\.equ\s+8/);
  assert.match(source, /TECM8_EDITOR_KEY_INSERT_MODE\s+\.equ\s+9/);
  assert.match(source, /TECM8_EDITOR_KEY_DELETE\s+\.equ\s+127/);
  assert.match(source, /EditorInsertMode:\n\s+\.db\s+0/);
  assert.match(source, /EditorKeyInsertMode:/);
  assert.match(source, /EditorKeyMaybeInsertMode:/);
  assert.match(source, /EditorKeyCursorLeft:/);
  assert.match(source, /EditorKeyCursorDown:/);
  assert.match(source, /EditorKeyCursorUp:/);
  assert.match(source, /EditorKeyCursorRight:/);
  assert.match(source, /EditorKeyInsertPrintable:/);
  assert.match(source, /CALL\s+TECM8_EDITOR_INSERT_CHAR/);
  assert.match(source, /CALL\s+TECM8_EDITOR_BACKSPACE_CHAR/);
  assert.match(source, /CALL\s+TECM8_EDITOR_DELETE_CHAR/);
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
  assert.match(proof, /\.db\s+"hku"/);
  assert.match(proof, /\.db\s+"ljHKLJHK"/);
  assert.match(proof, /\.db\s+"hhhhhhhhhhhk"/);
  assert.match(proof, /\.db\s+"hhhhhhhhhhhhhhhhh"/);
  assert.match(proof, /\.db\s+"d"/);
  assert.match(proof, /\.db\s+9/);
  assert.match(proof, /\.db\s+"dl!"/);
  assert.match(proof, /\.db\s+8/);
  assert.match(proof, /\.db\s+"\?",127,0/);
  assert.match(proof, /EditorKeyLeft:\n\s+\.db\s+"h",0/);
  assert.match(proof, /EditorKeyRight:\n\s+\.db\s+"l",0/);
  assert.match(runner, /shell-edit-interaction-proof/);
  assert.match(runner, /verifyShellEditInteractionProof/);
  assert.match(runner, /verifyShellEditVisibleCursor/);
  assert.match(runner, /EditorCursorRow/);
  assert.match(runner, /EditorCursorCol/);
  assert.match(runner, /expected 7/);
  assert.match(runner, /expected 5/);
  assert.match(runner, /mutatedRecord !== 'A1dl\?LINE 07'/);
  assert.match(runner, /cursorMask = 0x08/);
  assert.doesNotMatch(runner, /previous cursor/);
  assert.match(packageJson, /"proof:display:shell-edit-interaction"/);
  assert.match(packageJson, /proof:display:shell-edit-interaction/);
});

test('editor mutation boundary proof covers fixed-record edge cases', () => {
  assert.ok(existsSync(resolve(root, 'proofs/display/editor-mutation-boundary-proof.asm')));
  const proof = readRepoFile('proofs/display/editor-mutation-boundary-proof.asm');
  const runner = readRepoFile('tools/run-editor-viewport-storage-proof.ts');
  const packageJson = readRepoFile('package.json');

  assert.match(proof, /CALL\s+TECM8_EDITOR_BACKSPACE_CHAR/);
  assert.match(proof, /CALL\s+TECM8_EDITOR_DELETE_CHAR/);
  assert.match(proof, /CALL\s+TECM8_EDITOR_INSERT_CHAR/);
  assert.match(proof, /CALL\s+TECM8_EDITOR_RUN_KEYS/);
  assert.match(proof, /BoundaryRecord0:\n\s+\.db\s+0/);
  assert.match(proof, /BoundaryRecord1:\n\s+\.db\s+31,"ABCDEFGHIJKLMNOPQRSTUVWXYZ12345"/);
  assert.match(proof, /BoundaryReservedKeys:\n\s+\.db\s+9,"dl",0/);
  assert.match(proof, /BoundaryCursorCase1:/);
  assert.match(proof, /BoundaryCursorCase9:/);
  assert.match(proof, /CALL\s+BoundarySaveCursor/);
  assert.match(runner, /editor-mutation-boundary-proof/);
  assert.match(runner, /verifyEditorMutationBoundaryProof/);
  assert.match(runner, /text: 'Z'/);
  assert.match(runner, /text: 'ABCDEFGHIJKLMNOPQRSTUVWXYZ12345'/);
  assert.match(runner, /text: 'ABCDE'/);
  assert.match(runner, /text: 'ABDE'/);
  assert.match(runner, /text: 'XYZ!'/);
  assert.match(runner, /text: 'dl'/);
  assert.match(runner, /BoundaryCursorCase1', row: 0, col: 0/);
  assert.match(runner, /BoundaryCursorCase4', row: 1, col: 0/);
  assert.match(runner, /BoundaryCursorCase6', row: 2, col: 5/);
  assert.match(runner, /BoundaryCursorCase8', row: 4, col: 4/);
  assert.match(runner, /BoundaryCursorCase9', row: 5, col: 2/);
  assert.match(runner, /expected 2/);
  assert.match(packageJson, /"proof:display:editor-mutation-boundary"/);
  assert.match(packageJson, /proof:display:editor-mutation-boundary/);
});
