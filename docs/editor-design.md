# Editor Design

## Goal

The first editor should be a small GLCD text editor: closer to a simple
WordStar/Pico/Nano-style editor than to a full GUI IDE.

It should edit one file at a time, save reliably, and return to the shell so
other tools can run.

## Display Targets

Initial target:

```text
GLCD: approximately 20 columns x 8 rows
```

Future target:

```text
TMS9918 VDU: 32 columns x 24 rows
```

The editor core should not depend on either display. It should expose a
viewport model that renderers can draw differently.

## Source Record Format

Source files use fixed-size Pascal-string line records.
The preferred user-facing extension is `.ASM`; `.Z80` remains a supported
compatibility extension for imported ASM80-era source.

Initial record:

```text
32 bytes total
byte 0      length, 0-31
byte 1-31   text bytes
```

This provides:

```text
512-byte sector = 16 lines
4K block        = 128 lines
```

Line-to-sector math:

```text
sector index      = line_number / 16
line in sector    = line_number % 16
offset in sector  = (line_number % 16) * 32
```

The same format allows the debugger to display source without loading the whole
file.

## Line Length Policy

GLCD editing should encourage short assembly lines.

Initial policy:

- 20 visible columns on GLCD.
- 31 stored characters per line.
- No horizontal scrolling in v1.
- Cursor should normally be constrained to the visible region.
- Later builds can add overflow indicators or a wider-line mode.

This fits assembly code if users keep labels and comments short.

## Editor Memory Model

The editor does not need to load all project files. It can initially load one
source file, or a bounded working set, into RAM.

Longer-term, it should support paging source sectors from the virtual
filesystem:

- Load sector containing visible lines.
- Modify line records.
- Mark sector dirty.
- Write dirty sector on save or when evicted.

For v1, it is acceptable to load a small file entirely if that gets the editor
working sooner.

## Viewport Model

Core state:

```text
current file id
top line
cursor line
cursor column
dirty flag
mode/status
```

The renderer draws visible lines from the current viewport.

GLCD v1 likely uses:

```text
1 status row
6 editable rows
1 help/command row
```

The help row may be hidden to show more source lines.

## Screen Update Strategy

The document buffer is the source of truth. The GLCD is a rendering target.

Initial rendering strategy:

- Redraw the visible viewport after each edit or cursor move.
- Keep the logic simple and reliable.
- Add dirty-cell or partial redraw optimization later only if needed.

For the TMS9918 backend, the tile display may support more efficient updates,
but the editor core should not assume that.

## Commands

Prefer control-key style commands over menus.

Possible early commands:

```text
Ctrl-S  save
Ctrl-Q  quit
Ctrl-X  save and quit
Ctrl-G  go to line
Ctrl-K  delete line
Ctrl-N  insert new line
Ctrl-L  redraw
```

Exact bindings should be adjusted to the TEC-1G matrix keyboard and MON3
control-key behavior.

## First Editor Feature Set

Minimum useful version:

- Open source file.
- Display source records.
- Move cursor.
- Insert printable character.
- Backspace/delete.
- Insert line.
- Delete line.
- Save.
- Quit.
- Show path and dirty flag.

Excluded from v1:

- Undo.
- Multiple buffers.
- Syntax highlighting.
- Search/replace.
- Mouse/menu UI.
- Horizontal scrolling.
- True variable-length text storage.

## Source Text Import And Export

Internal source format is fixed-record binary text. Host-visible plain text
requires conversion. This is separate from the Phase 2 raw-byte `fs import`
command, which preserves file bytes exactly and does not convert line records.

Implemented source-conversion commands:

```text
fs import-text VOLUME.TM8 MAIN.ASM /projects/demo/main.asm
fs export-text VOLUME.TM8 /projects/demo/main.asm MAIN.ASM
```

Import converts UTF-8 newline-separated text into 32-byte line records.
CRLF input is normalized to LF. Each stored line may occupy at most 31 bytes.
Export validates the source records and writes LF-terminated host text.
