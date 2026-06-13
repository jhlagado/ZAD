# AZM Practical Feedback

This document records practical conclusions from using AZM on TECM8. It is
written for two audiences:

- TECM8 contributors deciding which AZM features to adopt next.
- AZM maintainers looking for concrete feedback from a real Z80 application.

It should stay evidence-based. When TECM8 adopts a feature, add the commit,
proof command, size result, and any discomfort or bug found during the work.

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
