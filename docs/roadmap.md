# TECM8 Roadmap

This is the live roadmap for TECM8. It records the current editor direction,
completed foundation, substantial future phases, milestone definitions, and
manual testing expectations. Update this file after meaningful phase changes so
the roadmap does not live only in conversation history.

## Current Goal: Phase 1 - Editor Reliability And Input Polish

The next editor goal is to make the current Debug80 editor behavior predictable
under manual testing. The editor already proves loading, rendering, character
editing, line split/join inside a page, save, backup, restore, and page
movement. The remaining problem for this phase is confidence: every live matrix
key and risky editor command should have clear behavior, clear feedback, and
coverage that makes regressions obvious.

Phase 1 is complete when a user can follow a manual Debug80 script without
ambiguous "did that key work?" moments, and the automated Debug80 smoke verifies
every major key command.

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
  the previous on-disk page there before writing the edited page to the source
  file.
- The editor can restore the hidden backup into the current page buffer through
  a status-line confirmation prompt and marks the restored buffer dirty.
- The editor can quit from the key stream; clean pages exit immediately, while
  dirty pages require status-line confirmation before discarding changes.
- Source-record padding is kept clean after in-page mutations so host export
  validation remains meaningful.
- Sector-edge editing policy is conservative today: split on the final row and
  join before the first row are no-ops rather than implicit cross-sector shifts.
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
- Phase 1 input polish has started: unknown Ctrl/Alt-modified printable keys
  are ignored with `KEY`, dirty page movement reports `Save first`, and the
  live Debug80 smoke covers dirty page blocking and restore-prompt cancel.

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
  and dirty-page restrictions.
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

- Make all source-record length handling metadata-safe: read length as
  `byte0 & 0x1F`, preserve bits 5-7 when rewriting lengths, and add tests/proofs
  that metadata bits survive insert/delete/split/join/render paths.
- Allow line insertion at the end of a page to push records into the next page.
- Allow Backspace at row 0 to join with the previous page.
- Decide what happens when the file grows and needs a new sector/page.
- Update the TM8 allocation/write path to extend a file safely.
- Replace the current one-page cache with a RAM edit window large enough to
  absorb common navigation without touching SD.

Likely design:

- Keep a 2K or 4K RAM edit window if feasible.
- Treat each 512-byte sector as 16 fixed records.
- A 2K window holds 64 lines; a 4K window holds 128 lines.
- Preload adjacent sectors around the visible viewport, because the MON3
  SD/FAT32 path is slow enough that per-sector navigation will feel broken on
  100-200 line files.
- On cross-page insert/delete, shift records across page boundaries.
- Avoid SD writes until explicit save, and then write back only dirty sectors.

Done when:

- You can create new lines past the end of the current page.
- Page up/down shows the reshaped file correctly.
- Save persists a grown file.
- Metadata bits in each source-record length byte are preserved unless a
  deliberately defined editor metadata operation changes them.
- Moving around a file within the RAM window does not perform SD reads.

## Phase 3: Better Viewport Navigation

Goal: make files longer than one screen usable inside the multi-sector RAM
window.

Work:

- Separate logical cursor row from visible screen row.
- Add vertical scrolling within a 16-record page.
- Add page movement over source pages.
- Add top-of-file and end-of-file movement, if a compact binding is available.
- Add visible indication of current page/line.

Design issue:

The GLCD shows 10 rows, but a page has 16 records. The editor needs a viewport
over the page, not just fixed rows 0-9.

Done when:

- You can move through all 16 records of a page, not only visible rows.
- Cursor movement scrolls the viewport when needed.
- Status shows enough location context to stay oriented.

## Phase 4: Horizontal Editing

Goal: support the full 31-character source record.

Work:

- Add horizontal scrolling or a horizontal viewport.
- Decide whether the first 20 visible columns are enough for now.
- Keep the gutter separate from text.
- Make cursor position clear when editing columns beyond the visible display.

Likely compromise:

- Implement horizontal panning only when cursor moves past visible column 19.
- Status line can show `Ln n Col n`.

Done when:

- You can edit all 31 characters in a record.
- The cursor never silently moves into invisible text.

## Phase 5: Save, Backup, Restore Hardening

Goal: make save behavior safe enough for real use.

Work:

- Keep the current hidden backup convention: `/src/.main.asm.b`.
- Ensure backup creation handles multi-page files.
- Ensure failed save does not destroy the old file.
- Add restore-from-backup UX that is clear and recoverable.
- Decide whether backup is per file, per page, or whole file.

Important:

For a real editor, backup should probably preserve the previous full file, not
only the currently edited page.

Done when:

- Save either fully succeeds or leaves the previous file recoverable.
- Restore works for a multi-page file.
- Manual tests prove failed/edge cases where possible.

## Phase 6: Status Prompt And Command UX

Goal: make modal editor actions usable without dialog boxes.

Work:

- Refine transient status row behavior.
- Add prompts or status messages for discard dirty changes, restore backup,
  save failure, file full/page full, overwrite, and replace.
- Add timeout or explicit dismiss behavior for informational messages.
- Decide whether the status row temporarily hides source row 9 or reserves a
  permanent row.

Likely direction:

Use transient bottom-row prompts. They obscure a row briefly, then restore it.

Done when:

- Every slow or risky operation tells the user what is happening.
- Prompt mode ignores unrelated keys safely.
- The source row underneath the prompt is restored cleanly.

## Phase 7: Display Performance

Goal: make the editor feel usable on slow GLCD hardware.

Work:

- Replace full GLCD flushes with dirty row or dirty byte-range flushes.
- Avoid full-screen blanking except on page load or explicit redraw.
- Optimize cursor redraw.
- Add cursor blink only after partial updates are cheap.
- Measure instruction counts for common operations.

Likely next display work:

- Dirty row flush.
- Dirty cell flush.
- Cursor-only flush.

Done when:

- Typing a character updates quickly enough to feel interactive.
- Cursor movement is visibly cheap.
- Save/load can still be slow, but editing should not be.

## Phase 8: File Picker And Editor Launch

Goal: make `edit` useful beyond the default main file.

Work:

- `edit` opens project main file.
- `edit name` opens `/src/name.asm` by convention.
- `edit /path/file.asm` opens exact path.
- Decide missing-file behavior: prompt create, create immediately, or error
  only.
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

- Implement TEC-side `ls` or enough listing for editor selection.
- Hide leading-dot files from ordinary listings.
- Make backups invisible by default.
- Add optional listing of hidden files later.

Done when:

- `.main.asm.b` does not clutter normal project views.
- Users can find and edit source files from inside TECM8.

## Phase 10: Integration With Shell

Goal: make the editor part of the Turbo Pascal-like command loop.

Work:

- Shell prompt runs commands.
- `edit` enters editor.
- `Alt-X` or quit returns to shell.
- `asm` assembles project main file.
- `run` runs derived binary.
- Preserve simple project defaults from `/tecm8.prj`.

Done when:

- User flow is: boot TECM8, `edit`, save, exit, `asm`, `run`.

## Phase 11: Source Format And Text Import/Export

Goal: ensure source files remain compatible between host tools and TECM8.

Work:

- Preserve 32-byte fixed records.
- Validate length bytes.
- Decide whether high bits in length byte must be masked or rejected.
- Confirm `export-text` handles edited files.
- Confirm hidden backups do not export by default.

Done when:

- A file edited in TECM8 exports cleanly to host `.asm`.
- A host-imported `.asm` edits cleanly in TECM8.

## Phase 12: Error Handling

Goal: stop silent failures.

Work:

- Add user-visible error states for disk open failure, read failure, write
  failure, full file/catalog/allocation, invalid source record, and unsupported
  file size.
- Add compact error strings.
- Preserve enough diagnostic info for Debug80/hardware troubleshooting.

Done when:

- The LCD/GLCD shows useful errors instead of unexplained lockups.
- Automated tests cover the major failure codes.

## Phase 13: Memory Layout

Goal: make the editor viable on a constrained TEC-1G memory map.

Work:

- Document editor RAM usage.
- Keep page buffers above MON3/GLCD volatile areas.
- Decide whether `3000h-3FFFh` becomes editor workspace.
- Prefer 2K or 4K editor windows if RAM permits; treat 1K as a fallback only.
- Avoid relying on MON3 RAM that GLCD/storage overwrites.

Done when:

- Editor memory map is explicit.
- Page buffers, cache, status state, and scratch areas have stable locations.

## Phase 14: Hardware Transition

Goal: prepare to move from Debug80 proof to real TEC-1G.

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

- Hide leading-dot files from ordinary TEC-side `ls`.
- Decide host `fs pack`/`unpack` defaults for hidden files and backups.
- Implement cleanup for hidden `.b` backups.
- Decide whether to use source-record length bits 5-7 for line metadata.
- Add a low-cost blinking cursor after the renderer can update the cursor cell
  or row without an irritating full GLCD transfer.
- Add an optional vertical insertion caret after cursor compositing is cheap and
  reliable enough not to disappear into glyph strokes.
- Revisit MON3-to-BIOS reductions once editor storage/display requirements are
  better measured.
