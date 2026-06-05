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

1. `docs/project-overview.md`: product goal, storage model, and project
   workflow.
2. `docs/workspace-disk-format.md`: exact `VOLUME.TM8` byte layout.
3. `docs/shell-command-contract.md`: how `edit`, `asm`, and `run` resolve.
4. `docs/editor-design.md`: 32-byte source records and GLCD viewport model.
5. `docs/tecm8-bios-api.md`: the BIOS wrapper vocabulary used by Z80 code.
6. `src/tecm8-bios.asm`: the current MON3-backed wrapper implementation.
7. `src/shell-commands.asm`: the current shell resolver and prompt skeleton.
8. `src/shell-editor-launch.asm`: the bridge from shell resolution into the
   editor.
9. `src/editor-storage-loader.asm`, `src/editor-navigation.asm`,
   `src/editor-viewport.asm`, and `src/editor-interaction.asm`: the current
   editor path.
10. `proofs/display/editor-line-editing-proof.asm`: the newest focused proof
    for split-line and join-line editor behavior.

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

This is a Debug80 starter program, not the TECM8 shell. It prints a message to
the LCD and scans `HELLO ` on the seven-segment display through MON3 `RST 10h`
API calls. Treat it as a minimal target configured by `debug80.json`, not as
the current product entry point.

### `src/tecm8-bios.asm` and `src/mon3.asmi`

These are the stable service boundary under TECM8 code. The implementation is
currently a thin MON3 compatibility layer:

- `BiosFileOpen`
- `BiosFileReadSector`
- `BiosFileWriteSector`
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
the `D8xxh` to `DCxxh` range. Higher-level code should call the wrapper names,
not hard-code MON3 addresses.

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
and calls `EditorOpenPath`.

`ShellRunEditorSession` adds a proof-oriented editor key stream: run
the shell edit command, reset the cursor, then pass the key stream to
`EditorRunKeys`.

This file is where shell-to-editor composition starts. `asm` and `run` are
still unsupported here because no assembler or runner exists yet.

### `src/display-model.asm`

This is the structured GLCD display layer. It renders an editor-like screen
through the `BiosDisplay*` wrapper calls:

- row 0 is top chrome
- rows 1-8 are editable source rows
- row 9 is bottom status/command chrome
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
MON3 terminal graphics buffer at `0x13C0` and pushes updates through
`BiosDisplayUpdate`.

### `src/editor-viewport.asm`

This converts source records into a screen descriptor for the display model.
Source records are fixed 32-byte Pascal strings:

```text
byte 0      length, 0-31
byte 1-31   text bytes
```

The upper three bits of the length byte are currently reserved and should remain
clear. They may later become line metadata bits, but the existing code and host
conversion tools still treat the byte as a plain `0..31` length.

`EditorViewportRender` takes `HL` pointing at a source-record window,
copies the first eight records into NUL-terminated row buffers, checks that no
record length exceeds 31, then calls `DisplayRenderScreen`.

This module currently has fixed placeholder chrome text and fixed marker flags.
It is a viewport proof surface, not a full editor model yet.

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
`BiosFileWriteSector`. `EditorCreateSourceFile` adds the narrow create path
needed by editor backups: it finds a free data block, marks that allocation
entry as end-of-chain, writes a catalog entry, and updates the superblock free
block count/checksum. It assumes the prefix already exists and creates a
single 4K source file; it is not a general grow, remove, rename, or directory
creation API.

This is still proof-focused. It reads pages, follows existing block chains,
writes existing pages, and can create the one-block backup files the editor
needs. It is not yet a general TM8 filesystem layer.

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

The module stores a 64-byte path buffer, a 512-byte page buffer, and
`EditorNavDirty`. It now also owns the first backup scratch buffers:
`EditorNavBackupPathBuffer` for the derived hidden path and
`EditorNavBackupPageBuffer` for the previous on-disk page. Page moves are
committed only after loading and rendering succeeds, so failed page-down or
page-up attempts do not corrupt current-page state. Successful load/page
movement and save clear the dirty flag.

`EditorSaveCurrentPage` is the current save coordinator. It first calls
`EditorBackupCurrentPage`; if that succeeds, it writes `EditorNavPageBuffer`
back to the current path/page and clears dirty. `EditorBackupCurrentPage`
derives the hidden backup path from the current source path, loads the current
on-disk page into `EditorNavBackupPageBuffer`, and writes that old page to the
backup path. If the backup path is missing, it asks the storage loader to
create a one-block file first, then retries the backup write. Multi-page backup
policy remains outside this module today.

`EditorNavDeriveBackupPath` implements the current naming convention. It keeps
the original prefix, prepends `.` to the local filename, and appends `.b`.
For example, `/src/main.asm` becomes `/src/.main.asm.b`. It fails with
`TECM8_EDITOR_NAV_ERR_BACKUP` if the path is malformed or the derived name does
not fit the fixed path buffer.

`EditorLoadCurrentBackupPage` uses the same derived path convention and loads
the hidden backup into `EditorNavPageBuffer`. The interaction layer decides
whether to mark that restored buffer dirty.

### `src/editor-interaction.asm`

This is the early editor interaction loop. It consumes a NUL-terminated proof
key stream rather than real keyboard input. In command mode:

- `d`/`D` page down
- `u`/`U` page up
- `h`/`j`/`k`/`l` move the cursor
- Ctrl-Q quits the key stream, prompting first when the page is dirty
- Ctrl-S saves the currently loaded page
- Ctrl-R prompts to restore the hidden backup into the current buffer
- TAB enters insert mode for the stream
- printable ASCII inserts into the current fixed source record
- backspace deletes before the cursor
- newline splits the current fixed source record when there is room in the page
- backspace at column zero joins with the previous record when the result fits
- delete removes the character at the cursor

The public interface now exposes the primitive edit operations as separate
entry points as well as the proof key-stream runner:

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
and clears the flag only after the backup and page write-back succeed. Ctrl-R
arms a status-line restore prompt; a yes answer loads the hidden backup into
the current page buffer, rerenders it, and marks it dirty so the user can
inspect before saving. Ctrl-Q exits the key stream immediately when clean; when
dirty, it asks before discarding changes and only exits on yes. There is not
yet sector-crossing insert/delete.

The mutation primitives return a small change result in `A`: `1` means the
buffer changed, `0` means the operation was a no-op, and carry still reports
errors. The key loop uses that result so no-op delete, split, insert, and join
paths do not dirty a clean buffer.

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
and splits the current record at the cursor. It is a no-op on the final page row
or when the final record is already in use. `EditorJoinPreviousLine`
is called by backspace at column zero; it joins the current record into the
previous record only when the combined text still fits in 31 bytes, then shifts
following records up and clears the last record. Both operations are in-page
only today.

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

### Display And Editor Proofs

The display proofs build up the editor stack incrementally:

- `proofs/display/glcd-smoke-proof.asm`: calls BIOS display wrappers and
  proves visible GLCD output.
- `proofs/display/structured-screen-proof.asm`: renders a fixed structured
  screen with chrome rows, source rows, and gutter markers.
- `proofs/display/editor-viewport-proof.asm`: converts eight source records
  into display rows.
- `proofs/display/editor-viewport-bad-record-proof.asm`: verifies malformed
  record length rejection.
- `proofs/display/editor-viewport-storage-proof.asm`: loads source pages from
  TM8 storage and renders them.
- `proofs/display/editor-viewport-storage-invalid-page-proof.asm`: verifies
  invalid page index rejection.
- `proofs/display/editor-viewport-storage-small-file-proof.asm`: verifies EOF
  behavior for too-small files.
- `proofs/display/editor-navigation-proof.asm`: opens `/src/main.asm`, pages
  forward and back, and proves page state survives.
- `proofs/display/shell-edit-navigation-proof.asm`: resolves shell `edit`,
  launches the editor, and pages through source.
- `proofs/display/shell-edit-explicit-navigation-proof.asm`: launches
  `edit /root.asm` without relying on project config.
- `proofs/display/shell-edit-interaction-proof.asm`: runs shell-launched editor
  interaction through cursor movement, paging, and mutation.
- `proofs/display/editor-mutation-boundary-proof.asm`: tests in-page insert,
  backspace, delete, cursor bounds, and reserved command-letter behavior.
- `proofs/display/editor-line-editing-proof.asm`: tests split-line/newline and
  join-line/backspace-at-start behavior inside the current 512-byte page
  buffer.
- `proofs/display/editor-page-write-proof.asm`: tests edit/save/write-back
  behavior through the storage-backed editor path. It now also checks that
  no-op edit paths do not mark dirty, Ctrl-S clears dirty only after save,
  prompt yes/no state works through the key loop, and the pre-existing hidden
  backup file receives the previous on-disk page before the source page is
  replaced.

These proofs are the best executable tour of the unfinished editor.

## TypeScript Tools

The TypeScript code supports the Z80 work. It is intentionally host-side and
does not represent the TEC-side runtime.

### `tools/tm8/format.ts`

This is the authoritative host implementation of the v1 TM8 volume format. It
can create, parse, validate, list, create files, import bytes, read bytes,
remove files, move files, and allocate/free block chains. It encodes the fixed
layout documented in `docs/workspace-disk-format.md`.

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
proofs consume.

### Proof Runners

The `run-*.ts` files assemble proof programs through AZM and run them through
Debug80:

- `tools/run-project-config-proof.ts`
- `tools/run-project-config-storage-proof.ts`
- `tools/run-shell-commands-proof.ts`
- `tools/run-display-proof.ts`
- `tools/run-editor-viewport-storage-proof.ts`
- `tools/run-storage-proof.ts`

The storage-backed runners also create FAT32 images, load MON3 ROM, configure
the TEC-1G runtime, disable shadow ROM where needed, seed SD card state, and
inspect proof-visible symbols, GLCD pixels, source-record buffers, and result
markers.

The proof runners run AZM register-contract checking in strict mode. They pass
`src/mon3.asmi` for MON3 ROM calls and rely on the `;!` comments in included
TECM8 source for routines implemented in this repository.

`tools/run-editor-viewport-storage-proof.ts` is the main editor proof runner.
It now includes `editor-line-editing-proof` and `editor-page-write-proof` cases
and verifies not just result markers, but also source-record text, zeroed
padding, cursor positions after split/join operations, dirty/prompt state, and
persisted TM8 image bytes after save. For the current backup proof slice it
starts without `/src/.main.asm.b`, then verifies that the Z80 save path creates
that hidden backup and stores the old on-disk text before the edited source page
is written.

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
- static checks that assembly modules expose expected entry points
- static checks that local entry points carry `;!` contract comments
- proof wiring checks that package scripts invoke the right proof runners

## Documentation Map

The docs are not just background; they are the contracts the code is working
toward.

- `docs/README.md`: top-level documentation index.
- `docs/project-overview.md`: product direction and user experience.
- `docs/roadmap.md`: live milestone tracker and next-goal sequence.
- `docs/implementation-plan.md`: phased roadmap.
- `docs/workspace-disk-format.md`: exact TM8 disk layout.
- `docs/virtual-filesystem.md`: prefix table, catalog, and virtual directory
  model.
- `docs/storage-proof.md`: MON3/FAT32 storage proof status.
- `docs/shell-command-contract.md`: TEC-side `edit`/`asm`/`run` behavior.
- `docs/editor-design.md`: GLCD editor model and source records.
- `docs/project-sizing.md`: why 4 MiB volumes, 4 KiB blocks, 256 files, and
  128 prefixes are enough for current targets.
- `docs/debugging-roadmap.md`: later source-aware debugger direction.
- `docs/memory-and-code-quality.md`: memory map, RAM pressure, resident versus
  overlay code, and compactness principles.
- `docs/azm-style-guide.md`: assembly style and routine contract conventions.
- `docs/azm-register-care-feedback.md`: notes on improving register-care
  discipline.
- `docs/tecm8-bios.md`: BIOS direction and what to keep from MON3.
- `docs/tecm8-bios-api.md`: current BIOS wrapper/API draft.
- `docs/mon3-decomposition.md`: plan for classifying MON3 code.
- `docs/mon3-service-inventory.md`: generated MON3 service classification.
- `docs/mon3-storage-split.md`: generated MON3 storage code analysis.
- `docs/mon3-glcd-split.md`: generated MON3 GLCD code and RAM analysis.
- `docs/codebase.md`: this tour.

Recent editor-design additions also matter for implementation work:

- Source-record length byte bits 5-7 are reserved and must remain clear until
  a future metadata format is deliberately defined.
- The v1 editor should use status-line prompt mode for confirmations rather
  than modal dialog boxes.
- The v1 save policy should create a one-level hidden backup before replacing
  an existing file. The derived backup of `/src/main.asm` is
  `/src/.main.asm.b`.
- Leading-dot local filenames are ordinary TM8 catalog entries, but future
  ordinary listings and project export/pack flows should hide or omit them by
  default.

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
  mutation, saves via Ctrl-S, and clears dirty after successful save.
- Status-line yes/no prompt state exists and is rendered through the bottom
  chrome row for restore and dirty-quit confirmations.
- The editor derives a hidden one-level backup path and can preserve the
  previous on-disk page there before save, creating the backup file when needed.
- The editor can restore the hidden backup into the current buffer and mark the
  restored buffer dirty for inspection.
- The editor can quit from the key stream, with dirty-state confirmation before
  discarding unsaved changes.

What is still missing or intentionally skeletal:

- No real top-level TECM8 shell entry has replaced `src/main.asm`.
- Shell keyboard input is proof-seeded, not real matrix keyboard input.
- `asm` and `run` resolve request blocks but do not launch real tools.
- The editor has no search or sector-crossing edit behavior yet.
- The roadmap milestone is Debug80-testable GLCD Editor V1. When that milestone
  is reached, stop before starting assembler integration.
- Split and join are currently limited to the loaded 512-byte page; they do not
  move records across sectors or allocate/free TM8 storage.
- The display chrome and marker policy are still mostly fixed proof data.
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
