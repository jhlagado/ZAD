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

The manual `4000h` entry now polls MON3 `matrixScan` and `parseMatrixScan`
through `BiosInputPollAscii`. Movement is represented inside the editor as
named actions:

```text
page down
page up
cursor left
cursor down
cursor up
cursor right
```

The current live path and the proof stream both map temporary host-friendly
ASCII bytes onto those actions:

```text
d / D    page down
u / U    page up
h / H    cursor left
j / J    cursor down
k / K    cursor up
l / L    cursor right
```

These are not intended to be the final TEC-1G user-facing bindings. They are
aliases for automated proofs, Debug80 script runs, and current manual testing
while the physical matrix arrow-key path is being settled.

The intended interactive binding is:

```text
matrix ArrowLeft     cursor left
matrix ArrowDown     cursor down
matrix ArrowUp       cursor up
matrix ArrowRight    cursor right
modified arrows      page or word movement, exact modifiers to be finalized
```

As of this TECM8 milestone, Debug80's visible matrix-keyboard UI has arrow keys,
but the observed Debug80 request path only special-cases `CapsLock`. Printable
keys are resolved through ASCII and reverse-mapped to matrix row/column states,
which is why `h`, `j`, `k`, `l`, `d`, and `u` work. Browser keys named
`ArrowLeft`, `ArrowDown`, `ArrowUp`, and `ArrowRight` are not printable ASCII,
so they appear not to reach the emulated matrix state yet.

If this blocks interactive testing, hand this minimal repro to the Debug80 team:

1. Launch the TEC-1G target with matrix keyboard capture enabled.
2. Press or click the visible matrix keyboard arrow keys.
3. Observe whether `ArrowLeft`, `ArrowDown`, `ArrowUp`, and `ArrowRight` apply
   any matrix row/column state.
4. Expected result: each visible arrow key should generate the TEC-1G matrix
   row/column event or documented MON3 matrix/ASCII code for that key.

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

It launches the manual `4000h` path under Debug80, injects matrix `j` then `l`,
and verifies that the editor cursor reaches row 1, column 1.

For an interactive Debug80 UI check:

1. Run `npm run debug80:editor-image` once to generate the local SD image.
2. Launch the `main` target in Debug80.
3. Leave SD enabled and high-capacity mode enabled.
4. Use MON3's normal `GO` flow to execute address `4000h`.
5. The generated image contains `VOLUME.TM8` with
   `/tecm8.prj` and `/src/main.asm`.
6. In the matrix keyboard UI, use the letter keys for current movement testing:
   `h` left, `j` down, `k` up, `l` right, `d` page down, and `u` page up.
7. `Ctrl-S` saves, `Ctrl-Q` quits, and `Ctrl-R` asks to restore from the
   hidden backup file.

After each key press the current implementation may repaint the whole GLCD
viewport, so movement is expected to feel slow. That is a known renderer
performance limitation, not an input failure.
