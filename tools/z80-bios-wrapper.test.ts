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
