# TECM8 Code Quality Audit

This document records the current code-health state of TECM8 and the quality
requirements future changes should meet. It is adapted from the Debug80
code-quality audit programme and is intentionally engineering-facing. The
memory and compactness pressure on the Z80 side is recorded separately in
[Memory and Code Quality Manifest](memory-and-code-quality.md); this document
covers the repository's process gates and the TypeScript host tooling.

Audit date: 2026-06-11

## Summary

TECM8 is a two-layer codebase: TEC-side Z80 assembly in `src/` (~7,900 lines,
13 modules) and TypeScript host tooling in `tools/` (~10,300 analyzed LOC).
The repository is in a healthy state: strict TypeScript, no circular
dependencies, no unused package dependencies, zero dead exports, machine-checked
AZM register contracts in error mode on the assembly, and a proof-driven gate
chain that runs every feature against Debug80's TEC-1G runtime.

The 2026-06-10 baseline audit found the main maintainability risks in the host
tooling, not the assembly: proof-runner harness code copy-pasted across seven
`run-*.ts` scripts (126 clone groups), two god-dispatcher `main()` functions
(`tools/fs.ts` cognitive 66, `tools/run-debug80-editor-session.ts` cognitive
64), duplicated MON3 report-tool plumbing, and two dead exports. Cleanup
Phases 1-4 (below) addressed all of these. The remaining flagged complexity is
concentrated in proof *verification* functions, which are sequential hardware
assertions and are accepted as-is unless they regress.

## Quality Gates

These are the repository's standing quality requirements. Blocking gates must
pass before a milestone commit; advisory gates are triage locators, not
verdicts.

| Gate | Command | Status |
| ---- | ------- | ------ |
| Strict typecheck | `npm run typecheck` | Blocking, zero errors |
| Test suite (structural + functional) | `npm run test` | Blocking, zero failures |
| MON3 report freshness | `npm run mon3:inventory:check`, `npm run mon3:storage-split:check`, `npm run mon3:glcd-split:check` | Blocking |
| Full proof chain | `npm run check` | Blocking before milestones |
| Dead code / dead exports | `npm run quality` | Blocking, zero findings |
| Complexity / hotspot locator | `npm run quality:health` | Advisory |
| Duplication locator | `npm run quality:dupes` | Advisory |
| AZM register contracts | enforced by proof runners (`registerContracts: 'strict'`, error mode) | Blocking |

Policy notes:

- Fallow is a locator, not a score to chase. Dense proof-verifier code and
  Z80-adjacent bit manipulation can be legitimately complex; refactor only
  when a named helper boundary makes hardware behavior easier to understand
  or test.
- The dead-code gate is enforceable because it is currently clean. Keep it
  clean: remove dead exports with the change that orphans them, and document
  intentional dynamic entrypoints rather than letting findings accumulate.
- AZM compile options must use the current `registerContracts*` names. The
  `registerCare*` aliases are deprecated in AZM and were removed from this
  repository on 2026-06-11.

## Audit Inputs

```sh
npx fallow --root . --only health --format compact
npx fallow --root . --only dead-code --format compact
npx fallow --root . --only dupes --format compact
npm run typecheck && npm run test
npm run check
```

Fallow vital signs:

| Metric | 2026-06-10 baseline | 2026-06-11 (post-cleanup) |
| ------ | ------------------: | ------------------------: |
| Analyzed LOC (tools) | 11,058 | 10,342 |
| Average cyclomatic | 2.1 | 2.0 |
| P90 cyclomatic | 4 | 4 |
| Dead exports | 6.3% | 0.0% |
| Average maintainability | 95.7 | 94.5 |
| Clone groups | 126 | 82 |
| Functions above complexity threshold | 65 | 62 |
| Critical god-functions (`main` ≥ cognitive 60) | 2 | 0 |
| Circular dependencies | 0 | 0 |
| Unused dependencies | 0 | 0 |

The LOC reduction is the duplicated harness code that now lives in shared
modules. The small maintainability-average drop is an artifact of removing
many simple duplicated lines while keeping the dense verifiers; it is not a
regression signal.

## Code Shape

- `src/`: Z80 assembly modules (editor interaction/navigation/storage-loader/
  viewport, shell commands, display model, GLCD tile layer, TECM8 BIOS
  wrappers, project config). Every routine carries `;!` register-contract
  annotations checked in error mode.
- `tools/proof/harness.ts`: shared Debug80/TEC-1G proof harness — path/ROM
  resolution, runtime types, AZM compile, TEC-1G and bare-Z80 runtime setup,
  run loops, memory readers, source-record codecs, FAT32/TM8 image helpers,
  GLCD cell assertions.
- `tools/run-*.ts`: proof runners. Each owns only its fixtures, proof case
  table, and verification logic; plumbing comes from the harness.
- `tools/tm8/format.ts`: authoritative host implementation of the TM8 volume
  format. `tools/fs.ts` is its CLI, dispatched through a typed command table.
- `tools/mon3-*.ts` + `tools/mon3/support.ts`: MON3 decomposition reports and
  their shared CLI/debug-map plumbing.
- `tools/*.test.ts`: structural tests over assembly/doc/runner sources plus
  functional tests for the TM8 format and MON3 reports. Shared file access
  lives in `tools/test-support.ts`.

## Findings

### P0: No Critical Architecture Failure

No circular dependencies, no unused dependencies, strict TypeScript
throughout, and behavior is pinned by an emulator-level proof chain. Cleanup
can remain incremental and commit-driven.

### P1 (resolved 2026-06-11): Proof Harness Duplication

Seven proof runners each carried their own copy of Debug80 module loading,
TEC-1G runtime configuration, MON3 ROM seeding, AZM compilation, run loops,
and GLCD cell decoding — the largest clones were 93 lines, and each new proof
grew the duplication linearly. All of it now lives in
`tools/proof/harness.ts`. Requirement going forward: a new proof runner must
not re-implement harness plumbing; extend the harness instead, and keep
harness changes behavior-preserving across all runners (`npm run check` is
the gate).

### P1 (resolved 2026-06-11): God Dispatchers

`tools/fs.ts` dispatched seventeen CLI commands through one cognitive-66
`main()`; it now uses a typed command table with per-command arity checks.
`tools/run-debug80-editor-session.ts` ran prepare/scripted/live-smoke flows
through one cognitive-64 `main()`; the flows are now separate functions and
the live smoke is decomposed into named phases sharing a context object.
Requirement going forward: new CLI commands are table entries, new smoke
coverage is a phase function — neither should grow a monolithic `main()`.

### P1 (policy): Structural Tests Must Follow Contract Ownership

The structural test suite asserts on source text (assembly labels, equate
values, runner wiring). This is deliberate: it pins contracts that the proofs
depend on. Two rules keep it honest:

- Shared fixture plumbing (repo-root file reading) lives in
  `tools/test-support.ts`; assertions themselves stay local and explicit and
  are not deduplicated, even though Fallow flags them as clones.
- When a contract moves between files (as the run-until budget,
  `registerContracts` options, and MON3 `SYS_MODE` policy moved into the
  harness), the assertion moves with it to the owning file in the same
  commit.

### P2: Remaining Duplication Is Accepted Test Structure

Of the 82 remaining clone groups, the large ones are structural-test
assertion blocks (kept by policy above) and paired validation helpers in
`tools/tm8/format.ts`. Refactor the format-layer pairs only when a change
already touches them with functional coverage in place; do not refactor
assertion blocks for aesthetics.

### P2: Proof Verifier Complexity Is Accepted As Sequential Assertions

The current top complexity findings (`verifyEditorAllocationGrowthProof`,
`verifyStructuredScreen`, `verifyEditorPageWriteProof`,
`smokeSplitSaveJoin`, `runProof` trace handling) are linear sequences of
hardware-state assertions. Splitting them further would scatter the proof
narrative without reducing regression risk. Revisit only if one of them
regresses repeatedly or needs to be reused.

### P3: Generated Proof Artifacts

FAT32 proof images, `.bin`/`.hex` artifacts, Debug80 session captures, and
last-run JSON reports are generated locally and ignored by git. Reproducibility
comes from the checked-in proof sources, fixture builders, MON3 reports, and
`npm run check`, not from committing generated binaries. Do not start tracking
or deleting artifact classes without updating the corresponding runner,
`.gitignore`, and proof-status documentation together.

## Cleanup Programme

### Phase 1: Shared Proof Harness (complete, 2026-06-11)

Extracted `tools/proof/harness.ts`; ported all seven runners; standardized on
AZM `registerContracts*` options; unified the run-until/error-diagnostic
paths. Verified by typecheck, full test suite, and the proof chain.

### Phase 2: Dispatcher Splits (complete, 2026-06-11)

`fs.ts` command table; Debug80 editor session main split into
prepare/scripted/live-smoke with named live-smoke phases.

### Phase 3: Shared Test And Report Plumbing (complete, 2026-06-11)

`tools/test-support.ts` for the structural tests; `tools/mon3/support.ts` for
the three MON3 report tools, including unifying the GLCD split tool's ad-hoc
CLI onto the staged parser.

### Phase 4: Dead Surface (complete, 2026-06-11)

Removed unused `TM8_CATALOG_ENTRY`/`TM8_PREFIX_ENTRY` exports and trimmed
unused harness type exports. The dead-code gate is clean and now blocking via
`npm run quality`.

### Phase 5 (future): TM8 Format Validation Helpers

`tools/tm8/format.ts` repeats assert/validate patterns (`assertPrefixText`/
`assertPathText`, chain validation). Candidate for a small validation helper
API when format work resumes. Verify with `tools/tm8/format.test.ts`.

### Phase 6 (future): Structural-Test Fixture Builders

If assertion files keep growing past ~400 lines (today:
`editor-interaction.test.ts` at ~400), add focused builders for repeated
regex families (entry-point lists, contract-comment checks) without moving
the assertions themselves.

## Quality Criteria For Future Changes

Use these when deciding whether cleanup or new code is acceptable:

- Does it remove obsolete behavior, not just move code around?
- Does it make a recurring regression harder to reintroduce?
- Does it reduce a public or cross-module surface area?
- Does it make product policy explicit in names, tests, or docs?
- Does it preserve proof behavior? `npm run check` must pass unchanged unless
  the change deliberately updates a proof contract.
- Is every new or moved assembly routine annotated with `;!` register
  contracts, and does the contract checker stay in error mode?
- Does every new editor/shell/storage feature land with a proof (AZM proof
  program plus runner case) in the same change?
- Do structural tests move with relocated contracts in the same commit?
- Can it be verified with focused tests rather than manual inspection only?

Avoid cleanup that:

- Refactors proof verifier assertion sequences or structural-test assertion
  blocks purely for aesthetics.
- Creates abstractions before two or three real call sites need them.
- Mixes product behavior changes with structural cleanup in one commit.
- Chases Fallow metrics in legitimately dense hardware-facing code.

## Priority Summary (2026-06-11)

| Priority | Issue | State |
| -------- | ----- | ----- |
| Critical | Proof harness duplication | Resolved (Phase 1) |
| Critical | `fs.ts` / editor-session god mains | Resolved (Phase 2) |
| High | Deprecated AZM `registerCare` options | Resolved (standardized) |
| Medium | MON3 report tool plumbing duplication | Resolved (Phase 3) |
| Medium | Dead exports | Resolved (Phase 4); gate now blocking |
| Low | TM8 format validation helper pairs | Deferred (Phase 5) |
| Low | Structural-test assertion clones | Accepted by policy |
| Low | Generated proof artifacts | Accepted by policy |
