# TECM8 Code Quality Execution Plan

This document is the response plan for the external code-quality assessments in
`docs/code-quality-report.md` and the earlier remediation draft. It turns those
audits into an execution sequence for TECM8, adjusted for the current roadmap:
the editor is usable in Debug80 and Block Editing V1 is automation-complete, but
manual validation and later editor features are still ahead. The code should be
improved without destabilizing that progress.

## Current Baseline

- Z80 source size: 24 `.asm` modules, 11,367 lines.
- Largest files:
  - `src/editor-interaction.asm`: 1,506 lines.
  - `src/editor-storage-loader.asm`: 1,463 lines.
  - `src/shell-commands.asm`: 1,325 lines.
  - `src/editor-navigation.asm`: 1,164 lines.
  - `src/glcd-tile.asm`: 1,008 lines.
  - `src/editor-line-edit.asm`: 595 lines.
- Current fresh source build: `npm run z80:size` reports 14,969 bytes emitted
  at `4000h..7A79h`, leaving 1,415 bytes before the `8000h` bank boundary. The
  checked-in `build/main.bin` artifact may be stale; use the size command for
  baselines.
- Current product shape: Debug80-runnable editor at `0x4000`, launched under
  MON3, with storage-backed load/save, multi-page editing, display scheduling,
  and Block Editing V1 automation.
- Current roadmap position: Block Editing V1 needs manual Debug80 validation
  before named block read/write, character selections, or larger feature work.
- System context: TECM8 is becoming a small ROM-based operating system. The
  shell is the resident personality that owns project context and launches
  tools; the editor, assembler, runner, and debugger are separate banked tool
  projects.

The audits are useful, but their line numbers and byte counts are snapshots.
Every implementation phase below starts by re-grepping symbols and measuring the
current binary rather than trusting stale offsets.

## Quality Principles

1. Keep the editor runnable after every increment. `npm run check` is the main
   gate, and manual Debug80 behavior must not regress.
2. Preserve the AZM discipline. New public routines need `;!` contracts, and
   refactors must keep register boundaries clear rather than hiding clobbers.
3. Prefer native AZM structure where it improves boundaries, layout safety, or
   readability: `.import` for routine modules, layout types for records, enums
   for closed state families, and string directives for explicit storage.
4. Prefer compact shared routines when they reduce both bytes and bugs. Do not
   chase clever opcode-level savings before the module boundaries are clean.
5. Do not reintroduce old keyboard conventions. Alphabetic keys are commands or
   text; navigation is by matrix arrow keys and modifiers only.
6. Preserve the source-record contract. Each line is a 32-byte record; the
   length byte uses only bits 0-4 for length, so reads must mask with `0x1F`
   and writes must preserve bits 5-7 unless deliberately changing metadata.
7. Keep resident code honest. Proof-only scaffolding and shell features not used
   by the live editor should not be accidentally treated as required resident
   product code.
8. Use TypeScript for host tooling in this repo. Do not introduce Python helper
   scripts for code-quality or size measurement.

## Audit Findings Triage

The audit agents did not have the full TECM8 system context. In particular, the
shell is not accidental baggage. It is the intended replacement for the classic
monitor UI as the normal front door of the machine. Quality work should separate
resident shell/kernel code from editor-bank code, not remove or minimize the
shell as if it were merely a proof harness.

Accepted findings:

- `editor-interaction.asm` is too large and mixes key dispatch, cursor state,
  block editing, prompt handling, record mutation, and render scheduling.
- TM8 path/catalog/superblock logic is duplicated across loaders and should
  become a narrow shared reader/writer layer.
- Display, editor, TM8, and keyboard constants are spread across modules under
  parallel names. Canonical equates are needed.
- Native AZM module and layout features are underused. See
  `docs/azm-adoption-opportunities.md` for the adoption sequence.
- Space-saving opportunities exist in table-shaped error lookup, validation
  logic, and common render/error tails. See
  `docs/z80-space-saving-opportunities.md` for recommended pilots.
- Record shifts, buffer clears, match-byte loops, and GLCD dirty-row masking are
  good candidates for shared routines.
- `main.asm` currently links more shell machinery into the live editor image
  than that editor bank should need.
- Some docs and comments still describe earlier roadmap states.

Findings to adjust before execution:

- Do not make an arbitrary line limit a hard quality gate. File size is a
  warning sign, not proof of bad design. The target is clearer ownership and
  smaller reviewable modules.
- Do not create a broad general-purpose filesystem layer yet. Extract a narrow
  TM8 layer that serves current project config, file listing, editor loading,
  editor saving, backup creation, and growth.
- Do not table-drive every dispatch path before the keymap has a stable module
  boundary. Keymap extraction should happen first; table dispatch can follow
  where it measurably reduces code and complexity.
- Do not delete BIOS wrappers purely because they have no current product
  callers. First classify them as current product, near-future diagnostic/API,
  or obsolete MON3-terminal compatibility.

Deferred findings:

- Banked overlays and MON3 BIOS replacement remain future architecture work.
  This quality plan can prepare module boundaries for overlays, but should not
  start bank switching.
- TypeScript proof-runner deduplication is tracked separately in
  `docs/typescript-code-quality.md`. It is worthwhile, but Z80 organization is
  the priority for this pass unless TS duplication blocks a Z80 refactor.
- Named block read/write and anonymous clipboard-file behavior belong after
  Block Editing V1 manual validation.

## Execution Roadmap

### Q0: Baseline And Guardrails

Goal: establish the measured state before structural work.

Actions:

- Run `npm run check` on the current tree.
- Run `npm run z80:size` and record the fresh assembled binary size and emitted
  address span. The command also reports non-exclusive D8 source-map coverage
  ranges where available.
- Review `docs/roadmap.md`, `docs/codebase.md`, and
  `docs/memory-and-code-quality.md` for obvious contradictions with the current
  code.
- Keep `debug80.json` and other local emulator configuration changes out of
  quality commits unless explicitly requested.

Done when:

- The baseline command output and binary size are recorded.
- `npm run z80:size` is the canonical measurement surface.
- The next refactor has a known verification command set.
- No behavior has changed.

### Q1: Low-Risk Hygiene Before Refactoring

Goal: remove stale policy and proof friction that would mislead later work.

Actions:

- Update stale comments and docs that still describe superseded editor behavior:
  sector-edge editing, display-model being proof-only, old block overlap notes,
  and any lingering alphabet-navigation language.
- Classify apparently unused BIOS and editor routines into keep, deprecate, or
  delete candidates. Do not delete until proof and product caller checks agree.
- Identify test assertions that pin dead labels rather than behavior. Convert
  them to behavior or contract checks before removing the labels.
- Ensure the codebase tour describes `@` routine entries, current Control-key
  command policy, and the no-letter-navigation rule.

Done when:

- Docs no longer encourage outdated implementation decisions.
- Dead-code candidates are listed with caller evidence.
- No code behavior changes except removal of proven-unused code.

### Q2: Canonical Equates And Memory Names

Goal: stop constants from drifting across modules.

Actions:

- Done: introduce `src/tecm8-equates.asm` for shared constants that cost no
  resident bytes: source-record sizes, source length masks, sector size,
  keyboard modifier bits, display geometry, and GLCD buffer addresses.
- Keep domain aliases only when they add meaning. For example, a record size of
  32 and printable ASCII space both have value 32 but should not collapse into
  one ambiguous name.
- Done: keep domain aliases in modules such as `TECM8_EDITOR_RECORD_BYTES`,
  `TECM8_GLCD_TILE_ROWS`, and `TECM8_BIOS_KEY_MOD_CTRL`, but derive those
  aliases from the canonical names.
- Done: audit bare `0x1F` uses. The remaining bare uses are not source-record
  length masks: storage uses one for page-to-block steps, and BIOS uses one for
  Ctrl-letter normalization.
- Add or update tests/proofs that confirm length metadata bits survive
  render/edit/save paths.
- Done: update structural tests so literal shared values are pinned in
  `src/tecm8-equates.asm` and modules are checked as aliases.

Done when:

- Constants are owned in one place, or aliases clearly derive from one place.
- `npm run check` passes.
- The binary size is measured before and after; a size drop is welcome but not
  required for this phase.

### Q2A: Native AZM Adoption Pilots

Goal: prove native AZM features in small slices before broad source churn.

Actions:

- Follow the adoption sequence in `docs/azm-adoption-opportunities.md`.
- Adopt only one new AZM feature per increment. Keep `.import`, layout types,
  enums, string directives, and ops in separate changes so each feature's value
  and cost can be measured independently.
- Pilot `.import` on one low-risk module or proof path. Keep `.include` for
  equates, layouts, ops, and deliberately textual proof fixtures.
- Introduce one layout declaration for a real memory record, such as the
  display row descriptor or source-record shape, then derive size and offset
  constants from it.
- Convert one closed constant family to `.enum`, preferably a status/action
  group whose call sites already treat the values as a set.
- Convert obvious NUL-terminated strings in one module from `.db "text",0` to
  `.cstr "text"` where the storage contract is actually a C string.
- Identify at most a few tiny `op` candidates. Measure the binary before and
  after each one, and reject any op that increases size without a readability
  win.
- Keep ASM80-lowered `.z80` compatibility in mind: `.import` is not suitable
  for workflows that need that output path until AZM supports it.

Done when:

- The increment contains only one new AZM feature category, unless the exception
  is explicitly documented.
- Each pilot has a targeted proof or build command.
- `npm run z80:size` records the before/after size.
- Strict register contracts still pass for affected proof/build paths.
- The successful patterns are folded into the style guide or module templates.

### Q2B: Z80 Space-Saving Pilots

Goal: test compactness techniques in small, measurable increments before making
them part of the house style.

Actions:

- Follow the ranked recommendations in
  `docs/z80-space-saving-opportunities.md`.
- Try only one compactness technique per increment. Keep table-driven lookup,
  common-tail sharing, table-driven validation, and command normalization in
  separate changes so each one can be judged and reverted independently.
- Start with low-risk data-shaped logic, especially editor load error text
  lookup or exact repeated editor render tails.
- Use classic jump tables only where the dispatch family is dense, stable, and
  large enough that the indirect-dispatch scaffold is smaller than the compare
  chain.
- Do not share tiny tails such as `XOR A` / `RET` merely for style.
- Record the binary size before and after every pilot with `npm run z80:size`.

Done when:

- Each pilot has a before/after byte count and targeted proof command.
- The change improves or preserves readability at the affected label.
- Any new shared tail or helper has a clear contract when public.
- Patterns that do not pay for themselves are rejected and documented rather
  than spread through the codebase.

### Q3: Shared Record, String, And Path Helpers

Goal: remove duplicated small algorithms before splitting large modules.

Actions:

- Done: create `src/tecm8-record.asm` for the first shared source-record
  operations:
  - reading a masked record length,
  - writing a length while preserving bits 5-7,
  - zeroing padding bytes after the effective length,
  - clearing a 32-byte record,
  - shifting text bytes left or right inside one record,
  - shifting records up/down inside a page or resident window.
- Done: route the remaining resident-page block copy, paste, insert-space, and
  delete-source row-copy loops through those shared record-window helpers.
- The existing `EditorKey*Record*` labels remain as compatibility wrappers and
  now delegate to the shared helpers. Replace duplicate split/join/paste/delete
  shift loops in `src/editor-interaction.asm` only after the small record-helper
  boundary is proof-green.
- Done: create `src/tecm8-string.asm` for the first shared byte/string/path
  helpers:
  - bounded byte matching with carry clear on match and carry set on mismatch,
  - bounded NUL-terminated string copy used behind shell and editor-navigation
    wrappers,
  - ASCII-space skipping used by shell command parsing,
  - local filename lookup by returning the byte after the final slash in a
    NUL-terminated path.
- Done: add `proofs/shared/tecm8-string-proof.asm` and
  `npm run proof:tecm8-string` so the shared bounded-copy helper has direct
  boundary coverage for zero capacity, exact fit, and overflow.
- Leave the shell-local append helper local for now. A trial extraction into
  `src/tecm8-string.asm` increased the live image by 8 bytes because the helper
  has only shell-local callers and still needs shell-specific error mapping.
- Defer prefix/name split and sibling backup path derivation until the narrow
  TM8 layer exists. The current backup path builder has editor-specific error
  codes and saved-pointer state, so extracting it prematurely would add API
  surface without reducing real duplication.
- Continue replacing duplicated path walks in shell, navigation, and storage
  code only where the helper is shared across modules or measurably reduces
  resident bytes.
- Keep helper interfaces pointer-based (`HL`, `DE`, `BC`) where practical so
  future overlay/banking work is not tied to hidden globals.

Done when:

- Record and path behavior is unchanged under the existing proofs.
- The byte delta is recorded.
- Register contracts are present on each public helper.

### Q4: Narrow TM8 Storage Layer

Goal: keep storage behavior identical while removing repeated TM8 walks.

Actions:

- Done: create `src/tecm8-storage.asm` for the first shared TM8 format helper,
  `Tecm8StorageBlockToOffset`. `project-config-loader` and
  `editor-storage-loader` now use it instead of carrying duplicate block-offset
  conversion routines. The helper stays deliberately narrow: callers still map
  errors and add sector-in-block offsets locally. This reduced the live
  Debug80 image from 15,090 bytes to 15,060 bytes, leaving 1,324 bytes in the
  current 16K bank.
- Done: move canonical TM8 v1 layout constants and the `TECM8VOL` magic bytes
  into `src/tecm8-storage.asm`. The loaders now share those definitions while
  keeping policy constants such as `TM8_SOURCE_MIN_BYTES` local. Sharing the
  magic bytes reduced the live Debug80 image to 15,052 bytes, leaving 1,332
  bytes in the current 16K bank.
- Done: add `Tecm8StorageValidateCoreSuperblock` for the TM8 v1 checks shared
  by all current readers: magic, version, sector size, catalog start, and
  catalog-entry size. Project config delegates all of its superblock validation
  to this helper; editor storage calls it first and then performs the extra
  writer/allocation/prefix/data-block checks it needs. This reduced the live
  Debug80 image to 15,001 bytes, leaving 1,383 bytes in the current 16K bank.
- Done: add `Tecm8StorageAdvanceSectorOffset`, a shared MON3 `DE` byte-offset
  step for scanning TM8 sector tables. Project config, editor source lookup,
  editor file listing, catalog-slot search, and catalog writing now use it.
  Other `TM8_SECTOR_BYTES` uses remain local because they are buffer copies or
  allocation math, not the same offset-advance pattern. This reduced the live
  Debug80 image to 14,990 bytes, leaving 1,394 bytes in the current 16K bank.
- Done: add `Tecm8StorageReadSectorPreserveOffset`, a shared MON3 sector read
  wrapper for scan loops that need the current `DE` byte offset after
  `BiosFileReadSector`. Project config, editor prefix/catalog scans, allocation
  scans, catalog-slot scans, and file listing now use it. Direct sector reads
  remain local where the caller does not need `DE` preserved or is writing a
  sector. This reduced the live Debug80 image to 14,964 bytes, leaving 1,420
  bytes in the current 16K bank.
- Done: add `Tecm8StorageAdvancePrefixEntryPtr` and
  `Tecm8StorageAdvanceCatalogEntryPtr` for table-entry walks that must preserve
  the current scan offset in `DE`. This replaces both duplicated preserved-add
  sequences and older scratch-`DE` entry advances in project config and editor
  storage. The new `editor-nonfirst-catalog-save-proof` seeds a preceding
  `/src/first.asm` catalog entry and proves `/src/main.asm` still saves back to
  the correct catalog entry. This leaves the live Debug80 image at 14,966 bytes,
  with 1,418 bytes free in the current 16K bank.
- Done: add `Tecm8StorageBlockSectorToOffset` for source-page read/write paths
  that convert a resolved TM8 block plus sector-in-block into a MON3 byte
  offset. This is a code-organization helper rather than a size win: the live
  Debug80 image is now 14,969 bytes, leaving 1,415 bytes free in the current
  16K bank. AZM strict contracts caught the first draft because it tried to use
  `A` after calling `Tecm8StorageBlockToOffset`, whose contract clobbers `A`;
  the helper now preserves `AF` across that call.
- Extract shared superblock validation, byte matching, prefix scan, catalog
  scan, allocation-chain follow, and file-relative sector read/write helpers.
- Route `project-config-loader`, `editor-storage-loader`, and
  `editor-file-list` through the shared layer.
- Keep the layer narrow: it should support the operations TECM8 already uses,
  not become a full remove/rename/truncate/general filesystem API.
- Preserve current error codes or provide a deliberate mapping layer so
  user-facing compact status messages remain stable.

Done when:

- Project config, file listing, storage, editor page load/save, backup, and
  allocation-growth proofs pass.
- Manual Debug80 editor image preparation still produces the same user-facing
  fixture.
- The storage byte delta and any new shared entry points are documented.

### Q5: Editor Interaction Decomposition

Goal: make editor behavior reviewable without changing what it does.

Target ownership:

- `src/editor-keymap.asm`: key normalization, command lookup, and dispatch
  tables/helpers.
- `src/editor-cursor.asm`: cursor position, visibility, blink, render/erase.
- `src/editor-record.asm`: editor-facing fixed-record addressing wrappers and
  record-operation scratch state shared by line-edit and block-edit paths.
- `src/editor-line-edit.asm`: character insert/delete, split, join, fixed-record
  mutation.
- `src/editor-block.asm`: ordinary selection, pending copy/move source, paste,
  replace, delete, and block marker state.
- `src/editor-prompt.asm`: status-line prompts and modal yes/no handling.
- `src/editor-render.asm`: dirty render policy that connects editor state to
  viewport/display scheduling.
- `src/editor-interaction.asm`: orchestration glue and the live/script loops.

Actions:

- First move code without changing logic. Update include order and tests only as
  needed for symbol locations.
  - Current checkpoint: cursor reset, render/erase, blink, and invalidate
    routines now live in `src/editor-cursor.asm`; `src/editor-interaction.asm`
    still owns the shared editor constants and state bytes during the
    transition.
  - Current checkpoint: key normalization, movement-action lookup, and
    Ctrl-modified command lookup now live in `src/editor-keymap.asm`;
    `src/editor-interaction.asm` still performs the command dispatch.
  - Current checkpoint: status-line yes/no prompt handling now lives in
    `src/editor-prompt.asm`; block deletion itself remains with block mutation
    code for the later block-module extraction.
  - Current checkpoint: dirty render policy, cursor visibility checks, and
    dirty-column scratch state now live in `src/editor-render.asm`.
  - Current checkpoint: editor-facing record addressing wrappers, record helper
    wrappers, cursor advance, and line-edit scratch bytes now live in
    `src/editor-record.asm`.
  - Current checkpoint: character insert/delete, split, join, row-15 growth, and
    cross-page join now live in `src/editor-line-edit.asm`; block mutation remains
    in `src/editor-interaction.asm`.
- After movement is green, collapse duplicated cursor-reset and movement
  handler shapes into shared routines.
- Move selection state out of viewport if it is not purely projection state.
  The viewport should answer "what marker appears on this visible row?", not
  own the block editing model.
- Keep public entry names stable where proofs or docs use them; add wrappers
  during transition rather than broad rename churn.

Done when:

- The monolith is reduced to orchestration and compatibility wrappers.
- `npm run check` passes after each sub-step.
- Manual editor behavior is unchanged.

### Q6: Resident Product Compactness

Goal: separate resident shell/kernel code from the live editor bank while
preserving the shell as the TECM8 operating-system personality.

Actions:

- Split shell command resolution from the interactive shell program. The live
  editor entry should include the resolver and editor launch path, not proof
  stubs or unused prompt loops.
- Treat the shell as its own project with resident APIs: project config,
  command dispatch, tool launch/return, bank switching, and compact status/error
  output.
- Treat the editor as a banked tool project. Its code-quality target is to fit
  comfortably in one 16K bank, calling resident services rather than owning
  shell state.
- Gate or separate proof-only entry points such as scripted key runners and
  proof counters if they are not needed in the resident image.
- Review synchronous GLCD compatibility wrappers. Keep them where a blocking
  flush is deliberate; otherwise prefer the cooperative stepper.
- Consider table-driven dispatch in the extracted keymap and shell resolver
  once behavior and module ownership are stable.

Done when:

- The live editor binary is measurably smaller or the retained resident code is
  explicitly justified.
- The shell/editor boundary is documented as a resident-to-banked-tool call
  boundary, not as a temporary proof convenience.
- Proof-only behavior remains testable without bloating the live path.
- `npm run check` and the manual Debug80 image path still work.

### Q7: Contracts, Documentation, And Acceptance

Goal: make the new organization the documented system.

Actions:

- Audit public labels for AZMDoc `;!` contracts.
- Update `docs/codebase.md` with the new module map and reading order.
- Update `docs/memory-and-code-quality.md` with current RAM use and binary size.
- Update `docs/roadmap.md` with the completed quality phases and the next
  feature milestone.
- Run `npm run quality` and decide which TypeScript findings become future work.
- Reconcile this plan with `docs/typescript-code-quality.md`: host-tooling
  cleanup should follow the Z80 bank-readiness pass unless duplicated proof
  harness code blocks the Z80 work.

Done when:

- `npm run check` passes.
- `npm run quality` has been reviewed.
- The current binary size and code-organization state are documented.
- The user has a short manual Debug80 script for any editor-visible changes.

## Verification Policy

Use targeted proof commands while working, but every committed phase must end
with:

```text
npm run check
```

For doc-only changes, `git diff --check` is sufficient. For Z80 code changes,
also record:

- `build/main.bin` size,
- relevant targeted proof commands,
- whether a manual Debug80 check is recommended,
- any AZM contract issues encountered.

If a phase affects live editor behavior, prepare the image with:

```text
npm run debug80:editor-image
```

and list the exact manual keys to test.

## Immediate Next Goal

The next practical quality goal is **Q0: Baseline And Guardrails**. It should be
small and non-invasive: verify the current tree, record size, and decide the
measurement surface before code starts moving. After that, proceed into Q1/Q2
before attempting the larger `editor-interaction.asm` split. The architectural
goal behind the quality pass is a bank-ready editor and a clean resident shell
boundary, not a standalone editor detached from TECM8 OS.

Do not start named block read/write, character selections, bank switching, or
MON3 BIOS replacement as part of this quality pass.
