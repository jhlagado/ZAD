#!/usr/bin/env node

const { readFileSync, writeFileSync } = require('node:fs');

const {
  createFileInVolumeImage,
  formatVolumeFile,
  importFileIntoVolumeImage,
  listVolumePath,
  moveFileInVolumeImage,
  parseVolumeImage,
  readFileFromVolumeImage,
  removeFileFromVolumeImage,
} = require('./tm8/format.ts');

function usage(): never {
  console.error('usage: fs format VOLUME.TM8');
  console.error('       fs info VOLUME.TM8');
  console.error('       fs import VOLUME.TM8 hostfile /path/file');
  console.error('       fs export VOLUME.TM8 /path/file hostfile');
  console.error('       fs copy SOURCE.TM8:/path/file DEST.TM8:/path/file');
  console.error('       fs new VOLUME.TM8 /path/file');
  console.error('       fs rm VOLUME.TM8 /path/file');
  console.error('       fs mv VOLUME.TM8 /old/path /new/path');
  console.error('       fs ls VOLUME.TM8 /path');
  console.error('       fs cat VOLUME.TM8 /path/file');
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

function importFile(volumePath: string, hostPath: string, tm8Path: string): void {
  writeFileSync(
    volumePath,
    importFileIntoVolumeImage(readFileSync(volumePath), tm8Path, readFileSync(hostPath)),
  );
}

function exportFile(volumePath: string, tm8Path: string, hostPath: string): void {
  try {
    writeFileSync(hostPath, readFileFromVolumeImage(readFileSync(volumePath), tm8Path), {
      flag: 'wx',
    });
  } catch (error) {
    if (error instanceof Error && 'code' in error && error.code === 'EEXIST') {
      throw new Error(`refusing to overwrite existing file: ${hostPath}`);
    }
    throw error;
  }
}

function parseVolumeFileSpec(spec: string): { volumePath: string; tm8Path: string } {
  const separator = spec.lastIndexOf(':/');
  if (separator <= 0) {
    throw new Error(`expected VOLUME.TM8:/path/file: ${spec}`);
  }

  const volumePath = spec.slice(0, separator);
  const tm8Path = spec.slice(separator + 1);
  if (!volumePath || tm8Path === '/') {
    throw new Error(`expected VOLUME.TM8:/path/file: ${spec}`);
  }

  return { volumePath, tm8Path };
}

function copyFile(sourceSpec: string, destinationSpec: string): void {
  const source = parseVolumeFileSpec(sourceSpec);
  const destination = parseVolumeFileSpec(destinationSpec);
  const content = readFileFromVolumeImage(readFileSync(source.volumePath), source.tm8Path);
  writeFileSync(
    destination.volumePath,
    importFileIntoVolumeImage(
      readFileSync(destination.volumePath),
      destination.tm8Path,
      content,
    ),
  );
}

function printFile(volumePath: string, path: string): void {
  process.stdout.write(readFileFromVolumeImage(readFileSync(volumePath), path));
}

function removeFile(volumePath: string, path: string): void {
  writeFileSync(volumePath, removeFileFromVolumeImage(readFileSync(volumePath), path));
}

function moveFile(volumePath: string, sourcePath: string, destinationPath: string): void {
  writeFileSync(
    volumePath,
    moveFileInVolumeImage(readFileSync(volumePath), sourcePath, destinationPath),
  );
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

  if (command === 'import') {
    const destinationPath = argv[3];
    if (argv.length !== 4 || !tm8Path || !destinationPath) {
      usage();
    }
    importFile(path, tm8Path, destinationPath);
    return;
  }

  if (command === 'export') {
    const hostPath = argv[3];
    if (argv.length !== 4 || !tm8Path || !hostPath) {
      usage();
    }
    exportFile(path, tm8Path, hostPath);
    return;
  }

  if (command === 'copy') {
    const destinationSpec = argv[2];
    if (argv.length !== 3 || !tm8Path || !destinationSpec) {
      usage();
    }
    copyFile(path, tm8Path);
    return;
  }

  if (command === 'rm') {
    if (argv.length !== 3 || !tm8Path) {
      usage();
    }
    removeFile(path, tm8Path);
    return;
  }

  if (command === 'mv') {
    const destinationPath = argv[3];
    if (argv.length !== 4 || !tm8Path || !destinationPath) {
      usage();
    }
    moveFile(path, tm8Path, destinationPath);
    return;
  }

  if (command === 'cat') {
    if (argv.length !== 3 || !tm8Path) {
      usage();
    }
    printFile(path, tm8Path);
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
