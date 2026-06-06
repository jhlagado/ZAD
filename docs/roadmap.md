# TECM8 Roadmap

This is the live roadmap for TECM8. It records the current milestone, completed
foundation, near-term goal order, stop condition, and deferred work. Update this
file after meaningful phase changes so the roadmap does not live only in
conversation history.

## Current Milestone: TECM8 Tiled GLCD Renderer V1

The previous Debug80-testable editor milestone proved the storage-backed edit,
save, quit, reopen, and backup path. Real manual testing showed that the current
MON3-backed display path is not usable enough for continued editor work: every
text mutation can clear and repaint the full GLCD, producing visible multi-second
blanking. The next milestone therefore focuses on the display system before
assembler integration or broader shell work.

The current milestone is complete when a user can run the Debug80 editor session,
type into the editor, move the cursor, and see ordinary cursor movement and
single-line text edits update without a full-screen blank/repaint cycle.

The target display model is a TECM8-owned tiled GLCD layer:

```text
128x64 bitmap hardware
6x6 text cells for the current GLCD font rhythm
4-pixel gutter plus 20 visible text cells
10 physical text rows, normally all source text in the 6x6 profile
row 9 can temporarily become a prompt/status overlay
tile writes replace both black and white pixels for the full cell footprint
```

The renderer may initially continue to flush through MON3's low-level GLCD
hardware routines, but editor text drawing, clearing, cursor overlays, and dirty
update policy should move out of the MON3 terminal library and into TECM8-owned
code.

This milestone does not require a complete replacement of the MON3 GLCD library.
It requires enough replacement to make the editor responsive and to establish the
direction for a future TECM8 GLCD BIOS/display library.

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
- The editor tracks whether the loaded page has unsaved edits, marks dirty
  after in-page mutation, accepts a Ctrl-S save key, and clears dirty after a
  successful save.
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
- Sector-edge editing policy is conservative for V1: split on the final row
  and join before the first row are no-ops rather than cross-sector shifts.
- Design policies exist for reserved source-record length bits, hidden dotfiles,
  one-level editor backups, and status-line confirmation prompts.
- `src/main.asm` is now a Debug80-runnable TECM8 editor session entry rather
  than the old seven-segment/LCD starter.
- `npm run debug80:editor-session` generates a prepared FAT32/TM8 image and
  proves the user-facing edit/save/quit/reopen workflow against Debug80.
- `BiosInputPollKey` exposes translated key codes, modifier flags, and raw
  matrix scan diagnostics so the Debug80 editor can be driven from real matrix
  arrow keys and modifier chords.
- A TECM8-owned GLCD tile-cell layer exists for 6x6 text cells. Structured
  screen text rendering now writes through tile primitives rather than MON3's
  terminal character drawing routine.

## Near-Term Goal Order

1. **Measure and document the current display bottleneck.**
   Confirm the exact full-screen clear/redraw path, separate Debug80 canvas
   scaling artifacts from GLCD buffer contents, and record the target replacement
   architecture in the design docs.

2. **Introduce a TECM8 GLCD tile-buffer layer.**
   Add Z80 routines that compute cell addresses in the GLCD backing buffer and
   write a complete 6x6 cell, including blank pixels. Keep the first scope narrow:
   `GlcdTileClearCell`, `GlcdTileDrawCell`, and `GlcdTileDrawTextRun` or
   equivalent names.

3. **Move structured screen rendering onto tile primitives.**
   Replace per-character MON3 terminal drawing in the structured display model
   with TECM8 tile writes. Full-page rendering may still clear and repaint, but
   it should no longer depend on MON3 terminal text policy. Status: implemented
   for text rows via `GlcdTileClearTextRow` and `GlcdTileDrawTextRun`; gutter
   and cursor paths still use direct `TGBUF` writes pending later cursor/dirty
   rendering work.

4. **Add dirty line/cell rendering for editor mutations.**
   Change printable insert/delete paths so they redraw the affected line or cell
   range instead of calling `DisplayRenderScreen`. Cursor-only movement should
   erase the old cursor overlay, draw the new overlay, and avoid page redraw.

5. **Improve cursor visibility.**
   Replace the fragile single vertical stroke with a cell-level cursor treatment,
   likely inverse/XOR or another full-cell overlay. Blinking can follow once the
   nonblank overlay is reliable.

6. **Add Debug80 performance smoke coverage.**
   Extend the live editor smoke so it proves that a key insertion no longer calls
   the full-screen render path. Prefer observable state or counters over timing,
   because emulator speed and host canvas scaling vary.

7. **Define the MON3 GLCD deprecation boundary.**
   Decide which MON3 GLCD routines remain temporary low-level hardware services
   and which terminal/rendering services are no longer allowed in editor drawing.

## Debug80-Testable GLCD Editor V1 Done Criteria

Status: reached by `npm run debug80:editor-session`. The command assembles
`src/main.asm`, generates a FAT32/TM8 project image, launches the storage-backed
editor path in Debug80's TEC-1G runtime, saves and reopens `/src/main.asm`, and
verifies the saved source and hidden backup. See
`docs/debug80-editor-session.md`.

- `edit` opens the project main file by default.
- `edit name` can open a named source file with `.asm` defaulting where
  appropriate.
- A loaded source page can be rendered, edited, saved, quit, and reopened.
- Dirty state is visible and prevents silent loss.
- Save creates a hidden one-level backup before replacement.
- Restore from backup works from inside the editor.
- Status-line prompt mode handles confirmation questions.
- Fixed-record source files remain valid for `fs export-text`.
- Local verification includes focused AZM/Debug80 proofs and `npm run check`.
- There is a documented Debug80 command/session that launches TECM8 into the
  editor workflow against a prepared project volume.
- The emulator demonstration proves the user-facing phase result, not just
  isolated subroutine behavior.

## TECM8 Tiled GLCD Renderer V1 Done Criteria

- The editor has a TECM8-owned GLCD tile writer for 6x6 cells.
- Tile writes replace both set and clear pixels for the affected cell.
- Structured display rendering uses TECM8 tile primitives rather than MON3
  terminal character output.
- Cursor-only movement avoids full-screen clear/repaint.
- Printable character insertion avoids full-screen clear/repaint for ordinary
  in-line edits.
- Full-screen repaint remains available for page load, mode switch, and explicit
  redraw.
- The cursor is visibly distinct on glyphs with vertical strokes such as `E`,
  `L`, and `N`.
- Local verification includes focused display proofs, the Debug80 live editor
  smoke, and `npm run check`.
- Manual Debug80 testing shows no obvious blanking on ordinary cursor movement or
  single-line character insertion.

After these criteria are satisfied, stop and reassess whether the next milestone
should continue display work, return to shell ergonomics, or begin assembler
integration.

## Later Milestones

### Real Shell Workspace

- Replace proof-seeded keyboard streams with real matrix keyboard input.
- Add or complete the top-level TECM8 command loop.
- Support `cd`, `pwd`, `ls`, `edit`, `asm`, and `run` as shell commands.
- Keep project defaults short: `edit`, `asm`, `run`.

### Build Tools

- Integrate a Z80 assembler path after the editor is useful.
- Treat `.asm` as the preferred source extension; keep `.z80` as compatibility.
- Emit derived outputs such as `/build/main.bin` and `/build/main.map`.
- Report assembler errors in a way the editor can use later.

### Run Loop

- Load the derived binary output.
- Run it from TECM8.
- Return to the shell where practical.

### Source-Aware Debugger

- Load compact map data.
- Display source context by source sector/line.
- Support break, run, step, register display, and eventually source-level
  navigation.

## Deferred Design Work

- Hide leading-dot files from ordinary TEC-side `ls`.
- Decide host `fs pack`/`unpack` defaults for hidden files and backups.
- Implement cleanup for hidden `.b` backups.
- Decide whether to use source-record length bits 5-7 for line metadata.
- Add multi-sector line insertion/deletion after in-page behavior is stable.
- Consider a tiny one-level undo or page snapshot only after save/backup is
  working.
- Revisit MON3-to-BIOS reductions once editor storage/display requirements are
  better measured.
