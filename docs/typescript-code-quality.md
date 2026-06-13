# TECM8 TypeScript Code-Quality Report (fallow)

A `fallow` analysis of the **host TypeScript** in `tools/` — proof runners,
host tooling, and tests — focused on **redundancy and dead-code removal**. This
is the companion to the Z80 [code-quality remediation plan](code-quality-remediation-plan.md);
that one covers the on-device `.asm`, this one covers the support code that
builds images, drives Debug80, and asserts behavior. The two are independent:
nothing here touches the editor binary or runtime.

## Context

The TypeScript side is pure host tooling: TM8 volume format
(`tools/tm8/format.ts`), the `fs` CLI, the `run-*.ts` proof runners that
assemble Z80 via `@jhlagado/azm` and drive Debug80, the MON3 analysis tools, and
the `*.test.ts` suite. It has no size or runtime constraint — its only job is to
be a fast, trustworthy safety net. So the quality bar here is **low duplication
and no dead weight**, and refactors are guarded directly by `npm run test` /
`npm run check`.

**Tool:** `fallow` 2.86.0 (a TS/JS analyzer for unused code + duplication),
already a devDependency. Reproduce with:

```sh
npx --no-install fallow dead-code --root . --no-cache
npx --no-install fallow dupes     --root . --no-cache
```

## Headline

Almost the inverse of the Z80 findings:

- **Dead code: essentially clean** — 2 unused exports, both possibly intentional API.
- **Redundancy: severe — 31.6% duplication** (3,927 duplicated lines, 153 clone
  groups, 27 files), concentrated in proof-runner setup and test scaffolding.

---

## Findings

### TS-F1 — Duplication is the dominant issue: 31.6% (3,927 lines)  [redundancy]
`fallow dupes` reports **153 clone groups** spanning 27 files, which it rolls up
into 73 "clone families" with extraction recommendations. The duplication has
three structural root causes, each = a missing shared module:

**(a) No shared proof harness.** Every `run-*.ts` re-implements the same
ceremony — build a FAT32 image, configure the Debug80 TEC-1G runtime, load the
MON3 ROM, disable shadow ROM, seed SD state, assemble the proof program, and
read back symbols / GLCD pixels / result markers. fallow's largest run-runner
recommendations:

| Clone block | Instances | Files | ~lines saved |
|---|---|---|---|
| FAT32/runtime setup family | 9 groups | `run-display-proof`, `run-editor-viewport-storage-proof` | 397 |
| 56-line setup block | ×5 | `run-debug80-editor-session`, `run-display-proof`, `run-editor-viewport-storage-proof`, `run-project-config-proof`, `run-shell-commands-proof` | 224 |
| 105-line block | ×3 | `run-debug80`, `run-display`, `run-editor-viewport-storage` | 210 |
| 19-line bootstrap | ×7 | all 6 `run-*` + `build-keyboard-tester` | 114 |

**(b) No shared test helper.** Every `*.test.ts` repeats the same import header,
TM8-fixture construction, and record/marker assertion patterns:

| Helper | Repeated across | ~lines saved |
|---|---|---|
| 15-line setup/assert | ~26 sites in 6 test files | 375 |
| 9-line fixture header | ~26 sites in 8 test files | 225 |
| 12/13-line builders | 8–11 test files | 84 + 130 |

**(c) `editor-interaction.test.ts` is internally duplicated to a fault.** This
single ~40 KB file appears in **193 clone instances** — fallow recommends
extracting **24 clone groups (~859 lines)**. It is the #1 target by a wide
margin: the key-stream → expected-state cases are copy-pasted rather than
table-driven.

Secondary: the MON3 analysis tools (`mon3-service-inventory.ts`,
`mon3-storage-split.ts`, `mon3-glcd-split.ts`) share 83–90-line blocks, and
`tools/tm8/format.test.ts` has 7 internal clone groups (~103 lines).

> Note on totals: 3,927 lines is the *measured* duplication. fallow's
> per-family savings sum higher (~6 k) because suggestions overlap (one line can
> belong to several proposed extractions). Treat ~3,900 lines as the realistic
> ceiling.

### TS-F2 — Dead code is minimal, but verify the two exports  [dead-code]
`fallow dead-code` found only **2 unused exports**, both in `tools/tm8/format.ts`:
`TM8_CATALOG_ENTRY` (:1004) and `TM8_PREFIX_ENTRY` (:1006). No TS consumer
imports them. They may be **intentional format-layout API** (the Z80 side
declares its own copies of these constants), so confirm intent: either
re-export them as part of a documented `format` API surface, or delete them.
This is the only dead-code finding — the proof runners and tests are otherwise
fully reachable (fallow detects entry points from `package.json` scripts and the
`*.test.ts` files).

### TS-F3 — The wired-up quality gate is a no-op  [process]
`package.json` defines `"quality": "fallow --root . --skip dead-code || true"`.
Two problems: it **skips the dead-code analysis** outright, and the trailing
`|| true` **swallows every failure**, so the gate can never fail CI even when
fallow reports issues. As-is it provides false assurance.

---

## Remediation plan

Pure host-tooling refactors. The safety net is direct: after each step,
`npm run test` (and the relevant `npm run proof:*`) must pass, since the runners
and tests *are* the thing being refactored — a broken extraction fails loudly.

### Phase 0 — Baseline
- Record current duplication: `npx --no-install fallow dupes --root . --no-cache`
  → 31.6%. This is the number every later phase drives down.
- `npm run check` green.

### Phase 1 — `tools/proof-harness.ts` (kills TS-F1a)
Extract the shared proof ceremony into one module, then re-point every
`run-*.ts` at it. Candidate exports (named from the clone blocks):
- `buildFat32Image(opts)` / `createTm8Volume(...)` — image + volume construction.
- `startTecRuntime(cfg)` — Debug80 TEC-1G runtime, MON3 ROM load, shadow-ROM
  disable, SD seed.
- `assembleProof(src)` — `@jhlagado/azm` assembly with strict `;!` contracts +
  `src/mon3.asmi`.
- `readSymbol(name)` / `readGlcd()` / `captureGlcdPgm(path)` / `expectResultMarker()`.
- **Verify:** `npm run check` (every proof runner exercises the new harness).

### Phase 2 — `tools/test-support.ts` (kills TS-F1b)
Extract shared fixture builders and assertions used across `*.test.ts`:
- `makeSourceVolume(pages)` / `withTm8Fixture(...)` — fixture construction.
- `expectRecord(buf, row, text)` — 32-byte record text + zeroed-padding check.
- `expectMarkers(...)` / `expectCursor(...)` — gutter/cursor assertions.
- Replace the duplicated import headers and inline builders with imports.
- **Verify:** `npm run test`.

### Phase 3 — Rewrite `editor-interaction.test.ts` table-driven (kills TS-F1c)
Collapse the 24 internal clone groups (~859 lines) by expressing cases as data:
`{ name, keyStream, expect: { dirty, cursor, records, markers } }` walked by one
runner built on `test-support.ts`. Target: drop this file's duplication share to
near zero while keeping identical coverage.
- **Verify:** `npm run test` shows the same case count/coverage.

### Phase 4 — MON3 tools + `format.test.ts` tidy
- Factor the shared 83–90-line block out of the three `mon3-*-split/inventory`
  tools into a small `mon3-report` helper.
- Extract `format.test.ts`'s 7 internal clone groups.
- Resolve TS-F2 (keep-or-delete the 2 unused exports).
- **Verify:** `npm run test`, `npm run mon3:*:check`.

### Phase 5 — Make the quality gate real (TS-F3)
- Change `quality` to actually enforce: run `fallow dead-code` + `fallow dupes`,
  drop the `|| true`, and set a duplication threshold (start at the post-refactor
  number, ratchet down). Keep `--no-cache` or wire the cache to ignore stale
  cross-project entries (the `.fallow/cache.bin` currently references old
  `/projects/ZAD/` paths).
- **Verify:** `npm run quality` fails on a deliberately added clone, passes clean.

---

## Verification
- `npm run test` — the TS suite (this *is* the safety net for Phases 1–4).
- `npm run check` — full typecheck + tests + all proofs + Debug80 smokes.
- `npx --no-install fallow dupes --root . --no-cache` — watch the 31.6% fall after
  each phase; `fallow dead-code` should stay at 0 (post TS-F2).
- Spot-run affected proofs, e.g. `npm run proof:display:editor-viewport:storage`,
  `npm run proof:display`, `npm run debug80:editor-session`.

## Risks & non-goals
- **Risk:** a harness extraction that subtly changes runtime/image setup could
  make a proof pass for the wrong reason — extract behavior-preservingly and
  confirm each runner still asserts the same markers.
- **Non-goals:** no change to the Z80 source, the editor binary, or proof
  *coverage*; no new test framework; host tooling stays TypeScript (no Python
  helpers).

## Appendix — reproduce
```sh
npx --no-install fallow dead-code --root . --no-cache --format markdown
npx --no-install fallow dupes     --root . --no-cache --format markdown
# fallow also offers: health (complexity hotspots), audit (changed-files only),
# and `fallow fix` for safe auto-removal of unused code.
```
