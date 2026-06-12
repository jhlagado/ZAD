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

The default 6x6 GLCD editor should expose all ten rows as source rows:

```text
rows 0-9   editable source viewport
```

Status, error, and confirmation prompts are transient overlays, not permanent
chrome. The normal overlay row is physical row 9. While a prompt is active it
temporarily hides the source row underneath; when the prompt completes, the
renderer redraws the obscured source row from the viewport buffer.

This keeps the design font-independent. A future 6x8 profile with a better
5x7 glyph can reduce the physical viewport to eight rows, or seven source rows
plus a transient row, without changing the editor's source/page model.

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

The GLCD editor renderer should now be treated as a tiled text renderer over a
bitmap, not as a general terminal repaint. The editor's normal operations are
cell and line operations:

```text
cursor moved       erase old cursor cell, draw new cursor cell
character typed    update source record, redraw affected cell range or line
delete/backspace   redraw affected cell range or line
split/join line    redraw from changed line downward
page load          full screen render
explicit redraw    full screen render
```

This requires TECM8 to own the text-cell drawing policy. MON3's current GLCD
terminal routines are useful for proofing and early hardware access, but they
clear and redraw too much for an interactive editor. A TECM8 tile write must
replace the whole cell footprint, including blank pixels, so stale strokes from
previous glyphs cannot remain. It should not merely OR glyph pixels into the
buffer.

The first TECM8 GLCD tile layer should provide narrow primitives along these
lines:

```text
GlcdTileClearCell(row, col)
GlcdTileDrawCell(row, col, glyph, flags)
GlcdTileDrawTextRun(row, col, text, max_cells, flags)
GlcdTileClearTextRow(row)
GlcdTileDrawGutter(row, marker_flags)
GlcdTileFlushFull()
GlcdTileFlushDirtyRow(row) or equivalent later dirty flush
```

The first implementation can still flush through MON3's low-level GLCD plotting
routine if that is the fastest way to reach hardware. The boundary is that MON3
should no longer decide editor terminal policy, cell clearing, cursor drawing, or
dirty update scope.

Structured screen text rendering follows that boundary: `DisplayRenderLine`
clears the row's text cells and redraws the string through TECM8 tile
primitives. Full-screen repaint remains available, but normal structured text
rows no longer call MON3's terminal glyph drawing path.

Cursor rendering now uses a saved-byte XOR insertion bar rather than a full
inverse block. The bar is drawn one pixel before the active 6x6 cell, so column
0 appears just to the left of the first source character and column N appears
between columns N-1 and N. The renderer saves the affected bytes, toggles that
one-pixel vertical bar, then restores the original bytes when the cursor moves
or blinks. This keeps the cursor in the inter-character space where possible,
while preserving the same dirty-cell compositing path used by the earlier
inverse-cell experiment.

Initial structured display constants:

```text
TECM8_DISPLAY_GLCD_COLUMNS      20
TECM8_DISPLAY_GLCD_ROWS         10
TECM8_DISPLAY_EDIT_ROWS         10
TECM8_DISPLAY_GUTTER_PIXELS     4
TECM8_DISPLAY_TEXT_X            6
TECM8_DISPLAY_Y_ORIGIN          2
TECM8_DISPLAY_STATUS_ROW        9
TECM8_DISPLAY_MARKER_NONE       0
TECM8_DISPLAY_MARKER_BREAKPOINT bit 0
TECM8_DISPLAY_MARKER_CURRENT    bit 1
TECM8_DISPLAY_MARKER_SELECTED   bit 2
```

The first display-model proof uses a fixed screen descriptor rather than an
editor buffer:

```text
10 x {
  byte marker_flags
  word source_line_text
}
```

That descriptor is intentionally small. It proves the rendering contract for
source rows and gutter metadata without starting the editor implementation.
Prompt/status rendering is exercised through row-level redraw helpers rather
than through a permanent descriptor field.

Future TMS9918 mapping:

```text
GLCD 20x10 physical cells       -> TMS 32x24 physical tile field
GLCD rows 0-9 source viewport   -> TMS editor viewport, likely taller
GLCD transient status row       -> TMS status band or overlay policy
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
three bits are therefore reserved for editor metadata. Editor code must not
accidentally destroy or misread those bits. Any routine that reads a line length
should mask byte 0 with `0x1F` before comparing, copying, inserting, deleting,
splitting, joining, rendering, or exporting line text. Any routine that rewrites
byte 0 should preserve the upper three bits unless it is deliberately updating a
defined metadata flag.

Possible uses include selected/block-marked state, breakpoint state,
continuation/wrap state, per-line dirty state, or another compact editor/debugger
marker. Host validators and proofs should distinguish malformed lengths from
defined metadata: the effective text length is `length_byte & 0x1F`, while bits
5-7 are metadata policy. Until individual flags are assigned, those bits should
be preserved by editor mutations and either preserved or explicitly normalized
by import/export tools according to the command being run.

This provides:

```text
512-byte sector = 16 lines
4K block        = 128 lines
```

## Editor RAM Window And SD Latency

MON3 SD/FAT32 access is slow because the storage path is bit-banged and moves
through MON3's sector-oriented FAT/file routines. TECM8 cannot assume that a
sector read/write is cheap enough to do during ordinary cursor movement. The
single 512-byte source page used by the current proof editor is therefore a
bootstrap implementation, not the intended editing model.

The editor should grow toward a RAM window that holds multiple contiguous source
sectors:

```text
512 bytes  = 16 source lines
1K         = 32 source lines
2K         = 64 source lines
4K         = 128 source lines
```

For practical `.ASM` files of roughly 100-200 lines, a 2K or 4K edit window
would make vertical navigation much less dependent on SD reads. The editor can
still keep explicit save semantics: load a window, edit in RAM, track dirty
state, and write changed sectors only when the user saves or when the design
later permits a controlled window flush.

Design direction:

- Prefer preloading adjacent sectors around the visible viewport.
- Avoid SD reads for ordinary up/down movement inside the cached window.
- Avoid SD writes except explicit save or a future clearly signposted flush.
- Keep enough per-sector dirty metadata to write back only changed sectors.
- Treat cross-sector insert/delete as RAM-window operations first, then storage
  allocation/write-back operations at save time.
- If RAM pressure forces a smaller window, make window loads visible with a
  status message so the user understands the pause.

Line-to-sector math:

```text
sector index      = line_number / 16
line in sector    = line_number % 16
offset in sector  = (line_number % 16) * 32
```

The same format allows the debugger to display source without loading the whole
file.

## Sector-Edge Editing Policy

The V1 editor edits one loaded 512-byte source sector at a time. Split and join
operations are deliberately conservative at sector boundaries:

- Splitting the final record in the loaded sector is a no-op.
- Joining before the first record in the loaded sector is a no-op.
- The editor does not shift source records across sectors in V1.
- The editor does not allocate or free TM8 storage blocks as a side effect of
  line editing in V1.

This keeps the first Debug80-testable editor predictable and avoids hiding
multi-sector file mutation behind simple cursor commands. A later editor can
add explicit sector/page shifting once save, backup, restore, and viewport
movement are stable.

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
10 editable source rows in the current 6x6 profile
row 9 as a transient command/error/status overlay when needed
```

A later 6x8 font profile may expose fewer source rows or reserve a permanent
status row. The renderer should therefore know both the physical GLCD geometry
and the active editor viewport geometry.

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
Alt-Q   alternate quit for host environments that capture Ctrl-Q
Ctrl-G  go to line
Ctrl-K  delete line
Ctrl-N  insert new line
Ctrl-L  redraw
```

Exact bindings should be adjusted to the TEC-1G matrix keyboard and MON3
control-key behavior. Block operations now have a more detailed future keymap
in [Editor Block Operations](block-operations.md): `Ctrl-X`/`Alt-X` should
eventually mean pending block move, while restore-from-backup moves toward
`Ctrl-Z`/`Alt-Z`.

## Status-Line Prompt Mode

The editor should use the status line for confirmation prompts instead of modal
dialog boxes. A 128x64 GLCD does not have enough space for heavy window UI, and
the Pico/Nano-style status prompt fits the small editor model better.

When an operation needs confirmation, the editor temporarily routes key input to
a prompt state:

```text
normal edit mode
  all rows show source text

confirmation mode
  status row temporarily asks a question
  Y/Enter accepts
  N/Esc cancels
  accepted action returns to edit mode
```

Examples:

```text
Save changes? Y/N
Restore from .main.asm.b? Y/N
Discard unsaved changes? Y/N
Replace existing backup? Y/N
```

This is a small state machine, not a dialog system. The editor needs enough
state to remember the pending action, render the prompt text, interpret the next
confirmation key, and then either execute or cancel the action. Likely pending
actions include save, restore-from-backup, quit-with-dirty-buffer, overwrite, and
discard changes.

Prompt mode should block ordinary editing keys until it is answered. After the
answer, the editor should redraw the source row hidden by the prompt and return
to the previous edit or insert mode as appropriate.

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
- Restore from backup.
- Quit.
- Show path and dirty flag.

Excluded from v1:

- General undo.
- Multiple buffers.
- Syntax highlighting.
- Search/replace.
- Mouse/menu UI.
- Horizontal scrolling.
- True variable-length text storage.

## Save, Backup, And Restore Policy

The v1 editor should not assume a general undo system. Undo is valuable, but a
real undo stack consumes RAM and complicates sector-crossing edits. TECM8 should
instead use explicit saves plus a one-level backup file as the first safety
mechanism.

Policy:

- Edits live in the editor's RAM page/window until the user saves.
- `Ctrl-S` or the final save command explicitly commits changes.
- Before replacing an existing file, save creates or replaces a hidden backup of
  the previous saved file.
- The backup path is derived from the original local filename as
  `.` + filename + `.b`.
- Example: `/src/main.asm` backs up to `/src/.main.asm.b`.
- The backup is a normal fixed-record text file and can be restored manually
  with file commands if needed.
- The editor should also provide a restore-from-backup command so the user does
  not have to leave the editor, delete the damaged file, and rename the backup.
- Autosave should not be part of v1; autosave is much safer once undo, journaling,
  or version history exists.

The restore command should be conservative: confirm or clearly indicate that the
current buffer will be replaced, load the hidden backup if present, and mark the
buffer dirty so the user can inspect it before saving it back over the original
file. Exact key bindings can be chosen with the rest of the TEC-1G keyboard
mapping.

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
