# TECM8 Codebase Tour

This is a first-pass tour of the TECM8 repository as it stands. It is meant to
help a reader find their way around the current code, especially the Z80 source
tree, without pretending the project is finished. The project is still
proof-driven: many files are deliberately small modules or harnesses that prove
one boundary before the full shell, editor, assembler, and runner exist.

## Big Picture

TECM8 is a Z80 assembly development environment for the TEC-1G. The intended
first product is a Turbo Pascal-like edit/assemble/run workflow on the machine:
a project has a main source file, `edit` opens source, `asm` builds it, and
`run` launches the derived output.

The current codebase is split into four working layers:

- `src/`: Z80 assembly modules for the TEC-side shell, project config reader,
  MON3-backed BIOS wrappers, structured GLCD display, source-page loading,
  editor navigation, and early editor interaction.
- `proofs/`: Z80 proof programs that include `src/` modules and exercise one
  behavior under Debug80/MON3.
- `tools/`: TypeScript host tools for TM8 volume formatting, project setup,
  source-record conversion, proof runners, and MON3 decomposition reports.
- `docs/`: design notes, contracts, and generated reports that explain the
  intended system and keep the implementation honest.

The main dependency direction is:

```text
host fs tools -> create TM8 volumes and FAT32 proof images
proof runners -> assemble proof programs and run Debug80
Z80 proof files -> include src modules
src modules -> call PascalCase BIOS wrappers
BIOS wrappers -> call MON3 storage and GLCD services
```

## Reading Order

For the fastest orientation, read these files first:

1. `docs/roadmap.md`: live phase tracker and next milestone.
2. `docs/codebase.md`: this tour of the current implementation.
3. `docs/virtual-filesystem.md`: exact `VOLUME.TM8` byte layout, source record
   model, hidden-file policy, and host preservation tools.
4. `docs/shell-command-contract.md`: how `edit`, `asm`, and `run` resolve.
5. `docs/editor-design.md`: 32-byte source records and GLCD viewport model.
6. `docs/tecm8-bios-api.md`: the BIOS wrapper vocabulary used by Z80 code.
7. `src/tecm8-equates.asm`: shared source-record, sector, display, GLCD, and
   keyboard modifier constants used by the Z80 modules.
8. `src/tecm8-record.asm`: shared fixed source-record helpers for masked
   length reads, metadata-preserving length writes, padding zeroing,
   full-record clear, in-record text shifts, and up/down record-window shifts.
9. `src/tecm8-string.asm`: shared byte/string/path helpers used by storage,
   project config, and shell path-resolution code.
10. `src/tecm8-storage.asm`: shared TM8 format helpers used by storage-backed
    loaders.
11. `src/tecm8-bios.asm`: the current MON3-backed wrapper implementation.
12. `src/shell-resolver.asm`: shell command resolution and executor stubs.
13. `src/shell-program.asm`: the proof/live prompt loop and input buffer layer.
14. `src/shell-commands.asm`: compatibility include for code that still wants
    the complete shell.
15. `src/shell-editor-launch.asm`: the bridge from shell resolution into the
   editor.
16. `src/glcd-tile.asm` and `src/display-model.asm`: the current direct GLCD
   cell layer and the structured screen renderer built on top of it.
17. `src/editor-storage-loader.asm`, `src/editor-navigation.asm`,
    `src/editor-block-state.asm`, `src/editor-viewport.asm`,
    `src/editor-record.asm`, `src/editor-line-edit.asm`, `src/editor-block.asm`,
    `src/editor-keymap.asm`, `src/editor-cursor.asm`, `src/editor-prompt.asm`,
    `src/editor-render.asm`, and `src/editor-interaction.asm`: the current editor
    path.
18. `proofs/display/glcd-tile-proof.asm`,
    `proofs/display/editor-selection-proof.asm`, and
    `proofs/display/editor-line-editing-proof.asm`: focused proofs for the tile
    cell renderer, the current block-editing state, and the fixed-record line
    editing behavior.

## Z80 Source Tree

The `src/` tree is the TEC-side implementation. Files ending in `.asm` contain
code, state, labels, and AZMDoc `;!` register contracts for routines TECM8
owns. Files ending in `.asmi` are only for external code that is not available
as annotated source; currently `src/mon3.asmi` documents the MON3 ROM entry
points called by the TECM8 BIOS wrappers.

The current assembly style follows `docs/azm-style-guide.md`: callable routine
entries and ordinary labels are PascalCase, while `.equ` constants use
uppercase names with underscores. The TECM8 modules should not create duplicate
`.asmi` manifests for code in this repository; AZM can read the local `;!`
contract blocks from the included source.

### `src/tecm8-equates.asm`

This is the byte-free shared equate surface. Top-level programs and proof
bundles include it once before including TECM8 modules. It owns values that must
not drift across modules:

- source record geometry: 32-byte records, 31 text characters, `0x1F` length
  mask, `0xE0` metadata mask, and 16 records per 512-byte page
- shared sector size
- GLCD tile/display geometry: 20 columns, 10 rows, 6x6 cells, 2-pixel vertical
  origin, and 16-byte bitmap rows
- MON3 GLCD `VPORT` and `TGBUF` addresses
- matrix keyboard modifier bits

Module-local names such as `TECM8_EDITOR_RECORD_BYTES`,
`TECM8_GLCD_TILE_ROWS`, and `TECM8_BIOS_KEY_MOD_CTRL` remain where they clarify
the domain, but they derive from this shared file rather than repeating the
literal values.

### `src/tecm8-record.asm`

This is the shared byte-level helper module for fixed source records. A source
line is a 32-byte record: byte 0 stores a 5-bit text length and 3 metadata bits,
followed by up to 31 text bytes. The helper module owns the small operations
that must treat that format consistently:

- read an effective length by masking with `TECM8_SOURCE_RECORD_LENGTH_MASK`
- write an effective length while preserving metadata bits 5-7
- zero padding bytes after a record's effective length
- clear a full 32-byte record
- shift text bytes left or right within one record
- shift contiguous record windows up or down

`src/editor-record.asm` exposes the editor-facing `EditorKey*Record*` entry
points as compatibility wrappers around these shared helpers, plus current-row
addressing helpers and line-edit scratch bytes. Proof bundles include
`src/tecm8-record.asm` once before the editor modules.

### `src/tecm8-string.asm`

This is the first shared byte/string/path helper module. It currently owns:

- `Tecm8StringMatchBytes`, a bounded byte comparison used by
  `src/project-config-loader.asm` and `src/editor-storage-loader.asm` when
  matching TM8 magic bytes, prefix names, and catalog names. The helper keeps
  the existing storage convention: carry clear means match, carry set means
  mismatch.
- `Tecm8StringCopyNulBounded`, a bounded NUL-terminated string copier. It is
  used behind shell and editor-navigation wrappers so each caller can keep its
  own error code and saved write-pointer policy without duplicating the byte
  loop.
- `Tecm8StringSkipSpaces`, an ASCII-space scanner used by shell parsing paths
  to advance `HL` past ordinary spaces without carrying shell-specific state.
- `Tecm8StringFindLocalName`, a NUL-terminated path scanner that returns `HL`
  at the byte after the final slash. The shell build-output resolver uses it to
  derive `/build/<stem>.bin` and `/build/<stem>.map` from source paths.

Proof bundles that include loaders or shell code directly include
`src/tecm8-string.asm` before those modules, but after their entry trampolines so
standalone proof targets still start at `4000h`.
`proofs/shared/tecm8-string-proof.asm` directly verifies the bounded-copy
helper's zero-capacity, exact-fit, and overflow cases through
`npm run proof:tecm8-string`.

### `src/tecm8-storage.asm`

This is the first shared TM8-format helper module. It owns the canonical v1 TM8
layout constants, the `TECM8VOL` magic bytes,
`Tecm8StorageValidateCoreSuperblock`, `Tecm8StorageAdvanceSectorOffset`, and
`Tecm8StorageReadSectorPreserveOffset`, the narrow MON3 sector-scan helpers used
by project config, editor storage, and file listing. It also owns
`Tecm8StorageAdvancePrefixEntryPtr` and
`Tecm8StorageAdvanceCatalogEntryPtr`, which advance table entry pointers while
preserving the current scan offset in `DE`. It also owns
`Tecm8StorageBlockToOffset`, the 4K TM8 block-number to MON3 `HLDE` byte-offset
conversion used by `src/project-config-loader.asm`, and
`Tecm8StorageBlockSectorToOffset`, the block-plus-sector variant used by editor
source page reads and writes. The code is intentionally format-level only:
callers still own their own error codes, extra validation needs, and storage
write policy.

Proof bundles that include storage loaders directly include
`src/tecm8-storage.asm` after `src/tecm8-string.asm` and before the loader.
This keeps the Q4 storage layer narrow while removing duplicated bytecode from
the two live readers.

### `src/main.asm`

This is now the Debug80-testable TECM8 editor session entry. It runs at `4000h`
under the TEC-1G/MON3 profile. `Start` jumps to
`LiveStart`, which initializes the GLCD, resolves `edit`, resets the cursor,
and enters `EditorRunLive` for manual matrix-key testing against the real
storage-backed editor path. The automated save/reopen proof has moved to
`src/editor-session-script.main.asm` so the live image does not carry the
script entry and key-stream fixture data. Both targets include the real project
config loader and storage-backed editor path rather than a stub.

### `src/editor-session-script.main.asm`

This is the Debug80 automated editor-session target. It also starts at `4000h`
but enters `ScriptStart`, opens the project main source through `edit`, inserts
a small visible edit, saves, quits, reopens the same file, and leaves the final
editor screen visible. `tools/run-debug80-editor-session.ts` compiles this
target for the default automated session and compiles `src/main.asm` for live
and block smoke testing.

### `src/keyboard-tester.main.asm`

This is a standalone Debug80/TEC-1G keyboard diagnostic target. It also starts
at `0x4000`, initializes the GLCD tile display, and then polls
`BiosInputPollKey` forever. Each key event is appended to a small on-screen
history so Debug80 mouse-matrix input and physical-keyboard input can be
compared without involving the editor. Ctrl chords render as `^X`; Alt chords
render as `\X`. Arrow keys render as `^`, `_`, `<`, and `>`, not alphabet
aliases. Each history entry includes the raw matrix `D/E` bytes in hex
before the interpreted token so translated-token issues can be separated from
raw Debug80 matrix mapping issues.

### `src/tecm8-bios.asm` and `src/mon3.asmi`

These are the stable service boundary under TECM8 code. The implementation is
currently a thin MON3 compatibility layer:

- `BiosFileOpen`
- `BiosFileReadSector`
- `BiosFileWriteSector`
- `BiosInputPollAscii`
- `BiosInputPollKey`
- `BiosDisplayInit`
- `BiosDisplayClear`
- `BiosDisplaySetCursor`
- `BiosDisplayPutChar`
- `BiosDisplayPutString`
- `BiosDisplayDrawCharAt`
- `BiosDisplayUpdate`
- `BiosDisplaySetBitmapMode`

The wrappers depend on MON3 entry points such as `F5A1h` for file open,
`F5D5h` for sector read, `F66Dh` for sector write, and MON3 GLCD routines in
the `D8xxh` to `DCxxh` range. `BiosInputPollKey` also wraps the MON3 matrix
scanner path, returns translated keys with TECM8 modifier bits, exposes the raw
scan bytes for diagnostics, and normalizes Ctrl+A..Z into the ASCII control
codes consumed by the editor command loop. Higher-level code should call the
wrapper names, not hard-code MON3 addresses. `BiosDisplayInit` still enters the
MON3 terminal path first, then clears and plots the graphics buffer so TECM8
starts from a known GLCD image. `BiosDisplayClear` now only clears and plots
the active graphics buffer, which preserves MON3's terminal cursor policy while
the tile renderer redraws the screen.

`src/mon3.asmi` documents the external MON3 symbols that are not implemented in
this repository. The TECM8 wrapper routines themselves live in
`src/tecm8-bios.asm` and carry their contracts in local `;!` blocks.
The previous local-module interface files have been removed; `mon3.asmi` is the
only interface file currently expected under `src/`.

### `src/project-config.asm`

This parses the loaded `/tecm8.prj` project file. It does not perform I/O. The
expected v1 format is:

```text
tm8project=1
main=/src/main.asm
```

`ParseProjectConfig` takes `HL` pointing at zero-terminated config text, `DE`
pointing at an output buffer, and `B` as output capacity. It validates the
canonical line order and copies the `main` path. Error codes distinguish bad
header, bad main line, empty value, long output, and extra content.

This parser is intentionally simpler than the host parser in `tools/fs.ts`.
The host tool accepts and validates key/value metadata broadly; the Z80 parser
currently accepts the canonical v1 order only.

### `src/project-config-loader.asm`

This connects project config parsing to real storage. `LoadProjectConfig` opens
`VOLUME.TM8` through `BiosFileOpen`, reads sector 0 to validate the
fixed v1 superblock fields it depends on, scans the root file catalog for
`tecm8.prj`, reads the first data sector of that file, NUL-terminates the text
in a fixed buffer at `0x0A00`, and calls `ParseProjectConfig`.

It relies on the v1 TM8 layout:

- catalog starts at block 6, sector 48
- catalog entries are 64 bytes
- root prefix id is 0
- `/tecm8.prj` is a root file named `tecm8.prj`

The loader is deliberately narrow. It reads only one sector of project config
text and is not a general TM8 filesystem implementation.

### `src/shell-resolver.asm`

This is the current shell resolver and executor-stub layer. It does not yet
launch a real assembler or runner. It does enough to prove the shell command
contract without pulling in the interactive prompt program:

- `edit`, `asm`, and `run` are recognized
- default commands load the cached project main path from `/tecm8.prj`
- explicit source arguments get `.asm` appended when no extension is present
- `asm` derives `/build/<stem>.bin` and `/build/<stem>.map`
- `run` derives or copies the runnable path
- executor stubs store `ShellLastExecAction` and `ShellLastExecRequestPtr`

Important state:

- `ShellMainPath`: cached project main path
- `ShellProjectStatus` and `ShellProjectError`: project config load state
- `ShellCurrentPrefix`: currently hard-coded as `/src/`
- `ShellStepDispatch`: dispatch block used by command execution
- `ShellLastExecAction` and `ShellLastExecRequestPtr`: proof-visible result

The resolver depends on an external `LoadProjectConfig` routine. Storage-backed
proofs include `project-config-loader.asm`; some command-only proofs stub
`LoadProjectConfig` so they can test parsing without MON3.

### `src/shell-program.asm`

This is the interactive shell program and prompt/input skeleton. It is included
after `shell-resolver.asm` when a proof or future live shell needs prompt-loop
behavior:

- line input is copied into a bounded command buffer
- `RunShellProgramEntry` initializes the shell state and runs one prompt cycle
- `RunShellProgramCycles` runs a bounded sequence for proofs
- `ReadShellKey` is still a seed-stream provider, not the final matrix keyboard
  shell input implementation

The live editor image currently includes `shell-resolver.asm` directly and does
not include this prompt layer.

### `src/shell-commands.asm`

This is now only a compatibility include that pulls in `shell-resolver.asm` and
`shell-program.asm`. New code should include the smaller module it actually
needs.

### `src/shell-editor-launch.asm`

This is the bridge from the shell resolver into the storage-backed editor.
`ShellRunEditorLine` runs one shell command line and only proceeds if
the resolved action is `SHELL_CMD_EDIT`. It then reads the edit request payload
and calls `EditorOpenPath`. If the open fails with `EDITOR_LOAD_ERR_FIND`, it
creates a one-block source file in the existing prefix and retries the open.
Missing prefixes still fail; this path is for normal project cases such as
`edit fresh` inside `/src`.

This file is where shell-to-editor composition starts. `asm` and `run` are
still unsupported here because no assembler or runner exists yet.

### `src/shell-editor-session.asm`

This proof-oriented helper runs one shell edit command line, resets the cursor,
then passes a NUL-terminated translated-key stream to `EditorRunKeys`.
`src/editor-session-script.main.asm` includes it; the live editor image does
not.

### `src/display-model.asm`

This is the structured GLCD screen renderer. It renders an editor-like screen
on top of the tile-cell layer:

- rows 0-9 are editable source rows in the current 6x6 profile
- row 9 can be temporarily redrawn as a prompt/status overlay
- a 4-pixel gutter carries marker flags
- text is drawn as 20 columns of MON3 6x6 glyphs

The main entry points are:

- `DisplayInit`
- `DisplayRenderScreen`
- `DisplayRenderLine`
- `DisplayRenderGutter`
- `DisplayRenderCursorCell`
- `DisplayEraseCursorCell`

The cursor routines save and restore the original GLCD bytes under the cursor,
which prevents cursor trails when the cursor moves. Cursor render and erase now
mark only the affected cell byte range dirty through `GlcdTileMarkCellDirty`;
the cooperative GLCD stepper then transfers that byte span rather than a whole
text row. This module depends on the MON3 terminal graphics buffer at `0x13C0`,
shares the tile layer's 6x6 cell geometry, and pushes full-screen updates
through `BiosDisplayUpdate`.

The gutter markers are now live editor state rather than proof-only
placeholders. An ordinary whole-line selection draws a thin bar, the current
row adds the current-line bar, a pending copy source draws a thick bar, and a
pending move source draws the sawtooth edge. The viewport composes those marker
bits for every visible row and the interaction layer updates them as cursor
movement, selection movement, and pending source state change.

### `src/glcd-tile.asm`

This is the direct GLCD tile-cell layer under the structured renderer. It
writes TECM8-owned 6x6 character cells straight into MON3's `TGBUF` bitmap,
uses the ROM font data at `0xDD9B`, and relies on the BIOS layer for display
initialization and full-screen flushes. It does not call MON3's terminal glyph
drawing path, so TECM8 owns cell overwrite, clear, and text-run behavior
directly. Row flushes are now TECM8-owned ST7920 transfers: one editor text row
writes the six physical GLCD rows, 16 bytes per physical row, through ports
`0x07` and `0x87`. Current entry points include `GlcdTileClearCell`,
`GlcdTileDrawCell`, `GlcdTileDrawTextRun`, `GlcdTileClearTextRow`,
`GlcdTileFlushFull`, `GlcdTileFlushRow`, and the cooperative dirty row/cell
scheduler.

Public entries:

- `GlcdTileClearCell`
- `GlcdTileDrawCell`
- `GlcdTileDrawTextRun`
- `GlcdTileFlushFull`
- `GlcdTileFlushRow`
- `GlcdTileQueueRow`
- `GlcdTileMarkRowDirty`
- `GlcdTileMarkCellDirty`
- `GlcdTileMarkGutterDirty`
- `GlcdTileStep`
- `GlcdTilePrepareCell`

`GlcdTilePrepareCell` validates the `20 x 10` cell bounds and maps a row and
column to the first backing-bitmap byte plus bit offset. The draw and clear
paths then walk six rows of six pixels with local set and clear mask tables.
`GlcdTileFlushFull` writes `TGBUF` to the active viewport pointer and calls
`BiosDisplayUpdate`, which keeps the visible GLCD in sync with the TECM8-owned
bitmap state after full viewport renders. `GlcdTileFlushRow` bypasses MON3
`plotToLCD` and transfers only one six-pixel text row, so cursor movement,
status overlays, and row-local edits avoid the old full-screen blank/repaint
path.

The row-transfer path now also has a cooperative surface. `GlcdTileQueueRow`
sets up one text row immediately, while `GlcdTileMarkRowDirty` records row
numbers in a compact dirty mask for later transfer. `GlcdTileStep` starts the
next marked row when no transfer is pending, then transfers one physical GLCD
row per call. `GlcdTileFlushRow` is kept as the synchronous compatibility
wrapper: it first drains any already pending cooperative work, then queues the
requested row and drains all six steps before returning. The live editor idle
loop calls `GlcdTileStep`, so current-line edits and block-marker changes can
schedule GLCD work and return to matrix keyboard polling while the display
drains in bounded slices.

The same stepper also understands dirty cell byte ranges. `GlcdTileMarkCellDirty`
validates a row/column, computes the GLCD byte column touched by the 6-pixel
cell, coalesces the minimum and maximum dirty bytes for that row, and lets
`GlcdTileStep` transfer only that byte span across the six physical rows. Cursor
overlay render/erase uses this path, so ordinary horizontal cursor movement and
post-edit cursor restore/redraw no longer require full text-row transfers.
`GlcdTileMarkGutterDirty` uses the same scheduler for the left gutter byte pair
when selection or pending copy/move markers change.

This module is the current boundary between TECM8 display policy and MON3 GLCD
transport. Higher-level display code can stay in row and column coordinates
instead of issuing per-glyph MON3 terminal calls.

### `src/editor-viewport.asm`

This converts source records into a screen descriptor for the display model.
Source records are fixed 32-byte Pascal strings:

```text
byte 0      low five bits = length, upper three bits = reserved metadata
byte 1-31   text bytes
```

The implementation reads the visible length with `0x1F` and preserves bits 5-7
when existing line lengths are rewritten. New or cleared source records normally
start with metadata bits clear. The upper bits are intended for compact
per-line editor/debugger state such as selection, breakpoint, or wrap flags.

`EditorViewportRender` takes `HL` pointing at a 16-record source page/window,
starts at `EditorViewportTopRow`, copies ten visible records into
NUL-terminated row buffers, masks each record length to the low five bits, then
calls `DisplayRenderScreen`.
`EditorViewportRenderRecordRow` performs the same record-to-row conversion for
one visible row and calls `DisplayRenderLine`, which is the dirty-rendering path
used by ordinary in-line editor mutations.

This module now owns the viewport-facing selection projection. It maps visible
rows back to absolute page-line numbers, tests whether those lines fall inside
the current ordinary selection, and layers pending copy or move source markers
over the same rows. It is still only a viewport and marker surface: persistent
selection intervals and pending-source state live in `editor-block-state.asm`,
with mutation in `editor-block.asm`; viewport keeps only normalized/projection
scratch needed to answer visible-row marker queries.

### `src/editor-storage-loader.asm`

This is the first storage-backed source loader. It opens `VOLUME.TM8`, validates
the v1 superblock fields it depends on, resolves a TM8 path into prefix and
local filename, scans prefix and catalog tables, follows allocation entries,
and copies one 512-byte page to a caller buffer.

Public entries:

- `EditorLoadMainSector`: first sector of `/src/main.asm`
- `EditorLoadMainPage`: page `A` of `/src/main.asm`
- `EditorLoadSourcePage`: page `A` of an arbitrary TM8 path in `DE`
- `EditorSaveSourcePage`: save caller buffer `HL` to page `A` of path `DE`
- `EditorCreateSourceFile`: create a one-block source file at path `DE` in an
  existing prefix

Page indexes are limited to 0..127. A page is a 512-byte sector, not a 4K TM8
allocation block. The loader computes the sector-in-block and number of block
links to follow. It depends on MON3's `DISK_BUFF` at `0x0600` through the BIOS
storage wrappers.

The save entry follows the same narrow path resolution as the loader. It finds
the target TM8 file, resolves the requested page to the corresponding
file-relative sector, reads that sector first to establish MON3's write context,
copies the caller's 512-byte buffer into `DISK_BUFF`, and then calls
`BiosFileWriteSector`. Save can grow the catalog byte size and, when a save
steps past the end of the current 4K block chain, allocate a new TM8 data block,
mark it end-of-chain, link it from the previous block, and update the
superblock free-block count/checksum.

`EditorCreateSourceFile` adds the narrow create path needed by editor backups:
it finds a free data block, marks that allocation entry as end-of-chain, writes
a catalog entry, and updates the superblock free block count/checksum. It
assumes the prefix already exists and creates a single 4K source file; it is not
a general remove, rename, directory creation, or truncation API.

This is still proof-focused. It reads pages, follows existing block chains,
writes existing and newly grown pages, and can create the one-block backup
files the editor needs. It is not yet a general TM8 filesystem layer.

### `src/editor-navigation.asm`

This owns the editor's current path and current page. It layers simple page
navigation on top of `editor-storage-loader.asm` and `editor-viewport.asm`.

Public entries:

- `EditorOpenMain`
- `EditorOpenPath`
- `EditorRenderCurrent`
- `EditorRenderPageBuffer`
- `EditorSaveCurrentPage`
- `EditorBackupCurrentPage`
- `EditorClearDirty`
- `EditorPageDown`
- `EditorPageUp`
- `EditorNavDeriveBackupPath`

The module stores a 64-byte path buffer and legacy aggregate `EditorNavDirty`.
The source-sector buffers now live in a fixed workspace at `3000h-37FFh`:
previous-page cache at `3000h`, active page at `3200h`, adjacent next page at
`3400h`, and backup/save scratch at `3600h`. This keeps the 2K resident source
workspace below the `4000h` MON3 launch address and away from MON3's lower
GLCD/storage volatile RAM. `EditorNavDirtySectors` tracks the active/next
sector dirty bits, while `EditorNavCachedPageDirty` preserves dirty state for
the previous-page cache. This is now a small two-sector edit window plus one
previous-page cache: page-down/page-up movement can stay in RAM, and dirty
movement no longer forces an immediate save. The RAM policy is tracked in
[Memory and Code Quality Manifest](memory-and-code-quality.md).

`EditorNavViewportTopRow` is the logical source row currently shown at GLCD
visible row 0. `EditorRenderPageBuffer` calls `EditorNavSyncViewport` before
rendering so the viewport module and cursor marker agree on the visible row.
The interaction layer keeps `EditorCursorRow` as the logical record row 0-15
and `EditorCursorVisibleRow` as the row 0-9 actually drawn on the GLCD.
Cursor up/down can therefore move through all 16 records of the loaded page
while scrolling the 10-row viewport when needed.
`EditorCursorCol` is the logical source column 0-30, while
`EditorCursorVisibleCol` is the GLCD text column 0-19. The viewport owns
`EditorViewportColOffset`, so rows render from the visible 20-character slice
of a 31-character source record and pan only when the cursor moves beyond the
visible text columns. The gutter remains outside the horizontal text viewport.

It now also owns the first backup scratch buffers:
`EditorNavBackupPathBuffer` for the derived hidden path and
`EditorNavBackupPageBuffer` for the previous on-disk page. Page moves are
committed only after loading and rendering succeeds, so failed page-down or
page-up attempts do not corrupt current-page state. Cache/window hits render
the already-loaded page buffer directly and skip the transient loading status.
Successful load and save clear the relevant dirty state.

Storage-backed loads, backup restore, and save now also route through
`EditorNavShowStatus`, which renders transient `Loading...` or `Saving...`
text through `EditorViewportRenderStatusOverlay` before the storage call and
restores the hidden source row afterward. The status overlay shares row 9 with
the editor prompt path, so slow navigation and save operations present visible
feedback without adding a second status surface.

Editor/storage failures now route through `EditorNavShowError`, which maps the
existing compact error codes to short status-row messages. Examples include
`ERR OPEN 30`, `ERR VOL 31`, `ERR FIND 33`, `ERR SIZE 34`, `ERR READ 35`,
`ERR ALLOC 36`, `ERR PAGE 37`, `ERR WRITE 38`, and `ERR FULL 39`. The routine
also records `EditorLastErrorCode` and `EditorLastErrorTextPtr`, giving Debug80
and hardware diagnostics a stable place to inspect the last surfaced error.
The live entry path calls this before falling into its failure loop, and the
interactive key loop shows save/navigation failures without silently accepting
the key and leaving the display unexplained.

`EditorSaveCurrentPage` is the current save coordinator. It first backs up the
active page, any dirty cached previous page, and any dirty resident adjacent
next page; if those backups succeed, it writes dirty resident sectors from the
active, adjacent, and cached buffers back to their source pages and clears
dirty. `EditorBackupCurrentPage`
derives the hidden backup path from the current source path, loads the current
on-disk page into `EditorNavBackupPageBuffer`, and writes that old page to the
backup path. If the backup path is missing, it asks the storage loader to
create a one-block file first, then retries the backup write. Backup writes use
the same growing save path as source writes, so a backup can extend across 4K
allocation boundaries. This is still a resident-window backup policy rather
than a whole-file copy policy; truncation/freeing behavior remains future work.

`EditorNavDeriveBackupPath` implements the current naming convention. It keeps
the original prefix, prepends `.` to the local filename, and appends `.b`.
For example, `/src/main.asm` becomes `/src/.main.asm.b`. It fails with
`TECM8_EDITOR_NAV_ERR_BACKUP` if the path is malformed or the derived name does
not fit the fixed path buffer.

`EditorLoadCurrentBackupWindow` uses the same derived path convention and
loads the hidden backup into `EditorNavPageBuffer`. When the adjacent next-page
window is resident, it also reloads `EditorNavNextPageBuffer` from backup and
marks both restored sectors dirty so a later save writes the restored content
back to the source file.

### `src/editor-cursor.asm`

`src/editor-cursor.asm` owns the editor cursor overlay and blink behavior.
It keeps the public cursor entry points stable while removing that logic from
the interaction monolith:

- `EditorCursorReset`
- `EditorCursorResetState`
- `EditorCursorResetStateKeepSelection`
- `EditorRenderCursor`
- `EditorHideCursor`
- `EditorCursorBlinkReset`
- `EditorCursorBlinkStep`
- `EditorInvalidateCursorOverlay`

The cursor is a one-pixel XOR insertion bar drawn one pixel before the active
6x6 cell, with a cooperative blink state.
`EditorCursorBlinkReset` arms a 16-bit idle countdown after key handling
renders the cursor. The live idle path first runs one `GlcdTileStep`; only when
that reports no remaining queued display work does it call
`EditorCursorBlinkStep`. When the countdown expires, blink hides or restores
the cursor through the same dirty cell byte-range path used by ordinary cursor
movement. The countdown is intentionally long enough to avoid the cursor
blending into a grey high-speed flicker in Debug80. The proof-visible
`EditorCursorBlinkToggleCount` lets emulator proofs assert that blink toggles do
not use row or full-screen flushes.

The cursor module still uses cursor state bytes currently stored with the
interaction state block. Later Q5 decomposition can move those bytes beside the
cursor routines once the larger block, line-edit, render, and prompt slices are
also separated.

### `src/editor-keymap.asm`

`src/editor-keymap.asm` owns translated key normalization and modified-command
lookup. It keeps alphabetic navigation out of the editor: movement comes from
matrix arrow key bytes, while Ctrl-modified printable letters are mapped to
editor commands before printable insertion.

The public entries are:

- `EditorActionFromKey`: maps arrow keys, with Ctrl+ArrowUp and
  Ctrl+ArrowDown converted to page actions.
- `EditorModifiedCommandFromKey`: maps Ctrl-S, Ctrl-Q, Ctrl-Z, Ctrl-C,
  Ctrl-X, Ctrl-V, and Ctrl-Y into editor command bytes.
- `EditorShouldIgnoreModifiedPrintable`: suppresses unknown Ctrl-modified
  printable letters so a failed command chord does not insert text.

The keymap module still reads `EditorPendingChar` and `EditorPendingModifier`
from the interaction state block. That keeps this checkpoint behavior-only and
avoids moving shared state before the block, prompt, and line-edit modules have
their own ownership boundaries. The source-level contract is pinned by
`tools/editor-interaction.test.ts`, and the live editor acceptance proofs now
include `src/editor-interaction.asm`, then `src/editor-record.asm`, then
`src/editor-line-edit.asm`, then `src/editor-block.asm`, then
`src/editor-keymap.asm`, then `src/editor-cursor.asm`, then
`src/editor-prompt.asm`, then `src/editor-render.asm`, so the storage-backed
editor runners exercise the same normalized command path as the real session
target.

### `src/editor-prompt.asm`

`src/editor-prompt.asm` owns status-line yes/no prompts and their completion
dispatch. The public entries are:

- `EditorPromptAskYesNo`: arms a prompt using caller-provided NUL-terminated
  text and renders it through the status overlay.
- `EditorPromptHandleKey`: accepts `Y`/`y`, `N`/`n`, or ESC and leaves unknown
  keys modal.
- `EditorPromptDispatch`: converts a completed prompt into the pending restore,
  quit, or delete-block action.

The prompt module reads prompt-active/result/text-pointer state from
`src/editor-viewport.asm` and the pending prompt action byte from
`src/editor-interaction.asm`. It also calls back into editor actions such as
backup restore, dirty rerender, and selected-block deletion. That is intentional
for this checkpoint: prompt control flow is isolated, while selected-block
deletion is dispatched to `src/editor-block.asm`.

### `src/editor-render.asm`

`src/editor-render.asm` owns the dirty render policy between editor state and
the direct GLCD tile layer. It contains:

- `EditorKeyRenderDirty`, which marks the current sector dirty, hides the cursor,
  keeps row/column viewports in range, and rerenders the page buffer.
- `EditorKeyRenderCurrentLineDirty` and
  `EditorKeyRenderCurrentLineCellsDirty`, which repaint the current source row
  and mark the affected dirty row or dirty cell span.
- cursor movement render helpers, which either update only gutter/cursor cell
  ranges or fall back to the full viewport render when scrolling changes the
  visible window.
- `EditorEnsureCursorVisible`, `EditorEnsureCursorVisibleColumn`,
  `EditorLogicalRowVisible`, and `EditorMarkDirty`.

The module still calls editor-record helpers such as `EditorKeyCurrentRecord`
and still reads cursor state that has not yet been moved beside the cursor
module.

### `src/editor-record.asm`

`src/editor-record.asm` is the editor-facing layer above `src/tecm8-record.asm`.
It owns:

- `EditorKeyCurrentRecord` and `EditorKeyRecordAtRow`, which calculate fixed
  32-byte source-record addresses inside `EditorNavPageBuffer`.
- thin editor wrappers for masked length read/write, record padding zeroing, and
  full-record clear.
- `EditorKeyAdvanceCursor`.
- record-operation scratch bytes such as `EditorRecordBase`, `EditorLineSrc`,
  `EditorLineDest`, `EditorLineRowsLeft`, `EditorLineLength`, and split/join
  length temporaries. Some of this scratch is still shared by block-edit
  row-shift paths until block and line mutation have separate modules.

The actual insert/delete/split/join routines now live in
`src/editor-line-edit.asm`. Block row-shift mutation lives in
`src/editor-block.asm`.

### `src/editor-line-edit.asm`

`src/editor-line-edit.asm` owns fixed-record text mutations for ordinary editor
typing:

- `EditorInsertChar`, `EditorBackspaceChar`, and `EditorDeleteChar`.
- `EditorSplitLine`, including final-row split/growth into the adjacent resident
  page.
- `EditorJoinPreviousLine` and `EditorJoinPreviousPageLine`.

This module is deliberately placed after `src/editor-record.asm` in every include
stack because it uses the editor-facing record wrappers and shared line scratch
state. It still calls navigation routines for cross-page split/join cases; those
calls are part of the current resident editor model and are covered by the
line-editing, mutation-boundary, row-15-growth, and cross-page-join proofs.

### `src/editor-block.asm`

`src/editor-block-state.asm` owns the persistent selection interval and pending
copy/move source bytes. It is intentionally separate from `src/editor-block.asm`
so viewport-only proofs can project markers without linking all block mutation
code.

`src/editor-block.asm` owns whole-line block behavior:

- ordinary selection begin/update/clear over absolute line numbers.
- pending copy/move source arming.
- current-page insert paste and equal-sized replace paste.
- selected block delete.
- gutter marker repaint after selection or pending-source changes.

The viewport still owns marker projection state and helper queries such as
`EditorBlockSelectionNormalize` and `EditorViewportMarkerForRow`. That split is
intentional for this checkpoint: persistent selection data is already outside
the viewport, while viewport-local normalization scratch remains with the code
that answers visible-row marker queries.

### `src/editor-interaction.asm`

This is the early editor interaction loop. It supports both a NUL-terminated
translated-key fixture runner and the live matrix-key path that polls MON3
through `BiosInputPollKey`. In command mode:

- matrix arrows move the cursor
- Ctrl+ArrowDown pages down
- Ctrl+ArrowUp pages up
- Shift+ArrowDown and Shift+ArrowUp extend or shrink an ordinary whole-line
  selection
- Shift+Ctrl+ArrowDown and Shift+Ctrl+ArrowUp extend that selection by
  page
- Ctrl-Q quit the key stream, prompting first when the page is dirty
- Ctrl-S save the currently loaded page
- Ctrl-Z prompt to restore the hidden backup into the current buffer
- Ctrl-C arm the current selection as a pending copy source
- Ctrl-X arm the current selection as a pending move source
- Ctrl-V paste the pending source before the cursor or replace an
  ordinary destination selection
- Escape clears ordinary selection and pending copy/move source markers
- Ctrl-R and Ctrl-W remain reserved for named block read and
  write
- TAB enters insert mode for the stream
- printable ASCII inserts into the current fixed source record
- backspace deletes before the cursor
- newline splits the current fixed source record when there is room in the page
- backspace at column zero joins with the previous record when the result fits
- delete removes the character at the cursor, or prompts before deleting a
  selected whole-line block

The editor interface now exposes the translated-key fixture runner and the live
polling loop from `src/editor-interaction.asm`, plus primitive line-edit entries
from `src/editor-line-edit.asm`:

- `EditorRunLive`
- `EditorInsertChar`
- `EditorBackspaceChar`
- `EditorDeleteChar`
- `EditorSplitLine`
- `EditorJoinPreviousLine`

The editing operations mutate `EditorNavPageBuffer` in memory and then rerender
the current page buffer. The implementation respects 32-byte source records and
the 31-character maximum stored line length. It keeps record padding clear so
host source export can continue validating the fixed-record format. Mutating
operations mark `EditorNavDirty`; Ctrl-S routes through
`EditorSaveCurrentPage` and clear the flag only after the backup and page
write-back succeeds.
Before that save path runs, `EditorHideCursor` removes the XOR cursor overlay
so the transient `Saving...` redraw and the restored edit row do not inherit
stale cursor pixels. A clean save is ignored before any storage call. Ctrl-Z
arms a status-line restore prompt; a yes answer loads the hidden
backup into the current page buffer, rerenders it, and marks it dirty so the
user can inspect before saving. Ctrl-Q exits the key stream
immediately when clean; when dirty, they ask before discarding changes and only
exit on yes.
The key loop dispatches whole-line block commands into `src/editor-block.asm`.
`Shift` movement captures an absolute-line selection interval. `Ctrl-C`
normalizes that interval into a pending copy source, while `Ctrl-X` stores the
same interval as a pending move source. `Ctrl-V` either inserts the pending rows
before the cursor when no destination selection is active, or replaces an
ordinary destination selection when the source and destination are equal-sized
resident-page ranges. Move paste deletes the original source only after the
destination copy succeeds. Overlap and self cases are rejected as no-ops, and
insert paste requires blank tail rows so it cannot silently discard existing
records. `Delete` on a selected block asks `Delete block? Y/N`, then shifts
following records up and clears the vacated tail rows on confirmation. `Escape`
clears ordinary selection and pending copy/move source state without mutating
source records.
Ordinary movement and ordinary character editing clear selection and pending
source state before mutating records.

Full multi-page block editing and arbitrary cross-sector compaction are not
implemented yet. Sector-edge line editing does exist for the common resident
window cases: row-15 split/growth into the adjacent page and Backspace joining
into the cached previous page.
The current live Debug80 smoke now drives the same path through matrix `Enter`,
`Backspace` at column zero, save, page-away/page-back persistence checks, a
clean-save no-op, post-save input, and quit. The block-editing acceptance smoke
boots the live matrix-key path, selects a single line, arms copy, pastes it,
saves, and validates the reshaped TM8 source records from the host side.
Page-boundary movement no longer leaves `Top` or `End` status text behind:
page-up at the first page and page-down past the available source both restore
the hidden source row.

The mutation primitives return a small change result in `A`: `1` means the
buffer changed, `0` means the operation was a no-op, and carry still reports
errors. The key loop uses that result so no-op delete, split, insert, and join
paths do not dirty a clean buffer.

Simple printable insert/delete and non-joining backspace record the logical
source-column range they changed. `EditorKeyRenderCurrentLineCellsDirty`
rerenders the current source row into the GLCD backing buffer, clips that dirty
range to the visible 20-column viewport, and marks only the first and last
affected cells so the GLCD stepper transfers the coalesced byte span. Split,
join, status restore, and viewport-changing edits still use broader redraw
paths.

Horizontal cursor movement only redraws the cursor overlay cell range.
Non-scrolling vertical cursor movement updates only the cursor overlay cell
range; the gutter is reserved for selection and pending copy/move markers.

Dirty row and cell transfers write ST7920 command/data ports directly and do
not reissue the MON3 bitmap-mode setup call for every small transfer. The live
editor enters GLCD bitmap mode through `DisplayInit`, and TECM8's direct tile
renderer assumes no MON3 text-mode terminal routine changes that mode before
dirty row/cell transfers run. Avoiding repeated mode setup keeps cursor blink
from causing a display-wide flicker in Debug80.

`EditorRunLive` renders the cursor, polls one TECM8 key event at a time from
`BiosInputPollKey`, and dispatches that key through `EditorRunModifiedKey` so
the editor sees both the translated key byte and modifier flags. Because the
BIOS layer normalizes Ctrl-letter chords to ASCII control codes, the same
command loop handles proof streams and live Ctrl-S, Ctrl-Q, and Ctrl-Z input.
The editor also checks modified printable command letters before normal
printable insertion, so Ctrl-S/Ctrl-Q/Ctrl-Z are first-class commands and a
host path that reports Ctrl+S as printable `S` plus a Ctrl modifier will not
insert `S` before saving. Ctrl+Up/Down use modifier flags directly
for page movement.

The first backup path is deliberately narrow: `EditorSaveCurrentPage` derives
the hidden backup path (`/src/main.asm` -> `/src/.main.asm.b`), loads the
current on-disk page into `EditorNavBackupPageBuffer`, writes that page to the
backup path, then writes the edited page to the source path. If the backup file
does not exist, it creates a one-block hidden backup file in the existing
prefix. Replacement is just the existing page-write path.

Prompt state is currently split: `EditorPromptActive`, `EditorPromptResult`, and
`EditorPromptTextPtr` live with viewport/status-overlay state in
`src/editor-viewport.asm`, while the pending prompt action byte
`EditorPromptAction` remains in the interaction state block until prompt actions
have clearer module ownership.

`EditorSplitLine` shifts records down within the current 16-record page
and splits the current record at the cursor. When the current sector is full and
the adjacent next-sector buffer has room, it pushes row 15 into next-sector row
0 before splitting. `EditorJoinPreviousLine` is called by backspace at column
zero; it joins the current record into the previous record only when the
combined text still fits in 31 bytes, then shifts following records up and
clears the last record. At row 0, it can join into cached previous-page row 15
and make that previous page active. These sector-edge paths operate only on
resident RAM buffers today; allocating or freeing TM8 storage remains future
work.

## Proof Programs

The `proofs/` tree contains Z80 programs assembled and run by TypeScript proof
runners. Most proof files start at `.org 0x4000`, set `ResultMarker` to `0x42`
on success, and then loop or halt so the runner can inspect memory and display
state.

### Storage Proofs

`proofs/storage/mon3-sector-proof.z80` is the original sketch for proving that
MON3 can open a host-created `VOLUME.TM8`, read file-relative sectors, write
markers into `DISK_BUFF`, and write those sectors back. The maintained runner
is now `tools/run-storage-proof.ts`, which builds an equivalent proof program
directly.

### Project Config Proofs

- `proofs/project-config/project-config-proof.asm` tests
  `ParseProjectConfig` without MON3 storage.
- `proofs/project-config/project-config-storage-proof.asm` tests
  `LoadProjectConfig` against a real FAT32 image containing a TM8 volume and
  `/tecm8.prj`.

These prove the split between parser and loader.

### Shell Command Proofs

`proofs/shell-commands/shell-commands-proof.asm` exercises command resolution
for `edit`, `asm`, and `run`. It stubs `LoadProjectConfig`, then verifies
default project paths, explicit source paths, derived build output paths,
dispatch blocks, executor stubs, prompt state, line input, and error behavior.
It also proves the current shell-loop boundary by running `edit`, `asm`, and
`run` from one initialized prompt session and checking the recorded action
sequence.

### Display And Editor Proofs

The display proofs build up the editor stack incrementally:

- `proofs/display/glcd-smoke-proof.asm`: calls BIOS display wrappers and
  proves visible GLCD output.
- `proofs/display/glcd-tile-proof.asm`: writes TECM8-owned 6x6 cells into
  `TGBUF`, clears and redraws adjacent cells, draws a short text run, and
  proves that the visible GLCD matches the expected ROM glyph rows after
  flushing.
- `proofs/display/structured-screen-proof.asm`: renders a fixed structured
  screen with chrome rows, source rows, and gutter markers.
- `proofs/display/editor-viewport-proof.asm`: converts ten source records
  into display rows.
- `proofs/display/editor-viewport-metadata-record-proof.asm`: verifies that
  source-record metadata bits are ignored by viewport length reads.
- `proofs/display/editor-viewport-storage-proof.asm`: loads source pages from
  TM8 storage and renders them.
- `proofs/display/editor-viewport-storage-invalid-page-proof.asm`: verifies
  invalid page index rejection.
- `proofs/display/editor-viewport-storage-small-file-proof.asm`: verifies EOF
  behavior for too-small files.
- `proofs/display/editor-navigation-proof.asm`: opens `/src/main.asm`, pages
  forward and back, and proves page state survives.
- `proofs/display/editor-viewport-scroll-proof.asm`: moves the logical cursor
  through all 16 records of one source page, proves the viewport scrolls to top
  row 6 for rows 6-15, and proves movement alone does not dirty the editor.
- `proofs/display/editor-horizontal-scroll-proof.asm`: fills one source record
  to 31 characters, proves the logical cursor reaches column 30, proves the
  visible cursor stays at column 19, and proves the rendered row starts at
  column offset 11.
- `proofs/display/editor-selection-proof.asm`: tests Shift-based whole-line
  selection, page-sized selection extension, thin/thick/sawtooth gutter marker
  combinations, pending copy and move sources, insert paste, replace paste and
  overlap or blank-tail no-op cases.
- `proofs/display/editor-block-delete-proof.asm`: tests selected-block delete
  prompt cancel and confirm behavior.
- `proofs/display/editor-file-list-proof.asm`: lists `/src` through TEC-side
  TM8 catalog code and proves hidden backup files are omitted.
- `proofs/display/shell-edit-navigation-proof.asm`: resolves shell `edit`,
  launches the editor, and pages through source.
- `proofs/display/shell-edit-explicit-navigation-proof.asm`: launches
  `edit /root.asm` without relying on project config.
- `proofs/display/shell-edit-named-navigation-proof.asm`: launches
  `edit notes` and proves the shell resolves it to `/src/notes.asm`.
- `proofs/display/shell-edit-interaction-proof.asm`: runs shell-launched editor
  interaction through cursor movement, paging, and mutation.
- `proofs/display/editor-mutation-boundary-proof.asm`: tests in-page insert,
  backspace, delete, cursor bounds, and reserved command-letter behavior.
- `proofs/display/editor-line-editing-proof.asm`: tests split-line/newline and
  join-line/backspace-at-start behavior inside the current 512-byte page
  buffer.
- `proofs/display/editor-page-write-proof.asm`: tests edit/save/write-back
  behavior through the storage-backed editor path. It now also checks that
  no-op edit paths do not mark dirty, save clears dirty only after write-back,
  prompt yes/no state works through the key loop, and the pre-existing hidden
  backup file receives the previous on-disk page before the source page is
  replaced.
- `proofs/display/editor-nonfirst-catalog-save-proof.asm`: opens and saves
  `/src/main.asm` when another `/src` file appears earlier in the TM8 catalog,
  proving catalog entry walks preserve the sector offset needed by later
  write-back.
- `proofs/display/editor-error-handling-proof.asm`: tests compact editor
  error-code to status-text mappings and records the last surfaced error
  diagnostic state.
- `proofs/display/editor-allocation-growth-proof.asm`: starts with a source
  file that exactly fills one 4K TM8 allocation block, saves page 8, and
  verifies that `/src/main.asm` grows to 4608 bytes with a newly linked second
  data block.

These proofs are the best executable tour of the unfinished editor.

## TypeScript Tools

The TypeScript code supports the Z80 work. It is intentionally host-side and
does not represent the TEC-side runtime.

### `tools/tm8/format.ts`

This is the authoritative host implementation of the v1 TM8 volume format. It
can create, parse, validate, list, create files, import bytes, read bytes,
remove files, move files, and allocate/free block chains. It encodes the fixed
layout documented in `docs/virtual-filesystem.md`.

Z80 loaders do not call this file, but their constants and assumptions should
match it.

### `tools/fs.ts`

This is the CLI wrapper around `tools/tm8/format.ts`. Current commands include:

- `format`, `info`, `ls`, `new`, `rm`, `mv`, `cat`
- `import` and `export` for raw bytes
- `import-text` and `export-text` for 32-byte source records
- `copy` between TM8 volumes
- `unpack` and `pack` for host folder trees
- `project-init`, `project-info`, and `project-set-main` for `/tecm8.prj`

This tool creates the volumes and source records that the storage-backed Z80
proofs consume. `unpack` and `pack` are project-preservation flows, so they
omit leading-dot local filenames by default and keep editor backups such as
`/src/.main.asm.b` out of ordinary exported or repacked workspaces. Raw
`import`, `export`, and `copy` remain byte-exact host operations and can still
address those hidden TM8 paths directly.

### Proof Runners

The `run-*.ts` files assemble proof programs through the npm
`@jhlagado/azm` package and run them through Debug80. Set `AZM_ROOT` only when
intentionally testing against a local AZM checkout:

- `tools/run-project-config-proof.ts`
- `tools/run-project-config-storage-proof.ts`
- `tools/run-shell-commands-proof.ts`
- `tools/run-display-proof.ts`
- `tools/run-editor-viewport-storage-proof.ts`
- `tools/run-debug80-editor-session.ts`

`tools/run-storage-proof.ts` is the exception: it builds a very small proof
program directly because it is testing raw MON3 sector access rather than
assembled TECM8 source.

The storage-backed runners also create FAT32 images, load MON3 ROM, configure
the TEC-1G runtime, disable shadow ROM where needed, seed SD card state, and
inspect proof-visible symbols, GLCD pixels, source-record buffers, and result
markers.

The proof runners run AZM register-contract checking in strict mode. They pass
`src/mon3.asmi` for MON3 ROM calls and rely on the `;!` comments in included
TECM8 source for routines implemented in this repository.

`tools/run-display-proof.ts` is the shared GLCD proof runner for
`glcd-smoke-proof`, `glcd-tile-proof`, `structured-screen-proof`, and the
viewport display proofs. The tile proof path checks cleared-cell behavior, cell
glyph rows against the MON3 font table, and that the flush path reaches the
visible GLCD image.

`tools/run-editor-viewport-storage-proof.ts` is the main editor proof runner.
It now includes `editor-line-editing-proof`, `editor-page-write-proof`, and
`editor-nonfirst-catalog-save-proof` cases and verifies not just result markers,
but also source-record text, zeroed padding, cursor positions after split/join
operations, dirty/prompt state, and persisted TM8 image bytes after save. Backup
proof coverage starts without `/src/.main.asm.b`, verifies that the Z80 save
path creates that hidden backup, and checks that resident-window saves preserve
the old on-disk text for both the active page and dirty adjacent next page
before the edited source pages are written. It also runs the selection and
block-delete proofs, checking visible marker state, selected-row intervals,
paste reshaping and prompted delete
behavior through the same storage-backed editor path.

`tools/run-debug80-editor-session.ts` is the milestone runner for the first
user-testable editor session. Its default automated path assembles
`src/editor-session-script.main.asm`, generates
`demos/debug80/editor-session-fat32.img`, mounts it in Debug80's TEC-1G
runtime, verifies `/src/main.asm` was saved as fixed source records, verifies
the hidden backup, and writes
`demos/debug80/editor-session-glcd.pgm` as a local GLCD capture. Its
`--live-smoke` and `--block-smoke` paths assemble `src/main.asm`, boot the
manual `LiveStart` entry, inject matrix-key
events, and checks that live cursor movement, page movement, split-line,
join-line, save, saved-page round-trip, clean-save no-op, post-save input,
second save, and quit commands reach the same dirty-state and translated-key
results as the scripted editor loop. The generated fixture now carries two
source pages, with page 0 ending in an empty record so the live smoke can split
and rejoin a line without crossing a sector boundary.

The same runner now has a block-editing acceptance path. `--block-smoke` builds
an editor fixture with spare tail rows, boots the live matrix-key path, drives
selection, copy, paste, save and quit through real key injection, then checks
the saved TM8 records from the host side. `debug80:editor-block-image` prepares
the same fixture for manual screenshot or keyboard validation, and
`acceptance:block-editing-v1` composes the selection proof, block-delete proof,
block smoke and manual image preparation into one host acceptance entry.

`tools/build-keyboard-tester.ts` assembles `src/keyboard-tester.main.asm` into
`build/keyboard-tester.bin` plus a D8M symbol file. It is a manual diagnostic
target, not a storage-backed proof runner.

`proof:display:shell-edit-create-source` covers the missing-source launch case:
`edit fresh` creates `/src/fresh.asm` as a blank one-block source file and opens
it through the same storage-backed editor path.

### Storage Image And Audit Tools

- `tools/create-storage-proof-image.ts` creates a minimal FAT32 image with a
  contiguous 4 MiB `VOLUME.TM8` file.
- `tools/check-storage-proof-status.ts` regenerates the image, verifies it,
  runs the MON3 sector proof, and reports status.
- `tools/audit-storage-proof.ts` converts that status into a
  requirement-by-requirement audit.

### MON3 Analysis Tools

These tools inspect Debug80's bundled MON3 map/source and keep generated docs
current:

- `tools/mon3-service-inventory.ts`
- `tools/mon3-storage-split.ts`
- `tools/mon3-glcd-split.ts`

They support the future BIOS decomposition work by measuring which MON3
services should be kept, rewritten, relocated, or removed.

### Tests

The `tools/*.test.ts` and `tools/tm8/*.test.ts` files provide several kinds of
coverage:

- host volume format and CLI behavior
- source-record import/export conversion
- project config host commands
- generated MON3 report freshness
- direct GLCD tile-layer contracts
- static checks that assembly modules expose expected entry points
- static checks that local entry points carry `;!` contract comments
- proof wiring checks that package scripts invoke the right proof runners

## Documentation Map

The docs are not just background; they are the contracts the code is working
toward.

- `docs/README.md`: top-level documentation index.
- `docs/roadmap.md`: live milestone tracker and next-goal sequence.
- `docs/virtual-filesystem.md`: exact TM8 disk layout, prefix table, catalog,
  virtual directory model, and host preservation commands.
- `docs/shell-command-contract.md`: TEC-side `edit`/`asm`/`run` behavior.
- `docs/editor-design.md`: GLCD editor model and source records.
- `docs/memory-and-code-quality.md`: memory map, RAM pressure, resident versus
  overlay code, and compactness principles.
- `docs/azm-style-guide.md`: assembly style and routine contract conventions.
- `docs/tecm8-bios-api.md`: current BIOS wrapper/API draft.
- `docs/mon3/decomposition.md`: plan for classifying MON3 code.
- `docs/mon3/service-inventory.md`: generated MON3 service classification.
- `docs/mon3/storage-split.md`: generated MON3 storage code analysis.
- `docs/mon3/glcd-split.md`: generated MON3 GLCD code and RAM analysis.
- `docs/codebase.md`: this tour.

Recent editor-design additions also matter for implementation work:

- Source-record length byte bits 5-7 are reserved for editor metadata. Before
  adding more line editing logic, mask lengths with `0x1F` and preserve those
  upper bits when rewriting length bytes.
- The v1 editor should use status-line prompt mode for confirmations rather
  than modal dialog boxes.
- The v1 save policy should create a one-level hidden backup before replacing
  an existing file. The derived backup of `/src/main.asm` is
  `/src/.main.asm.b`.
- Leading-dot local filenames are ordinary TM8 catalog entries, but ordinary
  TEC-side listings and project export/pack flows now hide or omit them by
  default while raw host byte operations still expose them directly.

## Current State And Gaps

What exists now:

- Host TM8 volume tooling is substantial.
- Source text can be converted into 32-byte editor records.
- `/tecm8.prj` can be created on host and read by Z80 code.
- Shell command resolution for `edit`, `asm`, and `run` is proven.
- MON3-backed storage and GLCD wrappers exist.
- A storage-backed editor can load and render source pages.
- A shell `edit` command can launch that editor path in proofs.
- Cursor movement, in-page character mutation, split-line, and join-line
  behavior are implemented and covered by proofs.
- Whole-line selection and resident-page block copy, move, paste, replace and
  prompted delete behavior are implemented and covered by proofs.
- The editor can save the currently loaded 512-byte page buffer back to the
  matching TM8 source page, with persisted image verification.
- The editor tracks dirty state for the loaded page, marks dirty after
  mutation, saves via Ctrl-S, and clears dirty after successful save.
- Status-line yes/no prompt state exists and is rendered as a transient row 9
  overlay for restore and dirty-quit confirmations; the hidden source row is
  redrawn when the prompt clears.
- The editor derives a hidden one-level backup path and can preserve the
  previous on-disk page there before save, creating the backup file when needed.
- The editor can restore the hidden backup into the current buffer and mark the
  restored buffer dirty for inspection.
- The editor can quit from the key stream, with dirty-state confirmation before
  discarding unsaved changes.
- The live Debug80 editor session now rechecks line split and join behavior
  through the matrix-key path, including save and page-return persistence.
- Unknown Ctrl-modified printable keys are silently ignored instead of
  falling through as plain text or leaving status text behind, and dirty page
  movement is allowed inside the RAM window.
- Page-up at the first page restores the hidden source row without leaving
  stale `Top` text; page-down past the available source leaves visible source
  rows intact instead of overlaying a misleading end-of-file label.
- Logical cursor movement can traverse all 16 records of a source page. The
  GLCD viewport scrolls within that page, with `EditorCursorVisibleRow` tracking
  the physical row used for cursor and marker rendering.
- Logical cursor movement and insertion can reach all 31 characters in a source
  record. The GLCD text viewport pans horizontally, with
  `EditorCursorVisibleCol` tracking the physical column used for cursor
  rendering.

What is still missing or intentionally skeletal:

- `asm` and `run` resolve request blocks but do not launch real tools.
- The editor has no search behavior yet.
- The current RAM edit window is deliberately small: active sector, adjacent
  next sector, and one previous-page cache. A later 2K or 4K window should
  reduce SD reads further for 100-200 line source files.
- Split can push row 15 into the adjacent sector, row-15 Enter can create the
  first record in the adjacent sector, and Backspace at row 0 can join into
  cached previous row 15. Saving can grow the catalog byte size when the new
  sector still fits inside the file's existing 4K allocation block, and can
  allocate/link a new block when the grown file crosses a 4K boundary. Shrinking
  and freeing TM8 blocks are still not implemented.
- Block editing is still intentionally narrow: selections are whole-line
  intervals, paste and replace operate on resident-page ranges, named block
  read/write is not implemented yet, and there is no hidden cross-document
  clipboard file.
- Prompt overlays and some full-row redraw paths still do more GLCD work than
  the simple cell-dirty cursor and character-mutation paths.
- The Z80 storage readers are narrow readers, not a general reusable TM8
  filesystem layer.
- Banked overlays and a trimmed TECM8 BIOS are design targets, not implemented
  runtime infrastructure.

## How To Extend This Tour

When new code lands, update this file in the same style:

- say what the file does
- say what calls it
- say what it calls or relies on
- say what proof or test covers it
- say whether it is product code, proof code, host tooling, or design support
- call out unfinished assumptions rather than hiding them

This document should remain a map, not a replacement for the detailed design
docs.
