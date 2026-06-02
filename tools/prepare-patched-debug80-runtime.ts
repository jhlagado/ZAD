#!/usr/bin/env node
/**
 * Prepare an isolated patched Debug80 runtime for the ZAD storage proof.
 *
 * This does not mutate the real Debug80 checkout. It copies the source needed
 * for build/test into /private/tmp, applies the ZAD Debug80 SD-SPI patch, then
 * compiles the runtime and runs the focused SD tests.
 */

const { cpSync, existsSync, mkdirSync, readFileSync, rmSync, symlinkSync, copyFileSync } = require('node:fs');
const { resolve, join } = require('node:path');
const { spawnSync } = require('node:child_process');

const ZAD_ROOT = resolve(__dirname, '..');
const DEFAULT_SOURCE = '/Users/johnhardy/projects/debug80';
const DEFAULT_TARGET = '/private/tmp/zad-debug80-patched';
const PATCH_PATH = resolve(ZAD_ROOT, 'patches/debug80-mon3-sd-spi.patch');

type Options = {
  source: string;
  target: string;
  skipTests: boolean;
};

function parseArgs(argv: string[]): Options {
  const valueAfter = (flag: string): string | undefined => {
    const index = argv.indexOf(flag);
    return index >= 0 ? argv[index + 1] : undefined;
  };
  return {
    source: resolve(valueAfter('--source') ?? process.env.DEBUG80_SOURCE_ROOT ?? DEFAULT_SOURCE),
    target: resolve(valueAfter('--target') ?? process.env.DEBUG80_PATCHED_ROOT ?? DEFAULT_TARGET),
    skipTests: argv.includes('--skip-tests'),
  };
}

function run(command: string, args: string[], cwd: string): void {
  const result = spawnSync(command, args, {
    cwd,
    encoding: 'utf8',
    stdio: 'inherit',
  });
  if (result.status !== 0) {
    throw new Error(`${command} ${args.join(' ')} failed with exit ${result.status}`);
  }
}

function runStatus(command: string, args: string[], cwd: string): number | null {
  const result = spawnSync(command, args, {
    cwd,
    encoding: 'utf8',
  });
  return result.status;
}

function copyRequiredTree(source: string, target: string): void {
  rmSync(target, { recursive: true, force: true });
  mkdirSync(target, { recursive: true });

  for (const file of ['package.json', 'package-lock.json', 'tsconfig.json', 'vitest.config.ts']) {
    copyFileSync(join(source, file), join(target, file));
  }

  for (const dir of ['src', 'tests']) {
    cpSync(join(source, dir), join(target, dir), { recursive: true });
  }

  const sourceNodeModules = join(source, 'node_modules');
  if (existsSync(sourceNodeModules)) {
    symlinkSync(sourceNodeModules, join(target, 'node_modules'), 'dir');
  }
}

function hasMon3SdSpiFix(root: string): boolean {
  const path = join(root, 'src/platforms/tec1g/sd-spi.ts');
  const text = existsSync(path) ? readFileSync(path, 'utf8') : '';
  return (
    text.includes('hasActiveTransaction') &&
    !/if \(!nextCsActive\) \{\s+this\.resetTransaction\(\);/.test(text)
  );
}

function applyPatchIfNeeded(target: string): 'applied' | 'already-present' {
  if (runStatus('git', ['apply', '--check', PATCH_PATH], target) === 0) {
    run('git', ['apply', PATCH_PATH], target);
    return 'applied';
  }
  if (hasMon3SdSpiFix(target)) {
    return 'already-present';
  }
  run('git', ['apply', PATCH_PATH], target);
  return 'applied';
}

function main(): void {
  const options = parseArgs(process.argv.slice(2));
  if (!existsSync(PATCH_PATH)) {
    throw new Error(`missing patch: ${PATCH_PATH}`);
  }
  if (!existsSync(join(options.source, 'package.json'))) {
    throw new Error(`Debug80 source root not found: ${options.source}`);
  }

  copyRequiredTree(options.source, options.target);
  const patchState = applyPatchIfNeeded(options.target);
  run('npx', ['tsc'], options.target);
  if (!options.skipTests) {
    run(
      'npx',
      [
        'vitest',
        'run',
        'tests/platforms/tec1g/sd-spi.test.ts',
        'tests/platforms/tec1g/sd-spi-runtime.test.ts',
      ],
      options.target,
    );
  }

  console.log(
    JSON.stringify(
      {
        result: 'ok',
        source: options.source,
        target: options.target,
        patch: PATCH_PATH,
        patchState,
        tests: options.skipTests ? 'skipped' : 'passed',
      },
      null,
      2,
    ),
  );
}

main();
