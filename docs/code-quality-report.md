# TECM8 Z80 Code Quality Report

**Purpose:** Actionable plan for a coding agent to improve compactness, structure, and coherence without breaking the proof-driven editor milestone.

**Scope:** 24 assembly modules under `src/` (~11,400 lines), 30+ display proofs, TypeScript harness. Full editor binary (`src/main.asm`) currently assembles to **14,969 bytes** at `0x4000`, leaving **1,415 bytes** in the 16 KiB bank.

**Date:** June 2026 (post editor milestone / block-editing V1 automation)

---

## Executive Summary

TECM8 is a **working, proof-hardened Z80 editor** with unusually good engineering for retro assembly: AZM register contracts, strict proof runners, incremental GLCD scheduling, and a thoughtful 2 KiB RAM edit window. The code **runs and the architecture direction is sound**.

The main problem is **incremental growth without consolidation**. Features landed phase-by-phase (multi-page editing, horizontal scroll, block ops, cooperative display) inside existing files instead of being factored into shared libraries. The result:

| Symptom | Primary location |
|--------|-------------------|
| One file doing too much | `editor-interaction.asm` (747 lines after keymap/cursor/prompt/render/record/line-edit/block extraction) |
| Copy-pasted TM8 I/O | `editor-storage-loader.asm` |
| Parallel constant namespaces | `display-model.asm`, `glcd-tile.asm`, `editor-viewport.asm`, `editor-interaction.asm` |
| Legacy state kept for compatibility | `EditorNavDirty` vs `EditorNavDirtySectors` |
| Dead code kept alive by tests | `EditorKeyDirtyPageBlocked` |
| Docs describing superseded V1 policy | `docs/editor-design.md`, `docs/codebase.md` |
| Full shell linked into editor entry | `main.asm` includes all of `shell-commands.asm` |

**Estimated recoverable ROM** from deduplication and module factoring (not splitting features): **~800–1,200 bytes** in the current editor binary, plus substantial maintainability gains. Further savings (~2–4 KiB) require **excluding unused shell-program code** from the live editor link and preparing **banked overlays** (already planned in docs, not implemented).

---

## What Is Working Well (Do Not Break)

These are strengths to preserve through refactoring:

1. **BIOS boundary** (`tecm8-bios.asm`, 386 lines) — thin MON3 wrappers; higher layers do not hard-code ROM addresses.
2. **Proof gate** — `npm run check` runs 40+ proof/smoke steps; any refactor must keep this green after each increment.
3. **Cooperative GLCD** — `GlcdTileStep`, dirty row mask, dirty cell byte ranges; live loop polls keyboard between display slices.
4. **Mutation API** — primitives return `A=1` (changed) / `A=0` (noop); prevents spurious dirty marks.
5. **RAM window policy** — fixed `3000h–37FFh` workspace documented in `editor-navigation.asm` and [Memory and Code Quality Manifest](memory-and-code-quality.md).
6. **Static TypeScript tests** — entry-point and contract assertions in `tools/*.test.ts` catch accidental API drift.

---

## Current Module Map

```text
                    ┌─────────────────────┐
                    │   shell-commands    │  ← resolver + full shell program (mixed)
                    └──────────┬──────────┘
                               │
                    ┌──────────▼──────────┐
                    │ shell-editor-launch │  ← clean bridge (91 lines)
                    └──────────┬──────────┘
                               │
         ┌─────────────────────┼─────────────────────┐
         │                     │                     │
┌────────▼────────┐  ┌─────────▼─────────┐  ┌───────▼────────┐
│ editor-nav      │  │ editor-interaction │  │ editor-viewport│
│ (page/cache/    │  │ (MONOLITH)         │  │ (render proj.) │
│  save/backup)   │  └─────────┬──────────┘  └───────┬────────┘
└────────┬────────┘            │                     │
         │            ┌────────▼──────────┐  ┌───────▼────────┐
         └───────────►│ editor-storage-   │  │ display-model  │
                      │ loader (TM8 I/O)  │  └───────┬────────┘
                      └───────────────────┘          │
                                              ┌──────▼────────┐
                                              │  glcd-tile    │
                                              └───────┬────────┘
                                              ┌──────▼────────┐
                                              │  tecm8-bios   │
                                              └───────────────┘
```

**Include order in proofs and `main.asm`:** glcd-tile → display-model → editor-block-state → editor-viewport → editor-storage-loader → editor-navigation → editor-interaction → editor-record → editor-line-edit → editor-block → editor-keymap → editor-cursor → editor-prompt → editor-render → shell-* → tecm8-bios. This order is consistent across ~25 proofs but **always pulls the full stack**, even for proofs that only need viewport rendering.

---

## Critical Issues (Ranked by Impact)

### 1. `editor-interaction.asm` is a monolith (highest priority)

**747 lines, now mostly orchestration but still carrying shared constants/state:**

| Approx. lines | Concern |
|---------------|---------|
| Extracted | Key normalization and command lookup now live in `editor-keymap.asm` |
| Extracted | Cursor overlay and cooperative blink now live in `editor-cursor.asm` |
| Extracted | Prompt dispatch now lives in `editor-prompt.asm` |
| Extracted | Dirty render policy now lives in `editor-render.asm` |
| Extracted | Editor-facing record helpers and line scratch now live in `editor-record.asm` |
| Extracted | Character insert/delete, split, join, row-15 growth, and cross-page join now live in `editor-line-edit.asm` |
| Extracted | Block selection, pending copy/move, paste, replace, and delete now live in `editor-block.asm` |
| ~55–675 | Key dispatch (`EditorRunKeys`, `EditorRunLive`, handlers) |
| ~677–747 | Remaining shared state and prompt/status strings |

This is the single largest barrier to review, banking, and compactness. A Z80 editor **should** have a key loop module, but not one that also owns TM8 record algebra, block editing, cursor rendering, and GLCD dirty scheduling.

### 2. No shared TM8 path/catalog layer

`editor-storage-loader.asm` (~1,626 lines) repeats the same **open volume → parse path → superblock → prefix branch** sequence three times (load ~L100–119, save ~L181–200, create ~L224–243). Catalog/prefix sector walks appear in four structural variants. `editor-file-list.asm` reaches into loader internals instead of calling shared helpers.

`ProjectLoadMatchBytes` in `project-config-loader.asm` and `EditorLoadMatchBytes` in `editor-storage-loader.asm` are **byte-identical DJNZ loops**.

**Estimated duplication:** 350–550 bytes ROM + ongoing bug surface when TM8 layout changes.

### 3. Legacy dual dirty-state track

Navigation maintains both:

- `EditorNavDirtySectors` (bits: current, adjacent next)
- `EditorNavCachedPageDirty`
- `EditorNavDirty` (aggregate, explicitly labeled “legacy” at L609–610)

Quit/save prompts in interaction read **`EditorNavDirty` only** (L406, L430). Cross-sector split/join paths in interaction write **`EditorNavDirtySectors` directly** (e.g. L2032–2057), bypassing `EditorMarkDirty`. Today `EditorNavRefreshAggregateDirty` bridges the gap, but the dual track is fragile and adds sync code on every path.

**Recommendation:** One `EditorNavIsDirty` helper; retire `EditorNavDirty` byte once all call sites use sector+cache bits.

### 4. Nine near-identical 32-byte row-shift loops

Split, join, block paste, insert, and cross-page paths each implement their own `LDIR`-based shift loop with `EditorLineRowsLeft` countdown. Same algorithm, different labels (`EditorSplitShiftLoop`, `EditorJoinShiftLoop`, `EditorPendingBlockShiftLoop`, `EditorSplitFinalNextShiftLoop`, etc.).

**Estimated duplication:** 400–500 bytes.

### 5. Parallel display geometry constants

Three namespaces define the same screen:

- `TECM8_DISPLAY_*` in `display-model.asm` (L6–24)
- `TECM8_GLCD_TILE_*` in `glcd-tile.asm`
- Record constants in `editor-viewport.asm` and `editor-interaction.asm` under different names (`TECM8_EDITOR_RECORD_*` vs `TECM8_EDITOR_EDIT_RECORD_*`)

Drift risk is real; this is maintenance debt, not just bytes.

### 6. Block-editing projection remains split from mutation

Persistent block state now lives outside viewport in `editor-block-state.asm`
(selection interval and pending copy/move source), while mutation lives in
`editor-block.asm`. Viewport keeps marker projection scratch because it answers
the visible-row question for display rendering. Line mutation is isolated in
`editor-line-edit.asm`, status-line prompt control flow is isolated in
`editor-prompt.asm`, and display scheduling is isolated in `editor-render.asm`.
Viewport also holds **prompt flags** (`EditorPromptActive`).

The remaining split is intentional for now but should be watched as block editing
becomes multi-page: viewport should not grow back into the owner of block policy.

### 7. `glcd-tile.asm` dirty-bit boilerplate

Six routines repeat the same “row < 8 → low mask table, else high mask table” branch for dirty row scheduling (~15 lines × 6). A single `GlcdTileDirtyRowApply(A)` internal helper would save **~150–200 bytes**.

### 8. Full shell program linked into live editor

`main.asm` includes all of `shell-commands.asm` (1,362 lines) but `LiveStart` only needs:

- `RunShellCommandLine` → resolver → `ShellRunEditorLine`

Unused in live path: `RunShellProgramEntry`, `RunShellProgramCycles`, `ReadShellInputLine`, stub keyboard providers, executor stubs. All of this is still assembled into the 15 KiB binary.

**Recommendation:** Split into `shell-resolver.asm` (path/command resolution) and `shell-program.asm` (interactive loop). `main.asm` should include only resolver + launch.

### 9. Stale documentation describing superseded behavior

| Document | Says | Code actually does |
|----------|------|-------------------|
| `docs/editor-design.md` L292–299 | V1 does **not** shift records across sectors | `EditorSplitFinalRow`, `EditorSplitPushLastRecordToNextPage`, `EditorJoinPreviousPageLine` implement cross-page split/join |
| `display-model.asm` L4 | “display proof surface, not an editor” | Core production render path |
| Earlier block-edit notes | “overlap/self cases left for B6” | B6 paste/replace and overlap rejection are implemented |

These are **echoes of earlier milestones** (roadmap Phase 2 is largely done in code but not fully reflected in design docs).

### 10. Dead code kept by test assertion

```asm
EditorKeyDirtyPageBlocked:
        LD      HL,EditorStatusSaveFirstText
        CALL    EditorKeyShowStatus
        RET     C
        JP      EditorKeyLoop
```

(`src/editor-interaction.asm`, label `EditorKeyDirtyPageBlocked`)

**No caller.** `tools/editor-interaction.test.ts` still requires this dead handler to exist. Likely remnant of abandoned “save before page move on dirty page” policy. Either wire it up or delete handler + test + `EditorStatusSaveFirstText` string.

---

## Duplication Inventory (Estimated ROM)

| Hotspot | Files | Est. bytes |
|---------|-------|------------|
| TM8 open + prefix resolve | storage-loader ×3, file-list | 150–250 |
| Catalog/prefix sector scan loops | storage-loader | 200–300 |
| 32-byte row shift loops | interaction ×9 | 400–500 |
| GLCD dirty row bit mask | glcd-tile ×6 | 150–200 |
| Cursor render/erase mirror blocks | display-model | 100–150 |
| MatchBytes | storage-loader, project-config-loader | 20–30 |
| Page×16 absolute line calc | interaction, viewport | 30–40 |
| 512-byte buffer clear loops | navigation ×2 | 30–40 |
| Render prelude (hide cursor, ensure visible) | interaction ×3 | 60–90 |
| **Total dedup opportunity** | | **~800–1,200** |

---

## Memory Layout Assessment

**Good:**

- Editor workspace `3000h–37FFh` (2 KiB) with explicit slot assignment in `editor-navigation.asm`
- `3800h–3FFFh` reserved for growth
- TGBUF at `13C0h` shared with MON3 — intentional

**Needs improvement:**

- **No single manifest file** — RAM equates spread across navigation, viewport (320-byte row text buffers), interaction scratch. Add `src/tecm8-memory.asm` or extend [Memory and Code Quality Manifest](memory-and-code-quality.md) with a machine-readable equ block included by all modules.
- **Implicit buffer aliasing** — block paste uses `EditorNavBackupPageBuffer` as scratch during paste (`editor-block.asm`). Safe if operations don’t interleave, but undocumented and risky for future async paths.
- **`TECM8_EDITOR_NAV_CACHE_BASE` == `TECM8_EDITOR_NAV_WORKSPACE_BASE`** (both `0x3000`) — correct sizing, confusing names.

---

## Proof and Tooling Hygiene

### Proof include patterns

Most editor proofs include **7–9 modules** identically. Consider:

- **`proofs/display/editor-common.inc`** — standard include block with documented dependency order
- **Tiered proofs** — viewport-only proofs should not need `editor-interaction.asm` (today some do unnecessarily)

### TypeScript proof runners

`fallow` reports **153 clone groups** in `tools/` — especially `run-display-proof.ts`, `run-editor-viewport-storage-proof.ts`, `run-debug80-editor-session.ts` sharing 100+ line blocks (Debug80 setup, FAT32 image prep, GLCD capture). This does not affect Z80 ROM but slows maintenance.

**Recommendation:** Extract `tools/debug80-proof-runtime.ts` with shared compile, mount, step, and symbol-read helpers.

### Measurement gap

[Memory and Code Quality Manifest](memory-and-code-quality.md) calls for per-module byte tracking but **no script exists**. Add `tools/measure-z80-modules.ts` that assembles `main.asm` and reports symbol address ranges (AZM d8m output already available from build).

---

## Recommended Module Split Plan

Execute **incrementally**; run `npm run check` (or targeted proof npm scripts) after each step.

### Phase A — Low risk, high dedup (do first)

| Step | Action | New file | Gate |
|------|--------|----------|------|
| A1 | Extract shared record constants + helpers | `src/editor-record.asm` | `proof:display:editor-line-editing`, `editor-mutation-boundary` |
| A2 | Extract `ShiftRecordsDown` / `ShiftRecordsUp` parameterized by count | same | split/join proofs |
| A3 | Extract `Tm8MatchBytes`, shared TM8 layout equates | `src/tm8-bytes.asm` | project-config + storage proofs |
| A4 | Extract `Tm8OpenVolumePath(DE)` prefix-ready block | `src/tm8-path.asm` | storage + file-list proofs |
| A5 | Unify display geometry equates | `src/tecm8-display-equ.asm` | glcd-tile, display-model, viewport tests |

### Phase B — Split the monolith

| Step | Action | New file | Gate |
|------|--------|----------|------|
| B1 | Key dispatch + live loop | `src/editor-keys.asm` | `debug80:editor-live-smoke` |
| B2 | Cursor + blink + visibility scroll | `src/editor-cursor.asm` | dirty-render proof |
| B3 | Dirty render policy | `src/editor-render.asm` | dirty-render proof |
| B4 | Block selection/paste/delete | `src/editor-block.asm` | `acceptance:block-editing-v1` |
| B5 | Slim interaction to glue + prompts | keep `editor-interaction.asm` ~400–600 lines | full check |

**Target:** `editor-interaction.asm` becomes orchestrator only; no file over ~1,000 lines except `editor-storage-loader.asm` (until Phase C).

### Phase C — Storage and shell compactness

| Step | Action | New file | Gate |
|------|--------|----------|------|
| C1 | Catalog/prefix scan helpers | `src/tm8-catalog.asm` | all storage proofs |
| C2 | Split shell | `shell-resolver.asm`, `shell-program.asm` | shell-commands proof + main.asm size check |
| C3 | `main.asm` includes resolver only | — | measure ROM drop |

### Phase D — State and doc cleanup

| Step | Action | Gate |
|------|--------|------|
| D1 | Retire `EditorNavDirty`; add `EditorNavIsDirty` | page-write, window-save proofs |
| D2 | Done: move block **state** from viewport to `editor-block-state.asm` (viewport keeps projection only) | selection proof |
| D3 | Delete or wire `EditorKeyDirtyPageBlocked` | update `editor-interaction.test.ts` |
| D4 | Update `docs/editor-design.md` § Sector-Edge Editing Policy and `docs/codebase.md` L549 | doc review only |
| D5 | Fix stale comments (“left for B6”, “not an editor”) | — |

---

## Compactness Principles for the Agent

When implementing the plan:

1. **Prefer one parameterized loop over N copy-pasted loops** — especially for 32-byte record shifts and TM8 catalog walks.
2. **Prefer `.include` of equ-only headers** over duplicating constants — Z80 has no linker; shared equates cost zero bytes if in a header included once.
3. **Do not inline for bytes until measured** — docs correctly say clarity first; dedup shared loops is the exception because it reduces bytes *and* bugs.
4. **Keep public `@` entry points stable** — proofs and TS tests grep for symbol names; deprecate by wrapper, don’t rename without updating tests.
5. **New modules need AZM `;!` contracts** on every public entry — match [AZM Style Guide](azm-style-guide.md).
6. **Banking prep:** new modules should avoid hidden cross-module statics; pass buffer pointers in HL/DE. This matches the overlay plan in [Memory and Code Quality Manifest](memory-and-code-quality.md).

---

## Include Dependency Rules (Target State)

```text
tecm8-display-equ.asm     (equates only, no code)
tecm8-memory.asm          (equates only)
tm8-bytes.asm             (TM8 layout equates + MatchBytes)
tm8-path.asm              → tecm8-bios, tm8-bytes
tm8-catalog.asm           → tm8-path
editor-record.asm         → editor-viewport state, editor-cursor state, tecm8-record
glcd-tile.asm             → tecm8-display-equ, tecm8-bios
display-model.asm         → glcd-tile
editor-viewport.asm       → display-model, editor-record
editor-storage-loader.asm → tm8-path, tm8-catalog
editor-navigation.asm     → editor-storage-loader, editor-viewport
editor-line-edit.asm      → editor-record, editor-navigation
editor-cursor.asm         → display-model, glcd-tile
editor-render.asm         → editor-cursor, editor-viewport, glcd-tile
editor-block-state.asm    → data only
editor-block.asm          → editor-block-state, editor-record, editor-viewport
editor-keys.asm           → editor-navigation, editor-interaction glue
editor-interaction.asm    → keys, block, render, navigation (orchestration)
shell-resolver.asm        → project-config-loader
shell-program.asm         → shell-resolver
shell-editor-launch.asm   → shell-resolver, editor-navigation, editor-interaction
tecm8-bios.asm            → mon3.asmi
```

---

## Agent Execution Checklist

Copy this section directly to the implementing agent:

```text
[ ] Read docs/azm-style-guide.md and docs/memory-and-code-quality.md
[ ] Baseline: assemble main.asm, record 14969 bytes and symbol map
[x] Phase A1: create editor-record.asm, move editor-facing record wrappers and line scratch
[x] Phase B line-edit slice: create editor-line-edit.asm, move fixed-record insert/delete/split/join
[ ] Phase A2: EditorShiftRecordsDown/Up — replace 9 duplicate loops
[ ] Phase A3–A4: tm8-bytes.asm + tm8-path.asm — collapse 3× prefix-open blocks
[ ] Phase A5: tecm8-display-equ.asm — unify geometry constants
[ ] npm run check after each sub-step
[ ] Phase B: split editor-interaction.asm (B1→B5 order)
[ ] Phase C: tm8-catalog.asm; split shell-commands.asm
[ ] Phase C3: main.asm includes shell-resolver only; re-measure ROM
[ ] Phase D: dirty state unification; dead code removal; doc updates
[ ] Add tools/measure-z80-modules.ts
[ ] Optional: tools/debug80-proof-runtime.ts for TS dedup
[ ] Final: npm run check; document new byte count in memory-and-code-quality.md
```

**Acceptance criteria for the refactor milestone:**

- `npm run check` passes unchanged functionally
- No single `.asm` file over ~1,200 lines except `editor-storage-loader.asm` (until catalog extraction completes)
- `EditorNavDirty` removed or documented as deprecated with zero direct readers
- `docs/editor-design.md` sector policy matches implemented cross-page behavior
- Measured ROM reduction ≥ 500 bytes OR documented explanation if less (e.g. include overhead)

---

## What Not to Do Yet

- **Do not** pursue aggressive inlining or hand-tuned opcode tricks before module split — readability and proof safety come first.
- **Do not** implement general TM8 filesystem layer — loader stays narrow; just deduplicate its internals.
- **Do not** start bank switching until module boundaries are clean — overlay loading needs stable entry points.
- **Do not** merge display-model and glcd-tile — the layer split (policy vs transport) is correct; only unify **constants**.

---

## Summary Judgment

The codebase is **good software that outgrew its file boundaries**. Coherence at the Z80 level is reasonable (clear dependency direction, stable BIOS API, sensible RAM map), but **compactness and organization lag behind feature completeness** because each roadmap phase landed as incremental patches inside `editor-interaction.asm` and `editor-storage-loader.asm`.

The highest-value work is not rewriting algorithms — it is **extracting shared libraries, splitting the monolith, unlinking unused shell code from the editor entry, and syncing docs with the now-completed multi-page editing model**. That path gets you toward a structure that could live in banked ROM alongside a future assembler, which is the stated long-term product shape.

---

## Related Documentation

- [Codebase Tour](codebase.md)
- [Editor Design](editor-design.md)
- [Memory and Code Quality Manifest](memory-and-code-quality.md)
- [AZM Style Guide](azm-style-guide.md)
- [Roadmap](roadmap.md)
