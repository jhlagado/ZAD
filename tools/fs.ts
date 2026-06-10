#!/usr/bin/env node

const { lstatSync, mkdirSync, readdirSync, readFileSync, writeFileSync } = require('node:fs');
const { dirname, join } = require('node:path');

const {
  createFileInVolumeImage,
  createVolumeImage,
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

type HostDirent = {
  name: string;
  isSymbolicLink(): boolean;
  isDirectory(): boolean;
  isFile(): boolean;
};

type HostStats = {
  isSymbolicLink(): boolean;
  isDirectory(): boolean;
};

function usage(): never {
  console.error('usage: fs format VOLUME.TM8');
  console.error('       fs info VOLUME.TM8');
  console.error('       fs import VOLUME.TM8 hostfile /path/file');
  console.error('       fs export VOLUME.TM8 /path/file hostfile');
  console.error('       fs import-text VOLUME.TM8 hostfile /path/file');
  console.error('       fs export-text VOLUME.TM8 /path/file hostfile');
  console.error('       fs copy SOURCE.TM8:/path/file DEST.TM8:/path/file');
  console.error('       fs unpack VOLUME.TM8 folder');
  console.error('       fs pack folder VOLUME.TM8');
  console.error('       fs project-init VOLUME.TM8 [/src/main.asm]');
  console.error('       fs project-info VOLUME.TM8');
  console.error('       fs project-set-main VOLUME.TM8 /path/file');
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

function encodeSourceTextRecords(content: Buffer): Buffer {
  const text = content.toString('utf8');
  if (Buffer.from(text, 'utf8').compare(content) !== 0) {
    throw new Error('source text must be valid UTF-8');
  }
  if (text.includes('\0')) {
    throw new Error('source text cannot contain NUL bytes');
  }

  const normalized = text.replace(/\r\n/g, '\n');
  if (normalized.includes('\r')) {
    throw new Error('source text cannot contain bare carriage returns');
  }

  if (normalized === '') {
    return Buffer.alloc(0);
  }

  const lines = normalized.endsWith('\n')
    ? normalized.slice(0, -1).split('\n')
    : normalized.split('\n');

  const records = Buffer.alloc(lines.length * 32);
  for (let index = 0; index < lines.length; index += 1) {
    const line = lines[index];
    const bytes = Buffer.from(line, 'utf8');
    if (bytes.length > 31) {
      throw new Error(`source line ${index + 1} exceeds 31 bytes`);
    }
    records[index * 32] = bytes.length;
    bytes.copy(records, index * 32 + 1);
  }
  return records;
}

function decodeSourceTextRecords(records: Buffer): Buffer {
  if (records.byteLength % 32 !== 0) {
    throw new Error(`malformed source records: byte length ${records.byteLength} is not a multiple of 32`);
  }

  const lines: string[] = [];
  for (let offset = 0; offset < records.byteLength; offset += 32) {
    const length = records[offset] & 0x1f;
    for (let padding = offset + 1 + length; padding < offset + 32; padding += 1) {
      if (records[padding] !== 0) {
        throw new Error(`malformed source record ${offset / 32 + 1}: non-zero padding byte`);
      }
    }
    const text = records.subarray(offset + 1, offset + 1 + length).toString('utf8');
    if (Buffer.from(text, 'utf8').compare(records.subarray(offset + 1, offset + 1 + length)) !== 0) {
      throw new Error(`malformed source record ${offset / 32 + 1}: invalid UTF-8`);
    }
    if (text.includes('\0') || text.includes('\r') || text.includes('\n')) {
      throw new Error(`malformed source record ${offset / 32 + 1}: unsupported control character`);
    }
    lines.push(text);
  }

  return Buffer.from(lines.length === 0 ? '' : `${lines.join('\n')}\n`, 'utf8');
}

function importTextFile(volumePath: string, hostPath: string, tm8Path: string): void {
  writeFileSync(
    volumePath,
    importFileIntoVolumeImage(
      readFileSync(volumePath),
      tm8Path,
      encodeSourceTextRecords(readFileSync(hostPath)),
    ),
  );
}

function exportTextFile(volumePath: string, tm8Path: string, hostPath: string): void {
  writeNewHostFile(
    hostPath,
    decodeSourceTextRecords(readFileFromVolumeImage(readFileSync(volumePath), tm8Path)),
  );
}

const PROJECT_CONFIG_PATH = '/tecm8.prj';

type ProjectConfig = {
  mainFile: string;
};

function validateTm8FilePath(path: string): void {
  importFileIntoVolumeImage(createVolumeImage(), path, Buffer.alloc(0));
}

function defaultProjectConfig(mainFile = '/src/main.asm'): ProjectConfig {
  validateTm8FilePath(mainFile);
  return {
    mainFile,
  };
}

function fileStem(path: string): string {
  const name = path.slice(path.lastIndexOf('/') + 1);
  const extension = name.lastIndexOf('.');
  return extension > 0 ? name.slice(0, extension) : name;
}

function projectOutputFile(config: ProjectConfig): string {
  return `/build/${fileStem(config.mainFile)}.bin`;
}

function projectMapFile(config: ProjectConfig): string {
  return `/build/${fileStem(config.mainFile)}.map`;
}

function encodeProjectConfig(config: ProjectConfig): Buffer {
  return Buffer.from(
    [
      'tm8project=1',
      `main=${config.mainFile}`,
      '',
    ].join('\n'),
    'ascii',
  );
}

function decodeProjectConfig(content: Buffer): ProjectConfig {
  const text = content.toString('ascii');
  if (Buffer.from(text, 'ascii').compare(content) !== 0) {
    throw new Error('bad project config encoding');
  }

  const allowedKeys = new Set(['tm8project', 'main']);
  const values = new Map<string, string>();
  const lines = text.split('\n');
  for (const [index, rawLine] of lines.entries()) {
    if (rawLine === '') {
      if (index === lines.length - 1) {
        continue;
      }
      throw new Error(`bad project config line ${index + 1}`);
    }
    const separator = rawLine.indexOf('=');
    if (separator <= 0) {
      throw new Error(`bad project config line ${index + 1}`);
    }
    const key = rawLine.slice(0, separator);
    const value = rawLine.slice(separator + 1);
    if (!allowedKeys.has(key)) {
      throw new Error(`unknown project config key: ${key}`);
    }
    if (values.has(key)) {
      throw new Error(`duplicate project config key: ${key}`);
    }
    values.set(key, value);
  }

  if (
    values.get('tm8project') !== '1'
  ) {
    throw new Error('bad project config header');
  }

  const mainFile = values.get('main');
  if (!mainFile) {
    throw new Error('missing project config key');
  }

  validateTm8FilePath(mainFile);
  validateTm8FilePath(projectOutputFile({ mainFile }));
  validateTm8FilePath(projectMapFile({ mainFile }));
  return { mainFile };
}

function hasVolumeFile(image: Buffer, path: string): boolean {
  try {
    readFileFromVolumeImage(image, path);
    return true;
  } catch (error) {
    if (error instanceof Error && error.message.includes('file not found')) {
      return false;
    }
    throw error;
  }
}

function writeVolumeFileReplacing(image: Buffer, path: string, content: Buffer): Buffer {
  const withoutExisting = hasVolumeFile(image, path)
    ? removeFileFromVolumeImage(image, path)
    : image;
  return importFileIntoVolumeImage(withoutExisting, path, content);
}

function readProjectConfig(image: Buffer): ProjectConfig {
  return decodeProjectConfig(readFileFromVolumeImage(image, PROJECT_CONFIG_PATH));
}

function initProject(volumePath: string, mainFile = '/src/main.asm'): void {
  let image = readFileSync(volumePath);
  if (hasVolumeFile(image, PROJECT_CONFIG_PATH)) {
    throw new Error(`project config already exists: ${PROJECT_CONFIG_PATH}`);
  }

  const config = defaultProjectConfig(mainFile);
  if (!hasVolumeFile(image, config.mainFile)) {
    image = importFileIntoVolumeImage(image, config.mainFile, Buffer.alloc(0));
  }
  image = importFileIntoVolumeImage(image, PROJECT_CONFIG_PATH, encodeProjectConfig(config));
  writeFileSync(volumePath, image);
}

function printProjectInfo(volumePath: string): void {
  const config = readProjectConfig(readFileSync(volumePath));
  console.log(JSON.stringify({
    format: 'tm8project',
    version: 1,
    mainFile: config.mainFile,
    outputFile: projectOutputFile(config),
    mapFile: projectMapFile(config),
    commands: {
      edit: 'mainFile',
      asm: 'mainFile',
      run: 'outputFile',
    },
  }, null, 2));
}

function updateProjectConfig(
  volumePath: string,
  update: (config: ProjectConfig) => ProjectConfig,
): void {
  const image = readFileSync(volumePath);
  const config = update(readProjectConfig(image));
  validateTm8FilePath(config.mainFile);
  validateTm8FilePath(projectOutputFile(config));
  validateTm8FilePath(projectMapFile(config));
  writeFileSync(volumePath, writeVolumeFileReplacing(image, PROJECT_CONFIG_PATH, encodeProjectConfig(config)));
}

function setProjectMainFile(volumePath: string, mainFile: string): void {
  validateTm8FilePath(mainFile);
  updateProjectConfig(volumePath, (config) => ({ ...config, mainFile }));
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

function tm8PathForHostParts(parts: string[]): string {
  if (parts.length === 0) {
    throw new Error('cannot pack folder root as a file');
  }
  for (const part of parts) {
    if (part === '' || part === '.' || part === '..') {
      throw new Error(`cannot pack unsafe host path: ${parts.join('/')}`);
    }
  }
  return `/${parts.join('/')}`;
}

function collectHostFiles(folder: string, parts: string[] = []): Array<{ hostPath: string; tm8Path: string }> {
  const entries = (readdirSync(join(folder, ...parts), { withFileTypes: true }) as HostDirent[])
    .sort((left: HostDirent, right: HostDirent) => left.name.localeCompare(right.name));
  const files: Array<{ hostPath: string; tm8Path: string }> = [];

  for (const entry of entries) {
    const entryParts = [...parts, entry.name];
    const hostPath = join(folder, ...entryParts);
    if (entry.isSymbolicLink()) {
      throw new Error(`cannot pack symbolic link: ${hostPath}`);
    }
    if (entry.isDirectory()) {
      files.push(...collectHostFiles(folder, entryParts));
      continue;
    }
    if (!entry.isFile()) {
      throw new Error(`cannot pack non-file entry: ${hostPath}`);
    }
    files.push({ hostPath, tm8Path: tm8PathForHostParts(entryParts) });
  }

  return files;
}

function packVolume(hostFolder: string, volumePath: string): void {
  try {
    lstatSync(volumePath);
    throw new Error(`refusing to overwrite existing file: ${volumePath}`);
  } catch (error) {
    if (!(error instanceof Error && 'code' in error && error.code === 'ENOENT')) {
      throw error;
    }
  }

  const root = lstatSync(hostFolder) as HostStats;
  if (root.isSymbolicLink()) {
    throw new Error(`cannot pack symbolic link: ${hostFolder}`);
  }
  if (!root.isDirectory()) {
    throw new Error(`cannot pack non-directory root: ${hostFolder}`);
  }

  let image = createVolumeImage();
  for (const file of collectHostFiles(hostFolder)) {
    image = importFileIntoVolumeImage(image, file.tm8Path, readFileSync(file.hostPath));
  }
  try {
    writeFileSync(volumePath, image, { flag: 'wx' });
  } catch (error) {
    if (error instanceof Error && 'code' in error && error.code === 'EEXIST') {
      throw new Error(`refusing to overwrite existing file: ${volumePath}`);
    }
    throw error;
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

type CliCommand = {
  minArgs: number;
  maxArgs: number;
  run: (argv: string[]) => void;
};

const CLI_COMMANDS: Record<string, CliCommand> = {
  format: { minArgs: 2, maxArgs: 2, run: ([, path]) => formatVolumeFile(path) },
  info: { minArgs: 2, maxArgs: 2, run: ([, path]) => printInfo(path) },
  ls: { minArgs: 3, maxArgs: 3, run: ([, path, tm8Path]) => printListing(path, tm8Path) },
  new: { minArgs: 3, maxArgs: 3, run: ([, path, tm8Path]) => createNewFile(path, tm8Path) },
  import: {
    minArgs: 4,
    maxArgs: 4,
    run: ([, path, hostPath, tm8Path]) => importFile(path, hostPath, tm8Path),
  },
  export: {
    minArgs: 4,
    maxArgs: 4,
    run: ([, path, tm8Path, hostPath]) => exportFile(path, tm8Path, hostPath),
  },
  'import-text': {
    minArgs: 4,
    maxArgs: 4,
    run: ([, path, hostPath, tm8Path]) => importTextFile(path, hostPath, tm8Path),
  },
  'export-text': {
    minArgs: 4,
    maxArgs: 4,
    run: ([, path, tm8Path, hostPath]) => exportTextFile(path, tm8Path, hostPath),
  },
  copy: { minArgs: 3, maxArgs: 3, run: ([, sourceSpec, destinationSpec]) => copyFile(sourceSpec, destinationSpec) },
  unpack: { minArgs: 3, maxArgs: 3, run: ([, path, folder]) => unpackVolume(path, folder) },
  pack: { minArgs: 3, maxArgs: 3, run: ([, folder, path]) => packVolume(folder, path) },
  'project-init': { minArgs: 2, maxArgs: 3, run: ([, path, mainFile]) => initProject(path, mainFile) },
  'project-info': { minArgs: 2, maxArgs: 2, run: ([, path]) => printProjectInfo(path) },
  'project-set-main': {
    minArgs: 3,
    maxArgs: 3,
    run: ([, path, tm8Path]) => setProjectMainFile(path, tm8Path),
  },
  rm: { minArgs: 3, maxArgs: 3, run: ([, path, tm8Path]) => removeFile(path, tm8Path) },
  mv: {
    minArgs: 4,
    maxArgs: 4,
    run: ([, path, sourcePath, destinationPath]) => moveFile(path, sourcePath, destinationPath),
  },
  cat: { minArgs: 3, maxArgs: 3, run: ([, path, tm8Path]) => printFile(path, tm8Path) },
};

function main(argv: string[]): void {
  const [command] = argv;
  const cliCommand = command !== undefined ? CLI_COMMANDS[command] : undefined;
  if (!cliCommand) {
    usage();
  }
  const requiredArgs = argv.slice(0, cliCommand.minArgs);
  if (
    argv.length < cliCommand.minArgs ||
    argv.length > cliCommand.maxArgs ||
    requiredArgs.length < cliCommand.minArgs ||
    requiredArgs.some((arg) => !arg)
  ) {
    usage();
  }
  cliCommand.run(argv);
}

try {
  main(process.argv.slice(2));
} catch (error) {
  const message = error instanceof Error ? error.message : String(error);
  console.error(`error: ${message}`);
  process.exit(1);
}
