#!/usr/bin/env node
/**
 * Assemble and run the TECM8 editor entry in Debug80's TEC-1G runtime.
 */

const { mkdirSync, writeFileSync } = require('node:fs');
const { dirname, resolve } = require('node:path');

import type { D8Symbol, PlatformRuntime, ProofHarness, Runtime } from './proof/harness';

const harness: ProofHarness = require('./proof/harness.ts');
const {
  TECM8_ROOT,
  MON3_INTERFACE,
  APP_START,
  PROOF_PASS,
  compileAzm,
  symbolAddress,
  loadTec1gRuntime,
  stepRuntime,
  runUntil,
  runUntilPc,
  stepThenRunUntilPc,
  runUntilAnyPc,
  runInstructions,
  readWord,
  readAsciiZ,
  encodeSourceRecords,
  readSourceRecord,
  requireTm8Format,
  createProofImage,
  writeVolumeIntoImage,
  readFileFromImage,
  getGlcdBytes,
} = harness;

const SESSION_DIR = resolve(TECM8_ROOT, 'demos/debug80');
const IMAGE_PATH = resolve(SESSION_DIR, 'editor-session-fat32.img');
const GLCD_CAPTURE_PATH = resolve(SESSION_DIR, 'editor-session-glcd.pgm');
const SUMMARY_PATH = resolve(SESSION_DIR, 'editor-session-last-run.json');
const SOURCE_FILE = resolve(TECM8_ROOT, 'src/main.asm');

function compileMain(): Promise<{ bytes: Uint8Array; symbols: D8Symbol[] }> {
  return compileAzm(SOURCE_FILE, 'main', { interfaces: [MON3_INTERFACE] });
}

function encodeProjectConfig(mainFile: string): Buffer {
  return Buffer.from(['tm8project=1', `main=${mainFile}`, ''].join('\n'), 'ascii');
}

function ensureSessionImage(): void {
  mkdirSync(SESSION_DIR, { recursive: true });
  createProofImage(IMAGE_PATH);

  const { createVolumeImage, importFileIntoVolumeImage, readFileFromVolumeImage } = requireTm8Format();
  let volume = createVolumeImage() as Buffer;
  const sourceRecords = encodeSourceRecords([
    'R0 LINE 00',
    'R0 LINE 01',
    'R0 LINE 02',
    'R0 LINE 03',
    'R0 LINE 04',
    'R0 LINE 05',
    'R0 LINE 06',
    'R0 LINE 07',
    'R0 LINE 08',
    'R0 LINE 09',
    'R0 LINE 10',
    'R0 LINE 11',
    'R0 LINE 12',
    'R0 LINE 13',
    'R0 LINE 14',
    '',
    'R1 LINE 00',
    'R1 LINE 01',
    'R1 LINE 02',
    'R1 LINE 03',
    'R1 LINE 04',
    'R1 LINE 05',
    'R1 LINE 06',
    'R1 LINE 07',
    'R1 LINE 08',
    'R1 LINE 09',
    'R1 LINE 10',
    'R1 LINE 11',
    'R1 LINE 12',
    'R1 LINE 13',
    'R1 LINE 14',
    'R1 LINE 15',
  ]);
  volume = importFileIntoVolumeImage(volume, '/tecm8.prj', encodeProjectConfig('/src/main.asm'));
  volume = importFileIntoVolumeImage(volume, '/src/main.asm', sourceRecords);

  const storedProject = readFileFromVolumeImage(volume, '/tecm8.prj') as Buffer;
  if (!storedProject.equals(encodeProjectConfig('/src/main.asm'))) {
    throw new Error('generated project config was not stored exactly');
  }

  writeVolumeIntoImage(IMAGE_PATH, volume);
}

function tapMatrixKey(
  platformRuntime: PlatformRuntime,
  runtime: Runtime,
  row: number,
  col: number,
  settleInstructions = 20000,
  releaseInstructions = 20000,
): void {
  if (!platformRuntime.applyMatrixKey) {
    throw new Error('Debug80 runtime does not expose matrix key injection');
  }
  platformRuntime.applyMatrixKey(row, col, true);
  runInstructions(runtime, platformRuntime, settleInstructions);
  platformRuntime.applyMatrixKey(row, col, false);
  runInstructions(runtime, platformRuntime, releaseInstructions);
}

function tapMatrixCombo(
  platformRuntime: PlatformRuntime,
  runtime: Runtime,
  modifier: { row: number; col: number },
  key: { row: number; col: number },
  settleInstructions = 20000,
  releaseInstructions = 20000,
): void {
  if (!platformRuntime.applyMatrixKey) {
    throw new Error('Debug80 runtime does not expose matrix key injection');
  }
  platformRuntime.applyMatrixKey(modifier.row, modifier.col, true);
  platformRuntime.applyMatrixKey(key.row, key.col, true);
  runInstructions(runtime, platformRuntime, settleInstructions);
  platformRuntime.applyMatrixKey(key.row, key.col, false);
  platformRuntime.applyMatrixKey(modifier.row, modifier.col, false);
  runInstructions(runtime, platformRuntime, releaseInstructions);
}

function readTm8File(tm8Path: string): Buffer {
  return readFileFromImage(IMAGE_PATH, tm8Path);
}

function readBufferSourceRecord(records: Buffer, record: number): string {
  const start = record * 32;
  const length = records[start] & 0x1f;
  return records.subarray(start + 1, start + 1 + length).toString('ascii');
}

function assertRuntimeSourceRecord(
  runtime: Runtime,
  pageBufferAddr: number,
  record: number,
  expected: string,
  label: string,
): void {
  const actual = readSourceRecord(runtime.hardware.memory, pageBufferAddr, record);
  if (actual !== expected) {
    throw new Error(`${label} record ${record} "${actual}", expected "${expected}"`);
  }
}

function writeGlcdCapture(glcd: number[]): void {
  mkdirSync(dirname(GLCD_CAPTURE_PATH), { recursive: true });
  const pixels = Buffer.alloc(128 * 64);
  for (let y = 0; y < 64; y += 1) {
    for (let byteX = 0; byteX < 16; byteX += 1) {
      const value = glcd[y * 16 + byteX] ?? 0;
      for (let bit = 0; bit < 8; bit += 1) {
        const x = byteX * 8 + bit;
        pixels[y * 128 + x] = (value & (0x80 >> bit)) !== 0 ? 0 : 255;
      }
    }
  }
  writeFileSync(GLCD_CAPTURE_PATH, Buffer.concat([Buffer.from('P5\n128 64\n255\n', 'ascii'), pixels]));
}

type LiveSmokeAddrs = {
  liveLoop: number;
  done: number;
  cursorRow: number;
  cursorCol: number;
  dirty: number;
  currentPage: number;
  pageBuffer: number;
  promptActive: number;
  promptResult: number;
  quitRequested: number;
  modifierBits: number;
  rawPrimary: number;
  rawSecondary: number;
  translatedKey: number;
};

type LiveSmokeContext = {
  runtime: Runtime;
  platformRuntime: PlatformRuntime;
  addrs: LiveSmokeAddrs;
};

function resolveLiveSmokeAddrs(symbols: D8Symbol[]): LiveSmokeAddrs {
  return {
    liveLoop: symbolAddress(symbols, 'EditorLiveLoop'),
    done: symbolAddress(symbols, 'MainDone'),
    cursorRow: symbolAddress(symbols, 'EditorCursorRow'),
    cursorCol: symbolAddress(symbols, 'EditorCursorCol'),
    dirty: symbolAddress(symbols, 'EditorNavDirty'),
    currentPage: symbolAddress(symbols, 'EditorNavCurrentPage'),
    pageBuffer: symbolAddress(symbols, 'EditorNavPageBuffer'),
    promptActive: symbolAddress(symbols, 'EditorPromptActive'),
    promptResult: symbolAddress(symbols, 'EditorPromptResult'),
    quitRequested: symbolAddress(symbols, 'EditorQuitRequested'),
    modifierBits: symbolAddress(symbols, 'BiosInputModifierBits'),
    rawPrimary: symbolAddress(symbols, 'BiosInputRawPrimary'),
    rawSecondary: symbolAddress(symbols, 'BiosInputRawSecondary'),
    translatedKey: symbolAddress(symbols, 'BiosInputTranslatedKey'),
  };
}

function readByte(ctx: LiveSmokeContext, addr: number): number {
  return ctx.runtime.hardware.memory[addr];
}

function describeKeyEvent(ctx: LiveSmokeContext): string {
  const modifier = readByte(ctx, ctx.addrs.modifierBits);
  const rawPrimary = readByte(ctx, ctx.addrs.rawPrimary);
  const rawSecondary = readByte(ctx, ctx.addrs.rawSecondary);
  const translated = readByte(ctx, ctx.addrs.translatedKey);
  return `modifier=0x${modifier.toString(16)} raw=${rawSecondary.toString(16)}/${rawPrimary.toString(16)} translated=0x${translated.toString(16)}`;
}

function smokeCursorPaging(ctx: LiveSmokeContext): Record<string, number> {
  const { runtime, platformRuntime, addrs } = ctx;
  tapMatrixKey(platformRuntime, runtime, 0, 4); // ArrowDown: raw key 04h
  runUntilPc(runtime, platformRuntime, addrs.liveLoop, 20_000_000);
  tapMatrixKey(platformRuntime, runtime, 0, 3); // ArrowUp: raw key 03h
  runUntilPc(runtime, platformRuntime, addrs.liveLoop, 20_000_000);
  tapMatrixKey(platformRuntime, runtime, 0, 4); // ArrowDown: raw key 04h
  runUntilPc(runtime, platformRuntime, addrs.liveLoop, 20_000_000);
  tapMatrixKey(platformRuntime, runtime, 0, 6); // ArrowRight: raw key 06h
  runUntilPc(runtime, platformRuntime, addrs.liveLoop, 20_000_000);
  tapMatrixCombo(platformRuntime, runtime, { row: 0, col: 1 }, { row: 0, col: 4 }); // Ctrl+ArrowDown
  runUntilPc(runtime, platformRuntime, addrs.liveLoop, 20_000_000);
  const pageAfterCtrlDown = readByte(ctx, addrs.currentPage);
  const rowAfterCtrlDown = readByte(ctx, addrs.cursorRow);
  if (pageAfterCtrlDown !== 1 || rowAfterCtrlDown !== 0) {
    throw new Error(
      `live editor after Ctrl+ArrowDown page=${pageAfterCtrlDown} row=${rowAfterCtrlDown}, expected page=1 row=0`,
    );
  }
  tapMatrixCombo(platformRuntime, runtime, { row: 0, col: 1 }, { row: 0, col: 3 }); // Ctrl+ArrowUp
  runUntilPc(runtime, platformRuntime, addrs.liveLoop, 20_000_000);
  const pageAfterCtrlUp = readByte(ctx, addrs.currentPage);
  if (pageAfterCtrlUp !== 0) {
    throw new Error(`live editor page after Ctrl+ArrowUp ${pageAfterCtrlUp}, expected 0`);
  }
  return { pageAfterCtrlDown, rowAfterCtrlDown, pageAfterCtrlUp };
}

function smokeModifierDiagnostics(ctx: LiveSmokeContext): Record<string, number> {
  const { runtime, platformRuntime, addrs } = ctx;
  tapMatrixCombo(platformRuntime, runtime, { row: 0, col: 3 }, { row: 0, col: 6 }); // Alt+ArrowRight
  runUntilPc(runtime, platformRuntime, addrs.liveLoop, 20_000_000);
  const altModifierBits = readByte(ctx, addrs.modifierBits);
  const altRawPrimary = readByte(ctx, addrs.rawPrimary);
  const altRawSecondary = readByte(ctx, addrs.rawSecondary);
  const altTranslatedKey = readByte(ctx, addrs.translatedKey);
  if (
    altModifierBits !== 0x08 ||
    altRawPrimary !== 0x06 ||
    altRawSecondary !== 0x03 ||
    altTranslatedKey !== 0x06
  ) {
    throw new Error(
      `live editor alt event modifier=0x${altModifierBits.toString(16)} raw=${altRawSecondary.toString(16)}/${altRawPrimary.toString(16)} translated=0x${altTranslatedKey.toString(16)}`,
    );
  }
  tapMatrixKey(platformRuntime, runtime, 0, 7); // CapsLock toggles caps state, no editor action
  runUntilPc(runtime, platformRuntime, addrs.liveLoop, 20_000_000);
  tapMatrixKey(platformRuntime, runtime, 0, 4); // ArrowDown with caps state set
  runUntilPc(runtime, platformRuntime, addrs.liveLoop, 20_000_000);
  const cursorRow = readByte(ctx, addrs.cursorRow);
  const cursorCol = readByte(ctx, addrs.cursorCol);
  const modifierBits = readByte(ctx, addrs.modifierBits);
  const rawPrimary = readByte(ctx, addrs.rawPrimary);
  const rawSecondary = readByte(ctx, addrs.rawSecondary);
  const translatedKey = readByte(ctx, addrs.translatedKey);
  if (cursorRow !== 1 || cursorCol !== 1) {
    throw new Error(`live editor cursor row=${cursorRow} col=${cursorCol}, expected row=1 col=1`);
  }
  if (modifierBits !== 0x10 || rawPrimary !== 0x04 || rawSecondary !== 0xff || translatedKey !== 0x04) {
    throw new Error(
      `live editor key event modifier=0x${modifierBits.toString(16)} raw=${rawSecondary.toString(16)}/${rawPrimary.toString(16)} translated=0x${translatedKey.toString(16)}`,
    );
  }
  return { cursorRow, cursorCol, modifierBits, rawPrimary, rawSecondary, translatedKey };
}

function smokeDirtyPaging(ctx: LiveSmokeContext): Record<string, number> {
  const { runtime, platformRuntime, addrs } = ctx;
  tapMatrixKey(platformRuntime, runtime, 7, 5); // z
  stepThenRunUntilPc(runtime, platformRuntime, addrs.liveLoop, 20_000_000);
  const dirtyAfterEdit = readByte(ctx, addrs.dirty);
  if (dirtyAfterEdit !== 1) {
    throw new Error(`live editor dirty after z ${dirtyAfterEdit}, expected 1`);
  }
  tapMatrixCombo(platformRuntime, runtime, { row: 0, col: 3 }, { row: 0, col: 4 }, 200_000, 200_000); // dirty Alt+ArrowDown within RAM window
  stepThenRunUntilPc(runtime, platformRuntime, addrs.liveLoop, 20_000_000);
  const pageAfterDirtyPageDown = readByte(ctx, addrs.currentPage);
  const dirtyAfterDirtyPageDown = readByte(ctx, addrs.dirty);
  if (pageAfterDirtyPageDown !== 1 || dirtyAfterDirtyPageDown !== 1) {
    throw new Error(
      `live editor dirty Alt+ArrowDown page=${pageAfterDirtyPageDown} dirty=${dirtyAfterDirtyPageDown}, expected page=1 dirty=1`,
    );
  }
  tapMatrixCombo(platformRuntime, runtime, { row: 0, col: 1 }, { row: 0, col: 3 }, 200_000, 200_000); // dirty Ctrl+ArrowUp back to edited page
  stepThenRunUntilPc(runtime, platformRuntime, addrs.liveLoop, 60_000_000);
  const pageAfterDirtyPageUp = readByte(ctx, addrs.currentPage);
  const dirtyAfterDirtyPageUp = readByte(ctx, addrs.dirty);
  if (pageAfterDirtyPageUp !== 0 || dirtyAfterDirtyPageUp !== 1) {
    throw new Error(
      `live editor dirty Alt+ArrowUp page=${pageAfterDirtyPageUp} dirty=${dirtyAfterDirtyPageUp}, expected page=0 dirty=1`,
    );
  }
  return { dirtyAfterEdit, pageAfterDirtyPageDown };
}

function smokeSplitSaveJoin(ctx: LiveSmokeContext): Record<string, number> {
  const { runtime, platformRuntime, addrs } = ctx;
  tapMatrixKey(platformRuntime, runtime, 1, 2); // Enter: split line
  stepThenRunUntilPc(runtime, platformRuntime, addrs.liveLoop, 20_000_000);
  const cursorRowAfterEnter = readByte(ctx, addrs.cursorRow);
  const cursorColAfterEnter = readByte(ctx, addrs.cursorCol);
  if (cursorRowAfterEnter !== 1 || cursorColAfterEnter !== 0) {
    throw new Error(
      `live editor cursor after Enter ${cursorRowAfterEnter},${cursorColAfterEnter}; expected 1,0; ${describeKeyEvent(ctx)}`,
    );
  }
  assertRuntimeSourceRecord(runtime, addrs.pageBuffer, 0, '', 'after Enter split');
  assertRuntimeSourceRecord(runtime, addrs.pageBuffer, 1, 'R0 LINE 00', 'after Enter split');
  assertRuntimeSourceRecord(runtime, addrs.pageBuffer, 2, 'RZ0 LINE 01', 'after Enter split');
  assertRuntimeSourceRecord(runtime, addrs.pageBuffer, 15, 'R0 LINE 14', 'after Enter split');
  tapMatrixCombo(platformRuntime, runtime, { row: 0, col: 3 }, { row: 6, col: 6 }, 200_000, 200_000); // Alt+S
  stepThenRunUntilPc(runtime, platformRuntime, addrs.liveLoop, 120_000_000);
  const dirtyAfterSave = readByte(ctx, addrs.dirty);
  const saveTranslatedKey = readByte(ctx, addrs.translatedKey);
  const saveModifierBits = readByte(ctx, addrs.modifierBits);
  if (
    dirtyAfterSave !== 0 ||
    (saveTranslatedKey !== 0x53 && saveTranslatedKey !== 0x73) ||
    (saveModifierBits & 0x08) === 0
  ) {
    throw new Error(
      `live editor Alt-S save dirty=${dirtyAfterSave} modifier=0x${saveModifierBits.toString(16)} translated=0x${saveTranslatedKey.toString(16)}, expected dirty=0 alt-modified S/s`,
    );
  }
  tapMatrixCombo(platformRuntime, runtime, { row: 0, col: 3 }, { row: 0, col: 4 }, 200_000, 200_000); // Alt+ArrowDown
  stepThenRunUntilPc(runtime, platformRuntime, addrs.liveLoop, 60_000_000);
  const pageAfterSplitSaveDown = readByte(ctx, addrs.currentPage);
  if (pageAfterSplitSaveDown !== 1) {
    throw new Error(`live editor page after saved split Alt+ArrowDown ${pageAfterSplitSaveDown}, expected 1`);
  }
  tapMatrixCombo(platformRuntime, runtime, { row: 0, col: 1 }, { row: 0, col: 3 }, 200_000, 200_000); // Ctrl+ArrowUp
  stepThenRunUntilPc(runtime, platformRuntime, addrs.liveLoop, 60_000_000);
  const pageAfterSplitSaveUp = readByte(ctx, addrs.currentPage);
  if (pageAfterSplitSaveUp !== 0) {
    throw new Error(`live editor page after saved split Alt+ArrowUp ${pageAfterSplitSaveUp}, expected 0`);
  }
  assertRuntimeSourceRecord(runtime, addrs.pageBuffer, 0, '', 'after saved split page return');
  assertRuntimeSourceRecord(runtime, addrs.pageBuffer, 1, 'R0 LINE 00', 'after saved split page return');
  assertRuntimeSourceRecord(runtime, addrs.pageBuffer, 2, 'RZ0 LINE 01', 'after saved split page return');
  tapMatrixKey(platformRuntime, runtime, 0, 4); // ArrowDown: move to split tail for join
  stepThenRunUntilPc(runtime, platformRuntime, addrs.liveLoop, 20_000_000);
  tapMatrixKey(platformRuntime, runtime, 1, 0); // Backspace: join with previous line
  stepThenRunUntilPc(runtime, platformRuntime, addrs.liveLoop, 20_000_000);
  const cursorRowAfterJoin = readByte(ctx, addrs.cursorRow);
  const cursorColAfterJoin = readByte(ctx, addrs.cursorCol);
  if (cursorRowAfterJoin !== 0 || cursorColAfterJoin !== 0) {
    throw new Error(
      `live editor cursor after Backspace join ${cursorRowAfterJoin},${cursorColAfterJoin}; expected 0,0`,
    );
  }
  assertRuntimeSourceRecord(runtime, addrs.pageBuffer, 0, 'R0 LINE 00', 'after Backspace join');
  assertRuntimeSourceRecord(runtime, addrs.pageBuffer, 1, 'RZ0 LINE 01', 'after Backspace join');
  assertRuntimeSourceRecord(runtime, addrs.pageBuffer, 15, '', 'after Backspace join');
  tapMatrixCombo(platformRuntime, runtime, { row: 0, col: 3 }, { row: 6, col: 6 }, 200_000, 200_000); // save joined page
  stepThenRunUntilPc(runtime, platformRuntime, addrs.liveLoop, 120_000_000);
  const dirtyAfterJoinSave = readByte(ctx, addrs.dirty);
  if (dirtyAfterJoinSave !== 0) {
    throw new Error(`live editor dirty after join save ${dirtyAfterJoinSave}, expected 0`);
  }
  tapMatrixCombo(platformRuntime, runtime, { row: 0, col: 3 }, { row: 6, col: 6 }, 200_000, 200_000); // clean Alt+S no-op
  stepThenRunUntilPc(runtime, platformRuntime, addrs.liveLoop, 20_000_000);
  const dirtyAfterCleanSave = readByte(ctx, addrs.dirty);
  if (dirtyAfterCleanSave !== 0) {
    throw new Error(`live editor clean save dirty=${dirtyAfterCleanSave}, expected 0`);
  }
  tapMatrixKey(platformRuntime, runtime, 7, 5); // z after save: editor should still accept input
  stepThenRunUntilPc(runtime, platformRuntime, addrs.liveLoop, 20_000_000);
  const dirtyAfterPostSaveEdit = readByte(ctx, addrs.dirty);
  if (dirtyAfterPostSaveEdit !== 1) {
    throw new Error(
      `live editor post-save edit dirty=${dirtyAfterPostSaveEdit}, expected 1; ${describeKeyEvent(ctx)}`,
    );
  }
  tapMatrixCombo(platformRuntime, runtime, { row: 0, col: 3 }, { row: 6, col: 6 }, 200_000, 200_000); // save post-save edit
  stepThenRunUntilPc(runtime, platformRuntime, addrs.liveLoop, 120_000_000);
  const dirtyAfterSecondSave = readByte(ctx, addrs.dirty);
  if (dirtyAfterSecondSave !== 0) {
    throw new Error(`live editor second save dirty=${dirtyAfterSecondSave}, expected 0`);
  }
  return {
    cursorRowAfterEnter,
    cursorColAfterEnter,
    dirtyAfterSave,
    saveTranslatedKey,
    saveModifierBits,
    pageAfterSplitSaveDown,
    pageAfterSplitSaveUp,
    cursorRowAfterJoin,
    cursorColAfterJoin,
    dirtyAfterJoinSave,
    dirtyAfterCleanSave,
    dirtyAfterPostSaveEdit,
    dirtyAfterSecondSave,
  };
}

function smokeRestorePromptAndQuit(ctx: LiveSmokeContext): Record<string, number> {
  const { runtime, platformRuntime, addrs } = ctx;
  tapMatrixCombo(platformRuntime, runtime, { row: 0, col: 3 }, { row: 6, col: 5 }, 200_000, 200_000); // Alt+R
  stepThenRunUntilPc(runtime, platformRuntime, addrs.liveLoop, 20_000_000);
  const promptAfterAltR = readByte(ctx, addrs.promptActive);
  if (promptAfterAltR !== 1) {
    const restoreModifierBits = readByte(ctx, addrs.modifierBits);
    const restoreTranslatedKey = readByte(ctx, addrs.translatedKey);
    throw new Error(
      `live editor Alt-R prompt active=${promptAfterAltR}, expected 1; modifier=0x${restoreModifierBits.toString(16)} translated=0x${restoreTranslatedKey.toString(16)}`,
    );
  }
  tapMatrixKey(platformRuntime, runtime, 6, 1, 200_000, 200_000); // n: cancel restore prompt
  stepThenRunUntilPc(runtime, platformRuntime, addrs.liveLoop, 20_000_000);
  const promptAfterRestoreNo = readByte(ctx, addrs.promptActive);
  const restoreNoResult = readByte(ctx, addrs.promptResult);
  const dirtyAfterRestoreNo = readByte(ctx, addrs.dirty);
  if (promptAfterRestoreNo !== 0 || restoreNoResult !== 2 || dirtyAfterRestoreNo !== 0) {
    throw new Error(
      `live editor restore cancel prompt=${promptAfterRestoreNo} result=${restoreNoResult} dirty=${dirtyAfterRestoreNo}, expected prompt=0 result=2 dirty=0`,
    );
  }
  tapMatrixCombo(platformRuntime, runtime, { row: 0, col: 3 }, { row: 7, col: 3 }, 200_000, 200_000); // Alt+X
  stepRuntime(runtime, platformRuntime);
  let afterQuitPc = runUntilAnyPc(runtime, platformRuntime, [addrs.done, addrs.liveLoop], 20_000_000);
  if (afterQuitPc === addrs.liveLoop && readByte(ctx, addrs.quitRequested) === 1) {
    stepRuntime(runtime, platformRuntime);
    afterQuitPc = runUntilAnyPc(runtime, platformRuntime, [addrs.done, addrs.liveLoop], 20_000_000);
  }
  const quitTranslatedKey = readByte(ctx, addrs.translatedKey);
  if (afterQuitPc !== addrs.done) {
    throw new Error(`live editor Alt-X returned to loop instead of exiting: ${describeKeyEvent(ctx)}`);
  }
  const quitModifierBits = readByte(ctx, addrs.modifierBits);
  if ((quitTranslatedKey !== 0x58 && quitTranslatedKey !== 0x78) || (quitModifierBits & 0x08) === 0) {
    throw new Error(
      `live editor quit modifier=0x${quitModifierBits.toString(16)} translated=0x${quitTranslatedKey.toString(16)}, expected alt-modified X/x`,
    );
  }
  return { promptAfterAltR, promptAfterRestoreNo, dirtyAfterRestoreNo, quitTranslatedKey };
}

async function runLiveSmoke(bytes: Uint8Array, symbols: D8Symbol[]): Promise<void> {
  const addrs = resolveLiveSmokeAddrs(symbols);
  const { runtime, platformRuntime } = loadTec1gRuntime(bytes, {
    imagePath: IMAGE_PATH,
    startAddress: APP_START,
    matrixMode: true,
    sysModeShadowOff: true,
  });
  platformRuntime.setMatrixMode?.(true);
  const ctx: LiveSmokeContext = { runtime, platformRuntime, addrs };
  const bootInstructions = runUntilPc(runtime, platformRuntime, addrs.liveLoop, 60_000_000);

  const metrics = {
    ...smokeCursorPaging(ctx),
    ...smokeModifierDiagnostics(ctx),
    ...smokeDirtyPaging(ctx),
    ...smokeSplitSaveJoin(ctx),
    ...smokeRestorePromptAndQuit(ctx),
  };

  const summary = {
    result: 'ok',
    liveSmoke: true,
    bootInstructions,
    cursorRow: metrics.cursorRow,
    cursorCol: metrics.cursorCol,
    pageAfterCtrlDown: metrics.pageAfterCtrlDown,
    rowAfterCtrlDown: metrics.rowAfterCtrlDown,
    pageAfterCtrlUp: metrics.pageAfterCtrlUp,
    dirtyAfterEdit: metrics.dirtyAfterEdit,
    pageAfterDirtyPageDown: metrics.pageAfterDirtyPageDown,
    cursorRowAfterEnter: metrics.cursorRowAfterEnter,
    cursorColAfterEnter: metrics.cursorColAfterEnter,
    cursorRowAfterJoin: metrics.cursorRowAfterJoin,
    cursorColAfterJoin: metrics.cursorColAfterJoin,
    dirtyAfterSave: metrics.dirtyAfterSave,
    pageAfterSplitSaveDown: metrics.pageAfterSplitSaveDown,
    pageAfterSplitSaveUp: metrics.pageAfterSplitSaveUp,
    dirtyAfterCleanSave: metrics.dirtyAfterCleanSave,
    dirtyAfterPostSaveEdit: metrics.dirtyAfterPostSaveEdit,
    dirtyAfterJoinSave: metrics.dirtyAfterJoinSave,
    dirtyAfterSecondSave: metrics.dirtyAfterSecondSave,
    promptAfterAltR: metrics.promptAfterAltR,
    promptAfterRestoreNo: metrics.promptAfterRestoreNo,
    dirtyAfterRestoreNo: metrics.dirtyAfterRestoreNo,
    saveModifierBits: metrics.saveModifierBits,
    modifierBits: metrics.modifierBits,
    rawPrimary: metrics.rawPrimary,
    rawSecondary: metrics.rawSecondary,
    translatedKey: metrics.translatedKey,
    saveTranslatedKey: metrics.saveTranslatedKey,
    quitTranslatedKey: metrics.quitTranslatedKey,
  };
  writeFileSync(SUMMARY_PATH, `${JSON.stringify(summary, null, 2)}\n`);
  console.log(JSON.stringify(summary, null, 2));
}

async function runScriptedSession(bytes: Uint8Array, symbols: D8Symbol[]): Promise<void> {
  const scriptStartAddr = symbolAddress(symbols, 'ScriptStart');
  const doneAddr = symbolAddress(symbols, 'MainDone');
  const resultAddr = symbolAddress(symbols, 'MainResultMarker');
  const errorAddr = symbolAddress(symbols, 'MainErrorMarker');
  const caseAddr = symbolAddress(symbols, 'MainCaseMarker');
  const { runtime, platformRuntime } = loadTec1gRuntime(bytes, {
    imagePath: IMAGE_PATH,
    startAddress: scriptStartAddr,
    sysModeShadowOff: true,
  });
  const instructions = runUntil(runtime, platformRuntime, doneAddr);
  const resultMarker = runtime.hardware.memory[resultAddr];
  if (resultMarker !== PROOF_PASS) {
    const catalogSector = symbolAddress(symbols, 'EditorLoadCatalogSectorOffset');
    const catalogEntry = symbolAddress(symbols, 'EditorLoadCatalogEntryOffset');
    const sourcePathPtr = symbolAddress(symbols, 'EditorLoadSourcePathPtr');
    const catalogSectorValue = readWord(runtime.hardware.memory, catalogSector);
    const catalogEntryValue = readWord(runtime.hardware.memory, catalogEntry);
    const sourcePathValue = readWord(runtime.hardware.memory, sourcePathPtr);
    throw new Error(
      `Debug80 editor session failed result=0x${resultMarker.toString(16)} case=${runtime.hardware.memory[caseAddr]} error=0x${runtime.hardware.memory[errorAddr].toString(16)} catalogSector=0x${catalogSectorValue.toString(16)} catalogEntry=0x${catalogEntryValue.toString(16)} sourcePath=${JSON.stringify(readAsciiZ(runtime.hardware.memory, sourcePathValue))}`,
    );
  }

  const source = readTm8File('/src/main.asm');
  const backup = readTm8File('/src/.main.asm.b');
  const savedRecord0 = readBufferSourceRecord(source, 0);
  const backupRecord0 = readBufferSourceRecord(backup, 0);
  if (savedRecord0 !== 'ABR0 LINE 00') {
    throw new Error(`saved source record 0 "${savedRecord0}", expected "ABR0 LINE 00"`);
  }
  if (backupRecord0 !== 'R0 LINE 00') {
    throw new Error(`backup source record 0 "${backupRecord0}", expected "R0 LINE 00"`);
  }

  const glcd = getGlcdBytes(platformRuntime);
  if (!glcd.some((value) => value !== 0)) {
    throw new Error('Debug80 editor session left the GLCD blank');
  }
  writeGlcdCapture(glcd);

  const summary = {
    result: 'ok',
    instructions,
    image: IMAGE_PATH,
    glcdCapture: GLCD_CAPTURE_PATH,
    savedRecord0,
    backupRecord0,
  };
  writeFileSync(SUMMARY_PATH, `${JSON.stringify(summary, null, 2)}\n`);
  console.log(JSON.stringify(summary, null, 2));
}

async function main(): Promise<void> {
  ensureSessionImage();
  if (process.argv.includes('--prepare-only')) {
    const summary = {
      result: 'ok',
      preparedOnly: true,
      image: IMAGE_PATH,
    };
    writeFileSync(SUMMARY_PATH, `${JSON.stringify(summary, null, 2)}\n`);
    console.log(JSON.stringify(summary, null, 2));
    return;
  }

  const { bytes, symbols } = await compileMain();
  if (process.argv.includes('--live-smoke')) {
    await runLiveSmoke(bytes, symbols);
    return;
  }
  await runScriptedSession(bytes, symbols);
}

main().catch((error: unknown) => {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 1;
});
