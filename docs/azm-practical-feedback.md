# AZM Practical Feedback

This document records practical conclusions from using AZM on TECM8. It is
written for two audiences:

- TECM8 contributors deciding which AZM features to adopt next.
- AZM maintainers looking for concrete feedback from a real Z80 application.

It should stay evidence-based. When TECM8 adopts a feature, add the commit,
proof command, size result, and any discomfort or bug found during the work.

## Executive Conclusions

AZM has been a net positive for TECM8 because it makes hand-written Z80 code
more reviewable without hiding the machine. The strongest feature is register
contract checking: it catches real risks, encourages cleaner routine shape, and
turns vague calling-convention assumptions into compiler-checked facts.

The main limitation is that AZM's most useful discipline currently depends on
simple source-structure signals, especially `@` routine boundaries. That is a
reasonable first model, but real programs sometimes need non-local control
flow, jump-table dispatch, shared exits, or deliberate tail jumps. When those
patterns appear, AZM needs a way to express intent locally without weakening
strict checking for the rest of the file.

The second broad conclusion is that AZM's diagnostics and library/API surfaces
matter as much as the assembly syntax. TECM8 uses AZM from TypeScript proof
tools, not only from a shell command, and depends on D8/D8M artifacts, source
maps, external `.asmi` contracts, and stable compiler options. For projects
like TECM8, AZM is both an assembler and a verification library.

The third conclusion is that AZM should teach a diagnostics-first workflow.
Report files are useful for debugging and CI evidence, but the normal workflow
should be compiler diagnostics plus source comments. The persistent contract is
the source, not generated side files.

## Feature Scorecard

This is a practical scorecard from TECM8's current usage, not a general ranking
of every AZM feature.

| Feature | TECM8 experience | Keep using? | Main feedback |
|---|---|---:|---|
| AZMDoc register contracts | Very high value; changed code shape for the better | Yes | Add local suppressions/hints for non-local control flow |
| `--rc` modes | Useful development ladder from audit to strict | Yes | Document diagnostics-first workflow more prominently |
| `.asmi` external interfaces | Good fit for MON3 ROM calls | Yes | Provide more external ROM/API examples |
| D8/D8M artifacts | Essential for Debug80 proofs and size work | Yes | Add clearer byte ownership/routine range metadata |
| `.include` | Simple and reliable, but scales poorly | Yes, selectively | Add include-once/guard guidance for declarations |
| Shared `.equ` declarations | Worked well and was byte-neutral in first pilot | Yes | Expose resolved equates in machine-readable output |
| `.import` | Attractive, not adopted in production yet | Pilot carefully | Clarify source-map/contracts/output compatibility |
| Layout types | Strong candidate for record/disk structures | Pilot soon | Provide fixed-record and runtime-index examples |
| `.enum` | Useful for closed state families | Pilot later | Document value pinning and duplicate behavior |
| String directives | Low-risk readability win for NUL strings | Use locally | Document exact emitted bytes and non-use cases |
| `op` | Potentially useful but code-size risky | Rarely | Show expansion counts/byte costs in listings |

## Feedback For The AZM Team

The following are the highest-value product or documentation improvements from
TECM8's point of view.

1. Add routine-boundary and stack-effect hints.

   Strict register contracts are worth preserving, but AZM needs a way to mark
   deliberate non-local control-flow patterns: shared exits, tail jumps,
   jump-table dispatch, and routines that intentionally never return. A local
   annotation is preferable to disabling strict checking for a wider region.

2. Improve diagnostics around inferred routine boundaries.

   When AZM reports an unknown boundary, asymmetrical stack effect, or unsafe
   jump, the diagnostic should state the exact `@` region it inferred, the edge
   that crossed it, and the register/stack fact it could not prove. That would
   make the checker easier to trust during refactors.

3. Keep report files out of the default learning path.

   Teach `azm --rc audit program.asm`, `--rc warn`, `--rc error`, and
   `--rc strict` as the normal workflow. Mention `--reg-report` only as an
   advanced/export option for CI, large audits, or debugging AZM itself.

4. Provide an include-once or declaration-file pattern.

   Shared equate/layout files are useful, but textual `.include` makes every
   proof responsible for include order and duplicate prevention. AZM should
   either provide an include-once mechanism or document a canonical guard
   pattern for byte-free declarations.

5. Emit richer machine-readable metadata.

   TECM8 needs host tools to compare TypeScript and Z80 layout agreement,
   measure resident size, and reason about byte ownership. Resolved equates,
   layout offsets, routine ranges, and op expansion counts would all be useful
   as artifacts.

6. Treat TypeScript/library users as first-class.

   TECM8 assembles from Node-based proof runners. Stable compile APIs,
   documented options, and compatibility notes are important because the
   assembler sits inside a larger test harness.

## Current Evidence Base

TECM8 already depends heavily on these AZM surfaces:

- AZMDoc register contracts in source comments.
- Strict register-contract checking for the main editor image and proof
  programs.
- `.asmi` contracts for external MON3 routines.
- D8/D8M source-map output used by Debug80.
- Textual `.include` composition for source modules and proof harnesses.
- `.equ` constants and aliases for memory maps, records, key modifiers, and
  display geometry.

The codebase has only just started adopting additional native AZM structure.
The first concrete quality increment added `src/tecm8-equates.asm` and made
module-local constants alias shared canonical constants. That change was
byte-neutral: `npm run z80:size` still reports 15,235 bytes emitted at
`4000h..7B82h`.

Current concrete evidence:

- `7cac5c8 Add Z80 size baseline tooling`: added the `npm run z80:size`
  measurement surface and confirmed the fresh assembled editor image size.
- `a001409 Centralize shared Z80 equates`: added
  `src/tecm8-equates.asm`; proof and typecheck gates passed; size remained
  15,235 bytes.
- Current helper extraction: adding `src/tecm8-record.asm` moves masked
  source-record length reads, metadata-preserving length writes, padding
  zeroing, full-record clear, in-record text shifts, up/down record-window
  shifts, and resident-page block row copies into a shared module. Adding
  `src/tecm8-string.asm` moves the duplicated bounded byte matcher shared by the
  project config and editor storage loaders, the bounded NUL string copier used
  by shell/editor-navigation wrappers, and the shell's local-name path scanner.
  `npm run z80:size` reports 15,090 bytes, a 145-byte reduction from the
  original 15,235-byte baseline while preserving the older
  `EditorKey*Record*` wrapper entry points where external proof code still
  expects them.
- Shared helper proofs: `npm run proof:tecm8-string` assembles a standalone
  `4000h` proof that calls the shared string helpers directly and checks the
  bounded-copy edge cases that higher-level editor proofs only cover
  indirectly. This is a useful AZM pattern for small library routines before
  they gain more callers.
- Contract annotation experiment: running
  `azm --contracts --fix --rc audit --reg-profile mon3 --interface src/mon3.asmi src/main.asm`
  successfully rewrote contract comments across the included source tree. TECM8
  normalized those comments to one compact clause per `;!` line because that is
  easier to diff and review in dense assembly. During this work I briefly saw
  strict-check diagnostics after a broad generated rewrite, but I do not yet
  have an isolated repro proving an AZM parser or checker defect. Treat that as
  a local caution, not an actionable AZM bug report.

## Register Contracts

Register contracts have been the most valuable AZM feature for TECM8 so far.
They changed the way the Z80 code is written, not just how it is checked.

Practical advantages:

- Contracts catch the class of bugs most likely to hurt hand-written Z80:
  accidental register clobbers, unclear carry/zero use, and unreviewed stack
  effects.
- `--rc strict` forces routines to have clear boundaries. This has pushed code
  away from long jumpy flows and toward smaller routines with local exits.
- AZMDoc comments keep the contract beside the routine, which makes review much
  easier than reading an external manifest.
- `.asmi` files are a good fit for MON3. TECM8 can describe ROM routines that
  are not part of this source tree while still keeping strict checks on calls
  into them.

Costs and awkward cases:

- Routine boundaries are currently tied to the `@` label structure. That is
  useful and simple, but it becomes crude when code jumps across routine-like
  regions or deliberately transfers control outside the local block.
- Strict checking is good at revealing unstructured code, but it can also flag
  cases where the intended control flow is real and safe but not expressible
  with the current contract language.
- Stack symmetry checking is particularly valuable, but it needs a way to mark
  deliberate non-local stack/control-flow patterns without disabling discipline
  for an entire file.
- Report files should not be the normal workflow. Compiler diagnostics are the
  right default surface; report files are useful as advanced evidence only.

Useful requests for AZM:

- Add a documented way to suppress or annotate a specific routine-boundary or
  stack-effect false positive without turning off strict checking broadly.
- Improve diagnostics around "unknown routine boundary" and non-local jumps so
  they explain the exact boundary AZM inferred.
- Keep the diagnostics-first workflow prominent in the manual: normal users
  should run `azm --rc audit`, `--rc warn`, `--rc error`, or `--rc strict` and
  read compiler output.
- Keep `.asmi` examples close to the register-contract documentation, because
  external ROM APIs are a major use case for retro systems.

## Contract Generation

TECM8 has used contract generation/checking as a development aid rather than as
a replacement for review.

Practical advantages:

- Generated contracts are useful when first annotating an existing routine.
- Conservative generated updates reduce the risk of hand-written comments
  drifting from code.
- Running audit/warn/error/strict modes in sequence is a good workflow: audit
  while exploring, error/strict when stabilizing.

Costs and cautions:

- Generated contracts still need human review. A mechanically correct clobber
  list can document an undesirable routine shape instead of encouraging a
  cleaner boundary.
- Source comments are the persistent interface. Generated reports are evidence,
  not source of truth.

Useful requests for AZM:

- Make `--contracts` and `--fix` behavior very explicit in the manual: what is
  conservative, what is inferred, and what a developer must still review.
- Prefer examples that update source annotations or print diagnostics. Do not
  teach `.regcontracts.txt` report files as the ordinary path.

## `.include` And Shared Equates

TECM8 currently uses textual `.include` for source composition. This is simple
and works well for proof programs, but it has real scaling costs.

Practical advantages:

- `.include` is easy to reason about in early proof-driven development.
- Proof fixtures can include exactly the modules they exercise.
- Shared byte-free declaration files such as `src/tecm8-equates.asm` work well
  when included once by the top-level program or proof.

Costs and awkward cases:

- AZM correctly rejects duplicate symbols. A quick experiment confirmed that
  including the same `.equ` file twice produces a duplicate-symbol diagnostic.
  That is good for correctness, but it means shared declaration files cannot be
  safely included by every module unless AZM has an include-once/guard pattern.
- Because proof programs compose modules directly, each proof that uses shared
  constants must include the shared equates file before the modules. This is
  manageable, but it makes proof harnesses noisier.
- `.include` keeps every helper label in one namespace. Large source modules
  become harder to split safely because private implementation labels are not
  private.

Useful requests for AZM:

- Consider an `include once` mechanism, include guards, or a conventional
  pattern documented for byte-free equate/layout files.
- Provide a symbol-table artifact that shows resolved equates and aliases. That
  would let host tests inspect final values without brittle source regexes.
- Keep duplicate-symbol diagnostics strict; they catch real mistakes. The gap is
  not the diagnostic, but the lack of a low-friction shared-declaration pattern.

## `.import`

TECM8 has not yet converted production modules to `.import`, but the project is
an obvious candidate. The current editor image is built by a long `.include`
list in `src/main.asm`, and proof files repeat similar include blocks.

Expected advantages:

- Public `@` entries plus private implementation labels should shrink the
  accidental module surface.
- Importing routine modules would make the intended banked-tool boundaries more
  explicit.
- Label collision risk should drop as `editor-interaction.asm` is split into
  keymap, cursor, line-edit, block, prompt, render, and orchestration modules.

Risks and adoption cautions:

- `.import` should not be combined with layout, enum, or string-directive
  adoption in the same increment. TECM8 needs to learn one AZM feature at a
  time.
- Proof and Debug80 source maps must be checked carefully after the first
  import conversion. Debuggability matters as much as successful assembly.
- ASM80-lowered `.z80` output currently appears to be a constraint for `.import`
  workflows. TECM8 mostly wants `.asm`, but compatibility expectations need to
  be clear.

Useful requests for AZM:

- Document the exact public/private rules for imported files with examples
  using `@` routine labels and plain helper labels.
- Document how `.import` interacts with source maps, register contracts, and
  any ASM80-lowered output path.
- If possible, make the compiler diagnostic for unsupported output paths tell
  the user which imported file caused the limitation and what output mode works.

## Layout Types

TECM8 has not yet adopted `.type`, `.field`, `sizeof`, `offset`, or layout
casts, but the need is clear. The project has hand-maintained memory layouts
for source records, display descriptors, shell requests, navigation state, and
TM8 disk structures.

Expected advantages:

- A layout declaration would make record sizes and offsets assembler-checked
  instead of comment-maintained.
- The source-record length byte and 31-byte text field are a good first test:
  the layout is simple, important, and used everywhere.
- TM8 catalog/prefix/superblock records are also strong candidates because host
  TypeScript and Z80 code must agree on byte offsets.

Risks and adoption cautions:

- Runtime indexing still needs ordinary Z80 arithmetic. Layout casts should not
  make code look more static than it really is.
- The syntax must stay readable for assembly programmers. If field access
  obscures simple address arithmetic, it will not help.
- Types should start as declarations that emit no bytes. Data allocation and
  layout declaration should stay visibly separate unless AZM has a clear idiom.

Useful requests for AZM:

- Provide examples for fixed disk records and in-RAM structs, not only small
  toy examples.
- Show both assembler-time offset use and runtime indexed access patterns.
- Consider emitting type/layout metadata in a machine-readable artifact so host
  tools can verify TypeScript and Z80 layout agreement.

## `.enum`

TECM8 has many closed state families: shell command IDs, shell errors, editor
actions, prompt actions, pending block modes, display markers, and loader
errors.

Expected advantages:

- `.enum` could document that a group of constants is a closed set.
- Related names would be easier to scan and audit.
- Enums may help future generated docs or symbol exports.

Risks and adoption cautions:

- Not every constant family should become an enum. Memory addresses, masks,
  geometry, and protocol byte values often need domain names more than enum
  grouping.
- Large enum migrations create churn without changing behavior. TECM8 should
  start with one small family, probably prompt actions or pending block modes.

Useful requests for AZM:

- Document whether enum values are ordinary symbols, scoped symbols, or both.
- Show how to pin explicit values for ABI/protocol stability.
- Provide diagnostics for accidental duplicate values where the enum is meant
  to be unique, or document the intended behavior if duplicates are allowed.

## String Directives

TECM8 stores many NUL-terminated strings as `.db "text",0`. `.cstr` looks like
a low-risk readability win where the storage convention is genuinely a C-style
string.

Expected advantages:

- The declaration states the terminator policy directly.
- Status strings, command names, suffix strings, and path fragments become less
  visually noisy.

Risks and adoption cautions:

- Proof key streams, mixed byte sequences, fixed source records, and strings
  with deliberate embedded control bytes should remain `.db`.
- A broad string-directive sweep would produce churn without much design value.
  Adopt it one module at a time.

Useful requests for AZM:

- Document the exact emitted bytes for `.cstr`, `.pstr`, and `.istr`.
- Include examples showing when not to use string directives.
- If source-map or listing output marks string directive expansions clearly,
  document that behavior.

## `op`

TECM8 has not yet adopted `op`. It may be useful, but it is the AZM feature
with the clearest code-size risk for this project.

Expected advantages:

- A tiny repeated instruction idiom can be named without call/return overhead.
- Flag-sensitive compare/branch idioms might become easier to review.

Risks and adoption cautions:

- Ops expand inline, so they can increase binary size quickly.
- Anything long enough to deserve a register contract should probably be a
  routine, not an op.
- Ops can hide real flag/register effects if used like macros.

Useful requests for AZM:

- Document code-size tradeoffs directly: when an op is better than a routine and
  when it is worse.
- Provide listing output that makes expanded ops easy to identify.
- Consider diagnostics or listing annotations that show expansion counts and
  byte totals for ops.

## D8/D8M And Tooling Artifacts

Debug80 source maps are central to TECM8's proof workflow. They make emulator
proofs and size analysis possible.

Practical advantages:

- D8/D8M output lets TECM8 run machine-level proofs while still relating
  behavior back to source files.
- The new `npm run z80:size` command can compile the editor image and report
  the emitted address span, which is useful for bank-readiness work.

Costs and awkward cases:

- Source-map coverage from textual includes is non-exclusive. Include-line
  mappings can overlap, so per-file mapped byte totals are pressure signals, not
  ownership accounting.
- The size tool can report the true emitted image span, but it cannot yet give
  a clean resident-module byte ownership table.

Useful requests for AZM:

- Provide a source-map or listing mode that distinguishes byte ownership from
  include/call-site attribution.
- Emit enough symbol/range data to let tooling answer "which routine owns these
  bytes?" without reverse-engineering the source map.
- Keep native APIs stable for TypeScript tooling. TECM8 uses AZM as a library,
  not only as a command-line assembler.

## Current Recommendations For TECM8

1. Keep strict register contracts. They are worth the friction.
2. Keep source comments as the persistent contract surface; use generated
   reports only as advanced evidence.
3. Adopt one new AZM feature at a time and measure `npm run z80:size` before
   and after each increment.
4. Prefer `.include` for shared equates/layouts until AZM has an include-once
   or guard story.
5. Pilot `.import` on a small routine module only after the current equate
   centralization is committed and proof-green.
6. Use layout types before broad module imports if the next pain point is
   duplicated offsets rather than label visibility.
7. Treat `op` as a last-mile readability feature, not as the main refactoring
   mechanism.

## Evidence To Add Over Time

For every AZM feature adoption, add:

- commit hash
- files changed
- command run, usually `npm run z80:size` plus a targeted proof
- before/after byte count
- whether strict register contracts passed
- what became clearer
- what became more awkward
- whether the result suggests an AZM documentation change or product change
