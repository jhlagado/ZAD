const { strict: assert } = require('node:assert');
const { readFileSync } = require('node:fs');
const { resolve } = require('node:path');
const { test } = require('node:test');

const root = resolve(__dirname, '..');
const sourcePath = resolve(root, 'src/keyboard-tester.main.asm');
const packagePath = resolve(root, 'package.json');

test('keyboard tester is a standalone 4000h diagnostic target', () => {
  const source = readFileSync(sourcePath, 'utf8');

  assert.match(source, /\.org\s+0x4000/);
  assert.match(source, /@Start:/);
  assert.match(source, /CALL\s+BiosInputPollKey/);
  assert.match(source, /\.include\s+"glcd-tile\.asm"/);
  assert.match(source, /\.include\s+"tecm8-bios\.asm"/);
});

test('keyboard tester renders ctrl and alt chords distinctly', () => {
  const source = readFileSync(sourcePath, 'utf8');

  assert.match(source, /TECM8_BIOS_KEY_MOD_CTRL/);
  assert.match(source, /TECM8_BIOS_KEY_MOD_ALT/);
  assert.match(source, /LD\s+A,"\^"/);
  assert.match(source, /KbdTestAppendSpecialUp:[\s\S]*?LD\s+A,"\^"/);
  assert.match(source, /KbdTestAppendSpecialDown:[\s\S]*?LD\s+A,"_"/);
  assert.match(source, /KbdTestAppendSpecialLeft:[\s\S]*?LD\s+A,"<"/);
  assert.match(source, /KbdTestAppendSpecialRight:[\s\S]*?LD\s+A,">"/);
  assert.doesNotMatch(source, /KbdTestAppendSpecialUp:[\s\S]*?LD\s+A,"U"/);
  assert.doesNotMatch(source, /KbdTestAppendSpecialDown:[\s\S]*?LD\s+A,"D"/);
  assert.doesNotMatch(source, /KbdTestAppendSpecialLeft:[\s\S]*?LD\s+A,"L"/);
  assert.doesNotMatch(source, /KbdTestAppendSpecialRight:[\s\S]*?LD\s+A,"R"/);
  assert.match(source, /LD\s+A,0x5C/);
  assert.match(source, /@KbdTestAppendCtrlName:/);
  assert.match(source, /@KbdTestAppendChordName:/);
});

test('keyboard tester exposes raw matrix bytes for diagnostics', () => {
  const source = readFileSync(sourcePath, 'utf8');

  assert.match(source, /CALL\s+KbdTestAppendHexByte/);
  assert.match(source, /@KbdTestWriteHexByte:/);
  assert.match(source, /@KbdTestAppendHexByte:/);
  assert.match(source, /KbdTestRawSecondary/);
  assert.match(source, /KbdTestRawPrimary/);
});

test('keyboard tester target has a package script', () => {
  const packageJson = JSON.parse(readFileSync(packagePath, 'utf8')) as { scripts: Record<string, string> };

  assert.equal(
    packageJson.scripts['debug80:keyboard-tester'],
    'node --experimental-strip-types tools/build-keyboard-tester.ts',
  );
});
