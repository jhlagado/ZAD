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

  assert.match(source, /^@EditorViewportRender:/m);
  assert.match(source, /^@EditorViewportRenderRecordRow:/m);
  assert.match(source, /^@EditorViewportSetTopRow:/m);
  assert.match(source, /^@EditorViewportSetColOffset:/m);
  assert.match(source, /^@EditorViewportTopRecordPtr:/m);
  assert.match(source, /;!\s+in\s+HL\n;!\s+out\s+A,carry\n;!\s+clobbers\s+A,BC,DE,HL,zero,sign,parity,halfCarry\n@EditorViewportRender:/);
  assert.match(source, /;!\s+in\s+A,HL\n;!\s+out\s+A,carry\n;!\s+clobbers\s+A,BC,DE,HL,zero,sign,parity,halfCarry\n@EditorViewportRenderRecordRow:/);

  for (const constant of [
    'TECM8_EDITOR_RECORD_BYTES',
    'TECM8_EDITOR_VISIBLE_ROWS',
    'TECM8_EDITOR_MAX_RECORD_TEXT',
    'TECM8_EDITOR_RECORD_LENGTH_MASK',
    'TECM8_EDITOR_ROW_TEXT_BYTES',
  ]) {
    assert.match(source, new RegExp(`^${constant}\\s+\\.equ`, 'm'));
  }

  assert.match(source, /AND\s+TECM8_EDITOR_RECORD_LENGTH_MASK/);
  assert.match(source, /^TECM8_EDITOR_VISIBLE_ROWS\s+\.equ\s+10$/m);
  assert.match(source, /^TECM8_EDITOR_VISIBLE_COLS\s+\.equ\s+20$/m);
  assert.match(source, /EditorViewportTopRow:\n\s+\.db\s+0/);
  assert.match(source, /EditorViewportColOffset:\n\s+\.db\s+0/);
  assert.match(source, /EditorRecordBasePtr:\n\s+\.dw\s+0/);
  assert.match(source, /CALL\s+EditorViewportTopRecordPtr/);
  assert.match(source, /LD\s+A,\(EditorViewportColOffset\)/);
  assert.match(source, /^@EditorViewportRenderStatusOverlay:/m);
  assert.match(source, /^@EditorViewportRestoreStatusRow:/m);
  assert.match(source, /^@EditorViewportRowTextPtr:/m);
  assert.match(source, /^@EditorViewportSetCurrentRow:/m);
  assert.match(source, /^@EditorViewportMarkerForRow:/m);
  assert.match(source, /^@EditorViewportRenderRowMarker:/m);
  assert.match(source, /^@EditorViewportStoreDescriptorMarker:/m);
  assert.match(source, /EditorViewportRenderRowMarkerCount:\n\s+\.db\s+0/);
  assert.match(source, /LD\s+A,TECM8_DISPLAY_STATUS_ROW/);
  assert.match(source, /LD\s+HL,EditorRowText9/);
  assert.match(source, /CALL\s+DisplayRenderLine/);
  assert.match(source, /CALL\s+GlcdTileFlushFull/);
  assert.doesNotMatch(source, /EditorViewportSelectBottom/);
  assert.doesNotMatch(source, /EditorScreenBottomPtr/);
  assert.doesNotMatch(source, /EditorTopChrome/);
  assert.doesNotMatch(source, /EditorBottomChrome/);
  assert.match(source, /EditorPromptActive:\n\s+\.db\s+0/);
  assert.match(source, /EditorPromptResult:\n\s+\.db\s+0/);
  assert.match(source, /EditorPromptTextPtr:\n\s+\.dw\s+EditorPromptDefaultText/);
  assert.match(source, /CALL\s+DisplayRenderScreen/);
  assert.match(source, /EditorRowText8:\n\s+\.ds\s+TECM8_EDITOR_ROW_TEXT_BYTES/);
  assert.match(source, /EditorRowText9:\n\s+\.ds\s+TECM8_EDITOR_ROW_TEXT_BYTES/);
});

test('editor viewport proof builds records and renders through the display model', () => {
  assert.ok(existsSync(resolve(root, 'proofs/display/editor-viewport-proof.asm')));
  const source = readRepoFile('proofs/display/editor-viewport-proof.asm');

  assert.match(source, /CALL\s+EditorViewportRender/);
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
  assert.doesNotMatch(runner, /requiresVisiblePixels/);
  assert.match(runner, /EditorRowText0/);
  assert.match(runner, /EditorRowText9/);
  assert.match(runner, /editor viewport proof copied/);
  assert.match(runner, /editor viewport proof missing current-row gutter bits/);
  assert.match(runner, /editor viewport proof unexpected stale gutter bits/);
});

test('editor viewport metadata-record proof is wired into package checks', () => {
  assert.ok(existsSync(resolve(root, 'proofs/display/editor-viewport-metadata-record-proof.asm')));
  const packageJson = readRepoFile('package.json');
  const source = readRepoFile('proofs/display/editor-viewport-metadata-record-proof.asm');

  assert.match(packageJson, /"proof:display:editor-viewport:metadata-record"/);
  assert.match(packageJson, /proof:display:editor-viewport:metadata-record/);
  assert.match(source, /CALL\s+EditorViewportRender/);
  assert.match(source, /\.db\s+0xA8,"META ROW"/);
  assert.match(source, /\.db\s+0xFF,"ABCDEFGHIJKLMNOPQRSTUVWXYZ12345"/);
});
