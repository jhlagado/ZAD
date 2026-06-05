# TECM8 Roadmap

This is the live roadmap for TECM8. It records the current milestone, completed
foundation, near-term goal order, stop condition, and deferred work. Update this
file after meaningful phase changes so the roadmap does not live only in
conversation history.

## Current Milestone: Debug80-Testable GLCD Editor V1

The current milestone is a usable storage-backed GLCD editor for fixed-record
text files that can be launched and exercised in the Debug80 emulator. Proof
programs remain essential, but they are not the phase endpoint by themselves.

The milestone is complete when a user can:

```text
edit
modify source records
save explicitly
quit back to the shell
reopen the file and see saved changes
restore from the one-level hidden backup if needed
```

The milestone also requires proof coverage that edited records are written back
to the TM8 volume without corrupting the fixed 32-byte source-record format.

The final deliverable for this phase is a Debug80-runnable TECM8 image/session
that demonstrates the editor path: open a project/source file, edit it, save,
quit, reopen, and verify the saved content. When this milestone is reached, stop
and wait for further instructions before starting assembler integration.

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
  yes/no answers complete the prompt, and the bottom chrome switches back after
  completion.
- The editor derives the hidden backup path, creates it when missing, and saves
  the previous on-disk page there before writing the edited page to the source
  file.
- Source-record padding is kept clean after in-page mutations so host export
  validation remains meaningful.
- Design policies exist for reserved source-record length bits, hidden dotfiles,
  one-level editor backups, and status-line confirmation prompts.

## Near-Term Goal Order

1. **Restore from backup**
   - Add an editor command to load the hidden backup into the current buffer.
   - Confirm through status-line prompt mode.
   - Mark the restored buffer dirty so the user can inspect before saving.

2. **Quit behavior**
   - Add a real quit command from editor back to shell.
   - If dirty, prompt before discarding unsaved changes.
   - Preserve proof-key streams while moving toward real keyboard input.

3. **Sector-edge policy**
   - Keep current in-page split/join behavior.
   - Define and prove conservative behavior at page boundaries.
   - A first version may refuse sector-crossing line insert/delete rather than
     shifting data across multiple sectors.

4. **Debug80-runnable editor session**
   - Build a TECM8 entry path that can be launched in Debug80, not only proof
     harnesses.
   - Provide a prepared FAT32/TM8 image containing `/tecm8.prj` and source text.
   - Document the exact Debug80 run steps.
   - Demonstrate `edit`, mutation, save, quit, reopen, and saved-content
     verification inside the emulator workflow.

## Debug80-Testable GLCD Editor V1 Done Criteria

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

After these criteria are satisfied, stop. The next milestone should be chosen
deliberately rather than started automatically.

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
