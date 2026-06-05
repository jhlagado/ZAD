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
  ]) {
    assert.match(source, new RegExp(`^@${label}:`, 'm'));
  }
  assert.match(source, /;!\s+out\s+carry\n;!\s+clobbers\s+A,BC,DE,HL,zero,sign,parity,halfCarry\n@BiosDisplayInit:/);
  assert.match(source, /;!\s+in\s+B,C\n;!\s+out\s+carry\n;!\s+clobbers\s+A,BC,DE,HL,zero,sign,parity,halfCarry\n@BiosDisplaySetCursor:/);
  assert.match(source, /;!\s+in\s+A,B,C\n;!\s+out\s+A,carry\n;!\s+clobbers\s+A,BC,DE,HL,zero,sign,parity,halfCarry\n@BiosDisplayDrawCharAt:/);
  assert.match(source, /MON3_MATRIX_SCAN\s+\.equ\s+0xCC40/);
  assert.match(source, /MON3_PARSE_MATRIX_SCAN\s+\.equ\s+0xD142/);
  assert.match(source, /CALL\s+MON3_MATRIX_SCAN\n\s+CALL\s+MON3_PARSE_MATRIX_SCAN/);
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
