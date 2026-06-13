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

  assert.match(source, /^@EditorLoadMainSector:/m);
  assert.match(source, /^@EditorLoadMainPage:/m);
  assert.match(source, /^@EditorLoadSourcePage:/m);
  assert.match(source, /^@EditorSaveSourcePage:/m);
  assert.match(source, /^@EditorSaveSourcePageNoGrow:/m);
  assert.match(source, /@EditorLoadSourcePage:\n\s+PUSH\s+AF\n\s+XOR\s+A\n\s+LD\s+\(EditorLoadAllowShort\),A\n\s+LD\s+\(EditorSaveGrowMode\),A\n\s+POP\s+AF/);

  assert.match(source, /CALL\s+BiosFileOpen/);
  assert.match(source, /CALL\s+BiosFileReadSector/);
  assert.match(source, /CALL\s+BiosFileWriteSector/);
  assert.match(source, /EditorLoadVolumeName:\n\s+\.db\s+"VOLUME\.TM8",0/);
  assert.match(source, /CP\s+128\n\s+JP\s+NC,EditorLoadPageErr/);
  assert.match(source, /LD\s+\(EditorLoadBlockSteps\),A/);
  assert.match(source, /CALL\s+EditorLoadResolveSourceBlock/);
  assert.match(source, /CALL\s+EditorLoadResolveNextBlock/);
  assert.match(source, /@EditorLoadResolveNextBlock:/);
  assert.match(source, /JP\s+NZ,EditorSaveReadOrGrowAllocationEntry/);
  assert.match(source, /JP\s+EditorLoadReadAllocationEntry/);
  assert.match(source, /@EditorSaveReadOrGrowAllocationEntry:/);
  assert.match(source, /CALL\s+EditorCreateFindFreeBlock/);
  assert.match(source, /CALL\s+EditorCreateMarkAllocatedBlock/);
  assert.match(source, /CALL\s+EditorCreateUpdateSuperblock\n\s+RET\s+C\n\s+JP\s+EditorCreateBlankCreatedSource/);
  assert.match(source, /CALL\s+EditorSaveWriteAllocationEntryValue/);
  assert.match(source, /CALL\s+EditorLoadWriteSourceSector/);
  assert.match(source, /CALL\s+EditorSaveExtendCatalogSize/);
  assert.match(source, /EditorSaveGrowMode:\n\s+\.db\s+0/);
  assert.match(source, /@EditorSaveExtendCatalogSize:[\s\S]*?LD\s+A,\(EditorSaveRequiredSizeUpper\)\n\s+CP\s+B/);
  assert.match(source, /EditorSaveCatalogUpdate:\n\s+LD\s+DE,\(EditorLoadCatalogEntryOffset\)\n\s+LD\s+HL,DISK_BUFF \+ 46\n\s+ADD\s+HL,DE/);
  assert.match(source, /LD\s+A,\(EditorSaveRequiredSizeHigh\)\n\s+LD\s+\(HL\),A\n\s+INC\s+HL\n\s+LD\s+A,\(EditorSaveRequiredSizeUpper\)/);
  assert.match(source, /JR\s+NC,EditorLoadAllocationOffsetOk\n\s+INC\s+D/);
  assert.match(source, /EditorLoadPageErr:\n\s+LD\s+A,EDITOR_LOAD_ERR_PAGE\n\s+SCF\n\s+RET/);
  assert.match(source, /@EditorCreateBlankCreatedSource:[\s\S]*?LD\s+HL,EditorCreateBlankPageBuffer[\s\S]*?CALL\s+EditorSaveSourcePageNoGrow/);
  assert.match(source, /CP\s+8\n\s+JR\s+NZ,EditorCreateBlankCreatedSourceLoop/);
  assert.match(source, /EditorCreateBlankPageBuffer:\n\s+\.ds\s+TM8_SECTOR_BYTES/);
});

test('editor storage loader finds /src/main.asm through TM8 prefix and catalog tables', () => {
  const source = readRepoFile('src/editor-storage-loader.asm');
  const stringSource = readRepoFile('src/tecm8-string.asm');
  const storageSource = readRepoFile('src/tecm8-storage.asm');

  for (const constant of [
    'TM8_PREFIX_SECTOR',
    'TM8_PREFIX_SECTORS',
    'TM8_PREFIX_ENTRY',
    'TM8_CATALOG_SECTOR',
    'TM8_CATALOG_SECTORS',
    'TM8_CATALOG_ENTRY',
  ]) {
    assert.match(storageSource, new RegExp(`^${constant}\\s+\\.equ`, 'm'));
  }
  assert.match(source, /^TM8_SOURCE_MIN_BYTES\s+\.equ/m);

  assert.match(source, /EditorLoadParseSourcePath:/);
  assert.match(source, /EditorLoadRootPrefix:/);
  assert.match(source, /EditorLoadPrefixPtr:\n\s+\.dw\s+0/);
  assert.match(source, /EditorLoadNamePtr:\n\s+\.dw\s+0/);
  assert.match(source, /EditorLoadMainPath:\n\s+\.db\s+"\/src\/main\.asm",0/);
  assert.match(source, /CALL\s+EditorLoadFindSourcePrefix/);
  assert.match(source, /CALL\s+EditorLoadFindSource/);
  assert.match(source, /CALL\s+Tecm8StringMatchBytes/);
  assert.match(source, /CALL\s+Tecm8StorageValidateCoreSuperblock/);
  assert.doesNotMatch(source, /EditorLoadMagic:/);
  assert.doesNotMatch(source, /@EditorLoadMatchBytes:/);
  assert.match(stringSource, /^@Tecm8StringMatchBytes:/m);
  assert.match(storageSource, /^@Tecm8StorageBlockToOffset:/m);
  assert.match(storageSource, /^@Tecm8StorageValidateCoreSuperblock:/m);
  assert.match(storageSource, /^@Tecm8StorageAdvanceSectorOffset:/m);
  assert.match(storageSource, /^@Tecm8StorageReadSectorPreserveOffset:/m);
  assert.match(source, /LD\s+\(EditorLoadFirstBlock\),DE/);
  assert.match(source, /CALL\s+Tecm8StorageBlockToOffset/);
  assert.match(source, /CALL\s+Tecm8StorageAdvanceSectorOffset/);
  assert.match(source, /CALL\s+Tecm8StorageReadSectorPreserveOffset/);
  assert.doesNotMatch(source, /@EditorLoadBlockToOffset:/);
});

test('editor storage loader validates the fixed TM8 v1 layout it depends on', () => {
  const source = readRepoFile('src/editor-storage-loader.asm');
  const storageSource = readRepoFile('src/tecm8-storage.asm');

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
    assert.match(storageSource, new RegExp(`^${constant}\\s+\\.equ`, 'm'));
  }

  for (const offset of ['12', '14', '16', '20', '22', '26', '28', '30', '34', '38', '40']) {
    assert.match(source, new RegExp(`LD\\s+HL,DISK_BUFF \\+ ${offset}`));
  }
  assert.match(storageSource, /LD\s+DE,21[\s\S]*?CP\s+TM8_CATALOG_START_BLOCK/);
  assert.match(storageSource, /LD\s+DE,3[\s\S]*?CP\s+TM8_CATALOG_ENTRY/);
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

  assert.match(source, /CALL\s+EditorLoadMainPage/);
  assert.match(source, /CALL\s+EditorViewportRender/);
  assert.match(source, /CALL\s+GlcdTileFlushFull/);
  assert.match(source, /\.include\s+"..\/..\/src\/tecm8-string\.asm"/);
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
  assert.match(invalidPage, /CALL\s+EditorLoadMainPage/);
  assert.match(invalidPage, /JR\s+NC,ProofFailed/);
  assert.match(invalidPage, /CP\s+EDITOR_LOAD_ERR_PAGE/);

  assert.match(smallFile, /LD\s+A,1/);
  assert.match(smallFile, /CALL\s+EditorLoadMainPage/);
  assert.match(smallFile, /JR\s+NC,ProofFailed/);
  assert.match(smallFile, /CP\s+EDITOR_LOAD_ERR_SIZE/);
});

test('storage-backed editor viewport runner verifies storage records and GLCD output', () => {
  const runner = readRepoFile('tools/run-editor-viewport-storage-proof.ts');
  const packageJson = readRepoFile('package.json');

  assert.match(packageJson, /"proof:display:editor-viewport:storage"/);
  assert.match(packageJson, /"proof:display:editor-viewport:storage:invalid-page"/);
  assert.match(packageJson, /"proof:display:editor-viewport:storage:small-file"/);
  assert.match(packageJson, /"proof:display:editor-page-write"/);
  assert.match(packageJson, /proof:display:editor-viewport:storage/);
  assert.match(packageJson, /proof:display:editor-page-write/);
  assert.match(runner, /importFileIntoVolumeImage\(volume, '\/src\/main\.asm', sourceRecords\)/);
  assert.doesNotMatch(runner, /importFileIntoVolumeImage\(volume, '\/src\/\.main\.asm\.b', sourceRecords\)/);
  assert.match(runner, /editor-page-write-proof/);
  assert.match(runner, /verifyEditorPageWriteProof/);
  assert.match(runner, /DirtyAfterNoopDelete/);
  assert.match(runner, /DirtyAfterNoopSplit/);
  assert.match(runner, /DirtyAfterNoopInsert/);
  assert.match(runner, /InitialRow9Bytes/);
  assert.match(runner, /PageUpBoundaryRow9Bytes/);
  assert.match(runner, /PageDownBoundaryRow9Bytes/);
  assert.doesNotMatch(runner, /TopStatusPtrAfterPageUp/);
  assert.doesNotMatch(runner, /EditorStatusTopText/);
  assert.doesNotMatch(runner, /EditorStatusEndText/);
  assert.match(runner, /DirtyAfterEdit/);
  assert.match(runner, /DirtyAfterSave/);
  assert.match(runner, /PromptActiveAfterIgnore/);
  assert.match(runner, /PromptResultAfterYes/);
  assert.match(runner, /PromptOverlayRow9Bytes/);
  assert.match(runner, /PromptRestoredRow9Bytes/);
  assert.match(runner, /readStatusRowTextByte/);
  assert.match(runner, /DirtyAfterRestoreNo/);
  assert.match(runner, /DirtyAfterRestoreEsc/);
  assert.match(runner, /DirtyAfterRestore/);
  assert.match(runner, /QuitAfterDirtyYes/);
  assert.match(runner, /RestoreRecord0FirstChar/);
  assert.match(runner, /editor backup persisted record 0/);
  assert.match(runner, /editor-viewport-storage-invalid-page-proof/);
  assert.match(runner, /editor-viewport-storage-small-file-proof/);
  assert.match(runner, /editor-allocation-growth-proof/);
  assert.match(runner, /verifyEditorAllocationGrowthProof/);
  assert.match(runner, /makeSmallFileLines/);
  assert.match(runner, /makeSingleBlockLines/);
  assert.match(runner, /TM8_NONCONTIGUOUS_SECOND_BLOCK\s+=\s+130/);
  assert.match(runner, /makePositiveProofVolume/);
  assert.match(runner, /writeUInt16LE\(TM8_NONCONTIGUOUS_SECOND_BLOCK/);
  assert.match(runner, /length:\s+144/);
  assert.match(runner, /P0 LINE 00/);
  assert.match(runner, /P1 LINE 15/);
  assert.match(runner, /P8 LINE 15/);
  assert.match(runner, /EditorRowText9/);
  assert.match(runner, /readSourceRecord/);
  assert.match(runner, /readFileFromProofImage/);
  assert.match(runner, /storage viewport copied/);
  assert.match(runner, /storage viewport loaded record/);
  assert.match(runner, /storage viewport proof did not render display row/);
  assert.match(runner, /registerCare:\s+'strict'/);
  assert.match(runner, /src\/mon3\.asmi/);
});
