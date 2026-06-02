#!/usr/bin/env node

const { readFileSync } = require('node:fs');

const { formatVolumeFile, parseVolumeImage } = require('./tm8/format.ts');

function usage(): never {
  console.error('usage: tm8fs <format|info> VOLUME.TM8');
  process.exit(2);
}

function printInfo(path: string): void {
  const volume = parseVolumeImage(readFileSync(path));
  const { superblock } = volume;
  const info = {
    path,
    magic: superblock.magic,
    version: superblock.version,
    volumeBytes: superblock.volumeBytes,
    sectorBytes: superblock.sectorBytes,
    blockBytes: superblock.blockBytes,
    totalBlocks: superblock.totalBlocks,
    dataStartBlock: superblock.dataStartBlock,
    freeBlockCount: superblock.freeBlockCount,
    prefixEntries: superblock.prefixEntryCount,
    fileEntries: superblock.catalogEntryCount,
    checksum: superblock.checksum,
  };
  console.log(JSON.stringify(info, null, 2));
}

function main(argv: string[]): void {
  const [command, path] = argv;
  if (argv.length !== 2 || !command || !path) {
    usage();
  }

  if (command === 'format') {
    formatVolumeFile(path);
    return;
  }

  if (command === 'info') {
    printInfo(path);
    return;
  }

  usage();
}

try {
  main(process.argv.slice(2));
} catch (error) {
  const message = error instanceof Error ? error.message : String(error);
  console.error(`error: ${message}`);
  process.exit(1);
}
