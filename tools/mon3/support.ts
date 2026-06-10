/**
 * Shared plumbing for the MON3 decomposition report tools.
 *
 * The mon3-service-inventory, mon3-storage-split, and mon3-glcd-split tools
 * all read the bundled MON3 debug map, render a markdown report into docs/,
 * and support a --check mode that fails when the committed report is stale.
 * This module owns that common CLI and file plumbing. The `export type`
 * below is erased by Node's type stripping, so at runtime this remains a
 * plain CJS module.
 */

const { readFileSync } = require('node:fs');
const { resolve } = require('node:path');

type Mon3CliArgs = {
  check: boolean;
  outputPath: string;
  bundleRoot: string;
};

type Mon3ReportOptions = {
  bundleRoot: string;
  outputPath: string;
};

function defaultMon3BundleRoot(): string {
  return resolve(
    process.env.DEBUG80_ROOT ?? '/Users/johnhardy/projects/debug80',
    'resources/bundles/tec1g/mon3/v1',
  );
}

function repoRoot(): string {
  return resolve(__dirname, '../..');
}

function readText(path: string): string {
  return readFileSync(path, 'utf8');
}

function readDebugMap(bundleRoot: string): any {
  return JSON.parse(readText(resolve(bundleRoot, 'mon3.d8.json')));
}

function parseMon3CliArgs(argv: string[], defaultOutputDocsPath: string): Mon3CliArgs {
  let check = false;
  let outputPath = resolve(repoRoot(), defaultOutputDocsPath);
  let bundleRoot = defaultMon3BundleRoot();

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === '--check') {
      check = true;
    } else if (arg === '--output') {
      index += 1;
      outputPath = resolve(argv[index]);
    } else if (arg === '--bundle-root') {
      index += 1;
      bundleRoot = resolve(argv[index]);
    } else {
      throw new Error(`unknown argument: ${arg}`);
    }
  }

  return { check, outputPath, bundleRoot };
}

function runMon3MarkdownCli(
  argv: string[],
  defaultOutputDocsPath: string,
  handlers: {
    write: (options: Mon3ReportOptions) => void;
    check: (options: Mon3ReportOptions) => void;
  },
): void {
  try {
    const args = parseMon3CliArgs(argv, defaultOutputDocsPath);
    const options = { bundleRoot: args.bundleRoot, outputPath: args.outputPath };
    if (args.check) {
      handlers.check(options);
    } else {
      handlers.write(options);
    }
  } catch (error) {
    console.error(error instanceof Error ? error.message : String(error));
    process.exit(1);
  }
}

const mon3SupportExports = {
  defaultMon3BundleRoot,
  repoRoot,
  readText,
  readDebugMap,
  parseMon3CliArgs,
  runMon3MarkdownCli,
};

export type Mon3Support = typeof mon3SupportExports;
export type { Mon3ReportOptions };

module.exports = mon3SupportExports;
