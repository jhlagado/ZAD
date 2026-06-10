#!/usr/bin/env node
/**
 * Assemble and run the storage-backed editor viewport proof in Debug80's
 * TEC-1G runtime with MON3 ROM and a FAT32-backed VOLUME.TM8 image.
 */

const { execFileSync } = require('node:child_process');
const { existsSync, readFileSync, writeFileSync } = require('node:fs');
const { resolve } = require('node:path');

const TECM8_ROOT = resolve(__dirname, '..');
const DEBUG80_ROOT = resolve(process.env.DEBUG80_ROOT ?? '/Users/johnhardy/projects/debug80');
const AZM_ROOT = resolve(process.env.AZM_ROOT ?? '/Users/johnhardy/projects/AZM');
const MON3_ROM_CANDIDATES = [
  resolve(DEBUG80_ROOT, 'resources/bundles/tec1g/mon3/v1/mon3.bin'),
  '/Users/johnhardy/projects/debug80-tec1g-mon3/roms/tec1g/mon-3/mon3.bin',
  '/Users/johnhardy/projects/2026/debug80-tec1g-mon3/roms/tec1g/mon-3/mon3.bin',
];
const MON3_ROM_PATH = resolve(
  process.env.MON3_ROM_PATH ??
    MON3_ROM_CANDIDATES.find((path: string) => existsSync(path)) ??
    MON3_ROM_CANDIDATES[0],
);

const PROOF_SOURCE = resolve(TECM8_ROOT, 'proofs/display/editor-viewport-storage-proof.asm');
const LAST_RUN = resolve(TECM8_ROOT, 'proofs/display/editor-viewport-storage-proof-last-run.json');
const IMAGE_PATH = resolve(TECM8_ROOT, 'proofs/display/editor-viewport-storage-fat32.img');
const IMAGE_TOOL = resolve(TECM8_ROOT, 'tools/create-storage-proof-image.ts');
const INTERFACES = [
  resolve(TECM8_ROOT, 'src/mon3.asmi'),
];
const NODE_TS_ARGS = ['--experimental-strip-types'];
const APP_START = 0x4000;
const PROOF_PASS = 0x42;
const SYS_CTRL = 0xff;
const SHADOW_OFF = 0x01;
const MCB = 0x0888;
const MCB_SD_CARD = 0x80;
const TM8_BLOCK_BYTES = 4096;
const TM8_ALLOCATION_OFFSET = 4096;
const TM8_ALLOCATION_END = 0xffff;
const TM8_NONCONTIGUOUS_SECOND_BLOCK = 130;

const PROOF_CASES = {
  'editor-viewport-storage-proof': {
    source: PROOF_SOURCE,
    lastRun: LAST_RUN,
    image: IMAGE_PATH,
    lines: makeMultiBlockLines(),
    verify: verifyPositiveProof,
  },
  'editor-viewport-storage-invalid-page-proof': {
    source: resolve(TECM8_ROOT, 'proofs/display/editor-viewport-storage-invalid-page-proof.asm'),
    lastRun: resolve(TECM8_ROOT, 'proofs/display/editor-viewport-storage-invalid-page-proof-last-run.json'),
    image: resolve(TECM8_ROOT, 'proofs/display/editor-viewport-storage-invalid-page-fat32.img'),
    lines: makeMultiBlockLines(),
    verify: verifyNoopProof,
  },
  'editor-viewport-storage-small-file-proof': {
    source: resolve(TECM8_ROOT, 'proofs/display/editor-viewport-storage-small-file-proof.asm'),
    lastRun: resolve(TECM8_ROOT, 'proofs/display/editor-viewport-storage-small-file-proof-last-run.json'),
    image: resolve(TECM8_ROOT, 'proofs/display/editor-viewport-storage-small-file-fat32.img'),
    lines: makeSmallFileLines(),
    verify: verifyNoopProof,
  },
  'editor-navigation-proof': {
    source: resolve(TECM8_ROOT, 'proofs/display/editor-navigation-proof.asm'),
    lastRun: resolve(TECM8_ROOT, 'proofs/display/editor-navigation-proof-last-run.json'),
    image: resolve(TECM8_ROOT, 'proofs/display/editor-navigation-fat32.img'),
    lines: makeMultiBlockLines(),
    verify: verifyNavigationProof,
  },
  'shell-edit-navigation-proof': {
    source: resolve(TECM8_ROOT, 'proofs/display/shell-edit-navigation-proof.asm'),
    lastRun: resolve(TECM8_ROOT, 'proofs/display/shell-edit-navigation-proof-last-run.json'),
    image: resolve(TECM8_ROOT, 'proofs/display/shell-edit-navigation-fat32.img'),
    lines: makeMultiBlockLines(),
    verify: verifyShellEditNavigationProof,
  },
  'shell-edit-explicit-navigation-proof': {
    source: resolve(TECM8_ROOT, 'proofs/display/shell-edit-explicit-navigation-proof.asm'),
    lastRun: resolve(TECM8_ROOT, 'proofs/display/shell-edit-explicit-navigation-proof-last-run.json'),
    image: resolve(TECM8_ROOT, 'proofs/display/shell-edit-explicit-navigation-fat32.img'),
    lines: makeMultiBlockLines(),
    verify: verifyShellEditExplicitNavigationProof,
  },
  'shell-edit-interaction-proof': {
    source: resolve(TECM8_ROOT, 'proofs/display/shell-edit-interaction-proof.asm'),
    lastRun: resolve(TECM8_ROOT, 'proofs/display/shell-edit-interaction-proof-last-run.json'),
    image: resolve(TECM8_ROOT, 'proofs/display/shell-edit-interaction-fat32.img'),
    lines: makeMultiBlockLines(),
    verify: verifyShellEditInteractionProof,
  },
  'editor-dirty-render-proof': {
    source: resolve(TECM8_ROOT, 'proofs/display/editor-dirty-render-proof.asm'),
    lastRun: resolve(TECM8_ROOT, 'proofs/display/editor-dirty-render-proof-last-run.json'),
    image: resolve(TECM8_ROOT, 'proofs/display/editor-dirty-render-fat32.img'),
    lines: makeMultiBlockLines(),
    verify: verifyEditorDirtyRenderProof,
  },
  'editor-mutation-boundary-proof': {
    source: resolve(TECM8_ROOT, 'proofs/display/editor-mutation-boundary-proof.asm'),
    lastRun: resolve(TECM8_ROOT, 'proofs/display/editor-mutation-boundary-proof-last-run.json'),
    image: resolve(TECM8_ROOT, 'proofs/display/editor-mutation-boundary-fat32.img'),
    lines: makeSmallFileLines(),
    verify: verifyEditorMutationBoundaryProof,
  },
  'editor-cross-page-join-proof': {
    source: resolve(TECM8_ROOT, 'proofs/display/editor-cross-page-join-proof.asm'),
    lastRun: resolve(TECM8_ROOT, 'proofs/display/editor-cross-page-join-proof-last-run.json'),
    image: resolve(TECM8_ROOT, 'proofs/display/editor-cross-page-join-fat32.img'),
    lines: makeSmallFileLines(),
    verify: verifyEditorCrossPageJoinProof,
  },
  'editor-window-save-proof': {
    source: resolve(TECM8_ROOT, 'proofs/display/editor-window-save-proof.asm'),
    lastRun: resolve(TECM8_ROOT, 'proofs/display/editor-window-save-proof-last-run.json'),
    image: resolve(TECM8_ROOT, 'proofs/display/editor-window-save-fat32.img'),
    lines: makeWindowSaveLines(),
    verify: verifyEditorWindowSaveProof,
  },
  'editor-line-editing-proof': {
    source: resolve(TECM8_ROOT, 'proofs/display/editor-line-editing-proof.asm'),
    lastRun: resolve(TECM8_ROOT, 'proofs/display/editor-line-editing-proof-last-run.json'),
    image: resolve(TECM8_ROOT, 'proofs/display/editor-line-editing-fat32.img'),
    lines: makeSmallFileLines(),
    verify: verifyEditorLineEditingProof,
  },
  'editor-page-write-proof': {
    source: resolve(TECM8_ROOT, 'proofs/display/editor-page-write-proof.asm'),
    lastRun: resolve(TECM8_ROOT, 'proofs/display/editor-page-write-proof-last-run.json'),
    image: resolve(TECM8_ROOT, 'proofs/display/editor-page-write-fat32.img'),
    lines: makeSmallFileLines(),
    verify: verifyEditorPageWriteProof,
  },
} as const;

type ProofCaseName = keyof typeof PROOF_CASES;
type ProofCase = (typeof PROOF_CASES)[ProofCaseName];

type Runtime = {
  cpu: { pc: number; sp: number; halted: boolean };
  hardware: {
    memory: Uint8Array;
    memRead?: (addr: number) => number;
    memWrite?: (addr: number, value: number) => void;
    forceMemWrite?: (addr: number, value: number) => void;
    isMemoryWritable?: (addr: number) => boolean;
  };
  step: () => { halted: boolean; pc: number; cycles?: number };
};

type PlatformRuntime = {
  recordCycles: (cycles: number) => void;
  state: { display?: { glcdCtrl?: { glcd?: number[] | Uint8Array } } };
};

type D8Symbol = {
  name: string;
  kind: string;
  address?: number;
  value?: number;
};

type CompileResult = {
  diagnostics: Array<{ id?: string; message?: string; severity?: string }>;
  artifacts: Array<{ kind: string; bytes?: Uint8Array; json?: { symbols?: D8Symbol[] } }>;
};

function requireFromDebug80(modulePath: string): unknown {
  return require(resolve(DEBUG80_ROOT, modulePath));
}

async function compileProof(proofCase: ProofCase): Promise<{ bytes: Uint8Array; symbols: D8Symbol[] }> {
  const { compile, defaultFormatWriters } = await import(resolve(AZM_ROOT, 'dist/src/api-compile.js'));
  const result = await compile(
    proofCase.source,
    {
      emitBin: true,
      emitD8m: true,
      outputType: 'bin',
      sourceRoot: TECM8_ROOT,
      d8mInputs: { bin: 'build/editor-viewport-storage-proof.bin' },
      registerCare: 'strict',
      registerCareProfile: 'mon3',
      registerCareInterfaces: INTERFACES,
    },
    { formats: defaultFormatWriters },
  ) as CompileResult;

  if (result.diagnostics.length > 0) {
    throw new Error(`AZM diagnostics:\n${JSON.stringify(result.diagnostics, null, 2)}`);
  }

  const bin = result.artifacts.find((artifact) => artifact.kind === 'bin');
  const d8m = result.artifacts.find((artifact) => artifact.kind === 'd8m');
  if (!bin?.bytes) {
    throw new Error('AZM did not emit bin artifact');
  }
  return { bytes: bin.bytes, symbols: d8m?.json?.symbols ?? [] };
}

function symbolAddress(symbols: D8Symbol[], name: string): number {
  const symbol = symbols.find((entry) => entry.name === name);
  const address = symbol?.address ?? symbol?.value;
  if (typeof address !== 'number') {
    throw new Error(`missing address symbol: ${name}`);
  }
  return address;
}

function makeMultiBlockLines(): string[] {
  return Array.from({ length: 144 }, (_, index) => {
    const page = Math.floor(index / 16);
    const line = index % 16;
    return `P${page} LINE ${line.toString().padStart(2, '0')}`;
  });
}

function makeSmallFileLines(): string[] {
  return [
    'SMALL 00',
    'SMALL 01',
    'SMALL 02',
    'SMALL 03',
    'SMALL 04',
    'SMALL 05',
    'SMALL 06',
    'SMALL 07',
  ];
}

function makeWindowSaveLines(): string[] {
  return Array.from({ length: 24 }, (_, index) => {
    const page = Math.floor(index / 16);
    const line = index % 16;
    return `P${page} LINE ${line.toString().padStart(2, '0')}`;
  });
}

function makeAppLines(): string[] {
  return Array.from({ length: 32 }, (_, index) => {
    const page = Math.floor(index / 16);
    const line = index % 16;
    return `A${page} LINE ${line.toString().padStart(2, '0')}`;
  });
}

function makeRootLines(): string[] {
  return Array.from({ length: 16 }, (_, index) => {
    return `R0 LINE ${index.toString().padStart(2, '0')}`;
  });
}

function encodeSourceRecords(lines: string[]): Buffer {
  const records = Buffer.alloc(lines.length * 32);
  lines.forEach((line, index) => {
    const bytes = Buffer.from(line, 'ascii');
    if (bytes.length > 31) {
      throw new Error(`line too long: ${line}`);
    }
    records[index * 32] = bytes.length;
    bytes.copy(records, index * 32 + 1);
  });
  return records;
}

function makePositiveProofVolume(volume: Buffer): Buffer {
  const { parseVolumeImage } = require(resolve(TECM8_ROOT, 'tools/tm8/format.ts'));
  const parsed = parseVolumeImage(volume);
  const source = parsed.files.find((file: { prefixId: number; name: string }) => file.name === 'main.asm');
  if (!source) {
    throw new Error('generated source file is missing from TM8 volume');
  }

  const firstBlock = source.firstBlock;
  const secondBlock = parsed.allocation[firstBlock];
  if (secondBlock === TM8_ALLOCATION_END) {
    throw new Error('positive storage proof fixture did not allocate a second block');
  }
  if (firstBlock === TM8_NONCONTIGUOUS_SECOND_BLOCK || secondBlock === TM8_NONCONTIGUOUS_SECOND_BLOCK) {
    throw new Error('positive storage proof fixture already uses the non-contiguous target block');
  }
  if (parsed.allocation[TM8_NONCONTIGUOUS_SECOND_BLOCK] !== 0) {
    throw new Error('positive storage proof non-contiguous target block is not free');
  }

  const nextVolume = Buffer.from(volume);
  nextVolume.copy(
    nextVolume,
    TM8_NONCONTIGUOUS_SECOND_BLOCK * TM8_BLOCK_BYTES,
    secondBlock * TM8_BLOCK_BYTES,
    (secondBlock + 1) * TM8_BLOCK_BYTES,
  );
  nextVolume.fill(0, secondBlock * TM8_BLOCK_BYTES, (secondBlock + 1) * TM8_BLOCK_BYTES);
  nextVolume.writeUInt16LE(TM8_NONCONTIGUOUS_SECOND_BLOCK, TM8_ALLOCATION_OFFSET + firstBlock * 2);
  nextVolume.writeUInt16LE(0, TM8_ALLOCATION_OFFSET + secondBlock * 2);
  nextVolume.writeUInt16LE(TM8_ALLOCATION_END, TM8_ALLOCATION_OFFSET + TM8_NONCONTIGUOUS_SECOND_BLOCK * 2);

  parseVolumeImage(nextVolume);
  return nextVolume;
}

function ensureImage(proofCase: ProofCase): string {
  execFileSync(process.execPath, [...NODE_TS_ARGS, IMAGE_TOOL, proofCase.image], {
    cwd: TECM8_ROOT,
    stdio: 'ignore',
  });

  const { createVolumeImage, importFileIntoVolumeImage, readFileFromVolumeImage } =
    require(resolve(TECM8_ROOT, 'tools/tm8/format.ts'));
  const manifest = JSON.parse(readFileSync(proofCase.image.replace(/\.[^.]*$/, '.json'), 'utf8'));
  const sourceRecords = encodeSourceRecords(proofCase.lines);
  const appRecords = encodeSourceRecords(makeAppLines());
  const rootRecords = encodeSourceRecords(makeRootLines());
  let volume = createVolumeImage() as Buffer;
  volume = importFileIntoVolumeImage(volume, '/src/main.asm', sourceRecords);
  volume = importFileIntoVolumeImage(volume, '/projects/demo/app.asm', appRecords);
  volume = importFileIntoVolumeImage(volume, '/root.asm', rootRecords);
  if (proofCase === PROOF_CASES['editor-viewport-storage-proof']) {
    volume = makePositiveProofVolume(volume);
  }

  const stored = readFileFromVolumeImage(volume, '/src/main.asm') as Buffer;
  if (!stored.equals(sourceRecords)) {
    throw new Error('generated source records were not stored exactly');
  }
  const storedApp = readFileFromVolumeImage(volume, '/projects/demo/app.asm') as Buffer;
  if (!storedApp.equals(appRecords)) {
    throw new Error('generated app source records were not stored exactly');
  }
  const storedRoot = readFileFromVolumeImage(volume, '/root.asm') as Buffer;
  if (!storedRoot.equals(rootRecords)) {
    throw new Error('generated root source records were not stored exactly');
  }

  const image = Buffer.from(readFileSync(proofCase.image));
  volume.copy(image, manifest.volume_start_byte_offset);
  writeFileSync(proofCase.image, image);
  return proofCase.image;
}

function makeConfig(imagePath: string) {
  return {
    regions: [
      { start: 0x0000, end: 0x07ff, kind: 'rom' },
      { start: 0x0800, end: 0x7fff, kind: 'ram' },
      { start: 0xc000, end: 0xffff, kind: 'rom' },
    ],
    romRanges: [
      { start: 0x0000, end: 0x07ff },
      { start: 0xc000, end: 0xffff },
    ],
    appStart: APP_START,
    entry: APP_START,
    updateMs: 100,
    yieldMs: 0,
    gimpSignal: false,
    expansionBankHi: false,
    matrixMode: false,
    protectOnReset: false,
    rtcEnabled: false,
    sdEnabled: true,
    sdHighCapacity: true,
    sdImagePath: imagePath,
  };
}

function loadRuntime(bytes: Uint8Array, imagePath: string): { runtime: Runtime; platformRuntime: PlatformRuntime } {
  const { createTec1gRuntime } = requireFromDebug80('out/platforms/tec1g/runtime.js') as {
    createTec1gRuntime: Function;
  };
  const { createTec1gMemoryHooks } = requireFromDebug80(
    'out/platforms/tec1g/tec1g-memory.js',
  ) as { createTec1gMemoryHooks: Function };
  const { createZ80Runtime } = requireFromDebug80('out/z80/runtime.js') as {
    createZ80Runtime: Function;
  };

  const config = makeConfig(imagePath);
  const tec1gRuntime = createTec1gRuntime(config, () => {});
  const memory = new Uint8Array(0x10000);
  const rom = readFileSync(MON3_ROM_PATH);
  memory.set(rom.subarray(0, 0x4000), 0xc000);
  memory.set(bytes, APP_START);

  const runtime = createZ80Runtime({ memory, startAddress: APP_START }, APP_START, tec1gRuntime.ioHandlers, {
    romRanges: config.romRanges,
  }) as Runtime;

  const hooks = createTec1gMemoryHooks(
    runtime.hardware.memory,
    config.romRanges,
    tec1gRuntime.state.system,
  );
  runtime.hardware.memRead = hooks.memRead;
  runtime.hardware.memWrite = hooks.memWrite;
  runtime.hardware.forceMemWrite = hooks.forceMemWrite;
  runtime.hardware.isMemoryWritable = hooks.isMemoryWritable;

  tec1gRuntime.ioHandlers.write?.(SYS_CTRL, SHADOW_OFF);
  runtime.hardware.memory.set(runtime.hardware.memory.subarray(0xc000, 0xc100), 0x0000);
  runtime.hardware.forceMemWrite?.(MCB, MCB_SD_CARD);
  runtime.cpu.sp = 0x7ff0;
  runtime.cpu.pc = APP_START;
  return { runtime, platformRuntime: tec1gRuntime };
}

function runUntil(runtime: Runtime, platformRuntime: PlatformRuntime, doneAddr: number): number {
  const maxInstructions = 80_000_000;
  for (let i = 0; i < maxInstructions; i += 1) {
    if ((runtime.cpu.pc & 0xffff) === doneAddr) {
      return i;
    }
    const result = runtime.step();
    platformRuntime.recordCycles(result.cycles ?? 0);
  }
  throw new Error(`proof did not reach done at 0x${doneAddr.toString(16)}; pc=0x${runtime.cpu.pc.toString(16)}`);
}

function resultToString(value: number): string {
  return `0x${value.toString(16).padStart(2, '0')}`;
}

function readCString(memory: Uint8Array, address: number): string {
  const bytes = [];
  for (let current = address; current < memory.length; current += 1) {
    const value = memory[current];
    if (value === 0) {
      return Buffer.from(bytes).toString('ascii');
    }
    bytes.push(value);
  }
  throw new Error(`unterminated string at 0x${address.toString(16)}`);
}

function readWord(memory: Uint8Array, address: number): number {
  return memory[address] | (memory[(address + 1) & 0xffff] << 8);
}

function readSourceRecord(memory: Uint8Array, address: number, record: number): string {
  const start = address + record * 32;
  const length = memory[start] & 0x1f;
  return Buffer.from(memory.subarray(start + 1, start + 1 + length)).toString('ascii');
}

function assertSourceRecordClean(memory: Uint8Array, address: number, record: number, text: string): void {
  const start = address + record * 32;
  const length = memory[start] & 0x1f;
  const actual = Buffer.from(memory.subarray(start + 1, start + 1 + length)).toString('ascii');
  if (actual !== text) {
    throw new Error(`source record ${record} "${actual}", expected "${text}"`);
  }
  for (let offset = 1 + length; offset < 32; offset += 1) {
    const value = memory[start + offset];
    if (value !== 0) {
      throw new Error(`source record ${record} padding offset ${offset} is ${resultToString(value)}, expected 0x00`);
    }
  }
}

function readFileFromProofImage(proofCase: ProofCase, tm8Path: string): Buffer {
  const { readFileFromVolumeImage } = require(resolve(TECM8_ROOT, 'tools/tm8/format.ts'));
  const manifest = JSON.parse(readFileSync(proofCase.image.replace(/\.[^.]*$/, '.json'), 'utf8'));
  const image = readFileSync(proofCase.image);
  const volume = image.subarray(manifest.volume_start_byte_offset, manifest.volume_start_byte_offset + 4 * 1024 * 1024);
  return readFileFromVolumeImage(Buffer.from(volume), tm8Path) as Buffer;
}

function getGlcdBytes(platformRuntime: PlatformRuntime): number[] {
  return Array.from(platformRuntime.state.display?.glcdCtrl?.glcd ?? []);
}

const DISPLAY_Y_ORIGIN = 2;

function glcdRowHasPixels(glcd: number[], displayRow: number): boolean {
  const firstPixelRow = displayRow * 6 + DISPLAY_Y_ORIGIN;
  for (let y = firstPixelRow; y < firstPixelRow + 6; y += 1) {
    const start = y * 16;
    const end = start + 16;
    if (glcd.slice(start, end).some((value) => value !== 0)) {
      return true;
    }
  }
  return false;
}

function verifyNoopProof(): void {}

function verifyPositiveProof(runtime: Runtime, platformRuntime: PlatformRuntime, symbols: D8Symbol[]): void {
  const expectedRows = [
    { symbol: 'EditorRowText0', text: 'P8 LINE 00' },
    { symbol: 'EditorRowText1', text: 'P8 LINE 01' },
    { symbol: 'EditorRowText7', text: 'P8 LINE 07' },
    { symbol: 'EditorRowText9', text: 'P8 LINE 09' },
  ];
  for (const row of expectedRows) {
    const actual = readCString(runtime.hardware.memory, symbolAddress(symbols, row.symbol));
    if (actual !== row.text) {
      throw new Error(`storage viewport copied ${row.symbol} as "${actual}", expected "${row.text}"`);
    }
  }

  const page0 = symbolAddress(symbols, 'EditorSourcePage0');
  const page1 = symbolAddress(symbols, 'EditorSourcePage1');
  const page8 = symbolAddress(symbols, 'EditorSourcePage8');
  const expectedLoadedRecords = [
    { address: page0, record: 0, text: 'P0 LINE 00' },
    { address: page0, record: 15, text: 'P0 LINE 15' },
    { address: page1, record: 0, text: 'P1 LINE 00' },
    { address: page1, record: 15, text: 'P1 LINE 15' },
    { address: page8, record: 0, text: 'P8 LINE 00' },
    { address: page8, record: 15, text: 'P8 LINE 15' },
  ];
  for (const expected of expectedLoadedRecords) {
    const actual = readSourceRecord(runtime.hardware.memory, expected.address, expected.record);
    if (actual !== expected.text) {
      throw new Error(`storage viewport loaded record as "${actual}", expected "${expected.text}"`);
    }
  }

  const glcd = getGlcdBytes(platformRuntime);
  for (let row = 0; row < 10; row += 1) {
    if (!glcdRowHasPixels(glcd, row)) {
      throw new Error(`storage viewport proof did not render display row: ${row}`);
    }
  }
}

function verifyNavigationProof(runtime: Runtime, platformRuntime: PlatformRuntime, symbols: D8Symbol[]): void {
  const currentPage = symbolAddress(symbols, 'EditorNavCurrentPage');
  if (runtime.hardware.memory[currentPage] !== 8) {
    throw new Error(
      `editor navigation current page ${runtime.hardware.memory[currentPage]}, expected 8 after dirty RAM-window page movement`,
    );
  }
  const dirty = symbolAddress(symbols, 'EditorNavDirty');
  if (runtime.hardware.memory[dirty] !== 1) {
    throw new Error(`editor navigation dirty flag ${runtime.hardware.memory[dirty]}, expected 1`);
  }
  const cacheHits = symbolAddress(symbols, 'EditorNavCacheHitCount');
  if (runtime.hardware.memory[cacheHits] === 0) {
    throw new Error('editor navigation did not use the RAM page cache for back navigation');
  }

  const expectedRows = [
    { symbol: 'EditorRowText0', text: 'P8 LINE 00' },
    { symbol: 'EditorRowText1', text: 'P8 LINE 01' },
    { symbol: 'EditorRowText7', text: 'P8 LINE 07' },
    { symbol: 'EditorRowText9', text: 'P8 LINE 09' },
  ];
  for (const row of expectedRows) {
    const actual = readCString(runtime.hardware.memory, symbolAddress(symbols, row.symbol));
    if (actual !== row.text) {
      const cachedPage = symbolAddress(symbols, 'EditorNavCachedPage');
      const cacheValid = symbolAddress(symbols, 'EditorNavCacheValid');
      const cacheStores = symbolAddress(symbols, 'EditorNavCacheStoreCount');
      const pageBuffer = symbolAddress(symbols, 'EditorNavPageBuffer');
      const cacheBuffer = symbolAddress(symbols, 'EditorNavCachePageBuffer');
      const pageRecord = Array.from(runtime.hardware.memory.slice(pageBuffer, pageBuffer + 12))
        .map((value) => value.toString(16).padStart(2, '0'))
        .join(' ');
      const cacheRecord = Array.from(runtime.hardware.memory.slice(cacheBuffer, cacheBuffer + 12))
        .map((value) => value.toString(16).padStart(2, '0'))
        .join(' ');
      throw new Error(
        `editor navigation copied ${row.symbol} as "${actual}", expected "${row.text}"; cache page=${runtime.hardware.memory[cachedPage]} valid=${runtime.hardware.memory[cacheValid]} hits=${runtime.hardware.memory[cacheHits]} stores=${runtime.hardware.memory[cacheStores]} pageBuffer=0x${pageBuffer.toString(16)} [${pageRecord}] cacheBuffer=0x${cacheBuffer.toString(16)} [${cacheRecord}]`,
      );
    }
  }

  const glcd = getGlcdBytes(platformRuntime);
  for (let row = 0; row < 10; row += 1) {
    if (!glcdRowHasPixels(glcd, row)) {
      throw new Error(`editor navigation proof did not render display row: ${row}`);
    }
  }
}

function verifyShellEditNavigationProof(runtime: Runtime, platformRuntime: PlatformRuntime, symbols: D8Symbol[]): void {
  verifyShellEditLaunchProof(runtime, platformRuntime, symbols, 0x18, '/projects/demo/app.asm', 'A0');
}

function verifyShellEditExplicitNavigationProof(
  runtime: Runtime,
  platformRuntime: PlatformRuntime,
  symbols: D8Symbol[],
): void {
  verifyShellEditLaunchProof(runtime, platformRuntime, symbols, 0x19, '/root.asm', 'R0');
}

function verifyShellEditInteractionProof(runtime: Runtime, platformRuntime: PlatformRuntime, symbols: D8Symbol[]): void {
  verifyShellEditLaunchProof(runtime, platformRuntime, symbols, 0x18, '/projects/demo/app.asm', 'A1', 1, [
    { symbol: 'EditorRowText0', text: 'A1 LINE 00' },
    { symbol: 'EditorRowText1', text: 'A1 LINE 01' },
    { symbol: 'EditorRowText7', text: 'dl?1 LINE 07' },
    { symbol: 'EditorRowText9', text: 'A1 LINE 09' },
  ]);
  const cursorRow = symbolAddress(symbols, 'EditorCursorRow');
  const cursorCol = symbolAddress(symbols, 'EditorCursorCol');
  if (runtime.hardware.memory[cursorRow] !== 7) {
    throw new Error(`shell edit cursor row ${runtime.hardware.memory[cursorRow]}, expected 7`);
  }
  if (runtime.hardware.memory[cursorCol] !== 3) {
    throw new Error(`shell edit cursor col ${runtime.hardware.memory[cursorCol]}, expected 3`);
  }
  const pageBuffer = symbolAddress(symbols, 'EditorNavPageBuffer');
  const mutatedRecord = readSourceRecord(runtime.hardware.memory, pageBuffer, 7);
  if (mutatedRecord !== 'dl?1 LINE 07') {
    throw new Error(`shell edit mutated record "${mutatedRecord}", expected "dl?1 LINE 07"`);
  }
  const unknownModifiedDirty = runtime.hardware.memory[symbolAddress(symbols, 'UnknownModifiedDirty')];
  if (unknownModifiedDirty !== 0) {
    throw new Error(`shell edit unknown modified dirty ${unknownModifiedDirty}, expected 0`);
  }
  verifyShellEditVisibleCursor(runtime, platformRuntime);
}

function verifyEditorDirtyRenderProof(runtime: Runtime, _platformRuntime: PlatformRuntime, symbols: D8Symbol[]): void {
  const expectedCounts = [
    { symbol: 'MoveScreenCount', expected: 0 },
    { symbol: 'MovePageCount', expected: 0 },
    { symbol: 'MoveRowCount', expected: 4 },
    { symbol: 'InsertScreenCount', expected: 0 },
    { symbol: 'InsertPageCount', expected: 0 },
    { symbol: 'InsertRowCount', expected: 1 },
  ];
  for (const count of expectedCounts) {
    const value = runtime.hardware.memory[symbolAddress(symbols, count.symbol)];
    if (value !== count.expected) {
      throw new Error(`editor dirty render ${count.symbol} ${value}, expected ${count.expected}`);
    }
  }

  const pageBuffer = symbolAddress(symbols, 'EditorNavPageBuffer');
  const record = readSourceRecord(runtime.hardware.memory, pageBuffer, 0);
  if (record !== 'PZ0 LINE 00') {
    throw new Error(`editor dirty render inserted record "${record}", expected "PZ0 LINE 00"`);
  }
}

function verifyEditorMutationBoundaryProof(runtime: Runtime, _platformRuntime: PlatformRuntime, symbols: D8Symbol[]): void {
  const pageBuffer = symbolAddress(symbols, 'EditorNavPageBuffer');
  const expectedRecords = [
    { record: 0, text: 'Z' },
    { record: 1, text: 'ABCDEFGHIJKLMNOPQRSTUVWXYZ12345' },
    { record: 2, text: 'ABCDE' },
    { record: 3, text: 'ABDE' },
    { record: 4, text: 'XYZ!' },
    { record: 5, text: 'dl' },
    { record: 14, text: 'LE' },
    { record: 15, text: 'FT' },
  ];
  for (const expected of expectedRecords) {
    const actual = readSourceRecord(runtime.hardware.memory, pageBuffer, expected.record);
    if (actual !== expected.text) {
      throw new Error(
        `editor mutation boundary record ${expected.record} "${actual}", expected "${expected.text}"`,
      );
    }
  }

  const expectedCursors = [
    { symbol: 'BoundaryCursorCase1', row: 0, col: 0 },
    { symbol: 'BoundaryCursorCase2', row: 0, col: 0 },
    { symbol: 'BoundaryCursorCase3', row: 0, col: 1 },
    { symbol: 'BoundaryCursorCase4', row: 1, col: 0 },
    { symbol: 'BoundaryCursorCase5', row: 2, col: 0 },
    { symbol: 'BoundaryCursorCase6', row: 2, col: 5 },
    { symbol: 'BoundaryCursorCase7', row: 3, col: 2 },
    { symbol: 'BoundaryCursorCase8', row: 4, col: 4 },
    { symbol: 'BoundaryCursorCase9', row: 5, col: 2 },
    { symbol: 'BoundaryCursorCase10', row: 15, col: 0 },
  ];
  for (const expected of expectedCursors) {
    const address = symbolAddress(symbols, expected.symbol);
    const row = runtime.hardware.memory[address];
    const col = runtime.hardware.memory[address + 1];
    if (row !== expected.row || col !== expected.col) {
      throw new Error(
        `editor mutation boundary ${expected.symbol} cursor ${row},${col}; expected ${expected.row},${expected.col}`,
      );
    }
  }

  const cursorRow = symbolAddress(symbols, 'EditorCursorRow');
  const cursorCol = symbolAddress(symbols, 'EditorCursorCol');
  if (runtime.hardware.memory[cursorRow] !== 15) {
    throw new Error(`editor mutation boundary cursor row ${runtime.hardware.memory[cursorRow]}, expected 15`);
  }
  if (runtime.hardware.memory[cursorCol] !== 0) {
    throw new Error(`editor mutation boundary cursor col ${runtime.hardware.memory[cursorCol]}, expected 0`);
  }

  const nextPageBuffer = symbolAddress(symbols, 'EditorNavNextPageBuffer');
  const pushed = readSourceRecord(runtime.hardware.memory, nextPageBuffer, 0);
  if (pushed !== 'PUSH') {
    throw new Error(`editor mutation boundary next sector record 0 "${pushed}", expected "PUSH"`);
  }
  const dirtySectors = runtime.hardware.memory[symbolAddress(symbols, 'EditorNavDirtySectors')];
  if ((dirtySectors & 3) !== 3) {
    throw new Error(`editor mutation boundary dirty sectors ${dirtySectors}, expected bits 0 and 1 set`);
  }

  const expectedLengthBytes = [
    { record: 1, expected: 0x7f },
    { record: 2, expected: 0xe5 },
    { record: 3, expected: 0xa4 },
    { record: 4, expected: 0x64 },
    { record: 5, expected: 0x82 },
  ];
  for (const check of expectedLengthBytes) {
    const value = runtime.hardware.memory[pageBuffer + check.record * 32];
    if (value !== check.expected) {
      throw new Error(
        `editor mutation boundary record ${check.record} length byte 0x${value.toString(16)}, expected 0x${check.expected.toString(16)}`,
      );
    }
  }
}

function verifyEditorCrossPageJoinProof(runtime: Runtime, _platformRuntime: PlatformRuntime, symbols: D8Symbol[]): void {
  const pageBuffer = symbolAddress(symbols, 'EditorNavPageBuffer');
  const nextPageBuffer = symbolAddress(symbols, 'EditorNavNextPageBuffer');

  assertSourceRecordClean(runtime.hardware.memory, pageBuffer, 15, 'PREVCUR');
  assertSourceRecordClean(runtime.hardware.memory, nextPageBuffer, 0, 'NEXT');
  assertSourceRecordClean(runtime.hardware.memory, nextPageBuffer, 15, '');

  const currentPage = runtime.hardware.memory[symbolAddress(symbols, 'EditorNavCurrentPage')];
  if (currentPage !== 0) {
    throw new Error(`editor cross-page join current page ${currentPage}, expected 0`);
  }
  const cursorRow = runtime.hardware.memory[symbolAddress(symbols, 'EditorCursorRow')];
  const cursorCol = runtime.hardware.memory[symbolAddress(symbols, 'EditorCursorCol')];
  if (cursorRow !== 15 || cursorCol !== 4) {
    throw new Error(`editor cross-page join cursor ${cursorRow},${cursorCol}; expected 15,4`);
  }
  const dirtySectors = runtime.hardware.memory[symbolAddress(symbols, 'EditorNavDirtySectors')];
  if ((dirtySectors & 3) !== 3) {
    throw new Error(`editor cross-page join dirty sectors ${dirtySectors}, expected bits 0 and 1 set`);
  }
  const aggregateDirty = runtime.hardware.memory[symbolAddress(symbols, 'EditorNavDirty')];
  if (aggregateDirty !== 1) {
    throw new Error(`editor cross-page join aggregate dirty ${aggregateDirty}, expected 1`);
  }
  const cacheValid = runtime.hardware.memory[symbolAddress(symbols, 'EditorNavCacheValid')];
  if (cacheValid !== 0) {
    throw new Error(`editor cross-page join cache valid ${cacheValid}, expected 0`);
  }
  const nextValid = runtime.hardware.memory[symbolAddress(symbols, 'EditorNavNextPageValid')];
  if (nextValid !== 1) {
    throw new Error(`editor cross-page join next-page valid ${nextValid}, expected 1`);
  }
}

function verifyEditorWindowSaveProof(runtime: Runtime, _platformRuntime: PlatformRuntime, symbols: D8Symbol[]): void {
  const dirty = runtime.hardware.memory[symbolAddress(symbols, 'EditorNavDirty')];
  if (dirty !== 0) {
    throw new Error(`editor window save dirty ${dirty}, expected 0`);
  }
  const dirtySectors = runtime.hardware.memory[symbolAddress(symbols, 'EditorNavDirtySectors')];
  if (dirtySectors !== 0) {
    throw new Error(`editor window save dirty sectors ${dirtySectors}, expected 0`);
  }
  const stored = readFileFromProofImage(PROOF_CASES['editor-window-save-proof'], '/src/main.asm');
  const expected = [
    { record: 0, text: 'ZP0 LINE 00' },
    { record: 14, text: 'LE' },
    { record: 15, text: 'FT' },
    { record: 16, text: 'PUSH' },
    { record: 17, text: 'P1 LINE 00' },
  ];
  for (const check of expected) {
    const actual = readSourceRecord(stored, 0, check.record);
    if (actual !== check.text) {
      const pageBuffer = symbolAddress(symbols, 'EditorNavPageBuffer');
      const nextPageBuffer = symbolAddress(symbols, 'EditorNavNextPageBuffer');
      const runtimePage = readSourceRecord(runtime.hardware.memory, pageBuffer, check.record % 16);
      const runtimeNext = check.record >= 16
        ? readSourceRecord(runtime.hardware.memory, nextPageBuffer, check.record - 16)
        : '';
      throw new Error(
        `editor window save persisted record ${check.record} "${actual}", expected "${check.text}"; runtimePage="${runtimePage}" runtimeNext="${runtimeNext}"`,
      );
    }
  }
}

function verifyEditorLineEditingProof(runtime: Runtime, _platformRuntime: PlatformRuntime, symbols: D8Symbol[]): void {
  const pageBuffer = symbolAddress(symbols, 'EditorNavPageBuffer');
  const expectedRecords = [
    { record: 0, text: 'HELLO' },
    { record: 1, text: 'NE' },
    { record: 2, text: 'XT' },
    { record: 3, text: 'END' },
    { record: 4, text: 'TAIL' },
    { record: 5, text: '' },
    { record: 6, text: '' },
    { record: 7, text: 'ABCDEFGHIJKLMNOPQRSTUVWXYZ12345' },
    { record: 8, text: 'X' },
    { record: 9, text: 'AFTER' },
    { record: 10, text: '' },
    { record: 11, text: '' },
    { record: 12, text: '' },
    { record: 13, text: '' },
    { record: 14, text: '' },
    { record: 15, text: 'LAST' },
  ];
  for (const expected of expectedRecords) {
    assertSourceRecordClean(runtime.hardware.memory, pageBuffer, expected.record, expected.text);
  }

  const expectedCursors = [
    { symbol: 'LineEditCursorCase1', row: 1, col: 0 },
    { symbol: 'LineEditCursorCase2', row: 0, col: 2 },
    { symbol: 'LineEditCursorCase3', row: 3, col: 0 },
    { symbol: 'LineEditCursorCase4', row: 3, col: 0 },
    { symbol: 'LineEditCursorCase5', row: 7, col: 0 },
    { symbol: 'LineEditCursorCase6', row: 15, col: 2 },
    { symbol: 'LineEditCursorCase7', row: 2, col: 0 },
    { symbol: 'LineEditCursorCase8', row: 1, col: 1 },
    { symbol: 'LineEditCursorCase9', row: 0, col: 0 },
    { symbol: 'LineEditCursorCase10', row: 15, col: 0 },
  ];
  for (const expected of expectedCursors) {
    const address = symbolAddress(symbols, expected.symbol);
    const row = runtime.hardware.memory[address];
    const col = runtime.hardware.memory[address + 1];
    if (row !== expected.row || col !== expected.col) {
      throw new Error(`editor line ${expected.symbol} cursor ${row},${col}; expected ${expected.row},${expected.col}`);
    }
  }

  for (const symbol of ['LineEditResultCase6', 'LineEditResultCase9', 'LineEditResultCase10']) {
    const value = runtime.hardware.memory[symbolAddress(symbols, symbol)];
    if (value !== 0) {
      throw new Error(`editor line ${symbol} result ${value}; expected 0 for no-op`);
    }
  }
}

function verifyEditorPageWriteProof(runtime: Runtime, _platformRuntime: PlatformRuntime, symbols: D8Symbol[]): void {
  const pageBuffer = symbolAddress(symbols, 'EditorNavPageBuffer');
  assertSourceRecordClean(runtime.hardware.memory, pageBuffer, 0, 'SMALL 00');
  assertSourceRecordClean(runtime.hardware.memory, pageBuffer, 1, 'SMALL 01');

  for (const symbol of ['DirtyAfterNoopDelete', 'DirtyAfterNoopSplit', 'DirtyAfterNoopInsert']) {
    const value = runtime.hardware.memory[symbolAddress(symbols, symbol)];
    if (value !== 0) {
      throw new Error(`editor page write ${symbol} ${value}, expected 0`);
    }
  }
  const dirtyAfterEdit = runtime.hardware.memory[symbolAddress(symbols, 'DirtyAfterEdit')];
  const dirtyAfterSave = runtime.hardware.memory[symbolAddress(symbols, 'DirtyAfterSave')];
  if (dirtyAfterEdit !== 1) {
    throw new Error(`editor page write dirty after edit ${dirtyAfterEdit}, expected 1`);
  }
  if (dirtyAfterSave !== 0) {
    throw new Error(`editor page write dirty after save ${dirtyAfterSave}, expected 0`);
  }
  const quitAfterClean = runtime.hardware.memory[symbolAddress(symbols, 'QuitAfterClean')];
  if (quitAfterClean !== 1) {
    throw new Error(`editor page write quit after clean ${quitAfterClean}, expected 1`);
  }
  const dirtyAfterRestoreNo = runtime.hardware.memory[symbolAddress(symbols, 'DirtyAfterRestoreNo')];
  const dirtyAfterRestoreEsc = runtime.hardware.memory[symbolAddress(symbols, 'DirtyAfterRestoreEsc')];
  if (dirtyAfterRestoreNo !== 0) {
    throw new Error(`editor page write dirty after restore no ${dirtyAfterRestoreNo}, expected 0`);
  }
  if (dirtyAfterRestoreEsc !== 0) {
    throw new Error(`editor page write dirty after restore esc ${dirtyAfterRestoreEsc}, expected 0`);
  }
  const dirtyAfterRestore = runtime.hardware.memory[symbolAddress(symbols, 'DirtyAfterRestore')];
  if (dirtyAfterRestore !== 1) {
    throw new Error(`editor page write dirty after restore ${dirtyAfterRestore}, expected 1`);
  }

  const promptChecks = [
    { symbol: 'PromptActiveAfterIgnore', expected: 1 },
    { symbol: 'PromptResultAfterIgnore', expected: 0 },
    { symbol: 'PromptActiveAfterYes', expected: 0 },
    { symbol: 'PromptResultAfterYes', expected: 1 },
    { symbol: 'RestoreNoRecord0Length', expected: 10 },
    { symbol: 'RestoreNoRecord0FirstChar', expected: 'O'.charCodeAt(0) },
    { symbol: 'RestoreEscRecord0Length', expected: 10 },
    { symbol: 'RestoreEscRecord0FirstChar', expected: 'O'.charCodeAt(0) },
    { symbol: 'RestoreRecord0Length', expected: 8 },
    { symbol: 'RestoreRecord0FirstChar', expected: 'S'.charCodeAt(0) },
    { symbol: 'QuitAfterDirtyNo', expected: 0 },
    { symbol: 'PromptResultAfterQuitNo', expected: 2 },
    { symbol: 'QuitAfterDirtyYes', expected: 1 },
    { symbol: 'PromptResultAfterQuitYes', expected: 1 },
  ];
  for (const check of promptChecks) {
    const value = runtime.hardware.memory[symbolAddress(symbols, check.symbol)];
    if (value !== check.expected) {
      throw new Error(`editor page write ${check.symbol} ${value}, expected ${check.expected}`);
    }
  }

  const promptOverlay = readMemoryBytes(runtime.hardware.memory, symbolAddress(symbols, 'PromptOverlayRow9Bytes'), 6);
  const promptRestored = readMemoryBytes(runtime.hardware.memory, symbolAddress(symbols, 'PromptRestoredRow9Bytes'), 6);
  if (promptOverlay.join(',') === promptRestored.join(',')) {
    throw new Error(`editor page write prompt overlay row 9 did not differ from restored source row: [${promptOverlay.join(',')}]`);
  }

  const finalRow9 = readStatusRowTextByte(runtime.hardware.memory);
  if (promptRestored.join(',') !== finalRow9.join(',')) {
    throw new Error(
      `editor page write restored row 9 snapshot [${promptRestored.join(',')}] does not match final row 9 [${finalRow9.join(',')}]`,
    );
  }

  const stored = readFileFromProofImage(PROOF_CASES['editor-page-write-proof'], '/src/main.asm');
  const length = stored[0] & 0x1f;
  const text = stored.subarray(1, 1 + length).toString('ascii');
  if (text !== 'OKSMALL 00') {
    throw new Error(`editor page write persisted record 0 "${text}", expected "OKSMALL 00"`);
  }
  for (let offset = 1 + length; offset < 32; offset += 1) {
    const value = stored[offset];
    if (value !== 0) {
      throw new Error(`editor page write persisted padding offset ${offset} is ${resultToString(value)}, expected 0x00`);
    }
  }

  const backup = readFileFromProofImage(PROOF_CASES['editor-page-write-proof'], '/src/.main.asm.b');
  const backupLength = backup[0];
  const backupText = backup.subarray(1, 1 + backupLength).toString('ascii');
  if (backupText !== 'SMALL 00') {
    throw new Error(`editor backup persisted record 0 "${backupText}", expected "SMALL 00"`);
  }
}

function readMemoryBytes(memory: Uint8Array, address: number, length: number): number[] {
  return Array.from(memory.subarray(address, address + length));
}

function readStatusRowTextByte(memory: Uint8Array): number[] {
  const mon3Tgbuf = 0x13c0;
  const rowBytes = 16;
  const displayRow = 9;
  const textByte = 1;
  const values = [];
  for (let y = 0; y < 6; y += 1) {
    values.push(memory[mon3Tgbuf + (displayRow * 6 + DISPLAY_Y_ORIGIN + y) * rowBytes + textByte]);
  }
  return values;
}

function verifyShellEditVisibleCursor(runtime: Runtime, platformRuntime: PlatformRuntime): void {
  const glcd = getGlcdBytes(platformRuntime);
  assertCellMatchesInvertedFont(runtime.hardware.memory, 7, 3, '1'.charCodeAt(0));
  assertGlcdCellMatchesInvertedFont(runtime.hardware.memory, glcd, 7, 3, '1'.charCodeAt(0));
}

function readCellRows(memory: Uint8Array, row: number, column: number): number[] {
  const mon3Tgbuf = 0x13c0;
  const rowBytes = 16;
  const textX = 6;
  const cellX = textX + column * 6;
  const rows = [];
  for (let y = row * 6 + DISPLAY_Y_ORIGIN; y < row * 6 + DISPLAY_Y_ORIGIN + 6; y += 1) {
    let rowBits = 0;
    for (let x = cellX; x < cellX + 6; x += 1) {
      rowBits <<= 1;
      const address = mon3Tgbuf + y * rowBytes + Math.floor(x / 8);
      const mask = 0x80 >> (x % 8);
      if ((memory[address] & mask) !== 0) {
        rowBits |= 1;
      }
    }
    rows.push(rowBits);
  }
  return rows;
}

function readGlcdCellRows(glcd: number[], row: number, column: number): number[] {
  const rowBytes = 16;
  const textX = 6;
  const cellX = textX + column * 6;
  const rows = [];
  for (let y = row * 6 + DISPLAY_Y_ORIGIN; y < row * 6 + DISPLAY_Y_ORIGIN + 6; y += 1) {
    let rowBits = 0;
    for (let x = cellX; x < cellX + 6; x += 1) {
      rowBits <<= 1;
      const offset = y * rowBytes + Math.floor(x / 8);
      const mask = 0x80 >> (x % 8);
      if (((glcd[offset] ?? 0) & mask) !== 0) {
        rowBits |= 1;
      }
    }
    rows.push(rowBits);
  }
  return rows;
}

function readFontRows(memory: Uint8Array, charCode: number): number[] {
  const fontData = 0xdd9b;
  const offset = fontData + (charCode - 1) * 6;
  return Array.from(memory.subarray(offset, offset + 6), (value) => value & 0x3f);
}

function assertCellMatchesInvertedFont(memory: Uint8Array, row: number, column: number, charCode: number): void {
  const actual = readCellRows(memory, row, column);
  const expected = readFontRows(memory, charCode).map((value) => value ^ 0x3f);
  if (actual.join(',') !== expected.join(',')) {
    throw new Error(
      `shell edit cursor rendered inverted ${String.fromCharCode(charCode)} as [${actual.join(',')}], expected [${expected.join(',')}]`,
    );
  }
}

function assertGlcdCellMatchesInvertedFont(
  memory: Uint8Array,
  glcd: number[],
  row: number,
  column: number,
  charCode: number,
): void {
  const actual = readGlcdCellRows(glcd, row, column);
  const expected = readFontRows(memory, charCode).map((value) => value ^ 0x3f);
  if (actual.join(',') !== expected.join(',')) {
    throw new Error(
      `visible shell edit cursor rendered inverted ${String.fromCharCode(charCode)} as [${actual.join(',')}], expected [${expected.join(',')}]`,
    );
  }
}

function verifyShellEditLaunchProof(
  runtime: Runtime,
  platformRuntime: PlatformRuntime,
  symbols: D8Symbol[],
  expectedMode: number,
  expectedPath: string,
  expectedPrefix: string,
  expectedPage = 0,
  expectedRows = [
    { symbol: 'EditorRowText0', text: `${expectedPrefix} LINE 00` },
    { symbol: 'EditorRowText1', text: `${expectedPrefix} LINE 01` },
    { symbol: 'EditorRowText7', text: `${expectedPrefix} LINE 07` },
    { symbol: 'EditorRowText9', text: `${expectedPrefix} LINE 09` },
  ],
): void {
  const currentPage = symbolAddress(symbols, 'EditorNavCurrentPage');
  if (runtime.hardware.memory[currentPage] !== expectedPage) {
    throw new Error(`shell edit current page ${runtime.hardware.memory[currentPage]}, expected ${expectedPage}`);
  }

  const shellAction = symbolAddress(symbols, 'ShellLastExecAction');
  const shellRequestPtr = symbolAddress(symbols, 'ShellLastExecRequestPtr');
  if (runtime.hardware.memory[shellAction] !== 0x10) {
    throw new Error(`shell edit action ${runtime.hardware.memory[shellAction]}, expected SHELL_CMD_EDIT`);
  }

  const request = readWord(runtime.hardware.memory, shellRequestPtr);
  const mode = runtime.hardware.memory[request];
  const path = readCString(runtime.hardware.memory, request + 1);
  if (mode !== expectedMode) {
    throw new Error(`shell edit mode ${mode}, expected ${expectedMode}`);
  }
  if (path !== expectedPath) {
    throw new Error(`shell edit request path "${path}", expected "${expectedPath}"`);
  }

  for (const row of expectedRows) {
    const actual = readCString(runtime.hardware.memory, symbolAddress(symbols, row.symbol));
    if (actual !== row.text) {
      throw new Error(`shell edit copied ${row.symbol} as "${actual}", expected "${row.text}"`);
    }
  }

  const glcd = getGlcdBytes(platformRuntime);
  for (let row = 0; row < 10; row += 1) {
    if (!glcdRowHasPixels(glcd, row)) {
      throw new Error(`shell edit proof did not render display row: ${row}`);
    }
  }
}

async function main(): Promise<void> {
  if (!existsSync(MON3_ROM_PATH)) {
    throw new Error(`MON3 ROM not found: ${MON3_ROM_PATH}`);
  }

  const proofName = (process.argv[2] ?? 'editor-viewport-storage-proof') as ProofCaseName;
  const proofCase = PROOF_CASES[proofName];
  if (!proofCase) {
    throw new Error(`unknown editor viewport storage proof: ${proofName}`);
  }

  const imagePath = ensureImage(proofCase);
  const { bytes, symbols } = await compileProof(proofCase);
  const doneAddr = symbolAddress(symbols, 'ProofDone');
  const resultAddr = symbolAddress(symbols, 'ResultMarker');
  const { runtime, platformRuntime } = loadRuntime(bytes, imagePath);
  const instructions = runUntil(runtime, platformRuntime, doneAddr);
  const result = runtime.hardware.memory[resultAddr];
  if (result !== PROOF_PASS) {
    throw new Error(
      `editor viewport storage proof failed: marker=${resultToString(result)}${describeProofFailure(
        runtime,
        symbols,
      )}`,
    );
  }
  proofCase.verify(runtime, platformRuntime, symbols);

  const report = {
    result: 'ok',
    proof: proofName,
    instructions,
    resultMarker: resultToString(result),
    image: imagePath,
  };
  writeFileSync(proofCase.lastRun, JSON.stringify(report, null, 2) + '\n', 'ascii');
  console.log(JSON.stringify(report, null, 2));
}

function optionalSymbolAddress(symbols: D8Symbol[], name: string): number | undefined {
  const symbol = symbols.find((entry) => entry.name === name);
  return typeof symbol?.address === 'number' ? symbol.address : undefined;
}

function describeProofFailure(runtime: Runtime, symbols: D8Symbol[]): string {
  const parts: string[] = [];
  for (const name of [
    'CaseMarker',
    'ErrorMarker',
    'EditorLoadPrefixLen',
    'EditorLoadNameLen',
    'EditorLoadSrcPrefixId',
  ]) {
    const address = optionalSymbolAddress(symbols, name);
    if (address !== undefined) {
      parts.push(`${name}=${resultToString(runtime.hardware.memory[address])}`);
    }
  }
  for (const name of ['EditorLoadSourcePathPtr', 'EditorLoadPrefixPtr', 'EditorLoadNamePtr']) {
    const address = optionalSymbolAddress(symbols, name);
    if (address !== undefined) {
      const pointer = readWord(runtime.hardware.memory, address);
      parts.push(`${name}=0x${pointer.toString(16).padStart(4, '0')}`);
      parts.push(`${name}Text=${JSON.stringify(readCString(runtime.hardware.memory, pointer))}`);
    }
  }
  return parts.length > 0 ? ` (${parts.join(', ')})` : '';
}

main().catch((error: unknown) => {
  const message = error instanceof Error ? error.message : String(error);
  console.error(`error: ${message}`);
  process.exit(1);
});
