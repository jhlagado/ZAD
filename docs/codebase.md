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
7. `src/tecm8-bios.asm`: the current MON3-backed wrapper implementation.
8. `src/shell-commands.asm`: the current shell resolver and prompt skeleton.
9. `src/shell-editor-launch.asm`: the bridge from shell resolution into the
   editor.
10. `src/glcd-tile.asm` and `src/display-model.asm`: the current direct GLCD
   cell layer and the structured screen renderer built on top of it.
11. `src/editor-storage-loader.asm`, `src/editor-navigation.asm`,
    `src/editor-viewport.asm`, and `src/editor-interaction.asm`: the current
    editor path.
12. `proofs/display/glcd-tile-proof.asm` and
    `proofs/display/editor-line-editing-proof.asm`: focused proofs for the tile
    cell renderer and the current line editing behavior.

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

### `src/main.asm`

This is now the Debug80-testable TECM8 editor session entry. It runs at `4000h`
under the TEC-1G/MON3 profile and splits into two entry paths. `Start` jumps to
`LiveStart`, which initializes the GLCD, resolves `edit`, resets the cursor,
and enters `EditorRunLive` for manual matrix-key testing against the real
storage-backed editor path. `ScriptStart` is the automated proof entry: it
opens the project main source through `edit`, inserts a small visible edit,
saves, quits, reopens the same file, and leaves the final editor screen
visible. Both paths include the real project config loader and storage-backed
editor path rather than a stub.

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

### `src/shell-commands.asm`

This is the current shell resolver and prompt-state skeleton. It does not yet
launch a real assembler or runner. It does enough to prove the shell command
contract:

- line input is copied into a bounded command buffer
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

The file depends on an external `LoadProjectConfig` routine. Storage-backed
proofs include `project-config-loader.asm`; some command-only proofs stub
`LoadProjectConfig` so they can test parsing without MON3.

### `src/shell-editor-launch.asm`

This is the bridge from the shell resolver into the storage-backed editor.
`ShellRunEditorLine` runs one shell command line and only proceeds if
the resolved action is `SHELL_CMD_EDIT`. It then reads the edit request payload
and calls `EditorOpenPath`. If the open fails with `EDITOR_LOAD_ERR_FIND`, it
creates a one-block source file in the existing prefix and retries the open.
Missing prefixes still fail; this path is for normal project cases such as
`edit fresh` inside `/src`.

`ShellRunEditorSession` adds a proof-oriented editor key stream: run
the shell edit command, reset the cursor, then pass the key stream to
`EditorRunKeys`.

This file is where shell-to-editor composition starts. `asm` and `run` are
still unsupported here because no assembler or runner exists yet.

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
which prevents cursor trails when the cursor moves. This module depends on the
MON3 terminal graphics buffer at `0x13C0`, shares the tile layer's 6x6 cell
geometry, and pushes updates through `BiosDisplayUpdate`.

The live editor no longer uses the old proof-only breakpoint and selection
markers in the gutter. The viewport owns a single current-row marker, and the
interaction layer updates that marker from the cursor row. Other marker types
remain available in the display model for later breakpoint, selection, dirty,
or diagnostic metadata, but they should not appear until the editor has real
state to justify them.

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
`GlcdTileFlushFull`, and `GlcdTileFlushRow`.

Public entries:

- `GlcdTileClearCell`
- `GlcdTileDrawCell`
- `GlcdTileDrawTextRun`
- `GlcdTileFlushFull`
- `GlcdTileFlushRow`
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

This module currently has fixed marker flags. It is a viewport proof surface,
not a full editor model yet.

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

### `src/editor-interaction.asm`

This is the early editor interaction loop. It supports both a NUL-terminated
proof key stream and the live matrix-key path that polls MON3 through
`BiosInputPollKey`. In command mode:

- matrix arrows move the cursor
- Alt+ArrowDown pages down
- Alt+ArrowUp pages up
- Ctrl+ArrowDown and Ctrl+ArrowUp remain page-movement compatibility aliases
- Alt-Q or Alt-X quits the key stream, prompting first when the page is dirty
- Alt-S saves the currently loaded page
- Alt-R prompts to restore the hidden backup into the current buffer
- Ctrl-Q, Ctrl-X, Ctrl-S, and Ctrl-R remain compatibility aliases where the
  host environment does not capture them
- TAB enters insert mode for the stream
- printable ASCII inserts into the current fixed source record
- backspace deletes before the cursor
- newline splits the current fixed source record when there is room in the page
- backspace at column zero joins with the previous record when the result fits
- delete removes the character at the cursor

The public interface now exposes the primitive edit operations as separate
entry points, the proof key-stream runner, and the live polling loop:

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
operations mark `EditorNavDirty`; Ctrl-S routes through `EditorSaveCurrentPage`
and clears the flag only after the backup and page write-back succeeds. Alt-S
uses the same save path and is the preferred Debug80/macOS manual-test binding.
Before that save path runs, `EditorHideCursor` removes the inverse-cell overlay
so the transient `Saving...` redraw and the restored edit row do not inherit
stale cursor pixels. A clean save is ignored before any storage call. Ctrl-R
arms a status-line restore prompt; a yes answer loads the hidden backup into the
current page buffer, rerenders it, and marks it dirty so the user can inspect
before saving. Ctrl-Q and Ctrl-X exit the key stream immediately when clean;
when dirty, they ask before discarding changes and only exit on yes. There is
not yet sector-crossing insert/delete. The current live Debug80 smoke now
drives the same path through matrix `Enter`, `Backspace` at column zero,
save, page-away/page-back persistence checks, a clean-save no-op, post-save
input, and quit.
Page-boundary movement uses the same transient status overlay: page-up at the
first page shows `Top`, and page-down at the hard page limit shows `End`.

The mutation primitives return a small change result in `A`: `1` means the
buffer changed, `0` means the operation was a no-op, and carry still reports
errors. The key loop uses that result so no-op delete, split, insert, and join
paths do not dirty a clean buffer.

Horizontal cursor movement only redraws the cursor overlay. Vertical cursor
movement also redraws the old and new source rows so the current-row gutter
marker follows the cursor without a full viewport repaint.

`EditorRunLive` renders the cursor, polls one TECM8 key event at a time from
`BiosInputPollKey`, and dispatches that key through `EditorRunModifiedKey` so
the editor sees both the translated key byte and modifier flags. Because the
BIOS layer normalizes Ctrl-letter chords to ASCII control codes, the same
command loop handles proof streams and live Ctrl-S, Ctrl-Q, Ctrl-X, and Ctrl-R
input. The editor also checks modified printable command letters before normal
printable insertion, so Alt-S/Alt-Q/Alt-X/Alt-R are first-class commands and a
host path that reports Ctrl+S as printable `S` plus a Ctrl modifier will not
insert `S` before saving. Ctrl+Up/Down and Alt+Up/Down use modifier flags
directly for page movement.

The first backup path is deliberately narrow: `EditorSaveCurrentPage` derives
the hidden backup path (`/src/main.asm` -> `/src/.main.asm.b`), loads the
current on-disk page into `EditorNavBackupPageBuffer`, writes that page to the
backup path, then writes the edited page to the source path. If the backup file
does not exist, it creates a one-block hidden backup file in the existing
prefix. Replacement is just the existing page-write path.

The module also owns the early status-line prompt state:

- `EditorPromptAskYesNo` arms a prompt using caller-provided NUL-terminated
  text.
- `EditorPromptActive` routes subsequent keys to prompt handling.
- `EditorPromptResult` records yes/no completion (`1` yes, `2` no).
- `EditorPromptAction` records whether completion should trigger an editor
  action such as backup restore or dirty quit.
- Unknown keys leave the prompt active; `Y`/`y`, `N`/`n`, or ESC complete it.

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

The `run-*.ts` files assemble proof programs through AZM and run them through
Debug80:

- `tools/run-project-config-proof.ts`
- `tools/run-project-config-storage-proof.ts`
- `tools/run-shell-commands-proof.ts`
- `tools/run-display-proof.ts`
- `tools/run-editor-viewport-storage-proof.ts`
- `tools/run-storage-proof.ts`
- `tools/run-debug80-editor-session.ts`

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
It now includes `editor-line-editing-proof` and `editor-page-write-proof` cases
and verifies not just result markers, but also source-record text, zeroed
padding, cursor positions after split/join operations, dirty/prompt state, and
persisted TM8 image bytes after save. Backup proof coverage starts without
`/src/.main.asm.b`, verifies that the Z80 save path creates that hidden backup,
and checks that resident-window saves preserve the old on-disk text for both
the active page and dirty adjacent next page before the edited source pages are
written.

`tools/run-debug80-editor-session.ts` is the milestone runner for the first
user-testable editor session. Its default path assembles `src/main.asm`,
generates `demos/debug80/editor-session-fat32.img`, mounts it in Debug80's
TEC-1G runtime, verifies `/src/main.asm` was saved as fixed source records,
verifies the hidden backup, and writes
`demos/debug80/editor-session-glcd.pgm` as a local GLCD capture. Its
`--live-smoke` path boots the manual `LiveStart` entry, injects matrix-key
events, and checks that live cursor movement, page movement, split-line,
join-line, save, saved-page round-trip, clean-save no-op, post-save input,
second save, and quit commands reach the same dirty-state and translated-key
results as the scripted editor loop. The generated fixture now carries two
source pages, with page 0 ending in an empty record so the live smoke can split
and rejoin a line without crossing a sector boundary.

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
- The editor can save the currently loaded 512-byte page buffer back to the
  matching TM8 source page, with persisted image verification.
- The editor tracks dirty state for the loaded page, marks dirty after
  mutation, saves via Alt-S or Ctrl-S, and clears dirty after successful save.
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
- Unknown Ctrl/Alt-modified printable keys are ignored with a `KEY` status
  instead of falling through as plain text, and dirty page movement is allowed
  inside the RAM window.
- Page-boundary commands report `Top` or `End` through the transient status row
  instead of silently doing nothing.
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
- Stop before starting assembler integration until a new milestone is chosen.
- Split can push row 15 into the adjacent sector, row-15 Enter can create the
  first record in the adjacent sector, and Backspace at row 0 can join into
  cached previous row 15. Saving can grow the catalog byte size when the new
  sector still fits inside the file's existing 4K allocation block, and can
  allocate/link a new block when the grown file crosses a 4K boundary. Shrinking
  and freeing TM8 blocks are still not implemented.
- The marker policy is still mostly fixed proof data, and prompt overlays still
  flush more than they should.
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
