# Implementation Plan

## Phase 0: Research And Proofs

Goals:

- Keep the MON3/Debug80 storage proof passing against an existing FAT32 file.
- Validate the proposed default workspace size: 4MB volume, 4K blocks, 256 file
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
shell commands, not host `tm8fs` commands; they move to Phase 3 where there is
an interactive shell state. For shell v1, `cd` changes the current prefix and
always succeeds for syntactically valid paths.

## Phase 2: Host Tooling

Goals:

- Provide laptop-side tools for preservation and testing.
- Allow source files to be imported/exported without relying on TEC hardware.

Host commands:

```text
tm8fs list VOLUME.TM8
tm8fs import VOLUME.TM8 hostfile /path/in/tm8
tm8fs export VOLUME.TM8 /path/in/tm8 hostfile
tm8fs copy LIBS.TM8:/lib/file.z80 VOLUME.TM8:/lib/file.z80
tm8fs unpack VOLUME.TM8 folder
tm8fs pack folder VOLUME.TM8
```

Host-side cross-volume copy is the preferred early way to bring libraries and
examples into a project. TEC-side cross-volume import can follow once the active
volume workflow is stable.

## Phase 3: GLCD Shell

Goals:

- Boot or jump into TECM8 shell.
- Read matrix keyboard input.
- Print to GLCD terminal.
- Navigate virtual prefixes with `cd` and `pwd`.
- List files and virtual folder prefixes.

This phase can use MON3 GLCD terminal routines before a custom renderer exists.

## Phase 4: Source Record Files

Goals:

- Define fixed-record source file type.
- Convert text import into 32-byte Pascal-string records.
- Convert records back to plain text on export.
- Read source by sector and line number.

## Phase 5: GLCD Editor V1

Goals:

- Edit one source file.
- Save changes.
- Keep UI small and reliable.

Initial controls:

```text
move cursor
insert char
backspace/delete
insert line
delete line
save
quit
redraw
```

## Phase 6: Build Tools

Goals:

- Add assembler or interpreter tooling after editing is useful.
- Generate object output.
- Generate compact map data for future debugger.

## Phase 7: Debugger

Goals:

- Load object code.
- Load or page compact map data.
- Display source context by reading source sectors.
- Support break/run/step/register display.

This is a long-term phase and should not block the first editor.
