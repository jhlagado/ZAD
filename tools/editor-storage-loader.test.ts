const { strict: assert } = require('node:assert');
const { existsSync, readFileSync } = require('node:fs');
const { resolve } = require('node:path');
const { test } = require('node:test');

const root = resolve(__dirname, '..');

function readRepoFile(path: string): string {
  return readFileSync(resolve(root, path), 'utf8');
}

test('editor storage loader exposes a fixed main-source sector entry point', () => {
  const source = readRepoFile('src/editor-storage-loader.asm');
  const iface = readRepoFile('src/editor-storage-loader.asmi');

  assert.match(source, /^@TECM8_EDITOR_LOAD_MAIN_SOURCE_SECTOR:/m);
  assert.match(source, /^@TECM8_EDITOR_LOAD_MAIN_SOURCE_PAGE:/m);
  assert.match(iface, /^extern TECM8_EDITOR_LOAD_MAIN_SOURCE_SECTOR$/m);
  assert.match(iface, /^extern TECM8_EDITOR_LOAD_MAIN_SOURCE_PAGE$/m);
  assert.match(iface, /^in HL$/m);
  assert.match(iface, /^in A,HL$/m);
  assert.match(iface, /^out A,carry$/m);

  assert.match(source, /CALL\s+TECM8_BIOS_FILE_OPEN/);
  assert.match(source, /CALL\s+TECM8_BIOS_FILE_READ_SECTOR/);
  assert.match(source, /EditorLoadVolumeName:\n\s+\.db\s+"VOLUME\.TM8",0/);
  assert.match(source, /CP\s+128\n\s+JR\s+NC,EditorLoadPageErr/);
  assert.match(source, /LD\s+\(EditorLoadBlockSteps\),A/);
  assert.match(source, /CALL\s+EditorLoadResolveSourceBlock/);
  assert.match(source, /CALL\s+EditorLoadReadAllocationEntry/);
  assert.match(source, /JR\s+NC,EditorLoadAllocationOffsetOk\n\s+INC\s+D/);
  assert.match(source, /EditorLoadPageErr:\n\s+LD\s+A,EDITOR_LOAD_ERR_PAGE\n\s+SCF\n\s+RET/);
});

test('editor storage loader finds /src/main.asm through TM8 prefix and catalog tables', () => {
  const source = readRepoFile('src/editor-storage-loader.asm');

  for (const constant of [
    'TM8_PREFIX_SECTOR',
    'TM8_PREFIX_SECTORS',
    'TM8_PREFIX_ENTRY',
    'TM8_CATALOG_SECTOR',
    'TM8_CATALOG_SECTORS',
    'TM8_CATALOG_ENTRY',
    'TM8_SOURCE_MIN_BYTES',
  ]) {
    assert.match(source, new RegExp(`^${constant}\\s+\\.equ`, 'm'));
  }

  assert.match(source, /EditorLoadSrcPrefix:\n\s+\.db\s+"src"/);
  assert.match(source, /EditorLoadMainName:\n\s+\.db\s+"main\.asm"/);
  assert.match(source, /CALL\s+EditorLoadFindSrcPrefix/);
  assert.match(source, /CALL\s+EditorLoadFindMainSource/);
  assert.match(source, /LD\s+\(EditorLoadFirstBlock\),DE/);
  assert.match(source, /CALL\s+EditorLoadBlockToOffset/);
});

test('editor storage loader validates the fixed TM8 v1 layout it depends on', () => {
  const source = readRepoFile('src/editor-storage-loader.asm');

  for (const constant of [
    'TM8_TOTAL_BLOCKS',
    'TM8_VOLUME_BYTE_2',
    'TM8_ALLOC_START_BLOCK',
    'TM8_ALLOC_BLOCKS',
    'TM8_PREFIX_START_BLOCK',
    'TM8_PREFIX_BLOCKS',
    'TM8_PREFIX_COUNT',
    'TM8_CATALOG_START_BLOCK',
    'TM8_CATALOG_BLOCKS',
    'TM8_CATALOG_COUNT',
    'TM8_DATA_START_BLOCK',
  ]) {
    assert.match(source, new RegExp(`^${constant}\\s+\\.equ`, 'm'));
  }

  for (const offset of ['12', '14', '16', '20', '22', '26', '28', '30', '34', '36', '38', '40']) {
    assert.match(source, new RegExp(`LD\\s+HL,DISK_BUFF \\+ ${offset}`));
  }
});

test('editor storage loader preserves catalog hard-error carry and non-match state', () => {
  const source = readRepoFile('src/editor-storage-loader.asm');

  assert.match(source, /CP\s+EDITOR_LOAD_ERR_SIZE\n\s+JP\s+Z,EditorLoadReturnErr/);
  assert.match(source, /CP\s+EDITOR_LOAD_ERR_BLOCK\n\s+JP\s+Z,EditorLoadReturnErr/);
  assert.match(source, /EditorLoadEntryNo:\n\s+XOR\s+A\n\s+SCF\n\s+RET/);
  assert.match(source, /EditorLoadReturnErr:\n\s+SCF\n\s+RET/);
});

test('editor storage loader checks a 32-bit file size for the requested page', () => {
  const source = readRepoFile('src/editor-storage-loader.asm');

  assert.match(source, /LD\s+DE,46\n\s+ADD\s+HL,DE/);
  assert.match(source, /ADD\s+A,A\n\s+INC\s+A\n\s+LD\s+\(EditorLoadRequiredSizeHigh\),A/);
  assert.match(source, /INC\s+HL\n\s+LD\s+A,\(HL\)\n\s+OR\s+A\n\s+JR\s+NZ,EditorLoadSizeOk\n\s+INC\s+HL\n\s+LD\s+A,\(HL\)\n\s+OR\s+A\n\s+JR\s+NZ,EditorLoadSizeOk\n\s+LD\s+A,D\n\s+LD\s+B,A\n\s+LD\s+A,\(EditorLoadRequiredSizeHigh\)/);
  assert.match(source, /LD\s+A,\(EditorLoadSectorInBlock\)\n\s+ADD\s+A,A\n\s+ADD\s+A,D\n\s+LD\s+D,A/);
});

test('storage-backed editor viewport proof composes loader, viewport, and display update', () => {
  const proofPath = resolve(root, 'proofs/display/editor-viewport-storage-proof.asm');
  assert.ok(existsSync(proofPath));
  const source = readRepoFile('proofs/display/editor-viewport-storage-proof.asm');

  assert.match(source, /CALL\s+TECM8_EDITOR_LOAD_MAIN_SOURCE_PAGE/);
  assert.match(source, /CALL\s+TECM8_EDITOR_VIEWPORT_RENDER/);
  assert.match(source, /CALL\s+TECM8_BIOS_DISPLAY_UPDATE/);
  assert.match(source, /\.include\s+"..\/..\/src\/editor-storage-loader\.asm"/);
  assert.match(source, /EditorSourcePage0:\n\s+\.ds\s+512/);
  assert.match(source, /EditorSourcePage1:\n\s+\.ds\s+512/);
  assert.match(source, /LD\s+A,8\n\s+LD\s+HL,EditorSourcePage8/);
  assert.match(source, /EditorSourcePage8:\n\s+\.ds\s+512/);
});

test('storage-backed editor viewport negative proofs assert exact loader errors', () => {
  const invalidPage = readRepoFile('proofs/display/editor-viewport-storage-invalid-page-proof.asm');
  const smallFile = readRepoFile('proofs/display/editor-viewport-storage-small-file-proof.asm');

  assert.match(invalidPage, /LD\s+A,128/);
  assert.match(invalidPage, /CALL\s+TECM8_EDITOR_LOAD_MAIN_SOURCE_PAGE/);
  assert.match(invalidPage, /JR\s+NC,ProofFailed/);
  assert.match(invalidPage, /CP\s+EDITOR_LOAD_ERR_PAGE/);

  assert.match(smallFile, /LD\s+A,1/);
  assert.match(smallFile, /CALL\s+TECM8_EDITOR_LOAD_MAIN_SOURCE_PAGE/);
  assert.match(smallFile, /JR\s+NC,ProofFailed/);
  assert.match(smallFile, /CP\s+EDITOR_LOAD_ERR_SIZE/);
});

test('storage-backed editor viewport runner verifies storage records and GLCD output', () => {
  const runner = readRepoFile('tools/run-editor-viewport-storage-proof.ts');
  const packageJson = readRepoFile('package.json');

  assert.match(packageJson, /"proof:display:editor-viewport:storage"/);
  assert.match(packageJson, /"proof:display:editor-viewport:storage:invalid-page"/);
  assert.match(packageJson, /"proof:display:editor-viewport:storage:small-file"/);
  assert.match(packageJson, /proof:display:editor-viewport:storage/);
  assert.match(runner, /importFileIntoVolumeImage\(volume, '\/src\/main\.asm', sourceRecords\)/);
  assert.match(runner, /editor-viewport-storage-invalid-page-proof/);
  assert.match(runner, /editor-viewport-storage-small-file-proof/);
  assert.match(runner, /makeSmallFileLines/);
  assert.match(runner, /TM8_NONCONTIGUOUS_SECOND_BLOCK\s+=\s+130/);
  assert.match(runner, /makePositiveProofVolume/);
  assert.match(runner, /writeUInt16LE\(TM8_NONCONTIGUOUS_SECOND_BLOCK/);
  assert.match(runner, /length:\s+144/);
  assert.match(runner, /P0 LINE 00/);
  assert.match(runner, /P1 LINE 15/);
  assert.match(runner, /P8 LINE 15/);
  assert.match(runner, /readSourceRecord/);
  assert.match(runner, /storage viewport copied/);
  assert.match(runner, /storage viewport loaded record/);
  assert.match(runner, /storage viewport proof did not render display row/);
  assert.match(runner, /registerCare:\s+'strict'/);
  assert.match(runner, /src\/editor-storage-loader\.asmi/);
});
