const { strict: assert } = require('node:assert');
const { execFileSync } = require('node:child_process');
const { mkdtempSync, readFileSync, rmSync } = require('node:fs');
const { tmpdir } = require('node:os');
const { join } = require('node:path');
const { test } = require('node:test');

const {
  ALLOCATION_FREE,
  ALLOCATION_RESERVED,
  ENTRY_STATUS_ACTIVE,
  ENTRY_STATUS_FREE,
  TM8_FORMAT,
  createVolumeImage,
  formatVolumeFile,
  listVolumePath,
  parseVolumeImage,
} = require('./format.ts');

function writeCatalogEntry(
  image: Buffer,
  index: number,
  options: { fileId: number; prefixId: number; name: string; size?: number; fileType?: number },
): void {
  const offset =
    TM8_FORMAT.catalogStartBlock * TM8_FORMAT.blockBytes +
    index * TM8_FORMAT.catalogEntrySize;
  image[offset] = ENTRY_STATUS_ACTIVE;
  image[offset + 1] = options.fileId;
  image[offset + 2] = options.prefixId;
  image[offset + 3] = options.name.length;
  image.set(Buffer.from(options.name, 'ascii'), offset + 4);
  image.writeUInt16LE(0, offset + 44);
  image.writeUInt32LE(options.size ?? 0, offset + 46);
  image[offset + 50] = options.fileType ?? 1;
}

function writePrefixEntry(
  image: Buffer,
  index: number,
  options: { prefixId: number; prefix: string },
): void {
  const offset =
    TM8_FORMAT.prefixStartBlock * TM8_FORMAT.blockBytes +
    index * TM8_FORMAT.prefixEntrySize;
  image[offset] = ENTRY_STATUS_ACTIVE;
  image[offset + 1] = options.prefixId;
  image[offset + 2] = options.prefix.length;
  image.set(Buffer.from(options.prefix, 'ascii'), offset + 3);
}

test('formats and parses the default 4 MiB TM8 volume layout', () => {
  const image = createVolumeImage();
  const volume = parseVolumeImage(image);

  assert.equal(image.byteLength, 4 * 1024 * 1024);
  assert.deepEqual(volume.superblock, {
    magic: 'TECM8VOL',
    version: 1,
    volumeBytes: 4 * 1024 * 1024,
    sectorBytes: 512,
    blockBytes: 4096,
    totalBlocks: 1024,
    allocationStartBlock: 1,
    allocationBlockCount: 1,
    prefixStartBlock: 2,
    prefixBlockCount: 4,
    prefixEntrySize: 128,
    prefixEntryCount: 128,
    catalogStartBlock: 6,
    catalogBlockCount: 4,
    catalogEntrySize: 64,
    catalogEntryCount: 256,
    dataStartBlock: 10,
    freeBlockCount: 1014,
    checksum: volume.superblock.checksum,
  });
});

test('marks metadata blocks reserved and data blocks free in the allocation table', () => {
  const volume = parseVolumeImage(createVolumeImage());

  assert.equal(volume.allocation.length, TM8_FORMAT.totalBlocks);
  for (let block = 0; block < TM8_FORMAT.dataStartBlock; block += 1) {
    assert.equal(volume.allocation[block], ALLOCATION_RESERVED);
  }
  assert.equal(volume.allocation[TM8_FORMAT.dataStartBlock], ALLOCATION_FREE);
  assert.equal(volume.allocation[TM8_FORMAT.totalBlocks - 1], ALLOCATION_FREE);
});

test('leaves prefix and catalog regions zero-filled after format', () => {
  const image = createVolumeImage();
  const prefixStart = TM8_FORMAT.prefixStartBlock * TM8_FORMAT.blockBytes;
  const catalogEnd =
    (TM8_FORMAT.catalogStartBlock + TM8_FORMAT.catalogBlockCount) *
    TM8_FORMAT.blockBytes;

  for (let offset = prefixStart; offset < catalogEnd; offset += 1) {
    assert.equal(image[offset], 0);
  }
});

test('rejects volumes with invalid magic, size, or checksum', () => {
  const badMagic = createVolumeImage();
  badMagic[0] = 0;
  assert.throws(() => parseVolumeImage(badMagic), /bad TM8 magic/);

  const badSize = createVolumeImage().subarray(0, TM8_FORMAT.volumeBytes - 1);
  assert.throws(() => parseVolumeImage(badSize), /unexpected TM8 volume size/);

  const badChecksum = createVolumeImage();
  badChecksum[100] ^= 0xff;
  assert.throws(() => parseVolumeImage(badChecksum), /bad TM8 superblock checksum/);
});

test('rejects a valid-checksum superblock with unexpected layout fields', () => {
  const image = createVolumeImage();
  image.writeUInt16LE(2, 8);
  image.writeUInt32LE(0, TM8_FORMAT.checksumOffset);
  let checksum = 0;
  for (let offset = 0; offset < TM8_FORMAT.sectorBytes; offset += 1) {
    checksum = (checksum + image[offset]) >>> 0;
  }
  image.writeUInt32LE(checksum, TM8_FORMAT.checksumOffset);

  assert.throws(() => parseVolumeImage(image), /unexpected TM8 version/);
});

test('rejects corrupted allocation table entries', () => {
  const corruptedReservedBlock = createVolumeImage();
  corruptedReservedBlock.writeUInt16LE(
    ALLOCATION_FREE,
    TM8_FORMAT.allocationStartBlock * TM8_FORMAT.blockBytes,
  );
  assert.throws(
    () => parseVolumeImage(corruptedReservedBlock),
    /unexpected allocation entry for metadata block 0/,
  );

  const corruptedFreeBlock = createVolumeImage();
  corruptedFreeBlock.writeUInt16LE(
    ALLOCATION_RESERVED,
    TM8_FORMAT.allocationStartBlock * TM8_FORMAT.blockBytes +
      TM8_FORMAT.dataStartBlock * 2,
  );
  assert.throws(
    () => parseVolumeImage(corruptedFreeBlock),
    /unexpected allocation entry for free block 10/,
  );
});

test('rejects non-zero reserved allocation table tail bytes', () => {
  const image = createVolumeImage();
  const tailOffset =
    TM8_FORMAT.allocationStartBlock * TM8_FORMAT.blockBytes + TM8_FORMAT.totalBlocks * 2;
  image[tailOffset] = 1;

  assert.throws(() => parseVolumeImage(image), /non-zero reserved allocation table byte/);
});

test('rejects non-zero formatted prefix and catalog regions', () => {
  const corruptedPrefix = createVolumeImage();
  corruptedPrefix[TM8_FORMAT.prefixStartBlock * TM8_FORMAT.blockBytes + 1] = 1;
  assert.throws(() => parseVolumeImage(corruptedPrefix), /dirty inactive prefix entry/);

  const corruptedCatalog = createVolumeImage();
  corruptedCatalog[TM8_FORMAT.catalogStartBlock * TM8_FORMAT.blockBytes + 1] = 1;
  assert.throws(() => parseVolumeImage(corruptedCatalog), /dirty inactive file entry/);
});

test('rejects malformed prefix and catalog entry status bytes', () => {
  const badPrefixStatus = createVolumeImage();
  badPrefixStatus[TM8_FORMAT.prefixStartBlock * TM8_FORMAT.blockBytes] = 0x02;
  assert.throws(() => parseVolumeImage(badPrefixStatus), /bad prefix entry status/);

  const badCatalogStatus = createVolumeImage();
  badCatalogStatus[TM8_FORMAT.catalogStartBlock * TM8_FORMAT.blockBytes] = 0x02;
  assert.throws(() => parseVolumeImage(badCatalogStatus), /bad file entry status/);
});

test('rejects non-zero reserved superblock bytes even with a valid checksum', () => {
  const image = createVolumeImage();
  image[44] = 1;
  image.writeUInt32LE(0, TM8_FORMAT.checksumOffset);
  let checksum = 0;
  for (let offset = 0; offset < TM8_FORMAT.sectorBytes; offset += 1) {
    checksum = (checksum + image[offset]) >>> 0;
  }
  image.writeUInt32LE(checksum, TM8_FORMAT.checksumOffset);

  assert.throws(() => parseVolumeImage(image), /non-zero reserved superblock byte/);

  const secondSector = createVolumeImage();
  secondSector[TM8_FORMAT.sectorBytes] = 1;
  assert.throws(() => parseVolumeImage(secondSector), /non-zero reserved superblock byte/);
});

test('writes a formatted volume file that can be read back', () => {
  const dir = mkdtempSync(join(tmpdir(), 'tm8-format-'));
  try {
    const file = join(dir, 'VOLUME.TM8');
    formatVolumeFile(file);

    const image = readFileSync(file);
    const volume = parseVolumeImage(image);

    assert.equal(image.byteLength, TM8_FORMAT.volumeBytes);
    assert.equal(volume.superblock.magic, 'TECM8VOL');
    assert.equal(volume.superblock.freeBlockCount, 1014);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('lists an empty root path on a freshly formatted volume', () => {
  const volume = parseVolumeImage(createVolumeImage());

  assert.deepEqual(listVolumePath(volume, '/'), []);
});

test('lists active root catalog entries by local filename', () => {
  const image = createVolumeImage();
  writeCatalogEntry(image, 0, {
    fileId: 7,
    prefixId: 0,
    name: 'main.z80',
    size: 123,
    fileType: 1,
  });

  const listing = listVolumePath(parseVolumeImage(image), '/');

  assert.deepEqual(listing, [
    {
      fileId: 7,
      path: '/main.z80',
      name: 'main.z80',
      prefix: '',
      size: 123,
      fileType: 1,
    },
  ]);
});

test('lists active entries under a stored prefix', () => {
  const image = createVolumeImage();
  writePrefixEntry(image, 0, {
    prefixId: 3,
    prefix: 'projects/demo',
  });
  writeCatalogEntry(image, 0, {
    fileId: 8,
    prefixId: 3,
    name: 'main.z80',
    size: 456,
    fileType: 1,
  });

  const listing = listVolumePath(parseVolumeImage(image), '/projects/demo');

  assert.deepEqual(listing, [
    {
      fileId: 8,
      path: '/projects/demo/main.z80',
      name: 'main.z80',
      prefix: 'projects/demo',
      size: 456,
      fileType: 1,
    },
  ]);
});

test('rejects malformed active file entries', () => {
  const emptyName = createVolumeImage();
  writeCatalogEntry(emptyName, 0, {
    fileId: 1,
    prefixId: 0,
    name: '',
  });
  assert.throws(() => parseVolumeImage(emptyName), /bad file name length/);

  const missingPrefix = createVolumeImage();
  writeCatalogEntry(missingPrefix, 0, {
    fileId: 1,
    prefixId: 9,
    name: 'main.z80',
  });
  assert.throws(() => parseVolumeImage(missingPrefix), /unknown prefix id 9/);

  const slashName = createVolumeImage();
  writeCatalogEntry(slashName, 0, {
    fileId: 1,
    prefixId: 0,
    name: 'foo/bar',
  });
  assert.throws(() => parseVolumeImage(slashName), /bad file name/);

  const highBitName = createVolumeImage();
  writeCatalogEntry(highBitName, 0, {
    fileId: 1,
    prefixId: 0,
    name: 'main.z80',
  });
  highBitName[TM8_FORMAT.catalogStartBlock * TM8_FORMAT.blockBytes + 4] = 0xe1;
  assert.throws(() => parseVolumeImage(highBitName), /bad file name byte/);
});

test('rejects malformed active prefix entries', () => {
  const leadingSlash = createVolumeImage();
  writePrefixEntry(leadingSlash, 0, {
    prefixId: 1,
    prefix: '/projects',
  });
  assert.throws(() => parseVolumeImage(leadingSlash), /bad prefix/);

  const trailingSlash = createVolumeImage();
  writePrefixEntry(trailingSlash, 0, {
    prefixId: 1,
    prefix: 'projects/',
  });
  assert.throws(() => parseVolumeImage(trailingSlash), /bad prefix/);

  const highBitPrefix = createVolumeImage();
  writePrefixEntry(highBitPrefix, 0, {
    prefixId: 1,
    prefix: 'projects',
  });
  highBitPrefix[TM8_FORMAT.prefixStartBlock * TM8_FORMAT.blockBytes + 3] = 0xe1;
  assert.throws(() => parseVolumeImage(highBitPrefix), /bad prefix byte/);
});

test('refuses to overwrite an existing volume file by default', () => {
  const dir = mkdtempSync(join(tmpdir(), 'tm8-format-'));
  try {
    const file = join(dir, 'VOLUME.TM8');
    formatVolumeFile(file);

    assert.throws(() => formatVolumeFile(file), /refusing to overwrite existing file/);

    formatVolumeFile(file, { overwrite: true });
    assert.equal(parseVolumeImage(readFileSync(file)).superblock.magic, 'TECM8VOL');
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('tm8fs rejects extra CLI arguments', () => {
  const dir = mkdtempSync(join(tmpdir(), 'tm8-cli-'));
  try {
    const file = join(dir, 'VOLUME.TM8');
    formatVolumeFile(file);

    assert.throws(
      () =>
        execFileSync(
          process.execPath,
          ['--experimental-strip-types', 'tools/tm8fs.ts', 'info', file, 'junk'],
          { cwd: process.cwd(), stdio: 'pipe' },
        ),
      /usage: tm8fs <format\|info> VOLUME\.TM8/,
    );
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('tm8fs lists an empty root path', () => {
  const dir = mkdtempSync(join(tmpdir(), 'tm8-cli-'));
  try {
    const file = join(dir, 'VOLUME.TM8');
    formatVolumeFile(file);

    const output = execFileSync(
      process.execPath,
      ['--experimental-strip-types', 'tools/tm8fs.ts', 'ls', file, '/'],
      { cwd: process.cwd(), encoding: 'utf8' },
    );

    assert.equal(output, '');
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
