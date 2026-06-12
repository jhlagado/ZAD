# TECM8 Roadmap

This is the live roadmap for TECM8. It records the current editor direction,
completed foundation, substantial future phases, milestone definitions, and
manual testing expectations. Update this file after meaningful phase changes so
the roadmap does not live only in conversation history.

## Current Goal: Post-Milestone Manual Validation

The Debug80-testable editor milestone has been reached in the local automated
proof harness. The remaining validation is human-facing: run the manual Debug80
script in the UI, then defer Phase 14 real-hardware checks until a TEC-1G is
available.

## Completed Foundation

- TM8 host volume tooling exists for format, info, list, create, remove, rename,
  raw import/export, copy, pack, and unpack.
- Source text conversion exists: `fs import-text` writes 32-byte records and
  `fs export-text` validates those records and writes host text.
- `/tecm8.prj` can be created by host tools and read by TEC-side Z80 proof code.
- Shell command resolution for `edit`, `asm`, and `run` is proven against the
  project defaults and named targets.
- MON3-backed BIOS storage and GLCD display wrappers exist.
- The editor can load and render storage-backed source pages.
- Shell `edit` can launch the editor path in proofs.
- Cursor movement, in-page insert/delete, split-line/newline, and
  backspace-at-start join are implemented and covered by AZM/Debug80 proofs.
- The editor can write the current 512-byte page buffer back to the currently
  loaded TM8 source page, with proof coverage that persisted bytes survive in
  the FAT32/TM8 image.
- The editor tracks unsaved edits, marks dirty after mutation, accepts save
  commands, and clears dirty after successful save.
- The editor has a status-line yes/no prompt state: unrelated keys are ignored,
  yes/no answers complete the prompt, and the hidden source row is redrawn after
  completion.
- The editor derives the hidden backup path, creates it when missing, and saves
  previous on-disk resident pages there before writing edited resident pages to
  the source file.
- The editor can restore the hidden backup into the resident current/next page
  window through a status-line confirmation prompt and marks restored sectors
  dirty.
- The editor can quit from the key stream; clean pages exit immediately, while
  dirty pages require status-line confirmation before discarding changes.
- The live Debug80 entry shows a bottom-row shell-ready marker after the editor
  exits, so manual testing has a visible return point even before a full
  interactive shell prompt exists.
- Shell `edit name` can create a missing one-block `.asm` source file in an
  existing prefix before opening it.
- Page-boundary movement now gives explicit transient `Top` feedback at the
  first page. Page-down past the available source keeps visible source rows
  intact instead of overlaying a confusing end marker.
- Source-record padding is kept clean after in-page mutations so host export
  validation remains meaningful.
- Sector-edge editing has proof coverage for split pushing into the adjacent
  next sector and Backspace joining into the cached previous sector.
- Design policies exist for reserved source-record length bits, hidden dotfiles,
  one-level editor backups, and status-line confirmation prompts.
- `src/main.asm` is a Debug80-runnable TECM8 editor session entry.
- `npm run debug80:editor-session` generates a prepared FAT32/TM8 image and
  proves the user-facing edit/save/quit/reopen workflow against Debug80.
- `BiosInputPollKey` exposes translated key codes, modifier flags, and raw
  matrix scan diagnostics so the Debug80 editor can be driven from real matrix
  arrow keys and modifier chords.
- A TECM8-owned GLCD tile-cell layer exists for 6x6 text cells. Structured
  screen text rendering now writes through tile primitives rather than MON3's
  terminal character drawing routine.
- TECM8 Tiled GLCD Renderer V1 was reached: cursor movement and ordinary
  in-line edits no longer depend on MON3 terminal character drawing.
- Editor Line Editing V2 was reached by `npm run debug80:editor-live-smoke` and
  commit `040dbf5`: matrix Enter splits a line, split contents save and survive
  page movement, matrix Backspace rejoins, and the joined state saves.
- Phase 1 input polish is complete enough for the current milestone: unknown
  Ctrl/Alt-modified printable keys are ignored with `KEY`, dirty page movement
  works inside the RAM window, and the live Debug80 smoke covers restore-prompt
  cancel.
- Phase 15 Debug80 automation is complete at commit `5bcfe80`: the editor can
  create a missing source file, edit and save source pages, move through the
  prepared multi-page fixture, restore backup state, quit cleanly, and show the
  shell-ready marker after exit. `debug80:editor-session`,
  `debug80:editor-live-smoke`, and the storage-backed proof suite cover the
  executable milestone behavior.

## Target Editor Milestone

The editor is complete enough when a user can use Debug80, and later real
TEC-1G hardware, to edit a practical `.asm` source file inside a TECM8 project,
save it safely, navigate around it, recover from common mistakes, and return to
the shell without losing work.

The current editor is past the first proof stage. It can load `/src/main.asm`,
render records, edit characters, split/join lines inside one page, save, backup,
restore, and page through the prepared fixture. The remaining work is mostly
about making it usable as a real editor rather than a proof harness.

## Phase 1: Editor Reliability And Input Polish

Goal: make the current editor behavior predictable under manual Debug80 testing.

Work:

- Stabilize all live matrix key paths.
- Confirm `Enter`, `Backspace`, `Delete`, arrows, `Alt-S`, `Alt-X`, `Alt-R`,
  and page movement.
- Add clear status feedback for ignored commands, failed saves, failed loads,
  and RAM-window/page-boundary limits.
- Decide whether unknown modified printable keys should insert text or be
  ignored.
- Add more live smoke coverage for real matrix keys.

Done when:

- A user can follow a manual script without ambiguous "did that key work?"
  moments.
- Debug80 smoke verifies every major key command.

## Phase 2: Multi-Page Editing

Goal: move beyond editing one 512-byte page independently and stop treating SD
sector reads as an ordinary navigation operation.

Work:

- Done: make all source-record length handling metadata-safe: read length as
  `byte0 & 0x1F`, preserve bits 5-7 when rewriting lengths, and add tests/proofs
  that metadata bits survive insert/delete/split/join/render paths.
- Done: allow a split near the end of a full page to push row 15 into the next
  page when the adjacent sector is resident and has space.
- Done: allow Backspace at row 0 to join with the cached previous page.
- Done: replace the current one-page cache with a small RAM edit window large
  enough to absorb immediate adjacent navigation without touching SD.
- Done: avoid SD writes until explicit save, and then write back resident dirty
  sectors.
- Done: pressing Enter on row 15 can create the first record in the adjacent
  page when that page is resident and has room.
- Done: saving a new page inside the file's existing 4K allocation block grows
  the TM8 catalog byte size safely.
- Done: saving page 8 of a one-block source file extends the TM8 allocation
  chain, updates the superblock free-block count/checksum, and grows the
  catalog byte size to the new sector boundary.

Likely design:

- Current implementation keeps an active sector, adjacent next sector, and one
  previous-page cache. A 2K or 4K RAM edit window remains the likely later
  target if memory pressure allows it.
- Treat each 512-byte sector as 16 fixed records.
- A 2K window holds 64 lines; a 4K window holds 128 lines.
- Preload adjacent sectors around the visible viewport, because the MON3
  SD/FAT32 path is slow enough that per-sector navigation will feel broken on
  100-200 line files.
- On cross-page insert/delete, shift records across page boundaries.
- Avoid SD writes until explicit save, and then write back only resident dirty
  sectors.

Done when:

- You can create new lines past the end of the current page.
- Page up/down shows the reshaped file correctly.
- Save persists resident dirty sectors that already belong to the TM8 file.
- Save persists a grown file when the new sector still fits inside the existing
  4K allocation block.
- Save persists a grown file when the new sector crosses a 4K allocation-block
  boundary and requires a new TM8 data block.
- Metadata bits in each source-record length byte are preserved unless a
  deliberately defined editor metadata operation changes them.
- Moving around a file within the RAM window does not perform SD reads.

## Phase 3: Better Viewport Navigation

Goal: make files longer than one screen usable inside the multi-sector RAM
window.

Work:

- Done: separate logical cursor row from visible screen row.
- Done: add vertical scrolling within a 16-record page.
- Done: keep page movement over source pages working with the viewport state.
- Deferred: add top-of-file and end-of-file movement once a compact binding is
  chosen.
- Done: keep visible cursor/location state available as page, logical row,
  visible row, and viewport top row.

Design issue:

The GLCD shows 10 rows, but a page has 16 records. The editor needs a viewport
over the page, not just fixed rows 0-9.

Done when:

- You can move through all 16 records of a page, not only visible rows.
- Cursor movement scrolls the viewport when needed.
- Location context exists in editor state for page, logical row, visible row,
  and viewport top row; a richer user-facing status string remains part of
  Phase 6 command/status UX.

## Phase 4: Horizontal Editing

Goal: support the full 31-character source record.

Work:

- Done: add a horizontal viewport over the 31-character source record.
- Done: pan only when the logical cursor moves beyond the 20 visible text
  columns.
- Done: keep the gutter separate from text; horizontal panning shifts only the
  source text slice.
- Done: track logical column, visible column, and viewport column offset so the
  cursor position is not silent when editing beyond the visible display.

Likely compromise:

- Implement horizontal panning only when cursor moves past visible column 19.
- Status line can show `Ln n Col n`.

Done when:

- You can edit all 31 characters in a record.
- The cursor never silently moves into invisible text.

## Phase 5: Save, Backup, Restore Hardening

Goal: make save behavior safe enough for real use.

Work:

- Done: keep the current hidden backup convention: `/src/.main.asm.b`.
- Done: ensure backup creation handles dirty resident current, cached previous,
  and adjacent next pages.
- Done: back up a dirty adjacent next page before save writes it.
- Done: restore the resident current/next page window from backup and mark
  restored sectors dirty.
- Deferred: ensure failed save is atomic across all dirty resident pages.
- Done: keep restore-from-backup UX status-line based and recoverable.
- Decide whether backup is per file, per page, or whole file.

Important:

The current implementation is a resident-window backup, not a full-file backup.
For a real editor, backup should probably preserve the previous full file, but
that requires whole-file copy/truncation behavior that is beyond this phase.

Done when:

- Save preserves the previous on-disk contents for every dirty resident page it
  is about to overwrite.
- Restore works for the resident multi-page window.
- Automated proofs cover dirty adjacent-page backup and restore behavior.

## Phase 6: Status Prompt And Command UX

Goal: make modal editor actions usable without dialog boxes.

Work:

- Done: refine transient status row behavior enough that boundary messages use
  the same overlay/restore path as prompts and slow storage messages.
- Done: add prompts or status messages for discard dirty changes, restore
  backup, ignored modified keys, clean save, save-before-page-move, and
  top/end page boundaries.
- Deferred: add user-facing status messages for save failure, load failure,
  file full/page full, overwrite, and replace.
- Add timeout or explicit dismiss behavior for informational messages.
- Done: keep the status row transient; it temporarily hides source row 9 and
  restores it afterward.

Likely direction:

Use transient bottom-row prompts. They obscure a row briefly, then restore it.

Done when:

- Every slow or risky operation tells the user what is happening.
- Prompt mode ignores unrelated keys safely.
- The source row underneath the prompt is restored cleanly.
- Page-up at the first page provides explicit `Top` feedback. Page-down past
  available source restores the hidden row cleanly without drawing an end label.

## Phase 7: Display Performance

Goal: make the editor feel usable on slow GLCD hardware.

Work:

- Treat display updating as a cooperative task. Matrix keyboard scanning has no
  interrupt, so long GLCD transfers must not monopolize the CPU. The editor loop
  should eventually poll input first, handle a key if present, then perform only
  a bounded slice of pending display work before polling input again.
- Treat vertical cursor movement as the first display-performance target.
  Manual Debug80 testing shows left/right movement is already acceptably fast
  because it mostly updates the cursor overlay, while up/down movement is slow
  enough to dominate the editing feel. The current row-change path repaints the
  old and new source rows so the cursor marker can move; Phase 7 should replace
  that with a pixel/tile-delta update for only the affected cursor/marker bytes.
- Done: ordinary full viewport repaint no longer calls `BiosDisplayClear`
  before drawing the tile layout. Each rendered row clears its own text cells and
  overwrites the gutter, so short lines replacing long lines do not leave stale
  glyph pixels.
- Done: introduced row-scoped GLCD flush scheduling. Cursor overlays, status
  overlays, current-line redraws, and vertical current-row marker changes now
  call `GlcdTileFlushRow` instead of the full-flush API.
- Done: replaced the MON3-backed row flush with a TECM8-owned row-range GLCD
  backend. `GlcdTileFlushRow` now selects ST7920 graphics mode, sets the
  graphic row and banked horizontal address directly, and writes the 96 bytes
  that make up one 6-pixel editor text row. Full viewport renders still use
  `GlcdTileFlushFull` and MON3 `plotToLCD`.
- Done: added the first cooperative display step primitive. `GlcdTileQueueRow`
  prepares one dirty editor row, and `GlcdTileStep` transfers one physical
  16-byte GLCD row per call, returning whether more display work remains.
  `GlcdTileFlushRow` remains a synchronous compatibility wrapper that queues and
  drains all six steps. The live editor idle path now calls `GlcdTileStep`, so
  later non-blocking render paths have a place to advance pending display work
  between keyboard polls.
- Done: moved the first real editor paths onto cooperative dirty-row scheduling.
  `GlcdTileMarkRowDirty` records dirty text rows in a small row mask, and
  `GlcdTileStep` starts the next marked row when no row transfer is already
  pending. Current-line redraws and vertical cursor marker moves now mark rows
  dirty instead of synchronously flushing them.
- Done: added dirty cell-range scheduling for cursor overlays. `GlcdTileMarkCellDirty`
  records the minimum and maximum GLCD byte columns touched by a dirty text cell,
  and `GlcdTileStep` transfers only that byte span across the six physical GLCD
  rows. Horizontal cursor movement and simple edit cursor restore/redraw now use
  cell-range transfers instead of spending full 96-byte row flushes for cursor
  work.
- Done: narrowed non-scrolling vertical cursor movement. Current-row gutter
  marker changes now call `GlcdTileMarkGutterDirty`, which transfers only the
  word-aligned gutter byte pair for each affected row. The dirty-render proof
  now requires ordinary cursor movement to use zero full row flushes.
- Done: added cooperative cursor blink. The live idle path runs one
  `GlcdTileStep` first and advances `EditorCursorBlinkStep` only when no
  queued display work remains; when the blink countdown is due it hides or
  restores the XOR insertion cursor through the existing dirty cell byte-range
  path, without viewport, row, or gutter redraws.
- Done: extended dirty cell-range scheduling to simple printable insert/delete
  and non-joining backspace. These paths still rebuild the row text in the
  backing buffer for pixel correctness, but they transfer only the clipped
  changed cell range plus cursor overlay cells instead of queueing a full source
  row flush.
- Done: added first-pass display-work coalescing. A full dirty row now
  supersedes queued cell-range work for that row, and later cell/gutter marks
  for an already dirty full row are ignored so stale narrow updates do not drain
  before the latest row state.
- Done: added bounded-step measurements for common dirty-render operations:
  movement, insert, delete, non-joining backspace, and cursor blink now record
  and assert `GlcdTileStepCount` as well as byte counts.
- Add a small display work queue or dirty mask:
  - full viewport dirty for page loads, restore, and explicit redraw
  - dirty row for vertical cursor movement, line edits, status prompt restore
  - dirty cell range for simple character insert/delete
  - cursor dirty for cursor blink/overlay updates
- Add a `DisplayStep`-style primitive that performs one bounded GLCD update
  slice and returns whether more display work remains.
- Refactor the live editor loop toward:

  ```text
  poll keyboard
  if key pending: handle key and schedule display work
  else: perform one display update slice
  repeat
  ```

- Coalesce display work when keys arrive faster than the GLCD can update. The
  latest editor state should win; stale intermediate cursor paints should not
  build up as a backlog.
- Preserve the optimized cursor redraw rule: cursor movement and blinking
  should update only the affected cursor cell/bytes, never the whole GLCD.
- Keep blink work cooperative: blink toggles should be skipped or delayed while
  more important dirty display work is being drained, and should not reduce
  keyboard polling frequency beyond one bounded idle slice.
- Measure instruction counts for common operations.
- Finish this efficiency work before starting block operations. Block copy,
  delete, move, and read/write are useful, but they will add more redraw and
  storage pressure; the display scheduler should be settled first.

Incremental implementation order:

1. Keep full tile repaint, but remove unnecessary clear-first behavior.
2. Done: introduce dirty row scheduling while still flushing through MON3.
3. Done: replace MON3-backed row flushes with a TECM8-owned row-range GLCD
   flush backend.
4. Done: introduce `GlcdTileStep` and call it from live editor idle.
5. Done: add a dirty-row mask and use it for current-line edits and vertical
   cursor row-marker movement.
6. Done: add dirty cell ranges for horizontal movement and edit cursor overlays.
7. Done: replace non-scrolling vertical current-row marker flushes with gutter
   byte-range transfers.
8. Done: add cursor blink once cursor updates are cheap.
9. Done: replace simple printable insert/delete row flushes with clipped dirty
   cell-range transfers.
10. Done: coalesce dirty row work against stale dirty cell ranges.
11. Done: measure bounded GLCD steps for common dirty render paths.

Proofs:

- Dirty row render.
- Dirty cell render.
- Cursor move without full render.
- Cursor blink without row/full render.
- Insert/delete without full render.
- Cooperative display-step proof: a pending display update can be advanced in
  bounded slices without losing a queued/polled key event.

Done when:

- Typing a character updates quickly enough to feel interactive.
- Horizontal and vertical cursor movement are both visibly cheap; up/down no
  longer repaints two complete text rows.
- A long repaint can be interrupted between bounded GLCD slices by keyboard
  polling, so matrix-key input does not depend on users holding keys for the
  duration of a full-screen update.
- Save/load can still be slow, but editing should not be.

## Phase 8: File Picker And Editor Launch

Goal: make `edit` useful beyond the default main file.

Work:

- `edit` opens project main file.
- `edit name` opens `/src/name.asm` by convention.
- `edit /path/file.asm` opens exact path.
- Done: missing files are an explicit open error for now. Prompted creation is
  deferred until the editor has file-listing and prompt flows suitable for it.
- Decide whether editing `/tecm8.prj` is supported or whether the editor is
  restricted to source/text files.

Design decision:

The editor should probably be a text editor, not only an `.asm` editor, but
`.asm` remains the default extension.

Done when:

- A user can edit multiple files in a project without long paths.
- Missing files are handled intentionally.

## Phase 9: File Listing And Hidden Files

Goal: make project navigation practical.

Work:

- Done: implement TEC-side visible-file listing for a TM8 prefix, enough for
  editor selection.
- Done: hide leading-dot files from ordinary listings.
- Done: make backups invisible by default.
- Add optional listing of hidden files later.

Done when:

- `.main.asm.b` does not clutter normal project views.
- Users can find and edit source files from inside TECM8.

## Phase 10: Integration With Shell

Goal: make the editor part of the Turbo Pascal-like command loop.

Work:

- Done: shell prompt can run a bounded sequence of commands in one initialized
  shell session.
- Done: the one-shot shell editor launcher runs `edit` and enters the editor.
- Done: the bounded command loop dispatches `edit`, `asm`, and `run` in order
  through executor stubs.
- `Alt-X` or quit returns to shell.
- Done: `asm` resolves the project main file and derived `/build/<stem>.bin`
  plus `/build/<stem>.map` request paths; actual assembler execution remains a
  later tool/runtime increment.
- Done: `run` resolves the derived binary path; actual binary launch remains a
  later runtime increment.
- Done: preserve simple project defaults from `/tecm8.prj`.

Current proof boundary:

The one-shot shell editor launcher opens the editor. The bounded shell command
loop now proves `edit`, `asm`, and `run` dispatch in order from one prompt
session. The bounded loop's executor entries are still stubs, so the live user
flow is not yet a real edit-assemble-run cycle.

Done when:

- User flow is: boot TECM8, `edit`, save, exit, `asm`, `run`.
- Until the assembler and runner exist, Phase 10 is considered complete at the
  command-loop and dispatch boundary, not at real assembly/execution.

## Phase 11: Source Format And Text Import/Export

Goal: ensure source files remain compatible between host tools and TECM8.

Work:

- Done: preserve 32-byte fixed records.
- Done: validate length bytes and record padding on `export-text`.
- Done: high bits in the source-record length byte are treated as metadata and
  masked on export.
- Done: confirm `export-text` handles edited files.
- Done: default project `pack`/`unpack` omits leading-dot hidden backups such
  as `/src/.main.asm.b`; explicit raw operations can still name them directly.

Done when:

- Done: a file edited in TECM8 exports cleanly to host `.asm`.
- Done: a host-imported `.asm` edits cleanly in TECM8.

## Phase 12: Error Handling

Goal: stop silent failures.

Work:

- Done: added user-visible error states for disk open failure, read failure,
  write failure, full file/catalog/allocation, and unsupported file size.
- Deferred: invalid source-record UI errors remain a later editor/import
  validation task.
- Done: added compact status-row error strings such as `ERR OPEN 30`,
  `ERR READ 35`, `ERR WRITE 38`, `ERR FULL 39`, and `ERR SIZE 34`.
- Done: preserved `EditorLastErrorCode` and `EditorLastErrorTextPtr` for
  Debug80/hardware troubleshooting.

Done when:

- Done: the GLCD status row shows useful errors instead of unexplained lockups
  on the editor failure path.
- Done: `editor-error-handling-proof` covers the major compact error-code
  mappings and an actual invalid-page loader failure.

## Phase 13: Memory Layout

Goal: make the editor viable on a constrained TEC-1G memory map.

Work:

- Done: documented editor RAM usage in `docs/memory-and-code-quality.md`.
- Done: kept source page buffers above MON3/GLCD volatile areas.
- Done: assigned `3000h-3FFFh` as the current editor workspace.
- Done: fixed a 2K resident source-sector workspace at `3000h-37FFh`; `3800h`
  to `3FFFh` is reserved for future growth.
- Done: avoided relying on MON3 RAM that GLCD/storage overwrites.

Done when:

- Done: editor memory map is explicit.
- Done: page buffers, cache, status state, and scratch areas have stable
  locations.

## Phase 14: Hardware Transition

Goal: prepare to move from Debug80 proof to real TEC-1G.

Status: skipped in the current automation loop. Real hardware testing needs the
user and cannot be completed by Codex alone.

Work:

- Confirm MON3 service assumptions.
- Test SD latency and GLCD latency on real hardware.
- Identify Debug80-specific differences.
- Produce simple repro scripts for emulator bugs.
- Keep TECM8 code independent of Debug80-only conveniences.

Done when:

- Same image/program can be launched at `4000h` on Debug80 and hardware.
- Known differences are documented.

## Phase 15: Editor Completion Milestone

This is the point where the editor is substantially complete.

Done criteria:

- Edit an existing `.asm` file.
- Create a new source file.
- Insert and delete characters.
- Split and join lines across pages.
- Move through a multi-page file.
- Save the full file.
- Restore backup.
- Quit cleanly.
- Return to shell.
- Export the edited file on the host and verify content.
- Manual Debug80 test script passes.
- Automated Debug80 smoke covers core behavior.

Status: automated Debug80 milestone complete at commit `5bcfe80`. The manual
Debug80 script remains the human acceptance check, and Phase 14 is intentionally
skipped until a human can test real hardware.

## Future Phase: Block Operations

Detailed design: [Editor Block Operations](block-operations.md).

Goal: add line-oriented block editing with fast in-session copy/move behavior
and later named file read/write support. The milestone for this roadmap section
is **Block Editing V1**: a user can select line ranges, mark copy and move
sources, paste or replace a destination range, delete a selected block, and
verify the result in Debug80 without relying on SD-card clipboard writes.

Direction:

- Treat ordinary block copy/cut/paste as editor state, not an SD-card clipboard
  file.
- Use three gutter states: thin bar for ordinary destination selection, thick
  bar for pending copy source, and sawtooth edge for pending move/cut source.
- Use `Shift+Up/Down` and later `Shift+Alt+Up/Down` to select whole lines.
- Use `Ctrl-C`/`Alt-C` to arm a pending copy source, `Ctrl-X`/`Alt-X` to arm a
  pending move source, and `Ctrl-V`/`Alt-V` to paste or replace.
- Move quit back to `Ctrl-Q`/`Alt-Q` and move restore-from-backup to
  `Ctrl-Z`/`Alt-Z`, freeing `Ctrl-R`/`Alt-R` for named block read.
- Use `Delete` on a selected block rather than adding a separate delete-block
  command.
- Represent source and destination selections as line-range intervals in editor
  state. Do not use the source-record length metadata bits for transient block
  selection.
- Add named `Ctrl-W` write-block and `Ctrl-R` read-block later as explicit slow
  file operations.

Sequenced goals:

1. **Block Phase B1: Keymap Cleanup**
   - Move quit to `Ctrl-Q`/`Alt-Q`.
   - Move restore-from-backup to `Ctrl-Z`/`Alt-Z`.
   - Reserve `Ctrl-R`/`Alt-R` for read-block and `Ctrl-W`/`Alt-W` for
     write-block.
   - Update live smoke and manual docs.

2. **Block Phase B2: Selection Range And Thin Gutter**
   - Add ordinary line-selection interval state.
   - Implement `Shift+Up`/`Shift+Down`.
   - Render selected visible rows with the thin gutter marker.
   - Clear selection on ordinary movement and editing.

3. **Block Phase B3: Page Selection And Gutter Glyph Proofs**
   - Add `Shift+Alt+Up`/`Shift+Alt+Down` selection by page.
   - Add GLCD tile/display proofs for thin, thick, and sawtooth gutter glyphs.
   - Ensure selection display works through viewport movement.

4. **Block Phase B4: Pending Copy And Move Source**
   - `Ctrl-C`/`Alt-C` turns the ordinary selection into a pending copy source
     with a thick gutter marker.
   - `Ctrl-X`/`Alt-X` turns the ordinary selection into a pending move source
     with a sawtooth gutter marker.
   - Allow a second ordinary destination selection while the pending source
     remains visible.

5. **Block Phase B5: Paste Insert**
   - `Ctrl-V`/`Alt-V` inserts the pending source before the cursor when no
     destination selection is active.
   - Copy leaves source intact; move removes source only after insertion
     succeeds.
   - The pasted block becomes the ordinary selected range.

6. **Block Phase B6: Paste Replace And Overlap Handling**
   - `Ctrl-V`/`Alt-V` replaces an ordinary destination selection.
   - Reject unsafe move/copy overlaps with status feedback.
   - Treat exact move-to-self as a no-op.

7. **Block Phase B7: Delete Selected Block**
   - `Delete` acts on selected blocks.
   - Add status-line confirmation.
   - Preserve source-record metadata bits and clean padding.

8. **Block Phase B8: Debug80 Block Editing V1 Acceptance**
   - Add automated Debug80 smoke coverage for selection, copy, move, replace,
     overlap rejection, delete, save, and host export validation.
   - Provide a short manual keyboard test script.
   - Stop at this milestone for manual validation.

Deferred after Block Editing V1:

- `Ctrl-W`/`Alt-W` named block write.
- `Ctrl-R`/`Alt-R` named block read.
- Any anonymous hidden block file for cross-document persistence.
- Character-precise selections.

Block Editing V1 done criteria:

- A user can select a whole-line range with Shift movement.
- A user can mark that range as a thick pending copy source or sawtooth pending
  move source.
- A user can create a second thin destination selection and paste into or over
  it.
- Overlapping move/copy cases are predictable and do not lose text.
- Delete on selected block is confirmed and safe.
- Save persists the reshaped source.
- Host export still validates the edited source records and metadata bits.

## Likely Next Practical Milestone After Phase 1

The next sizeable milestone after the reliability phase should be **Multi-Page
Source Editing V1**.

Definition:

The editor can edit a file longer than one 512-byte page, insert lines that push
content across page boundaries, save the grown/reshaped file, page away and
back, and reopen to confirm persistence.

That is the next meaningful leap because it changes the editor from a page
editor to a file editor.

## Deferred Design Work

- Implement cleanup for hidden `.b` backups.
- Decide whether to use source-record length bits 5-7 for line metadata.
- Decide whether the current low-cost blinking insertion caret remains the
  preferred cursor shape, or whether to return to a block cursor.
- Revisit block operations after Phase 7 display efficiency is settled.
- Revisit MON3-to-BIOS reductions once editor storage/display requirements are
  better measured.
