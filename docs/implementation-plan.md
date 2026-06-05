# Implementation Plan

## Phase 0: Research And Proofs

Goals:

- Keep the MON3/Debug80 storage proof passing against an existing FAT32 file.
- Validate the default workspace size: 4MB volume, 4K blocks, 256 file
  entries, and 128 prefix entries.
- Decide exact superblock, allocation table, and catalog entry byte layouts.

Deliverables:

- Storage proof notes.
- Test disk image.
- Minimal sector read/write test.

## Phase 1: Workspace Disk Format

Goals:

- Create `VOLUME.TM8` format.
- Implement superblock read/write.
- Implement allocation table.
- Implement prefix table and file catalog.
- Support the default 4MB project-volume layout.

Commands:

```text
format
info
ls
new
rm
mv
cat
```

The Phase 1 host tool is intentionally stateless: commands take explicit
absolute TM8 paths and do not persist a current prefix. `cd` and `pwd` are GLCD
shell commands, not host `fs` commands; they move to Phase 3 where there is
an interactive shell state. For shell v1, `cd` changes the current prefix and
always succeeds for syntactically valid paths.

## Phase 2: Host Tooling

Goals:

- Provide laptop-side tools for preservation and testing.
- Allow source files to be imported/exported without relying on TEC hardware.

Host commands:

```text
fs ls VOLUME.TM8 /path
fs import VOLUME.TM8 hostfile /path/in/tm8
fs export VOLUME.TM8 /path/in/tm8 hostfile
fs copy LIBS.TM8:/lib/file.asm VOLUME.TM8:/lib/file.asm
fs unpack VOLUME.TM8 folder
fs pack folder VOLUME.TM8
```

Host-side cross-volume copy is the preferred early way to bring libraries and
examples into a project. TEC-side cross-volume import can follow once the active
volume workflow is stable.

`fs import`, `fs export`, `fs copy`, `fs unpack`, and `fs pack` are already
implemented as raw byte operations. Source-record conversion is tracked in
Phase 4 below.

## Phase 3: GLCD Shell

Goals:

- Boot or jump into TECM8 shell.
- Read matrix keyboard input.
- Print to GLCD terminal.
- Navigate virtual prefixes with `cd` and `pwd`.
- List files and virtual folder prefixes.
- Read `/tecm8.prj` line-by-line to get `main`, then derive build output
  and map paths from `main`.
- Use the first TEC-side project config parser in `src/project-config.asm`;
  `npm run proof:project-config` assembles and runs its proof harness.
- Use the first TEC-side project config loader in `src/project-config-loader.asm`;
  `npm run proof:project-config:storage` assembles it, creates a FAT32 SD image
  containing a real TM8 `VOLUME.TM8`, opens that file through MON3, scans the
  TM8 catalog for `/tecm8.prj`, loads the config bytes, and then calls
  `ParseProjectConfig`.
- Use the first TEC-side shell command resolver in `src/shell-commands.asm`;
  `npm run proof:shell-commands` verifies that `edit`, `asm`, and `run`
  resolve project defaults and named one-off targets while returning action
  codes instead of launching the editor, assembler, or program runner.

This phase used MON3 GLCD terminal routines to prove early shell/display paths.
That is no longer acceptable for the interactive editor's hot path: the renderer
phase below owns text-cell drawing and dirty update policy.

Host-side project metadata commands are implemented so shell work has a stable
format to target:

```text
fs project-init VOLUME.TM8 [/src/main.asm]
fs project-info VOLUME.TM8
fs project-set-main VOLUME.TM8 /path/file
```

The stored config is not JSON. It is an ASCII `key=value` file at
`/tecm8.prj`, chosen so Z80 code can parse it with simple line scanning.
The authoritative shell behavior for parsing that file and resolving
`edit`/`asm`/`run` is defined in
[TEC-Side Shell Command Contract](shell-command-contract.md).

## Phase 4: Source Record Files

Goals:

- Fixed-record source file type is defined as 32-byte Pascal-string records.
- `fs import-text` converts host text into 32-byte source records.
- `fs export-text` converts source records back to LF-terminated host text.
- Read source by sector and line number.

## Phase 5: GLCD Editor V1

Goals:

- Edit one source file.
- Save changes explicitly.
- Create a hidden one-level backup before replacing an existing file.
- Restore the current file from its hidden backup.
- Use a status-line prompt mode for confirmations instead of dialog boxes.
- Keep UI small and reliable.

Initial controls:

```text
move cursor
insert char
backspace/delete
insert line
delete line
save
restore backup
answer status prompt
quit
redraw
```

The v1 backup convention is documented in
[Editor Design](editor-design.md#save-backup-and-restore-policy): the backup of
`/src/main.asm` is `/src/.main.asm.b`. Leading-dot files are intended to be
hidden from ordinary listings and project export/pack output, but implementing
that hidden-file behavior is a separate low-priority filesystem task.

## Phase 6: TECM8 Tiled GLCD Renderer

Goals:

- Replace MON3 terminal-style text drawing in the editor hot path.
- Treat the 128x64 GLCD as a bitmap-backed tile surface using the current 6x6
  font rhythm.
- Write complete cells, including clear pixels, so old glyph strokes do not
  remain after edits.
- Redraw cursor movement with old/new cell updates rather than full-screen
  repaint.
- Redraw ordinary character insertion/deletion by affected cell range or line,
  not by full viewport clear.
- Keep full-screen repaint for page load, mode switch, and explicit redraw.
- Establish the future boundary between low-level GLCD hardware access and
  TECM8-owned editor display policy.

Initial routines should be deliberately small and measurable:

```text
clear cell
draw cell
draw text run
draw gutter marker
draw/erase cursor cell
flush full screen
flush dirty row or dirty byte range
```

MON3's low-level GLCD plot/update routine may remain as a temporary hardware
flush backend, but MON3 terminal initialization and character-output policy
should not be used for normal editor mutation rendering.

## Phase 7: Build Tools

Goals:

- Add Z80 assembler tooling after editing is useful.
- Generate object output.
- Generate compact map data for future debugger.

## Phase 8: Debugger

Goals:

- Load object code.
- Load or page compact map data.
- Display source context by reading source sectors.
- Support break/run/step/register display.

This is a long-term phase and should not block the first editor.
