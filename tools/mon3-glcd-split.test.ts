const { strict: assert } = require('node:assert');
const { mkdtempSync, readFileSync, writeFileSync } = require('node:fs');
const { tmpdir } = require('node:os');
const { join, resolve } = require('node:path');
const { test } = require('node:test');

const {
  analyzeMon3GlcdSplit,
  defaultMon3BundleRoot,
  renderMon3GlcdSplitMarkdown,
  writeMon3GlcdSplitMarkdown,
} = require('./mon3-glcd-split.ts');

const repoRoot = resolve(__dirname, '..');

test('splits MON3 GLCD ROM ranges into measured categories', () => {
  const split = analyzeMon3GlcdSplit({ bundleRoot: defaultMon3BundleRoot() });

  assert.equal(split.totalBytes, 3995);
  assert.deepEqual(
    split.categories.map((category: { id: string }) => category.id),
    [
      'hardware-init-clear-mode',
      'drawing-primitives',
      'plot-text-mode',
      'timing-buffer-policy',
      'terminal-core',
      'cursor-scroll',
      'glyph-renderer',
      'font-data',
      'banner-data',
    ],
  );

  assert.equal(split.categories.find((category: { id: string }) => category.id === 'hardware-init-clear-mode').bytes, 130);
  assert.equal(split.categories.find((category: { id: string }) => category.id === 'drawing-primitives').bytes, 526);
  assert.equal(split.categories.find((category: { id: string }) => category.id === 'terminal-core').bytes, 279);
  assert.equal(split.categories.find((category: { id: string }) => category.id === 'cursor-scroll').bytes, 187);
  assert.equal(split.categories.find((category: { id: string }) => category.id === 'font-data').bytes, 1544);
  assert.equal(split.categories.find((category: { id: string }) => category.id === 'banner-data').bytes, 1024);
});

test('reports key GLCD service labels and source locations', () => {
  const split = analyzeMon3GlcdSplit({ bundleRoot: defaultMon3BundleRoot() });
  const labels = split.keyLabels.map((label: { name: string }) => label.name);

  for (const label of [
    'initLCD',
    'clearGBUF',
    'drawPixel',
    'plotToLCD',
    'initTerminal',
    'sendCharToLCD',
    'SHIFT_BUFFER',
    'MOVE_VPORT',
    'drawGraphic',
    'FONT_DATA',
  ]) {
    assert.ok(labels.includes(label), `${label} should be listed as a GLCD service label`);
  }

  const initLCD = split.keyLabels.find((label: { name: string }) => label.name === 'initLCD');
  assert.equal(initLCD.addressHex, 'D800');
  assert.equal(initLCD.source, 'glcd_library.z80:58');
});

test('reports GLCD RAM allocation and practical workspace pressure', () => {
  const split = analyzeMon3GlcdSplit({ bundleRoot: defaultMon3BundleRoot() });

  assert.equal(split.ram.totalPracticalBytes, 3584);
  assert.equal(split.ram.buffers.find((buffer: { id: string }) => buffer.id === 'gbuf').bytes, 1024);
  assert.equal(split.ram.buffers.find((buffer: { id: string }) => buffer.id === 'sbuf').bytes, 960);
  assert.equal(split.ram.buffers.find((buffer: { id: string }) => buffer.id === 'tgbuf').bytes, 1024);
  assert.equal(split.ram.buffers.find((buffer: { id: string }) => buffer.id === 'scratch-state').bytes, 26);
  assert.equal(split.ram.buffers.find((buffer: { id: string }) => buffer.id === 'unassigned-gap').bytes, 486);
  assert.equal(split.ram.buffers.find((buffer: { id: string }) => buffer.id === 'tail-headroom').bytes, 64);
});

test('renders a checked-in MON3 GLCD split report', () => {
  const split = analyzeMon3GlcdSplit({ bundleRoot: defaultMon3BundleRoot() });
  const markdown = renderMon3GlcdSplitMarkdown(split);

  assert.match(markdown, /^# MON3 GLCD Split Report/m);
  assert.match(markdown, /\| Drawing primitives \| `drawing-primitives` \| 526 \| `020E` \|/);
  assert.match(markdown, /\| Font and text constants \| `font-data` \| 1544 \| `0608` \|/);
  assert.match(markdown, /Practical GLCD RAM workspace: 3584 bytes/);
  assert.match(markdown, /TECM8 Replacement Reading/);
});

test('write mode updates the generated GLCD split report exactly', () => {
  const outputDir = mkdtempSync(join(tmpdir(), 'tecm8-mon3-glcd-split-'));
  const outputPath = join(outputDir, 'mon3-glcd-split.md');
  const split = analyzeMon3GlcdSplit({ bundleRoot: defaultMon3BundleRoot() });
  const expected = renderMon3GlcdSplitMarkdown(split);

  writeFileSync(outputPath, 'stale\n');
  writeMon3GlcdSplitMarkdown({
    bundleRoot: defaultMon3BundleRoot(),
    outputPath,
  });

  assert.equal(readFileSync(outputPath, 'utf8'), expected);
});

test('generated MON3 GLCD split report is checked in and current', () => {
  const docsPath = resolve(repoRoot, 'docs/mon3/glcd-split.md');
  const split = analyzeMon3GlcdSplit({ bundleRoot: defaultMon3BundleRoot() });

  assert.equal(readFileSync(docsPath, 'utf8'), renderMon3GlcdSplitMarkdown(split));
});
