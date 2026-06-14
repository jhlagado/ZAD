# TECM8 Changelog

This file records completed TECM8 milestones. The project is not currently
released as an npm package; version tags are used to mark testable Z80/editor
progression and to make the project history easier to navigate.

## Versioning Policy

- Patch versions mark completed internal milestones or coherent editor/tooling
  increments: `v0.1.1`, `v0.1.2`, and so on.
- Minor versions mark larger user-visible steps, such as a substantially more
  capable editor, shell, assembler, or Debug80-testable workflow: `v0.2.0`,
  `v0.3.0`, and so on.
- Release notes should lead with user-testable TECM8 behavior and mention
  supporting proof/tooling changes only where they explain the milestone.
- Each milestone tag should point at a committed, pushed, reviewed, and locally
  verified state.

## [0.1.0] - 2026-06-14

Initial milestone tag for the Debug80-testable TECM8 editor line.

### User-Facing Editor Behavior

- Provides a TEC-1G Debug80 editor image that can be launched at `4000h` after
  MON3 initialization.
- Loads `/src/main.asm` from the FAT32-backed TM8 volume and renders it on the
  128x64 GLCD.
- Supports cursor movement, character insertion/deletion, newline split, line
  join by backspace at column zero, save, restore-from-backup prompt, and quit
  prompt.
- Supports whole-line block selection, copy, move, paste, and selected-line
  deletion with gutter markers.
- Uses a tile-oriented GLCD update path with dirty-cell updates, cursor blink,
  and a vertical insertion-bar cursor.
- Supports explicit page movement with `Ctrl+Up` and `Ctrl+Down`.
- Supports plain `Up`/`Down` crossing between already resident adjacent source
  pages, so moving from `R0 LINE 15` to `R1 LINE 00` no longer requires the user
  to use explicit page commands.

### Storage And Proof Milestones

- TM8 volume tooling supports formatting, import/export, pack/unpack, source
  text conversion, project metadata, and hidden backup handling.
- The TEC-side editor writes dirty source pages back through MON3-backed
  storage wrappers and preserves backup state.
- The proof harness covers editor loading, rendering, navigation, line editing,
  page writing, block operations, keyboard diagnostics, shell command
  resolution, and storage write evidence.
- `npm run check` passed at the tagged commit before release tagging.

### Architecture Notes

- TECM8 is being shaped as a ROM-oriented development environment with a
  resident shell launching banked tools such as the editor, assembler, runner,
  and later debugger.
- MON3 remains the current BIOS/service layer. TECM8 will continue to preserve
  useful MON3 service compatibility while gradually replacing optional monitor
  UI and display/storage assumptions where the development system needs a more
  suitable interface.
