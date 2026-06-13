const { strict: assert } = require('node:assert');
const { readFileSync } = require('node:fs');
const { resolve } = require('node:path');
const { test } = require('node:test');

const root = resolve(__dirname, '..');

function readRepoFile(path: string): string {
  return readFileSync(resolve(root, path), 'utf8');
}

test('TECM8 BIOS storage wrappers are real assembly entry points', () => {
  const source = readRepoFile('src/tecm8-bios.asm');

  for (const label of [
    '@BiosFileOpen:',
    '@BiosFileReadSector:',
    '@BiosFileWriteSector:',
  ]) {
    assert.match(source, new RegExp(`^${label}`, 'm'));
  }
});

test('project config storage loader calls TECM8 BIOS wrappers', () => {
  const source = readRepoFile('src/project-config-loader.asm');
  const storageProof = readRepoFile('proofs/project-config/project-config-storage-proof.asm');
  const storageSource = readRepoFile('src/tecm8-storage.asm');

  assert.match(source, /CALL\s+BiosFileOpen/);
  assert.match(source, /CALL\s+BiosFileReadSector/);
  assert.match(source, /CALL\s+Tecm8StringMatchBytes/);
  assert.match(storageSource, /^@Tecm8StorageBlockToOffset:/m);
  assert.match(source, /CALL\s+Tecm8StorageBlockToOffset/);
  assert.doesNotMatch(source, /@ProjectLoadMatchBytes:/);
  assert.doesNotMatch(source, /@ProjectLoadBlockToOffset:/);
  assert.match(storageProof, /\.include\s+"..\/..\/src\/tecm8-string\.asm"/);
  assert.match(storageProof, /\.include\s+"..\/..\/src\/tecm8-storage\.asm"/);
  assert.doesNotMatch(source, /CALL\s+MON3_(?:OPEN_FILE|READ_SECTOR|WRITE_SECTOR)/);
});

test('storage helper includes stay after proof entry trampolines', () => {
  for (const path of [
    'proofs/project-config/project-config-storage-proof.asm',
    'proofs/display/editor-viewport-storage-proof.asm',
    'proofs/display/editor-file-list-proof.asm',
  ]) {
    const source = readRepoFile(path);
    const startIndex = source.indexOf('@Start:');
    const storageIndex = source.indexOf('.include "../../src/tecm8-storage.asm"');
    const loaderIndex = source.search(/\.include "\.\.\/\.\.\/src\/(?:project-config-loader|editor-storage-loader)\.asm"/);

    assert.notEqual(startIndex, -1, `${path} should expose a 4000h entry`);
    assert.ok(storageIndex > startIndex, `${path} should include storage helper after entry code`);
    assert.ok(loaderIndex > storageIndex, `${path} should include storage helper before storage loader`);
  }
});

test('TECM8 BIOS display API is documented for GLCD wrappers', () => {
  const docs = readRepoFile('docs/tecm8-bios-api.md');

  for (const name of [
    'BiosDisplayInit',
    'BiosDisplayClear',
    'BiosDisplaySetCursor',
    'BiosDisplayPutChar',
    'BiosDisplayPutString',
    'BiosDisplayDrawCharAt',
    'BiosDisplayUpdate',
    'BiosDisplaySetBitmapMode',
    'BiosInputPollAscii',
    'BiosInputPollKey',
  ]) {
    assert.match(docs, new RegExp(`\\b${name}\\b`));
  }
});

test('TECM8 BIOS GLCD display wrappers are real assembly entry points', () => {
  const source = readRepoFile('src/tecm8-bios.asm');
  const equates = readRepoFile('src/tecm8-equates.asm');

  for (const label of [
    'BiosDisplayInit',
    'BiosDisplayClear',
    'BiosDisplaySetCursor',
    'BiosDisplayPutChar',
    'BiosDisplayPutString',
    'BiosDisplayDrawCharAt',
    'BiosDisplayUpdate',
    'BiosDisplaySetBitmapMode',
    'BiosInputPollAscii',
    'BiosInputPollKey',
  ]) {
    assert.match(source, new RegExp(`^@${label}:`, 'm'));
  }
  assert.match(source, /@BiosDisplayInit:\n\s+CALL\s+MON3_GLCD_INIT_TERMINAL\n\s+CALL\s+MON3_GLCD_CLEAR_GBUF\n\s+CALL\s+MON3_GLCD_PLOT_TO_LCD/);
  assert.match(source, /@BiosDisplayClear:\n\s+CALL\s+MON3_GLCD_CLEAR_GBUF\n\s+CALL\s+MON3_GLCD_PLOT_TO_LCD/);
  assert.doesNotMatch(source, /@BiosDisplayClear:\n\s+CALL\s+MON3_GLCD_INIT_TERMINAL/);
  assert.match(source, /MON3_MATRIX_SCAN\s+\.equ\s+0xCC40/);
  assert.match(source, /MON3_MATRIX_SCAN_ASCII\s+\.equ\s+0xD0CB/);
  assert.match(source, /MON3_PARSE_MATRIX_SCAN\s+\.equ\s+0xD142/);
  assert.match(source, /MON3_GET_CAPS\s+\.equ\s+0xCFCA/);
  assert.match(source, /MON3_TOGGLE_CAPS\s+\.equ\s+0xD02B/);
  assert.match(source, /TECM8_BIOS_KEY_MOD_SHIFT\s+\.equ\s+TECM8_KEY_MOD_SHIFT/);
  assert.match(source, /TECM8_BIOS_KEY_MOD_CTRL\s+\.equ\s+TECM8_KEY_MOD_CTRL/);
  assert.match(source, /TECM8_BIOS_KEY_MOD_FN\s+\.equ\s+TECM8_KEY_MOD_FN/);
  assert.match(source, /TECM8_BIOS_KEY_MOD_ALT\s+\.equ\s+TECM8_KEY_MOD_ALT/);
  assert.match(equates, /TECM8_KEY_MOD_SHIFT\s+\.equ\s+0x01/);
  assert.match(equates, /TECM8_KEY_MOD_CTRL\s+\.equ\s+0x02/);
  assert.match(equates, /TECM8_KEY_MOD_FN\s+\.equ\s+0x04/);
  assert.match(equates, /TECM8_KEY_MOD_ALT\s+\.equ\s+0x08/);
  assert.match(source, /CALL\s+MON3_MATRIX_SCAN\n\s+CALL\s+MON3_PARSE_MATRIX_SCAN/);
  assert.match(source, /@BiosInputPollKey:/);
  assert.match(source, /CP\s+0x07\n\s+JR\s+Z,BiosInputPollKeyToggleCaps/);
  assert.match(source, /CP\s+3\n\s+JR\s+NZ,BiosInputPollKeyNoRaw/);
  assert.match(source, /CALL\s+BiosInputIgnoreStandaloneModifier\n\s+RET\s+NC/);
  assert.match(source, /^@BiosInputIgnoreStandaloneModifier:/m);
  assert.match(source, /CALL\s+MON3_MATRIX_SCAN_ASCII/);
  assert.match(source, /CALL\s+BiosInputNormalizeControlKey/);
  assert.match(source, /^@BiosInputNormalizeControlKey:/m);
  assert.match(source, /AND\s+TECM8_BIOS_KEY_MOD_CTRL/);
  assert.match(source, /CP\s+"A"/);
  assert.match(source, /CP\s+"z" \+ 1/);
  assert.match(source, /CALL\s+MON3_TOGGLE_CAPS/);
  assert.match(source, /BiosInputModifierBits:\n\s+\.db\s+0/);
});

test('GLCD display smoke proof calls TECM8 BIOS display wrappers', () => {
  const source = readRepoFile('proofs/display/glcd-smoke-proof.asm');

  for (const label of [
    'BiosDisplayInit',
    'BiosDisplayClear',
    'BiosDisplaySetCursor',
    'BiosDisplayPutChar',
    'BiosDisplayPutString',
    'BiosDisplaySetBitmapMode',
    'BiosDisplayUpdate',
  ]) {
    assert.match(source, new RegExp(`CALL\\s+${label}`));
  }
});
