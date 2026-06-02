#!/usr/bin/env node

const { readFileSync, writeFileSync } = require('node:fs');

const {
  createFileInVolumeImage,
  formatVolumeFile,
  listVolumePath,
  parseVolumeImage,
} = require('./tm8/format.ts');

function usage(): never {
  console.error('usage: tm8fs format VOLUME.TM8');
  console.error('       tm8fs info VOLUME.TM8');
  console.error('       tm8fs new VOLUME.TM8 /path/file');
  console.error('       tm8fs ls VOLUME.TM8 /path');
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

function printListing(volumePath: string, path: string): void {
  const volume = parseVolumeImage(readFileSync(volumePath));
  for (const entry of listVolumePath(volume, path)) {
    console.log(entry.name);
  }
}

function createNewFile(volumePath: string, path: string): void {
  writeFileSync(volumePath, createFileInVolumeImage(readFileSync(volumePath), path));
}

function main(argv: string[]): void {
  const [command, path, tm8Path] = argv;
  if (!command || !path) {
    usage();
  }

  if (command === 'format') {
    if (argv.length !== 2) {
      usage();
    }
    formatVolumeFile(path);
    return;
  }

  if (command === 'info') {
    if (argv.length !== 2) {
      usage();
    }
    printInfo(path);
    return;
  }

  if (command === 'ls') {
    if (argv.length !== 3 || !tm8Path) {
      usage();
    }
    printListing(path, tm8Path);
    return;
  }

  if (command === 'new') {
    if (argv.length !== 3 || !tm8Path) {
      usage();
    }
    createNewFile(path, tm8Path);
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
