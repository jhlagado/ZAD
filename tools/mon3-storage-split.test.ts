const { strict: assert } = require('node:assert');
const { mkdtempSync, readFileSync, writeFileSync } = require('node:fs');
const { tmpdir } = require('node:os');
const { join, resolve } = require('node:path');
const { test } = require('node:test');

const {
  analyzeMon3StorageSplit,
  defaultMon3BundleRoot,
  renderMon3StorageSplitMarkdown,
  writeMon3StorageSplitMarkdown,
} = require('./mon3-storage-split.ts');

const repoRoot = resolve(__dirname, '..');

test('splits MON3 storage ROM ranges into measured categories', () => {
  const split = analyzeMon3StorageSplit({ bundleRoot: defaultMon3BundleRoot() });

  assert.equal(split.totalBytes, 2646);
  assert.deepEqual(
    split.categories.map((category: { id: string }) => category.id),
    [
      'pata-specific',
      'block-device-shared',
      'fat-core',
      'storage-ui',
      'sd-spi',
      'messages',
    ],
  );

  assert.equal(split.categories.find((category: { id: string }) => category.id === 'pata-specific').bytes, 167);
  assert.equal(split.categories.find((category: { id: string }) => category.id === 'sd-spi').bytes, 367);
  assert.equal(split.categories.find((category: { id: string }) => category.id === 'fat-core').bytes, 867);
  assert.equal(split.categories.find((category: { id: string }) => category.id === 'storage-ui').bytes, 853);
  assert.equal(split.categories.find((category: { id: string }) => category.id === 'messages').bytes, 223);

  const minimum = split.sdOnlyMinimum;
  assert.deepEqual(minimum.keepCategories, ['block-device-shared', 'fat-core', 'sd-spi']);
  assert.equal(minimum.keepBytes, 1403);
  assert.equal(minimum.optionalBytes, 1076);
  assert.equal(minimum.pataOnlyBytes, 167);
  assert.equal(minimum.plausibleReclaimBytes, 1243);
});

test('reports key service labels and source locations for the SD-only minimum', () => {
  const split = analyzeMon3StorageSplit({ bundleRoot: defaultMon3BundleRoot() });
  const minimumLabels = split.sdOnlyMinimum.keyLabels.map((label: { name: string }) => label.name);

  for (const label of [
    'openFile',
    'readSector',
    'writeSector',
    'FATmount',
    'FATreadSector',
    'FATgetSector',
    'FATgetFAT',
    'checkSDCardPresent',
    'sendSPICommand',
    'readSPIBlock',
    'writeSPIBlock',
    'initSD',
  ]) {
    assert.ok(minimumLabels.includes(label), `${label} should be listed in SD-only minimum`);
  }

  const readSector = split.sdOnlyMinimum.keyLabels.find((label: { name: string }) => label.name === 'readSector');
  assert.equal(readSector.addressHex, 'F5D5');
  assert.equal(readSector.source, 'pata_fat32.z80:1055');
});

test('renders a checked-in MON3 storage split report', () => {
  const split = analyzeMon3StorageSplit({ bundleRoot: defaultMon3BundleRoot() });
  const markdown = renderMon3StorageSplitMarkdown(split);

  assert.match(markdown, /^# MON3 Storage Split Report/m);
  assert.match(markdown, /\| PATA-specific hardware path \| `pata-specific` \| 167 \| `00A7` \|/);
  assert.match(markdown, /\| SD\/SPI hardware path \| `sd-spi` \| 367 \| `016F` \|/);
  assert.match(markdown, /\| FAT32\/file-sector core \| `fat-core` \| 867 \| `0363` \|/);
  assert.match(markdown, /SD-only minimum keep set/);
  assert.match(markdown, /Plausible reclaim from PATA \+ optional storage UI\/messages: 1243 bytes/);
});

test('write mode updates the generated storage split report exactly', () => {
  const outputDir = mkdtempSync(join(tmpdir(), 'tecm8-mon3-storage-split-'));
  const outputPath = join(outputDir, 'mon3-storage-split.md');
  const split = analyzeMon3StorageSplit({ bundleRoot: defaultMon3BundleRoot() });
  const expected = renderMon3StorageSplitMarkdown(split);

  writeFileSync(outputPath, 'stale\n');
  writeMon3StorageSplitMarkdown({
    bundleRoot: defaultMon3BundleRoot(),
    outputPath,
  });

  assert.equal(readFileSync(outputPath, 'utf8'), expected);
});

test('generated MON3 storage split report is checked in and current', () => {
  const docsPath = resolve(repoRoot, 'docs/mon3-storage-split.md');
  const split = analyzeMon3StorageSplit({ bundleRoot: defaultMon3BundleRoot() });

  assert.equal(readFileSync(docsPath, 'utf8'), renderMon3StorageSplitMarkdown(split));
});
