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
  resolve(TECM8_ROOT, 'src/tecm8-bios.asmi'),
  resolve(TECM8_ROOT, 'src/display-model.asmi'),
  resolve(TECM8_ROOT, 'src/editor-viewport.asmi'),
  resolve(TECM8_ROOT, 'src/editor-storage-loader.asmi'),
  resolve(TECM8_ROOT, 'src/editor-navigation.asmi'),
  resolve(TECM8_ROOT, 'src/shell-editor-launch.asmi'),
  resolve(TECM8_ROOT, 'src/editor-interaction.asmi'),
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
  if (!symbol || typeof symbol.address !== 'number') {
    throw new Error(`missing address symbol: ${name}`);
  }
  return symbol.address;
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
  const length = memory[start];
  return Buffer.from(memory.subarray(start + 1, start + 1 + length)).toString('ascii');
}

function getGlcdBytes(platformRuntime: PlatformRuntime): number[] {
  return Array.from(platformRuntime.state.display?.glcdCtrl?.glcd ?? []);
}

function glcdRowHasPixels(glcd: number[], displayRow: number): boolean {
  const firstPixelRow = displayRow * 6;
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
  if (runtime.hardware.memory[currentPage] !== 7) {
    throw new Error(`editor navigation current page ${runtime.hardware.memory[currentPage]}, expected 7`);
  }

  const expectedRows = [
    { symbol: 'EditorRowText0', text: 'P7 LINE 00' },
    { symbol: 'EditorRowText1', text: 'P7 LINE 01' },
    { symbol: 'EditorRowText7', text: 'P7 LINE 07' },
  ];
  for (const row of expectedRows) {
    const actual = readCString(runtime.hardware.memory, symbolAddress(symbols, row.symbol));
    if (actual !== row.text) {
      throw new Error(`editor navigation copied ${row.symbol} as "${actual}", expected "${row.text}"`);
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
  verifyShellEditLaunchProof(runtime, platformRuntime, symbols, 0x18, '/projects/demo/app.asm', 'A1', 1);
}

function verifyShellEditLaunchProof(
  runtime: Runtime,
  platformRuntime: PlatformRuntime,
  symbols: D8Symbol[],
  expectedMode: number,
  expectedPath: string,
  expectedPrefix: string,
  expectedPage = 0,
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

  const expectedRows = [
    { symbol: 'EditorRowText0', text: `${expectedPrefix} LINE 00` },
    { symbol: 'EditorRowText1', text: `${expectedPrefix} LINE 01` },
    { symbol: 'EditorRowText7', text: `${expectedPrefix} LINE 07` },
  ];
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
