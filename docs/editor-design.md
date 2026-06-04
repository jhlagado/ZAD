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

The editor must not assume source files are fixed length or small enough to
load entirely. TM8 files are block allocated and sector addressable. A source
file may be one sector, one 4K block, two 4K blocks, or longer.

With 32-byte source records:

```text
512-byte sector = 16 lines
4K block        = 128 lines
8K file span    = 256 lines
```

The natural editor unit is therefore a 512-byte sector containing 16 source
lines. A 4K TM8 allocation block contains eight of these sectors. TECM8 can
random-access the sectors that make up the area of interest; it should not
pretend the whole document is resident.

The editor should support paging source sectors from the virtual filesystem:

- Load sector containing visible lines.
- Keep a small sector window, likely previous/current/next.
- Modify line records.
- Mark sector dirty.
- Write dirty sector on save or when evicted.
- Redraw from source records when the viewport crosses a sector boundary.

For v1, it is acceptable to load a small file entirely if that gets the editor
working sooner, but the design should still look like a sector-window editor.
The whole-file path should be an implementation shortcut, not the mental model.

## Viewport Model

Core state:

```text
current file id
current sector index
sector window base line
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

Unlike a serial terminal, an editor has both past and future document content.
Scrolling is not primarily "scrollback"; it is moving a viewport through known
records. Page up/down should be preferred over smooth line scrolling if that
keeps the implementation practical on the TEC-1G.

## Screen Update Strategy

The document buffer is the source of truth. The GLCD is a rendering target.

Initial rendering strategy:

- Redraw the visible viewport after each edit or cursor move.
- Keep the logic simple and reliable.
- Add dirty-cell or partial redraw optimization later only if needed.

For the TMS9918 backend, the tile display may support more efficient updates,
but the editor core should not assume that.

The MON3 GLCD terminal keeps bitmap scrollback because it is a terminal: output
arrives, is rendered into pixels, and the past may be scrolled back into view.
The TECM8 editor should use a different cache shape:

```text
source sector window -> decoded line records -> visible render -> GLCD bitmap
```

Useful cache options:

- Character cache: small RAM cost, redraw visible rows from text records.
- Bitmap row cache: larger RAM cost, faster page/line movement.
- Hybrid cache: keep source sectors plus a small rendered band before and after
  the visible viewport.

The first implementation should probably be character/sector based, then add a
rendered band only if real GLCD redraws are too slow.

## Display Architecture

MON3's GLCD library is a working hardware and graphics reference, but its
terminal architecture is not the editor architecture TECM8 needs. TECM8 should
initially call MON3 GLCD services, then grow a display layer with these
separate responsibilities:

```text
low GLCD driver
  init, timing, command/data writes, plot bytes

bitmap/text renderer
  ROM font draw, clear region, draw row, cursor, inverse, underline

editor viewport layer
  source records, sector windows, page movement, redraw

terminal layer
  append text, newline, backspace, terminal scrollback policy
```

The terminal should remain useful for shell output, serial diagnostics, logs,
and compatibility. It should not be the center of the editor design. A future
TECM8 terminal can be rewritten as a client of the same renderer used by the
editor.

Full GLCD bitmap capability should be preserved. A 128x64 one-bit framebuffer
costs 1024 bytes and is the right model for arbitrary graphs, sprites, and
bitmap UI. The design question is whether every text/editor view must also pay
for MON3's second terminal framebuffer and bitmap scrollback. TECM8 should make
that an explicit display-mode choice rather than an accidental global cost.

The later TMS9918 backend will be a different video class: tile/name/pattern
tables and hardware sprites in video RAM rather than a simple CPU-side bitmap.
The editor should therefore target a display contract: draw text rows, set
cursor, clear/status regions, and optionally draw graphics. GLCD and TMS
backends can implement that contract with different memory strategies.

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
