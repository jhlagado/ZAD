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
src modules -> call TECM8_BIOS_* wrappers
TECM8_BIOS_* wrappers -> call MON3 storage and GLCD services
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

## Z80 Source Tree

The `src/` tree is the TEC-side implementation. Files ending in `.asm` contain
code and state. Files ending in `.asmi` describe public entry points and
register contracts for AZM-style checking and proof compilation.

### `src/main.asm`

This is a Debug80 starter program, not the TECM8 shell. It prints a message to
the LCD and scans `HELLO ` on the seven-segment display through MON3 `RST 10h`
API calls. Treat it as a minimal target configured by `debug80.json`, not as
the current product entry point.

### `src/tecm8-bios.asm` and `src/tecm8-bios.asmi`

These are the stable service boundary under TECM8 code. The implementation is
currently a thin MON3 compatibility layer:

- `TECM8_BIOS_FILE_OPEN`
- `TECM8_BIOS_FILE_READ_SECTOR`
- `TECM8_BIOS_FILE_WRITE_SECTOR`
- `TECM8_BIOS_DISPLAY_INIT`
- `TECM8_BIOS_DISPLAY_CLEAR`
- `TECM8_BIOS_DISPLAY_SET_CURSOR`
- `TECM8_BIOS_DISPLAY_PUT_CHAR`
- `TECM8_BIOS_DISPLAY_PUT_STRING`
- `TECM8_BIOS_DISPLAY_DRAW_CHAR_AT`
- `TECM8_BIOS_DISPLAY_UPDATE`
- `TECM8_BIOS_DISPLAY_SET_BITMAP_MODE`

The wrappers depend on MON3 entry points such as `F5A1h` for file open,
`F5D5h` for sector read, `F66Dh` for sector write, and MON3 GLCD routines in
the `D8xxh` to `DCxxh` range. Higher-level code should call the wrapper names,
not hard-code MON3 addresses.

The `.asmi` file also documents direct MON3 symbols and future-facing BIOS
entries such as bank selection. Some of those future entries are interface
placeholders, not implemented routines in `tecm8-bios.asm` yet.

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
`VOLUME.TM8` through `TECM8_BIOS_FILE_OPEN`, reads sector 0 to validate the
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

### `src/shell-editor-launch.asm` and `src/shell-editor-launch.asmi`

This is the bridge from the shell resolver into the storage-backed editor.
`TECM8_SHELL_RUN_EDITOR_LINE` runs one shell command line and only proceeds if
the resolved action is `SHELL_CMD_EDIT`. It then reads the edit request payload
and calls `TECM8_EDITOR_OPEN_PATH`.

`TECM8_SHELL_RUN_EDITOR_SESSION` adds a proof-oriented editor key stream: run
the shell edit command, reset the cursor, then pass the key stream to
`TECM8_EDITOR_RUN_KEYS`.

This file is where shell-to-editor composition starts. `asm` and `run` are
still unsupported here because no assembler or runner exists yet.

### `src/display-model.asm` and `src/display-model.asmi`

This is the structured GLCD display layer. It renders an editor-like screen
through `TECM8_BIOS_DISPLAY_*` calls:

- row 0 is top chrome
- rows 1-8 are editable source rows
- row 9 is bottom status/command chrome
- a 4-pixel gutter carries marker flags
- text is drawn as 20 columns of MON3 6x6 glyphs

The main entry points are:

- `TECM8_DISPLAY_INIT`
- `TECM8_DISPLAY_RENDER_SCREEN`
- `TECM8_DISPLAY_RENDER_LINE`
- `TECM8_DISPLAY_RENDER_GUTTER`
- `TECM8_DISPLAY_RENDER_CURSOR_CELL`
- `TECM8_DISPLAY_ERASE_CURSOR_CELL`

The cursor routines save and restore the original GLCD bytes under the cursor,
which prevents cursor trails when the cursor moves. This module depends on the
MON3 terminal graphics buffer at `0x13C0` and pushes updates through
`TECM8_BIOS_DISPLAY_UPDATE`.

### `src/editor-viewport.asm` and `src/editor-viewport.asmi`

This converts source records into a screen descriptor for the display model.
Source records are fixed 32-byte Pascal strings:

```text
byte 0      length, 0-31
byte 1-31   text bytes
```

The upper three bits of the length byte are currently reserved and should remain
clear. They may later become line metadata bits, but the existing code and host
conversion tools still treat the byte as a plain `0..31` length.

`TECM8_EDITOR_VIEWPORT_RENDER` takes `HL` pointing at a source-record window,
copies the first eight records into NUL-terminated row buffers, checks that no
record length exceeds 31, then calls `TECM8_DISPLAY_RENDER_SCREEN`.

This module currently has fixed placeholder chrome text and fixed marker flags.
It is a viewport proof surface, not a full editor model yet.

### `src/editor-storage-loader.asm` and `src/editor-storage-loader.asmi`

This is the first storage-backed source loader. It opens `VOLUME.TM8`, validates
the v1 superblock fields it depends on, resolves a TM8 path into prefix and
local filename, scans prefix and catalog tables, follows allocation entries,
and copies one 512-byte page to a caller buffer.

Public entries:

- `TECM8_EDITOR_LOAD_MAIN_SOURCE_SECTOR`: first sector of `/src/main.asm`
- `TECM8_EDITOR_LOAD_MAIN_SOURCE_PAGE`: page `A` of `/src/main.asm`
- `TECM8_EDITOR_LOAD_SOURCE_PAGE`: page `A` of an arbitrary TM8 path in `DE`

Page indexes are limited to 0..127. A page is a 512-byte sector, not a 4K TM8
allocation block. The loader computes the sector-in-block and number of block
links to follow. It depends on MON3's `DISK_BUFF` at `0x0600` through the BIOS
storage wrappers.

This is still proof-focused. It reads pages and follows block chains, but it
does not save modified editor pages back to the volume.

### `src/editor-navigation.asm` and `src/editor-navigation.asmi`

This owns the editor's current path and current page. It layers simple page
navigation on top of `editor-storage-loader.asm` and `editor-viewport.asm`.

Public entries:

- `TECM8_EDITOR_OPEN_MAIN`
- `TECM8_EDITOR_OPEN_PATH`
- `TECM8_EDITOR_RENDER_CURRENT`
- `TECM8_EDITOR_RENDER_PAGE_BUFFER`
- `TECM8_EDITOR_PAGE_DOWN`
- `TECM8_EDITOR_PAGE_UP`

The module stores a 64-byte path buffer and a 512-byte page buffer. Page moves
are committed only after loading and rendering succeeds, so failed page-down or
page-up attempts do not corrupt current-page state.

### `src/editor-interaction.asm` and `src/editor-interaction.asmi`

This is the early editor interaction loop. It consumes a NUL-terminated proof
key stream rather than real keyboard input. In command mode:

- `d`/`D` page down
- `u`/`U` page up
- `h`/`j`/`k`/`l` move the cursor
- TAB enters insert mode for the stream
- printable ASCII inserts into the current fixed source record
- backspace deletes before the cursor
- newline splits the current fixed source record when there is room in the page
- backspace at column zero joins with the previous record when the result fits
- delete removes the character at the cursor

The editing operations mutate `EditorNavPageBuffer` in memory and then rerender
the current page buffer. The implementation respects 32-byte source records and
the 31-character maximum stored line length. It keeps record padding clear so
host source export can continue validating the fixed-record format. There is
not yet a dirty flag, save path, sector-crossing insert/delete, or sector
write-back path.

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
- proof wiring checks that package scripts invoke the right proof runners

## Documentation Map

The docs are not just background; they are the contracts the code is working
toward.

- `docs/README.md`: top-level documentation index.
- `docs/project-overview.md`: product direction and user experience.
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

## Current State And Gaps

What exists now:

- Host TM8 volume tooling is substantial.
- Source text can be converted into 32-byte editor records.
- `/tecm8.prj` can be created on host and read by Z80 code.
- Shell command resolution for `edit`, `asm`, and `run` is proven.
- MON3-backed storage and GLCD wrappers exist.
- A storage-backed editor can load and render source pages.
- A shell `edit` command can launch that editor path in proofs.
- Cursor movement and in-page record mutation are being proven.

What is still missing or intentionally skeletal:

- No real top-level TECM8 shell entry has replaced `src/main.asm`.
- Shell keyboard input is proof-seeded, not real matrix keyboard input.
- `asm` and `run` resolve request blocks but do not launch real tools.
- The editor has no save/write-back path yet.
- The editor has no line insert/delete, dirty tracking, search, or real quit
  command yet.
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
