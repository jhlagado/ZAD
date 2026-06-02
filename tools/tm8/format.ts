const { writeFileSync } = require('node:fs');

const ALLOCATION_FREE = 0x0000;
const ALLOCATION_RESERVED = 0xffff;
const ENTRY_STATUS_FREE = 0x00;
const ENTRY_STATUS_ACTIVE = 0x01;

const TM8_FORMAT = {
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
  superblockBytes: 512,
  checksumOffset: 72,
} as const;

const TM8_PREFIX_ENTRY = {
  statusOffset: 0,
  prefixIdOffset: 1,
  lengthOffset: 2,
  textOffset: 3,
  textBytes: 121,
  reservedOffset: 124,
  reservedBytes: 4,
} as const;

const TM8_CATALOG_ENTRY = {
  statusOffset: 0,
  fileIdOffset: 1,
  prefixIdOffset: 2,
  nameLengthOffset: 3,
  nameOffset: 4,
  nameBytes: 40,
  firstBlockOffset: 44,
  fileSizeOffset: 46,
  fileTypeOffset: 50,
  reservedOffset: 51,
  reservedBytes: 13,
} as const;

type Superblock = {
  magic: string;
  version: number;
  volumeBytes: number;
  sectorBytes: number;
  blockBytes: number;
  totalBlocks: number;
  allocationStartBlock: number;
  allocationBlockCount: number;
  prefixStartBlock: number;
  prefixBlockCount: number;
  prefixEntrySize: number;
  prefixEntryCount: number;
  catalogStartBlock: number;
  catalogBlockCount: number;
  catalogEntrySize: number;
  catalogEntryCount: number;
  dataStartBlock: number;
  freeBlockCount: number;
  checksum: number;
};

type ParsedVolume = {
  superblock: Superblock;
  allocation: number[];
  prefixes: PrefixEntry[];
  files: FileEntry[];
};

type PrefixEntry = {
  status: number;
  prefixId: number;
  prefix: string;
};

type FileEntry = {
  status: number;
  fileId: number;
  prefixId: number;
  name: string;
  firstBlock: number;
  size: number;
  fileType: number;
};

type ListedFile = {
  fileId: number;
  path: string;
  name: string;
  prefix: string;
  size: number;
  fileType: number;
};

function putU16(buf: Buffer, offset: number, value: number): void {
  buf.writeUInt16LE(value & 0xffff, offset);
}

function putU32(buf: Buffer, offset: number, value: number): void {
  buf.writeUInt32LE(value >>> 0, offset);
}

function readU16(buf: Buffer, offset: number): number {
  return buf.readUInt16LE(offset);
}

function readU32(buf: Buffer, offset: number): number {
  return buf.readUInt32LE(offset);
}

function superblockChecksum(superblock: Buffer): number {
  const copy = Buffer.from(superblock.subarray(0, TM8_FORMAT.superblockBytes));
  putU32(copy, TM8_FORMAT.checksumOffset, 0);
  let checksum = 0;
  for (const byte of copy) {
    checksum = (checksum + byte) >>> 0;
  }
  return checksum;
}

function freeBlockCount(): number {
  return TM8_FORMAT.totalBlocks - TM8_FORMAT.dataStartBlock;
}

function makeSuperblock(): Buffer {
  const block = Buffer.alloc(TM8_FORMAT.blockBytes);
  block.set(Buffer.from(TM8_FORMAT.magic, 'ascii'), 0);
  putU16(block, 8, TM8_FORMAT.version);
  putU16(block, 10, TM8_FORMAT.sectorBytes);
  putU16(block, 12, TM8_FORMAT.blockBytes);
  putU16(block, 14, TM8_FORMAT.totalBlocks);
  putU32(block, 16, TM8_FORMAT.volumeBytes);
  putU16(block, 20, TM8_FORMAT.allocationStartBlock);
  putU16(block, 22, TM8_FORMAT.allocationBlockCount);
  putU16(block, 24, TM8_FORMAT.prefixStartBlock);
  putU16(block, 26, TM8_FORMAT.prefixBlockCount);
  putU16(block, 28, TM8_FORMAT.prefixEntrySize);
  putU16(block, 30, TM8_FORMAT.prefixEntryCount);
  putU16(block, 32, TM8_FORMAT.catalogStartBlock);
  putU16(block, 34, TM8_FORMAT.catalogBlockCount);
  putU16(block, 36, TM8_FORMAT.catalogEntrySize);
  putU16(block, 38, TM8_FORMAT.catalogEntryCount);
  putU16(block, 40, TM8_FORMAT.dataStartBlock);
  putU16(block, 42, freeBlockCount());
  putU32(block, TM8_FORMAT.checksumOffset, superblockChecksum(block));
  return block;
}

function makeAllocationTable(): Buffer {
  const block = Buffer.alloc(TM8_FORMAT.blockBytes);
  for (let index = 0; index < TM8_FORMAT.dataStartBlock; index += 1) {
    putU16(block, index * 2, ALLOCATION_RESERVED);
  }
  return block;
}

function createVolumeImage(): Buffer {
  const image = Buffer.alloc(TM8_FORMAT.volumeBytes);
  image.set(makeSuperblock(), 0);
  image.set(makeAllocationTable(), TM8_FORMAT.allocationStartBlock * TM8_FORMAT.blockBytes);
  return image;
}

function parseSuperblock(image: Buffer): Superblock {
  const magic = image.subarray(0, 8).toString('ascii');
  if (magic !== TM8_FORMAT.magic) {
    throw new Error(`bad TM8 magic: ${JSON.stringify(magic)}`);
  }

  const checksum = readU32(image, TM8_FORMAT.checksumOffset);
  const expectedChecksum = superblockChecksum(image.subarray(0, TM8_FORMAT.superblockBytes));
  if (checksum !== expectedChecksum) {
    throw new Error(`bad TM8 superblock checksum: expected ${expectedChecksum}, got ${checksum}`);
  }

  const superblock: Superblock = {
    magic,
    version: readU16(image, 8),
    sectorBytes: readU16(image, 10),
    blockBytes: readU16(image, 12),
    totalBlocks: readU16(image, 14),
    volumeBytes: readU32(image, 16),
    allocationStartBlock: readU16(image, 20),
    allocationBlockCount: readU16(image, 22),
    prefixStartBlock: readU16(image, 24),
    prefixBlockCount: readU16(image, 26),
    prefixEntrySize: readU16(image, 28),
    prefixEntryCount: readU16(image, 30),
    catalogStartBlock: readU16(image, 32),
    catalogBlockCount: readU16(image, 34),
    catalogEntrySize: readU16(image, 36),
    catalogEntryCount: readU16(image, 38),
    dataStartBlock: readU16(image, 40),
    freeBlockCount: readU16(image, 42),
    checksum,
  };

  const expectedFields: Array<[keyof Superblock, number]> = [
    ['version', TM8_FORMAT.version],
    ['sectorBytes', TM8_FORMAT.sectorBytes],
    ['blockBytes', TM8_FORMAT.blockBytes],
    ['totalBlocks', TM8_FORMAT.totalBlocks],
    ['volumeBytes', TM8_FORMAT.volumeBytes],
    ['allocationStartBlock', TM8_FORMAT.allocationStartBlock],
    ['allocationBlockCount', TM8_FORMAT.allocationBlockCount],
    ['prefixStartBlock', TM8_FORMAT.prefixStartBlock],
    ['prefixBlockCount', TM8_FORMAT.prefixBlockCount],
    ['prefixEntrySize', TM8_FORMAT.prefixEntrySize],
    ['prefixEntryCount', TM8_FORMAT.prefixEntryCount],
    ['catalogStartBlock', TM8_FORMAT.catalogStartBlock],
    ['catalogBlockCount', TM8_FORMAT.catalogBlockCount],
    ['catalogEntrySize', TM8_FORMAT.catalogEntrySize],
    ['catalogEntryCount', TM8_FORMAT.catalogEntryCount],
    ['dataStartBlock', TM8_FORMAT.dataStartBlock],
    ['freeBlockCount', freeBlockCount()],
  ];

  for (const [field, expected] of expectedFields) {
    if (superblock[field] !== expected) {
      throw new Error(`unexpected TM8 ${field}: expected ${expected}, got ${superblock[field]}`);
    }
  }

  assertZeroRange(image, 44, 72, 'reserved superblock byte');
  assertZeroRange(image, 76, TM8_FORMAT.blockBytes, 'reserved superblock byte');

  return superblock;
}

function parseAllocation(image: Buffer): number[] {
  const offset = TM8_FORMAT.allocationStartBlock * TM8_FORMAT.blockBytes;
  const allocation: number[] = [];
  for (let index = 0; index < TM8_FORMAT.totalBlocks; index += 1) {
    allocation.push(readU16(image, offset + index * 2));
  }
  return allocation;
}

function assertZeroRange(
  image: Buffer,
  startOffset: number,
  endOffsetExclusive: number,
  label: string,
): void {
  for (let offset = startOffset; offset < endOffsetExclusive; offset += 1) {
    if (image[offset] !== 0) {
      throw new Error(`non-zero ${label} at offset ${offset}`);
    }
  }
}

function validateAllocation(allocation: number[]): void {
  for (let block = 0; block < TM8_FORMAT.dataStartBlock; block += 1) {
    if (allocation[block] !== ALLOCATION_RESERVED) {
      throw new Error(
        `unexpected allocation entry for metadata block ${block}: ${allocation[block]}`,
      );
    }
  }

  for (let block = TM8_FORMAT.dataStartBlock; block < TM8_FORMAT.totalBlocks; block += 1) {
    if (allocation[block] !== ALLOCATION_FREE) {
      throw new Error(`unexpected allocation entry for free block ${block}: ${allocation[block]}`);
    }
  }
}

function validateAllocationTail(image: Buffer): void {
  const usedBytes = TM8_FORMAT.totalBlocks * 2;
  const startOffset = TM8_FORMAT.allocationStartBlock * TM8_FORMAT.blockBytes + usedBytes;
  const endOffset =
    (TM8_FORMAT.allocationStartBlock + TM8_FORMAT.allocationBlockCount) *
    TM8_FORMAT.blockBytes;
  assertZeroRange(image, startOffset, endOffset, 'reserved allocation table byte');
}

function assertAsciiBytes(entry: Buffer, offset: number, length: number, label: string): void {
  for (let index = 0; index < length; index += 1) {
    const byte = entry[offset + index];
    const isLower = byte >= 0x61 && byte <= 0x7a;
    const isDigit = byte >= 0x30 && byte <= 0x39;
    const isAllowedPunctuation = byte === 0x2e || byte === 0x2f || byte === 0x5f || byte === 0x2d;
    if (!isLower && !isDigit && !isAllowedPunctuation) {
      throw new Error(`bad ${label} byte 0x${byte.toString(16).padStart(2, '0')}`);
    }
  }
}

function assertPrefixText(text: string): void {
  if (!/^[a-z0-9._/-]+$/.test(text) || text.includes('//') || text.startsWith('/') || text.endsWith('/')) {
    throw new Error(`bad prefix: ${JSON.stringify(text)}`);
  }
}

function assertFileNameText(text: string): void {
  if (!/^[a-z0-9._-]+$/.test(text)) {
    throw new Error(`bad file name: ${JSON.stringify(text)}`);
  }
}

function assertPathText(text: string): void {
  if (!/^[a-z0-9._/-]+$/.test(text) || text.includes('//') || text.startsWith('/') || text.endsWith('/')) {
    throw new Error(`bad path: ${JSON.stringify(text)}`);
  }
}

function assertInactiveEntryClean(entry: Buffer, label: string, index: number): void {
  for (let offset = 1; offset < entry.byteLength; offset += 1) {
    if (entry[offset] !== 0) {
      throw new Error(`dirty inactive ${label} entry ${index} at byte ${offset}`);
    }
  }
}

function readAsciiField(entry: Buffer, offset: number, length: number, label: string): string {
  assertAsciiBytes(entry, offset, length, label);
  return entry.subarray(offset, offset + length).toString('ascii');
}

function parsePrefixEntries(image: Buffer): PrefixEntry[] {
  const startOffset = TM8_FORMAT.prefixStartBlock * TM8_FORMAT.blockBytes;
  const prefixes: PrefixEntry[] = [];
  const seen = new Set<number>();

  for (let index = 0; index < TM8_FORMAT.prefixEntryCount; index += 1) {
    const offset = startOffset + index * TM8_FORMAT.prefixEntrySize;
    const entry = image.subarray(offset, offset + TM8_FORMAT.prefixEntrySize);
    const status = entry[TM8_PREFIX_ENTRY.statusOffset];

    if (status === ENTRY_STATUS_FREE) {
      assertInactiveEntryClean(entry, 'prefix', index);
      continue;
    }

    if (status !== ENTRY_STATUS_ACTIVE) {
      throw new Error(`bad prefix entry status ${status} at entry ${index}`);
    }

    const prefixId = entry[TM8_PREFIX_ENTRY.prefixIdOffset];
    const length = entry[TM8_PREFIX_ENTRY.lengthOffset];
    if (prefixId === 0 || seen.has(prefixId)) {
      throw new Error(`bad prefix id ${prefixId} at entry ${index}`);
    }
    if (length < 1 || length > TM8_PREFIX_ENTRY.textBytes) {
      throw new Error(`bad prefix length ${length} at entry ${index}`);
    }

    const prefix = readAsciiField(entry, TM8_PREFIX_ENTRY.textOffset, length, 'prefix');
    assertPrefixText(prefix);
    assertZeroRange(
      entry,
      TM8_PREFIX_ENTRY.textOffset + length,
      TM8_PREFIX_ENTRY.reservedOffset + TM8_PREFIX_ENTRY.reservedBytes,
      `prefix entry ${index} unused byte`,
    );

    seen.add(prefixId);
    prefixes.push({ status, prefixId, prefix });
  }

  return prefixes;
}

function parseFileEntries(image: Buffer, prefixes: PrefixEntry[]): FileEntry[] {
  const startOffset = TM8_FORMAT.catalogStartBlock * TM8_FORMAT.blockBytes;
  const knownPrefixIds = new Set([0, ...prefixes.map((prefix) => prefix.prefixId)]);
  const files: FileEntry[] = [];

  for (let index = 0; index < TM8_FORMAT.catalogEntryCount; index += 1) {
    const offset = startOffset + index * TM8_FORMAT.catalogEntrySize;
    const entry = image.subarray(offset, offset + TM8_FORMAT.catalogEntrySize);
    const status = entry[TM8_CATALOG_ENTRY.statusOffset];

    if (status === ENTRY_STATUS_FREE) {
      assertInactiveEntryClean(entry, 'file', index);
      continue;
    }

    if (status !== ENTRY_STATUS_ACTIVE) {
      throw new Error(`bad file entry status ${status} at entry ${index}`);
    }

    const fileId = entry[TM8_CATALOG_ENTRY.fileIdOffset];
    const prefixId = entry[TM8_CATALOG_ENTRY.prefixIdOffset];
    const nameLength = entry[TM8_CATALOG_ENTRY.nameLengthOffset];
    if (!knownPrefixIds.has(prefixId)) {
      throw new Error(`unknown prefix id ${prefixId} at file entry ${index}`);
    }
    if (nameLength < 1 || nameLength > TM8_CATALOG_ENTRY.nameBytes) {
      throw new Error(`bad file name length ${nameLength} at entry ${index}`);
    }

    const name = readAsciiField(entry, TM8_CATALOG_ENTRY.nameOffset, nameLength, 'file name');
    assertFileNameText(name);
    assertZeroRange(
      entry,
      TM8_CATALOG_ENTRY.nameOffset + nameLength,
      TM8_CATALOG_ENTRY.firstBlockOffset,
      `file entry ${index} unused name byte`,
    );
    assertZeroRange(
      entry,
      TM8_CATALOG_ENTRY.reservedOffset,
      TM8_CATALOG_ENTRY.reservedOffset + TM8_CATALOG_ENTRY.reservedBytes,
      `file entry ${index} reserved byte`,
    );

    files.push({
      status,
      fileId,
      prefixId,
      name,
      firstBlock: readU16(entry, TM8_CATALOG_ENTRY.firstBlockOffset),
      size: readU32(entry, TM8_CATALOG_ENTRY.fileSizeOffset),
      fileType: entry[TM8_CATALOG_ENTRY.fileTypeOffset],
    });
  }

  return files;
}

function parseVolumeImage(image: Buffer): ParsedVolume {
  if (image.byteLength !== TM8_FORMAT.volumeBytes) {
    throw new Error(
      `unexpected TM8 volume size: expected ${TM8_FORMAT.volumeBytes}, got ${image.byteLength}`,
    );
  }

  const superblock = parseSuperblock(image);
  const allocation = parseAllocation(image);
  validateAllocation(allocation);
  validateAllocationTail(image);
  const prefixes = parsePrefixEntries(image);
  const files = parseFileEntries(image, prefixes);

  return {
    superblock,
    allocation,
    prefixes,
    files,
  };
}

function normalizePrefixPath(path: string): string {
  if (path === '/') {
    return '';
  }
  if (!path.startsWith('/')) {
    throw new Error(`TM8 paths must start with /: ${path}`);
  }
  const prefix = path.replace(/^\/+|\/+$/g, '');
  assertPathText(prefix);
  return prefix;
}

function listVolumePath(volume: ParsedVolume, path: string): ListedFile[] {
  const prefix = normalizePrefixPath(path);
  const prefixById = new Map(volume.prefixes.map((entry) => [entry.prefixId, entry.prefix]));
  let targetPrefixId = 0;

  if (prefix !== '') {
    const match = volume.prefixes.find((entry) => entry.prefix === prefix);
    if (!match) {
      return [];
    }
    targetPrefixId = match.prefixId;
  }

  return volume.files
    .filter((file) => file.prefixId === targetPrefixId)
    .map((file) => {
      const filePrefix = file.prefixId === 0 ? '' : prefixById.get(file.prefixId) ?? '';
      const fullPath = `/${filePrefix ? `${filePrefix}/` : ''}${file.name}`;
      return {
        fileId: file.fileId,
        path: fullPath,
        name: file.name,
        prefix: filePrefix,
        size: file.size,
        fileType: file.fileType,
      };
    });
}

function formatVolumeFile(path: string, options: { overwrite?: boolean } = {}): void {
  try {
    writeFileSync(path, createVolumeImage(), { flag: options.overwrite ? 'w' : 'wx' });
  } catch (error) {
    if (!options.overwrite && error instanceof Error && 'code' in error && error.code === 'EEXIST') {
      throw new Error(`refusing to overwrite existing file: ${path}`);
    }
    throw error;
  }
}

module.exports = {
  ALLOCATION_FREE,
  ALLOCATION_RESERVED,
  ENTRY_STATUS_ACTIVE,
  ENTRY_STATUS_FREE,
  TM8_CATALOG_ENTRY,
  TM8_FORMAT,
  TM8_PREFIX_ENTRY,
  createVolumeImage,
  formatVolumeFile,
  listVolumePath,
  parseVolumeImage,
};
