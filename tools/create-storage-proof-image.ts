#!/usr/bin/env node
/**
 * Create a minimal FAT32 SD-card image for TM8 storage proof work.
 *
 * The image contains one host-created root file:
 *
 *   VOLUME.TM8
 *
 * The file is contiguous and exactly 4 MiB. Its sectors are filled with
 * recognizable marker text so host tools can verify file-relative sectors that
 * map to the proposed TECM8 layout.
 */

const { mkdirSync, readFileSync, writeFileSync } = require('node:fs');
const { dirname } = require('node:path');

const SECTOR_SIZE = 512;
const MIB = 1024 * 1024;

const TOTAL_SECTORS = 32768;
const PARTITION_LBA = 2048;
const PARTITION_SECTORS = TOTAL_SECTORS - PARTITION_LBA;
const SECTORS_PER_CLUSTER = 8;
const RESERVED_SECTORS = 32;
const FAT_COUNT = 1;
const FAT_SIZE_SECTORS = 128;
const ROOT_CLUSTER = 2;
const VOLUME_CLUSTER = 3;
const VOLUME_SIZE = 4 * MIB;
const VOLUME_SECTORS = VOLUME_SIZE / SECTOR_SIZE;
const VOLUME_CLUSTERS = VOLUME_SIZE / (SECTORS_PER_CLUSTER * SECTOR_SIZE);
const VOLUME_LABEL = Buffer.from('TM8PROOF   ', 'ascii');
const FS_TYPE = Buffer.from('FAT32   ', 'ascii');

type Manifest = Record<string, number | string>;

function putU16(buf: Buffer, offset: number, value: number): void {
  buf.writeUInt16LE(value & 0xffff, offset);
}

function putU32(buf: Buffer, offset: number, value: number): void {
  buf.writeUInt32LE(value >>> 0, offset);
}

function dataStartLba(): number {
  return PARTITION_LBA + RESERVED_SECTORS + FAT_COUNT * FAT_SIZE_SECTORS;
}

function clusterLba(cluster: number): number {
  return dataStartLba() + (cluster - 2) * SECTORS_PER_CLUSTER;
}

function volumeStartLba(): number {
  return clusterLba(VOLUME_CLUSTER);
}

function makeMbr(): Buffer {
  const sector = Buffer.alloc(SECTOR_SIZE);
  const entry = 0x1be;
  sector[entry] = 0x80;
  sector.set(Buffer.from([0x00, 0x02, 0x00]), entry + 1);
  sector[entry + 4] = 0x0c;
  sector.set(Buffer.from([0xff, 0xff, 0xff]), entry + 5);
  putU32(sector, entry + 8, PARTITION_LBA);
  putU32(sector, entry + 12, PARTITION_SECTORS);
  sector[510] = 0x55;
  sector[511] = 0xaa;
  return sector;
}

function makeBpb(): Buffer {
  const sector = Buffer.alloc(SECTOR_SIZE);
  sector.set(Buffer.from([0xeb, 0x58, 0x90]), 0);
  sector.set(Buffer.from('TM8PROOF', 'ascii'), 3);
  putU16(sector, 0x0b, SECTOR_SIZE);
  sector[0x0d] = SECTORS_PER_CLUSTER;
  putU16(sector, 0x0e, RESERVED_SECTORS);
  sector[0x10] = FAT_COUNT;
  putU16(sector, 0x11, 0);
  putU16(sector, 0x13, 0);
  sector[0x15] = 0xf8;
  putU16(sector, 0x16, 0);
  putU16(sector, 0x18, 63);
  putU16(sector, 0x1a, 255);
  putU32(sector, 0x1c, PARTITION_LBA);
  putU32(sector, 0x20, PARTITION_SECTORS);
  putU32(sector, 0x24, FAT_SIZE_SECTORS);
  putU16(sector, 0x28, 0);
  putU16(sector, 0x2a, 0);
  putU32(sector, 0x2c, ROOT_CLUSTER);
  putU16(sector, 0x30, 1);
  putU16(sector, 0x32, 6);
  sector[0x40] = 0x80;
  sector[0x42] = 0x29;
  putU32(sector, 0x43, 0x5aadc001);
  sector.set(VOLUME_LABEL, 0x47);
  sector.set(FS_TYPE, 0x52);
  sector[510] = 0x55;
  sector[511] = 0xaa;
  return sector;
}

function makeFsInfo(): Buffer {
  const sector = Buffer.alloc(SECTOR_SIZE);
  putU32(sector, 0x000, 0x41615252);
  putU32(sector, 0x1e4, 0x61417272);
  putU32(sector, 0x1e8, 0xffffffff);
  putU32(sector, 0x1ec, 0xffffffff);
  putU32(sector, 0x1fc, 0xaa550000);
  return sector;
}

function makeFat(): Buffer {
  const fat = Buffer.alloc(FAT_SIZE_SECTORS * SECTOR_SIZE);
  putU32(fat, 0 * 4, 0x0ffffff8);
  putU32(fat, 1 * 4, 0x0fffffff);
  putU32(fat, ROOT_CLUSTER * 4, 0x0fffffff);
  const last = VOLUME_CLUSTER + VOLUME_CLUSTERS - 1;
  for (let cluster = VOLUME_CLUSTER; cluster < last; cluster += 1) {
    putU32(fat, cluster * 4, cluster + 1);
  }
  putU32(fat, last * 4, 0x0fffffff);
  return fat;
}

function makeRootDir(): Buffer {
  const cluster = Buffer.alloc(SECTORS_PER_CLUSTER * SECTOR_SIZE);
  const entry = Buffer.alloc(32);
  entry.set(Buffer.from('VOLUME  TM8', 'ascii'), 0);
  entry[11] = 0x20;
  putU16(entry, 20, (VOLUME_CLUSTER >> 16) & 0xffff);
  putU16(entry, 26, VOLUME_CLUSTER & 0xffff);
  putU32(entry, 28, VOLUME_SIZE);
  cluster.set(entry, 0);
  cluster[32] = 0x00;
  return cluster;
}

function makeVolumeSector(index: number): Buffer {
  const sector = Buffer.alloc(SECTOR_SIZE);
  const marker = Buffer.from(
    `TM8PROOF VOLUME.TM8 sector ${index.toString().padStart(8, '0')}\r\n`,
    'ascii',
  );
  sector.set(marker, 0);
  for (let i = marker.length; i < SECTOR_SIZE; i += 1) {
    sector[i] = (index + i) & 0xff;
  }
  return sector;
}

function metadata(imagePath: string): Manifest {
  const startLba = volumeStartLba();
  return {
    image: imagePath,
    image_size_bytes: TOTAL_SECTORS * SECTOR_SIZE,
    partition_lba: PARTITION_LBA,
    partition_sectors: PARTITION_SECTORS,
    fat_start_lba: PARTITION_LBA + RESERVED_SECTORS,
    fat_size_sectors: FAT_SIZE_SECTORS,
    root_dir_lba: clusterLba(ROOT_CLUSTER),
    volume_file_name: 'VOLUME.TM8',
    volume_size_bytes: VOLUME_SIZE,
    volume_start_cluster: VOLUME_CLUSTER,
    volume_start_lba: startLba,
    volume_start_byte_offset: startLba * SECTOR_SIZE,
    tm8_block_0_lba: startLba,
    tm8_block_1_lba: startLba + 8,
    tm8_catalog_first_lba: startLba + 16,
    tm8_catalog_last_lba: startLba + 79,
    tm8_data_first_lba: startLba + 80,
  };
}

function writeAt(image: Buffer, lba: number, data: Buffer): void {
  data.copy(image, lba * SECTOR_SIZE);
}

function createImage(imagePath: string): Manifest {
  const image = Buffer.alloc(TOTAL_SECTORS * SECTOR_SIZE);
  writeAt(image, 0, makeMbr());

  const bpbLba = PARTITION_LBA;
  writeAt(image, bpbLba, makeBpb());
  writeAt(image, bpbLba + 1, makeFsInfo());
  writeAt(image, bpbLba + 6, makeBpb());
  writeAt(image, bpbLba + 7, makeFsInfo());

  writeAt(image, PARTITION_LBA + RESERVED_SECTORS, makeFat());
  writeAt(image, clusterLba(ROOT_CLUSTER), makeRootDir());

  const startLba = volumeStartLba();
  for (let sectorIndex = 0; sectorIndex < VOLUME_SECTORS; sectorIndex += 1) {
    writeAt(image, startLba + sectorIndex, makeVolumeSector(sectorIndex));
  }

  mkdirSync(dirname(imagePath), { recursive: true });
  writeFileSync(imagePath, image);
  return metadata(imagePath);
}

function verifyImage(imagePath: string): Manifest {
  const data = readFileSync(imagePath);
  if (data.length !== TOTAL_SECTORS * SECTOR_SIZE) {
    throw new Error(`unexpected image size: ${data.length}`);
  }
  if (data[510] !== 0x55 || data[511] !== 0xaa) {
    throw new Error('missing MBR signature');
  }
  const partitionLba = data.readUInt32LE(0x1be + 8);
  if (partitionLba !== PARTITION_LBA) {
    throw new Error(`unexpected partition LBA: ${partitionLba}`);
  }
  const bpb = partitionLba * SECTOR_SIZE;
  if (data.readUInt16LE(bpb + 0x0b) !== SECTOR_SIZE) {
    throw new Error('BPB bytes-per-sector is not 512');
  }
  const root = clusterLba(ROOT_CLUSTER) * SECTOR_SIZE;
  if (!data.subarray(root, root + 11).equals(Buffer.from('VOLUME  TM8', 'ascii'))) {
    throw new Error('root directory does not contain VOLUME.TM8');
  }
  const start = volumeStartLba() * SECTOR_SIZE;
  const checks = [0, 8, 16, 79, 80, VOLUME_SECTORS - 1];
  for (const sectorIndex of checks) {
    const marker = Buffer.from(
      `TM8PROOF VOLUME.TM8 sector ${sectorIndex.toString().padStart(8, '0')}`,
      'ascii',
    );
    const offset = start + sectorIndex * SECTOR_SIZE;
    if (!data.subarray(offset, offset + marker.length).equals(marker)) {
      throw new Error(`missing marker at VOLUME.TM8 sector ${sectorIndex}`);
    }
  }
  return metadata(imagePath);
}

function manifestPath(imagePath: string): string {
  return imagePath.replace(/\.[^.]*$/, '') + '.json';
}

function parseArgs(argv: string[]): { imagePath: string; verifyOnly: boolean } {
  const verifyOnly = argv.includes('--verify-only');
  const imagePath =
    argv.find((arg) => arg !== '--verify-only') ?? 'proofs/storage/tm8proof-fat32.img';
  return { imagePath, verifyOnly };
}

function main(): void {
  const { imagePath, verifyOnly } = parseArgs(process.argv.slice(2));
  const info = verifyOnly ? verifyImage(imagePath) : createImage(imagePath);
  writeFileSync(manifestPath(imagePath), JSON.stringify(info, null, 2) + '\n', 'ascii');
  console.log(JSON.stringify(info, null, 2));
}

main();
