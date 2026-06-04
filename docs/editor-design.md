# Editor Design

## Goal

The first editor should be a small GLCD text editor: closer to a simple
WordStar/Pico/Nano-style editor than to a full GUI IDE.

It should edit one file at a time, save reliably, and return to the shell so
other tools can run.

## Display Targets

Initial target:

```text
GLCD: 20 columns x 10 rows using MON3's current 6x6 terminal cell
```

Future target:

```text
TMS9918 VDU: 32 columns x 24 rows
```

The editor core should not depend on either display. It should expose a
viewport model that renderers can draw differently.

The MON3 GLCD terminal is not an 8x8 tile display. Its current character path
uses 6x6 pixel cells on a 128x64 bitmap display. The practical terminal
capacity is therefore 20 columns by 10 rows. Older notes that refer to an
8-row GLCD editor should be read as an editor viewport policy, not a physical
display limit.

The default GLCD editor should reserve two of those ten rows for chrome:

```text
row 0      mode/menu/status row
rows 1-8   editable source viewport
row 9      command/status/error row
```

This preserves the earlier 8 editable line assumption while acknowledging the
full 10-row display. A later full-screen mode can hide one or both chrome rows
and expose 9 or 10 editable rows when the user wants more source context.

The gutter should not automatically consume a full 6-pixel character cell. A
4-pixel left gutter is enough for breakpoint, current-line, selection, dirty,
or diagnostic markers while still leaving room for 20 full 6-pixel text cells:

```text
128 px width - 4 px gutter = 124 px
124 px / 6 px cell = 20 full text columns, with 4 px spare
```

The shared display model should therefore be cell-based and metadata-based,
not fixed to identical tile dimensions across devices. GLCD can use compact
6x6 cells and a narrow bitmap gutter; a future TMS9918 backend can use 8x8
tiles, a hardware name table, and hardware sprites where appropriate.

Initial structured display constants:

```text
TECM8_DISPLAY_GLCD_COLUMNS      20
TECM8_DISPLAY_GLCD_ROWS         10
TECM8_DISPLAY_EDIT_ROWS         8
TECM8_DISPLAY_GUTTER_PIXELS     4
TECM8_DISPLAY_TEXT_X            6
TECM8_DISPLAY_TOP_ROW           0
TECM8_DISPLAY_FIRST_EDIT_ROW    1
TECM8_DISPLAY_BOTTOM_ROW        9
TECM8_DISPLAY_MARKER_NONE       0
TECM8_DISPLAY_MARKER_BREAKPOINT bit 0
TECM8_DISPLAY_MARKER_CURRENT    bit 1
TECM8_DISPLAY_MARKER_SELECTED   bit 2
```

The first display-model proof uses a fixed screen descriptor rather than an
editor buffer:

```text
word top_chrome_text
8 x {
  byte marker_flags
  word source_line_text
}
word bottom_chrome_text
```

That descriptor is intentionally small. It proves the rendering contract for
chrome rows, editable rows, gutter metadata, and status text without starting
the editor implementation.

Future TMS9918 mapping:

```text
GLCD 20x10 physical cells       -> TMS 32x24 physical tile field
GLCD rows 0 and 9 chrome        -> TMS top/bottom status bands
GLCD rows 1-8 editor viewport   -> TMS editor viewport, likely taller
GLCD 4-pixel bitmap gutter      -> TMS left tile column or sprite markers
GLCD software sprite overlays   -> TMS hardware sprites where suitable
```

The TMS backend should not be forced to mimic the GLCD's exact row count. It
should consume the same line text and marker metadata, then choose a larger
viewport or richer sprite/status presentation where the hardware permits it.

## Selection Model

Selection should be semantic editor metadata, not just an inverted bitmap. A
line can be selected because it belongs to a marked block, because it is the
current execution/cursor line, or because it has another editor/debugger state.
The renderer then chooses the visual treatment.

For the GLCD v1 renderer, the primary selection affordance should be the
4-pixel gutter. A selected block line can render as a vertical bar in the left
gutter, ideally in pixel column 0. This is cheap to draw, readable beside
source text, and does not reduce the 20 text columns. Inverted text remains a
useful terminal-era convention, but it should be optional: it may be added
later for range emphasis or modal feedback, not required for basic block
selection.

Possible gutter meaning:

```text
pixel 0 vertical bar  selected block line
pixel 1 marker        current cursor/execution line
pixel 2 marker        breakpoint
pixel 3 marker        diagnostic, dirty, or other transient state
```

The exact keyboard commands can be settled later. The display model only needs
to support the state:

```text
block start set
cursor moved through source lines
selected line flags applied to the affected rows
block cleared or committed by command
```

A WordStar-like command family remains plausible, such as `Ctrl-B` or
`Ctrl-Space` to start a block, cursor movement to extend it, and a second
command to end or clear the block. The important point for now is that selected
lines can be represented by `TECM8_DISPLAY_MARKER_SELECTED` without requiring
text inversion.

TMS9918 renderers can map the same metadata differently: a left tile-column
glyph, color attributes, or hardware sprite markers. The source/editor model
should not care which backend visual is used.

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

Only the low five bits of byte 0 are needed to store the line length. The upper
three bits are therefore reserved for possible editor metadata, but they are not
part of the active format yet. Current source records should keep those bits
clear, and import/export should continue treating the length byte as `0..31`
until a future change deliberately defines masked length handling.

Possible future uses include per-line dirty state, selected/block-marked state,
continuation/wrap state, breakpoint state, or another compact editor/debugger
marker. If these bits are adopted, every reader must mask the stored length with
`0x1F`, every writer must either preserve or intentionally update the metadata
bits, and host validators/proofs must be updated to reject accidental misuse
while allowing the defined flags.

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

- 20 visible text columns on GLCD, with an optional narrow bitmap gutter.
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
1 top mode/status row
8 editable source rows
1 bottom command/error/status row
```

Either chrome row may be hidden to show more source lines. The renderer should
therefore know both the physical GLCD geometry and the active editor viewport
geometry.

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
The editor should therefore target a display contract: draw text rows, draw
gutter markers, set cursor, clear/status regions, and optionally draw graphics
or sprite-like overlays. GLCD and TMS backends can implement that contract with
different memory strategies. A GLCD sprite is software-composited into a
bitmap; a TMS9918 sprite can use hardware sprite support.

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
