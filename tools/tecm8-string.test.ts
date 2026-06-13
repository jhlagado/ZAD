const { strict: assert } = require('node:assert');
const { existsSync, readFileSync } = require('node:fs');
const { resolve } = require('node:path');
const { test } = require('node:test');

const root = resolve(__dirname, '..');

function readRepoFile(path: string): string {
  return readFileSync(resolve(root, path), 'utf8');
}

test('shared string helper proof covers bounded copy boundary behavior', () => {
  assert.ok(existsSync(resolve(root, 'proofs/shared/tecm8-string-proof.asm')));
  const proof = readRepoFile('proofs/shared/tecm8-string-proof.asm');
  const runner = readRepoFile('tools/run-tecm8-string-proof.ts');
  const packageJson = readRepoFile('package.json');

  assert.match(proof, /CALL\s+Tecm8StringCopyNulBounded/);
  assert.match(proof, /AssertCopyZeroCapacity/);
  assert.match(proof, /AssertCopyExactFit/);
  assert.match(proof, /AssertCopyOverflow/);
  assert.match(proof, /\.include\s+"..\/..\/src\/tecm8-string\.asm"/);
  assert.ok(
    proof.indexOf('@Start:') < proof.indexOf('.include "../../src/tecm8-string.asm"'),
    'byte-emitting shared string helpers must not be included before proof entry'
  );
  assert.match(runner, /tecm8-string-proof\.asm/);
  assert.match(runner, /CopyCaseMarker/);
  assert.match(packageJson, /"proof:tecm8-string"/);
  assert.match(packageJson, /proof:tecm8-string/);
});
