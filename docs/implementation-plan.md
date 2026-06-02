# Implementation Plan

## Phase 0: Research And Proofs

Goals:

- Confirm MON3 sector read/write behavior on an existing FAT32 file.
- Confirm whether Debug80 currently emulates the same storage path needed for
  ZAD.
- Validate the proposed default workspace size: 4MB volume, 4K blocks, 256 file
  entries, and 128 prefix entries.
- Decide exact superblock, allocation table, and catalog entry byte layouts.

Deliverables:

- Storage notes.
- Test disk image or prepared card image.
- Minimal sector read/write test.

## Phase 1: Workspace Disk Format

Goals:

- Create `VOLUME.ZAD` format.
- Implement superblock read/write.
- Implement allocation table.
- Implement prefix table and file catalog.
- Support the default 4MB project-volume layout.

Commands:

```text
format
info
ls
cd
pwd
new
rm
mv
cat
```

For v1, `cd` changes a prefix and always succeeds for valid paths.

## Phase 2: Host Tooling

Goals:

- Provide laptop-side tools for preservation and testing.
- Allow source files to be imported/exported without relying on TEC hardware.

Host commands:

```text
zadfs list VOLUME.ZAD
zadfs import VOLUME.ZAD hostfile /path/in/zad
zadfs export VOLUME.ZAD /path/in/zad hostfile
zadfs copy LIBS.ZAD:/lib/file.z80 VOLUME.ZAD:/lib/file.z80
zadfs unpack VOLUME.ZAD folder
zadfs pack folder VOLUME.ZAD
```

Host-side cross-volume copy is the preferred early way to bring libraries and
examples into a project. TEC-side cross-volume import can follow once the active
volume workflow is stable.

## Phase 3: GLCD Shell

Goals:

- Boot or jump into ZAD shell.
- Read matrix keyboard input.
- Print to GLCD terminal.
- Navigate virtual prefixes.
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
