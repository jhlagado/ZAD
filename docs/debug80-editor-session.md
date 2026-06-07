# Debug80 Editor Session

This is the user-testable Debug80 session for the GLCD Editor V1 milestone.
It is not only an isolated proof harness: it assembles `src/main.asm`, boots it
in Debug80's TEC-1G runtime with MON3 loaded, mounts a generated FAT32 SD image,
opens `VOLUME.TM8`, reads `/tecm8.prj`, and launches the GLCD editor.

The manual entry at `4000h` opens the editor and enters a live MON3 matrix
keyboard polling loop. The automated runner enters `ScriptStart` instead: it
saves the project source file, quits, reopens it, and leaves the final editor
screen on the GLCD for verification.

Run it with:

```sh
npm run debug80:editor-session
```

For launching the `main` target from the Debug80 UI, prepare the disk image
without running the scripted edit session:

```sh
npm run debug80:editor-image
```

That command creates the SD-card image that `debug80.json` points at:

```text
demos/debug80/editor-session-fat32.img
```

If Debug80 is launched before this image exists, or with SD card emulation
disabled, MON3 storage calls can fail on the LCD with an IDE/disk timeout before
the editor has a usable project volume.

The Debug80 `main` target still boots through MON3 (`entry: 0`) and loads the
program at `4000h` (`appStart: 4000h`). For a manual UI check, let MON3 finish
initializing, then use MON3's normal `GO` flow to execute the TECM8 program at
`4000h`.

The full scripted session command generates:

```text
demos/debug80/editor-session-fat32.img
demos/debug80/editor-session-fat32.json
demos/debug80/editor-session-glcd.pgm
demos/debug80/editor-session-last-run.json
```

These files are generated local artifacts and are ignored by git.

The generated TM8 volume contains:

```text
/tecm8.prj
/src/main.asm
```

`/tecm8.prj` contains:

```text
tm8project=1
main=/src/main.asm
```

The session drives this flow:

```text
edit
insert AB at the start of the first source record
Ctrl-S save
Ctrl-Q quit
edit
Ctrl-Q quit after reopening the saved file
```

The runner verifies:

- `MainResultMarker` is `0x42`.
- `/src/main.asm` record 0 is saved as `ABR0 LINE 00`.
- `/src/.main.asm.b` record 0 preserves the previous `R0 LINE 00`.
- The final GLCD buffer is nonblank.

## Editor Input Status

The manual `4000h` entry now polls MON3 `matrixScan` through
`BiosInputPollKey`. The editor consumes the translated key in `A` and modifier
flags in `B`; raw `D/E` scan values remain available for diagnostics. Movement
is represented inside the editor as named actions:

```text
page down
page up
cursor left
cursor down
cursor up
cursor right
```

The current live path maps the TEC-1G matrix arrow codes directly onto cursor
actions:

```text
03h / ArrowUp       cursor up
04h / ArrowDown     cursor down
05h / ArrowLeft     cursor left
06h / ArrowRight    cursor right
```

The old `h`/`j`/`k`/`l` cursor aliases have been removed from the editor action
mapper now that real matrix arrow keys work. The temporary `u`/`d` page aliases
have also been removed. Printable letters should be text, not hidden movement
commands.

The intended interactive binding is:

```text
matrix ArrowLeft     cursor left
matrix ArrowDown     cursor down
matrix ArrowUp       cursor up
matrix ArrowRight    cursor right
Ctrl+ArrowDown       page down
Ctrl+ArrowUp         page up
Alt+ArrowDown        page down, after Debug80 modifier support
Alt+ArrowUp          page up, after Debug80 modifier support
other modified arrows reserved for later word/page movement
```

Debug80's visible matrix-keyboard UI now maps browser arrow keys to the TEC-1G
matrix arrow codes. The live smoke test covers `ArrowDown`, `ArrowUp`,
`ArrowRight`, `Ctrl+ArrowDown`, `Ctrl+ArrowUp`, `Alt+ArrowRight`, `CapsLock`,
`z`, `Ctrl-S`, and `Ctrl-X` so the modifier-aware path is exercised, not only
printable ASCII.
The Z80 editor accepts Alt+ArrowUp and Alt+ArrowDown for paging as well; the
automated live smoke keeps using Ctrl+Arrow until Debug80 can reliably inject
the macOS-friendly Alt/meta modifier path.
TECM8 normalizes Ctrl-letter chords after MON3 matrix translation, so Ctrl plus
`A`-`Z` or `a`-`z` produces the traditional ASCII control range `01h`-`1Ah`.

The GLCD capture is written as a portable graymap image:

```text
demos/debug80/editor-session-glcd.pgm
```

Most image viewers can open `.pgm` directly. The capture is useful for checking
that the final Debug80 session leaves a visible editor screen after the reopen.

The normal verification suite includes this session through:

```sh
npm run check
```

The live matrix-input smoke test can also be run directly:

```sh
npm run debug80:editor-live-smoke
```

It launches the manual `4000h` path under Debug80 with the MON3 `SYS_MODE`
RAM mirror initialized to match shadow-ROM-off state, injects `ArrowDown`,
`ArrowUp`, `ArrowDown`, `ArrowRight`, `Ctrl+ArrowDown`, `Ctrl+ArrowUp`,
`Alt+ArrowRight`, `CapsLock`, `ArrowDown`, `z`, `Ctrl-S`, and `Ctrl-X`, then
verifies that `Ctrl+ArrowDown` is treated as page movement rather than cursor
movement. The generated image has two source pages, so the smoke verifies that
`Ctrl+ArrowDown` changes to page 1 and `Ctrl+ArrowUp` returns to page 0 while
the cursor row stays unchanged. It also verifies that the editor cursor reaches
row 2, column 2 before save/quit. It also checks that
`Alt+ArrowRight` reports modifier bit `0x08`, raw secondary `03h`, raw primary
`06h`, translated key `06h`, that the final post-CapsLock `ArrowDown` reports
caps modifier bit `0x10`, raw primary `04h`, translated key `04h`, that `z`
marks the editor dirty, that `Ctrl-S` translates to `13h` and clears dirty, and
that `Ctrl-X` translates to `18h` and exits the live editor.

For an interactive Debug80 UI check:

1. Run `npm run debug80:editor-image` once to generate the local SD image.
2. Launch the `main` target in Debug80.
3. Leave SD enabled and high-capacity mode enabled.
4. Use MON3's normal `GO` flow to execute address `4000h`.
5. The generated image contains `VOLUME.TM8` with
   `/tecm8.prj` and `/src/main.asm`.
6. In the matrix keyboard UI, use the arrow keys for cursor movement.
   `Ctrl+ArrowDown` pages down and `Ctrl+ArrowUp` pages up. After the Debug80
   modifier update, `Alt+ArrowDown` and `Alt+ArrowUp` should do the same.
7. `Ctrl-S` saves, `Ctrl-X` quits through the same editor path as `Ctrl-Q`, and
   `Ctrl-R` asks to restore from the hidden backup file.

## Phase Milestone Manual Test

This phase is complete when the Debug80 UI can manually show the editor running
from MON3 at `4000h`, with visible cursor movement and basic typing on the
GLCD. Use this exact smoke test:

1. From the repo, run:

   ```sh
   npm run debug80:editor-image
   ```

2. In Debug80, launch the `main` target. Keep the FAT32 SD image mounted at:

   ```text
   demos/debug80/editor-session-fat32.img
   ```

3. Let MON3 initialize. Use MON3's normal `GO` flow to execute `4000h`.

4. Expected initial GLCD result:

   ```text
   R0 LINE 00
   R0 LINE 01
   ...
   ```

   This phase does not render a persistent title/header row. The visible rows
   are the source records from `/src/main.asm`.

   The cursor should be a non-blinking inverse cell, initially near the top-left
   source text area. It should not be the earlier single vertical stroke.
   The left gutter should be mostly clean: only the current source row should
   have a small marker, not the old prototype breakpoint/selection blocks.

5. Press matrix `ArrowRight` twice.

   Expected: the cursor moves two cells to the right. The whole GLCD should not
   visibly blank and repaint as a page load.

6. Press matrix `ArrowDown`, then `ArrowUp`.

   Expected: the cursor moves down one source row and back up one source row.
   The current-row gutter marker should follow it. This should not blank and
   repaint the whole GLCD as a page load.
7. Type `Z`.

   Expected: because the cursor is two cells to the right, the first line
   changes from `R0 LINE 00` to `R0Z LINE 00`, and the cursor advances one
   cell. This should redraw the affected row rather than doing the older
   obvious full-screen clear/repaint path.

8. Press `Ctrl+ArrowDown`, then `Ctrl+ArrowUp`. After the Debug80 modifier
   update, also test `Alt+ArrowDown`, then `Alt+ArrowUp`.

   Expected: because the page is now dirty, paging is ignored and the display
   stays on the `R0 LINE ...` page. This prevents accidental loss of unsaved
   page-buffer edits.

9. Press `Ctrl-S`.

   Expected: the status row shows `Saving...`, then the file is saved. There
   may be a visible pause because storage is still MON3/FAT32-backed and slow.
   When the save returns, the source row hidden by the transient status message
   is restored.

10. Press `Ctrl+ArrowDown`. After the Debug80 modifier update, also test
    `Alt+ArrowDown`.

   Expected: after saving, the generated two-page fixture moves to the second
   source page and the visible rows begin with `R1 LINE 00`, `R1 LINE 01`, and
   later `R1 LINE ...` records. Page movement is tested against this prepared
   fixture; V1 does not grow the document across source sectors when Enter is
   pressed at the end of a page.

11. Press `Ctrl+ArrowUp`. After the Debug80 modifier update, also test
    `Alt+ArrowUp`.

   Expected: the editor returns to the first page and shows `R0 LINE ...`
   records again.

12. Press `Ctrl-X`.

   Expected: if the page is clean after save, the editor exits without a dirty
   discard prompt. If it is dirty, the status row asks a yes/no question.

   `Ctrl-Q` remains available as plain quit, but `Ctrl-X` is the preferred
   Debug80 exit path because host tools commonly reserve `Ctrl-Q`.

The current phase does not require fast GLCD hardware flushing. Cursor movement
and simple printable edits avoid full viewport render, but cursor overlay and
row edits still flush through the current full GLCD transfer routine. Replacing
that with tile/dirty-region GLCD transfer is the next display-performance phase.

Ordinary cursor movement and simple in-line printable edits now use dirty
rendering: horizontal cursor keys redraw the cursor overlay, vertical cursor
keys redraw the old/new source rows so the gutter marker follows the cursor,
and printable insert/delete redraws the affected source row. Page loads,
split/join operations, explicit redraws, and mode changes may still repaint the
full viewport.

The cursor is constrained to the visible 20-column GLCD editor viewport in this
phase. The 32-byte source-record format still stores up to 31 text bytes, but
horizontal scrolling is not implemented yet.

The cursor is currently a non-blinking inverse 6x6 cell. It should remain
visible over glyphs with vertical strokes such as `E`, `L`, and `N`, unlike the
earlier single vertical bar cursor.
