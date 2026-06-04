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
    '@TECM8_BIOS_FILE_OPEN:',
    '@TECM8_BIOS_FILE_READ_SECTOR:',
    '@TECM8_BIOS_FILE_WRITE_SECTOR:',
  ]) {
    assert.match(source, new RegExp(`^${label}`, 'm'));
  }
});

test('project config storage loader calls TECM8 BIOS wrappers', () => {
  const source = readRepoFile('src/project-config-loader.asm');

  assert.match(source, /CALL\s+TECM8_BIOS_FILE_OPEN/);
  assert.match(source, /CALL\s+TECM8_BIOS_FILE_READ_SECTOR/);
  assert.doesNotMatch(source, /CALL\s+MON3_(?:OPEN_FILE|READ_SECTOR|WRITE_SECTOR)/);
});

test('TECM8 BIOS display contract is documented for GLCD wrappers', () => {
  const docs = readRepoFile('docs/tecm8-bios-api.md');

  for (const name of [
    'TECM8_BIOS_DISPLAY_INIT',
    'TECM8_BIOS_DISPLAY_CLEAR',
    'TECM8_BIOS_DISPLAY_SET_CURSOR',
    'TECM8_BIOS_DISPLAY_PUT_CHAR',
    'TECM8_BIOS_DISPLAY_PUT_STRING',
    'TECM8_BIOS_DISPLAY_DRAW_CHAR_AT',
    'TECM8_BIOS_DISPLAY_UPDATE',
    'TECM8_BIOS_DISPLAY_SET_BITMAP_MODE',
  ]) {
    assert.match(docs, new RegExp(`\\b${name}\\b`));
  }
});

test('TECM8 BIOS GLCD display wrappers are real assembly entry points', () => {
  const source = readRepoFile('src/tecm8-bios.asm');
  const iface = readRepoFile('src/tecm8-bios.asmi');

  for (const label of [
    'TECM8_BIOS_DISPLAY_INIT',
    'TECM8_BIOS_DISPLAY_CLEAR',
    'TECM8_BIOS_DISPLAY_SET_CURSOR',
    'TECM8_BIOS_DISPLAY_PUT_CHAR',
    'TECM8_BIOS_DISPLAY_PUT_STRING',
    'TECM8_BIOS_DISPLAY_DRAW_CHAR_AT',
    'TECM8_BIOS_DISPLAY_UPDATE',
    'TECM8_BIOS_DISPLAY_SET_BITMAP_MODE',
  ]) {
    assert.match(source, new RegExp(`^@${label}:`, 'm'));
    assert.match(iface, new RegExp(`^extern ${label}$`, 'm'));
  }
});

test('GLCD display smoke proof calls TECM8 BIOS display wrappers', () => {
  const source = readRepoFile('proofs/display/glcd-smoke-proof.asm');

  for (const label of [
    'TECM8_BIOS_DISPLAY_INIT',
    'TECM8_BIOS_DISPLAY_CLEAR',
    'TECM8_BIOS_DISPLAY_SET_CURSOR',
    'TECM8_BIOS_DISPLAY_PUT_CHAR',
    'TECM8_BIOS_DISPLAY_PUT_STRING',
    'TECM8_BIOS_DISPLAY_SET_BITMAP_MODE',
    'TECM8_BIOS_DISPLAY_UPDATE',
  ]) {
    assert.match(source, new RegExp(`CALL\\s+${label}`));
  }
});
