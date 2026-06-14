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

## [0.1.3] - 2026-06-15

Code Quality Phase A2: shared source-record row-shift helpers.

### Engineering Notes

- Confirmed `Tecm8RecordShiftRecordsDown` and `Tecm8RecordShiftRecordsUp` as
  the shared 32-byte row-shift helpers used by split, join, block paste, block
  copy, and block delete paths.
- Removed stale quality-plan wording that still described the former duplicate
  `LDIR` row-shift loops as open work.
- Updated the roadmap to mark Phase A2 complete and point the next
  agent-owned compactness work at TM8 byte/path helper extraction.

### Verification

- Covered by the existing structural interaction tests, line-editing proof,
  mutation-boundary proof, block-selection proof, block-delete proof, Block
  Editing V1 acceptance, and full `npm run check` gate.

## [0.1.2] - 2026-06-15

Block Editing V1 validation milestone.

### User-Facing Editor Behavior

- The Debug80 matrix-key smoke now proves block selection, copy, move/cut,
  paste, save, and reset/reopen persistence through the live editor path.
- Block Editing V1 manual notes now distinguish live matrix-key coverage from
  selected-block `Delete`, which remains Z80-proof-covered until Debug80
  exposes a live `Delete` key path.

### Engineering Notes

- Expanded `debug80:editor-block-smoke` to inspect saved source records and
  reopen the saved Debug80 image in a fresh runtime.
- `acceptance:block-editing-v1` remains the focused automated gate for the
  block editing milestone.

## [0.1.1] - 2026-06-15

Phase 3A milestone: Rolling Source Window V1 manual validation.

### User-Facing Editor Behavior

- The Debug80 manual editor script now covers the multi-page source editing
  milestone: continuous `R0`/`R1` navigation, edits in more than one sector,
  save, reset, reopen, and persistence verification.
- Plain `Up`/`Down` treats resident adjacent source pages as one continuous
  document instead of making page movement feel like switching files.
- `Ctrl-S` preserves pre-session hidden backup sectors while saving later edits
  to resident source sectors.
- `Ctrl-Z` restore is limited to resident sectors that were actually backed up
  during the session.

### Engineering Notes

- Added the rolling-window slice sequence and completed the five Phase 3A slice
  commits through local verification and high-effort review for code changes.
- Added session backed-page tracking so repeated saves do not overwrite the
  original backup sector with the first edited save.
- Updated the Debug80 session runner fixture construction and diagnostics used
  by the live smoke path.
- Added a low-priority roadmap item for Z80 label-length hygiene so PascalCase
  labels do not grow into sentence-length names.

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
