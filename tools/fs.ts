#!/usr/bin/env node

const { mkdirSync, readFileSync, writeFileSync } = require('node:fs');
const { dirname, join } = require('node:path');

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

type ParsedVolumeForCli = {
  prefixes: Array<{ prefixId: number; prefix: string }>;
  files: Array<{ prefixId: number; name: string }>;
};

function usage(): never {
  console.error('usage: fs format VOLUME.TM8');
  console.error('       fs info VOLUME.TM8');
  console.error('       fs import VOLUME.TM8 hostfile /path/file');
  console.error('       fs export VOLUME.TM8 /path/file hostfile');
  console.error('       fs copy SOURCE.TM8:/path/file DEST.TM8:/path/file');
  console.error('       fs unpack VOLUME.TM8 folder');
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

function pathForVolumeFile(volume: ParsedVolumeForCli, file: { prefixId: number; name: string }): string {
  if (file.prefixId === 0) {
    return `/${file.name}`;
  }

  const prefix = volume.prefixes.find((entry) => entry.prefixId === file.prefixId);
  if (!prefix) {
    throw new Error(`unknown prefix id ${file.prefixId} for ${file.name}`);
  }

  return `/${prefix.prefix}/${file.name}`;
}

function hostPathPartsForVolumeFile(
  volume: ParsedVolumeForCli,
  file: { prefixId: number; name: string },
): string[] {
  const tm8Path = pathForVolumeFile(volume, file);
  const parts = tm8Path.slice(1).split('/');
  for (const part of parts) {
    if (part === '' || part === '.' || part === '..') {
      throw new Error(`cannot unpack unsafe TM8 path: ${tm8Path}`);
    }
  }
  return parts;
}

function assertNoUnpackTreeCollisions(paths: string[][]): void {
  const filePaths = new Set(paths.map((parts) => parts.join('\0')));
  for (const parts of paths) {
    for (let length = 1; length < parts.length; length += 1) {
      const prefix = parts.slice(0, length).join('\0');
      if (filePaths.has(prefix)) {
        throw new Error(`cannot unpack both file and directory: /${parts.slice(0, length).join('/')}`);
      }
    }
  }
}

function writeNewHostFile(path: string, content: Buffer): void {
  mkdirSync(dirname(path), { recursive: true });
  try {
    writeFileSync(path, content, { flag: 'wx' });
  } catch (error) {
    if (error instanceof Error && 'code' in error && error.code === 'EEXIST') {
      throw new Error(`refusing to overwrite existing file: ${path}`);
    }
    throw error;
  }
}

function unpackVolume(volumePath: string, hostFolder: string): void {
  const image = readFileSync(volumePath);
  const volume = parseVolumeImage(image) as ParsedVolumeForCli;
  const paths = volume.files.map((file) => ({
    file,
    parts: hostPathPartsForVolumeFile(volume, file),
  }));
  assertNoUnpackTreeCollisions(paths.map((entry) => entry.parts));

  mkdirSync(hostFolder, { recursive: true });
  for (const { file, parts } of paths) {
    const tm8Path = `/${parts.join('/')}`;
    const hostPath = join(hostFolder, ...parts);
    writeNewHostFile(hostPath, readFileFromVolumeImage(image, tm8Path));
  }
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

  if (command === 'unpack') {
    if (argv.length !== 3 || !tm8Path) {
      usage();
    }
    unpackVolume(path, tm8Path);
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
