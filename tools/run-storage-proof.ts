#!/usr/bin/env node
/**
 * Run the ZAD storage proof against Debug80's TEC-1G runtime and MON3 ROM.
 *
 * This intentionally drives the same MON3 file API path ZAD expects to use:
 * openFile -> readSector -> writeSector. It does not implement ZAD FS logic.
 */

const { execFileSync } = require('node:child_process');
const { existsSync, readFileSync, writeFileSync } = require('node:fs');
const { resolve } = require('node:path');

const ZAD_ROOT = resolve(__dirname, '..');
const DEBUG80_ROOT = resolve(process.env.DEBUG80_ROOT ?? '/Users/johnhardy/projects/debug80');
const MON3_ROM_PATH = resolve(
  process.env.MON3_ROM_PATH ?? '/Users/johnhardy/projects/debug80-tec1g-mon3/roms/tec1g/mon-3/mon3.bin',
);

const IMAGE_PATH = resolve(ZAD_ROOT, 'proofs/storage/zadproof-fat32.img');
const IMAGE_TOOL = resolve(ZAD_ROOT, 'tools/create-storage-proof-image.ts');
const NODE_TS_ARGS = ['--experimental-strip-types'];

const MON3_OPEN_FILE_ADDR = 0xf5a1;
const MON3_READ_SECTOR_ADDR = 0xf5d5;
const MON3_WRITE_SECTOR_ADDR = 0xf66d;
const DISK_BUFF = 0x0600;
const MCB = 0x0888;
const SYS_CTRL = 0xff;
const SHADOW_OFF = 0x01;
const MCB_SD_CARD = 0x80;
const APP_START = 0x4000;
const SECTOR_SIZE = 512;

const MARKERS = [
  { sector: 0, label: 'markerSuperblock', text: 'ZAD MON3 WRITE SUPERBLOCK 0000' },
  { sector: 8, label: 'markerAlloc', text: 'ZAD MON3 WRITE ALLOC 0008' },
  { sector: 16, label: 'markerCatalogFirst', text: 'ZAD MON3 WRITE CATALOG 0016' },
  { sector: 79, label: 'markerCatalogLast', text: 'ZAD MON3 WRITE CATALOG 0079' },
  { sector: 80, label: 'markerDataFirst', text: 'ZAD MON3 WRITE DATA 0080' },
] as const;
const USE_SD_COMPAT_PATCH = !process.argv.includes('--no-sd-compat-patch');
const TRACE_POINTS: Record<number, string> = {
  0xf197: 'FATmount',
  0xf255: 'FATerror1: MBR read error',
  0xf25a: 'FATerror2: bad MBR signature',
  0xf25f: 'FATerror3: BPB read error',
  0xf264: 'FATerror4: BPB bytes-per-sector error',
  0xf269: 'FATerror5: root/file sector read/write error',
  0xf26e: 'FATerror6: file not found',
  0xf273: 'FATerror7: bad Intel HEX checksum',
  0xf278: 'FATerror8: no SD card',
  0xf27d: 'FATerror9: OCR read fail',
  0xf282: 'FATerror10: invalid SD card',
  0xf287: 'FATerror11: CMD16 failed',
  0xf28c: 'FATerror12: address too large',
  0xf291: 'FATerror dispatch',
  0xf02c: 'initDisk',
  0xf18b: 'FATmount',
  0xf296: 'FATgetRootDir',
  0xf3ea: 'FATgetRootDir done/error check',
  0xf5a1: 'openFile',
  0xf5d5: 'readSector',
  0xf66d: 'writeSector',
  0xf771: 'checkSDCardPresent',
  0xf803: 'initSD',
  0xc5d1: 'scanKeys',
  0xc656: 'scanKeysWait',
  0xc575: 'display delay loop',
};

type Runtime = {
  cpu: {
    pc: number;
    sp: number;
    halted: boolean;
    a: number;
    b: number;
    c: number;
    d: number;
    e: number;
    h: number;
    l: number;
  };
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
};

type SdSpiPatchInstance = {
  csMask: number;
  csActiveLow: boolean;
  csActive: boolean;
  clk: boolean;
  commandBytes: number[];
  pendingResponse: number[] | null;
  outputQueue: number[];
  outShift: number;
  outBitIndex: number;
  writeState: unknown;
  ioOut: number;
  appCommand: boolean;
  ready: boolean;
  highCapacity: boolean;
  handleCommand: (command: { cmd: number; arg: number; crc: number }) => void;
  beginTransaction: () => void;
  shiftIn: (bit: number) => void;
  shiftOut: () => void;
};

function requireFromDebug80(modulePath: string): unknown {
  return require(resolve(DEBUG80_ROOT, modulePath));
}

function installMon3SdSpiCompatibilityPatch(): void {
  const { SdSpi } = requireFromDebug80('out/platforms/tec1g/sd-spi.js') as {
    SdSpi: { prototype: SdSpiPatchInstance & { __zadMon3CompatPatch?: boolean } };
  };
  const proto = SdSpi.prototype;
  if (proto.__zadMon3CompatPatch) {
    return;
  }
  const originalHandleCommand = proto.handleCommand;

  proto.handleCommand = function handleCommandMon3Compatible(
    this: SdSpiPatchInstance,
    command: { cmd: number; arg: number; crc: number },
  ): void {
    if (command.cmd === 58) {
      const ocr = this.highCapacity ? 0xc0 : 0x80;
      this.pendingResponse = [this.ready ? 0x00 : 0x01, ocr, 0x00, 0x00, 0x00];
      return;
    }
    originalHandleCommand.call(this, command);
  };

  proto.write = function writeMon3Compatible(this: SdSpiPatchInstance, value: number): void {
    const nextClk = (value & 0x02) !== 0;
    const csLineHigh = (value & this.csMask) !== 0;
    const nextCsActive = this.csActiveLow ? !csLineHigh : csLineHigh;

    if (!nextCsActive) {
      this.csActive = false;
      this.clk = nextClk;
      return;
    }

    if (!this.csActive && nextCsActive) {
      const hasActiveTransaction =
        this.commandBytes.length > 0 ||
        this.pendingResponse !== null ||
        this.outputQueue.length > 0 ||
        this.outShift !== 0xff ||
        this.outBitIndex !== 0 ||
        this.writeState !== null;
      if (!hasActiveTransaction) {
        const appCommand = this.appCommand;
        this.beginTransaction();
        this.appCommand = appCommand;
      }
    }

    if (!this.clk && nextClk) {
      const bit = (value & 0x01) !== 0 ? 1 : 0;
      this.shiftIn(bit);
      this.shiftOut();
    }

    this.csActive = nextCsActive;
    this.clk = nextClk;
  };

  proto.read = function readMon3Compatible(this: SdSpiPatchInstance): number {
    if (!this.csActive) {
      return 0xff;
    }
    return this.ioOut ? 0x80 : 0x00;
  };

  proto.__zadMon3CompatPatch = true;
}

function low(value: number): number {
  return value & 0xff;
}

function high(value: number): number {
  return (value >> 8) & 0xff;
}

function asciiZ(text: string): number[] {
  return [...Buffer.from(text, 'ascii'), 0x00];
}

function buildProofProgram(): { bytes: Uint8Array; doneAddr: number } {
  const bytes: number[] = [];
  const push = (...values: number[]): void => {
    bytes.push(...values.map((value) => value & 0xff));
  };
  const ldHl = (addr: number): void => push(0x21, low(addr), high(addr));
  const ldDe = (addr: number): void => push(0x11, low(addr), high(addr));
  const ldBc = (value: number): void => push(0x01, low(value), high(value));
  const call = (addr: number): void => push(0xcd, low(addr), high(addr));
  const ldir = (): void => push(0xed, 0xb0);

  const placeholders: Record<string, number> = {};
  const labels: Record<string, number> = {};
  const label = (name: string): void => {
    labels[name] = APP_START + bytes.length;
  };
  const ldHlLabel = (name: string): void => {
    push(0x21, 0x00, 0x00);
    placeholders[`${name}:${bytes.length - 2}`] = bytes.length - 2;
  };
  const jpLabel = (name: string): void => {
    push(0xc3, 0x00, 0x00);
    placeholders[`${name}:${bytes.length - 2}`] = bytes.length - 2;
  };

  ldHlLabel('volumeName');
  call(MON3_OPEN_FILE_ADDR);

  for (const marker of MARKERS) {
    const byteOffset = marker.sector * SECTOR_SIZE;
    ldHl((byteOffset >>> 16) & 0xffff);
    ldDe(byteOffset & 0xffff);
    call(MON3_READ_SECTOR_ADDR);

    ldHlLabel(marker.label);
    ldDe(DISK_BUFF);
    ldBc(marker.text.length + 1);
    ldir();
    call(MON3_WRITE_SECTOR_ADDR);
  }

  label('done');
  jpLabel('done');

  label('volumeName');
  push(...asciiZ('VOLUME.ZAD'));
  for (const marker of MARKERS) {
    label(marker.label);
    push(...asciiZ(marker.text));
  }

  for (const [key, offset] of Object.entries(placeholders)) {
    const [name] = key.split(':');
    const addr = labels[name ?? ''];
    if (addr === undefined) {
      throw new Error(`missing label ${name}`);
    }
    bytes[offset] = low(addr);
    bytes[offset + 1] = high(addr);
  }
  if (labels.done === undefined) {
    throw new Error('missing done label');
  }
  return { bytes: Uint8Array.from(bytes), doneAddr: labels.done };
}

function ensureImage(): void {
  execFileSync(process.execPath, [...NODE_TS_ARGS, IMAGE_TOOL], {
    cwd: ZAD_ROOT,
    stdio: 'inherit',
  });
}

function makeConfig() {
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
    sdImagePath: IMAGE_PATH,
  };
}

function loadRuntime(): { runtime: Runtime; platformRuntime: PlatformRuntime; doneAddr: number } {
  if (USE_SD_COMPAT_PATCH) {
    installMon3SdSpiCompatibilityPatch();
  }
  const { createTec1gRuntime } = requireFromDebug80('out/platforms/tec1g/runtime.js') as {
    createTec1gRuntime: Function;
  };
  const { createTec1gMemoryHooks } = requireFromDebug80(
    'out/platforms/tec1g/tec1g-memory.js',
  ) as { createTec1gMemoryHooks: Function };
  const { createZ80Runtime } = requireFromDebug80('out/z80/runtime.js') as {
    createZ80Runtime: Function;
  };

  const config = makeConfig();
  const tec1gRuntime = createTec1gRuntime(config, () => {});
  const memory = new Uint8Array(0x10000);
  const rom = readFileSync(MON3_ROM_PATH);
  const proofProgram = buildProofProgram();
  memory.set(rom.subarray(0, 0x4000), 0xc000);
  memory.set(proofProgram.bytes, APP_START);

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

  // Minimal MON3 startup state needed for RST calls plus disk buffer RAM.
  tec1gRuntime.ioHandlers.write?.(SYS_CTRL, SHADOW_OFF);
  runtime.hardware.memory.set(runtime.hardware.memory.subarray(0xc000, 0xc100), 0x0000);
  runtime.hardware.forceMemWrite?.(MCB, MCB_SD_CARD);
  runtime.cpu.sp = 0x7ff0;
  runtime.cpu.pc = APP_START;
  return { runtime, platformRuntime: tec1gRuntime, doneAddr: proofProgram.doneAddr };
}

function runProof(runtime: Runtime, platformRuntime: PlatformRuntime, doneAddr: number): number {
  const maxInstructions = 20_000_000;
  const seenTracePoints = new Set<number>();
  const recentPcs: number[] = [];
  for (let i = 0; i < maxInstructions; i += 1) {
    const pc = runtime.cpu.pc & 0xffff;
    recentPcs.push(pc);
    if (recentPcs.length > 48) {
      recentPcs.shift();
    }
    const trace = TRACE_POINTS[pc];
    if (trace !== undefined && !seenTracePoints.has(pc)) {
      seenTracePoints.add(pc);
      console.error(
        `[trace] ${i} pc=0x${pc.toString(16).padStart(4, '0')} ${trace}`,
      );
      if (pc === 0xf282) {
        const ocr = [...runtime.hardware.memory.subarray(DISK_BUFF, DISK_BUFF + 4)]
          .map((value) => `0x${value.toString(16).padStart(2, '0')}`)
          .join(' ');
        throw new Error(`MON3 rejected SD OCR at instruction ${i}; DISK_BUFF=${ocr}`);
      }
      if (pc === 0xc575 || pc === 0xc5d1 || pc === 0xc656) {
        const stack = [];
        for (let offset = 0; offset < 16; offset += 2) {
          const lo = runtime.hardware.memRead?.((runtime.cpu.sp + offset) & 0xffff) ?? 0;
          const hi = runtime.hardware.memRead?.((runtime.cpu.sp + offset + 1) & 0xffff) ?? 0;
          stack.push(`0x${((hi << 8) | lo).toString(16).padStart(4, '0')}`);
        }
        const recent = recentPcs.map((entry) => `0x${entry.toString(16).padStart(4, '0')}`).join(' ');
        throw new Error(
          `entered MON3 UI wait path (${trace}) at instruction ${i}; regs=` +
            `AF? A=0x${runtime.cpu.a.toString(16)} BC=0x${(((runtime.cpu.b << 8) | runtime.cpu.c) & 0xffff).toString(16)} ` +
            `DE=0x${(((runtime.cpu.d << 8) | runtime.cpu.e) & 0xffff).toString(16)} ` +
            `HL=0x${(((runtime.cpu.h << 8) | runtime.cpu.l) & 0xffff).toString(16)} ` +
            `SP=0x${runtime.cpu.sp.toString(16)} stack=${stack.join(',')} recent=${recent}`,
        );
      }
    }
    if (pc === doneAddr) {
      return i;
    }
    const result = runtime.step();
    platformRuntime.recordCycles(result.cycles ?? 0);
  }
  const recent = recentPcs.map((pc) => `0x${pc.toString(16).padStart(4, '0')}`).join(' ');
  throw new Error(
    `proof did not reach done at 0x${doneAddr.toString(16)}; pc=0x${runtime.cpu.pc.toString(16)} recent=${recent}`,
  );
}

function verifyMarkers(): Array<{ sector: number; offset: number; marker: string }> {
  const manifestPath = IMAGE_PATH.replace(/\.[^.]*$/, '.json');
  const manifest = JSON.parse(readFileSync(manifestPath, 'utf8'));
  const image = readFileSync(IMAGE_PATH);
  return MARKERS.map((marker) => {
    const offset = manifest.volume_start_byte_offset + marker.sector * SECTOR_SIZE;
    const actual = image.subarray(offset, offset + marker.text.length).toString('ascii');
    if (actual !== marker.text) {
      throw new Error(`sector ${marker.sector} marker mismatch: ${JSON.stringify(actual)}`);
    }
    return { sector: marker.sector, offset, marker: marker.text };
  });
}

function main(): void {
  if (!existsSync(MON3_ROM_PATH)) {
    throw new Error(`MON3 ROM not found: ${MON3_ROM_PATH}`);
  }
  ensureImage();
  const { runtime, platformRuntime, doneAddr } = loadRuntime();
  const instructions = runProof(runtime, platformRuntime, doneAddr);
  const markers = verifyMarkers();
  writeFileSync(
    resolve(ZAD_ROOT, 'proofs/storage/last-run.json'),
    JSON.stringify({ instructions, doneAddr, markers }, null, 2) + '\n',
    'ascii',
  );
  console.log(
    JSON.stringify(
      {
        result: 'ok',
        instructions,
        doneAddr,
        markers,
      },
      null,
      2,
    ),
  );
}

main();
