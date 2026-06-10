const { strict: assert } = require('node:assert');
const { test } = require('node:test');

import type { TestSupport } from './test-support';

const { readRepoFile, repoFileExists }: TestSupport = require('./test-support.ts');

test('editor navigation module exposes open, render, and page movement entries', () => {
  const source = readRepoFile('src/editor-navigation.asm');

  for (const name of [
    'EditorOpenMain',
    'EditorOpenPath',
    'EditorRenderCurrent',
    'EditorRenderPageBuffer',
    'EditorSaveCurrentPage',
    'EditorBackupCurrentPage',
    'EditorLoadCurrentBackupPage',
    'EditorClearDirty',
    'EditorNavResetViewport',
    'EditorNavSyncViewport',
    'EditorPageDown',
    'EditorPageUp',
    'EditorNavDeriveBackupPath',
    'EditorNavShowStatus',
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
  assert.match(source, /TECM8_EDITOR_NAV_CACHE_BASE\s+\.equ\s+0x3000/);
  assert.match(source, /EditorNavCachePageBuffer\s+\.equ\s+TECM8_EDITOR_NAV_CACHE_BASE/);
  assert.match(source, /EditorNavPageBuffer:\n\s+\.ds\s+TECM8_EDITOR_NAV_PAGE_BYTES/);
  assert.match(source, /TECM8_EDITOR_NAV_WINDOW_BYTES\s+\.equ\s+1024/);
  assert.match(source, /EditorNavNextPageBuffer:\n\s+\.ds\s+TECM8_EDITOR_NAV_PAGE_BYTES/);
  assert.match(source, /EditorNavDirtySectors:\n\s+\.db\s+0/);
  assert.match(source, /EditorNavViewportTopRow:\n\s+\.db\s+0/);
  assert.match(source, /EditorNavCurrentRow:\n\s+\.db\s+0/);
  assert.match(source, /EditorNavCachedPageDirty:\n\s+\.db\s+0/);
  assert.match(source, /EditorNavNextPageNumber:\n\s+\.db\s+0/);
});

test('editor navigation commits page movement only after successful render', () => {
  const source = readRepoFile('src/editor-navigation.asm');

  assert.match(source, /CALL\s+EditorNavRenderPage\n\s+RET\s+C\n\s+LD\s+A,\(EditorNavPendingPage\)\n\s+LD\s+\(EditorNavCurrentPage\),A/);
  assert.match(source, /CALL\s+EditorLoadSourcePage/);
  assert.match(source, /@EditorRenderCurrent:\n\s+LD\s+A,\(EditorNavCurrentPage\)\n\s+CALL\s+EditorNavRenderPage\n\s+RET\s+C\n\s+CALL\s+EditorNavLoadNextWindowPage\n\s+RET\s+C\n\s+JP\s+EditorClearDirty/);
  assert.match(source, /@EditorRenderPageBuffer:[\s\S]*?CALL\s+EditorNavSyncViewport\n\s+RET\s+C[\s\S]*?CALL\s+EditorViewportRender/);
  assert.match(source, /@EditorNavResetViewport:[\s\S]*?CALL\s+EditorViewportSetTopRow[\s\S]*?CALL\s+EditorViewportSetColOffset[\s\S]*?JP\s+EditorViewportSetCurrentRow/);
  assert.match(source, /@EditorNavSyncViewport:[\s\S]*?LD\s+A,\(EditorNavCurrentRow\)[\s\S]*?JP\s+EditorViewportSetCurrentRow/);
  assert.match(source, /@EditorSaveCurrentPage:\n\s+LD\s+HL,EditorStatusSavingText\n\s+CALL\s+EditorNavShowStatus\n\s+RET\s+C\n\s+CALL\s+EditorBackupCurrentPage/);
  assert.match(source, /CALL\s+EditorClearDirty\n\s+JP\s+EditorViewportRestoreStatusRow/);
  assert.match(source, /EditorSaveCurrentPageRestoreError:\n\s+PUSH\s+AF\n\s+CALL\s+EditorViewportRestoreStatusRow\n\s+POP\s+AF\n\s+RET/);
  assert.match(source, /CALL\s+EditorNavDeriveBackupPath/);
  assert.match(source, /@EditorLoadCurrentBackupPage:/);
  assert.match(source, /LD\s+HL,EditorStatusLoadingText\n\s+CALL\s+EditorNavShowStatus\n\s+RET\s+C\n\s+LD\s+A,\(EditorNavCurrentPage\)/);
  assert.match(source, /CALL\s+EditorLoadSourcePage\n\s+JR\s+C,EditorLoadCurrentBackupPageRestoreError\n\s+XOR\s+A\n\s+RET/);
  assert.match(source, /EditorLoadCurrentBackupPageRestoreError:\n\s+PUSH\s+AF\n\s+CALL\s+EditorViewportRestoreStatusRow\n\s+POP\s+AF\n\s+RET/);
  assert.match(source, /LD\s+DE,EditorNavBackupPathBuffer/);
  assert.match(source, /LD\s+HL,EditorNavBackupPageBuffer/);
  assert.match(source, /CALL\s+EditorSaveSourcePage/);
  assert.match(source, /JP\s+EditorRenderPageBuffer/);
  assert.match(source, /@EditorNavRememberCurrentPage:/);
  assert.match(source, /@EditorNavRenderCachedPendingPage:/);
  assert.match(source, /@EditorNavRenderNextWindowPage:/);
  assert.match(source, /@EditorNavLoadNextWindowPage:/);
  assert.match(source, /@EditorNavCopyCachedPageToNext:/);
  assert.match(source, /LD\s+A,\(EditorNavCachedPage\)\n\s+CP\s+B\n\s+JR\s+NZ,EditorNavLoadNextWindowFromDisk\n\s+CALL\s+EditorNavCopyCachedPageToNext/);
  assert.match(source, /@EditorMarkCurrentSectorDirty:/);
  assert.match(source, /@EditorNavRefreshAggregateDirty:/);
  assert.match(source, /@EditorNavSwapCachePage:/);
  assert.match(source, /CALL\s+EditorNavRenderNextWindowPage/);
  assert.match(source, /EditorNavCommitPendingPagePreserveDirty:/);
  assert.match(source, /@EditorNavRenderPage:\n\s+LD\s+\(EditorNavRenderPageInput\),A\n\s+LD\s+HL,EditorStatusLoadingText\n\s+CALL\s+EditorNavShowStatus/);
  assert.match(source, /EditorNavRenderPageRestoreError:\n\s+PUSH\s+AF\n\s+CALL\s+EditorViewportRestoreStatusRow\n\s+POP\s+AF\n\s+RET/);
  assert.match(source, /EditorNavPathPtr:\n\s+\.dw\s+0/);
  assert.match(source, /EditorNavPathBuffer:\n\s+\.ds\s+TECM8_EDITOR_NAV_PATH_LEN/);
  assert.match(source, /CALL\s+EditorNavCopyPath/);
  assert.match(source, /CALL\s+EditorViewportRender/);
  assert.match(source, /CALL\s+GlcdTileFlushFull/);
  assert.match(source, /EditorStatusLoadingText:\n\s+\.db\s+"Loading\.\.\.",0/);
  assert.match(source, /EditorStatusSavingText:\n\s+\.db\s+"Saving\.\.\.",0/);
  assert.match(source, /EditorStatusCleanText:\n\s+\.db\s+"Clean",0/);
  assert.match(source, /EditorStatusSaveFirstText:\n\s+\.db\s+"Save first",0/);
  assert.match(source, /EditorStatusUnknownKeyText:\n\s+\.db\s+"KEY",0/);
  assert.match(source, /TECM8_EDITOR_NAV_ERR_PAGE\s+\.equ\s+0x50/);
});

test('editor navigation proof drives page state over storage-backed source', () => {
  assert.ok(repoFileExists('proofs/display/editor-navigation-proof.asm'));
  const proof = readRepoFile('proofs/display/editor-navigation-proof.asm');
  const runner = readRepoFile('tools/run-editor-viewport-storage-proof.ts');
  const packageJson = readRepoFile('package.json');

  assert.match(proof, /CALL\s+EditorOpenMain/);
  assert.match(proof, /CALL\s+EditorPageDown/);
  assert.match(proof, /LD\s+A,TECM8_EDITOR_KEY_ARROW_UP\n\s+LD\s+B,TECM8_EDITOR_KEY_MOD_ALT\n\s+CALL\s+EditorRunModifiedKey/);
  assert.match(proof, /LD\s+A,TECM8_EDITOR_KEY_ARROW_DOWN\n\s+LD\s+B,TECM8_EDITOR_KEY_MOD_CTRL\n\s+CALL\s+EditorRunModifiedKey/);
  assert.match(proof, /\.include\s+"..\/..\/src\/editor-navigation\.asm"/);
  assert.match(runner, /editor-navigation-proof/);
  assert.match(runner, /verifyNavigationProof/);
  assert.match(runner, /EditorNavCacheHitCount/);
  assert.match(readRepoFile('tools/proof/harness.ts'), /maxInstructions = 80_000_000/);
  assert.match(runner, /P8 LINE 07/);
  assert.match(packageJson, /"proof:display:editor-navigation"/);
  assert.match(packageJson, /proof:display:editor-navigation/);
});

test('editor window save proof covers cached next-window dirty persistence', () => {
  assert.ok(repoFileExists('proofs/display/editor-window-save-proof.asm'));
  const proof = readRepoFile('proofs/display/editor-window-save-proof.asm');
  const runner = readRepoFile('tools/run-editor-viewport-storage-proof.ts');
  const packageJson = readRepoFile('package.json');

  assert.match(proof, /CALL\s+EditorPageDown/);
  assert.match(proof, /CALL\s+EditorPageUp/);
  assert.match(proof, /CALL\s+EditorSplitLine/);
  assert.match(proof, /CALL\s+EditorSaveCurrentPage/);
  assert.match(runner, /verifyEditorWindowSaveProof/);
  assert.match(runner, /record: 16, text: 'PUSH'/);
  assert.match(packageJson, /"proof:display:editor-window-save"/);
  assert.match(packageJson, /proof:display:editor-window-save/);
});
