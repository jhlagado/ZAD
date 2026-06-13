# Editor Block Operations

This document defines the planned block editing model for the TECM8 editor.
It expands the roadmap item because block operations touch input handling,
display markers, source-record mutation, storage, prompts, and future
cross-file workflows.

## Design Goals

- Make line-block editing fast enough to use on a TEC-1G.
- Avoid using slow SD-card file writes as the normal copy/cut transport.
- Keep the first version whole-line based, matching the editor's fixed
  32-byte source records.
- Make the UI clear on a 128x64 GLCD with a 4-pixel gutter and no dialog boxes.
- Preserve the option for named block read/write later without making it the
  primary clipboard model.

## Vocabulary

TECM8 should avoid pretending it has a modern GUI clipboard in the normal hot
path. The editor has two related but separate block concepts:

```text
selection       the ordinary active destination range, shown with a thin gutter mark
pending copy    the source range armed by Copy, shown with a thick gutter mark
pending move    the source range armed by Cut/Move, shown with a sawtooth gutter mark
```

The pending copy/move source replaces the first-version clipboard. It is
anonymous and fast because it is editor state, not an immediately written file.
A named file block operation can still exist later for explicit import/export.

## Normal User Model

The normal workflow should be:

```text
Shift+Down selects lines
Ctrl-C arms those lines as a copy source
move somewhere else
Ctrl-V copies them there
```

or:

```text
Shift+Down selects lines
Ctrl-X arms those lines as a move source
move somewhere else
Ctrl-V moves them there
```

After `Ctrl-C` or `Ctrl-X`, the source block remains visible and marked with
the relevant source glyph. The user can then create a second ordinary selection
elsewhere. On paste, the pending source block is copied or moved into the
destination selection.

Implementation note: TECM8's editor key namespace uses `0x03` for arrow up, so
block copy/move are recognized as printable `C`/`X` plus Ctrl or Alt modifier
flags. They are not dispatched from raw ASCII control bytes.

## Key Bindings

Preferred bindings:

```text
Shift+Up          extend selection upward by one line
Shift+Down        extend selection downward by one line
Shift+Alt+Up      extend selection upward by one page
Shift+Alt+Down    extend selection downward by one page

Ctrl-C / Alt-C    arm selected block for copy
Ctrl-X / Alt-X    arm selected block for move
Ctrl-V / Alt-V    paste/apply pending block

Delete            delete selected block
Backspace         delete selected block, or remain ordinary line-join when no block is selected
Esc               clear ordinary selection

Ctrl-Q / Alt-Q    exit editor
Ctrl-Z / Alt-Z    restore from backup
Ctrl-W / Alt-W    write selected block to a named file, later
Ctrl-R / Alt-R    read a named block file, later
```

`Ctrl-R` is intentionally freed for read-block by moving restore-from-backup to
`Ctrl-Z`. `Ctrl-Q` and `Alt-Q` should be the exit commands; `Alt-X` can then
mean move/cut once the keymap migration is complete.

## Gutter Display

The GLCD gutter is a bitmap area, not limited to ASCII glyphs. It should carry
the line state cheaply without touching the source text columns.

Initial display states:

```text
blank       normal line
thin bar    ordinary selection / destination selection
thick bar   pending copy source
sawtooth    pending move/cut source
```

The thick bar says "this is the block that will be copied." The sawtooth says
"this is the block that will be moved or disposed of when paste completes."
That gives cut/move a different mood without requiring text inversion.

One possible 4x6 sawtooth cell is:

```text
1000
1100
1110
1111
1110
1100
```

A sharper, more serrated variant is:

```text
1000
1100
1110
1100
1000
0000
```

The exact pattern should be tested on the GLCD because a 4-pixel gutter gives
very little room. The renderer should keep the glyph vocabulary symbolic in the
editor state so a later TMS9918 backend can map these states to tile glyphs,
colors, or sprites.

If a visible row belongs to both the ordinary selection and pending block, the
pending source marker should win visually because it represents the source of a
future operation. If a row is both pending copy and pending move because of a
stale or invalid state, pending move should win and the editor should clear or
repair the invalid state at the next command boundary. Overlap rules still
decide whether paste is legal.

## Selection Semantics

The first implementation is whole-line only. The live selection uses an anchor
and an exclusive cursor endpoint. The cursor line is the place where the cursor
has arrived; it is not itself selected until the cursor moves past it with
Shift held.

Example:

```text
cursor line 4
Shift+Down       selects 4, cursor line 5
Shift+Down       selects 4..5, cursor line 6
Shift+Up         selects 4, cursor line 5
```

For operations, the anchor and exclusive endpoint are normalized to an
inclusive selected range:

```text
anchor 8, endpoint 5 => range 6..8
anchor 4, endpoint 6 => range 4..5
```

Movement without Shift clears the ordinary selection unless a command is
explicitly preserving it. Copy and move commands preserve the source as the
pending block. Paste and delete normally clear the ordinary destination
selection after the operation.

## Pending Block Semantics

`Ctrl-C` on a selection creates a pending copy block.

```text
source remains in place
source is shown with thick gutter markers
Ctrl-V duplicates the source at the destination
```

`Ctrl-X` on a selection creates a pending move block.

```text
source remains in place for now
source is shown with sawtooth gutter markers
Ctrl-V inserts it at the destination and removes the original source
```

Cut/move should not delete immediately. Delayed deletion avoids losing text if
the later paste cannot complete, and it avoids a slow SD-card write during the
normal cut command.

Any normal edit that changes source records outside the block operation should
clear the pending block. This prevents stale source references after the
document has changed underneath them. Cursor movement, selection movement, and
save do not need to clear the pending block.

## Paste Semantics

When there is no ordinary destination selection:

```text
Ctrl-V inserts the pending block before the current line.
```

When there is an ordinary destination selection:

```text
Ctrl-V replaces the selected destination range.
```

For copy mode, the source block remains. For move mode, the source block is
removed after the destination insertion/replacement succeeds.

The pasted block should become the ordinary selected range after paste. This
gives visible confirmation and allows a user to immediately move, delete, or
replace the newly pasted lines.

## Overlap Rules

Overlap must be explicit because there can be two selections at once:

```text
pending source range       thick or sawtooth gutter marker
ordinary destination range thin gutter marker
```

Recommended first-version rules:

- Copy from source into an overlapping destination is allowed only if the
  operation can be treated as a no-op or as insertion outside the source range.
- Move from source into itself is a no-op with a status message such as
  `Same block`.
- Move from source into a partially overlapping destination is rejected with a
  status message such as `Block overlap`.
- Replace-selection paste where the destination contains the move source is
  rejected in the first version.

These conservative rules avoid surprising deletion. More permissive behavior
can be added later after the basic implementation is proven.

## Delete Behavior

There is no separate `Alt-D` command in the first design. If a block is
selected, `Delete` acts on that block.

Recommended behavior:

```text
Delete selected block -> status prompt: Delete block? Y/N
Y                     -> remove selected lines
N / Esc               -> cancel
```

Backspace can either share this behavior when a block is selected or stay
disabled for block deletion in the first implementation. Ordinary Backspace
continues to join lines when no block is selected.

## Named Read And Write

Named block files are a separate, explicit feature. They should not be the
normal copy/cut/paste path because MON3 SD/FAT32 access is slow enough that a
file-backed clipboard would feel broken.

Planned commands:

```text
Ctrl-W / Alt-W   write selected block to a named file
Ctrl-R / Alt-R   read named block file at cursor or over selected destination
```

These operations need filename entry or a later file picker. They should show
status messages such as `Writing...` and `Reading...` and should be treated as
slow storage operations.

An anonymous hidden block file may still be useful later as a persistence or
cross-document exchange mechanism, but it should not be used for ordinary
copy/cut/paste inside one editor session.

## Source Record Metadata Bits

Each editor source record has a length byte:

```text
bits 0-4   text length, 0..31
bits 5-7   reserved metadata
```

Block selection should not initially use these metadata bits. The source range
and destination range are better represented as editor state intervals:

```text
selectionStartAbsLine
selectionEndAbsLine
pendingStartAbsLine
pendingEndAbsLine
pendingMode
```

Reasons:

- Selection and pending-copy/move state are transient UI state, not source
  content.
- Interval comparisons are cheaper than setting and clearing metadata bits
  across many lines while the user holds Shift+Down.
- Large selections may extend beyond the resident RAM window; marking each
  line would require loading and rewriting pages just to show transient state.
- The metadata bits should remain available for durable or semi-durable
  per-line states such as breakpoints, diagnostics, wrap flags, dirty markers,
  or debugger-related annotations.

The renderer can derive visible gutter markers from the active intervals for
rows currently on screen. It does not need selection bits stored inside each
source record.

If later hardware or UI constraints make interval checks too expensive, a
separate in-RAM line-state table for the resident edit window would be a better
intermediate step than writing transient selection bits into source records.

## State Model

Preferred compact editor state:

```text
EditorBlockSelectionActive
EditorBlockSelectionAnchorLo
EditorBlockSelectionAnchorHi
EditorBlockSelectionActiveLo
EditorBlockSelectionActiveHi

EditorBlockPendingActive
EditorBlockPendingMode          ; copy = thick gutter, move = sawtooth gutter
EditorBlockPendingStartLo
EditorBlockPendingStartHi
EditorBlockPendingEndLo
EditorBlockPendingEndHi
```

The line numbers should be absolute source-record indexes:

```text
absoluteLine = page * 16 + row
```

This keeps range normalization and visible-row checks simple. The practical
first version can use one byte if file size is capped low enough for the
current editor milestone, but the design should allow a 16-bit value because
the editor will eventually need more than 256 lines.

## Implementation Phases

### Phase B1: Keymap Cleanup

- Move quit to `Ctrl-Q` and `Alt-Q`.
- Move restore-from-backup to `Ctrl-Z` and `Alt-Z`.
- Reserve `Ctrl-R`/`Alt-R` for read block.
- Reserve `Ctrl-W`/`Alt-W` for write block.
- Decide whether old aliases remain temporarily for manual testing.

Done when Debug80 live smoke covers the new quit and restore bindings.

### Phase B2: Selection State And Gutter Markers

- Done: line selection state uses an anchor plus exclusive cursor endpoint,
  then normalizes to an inclusive range for operations.
- Done: `Shift+Up` and `Shift+Down` extend or shrink the ordinary selection;
  one `Shift+Down` selects only the line the cursor just left.
- Done in Phase B3: `Shift+Ctrl/Alt+Up` and `Shift+Ctrl/Alt+Down` page
  selection.
- Done: selected visible rows render with the thin gutter marker.
- Done: ordinary movement and editing clear the ordinary selection.

The current proof covers visible-range selection, ordinary movement clearing,
editing clearing, page-range selection, and pending source markers.

### Phase B3: Page Selection And Gutter Glyph Proofs

- Add `Shift+Alt+Up`/`Shift+Alt+Down` page selection.
- Add GLCD tile/display proofs for thin, thick, and sawtooth gutter glyphs.
- Ensure selection display works through viewport movement.

Done when page selection and all three gutter glyph families are covered by
proofs.

### Phase B4: Pending Copy/Move Source

- Done: `Ctrl-C`/`Alt-C` arm a selected source as pending copy.
- Done: `Ctrl-X`/`Alt-X` arm a selected source as pending move.
- Done: pending copy rows render with thick gutter markers.
- Done: pending move rows render with sawtooth gutter markers.
- Done: a second ordinary destination selection can coexist while the pending
  block remains visible.
- Done: pending blocks are cleared on ordinary source mutation.

`editor-selection-proof` covers pending copy source, pending move source, and
copy source plus a second thin destination selection.

### Phase B5: Paste Insert

- Done: `Ctrl-V`/`Alt-V` with no destination selection.
- Done: insert the pending block before the current line.
- Done: for copy mode, leave source intact.
- Done: for move mode, remove source after insertion succeeds.
- Done: select the pasted lines as the new ordinary selection.

The first implementation is deliberately conservative: it only pastes when the
pending source and insertion point are in the current resident 16-record page,
rejects overlap/self cases as no-ops, and requires enough blank tail records so
that no existing line is silently discarded. It uses the backup page buffer as a
transient scratch area during the operation.

`editor-selection-proof` covers copy/paste insert, move/paste insert, overlap
no-op, and blank-tail rejection within the resident editor window.

### Phase B6: Paste Replace And Overlap Handling

- Done: if a destination selection exists, paste replaces it when the source
  and destination are equal-sized resident-page ranges.
- Done: copy-replace leaves the source intact.
- Done: move-replace deletes the original source after replacement succeeds and
  selects the moved rows at their adjusted location.
- Done: unsafe partial overlaps and exact self-overlaps are rejected as no-ops
  by the replacement path.

`editor-selection-proof` covers copy-replace and move-replace. The overlap
rejection path is kept conservative in code; a separate compact proof should be
added later if this proof grows too large for stable storage-backed runs.

### Phase B7: Delete Selected Block

- Done: `Delete` on an ordinary selected block opens a status-line
  confirmation prompt.
- Done: `N` cancels without changing the selected block.
- Done: `Y` deletes the selected whole-line range, shifts following records up,
  clears the tail records, clears selection state, and marks the editor dirty.
- Done: ordinary character `Delete` behavior remains unchanged when no block is
  selected.

`editor-block-delete-proof` covers cancel and confirm behavior on a selected
block.

### Phase B8: Debug80 Block Editing V1 Acceptance

- Done: `debug80:editor-block-smoke` boots the editor in Debug80 matrix mode,
  selects lines with `Shift+Down`, arms copy with `Alt-C`, pastes with `Alt-V`,
  saves with `Alt-S`, and validates the saved TM8 source records from the host
  side.
- Done: `acceptance:block-editing-v1` runs the selection/paste proof, the
  delete proof, the Debug80 block smoke, and prepares the manual Debug80 block
  fixture image.
- Done: this document provides the manual keyboard test script below.

Done when Block Editing V1 is manually testable in Debug80.

### Deferred: Named Block Read/Write

- Add filename prompt support if it is not already sufficient.
- Implement `Ctrl-W`/`Alt-W` write selected block to named file.
- Implement `Ctrl-R`/`Alt-R` read named block at cursor or over destination
  selection.
- Show slow-operation status feedback.

Done when block transfer through named files works and normal copy/cut/paste
still avoids unnecessary SD writes.

## Manual Test Script Target

Run:

```sh
npm run debug80:editor-block-image
```

Then launch `demos/debug80/editor-session-fat32.img` in Debug80, start the
program at `0x4000` from MON3, and use the matrix keyboard.

The current resident-page implementation is deliberately conservative. It is
best to test block paste in a file with blank tail rows, such as the prepared
demo image, so insertion has room to shift records down.

Manual script:

```text
1. Press Shift+Down once. Row 0 should show the thin selection gutter and row
   1 should remain the current cursor row.
2. Press Alt-C. Row 0 should change to the thick pending-copy gutter.
3. Press Escape. The pending-copy gutter should clear. Select row 0 again with
   Shift+Down and press Alt-C to re-arm copy.
4. Press Down three times to move to row 4.
5. Press Alt-V. Row 0 should be copied before row 4 and the pasted row should
   become the thin selected destination block.
6. Press Alt-X. The pasted rows should change to the sawtooth pending-move
   gutter.
7. Press Down a few rows, then Alt-V. The moved rows should reappear at the new
   position and the old source rows should close up.
8. Select a destination range with Shift+Down, arm another source with Alt-C or
   Alt-X, and press Alt-V. Equal-sized resident-page ranges should replace;
   unsafe overlaps should leave the text unchanged.
9. Select a block and press Delete. Answer N first; the block should remain.
10. Press Delete again and answer Y; the selected whole-line block should be
   removed and following lines should shift up.
11. Press Alt-S. The editor should show saving feedback and return with the
    edited rows still visible.
```
