const { strict: assert } = require('node:assert');
const { mkdtempSync, readFileSync, writeFileSync } = require('node:fs');
const { tmpdir } = require('node:os');
const { join, resolve } = require('node:path');
const { test } = require('node:test');

const {
  buildMon3ServiceInventory,
  defaultMon3BundleRoot,
  renderMon3ServiceInventoryMarkdown,
  writeMon3ServiceInventoryMarkdown,
} = require('./mon3-service-inventory.ts');

const repoRoot = resolve(__dirname, '..');

test('extracts MON3 RST 10h and RST 18h API tables from Debug80 bundle', () => {
  const inventory = buildMon3ServiceInventory({
    bundleRoot: defaultMon3BundleRoot(),
  });

  assert.equal(inventory.tables.length, 2);
  assert.deepEqual(
    inventory.tables.map((table: { id: string }) => table.id),
    ['rst18-glcd', 'rst10-main'],
  );

  const rst10 = inventory.tables.find((table: { id: string }) => table.id === 'rst10-main');
  const rst18 = inventory.tables.find((table: { id: string }) => table.id === 'rst18-glcd');

  assert.equal(rst10.services[0].service, 'softwareID');
  assert.equal(rst10.services[0].selector, 0);
  assert.equal(rst10.services[0].addressHex, 'C68C');
  assert.equal(rst10.services[0].sourceFile, 'mon3.z80');
  assert.equal(rst10.services[0].classification, 'classic-core');

  const readSector = rst10.services.find((service: { service: string }) => service.service === 'readSector');
  assert.equal(readSector.selector, 60);
  assert.equal(readSector.addressHex, 'F5D5');
  assert.equal(readSector.sourceFile, 'pata_fat32.z80');
  assert.equal(readSector.classification, 'bios-keep');
  assert.match(readSector.notes, /SD-backed/i);

  const rtc = rst10.services.find((service: { service: string }) => service.service === 'RTCAPI');
  assert.equal(rtc.classification, 'optional-relocate');
  assert.equal(rtc.sourceFile, 'rtc.z80');

  const initLCD = rst18.services[0];
  assert.equal(initLCD.service, 'initLCD');
  assert.equal(initLCD.addressHex, 'D800');
  assert.equal(initLCD.sourceFile, 'glcd_library.z80');
  assert.equal(initLCD.classification, 'extension-rewrite');

  assert.equal(rst10.services.length, 63);
  assert.equal(rst18.services.length, 34);
});

test('renders a checked-in markdown inventory with classification and source data', () => {
  const inventory = buildMon3ServiceInventory({
    bundleRoot: defaultMon3BundleRoot(),
  });
  const markdown = renderMon3ServiceInventoryMarkdown(inventory);

  assert.match(markdown, /^# MON3 Service Inventory/m);
  assert.match(markdown, /\| RST 10h \| `3Ch` \| `readSector` \| `F5D5` \| `pata_fat32` \| `pata_fat32\.z80:1055` \| `bios-keep` \|/);
  assert.match(markdown, /\| RST 18h \| `00h` \| `initLCD` \| `D800` \| `glcd_library` \| `glcd_library\.z80:58` \| `extension-rewrite` \|/);
  assert.match(markdown, /Generated from Debug80 MON3 bundle/);
  assert.match(markdown, /Classification is an initial planning aid/);
});

test('classifies every extracted MON3 service explicitly', () => {
  const inventory = buildMon3ServiceInventory({
    bundleRoot: defaultMon3BundleRoot(),
  });
  const services = inventory.tables.flatMap((table: { services: Array<{ classification: string }> }) => table.services);

  assert.equal(services.length, 97);
  assert.equal(
    services.filter((service: { classification: string }) => service.classification === 'unknown').length,
    0,
  );
});

test('write mode updates the generated docs inventory exactly', () => {
  const outputDir = mkdtempSync(join(tmpdir(), 'tecm8-mon3-inventory-'));
  const outputPath = join(outputDir, 'mon3-service-inventory.md');

  const inventory = buildMon3ServiceInventory({
    bundleRoot: defaultMon3BundleRoot(),
  });
  const expected = renderMon3ServiceInventoryMarkdown(inventory);
  writeFileSync(outputPath, 'stale\n');

  writeMon3ServiceInventoryMarkdown({
    bundleRoot: defaultMon3BundleRoot(),
    outputPath,
  });

  assert.equal(readFileSync(outputPath, 'utf8'), expected);
});

test('generated MON3 service inventory is checked in and current', () => {
  const docsPath = resolve(repoRoot, 'docs/mon3/service-inventory.md');
  const inventory = buildMon3ServiceInventory({
    bundleRoot: defaultMon3BundleRoot(),
  });

  assert.equal(readFileSync(docsPath, 'utf8'), renderMon3ServiceInventoryMarkdown(inventory));
});
