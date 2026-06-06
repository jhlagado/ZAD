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

1. **Dirty editor rendering.**
   Change ordinary cursor movement and simple in-line printable edits so they do
   not call the full-screen `DisplayRenderScreen` path. Cursor movement should
   erase and redraw only the cursor overlay. Printable edits should redraw the
   affected source row from the loaded 512-byte page buffer.

   Status: implemented for cursor movement, printable insertion, delete, and
   backspace within a line. Split/join and page movement still use full viewport
   render because they can legitimately shift many source rows.

2. **Visible cell-level cursor.**
   Replace the fragile single vertical stroke with a cursor treatment that stays
   visible over glyphs such as `E`, `L`, and `N`. It may remain a non-blinking
   cursor for this phase; blink timing can be a later milestone.

3. **No-full-repaint Debug80 smoke coverage.**
   Add observable proof/smoke coverage that ordinary cursor movement and a
   simple printable insertion avoid the full-screen render path. Prefer counters
   or explicit render-path markers over wall-clock timing.

4. **Manual Debug80 test package.**
   Ensure `npm run debug80:editor-image` produces the manual image, document the
   exact MON3 launch path, and list specific matrix-keyboard checks for cursor
   movement, typing, saving, quitting, and restore prompts.

5. **Phase completion review.**
   Run local verification including `npm run check`, get a high-effort local
   subagent review for the code changes, address findings, close subagents,
   commit, push, monitor any remote CI runs, and then stop.

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

## Manual Milestone Test

The phase is complete only when a user can manually inspect the editor in
Debug80:

1. Run `npm run debug80:editor-image`.
2. Launch Debug80's `main` target with SD enabled.
3. Let MON3 initialize, then use MON3 `GO` at `4000h`.
4. Confirm the GLCD shows the TECM8 editor with `/src/main.asm`.
5. Press matrix arrow keys and confirm the cursor moves without a visible
   full-screen blank/repaint.
6. Type a few printable letters on one source line and confirm only that line
   visibly changes, without a full-screen blank/repaint.
7. Press `Ctrl-S` to save.
8. Press `Ctrl-Q` to quit; if dirty, answer the status prompt.
9. Restart the editor and confirm the saved text is still present.

The manual test script should be updated with exact expected screen changes
before this phase is marked complete.

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
