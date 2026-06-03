const { strict: assert } = require('node:assert');
const { execFileSync } = require('node:child_process');
const { mkdirSync, mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync } = require('node:fs');
const { tmpdir } = require('node:os');
const { join } = require('node:path');
const { test } = require('node:test');

const {
  ALLOCATION_FREE,
  ALLOCATION_RESERVED,
  ENTRY_STATUS_ACTIVE,
  ENTRY_STATUS_FREE,
  ALLOCATION_END,
  TM8_FORMAT,
  createFileInVolumeImage,
  createVolumeImage,
  formatVolumeFile,
  importFileIntoVolumeImage,
  listVolumePath,
  parseVolumeImage,
  readFileFromVolumeImage,
  removeFileFromVolumeImage,
  moveFileInVolumeImage,
} = require('./format.ts');

function writeU16(image: Buffer, offset: number, value: number): void {
  image.writeUInt16LE(value & 0xffff, offset);
}

function writeU32(image: Buffer, offset: number, value: number): void {
  image.writeUInt32LE(value >>> 0, offset);
}

function rewriteFreeBlockCount(image: Buffer, freeBlockCount: number): void {
  writeU16(image, 42, freeBlockCount);
  writeU32(image, TM8_FORMAT.checksumOffset, 0);
  let checksum = 0;
  for (let offset = 0; offset < TM8_FORMAT.sectorBytes; offset += 1) {
    checksum = (checksum + image[offset]) >>> 0;
  }
  writeU32(image, TM8_FORMAT.checksumOffset, checksum);
}

function writeCatalogEntry(
  image: Buffer,
  index: number,
  options: {
    fileId: number;
    prefixId: number;
    name: string;
    size?: number;
    fileType?: number;
    firstBlock?: number;
    allocate?: boolean;
  },
): void {
  const offset =
    TM8_FORMAT.catalogStartBlock * TM8_FORMAT.blockBytes +
    index * TM8_FORMAT.catalogEntrySize;
  const firstBlock = options.firstBlock ?? TM8_FORMAT.dataStartBlock + index;
  image[offset] = ENTRY_STATUS_ACTIVE;
  image[offset + 1] = options.fileId;
  image[offset + 2] = options.prefixId;
  image[offset + 3] = options.name.length;
  image.set(Buffer.from(options.name, 'ascii'), offset + 4);
  image.writeUInt16LE(firstBlock, offset + 44);
  image.writeUInt32LE(options.size ?? 0, offset + 46);
  image[offset + 50] = options.fileType ?? 1;
  if (options.allocate !== false) {
    const allocationOffset =
      TM8_FORMAT.allocationStartBlock * TM8_FORMAT.blockBytes + firstBlock * 2;
    image.writeUInt16LE(ALLOCATION_END, allocationOffset);
    const currentFree = image.readUInt16LE(42);
    rewriteFreeBlockCount(image, currentFree - 1);
  }
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

function writeFileSize(image: Buffer, catalogIndex: number, size: number): void {
  const offset =
    TM8_FORMAT.catalogStartBlock * TM8_FORMAT.blockBytes +
    catalogIndex * TM8_FORMAT.catalogEntrySize +
    46;
  image.writeUInt32LE(size >>> 0, offset);
}

function writeFileContent(image: Buffer, path: string, content: Buffer): Buffer {
  let updated = createFileInVolumeImage(image, path);
  const firstBlock = parseVolumeImage(updated).files[0].firstBlock;
  updated.set(content.subarray(0, TM8_FORMAT.blockBytes), firstBlock * TM8_FORMAT.blockBytes);
  writeFileSize(updated, 0, content.byteLength);
  return updated;
}

function writeTwoBlockFileContent(image: Buffer, path: string, content: Buffer): Buffer {
  let updated = createFileInVolumeImage(image, path);
  const volume = parseVolumeImage(updated);
  const firstBlock = volume.files[0].firstBlock;
  const secondBlock = firstBlock + 1;
  writeU16(
    updated,
    TM8_FORMAT.allocationStartBlock * TM8_FORMAT.blockBytes + firstBlock * 2,
    secondBlock,
  );
  writeU16(
    updated,
    TM8_FORMAT.allocationStartBlock * TM8_FORMAT.blockBytes + secondBlock * 2,
    ALLOCATION_END,
  );
  rewriteFreeBlockCount(updated, volume.superblock.freeBlockCount - 1);
  updated.set(content.subarray(0, TM8_FORMAT.blockBytes), firstBlock * TM8_FORMAT.blockBytes);
  updated.set(
    content.subarray(TM8_FORMAT.blockBytes),
    secondBlock * TM8_FORMAT.blockBytes,
  );
  writeFileSize(updated, 0, content.byteLength);
  parseVolumeImage(updated);
  return updated;
}

function catalogEntryStart(index: number): number {
  return TM8_FORMAT.catalogStartBlock * TM8_FORMAT.blockBytes + index * TM8_FORMAT.catalogEntrySize;
}

function prefixEntryStart(index: number): number {
  return TM8_FORMAT.prefixStartBlock * TM8_FORMAT.blockBytes + index * TM8_FORMAT.prefixEntrySize;
}

function initialFreeBlockCount(): number {
  return TM8_FORMAT.totalBlocks - TM8_FORMAT.dataStartBlock;
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
    /unexpected TM8 freeBlockCount/,
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

test('rejects active file entries with invalid block chains', () => {
  const freeBlockFile = createVolumeImage();
  writeCatalogEntry(freeBlockFile, 0, {
    fileId: 1,
    prefixId: 0,
    name: 'main.z80',
    firstBlock: TM8_FORMAT.dataStartBlock,
    allocate: false,
  });
  assert.throws(() => parseVolumeImage(freeBlockFile), /file entry 0 points to free block/);

  const cyclicFile = createVolumeImage();
  writeCatalogEntry(cyclicFile, 0, {
    fileId: 1,
    prefixId: 0,
    name: 'main.z80',
    firstBlock: TM8_FORMAT.dataStartBlock,
  });
  writeU16(
    cyclicFile,
    TM8_FORMAT.allocationStartBlock * TM8_FORMAT.blockBytes +
      TM8_FORMAT.dataStartBlock * 2,
    TM8_FORMAT.dataStartBlock + 1,
  );
  writeU16(
    cyclicFile,
    TM8_FORMAT.allocationStartBlock * TM8_FORMAT.blockBytes +
      (TM8_FORMAT.dataStartBlock + 1) * 2,
    TM8_FORMAT.dataStartBlock,
  );
  rewriteFreeBlockCount(cyclicFile, 1012);
  assert.throws(() => parseVolumeImage(cyclicFile), /cycle in file block chain/);

  const sharedBlock = createVolumeImage();
  writeCatalogEntry(sharedBlock, 0, {
    fileId: 1,
    prefixId: 0,
    name: 'main.z80',
    firstBlock: TM8_FORMAT.dataStartBlock,
  });
  writeCatalogEntry(sharedBlock, 1, {
    fileId: 2,
    prefixId: 0,
    name: 'other.z80',
    firstBlock: TM8_FORMAT.dataStartBlock,
    allocate: false,
  });
  assert.throws(() => parseVolumeImage(sharedBlock), /shared file block/);
});

test('rejects file sizes larger than their allocated block chains', () => {
  const image = createVolumeImage();
  writeCatalogEntry(image, 0, {
    fileId: 1,
    prefixId: 0,
    name: 'too-big.bin',
    size: TM8_FORMAT.blockBytes + 1,
    firstBlock: TM8_FORMAT.dataStartBlock,
  });

  assert.throws(() => parseVolumeImage(image), /exceeds allocated block chain/);
});

test('rejects duplicate active catalog paths', () => {
  const image = createVolumeImage();
  writeCatalogEntry(image, 0, {
    fileId: 1,
    prefixId: 0,
    name: 'main.z80',
  });
  writeCatalogEntry(image, 1, {
    fileId: 2,
    prefixId: 0,
    name: 'main.z80',
  });

  assert.throws(() => parseVolumeImage(image), /duplicate file path/);
});

test('rejects duplicate active file ids', () => {
  const image = createVolumeImage();
  writeCatalogEntry(image, 0, {
    fileId: 1,
    prefixId: 0,
    name: 'main.z80',
  });
  writeCatalogEntry(image, 1, {
    fileId: 1,
    prefixId: 0,
    name: 'other.z80',
  });

  assert.throws(() => parseVolumeImage(image), /duplicate file id/);
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

test('rejects duplicate active prefix strings', () => {
  const image = createVolumeImage();
  writePrefixEntry(image, 0, {
    prefixId: 1,
    prefix: 'dup',
  });
  writePrefixEntry(image, 1, {
    prefixId: 2,
    prefix: 'dup',
  });

  assert.throws(() => parseVolumeImage(image), /duplicate prefix/);
});

test('rejects duplicate active prefix ids', () => {
  const image = createVolumeImage();
  writePrefixEntry(image, 0, {
    prefixId: 1,
    prefix: 'one',
  });
  writePrefixEntry(image, 1, {
    prefixId: 1,
    prefix: 'two',
  });

  assert.throws(() => parseVolumeImage(image), /bad prefix id/);
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

test('fs rejects extra CLI arguments', () => {
  const dir = mkdtempSync(join(tmpdir(), 'tm8-cli-'));
  try {
    const file = join(dir, 'VOLUME.TM8');
    formatVolumeFile(file);

    assert.throws(
      () =>
        execFileSync(
          process.execPath,
          ['--experimental-strip-types', 'tools/fs.ts', 'info', file, 'junk'],
          { cwd: process.cwd(), stdio: 'pipe' },
        ),
      /usage: fs format VOLUME\.TM8/,
    );
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('fs lists an empty root path', () => {
  const dir = mkdtempSync(join(tmpdir(), 'tm8-cli-'));
  try {
    const file = join(dir, 'VOLUME.TM8');
    formatVolumeFile(file);

    const output = execFileSync(
      process.execPath,
      ['--experimental-strip-types', 'tools/fs.ts', 'ls', file, '/'],
      { cwd: process.cwd(), encoding: 'utf8' },
    );

    assert.equal(output, '');
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('creates a root file with one allocated data block', () => {
  const image = createVolumeImage();
  image.fill(0xa5, TM8_FORMAT.dataStartBlock * TM8_FORMAT.blockBytes, (TM8_FORMAT.dataStartBlock + 1) * TM8_FORMAT.blockBytes);
  const updated = createFileInVolumeImage(image, '/main.z80');
  const volume = parseVolumeImage(updated);

  assert.deepEqual(listVolumePath(volume, '/'), [
    {
      fileId: 0,
      path: '/main.z80',
      name: 'main.z80',
      prefix: '',
      size: 0,
      fileType: 1,
    },
  ]);
  assert.equal(volume.files[0].firstBlock, TM8_FORMAT.dataStartBlock);
  assert.equal(volume.allocation[TM8_FORMAT.dataStartBlock], ALLOCATION_END);
  assert.equal(volume.superblock.freeBlockCount, 1013);
  for (
    let offset = TM8_FORMAT.dataStartBlock * TM8_FORMAT.blockBytes;
    offset < (TM8_FORMAT.dataStartBlock + 1) * TM8_FORMAT.blockBytes;
    offset += 1
  ) {
    assert.equal(updated[offset], 0);
  }
});

test('creates a prefixed file and makes ls show it under that prefix', () => {
  const updated = createFileInVolumeImage(createVolumeImage(), '/projects/demo/main.z80');
  const volume = parseVolumeImage(updated);

  assert.deepEqual(volume.prefixes, [
    {
      status: ENTRY_STATUS_ACTIVE,
      prefixId: 1,
      prefix: 'projects/demo',
    },
  ]);
  assert.deepEqual(listVolumePath(volume, '/projects/demo'), [
    {
      fileId: 0,
      path: '/projects/demo/main.z80',
      name: 'main.z80',
      prefix: 'projects/demo',
      size: 0,
      fileType: 1,
    },
  ]);
});

test('rejects duplicate and malformed new file paths', () => {
  const image = createFileInVolumeImage(createVolumeImage(), '/main.z80');

  assert.throws(() => createFileInVolumeImage(image, '/main.z80'), /file already exists/);
  assert.throws(() => createFileInVolumeImage(image, 'main.z80'), /TM8 paths must start with/);
  assert.throws(() => createFileInVolumeImage(image, '/bad/name/'), /missing local filename/);
  assert.throws(() => createFileInVolumeImage(image, '/bad/foo*bar'), /bad file name/);
});

test('reports prefix table full, file catalog full, and no free block errors', () => {
  let prefixFull = createVolumeImage();
  for (let index = 0; index < TM8_FORMAT.prefixEntryCount; index += 1) {
    prefixFull = createFileInVolumeImage(prefixFull, `/p${index}/file.z80`);
  }
  assert.throws(
    () => createFileInVolumeImage(prefixFull, '/overflow/file.z80'),
    /prefix table full/,
  );

  let catalogFull = createVolumeImage();
  for (let index = 0; index < TM8_FORMAT.catalogEntryCount; index += 1) {
    catalogFull = createFileInVolumeImage(catalogFull, `/file${index}.z80`);
  }
  assert.throws(() => createFileInVolumeImage(catalogFull, '/overflow.z80'), /file catalog full/);

  const noFreeBlocks = createVolumeImage();
  const allocationStart = TM8_FORMAT.allocationStartBlock * TM8_FORMAT.blockBytes;
  for (let block = TM8_FORMAT.dataStartBlock; block < TM8_FORMAT.totalBlocks; block += 1) {
    writeU16(noFreeBlocks, allocationStart + block * 2, ALLOCATION_END);
  }
  rewriteFreeBlockCount(noFreeBlocks, 0);
  assert.throws(() => createFileInVolumeImage(noFreeBlocks, '/main.z80'), /no free blocks/);
});

test('fs new creates a file that can be listed', () => {
  const dir = mkdtempSync(join(tmpdir(), 'tm8-cli-'));
  try {
    const file = join(dir, 'VOLUME.TM8');
    formatVolumeFile(file);

    execFileSync(
      process.execPath,
      ['--experimental-strip-types', 'tools/fs.ts', 'new', file, '/projects/demo/main.z80'],
      { cwd: process.cwd(), stdio: 'pipe' },
    );
    const output = execFileSync(
      process.execPath,
      ['--experimental-strip-types', 'tools/fs.ts', 'ls', file, '/projects/demo'],
      { cwd: process.cwd(), encoding: 'utf8' },
    );

    assert.equal(output, 'main.z80\n');
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('reads root and prefixed file contents exactly', () => {
  const rootContent = Buffer.from('root file\n', 'utf8');
  const rootImage = writeFileContent(createVolumeImage(), '/main.z80', rootContent);
  assert.deepEqual(readFileFromVolumeImage(rootImage, '/main.z80'), rootContent);

  const prefixedContent = Buffer.from('prefixed file\n', 'utf8');
  const prefixedImage = writeFileContent(
    createVolumeImage(),
    '/projects/demo/main.z80',
    prefixedContent,
  );
  assert.deepEqual(
    readFileFromVolumeImage(prefixedImage, '/projects/demo/main.z80'),
    prefixedContent,
  );
});

test('reads zero-length files created by new as empty output', () => {
  const image = createFileInVolumeImage(createVolumeImage(), '/empty.z80');

  assert.deepEqual(readFileFromVolumeImage(image, '/empty.z80'), Buffer.alloc(0));
});

test('reads exact bytes across a multi-block file chain', () => {
  const content = Buffer.alloc(TM8_FORMAT.blockBytes + 17);
  for (let index = 0; index < content.byteLength; index += 1) {
    content[index] = index & 0xff;
  }
  const image = writeTwoBlockFileContent(createVolumeImage(), '/big.bin', content);

  assert.deepEqual(readFileFromVolumeImage(image, '/big.bin'), content);
});

test('rejects missing and malformed cat paths', () => {
  const image = createFileInVolumeImage(createVolumeImage(), '/main.z80');

  assert.throws(() => readFileFromVolumeImage(image, '/missing.z80'), /file not found/);
  assert.throws(() => readFileFromVolumeImage(image, 'main.z80'), /TM8 paths must start with/);
  assert.throws(() => readFileFromVolumeImage(image, '/bad/name/'), /missing local filename/);
});

test('fs cat prints file contents and zero-length files', () => {
  const dir = mkdtempSync(join(tmpdir(), 'tm8-cli-'));
  try {
    const file = join(dir, 'VOLUME.TM8');
    const content = Buffer.from('hello from tm8\n', 'utf8');
    writeFileSync(file, writeFileContent(createVolumeImage(), '/hello.txt', content));
    execFileSync(
      process.execPath,
      ['--experimental-strip-types', 'tools/fs.ts', 'new', file, '/empty.txt'],
      { cwd: process.cwd(), stdio: 'pipe' },
    );

    const output = execFileSync(
      process.execPath,
      ['--experimental-strip-types', 'tools/fs.ts', 'cat', file, '/hello.txt'],
      { cwd: process.cwd() },
    );
    const emptyOutput = execFileSync(
      process.execPath,
      ['--experimental-strip-types', 'tools/fs.ts', 'cat', file, '/empty.txt'],
      { cwd: process.cwd() },
    );

    assert.deepEqual(output, content);
    assert.equal(emptyOutput.byteLength, 0);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('removes a root file and frees its block', () => {
  const image = createFileInVolumeImage(createVolumeImage(), '/main.z80');
  const created = parseVolumeImage(image);
  const firstBlock = created.files[0].firstBlock;

  const updated = removeFileFromVolumeImage(image, '/main.z80');
  const volume = parseVolumeImage(updated);

  assert.deepEqual(listVolumePath(volume, '/'), []);
  assert.equal(volume.allocation[firstBlock], ALLOCATION_FREE);
  assert.equal(volume.superblock.freeBlockCount, created.superblock.freeBlockCount + 1);
  assert.throws(() => readFileFromVolumeImage(updated, '/main.z80'), /file not found/);
});

test('removes prefixed files while reusing and reclaiming prefix entries', () => {
  let image = createFileInVolumeImage(createVolumeImage(), '/projects/demo/main.z80');
  image = createFileInVolumeImage(image, '/projects/demo/readme.txt');
  const prefixEntryOffset = prefixEntryStart(0);
  assert.equal(parseVolumeImage(image).prefixes[0].prefix, 'projects/demo');

  const oneRemoved = removeFileFromVolumeImage(image, '/projects/demo/main.z80');
  const partial = parseVolumeImage(oneRemoved);
  assert.deepEqual(listVolumePath(partial, '/projects/demo').map((entry: { name: string }) => entry.name), [
    'readme.txt',
  ]);
  assert.equal(partial.prefixes.length, 1);
  assert.equal(oneRemoved[prefixEntryOffset], ENTRY_STATUS_ACTIVE);

  const allRemoved = removeFileFromVolumeImage(oneRemoved, '/projects/demo/readme.txt');
  const empty = parseVolumeImage(allRemoved);
  assert.deepEqual(listVolumePath(empty, '/projects/demo'), []);
  assert.deepEqual(empty.prefixes, []);
  for (
    let offset = prefixEntryOffset;
    offset < prefixEntryOffset + TM8_FORMAT.prefixEntrySize;
    offset += 1
  ) {
    assert.equal(allRemoved[offset], 0);
  }
});

test('removes a multi-block file chain and zeros the catalog entry', () => {
  const content = Buffer.alloc(TM8_FORMAT.blockBytes + 5, 0x7e);
  const image = writeTwoBlockFileContent(createVolumeImage(), '/big.bin', content);
  const created = parseVolumeImage(image);
  const firstBlock = created.files[0].firstBlock;
  const secondBlock = created.allocation[firstBlock];

  const updated = removeFileFromVolumeImage(image, '/big.bin');
  const volume = parseVolumeImage(updated);

  assert.equal(volume.superblock.freeBlockCount, created.superblock.freeBlockCount + 2);
  assert.equal(volume.allocation[firstBlock], ALLOCATION_FREE);
  assert.equal(volume.allocation[secondBlock], ALLOCATION_FREE);
  for (
    let offset = catalogEntryStart(0);
    offset < catalogEntryStart(0) + TM8_FORMAT.catalogEntrySize;
    offset += 1
  ) {
    assert.equal(updated[offset], 0);
  }
});

test('rejects missing and malformed rm paths', () => {
  const image = createFileInVolumeImage(createVolumeImage(), '/main.z80');

  assert.throws(() => removeFileFromVolumeImage(image, '/missing.z80'), /file not found/);
  assert.throws(() => removeFileFromVolumeImage(image, 'main.z80'), /TM8 paths must start with/);
  assert.throws(() => removeFileFromVolumeImage(image, '/bad/name/'), /missing local filename/);
});

test('fs rm removes files from listings and cat output', () => {
  const dir = mkdtempSync(join(tmpdir(), 'tm8-cli-'));
  try {
    const file = join(dir, 'VOLUME.TM8');
    formatVolumeFile(file);
    execFileSync(
      process.execPath,
      ['--experimental-strip-types', 'tools/fs.ts', 'new', file, '/projects/demo/main.z80'],
      { cwd: process.cwd(), stdio: 'pipe' },
    );

    execFileSync(
      process.execPath,
      ['--experimental-strip-types', 'tools/fs.ts', 'rm', file, '/projects/demo/main.z80'],
      { cwd: process.cwd(), stdio: 'pipe' },
    );
    const listing = execFileSync(
      process.execPath,
      ['--experimental-strip-types', 'tools/fs.ts', 'ls', file, '/projects/demo'],
      { cwd: process.cwd(), encoding: 'utf8' },
    );

    assert.equal(listing, '');
    assert.throws(
      () =>
        execFileSync(
          process.execPath,
          ['--experimental-strip-types', 'tools/fs.ts', 'cat', file, '/projects/demo/main.z80'],
          { cwd: process.cwd(), stdio: 'pipe' },
        ),
      /file not found/,
    );
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('renames a root file while preserving metadata and data', () => {
  const content = Buffer.from('root rename\n', 'utf8');
  const image = writeFileContent(createVolumeImage(), '/main.z80', content);
  const before = parseVolumeImage(image).files[0];

  const updated = moveFileInVolumeImage(image, '/main.z80', '/renamed.z80');
  const volume = parseVolumeImage(updated);

  assert.deepEqual(listVolumePath(volume, '/').map((entry: { name: string }) => entry.name), [
    'renamed.z80',
  ]);
  assert.equal(volume.files[0].fileId, before.fileId);
  assert.equal(volume.files[0].firstBlock, before.firstBlock);
  assert.equal(volume.files[0].size, before.size);
  assert.equal(volume.files[0].fileType, before.fileType);
  assert.deepEqual(readFileFromVolumeImage(updated, '/renamed.z80'), content);
  assert.throws(() => readFileFromVolumeImage(updated, '/main.z80'), /file not found/);
});

test('renames a prefixed file without changing its prefix', () => {
  const image = createFileInVolumeImage(createVolumeImage(), '/projects/demo/main.z80');

  const updated = moveFileInVolumeImage(
    image,
    '/projects/demo/main.z80',
    '/projects/demo/app.z80',
  );
  const volume = parseVolumeImage(updated);

  assert.deepEqual(
    listVolumePath(volume, '/projects/demo').map((entry: { name: string }) => entry.name),
    ['app.z80'],
  );
  assert.deepEqual(volume.prefixes.map((entry: { prefix: string }) => entry.prefix), [
    'projects/demo',
  ]);
});

test('moves a file across prefixes and reclaims the emptied source prefix', () => {
  const content = Buffer.from('moved between prefixes\n', 'utf8');
  const image = writeFileContent(createVolumeImage(), '/old/main.z80', content);

  const updated = moveFileInVolumeImage(image, '/old/main.z80', '/new/main.z80');
  const volume = parseVolumeImage(updated);

  assert.deepEqual(listVolumePath(volume, '/old'), []);
  assert.deepEqual(listVolumePath(volume, '/new').map((entry: { name: string }) => entry.name), [
    'main.z80',
  ]);
  assert.deepEqual(volume.prefixes.map((entry: { prefix: string }) => entry.prefix), ['new']);
  assert.deepEqual(readFileFromVolumeImage(updated, '/new/main.z80'), content);
});

test('moves a file into an existing prefix without reclaiming a still-used source prefix', () => {
  let image = createFileInVolumeImage(createVolumeImage(), '/src/main.z80');
  image = createFileInVolumeImage(image, '/src/other.z80');
  image = createFileInVolumeImage(image, '/dst/existing.z80');
  const before = parseVolumeImage(image);
  const srcPrefixId = before.prefixes.find((entry: { prefix: string }) => entry.prefix === 'src')?.prefixId;
  const dstPrefixId = before.prefixes.find((entry: { prefix: string }) => entry.prefix === 'dst')?.prefixId;

  const updated = moveFileInVolumeImage(image, '/src/main.z80', '/dst/main.z80');
  const volume = parseVolumeImage(updated);
  const moved = volume.files.find((entry: { name: string }) => entry.name === 'main.z80');

  assert.deepEqual(listVolumePath(volume, '/src').map((entry: { name: string }) => entry.name), [
    'other.z80',
  ]);
  assert.deepEqual(listVolumePath(volume, '/dst').map((entry: { name: string }) => entry.name), [
    'main.z80',
    'existing.z80',
  ]);
  assert.equal(moved?.prefixId, dstPrefixId);
  assert.ok(volume.prefixes.some((entry: { prefixId: number }) => entry.prefixId === srcPrefixId));
});

test('moves into a new prefix by reusing an emptied source prefix slot when the prefix table is full', () => {
  let image = createVolumeImage();
  for (let index = 0; index < TM8_FORMAT.prefixEntryCount; index += 1) {
    image = createFileInVolumeImage(image, `/p${index}/file.z80`);
  }

  const updated = moveFileInVolumeImage(image, '/p0/file.z80', '/new/file.z80');
  const volume = parseVolumeImage(updated);

  assert.deepEqual(listVolumePath(volume, '/p0'), []);
  assert.deepEqual(listVolumePath(volume, '/new').map((entry: { name: string }) => entry.name), [
    'file.z80',
  ]);
  assert.equal(volume.prefixes.length, TM8_FORMAT.prefixEntryCount);
  assert.ok(!volume.prefixes.some((entry: { prefix: string }) => entry.prefix === 'p0'));
  assert.ok(volume.prefixes.some((entry: { prefix: string }) => entry.prefix === 'new'));
});

test('rejects missing, malformed, and colliding mv paths', () => {
  let image = createFileInVolumeImage(createVolumeImage(), '/main.z80');
  image = createFileInVolumeImage(image, '/existing.z80');

  assert.throws(() => moveFileInVolumeImage(image, '/missing.z80', '/renamed.z80'), /file not found/);
  assert.throws(() => moveFileInVolumeImage(image, 'main.z80', '/renamed.z80'), /TM8 paths must start with/);
  assert.throws(() => moveFileInVolumeImage(image, '/main.z80', '/bad/name/'), /missing local filename/);
  assert.throws(() => moveFileInVolumeImage(image, '/main.z80', '/existing.z80'), /file already exists/);
});

test('fs mv updates listings and preserves cat output', () => {
  const dir = mkdtempSync(join(tmpdir(), 'tm8-cli-'));
  try {
    const file = join(dir, 'VOLUME.TM8');
    const content = Buffer.from('hello mv\n', 'utf8');
    writeFileSync(file, writeFileContent(createVolumeImage(), '/src/main.z80', content));

    execFileSync(
      process.execPath,
      ['--experimental-strip-types', 'tools/fs.ts', 'mv', file, '/src/main.z80', '/dst/app.z80'],
      { cwd: process.cwd(), stdio: 'pipe' },
    );
    const srcListing = execFileSync(
      process.execPath,
      ['--experimental-strip-types', 'tools/fs.ts', 'ls', file, '/src'],
      { cwd: process.cwd(), encoding: 'utf8' },
    );
    const dstListing = execFileSync(
      process.execPath,
      ['--experimental-strip-types', 'tools/fs.ts', 'ls', file, '/dst'],
      { cwd: process.cwd(), encoding: 'utf8' },
    );
    const output = execFileSync(
      process.execPath,
      ['--experimental-strip-types', 'tools/fs.ts', 'cat', file, '/dst/app.z80'],
      { cwd: process.cwd() },
    );

    assert.equal(srcListing, '');
    assert.equal(dstListing, 'app.z80\n');
    assert.deepEqual(output, content);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('imports host bytes into root and prefixed TM8 paths', () => {
  const rootContent = Buffer.from('org 8000h\nret\n', 'utf8');
  const rootImage = importFileIntoVolumeImage(createVolumeImage(), '/main.asm', rootContent);
  const rootVolume = parseVolumeImage(rootImage);

  assert.deepEqual(listVolumePath(rootVolume, '/').map((entry: { name: string }) => entry.name), [
    'main.asm',
  ]);
  assert.deepEqual(readFileFromVolumeImage(rootImage, '/main.asm'), rootContent);
  assert.equal(rootVolume.files[0].size, rootContent.byteLength);

  const prefixedContent = Buffer.from('call init\nret\n', 'utf8');
  const prefixedImage = importFileIntoVolumeImage(
    createVolumeImage(),
    '/src/lib.asm',
    prefixedContent,
  );
  const prefixedVolume = parseVolumeImage(prefixedImage);

  assert.deepEqual(
    listVolumePath(prefixedVolume, '/src').map((entry: { name: string }) => entry.name),
    ['lib.asm'],
  );
  assert.deepEqual(readFileFromVolumeImage(prefixedImage, '/src/lib.asm'), prefixedContent);
  assert.deepEqual(prefixedVolume.prefixes.map((entry: { prefix: string }) => entry.prefix), [
    'src',
  ]);
});

test('imports zero-length files with one allocated block', () => {
  const image = importFileIntoVolumeImage(createVolumeImage(), '/empty.asm', Buffer.alloc(0));
  const volume = parseVolumeImage(image);
  const firstBlock = volume.files[0].firstBlock;

  assert.equal(volume.files[0].size, 0);
  assert.equal(volume.allocation[firstBlock], ALLOCATION_END);
  assert.equal(volume.superblock.freeBlockCount, initialFreeBlockCount() - 1);
  assert.deepEqual(readFileFromVolumeImage(image, '/empty.asm'), Buffer.alloc(0));
});

test('imports multi-block files and zero-fills final block padding', () => {
  const content = Buffer.alloc(TM8_FORMAT.blockBytes * 2 + 17);
  for (let index = 0; index < content.byteLength; index += 1) {
    content[index] = index & 0xff;
  }

  const image = importFileIntoVolumeImage(createVolumeImage(), '/big.asm', content);
  const volume = parseVolumeImage(image);
  const file = volume.files[0];
  const blocks = [
    file.firstBlock,
    volume.allocation[file.firstBlock],
    volume.allocation[volume.allocation[file.firstBlock]],
  ];
  const finalBlock = blocks[2];

  assert.deepEqual(readFileFromVolumeImage(image, '/big.asm'), content);
  assert.equal(volume.allocation[blocks[0]], blocks[1]);
  assert.equal(volume.allocation[blocks[1]], blocks[2]);
  assert.equal(volume.allocation[blocks[2]], ALLOCATION_END);
  assert.equal(volume.superblock.freeBlockCount, initialFreeBlockCount() - 3);
  for (
    let offset = finalBlock * TM8_FORMAT.blockBytes + 17;
    offset < (finalBlock + 1) * TM8_FORMAT.blockBytes;
    offset += 1
  ) {
    assert.equal(image[offset], 0);
  }
});

test('rejects colliding, malformed, and no-space imports', () => {
  const image = importFileIntoVolumeImage(createVolumeImage(), '/main.asm', Buffer.from('one'));

  assert.throws(
    () => importFileIntoVolumeImage(image, '/main.asm', Buffer.from('two')),
    /file already exists/,
  );
  assert.throws(
    () => importFileIntoVolumeImage(image, 'main.asm', Buffer.from('two')),
    /TM8 paths must start with/,
  );
  assert.throws(
    () => importFileIntoVolumeImage(image, '/bad/name/', Buffer.from('two')),
    /missing local filename/,
  );

  const noSpace = createVolumeImage();
  const allocationStart = TM8_FORMAT.allocationStartBlock * TM8_FORMAT.blockBytes;
  for (let block = TM8_FORMAT.dataStartBlock; block < TM8_FORMAT.totalBlocks; block += 1) {
    writeU16(noSpace, allocationStart + block * 2, ALLOCATION_END);
  }
  rewriteFreeBlockCount(noSpace, 0);
  assert.throws(() => importFileIntoVolumeImage(noSpace, '/main.asm', Buffer.from('x')), /no free blocks/);
});

test('rejects catalog-full and prefix-full imports', () => {
  let catalogFull = createVolumeImage();
  for (let index = 0; index < TM8_FORMAT.catalogEntryCount; index += 1) {
    catalogFull = importFileIntoVolumeImage(catalogFull, `/file${index}.asm`, Buffer.from('x'));
  }
  assert.throws(
    () => importFileIntoVolumeImage(catalogFull, '/overflow.asm', Buffer.from('x')),
    /file catalog full/,
  );

  let prefixFull = createVolumeImage();
  for (let index = 0; index < TM8_FORMAT.prefixEntryCount; index += 1) {
    prefixFull = importFileIntoVolumeImage(prefixFull, `/p${index}/file.asm`, Buffer.from('x'));
  }
  assert.throws(
    () => importFileIntoVolumeImage(prefixFull, '/overflow/file.asm', Buffer.from('x')),
    /prefix table full/,
  );
});

test('fs import updates listings and cat output', () => {
  const dir = mkdtempSync(join(tmpdir(), 'tm8-cli-'));
  try {
    const volumePath = join(dir, 'VOLUME.TM8');
    const hostPath = join(dir, 'MAIN.ASM');
    const content = Buffer.from('start:\n  ret\n', 'utf8');
    formatVolumeFile(volumePath);
    writeFileSync(hostPath, content);

    execFileSync(
      process.execPath,
      ['--experimental-strip-types', 'tools/fs.ts', 'import', volumePath, hostPath, '/src/main.asm'],
      { cwd: process.cwd(), stdio: 'pipe' },
    );
    const listing = execFileSync(
      process.execPath,
      ['--experimental-strip-types', 'tools/fs.ts', 'ls', volumePath, '/src'],
      { cwd: process.cwd(), encoding: 'utf8' },
    );
    const output = execFileSync(
      process.execPath,
      ['--experimental-strip-types', 'tools/fs.ts', 'cat', volumePath, '/src/main.asm'],
      { cwd: process.cwd() },
    );

    assert.equal(listing, 'main.asm\n');
    assert.deepEqual(output, content);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('fs export writes root and prefixed TM8 files to host paths', () => {
  const dir = mkdtempSync(join(tmpdir(), 'tm8-cli-'));
  try {
    const volumePath = join(dir, 'VOLUME.TM8');
    const rootOut = join(dir, 'ROOT.ASM');
    const prefixedOut = join(dir, 'MAIN.ASM');
    const rootContent = Buffer.from('org 2000h\n', 'utf8');
    const prefixedContent = Buffer.from('start:\n  ret\n', 'utf8');
    const image = importFileIntoVolumeImage(
      importFileIntoVolumeImage(createVolumeImage(), '/boot.asm', rootContent),
      '/src/main.asm',
      prefixedContent,
    );
    writeFileSync(volumePath, image);

    execFileSync(
      process.execPath,
      ['--experimental-strip-types', 'tools/fs.ts', 'export', volumePath, '/boot.asm', rootOut],
      { cwd: process.cwd(), stdio: 'pipe' },
    );
    execFileSync(
      process.execPath,
      [
        '--experimental-strip-types',
        'tools/fs.ts',
        'export',
        volumePath,
        '/src/main.asm',
        prefixedOut,
      ],
      { cwd: process.cwd(), stdio: 'pipe' },
    );

    assert.deepEqual(readFileSync(rootOut), rootContent);
    assert.deepEqual(readFileSync(prefixedOut), prefixedContent);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('fs export writes zero-length and multi-block files exactly', () => {
  const dir = mkdtempSync(join(tmpdir(), 'tm8-cli-'));
  try {
    const volumePath = join(dir, 'VOLUME.TM8');
    const emptyOut = join(dir, 'EMPTY.BIN');
    const bigOut = join(dir, 'BIG.BIN');
    const bigContent = Buffer.alloc(TM8_FORMAT.blockBytes + 37);
    for (let index = 0; index < bigContent.byteLength; index += 1) {
      bigContent[index] = index % 251;
    }
    const image = importFileIntoVolumeImage(
      importFileIntoVolumeImage(createVolumeImage(), '/empty.bin', Buffer.alloc(0)),
      '/big.bin',
      bigContent,
    );
    writeFileSync(volumePath, image);

    execFileSync(
      process.execPath,
      ['--experimental-strip-types', 'tools/fs.ts', 'export', volumePath, '/empty.bin', emptyOut],
      { cwd: process.cwd(), stdio: 'pipe' },
    );
    execFileSync(
      process.execPath,
      ['--experimental-strip-types', 'tools/fs.ts', 'export', volumePath, '/big.bin', bigOut],
      { cwd: process.cwd(), stdio: 'pipe' },
    );

    assert.equal(readFileSync(emptyOut).byteLength, 0);
    assert.deepEqual(readFileSync(bigOut), bigContent);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('fs export rejects missing files, malformed volumes, and host overwrites', () => {
  const dir = mkdtempSync(join(tmpdir(), 'tm8-cli-'));
  try {
    const volumePath = join(dir, 'VOLUME.TM8');
    const malformedVolumePath = join(dir, 'BAD.TM8');
    const badChecksumVolumePath = join(dir, 'BAD-CHECKSUM.TM8');
    const outputPath = join(dir, 'MAIN.ASM');
    const existingPath = join(dir, 'EXISTING.ASM');
    const existingContent = Buffer.from('keep me\n', 'utf8');
    writeFileSync(
      volumePath,
      importFileIntoVolumeImage(createVolumeImage(), '/main.asm', Buffer.from('start:\n')),
    );
    writeFileSync(malformedVolumePath, Buffer.from('not a tm8 volume'));
    const badChecksum = createVolumeImage();
    badChecksum[100] ^= 0xff;
    writeFileSync(badChecksumVolumePath, badChecksum);
    writeFileSync(existingPath, existingContent);

    assert.throws(
      () =>
        execFileSync(
          process.execPath,
          [
            '--experimental-strip-types',
            'tools/fs.ts',
            'export',
            volumePath,
            '/missing.asm',
            outputPath,
          ],
          { cwd: process.cwd(), stdio: 'pipe' },
        ),
      /file not found/,
    );
    assert.throws(
      () =>
        execFileSync(
          process.execPath,
          [
            '--experimental-strip-types',
            'tools/fs.ts',
            'export',
            malformedVolumePath,
            '/main.asm',
            outputPath,
          ],
          { cwd: process.cwd(), stdio: 'pipe' },
        ),
      /unexpected TM8 volume size/,
    );
    assert.throws(
      () =>
        execFileSync(
          process.execPath,
          [
            '--experimental-strip-types',
            'tools/fs.ts',
            'export',
            badChecksumVolumePath,
            '/main.asm',
            outputPath,
          ],
          { cwd: process.cwd(), stdio: 'pipe' },
        ),
      /bad TM8 superblock checksum/,
    );
    assert.throws(
      () =>
        execFileSync(
          process.execPath,
          [
            '--experimental-strip-types',
            'tools/fs.ts',
            'export',
            volumePath,
            '/main.asm',
            existingPath,
          ],
          { cwd: process.cwd(), stdio: 'pipe' },
        ),
      /refusing to overwrite existing file/,
    );
    assert.deepEqual(readFileSync(existingPath), existingContent);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('fs copy copies root and prefixed TM8 files between volumes', () => {
  const dir = mkdtempSync(join(tmpdir(), 'tm8-cli-'));
  try {
    const sourcePath = join(dir, 'SOURCE.TM8');
    const destinationPath = join(dir, 'DEST.TM8');
    const rootContent = Buffer.from('org 2000h\n', 'utf8');
    const prefixedContent = Buffer.from('start:\n  ret\n', 'utf8');
    writeFileSync(
      sourcePath,
      importFileIntoVolumeImage(
        importFileIntoVolumeImage(createVolumeImage(), '/boot.asm', rootContent),
        '/src/main.asm',
        prefixedContent,
      ),
    );
    formatVolumeFile(destinationPath);

    execFileSync(
      process.execPath,
      [
        '--experimental-strip-types',
        'tools/fs.ts',
        'copy',
        `${sourcePath}:/boot.asm`,
        `${destinationPath}:/boot.asm`,
      ],
      { cwd: process.cwd(), stdio: 'pipe' },
    );
    execFileSync(
      process.execPath,
      [
        '--experimental-strip-types',
        'tools/fs.ts',
        'copy',
        `${sourcePath}:/src/main.asm`,
        `${destinationPath}:/copy/main.asm`,
      ],
      { cwd: process.cwd(), stdio: 'pipe' },
    );

    assert.deepEqual(readFileFromVolumeImage(readFileSync(destinationPath), '/boot.asm'), rootContent);
    assert.deepEqual(
      readFileFromVolumeImage(readFileSync(destinationPath), '/copy/main.asm'),
      prefixedContent,
    );
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('fs copy preserves zero-length and multi-block file contents', () => {
  const dir = mkdtempSync(join(tmpdir(), 'tm8-cli-'));
  try {
    const sourcePath = join(dir, 'SOURCE.TM8');
    const destinationPath = join(dir, 'DEST.TM8');
    const bigContent = Buffer.alloc(TM8_FORMAT.blockBytes + 37);
    for (let index = 0; index < bigContent.byteLength; index += 1) {
      bigContent[index] = index % 251;
    }
    writeFileSync(
      sourcePath,
      importFileIntoVolumeImage(
        importFileIntoVolumeImage(createVolumeImage(), '/empty.bin', Buffer.alloc(0)),
        '/big.bin',
        bigContent,
      ),
    );
    formatVolumeFile(destinationPath);

    execFileSync(
      process.execPath,
      [
        '--experimental-strip-types',
        'tools/fs.ts',
        'copy',
        `${sourcePath}:/empty.bin`,
        `${destinationPath}:/empty.bin`,
      ],
      { cwd: process.cwd(), stdio: 'pipe' },
    );
    execFileSync(
      process.execPath,
      [
        '--experimental-strip-types',
        'tools/fs.ts',
        'copy',
        `${sourcePath}:/big.bin`,
        `${destinationPath}:/big.bin`,
      ],
      { cwd: process.cwd(), stdio: 'pipe' },
    );

    assert.equal(readFileFromVolumeImage(readFileSync(destinationPath), '/empty.bin').byteLength, 0);
    assert.deepEqual(readFileFromVolumeImage(readFileSync(destinationPath), '/big.bin'), bigContent);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('fs copy rejects missing sources, destination collisions, malformed specs, and bad volumes', () => {
  const dir = mkdtempSync(join(tmpdir(), 'tm8-cli-'));
  try {
    const sourcePath = join(dir, 'SOURCE.TM8');
    const destinationPath = join(dir, 'DEST.TM8');
    const malformedSourcePath = join(dir, 'BAD-SOURCE.TM8');
    const malformedDestinationPath = join(dir, 'BAD-DEST.TM8');
    const sourceContent = Buffer.from('start:\n', 'utf8');
    const destinationContent = Buffer.from('existing:\n', 'utf8');
    writeFileSync(
      sourcePath,
      importFileIntoVolumeImage(createVolumeImage(), '/main.asm', sourceContent),
    );
    writeFileSync(
      destinationPath,
      importFileIntoVolumeImage(createVolumeImage(), '/existing.asm', destinationContent),
    );
    writeFileSync(malformedSourcePath, Buffer.from('not a tm8 volume'));
    const malformedDestination = createVolumeImage();
    malformedDestination[100] ^= 0xff;
    writeFileSync(malformedDestinationPath, malformedDestination);

    assert.throws(
      () =>
        execFileSync(
          process.execPath,
          [
            '--experimental-strip-types',
            'tools/fs.ts',
            'copy',
            `${sourcePath}:/missing.asm`,
            `${destinationPath}:/copy.asm`,
          ],
          { cwd: process.cwd(), stdio: 'pipe' },
        ),
      /file not found/,
    );
    assert.throws(
      () =>
        execFileSync(
          process.execPath,
          [
            '--experimental-strip-types',
            'tools/fs.ts',
            'copy',
            `${sourcePath}:/main.asm`,
            `${destinationPath}:/existing.asm`,
          ],
          { cwd: process.cwd(), stdio: 'pipe' },
        ),
      /file already exists/,
    );
    assert.throws(
      () =>
        execFileSync(
          process.execPath,
          [
            '--experimental-strip-types',
            'tools/fs.ts',
            'copy',
            `${sourcePath}/main.asm`,
            `${destinationPath}:/copy.asm`,
          ],
          { cwd: process.cwd(), stdio: 'pipe' },
        ),
      /expected VOLUME\.TM8:\/path\/file/,
    );
    assert.throws(
      () =>
        execFileSync(
          process.execPath,
          [
            '--experimental-strip-types',
            'tools/fs.ts',
            'copy',
            `${sourcePath}:/main.asm`,
            `${destinationPath}/copy.asm`,
          ],
          { cwd: process.cwd(), stdio: 'pipe' },
        ),
      /expected VOLUME\.TM8:\/path\/file/,
    );
    assert.throws(
      () =>
        execFileSync(
          process.execPath,
          [
            '--experimental-strip-types',
            'tools/fs.ts',
            'copy',
            `${malformedSourcePath}:/main.asm`,
            `${destinationPath}:/copy.asm`,
          ],
          { cwd: process.cwd(), stdio: 'pipe' },
        ),
      /unexpected TM8 volume size/,
    );
    assert.throws(
      () =>
        execFileSync(
          process.execPath,
          [
            '--experimental-strip-types',
            'tools/fs.ts',
            'copy',
            `${sourcePath}:/main.asm`,
            `${malformedDestinationPath}:/copy.asm`,
          ],
          { cwd: process.cwd(), stdio: 'pipe' },
        ),
      /bad TM8 superblock checksum/,
    );
    assert.deepEqual(
      readFileFromVolumeImage(readFileSync(destinationPath), '/existing.asm'),
      destinationContent,
    );
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('fs unpack writes root and prefixed files into a host folder tree', () => {
  const dir = mkdtempSync(join(tmpdir(), 'tm8-cli-'));
  try {
    const volumePath = join(dir, 'VOLUME.TM8');
    const outputFolder = join(dir, 'workspace');
    const rootContent = Buffer.from('org 2000h\n', 'utf8');
    const prefixedContent = Buffer.from('start:\n  ret\n', 'utf8');
    writeFileSync(
      volumePath,
      importFileIntoVolumeImage(
        importFileIntoVolumeImage(createVolumeImage(), '/boot.asm', rootContent),
        '/src/main.asm',
        prefixedContent,
      ),
    );

    execFileSync(
      process.execPath,
      ['--experimental-strip-types', 'tools/fs.ts', 'unpack', volumePath, outputFolder],
      { cwd: process.cwd(), stdio: 'pipe' },
    );

    assert.deepEqual(readFileSync(join(outputFolder, 'boot.asm')), rootContent);
    assert.deepEqual(readFileSync(join(outputFolder, 'src', 'main.asm')), prefixedContent);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('fs unpack preserves zero-length and multi-block file contents', () => {
  const dir = mkdtempSync(join(tmpdir(), 'tm8-cli-'));
  try {
    const volumePath = join(dir, 'VOLUME.TM8');
    const outputFolder = join(dir, 'workspace');
    const bigContent = Buffer.alloc(TM8_FORMAT.blockBytes + 37);
    for (let index = 0; index < bigContent.byteLength; index += 1) {
      bigContent[index] = index % 251;
    }
    writeFileSync(
      volumePath,
      importFileIntoVolumeImage(
        importFileIntoVolumeImage(createVolumeImage(), '/empty.bin', Buffer.alloc(0)),
        '/bin/big.bin',
        bigContent,
      ),
    );

    execFileSync(
      process.execPath,
      ['--experimental-strip-types', 'tools/fs.ts', 'unpack', volumePath, outputFolder],
      { cwd: process.cwd(), stdio: 'pipe' },
    );

    assert.equal(readFileSync(join(outputFolder, 'empty.bin')).byteLength, 0);
    assert.deepEqual(readFileSync(join(outputFolder, 'bin', 'big.bin')), bigContent);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('fs unpack rejects host overwrites and malformed volumes', () => {
  const dir = mkdtempSync(join(tmpdir(), 'tm8-cli-'));
  try {
    const volumePath = join(dir, 'VOLUME.TM8');
    const malformedVolumePath = join(dir, 'BAD.TM8');
    const badChecksumVolumePath = join(dir, 'BAD-CHECKSUM.TM8');
    const outputFolder = join(dir, 'workspace');
    const existingContent = Buffer.from('keep me\n', 'utf8');
    writeFileSync(
      volumePath,
      importFileIntoVolumeImage(createVolumeImage(), '/src/main.asm', Buffer.from('start:\n')),
    );
    writeFileSync(malformedVolumePath, Buffer.from('not a tm8 volume'));
    const badChecksum = createVolumeImage();
    badChecksum[100] ^= 0xff;
    writeFileSync(badChecksumVolumePath, badChecksum);
    mkdirSync(join(outputFolder, 'src'), { recursive: true });
    writeFileSync(join(outputFolder, 'src', 'main.asm'), existingContent);

    assert.throws(
      () =>
        execFileSync(
          process.execPath,
          ['--experimental-strip-types', 'tools/fs.ts', 'unpack', volumePath, outputFolder],
          { cwd: process.cwd(), stdio: 'pipe' },
        ),
      /refusing to overwrite existing file/,
    );
    assert.deepEqual(readFileSync(join(outputFolder, 'src', 'main.asm')), existingContent);
    assert.throws(
      () =>
        execFileSync(
          process.execPath,
          ['--experimental-strip-types', 'tools/fs.ts', 'unpack', malformedVolumePath, outputFolder],
          { cwd: process.cwd(), stdio: 'pipe' },
        ),
      /unexpected TM8 volume size/,
    );
    assert.throws(
      () =>
        execFileSync(
          process.execPath,
          [
            '--experimental-strip-types',
            'tools/fs.ts',
            'unpack',
            badChecksumVolumePath,
            outputFolder,
          ],
          { cwd: process.cwd(), stdio: 'pipe' },
        ),
      /bad TM8 superblock checksum/,
    );
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('fs unpack rejects unsafe paths and file-directory collisions before writing output', () => {
  const dir = mkdtempSync(join(tmpdir(), 'tm8-cli-'));
  try {
    const unsafeVolumePath = join(dir, 'UNSAFE.TM8');
    const collisionVolumePath = join(dir, 'COLLISION.TM8');
    const unsafeOutputFolder = join(dir, 'unsafe-workspace');
    const collisionOutputFolder = join(dir, 'collision-workspace');
    writeFileSync(
      unsafeVolumePath,
      importFileIntoVolumeImage(createVolumeImage(), '/../outside.asm', Buffer.from('outside\n')),
    );
    writeFileSync(
      collisionVolumePath,
      importFileIntoVolumeImage(
        importFileIntoVolumeImage(createVolumeImage(), '/src', Buffer.from('root file\n')),
        '/src/main.asm',
        Buffer.from('prefixed file\n'),
      ),
    );

    assert.throws(
      () =>
        execFileSync(
          process.execPath,
          ['--experimental-strip-types', 'tools/fs.ts', 'unpack', unsafeVolumePath, unsafeOutputFolder],
          { cwd: process.cwd(), stdio: 'pipe' },
        ),
      /cannot unpack unsafe TM8 path/,
    );
    assert.throws(
      () => readFileSync(join(dir, 'outside.asm')),
      /ENOENT/,
    );
    assert.throws(
      () =>
        execFileSync(
          process.execPath,
          [
            '--experimental-strip-types',
            'tools/fs.ts',
            'unpack',
            collisionVolumePath,
            collisionOutputFolder,
          ],
          { cwd: process.cwd(), stdio: 'pipe' },
        ),
      /cannot unpack both file and directory/,
    );
    assert.throws(
      () => readFileSync(join(collisionOutputFolder, 'src')),
      /ENOENT/,
    );
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('fs pack writes root and nested host files into a TM8 volume', () => {
  const dir = mkdtempSync(join(tmpdir(), 'tm8-cli-'));
  try {
    const folder = join(dir, 'workspace');
    const volumePath = join(dir, 'VOLUME.TM8');
    const rootContent = Buffer.from('org 2000h\n', 'utf8');
    const nestedContent = Buffer.from('start:\n  ret\n', 'utf8');
    mkdirSync(join(folder, 'src'), { recursive: true });
    writeFileSync(join(folder, 'boot.asm'), rootContent);
    writeFileSync(join(folder, 'src', 'main.asm'), nestedContent);

    execFileSync(
      process.execPath,
      ['--experimental-strip-types', 'tools/fs.ts', 'pack', folder, volumePath],
      { cwd: process.cwd(), stdio: 'pipe' },
    );

    assert.deepEqual(readFileFromVolumeImage(readFileSync(volumePath), '/boot.asm'), rootContent);
    assert.deepEqual(readFileFromVolumeImage(readFileSync(volumePath), '/src/main.asm'), nestedContent);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('fs pack preserves zero-length and multi-block file contents', () => {
  const dir = mkdtempSync(join(tmpdir(), 'tm8-cli-'));
  try {
    const folder = join(dir, 'workspace');
    const volumePath = join(dir, 'VOLUME.TM8');
    const bigContent = Buffer.alloc(TM8_FORMAT.blockBytes + 37);
    for (let index = 0; index < bigContent.byteLength; index += 1) {
      bigContent[index] = index % 251;
    }
    mkdirSync(join(folder, 'bin'), { recursive: true });
    writeFileSync(join(folder, 'empty.bin'), Buffer.alloc(0));
    writeFileSync(join(folder, 'bin', 'big.bin'), bigContent);

    execFileSync(
      process.execPath,
      ['--experimental-strip-types', 'tools/fs.ts', 'pack', folder, volumePath],
      { cwd: process.cwd(), stdio: 'pipe' },
    );

    assert.equal(readFileFromVolumeImage(readFileSync(volumePath), '/empty.bin').byteLength, 0);
    assert.deepEqual(readFileFromVolumeImage(readFileSync(volumePath), '/bin/big.bin'), bigContent);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('fs pack rejects illegal names, symlinks, and output overwrites', () => {
  const dir = mkdtempSync(join(tmpdir(), 'tm8-cli-'));
  try {
    const illegalFolder = join(dir, 'illegal');
    const symlinkFolder = join(dir, 'symlinked');
    const realRootFolder = join(dir, 'real-root');
    const rootSymlinkFolder = join(dir, 'root-link');
    const overwriteFolder = join(dir, 'overwrite');
    const nestedOutputFolder = join(dir, 'nested-output');
    const outsidePath = join(dir, 'outside.asm');
    const illegalVolumePath = join(dir, 'ILLEGAL.TM8');
    const symlinkVolumePath = join(dir, 'SYMLINK.TM8');
    const rootSymlinkVolumePath = join(dir, 'ROOT-SYMLINK.TM8');
    const overwriteVolumePath = join(dir, 'EXISTING.TM8');
    const nestedOutputVolumePath = join(nestedOutputFolder, 'out.tm8');
    const existingVolume = createVolumeImage();
    mkdirSync(join(illegalFolder, 'src'), { recursive: true });
    mkdirSync(symlinkFolder, { recursive: true });
    mkdirSync(realRootFolder, { recursive: true });
    mkdirSync(overwriteFolder, { recursive: true });
    mkdirSync(nestedOutputFolder, { recursive: true });
    writeFileSync(join(illegalFolder, 'src', 'Main.asm'), Buffer.from('bad name\n'));
    writeFileSync(outsidePath, Buffer.from('outside\n'));
    symlinkSync(outsidePath, join(symlinkFolder, 'outside.asm'));
    writeFileSync(join(realRootFolder, 'main.asm'), Buffer.from('start:\n'));
    symlinkSync(realRootFolder, rootSymlinkFolder);
    writeFileSync(join(overwriteFolder, 'main.asm'), Buffer.from('start:\n'));
    writeFileSync(overwriteVolumePath, existingVolume);
    writeFileSync(join(nestedOutputFolder, 'main.asm'), Buffer.from('start:\n'));
    writeFileSync(nestedOutputVolumePath, existingVolume);

    assert.throws(
      () =>
        execFileSync(
          process.execPath,
          ['--experimental-strip-types', 'tools/fs.ts', 'pack', illegalFolder, illegalVolumePath],
          { cwd: process.cwd(), stdio: 'pipe' },
        ),
      /bad file name/,
    );
    assert.throws(
      () =>
        execFileSync(
          process.execPath,
          ['--experimental-strip-types', 'tools/fs.ts', 'pack', symlinkFolder, symlinkVolumePath],
          { cwd: process.cwd(), stdio: 'pipe' },
        ),
      /cannot pack symbolic link/,
    );
    assert.throws(
      () =>
        execFileSync(
          process.execPath,
          ['--experimental-strip-types', 'tools/fs.ts', 'pack', rootSymlinkFolder, rootSymlinkVolumePath],
          { cwd: process.cwd(), stdio: 'pipe' },
        ),
      /cannot pack symbolic link/,
    );
    assert.throws(
      () =>
        execFileSync(
          process.execPath,
          ['--experimental-strip-types', 'tools/fs.ts', 'pack', overwriteFolder, overwriteVolumePath],
          { cwd: process.cwd(), stdio: 'pipe' },
        ),
      /refusing to overwrite existing file/,
    );
    assert.throws(
      () =>
        execFileSync(
          process.execPath,
          ['--experimental-strip-types', 'tools/fs.ts', 'pack', nestedOutputFolder, nestedOutputVolumePath],
          { cwd: process.cwd(), stdio: 'pipe' },
        ),
      /refusing to overwrite existing file/,
    );
    assert.deepEqual(readFileSync(overwriteVolumePath), existingVolume);
    assert.deepEqual(readFileSync(nestedOutputVolumePath), existingVolume);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('fs pack reports format-layer capacity errors', () => {
  const dir = mkdtempSync(join(tmpdir(), 'tm8-cli-'));
  try {
    const catalogFolder = join(dir, 'catalog-workspace');
    const catalogVolumePath = join(dir, 'CATALOG.TM8');
    const prefixFolder = join(dir, 'prefix-workspace');
    const prefixVolumePath = join(dir, 'PREFIX.TM8');
    mkdirSync(catalogFolder, { recursive: true });
    for (let index = 0; index <= TM8_FORMAT.catalogEntryCount; index += 1) {
      writeFileSync(join(catalogFolder, `file${index}.asm`), Buffer.from('x'));
    }
    for (let index = 0; index <= TM8_FORMAT.prefixEntryCount; index += 1) {
      mkdirSync(join(prefixFolder, `p${index}`), { recursive: true });
      writeFileSync(join(prefixFolder, `p${index}`, 'file.asm'), Buffer.from('x'));
    }

    assert.throws(
      () =>
        execFileSync(
          process.execPath,
          ['--experimental-strip-types', 'tools/fs.ts', 'pack', catalogFolder, catalogVolumePath],
          { cwd: process.cwd(), stdio: 'pipe' },
        ),
      /file catalog full/,
    );
    assert.throws(
      () =>
        execFileSync(
          process.execPath,
          ['--experimental-strip-types', 'tools/fs.ts', 'pack', prefixFolder, prefixVolumePath],
          { cwd: process.cwd(), stdio: 'pipe' },
        ),
      /prefix table full/,
    );
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
