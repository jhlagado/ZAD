/**
 * Shared helpers for the structural test suite.
 *
 * The structural tests read repository files (assembly modules, docs, proof
 * sources) and assert on their contents. This module owns the repo-root
 * resolution they all share. The `export type` below is erased by Node's
 * type stripping, so at runtime this remains a plain CJS module.
 */

const { existsSync, readFileSync } = require('node:fs');
const { resolve } = require('node:path');

const root = resolve(__dirname, '..');

function readRepoFile(path: string): string {
  return readFileSync(resolve(root, path), 'utf8');
}

function repoFileExists(path: string): boolean {
  return existsSync(resolve(root, path));
}

const testSupportExports = { root, readRepoFile, repoFileExists };

export type TestSupport = typeof testSupportExports;

module.exports = testSupportExports;
