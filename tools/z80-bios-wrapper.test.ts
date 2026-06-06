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

  assert.match(source, /CALL\s+BiosFileOpen/);
  assert.match(source, /CALL\s+BiosFileReadSector/);
  assert.doesNotMatch(source, /CALL\s+MON3_(?:OPEN_FILE|READ_SECTOR|WRITE_SECTOR)/);
});

test('TECM8 BIOS display contract is documented for GLCD wrappers', () => {
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
  assert.match(source, /;!\s+out\s+carry\n;!\s+clobbers\s+A,BC,DE,HL,zero,sign,parity,halfCarry\n@BiosDisplayInit:/);
  assert.match(source, /;!\s+in\s+B,C\n;!\s+out\s+carry\n;!\s+clobbers\s+A,BC,DE,HL,zero,sign,parity,halfCarry\n@BiosDisplaySetCursor:/);
  assert.match(source, /;!\s+in\s+A,B,C\n;!\s+out\s+A,carry\n;!\s+clobbers\s+A,BC,DE,HL,zero,sign,parity,halfCarry\n@BiosDisplayDrawCharAt:/);
  assert.match(source, /MON3_MATRIX_SCAN\s+\.equ\s+0xCC40/);
  assert.match(source, /MON3_MATRIX_SCAN_ASCII\s+\.equ\s+0xD0CB/);
  assert.match(source, /MON3_PARSE_MATRIX_SCAN\s+\.equ\s+0xD142/);
  assert.match(source, /MON3_GET_CAPS\s+\.equ\s+0xCFCA/);
  assert.match(source, /MON3_TOGGLE_CAPS\s+\.equ\s+0xD02B/);
  assert.match(source, /TECM8_BIOS_KEY_MOD_SHIFT\s+\.equ\s+0x01/);
  assert.match(source, /TECM8_BIOS_KEY_MOD_CTRL\s+\.equ\s+0x02/);
  assert.match(source, /TECM8_BIOS_KEY_MOD_FN\s+\.equ\s+0x04/);
  assert.match(source, /TECM8_BIOS_KEY_MOD_ALT\s+\.equ\s+0x08/);
  assert.match(source, /CALL\s+MON3_MATRIX_SCAN\n\s+CALL\s+MON3_PARSE_MATRIX_SCAN/);
  assert.match(source, /@BiosInputPollKey:/);
  assert.match(source, /CP\s+0x07\n\s+JR\s+Z,BiosInputPollKeyToggleCaps/);
  assert.match(source, /CP\s+3\n\s+JR\s+NZ,BiosInputPollKeyNoRaw/);
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
