# Z80 Space-Saving Optimization Opportunities

This document records TECM8-specific opportunities to reduce resident Z80 code
size without turning the codebase into a hard-to-review collection of clever
tricks. It complements the code-quality execution plan: that plan names the
quality sequence, while this document explains where compact table-driven logic,
shared tails, and related 1980s-style space-saving techniques look worth trying.

The intent is not to force every branch tree into a jump table. On Z80, a small
`CP` / `JR` chain can be smaller than the scaffold needed for an indirect
dispatch table. The useful question is local and measurable: does this change
reduce bytes while keeping the behavior and contracts easier to understand?

## Baseline And Guardrails

The current source-size check puts the live editor image at 15,922 bytes emitted
at `4000h..7E32h`, leaving 462 bytes inside the current 16K bank. Treat that
as a snapshot only. Every space-saving increment should record a fresh
before/after result from:

```text
npm run z80:size
```

Guardrails:

- Try only one space-saving technique per increment. Do not combine a jump-table
  experiment, tail sharing, table-driven validation, and unrelated cleanup in
  the same change.
- Prefer local, reversible transformations. The goal is to learn which
  techniques work well in this codebase, not to commit to a global style.
- Keep AZMDoc `;!` contracts accurate for any new public helper.
- Preserve current user-facing behavior and compact status strings unless the
  changed wording is explicitly part of the increment.
- Reject any optimization that saves only a few bytes by making a key editor or
  storage path substantially harder to audit.
- Table data should be named and commented well enough that the table is easier
  to verify than the branch tree it replaces.

## Recommended Pilot Order

### 1. Table-Drive Editor Load Error Text

Candidate: `EditorNavErrorTextForCode` in `src/editor-navigation.asm`.

The current logic maps a compact editor load error code to a status string with
a chain of comparisons. This is a strong first table candidate because the
input is a small closed error-code family and the output is data: a pointer to a
message string.

Recommended shape:

- Use either a sparse `(code, textPtr)` table with a sentinel, or a dense pointer
  table for the `0x30..0x39` range if the value range stays stable.
- Keep the default "unknown error" string path explicit.
- Measure size before choosing sparse versus dense. Dense tables are compact
  only when the code range is actually dense enough.

Expected value: likely worthwhile byte reduction and better readability, with
low behavioral risk.

### 2. Share Obvious Editor Render Tails

Candidate: repeated editor key-loop tails in `src/editor-interaction.asm`.

Several handlers end with the same render-and-return-to-key-loop sequence, for
example:

```asm
CALL EditorKeyRenderDirty
RET C
JP EditorKeyLoop
```

and similar block-selection marker render tails. These are good common-tail
candidates because the shared ending is already visually identical and the
control-flow destination is the same.

Recommended shape:

- Introduce one clearly named local tail helper, such as
  `EditorKeyRenderDirtyAndLoop`.
- Convert only the exact repeated tail first.
- Avoid sharing very small endings such as `XOR A` / `RET`; those usually break
  even or lose once the jump to the shared tail is counted.

Expected value: modest but low-risk byte savings, and less repeated exit
plumbing in the largest editor module.

### 3. Share Navigation Commit/Render Tails

Candidate: repeated commit-and-render endings in `src/editor-navigation.asm`.

Several navigation paths commit a pending page, reset viewport state, and render
the current buffer with nearly the same ending. A helper such as
`EditorNavCommitPendingAndRender` may save bytes while making the success path
more obvious.

Recommended shape:

- Extract only when the register and flag contracts are exactly the same at all
  call sites.
- Keep error paths local if they carry distinct status behavior.
- Add a focused navigation proof or smoke command to the increment.

Expected value: moderate readability improvement and small byte reduction.

### 4. Replace Repeated Shell Error Tails With Existing Labels

Candidate: inline `SHELL_ERR_SYNTAX` and `SHELL_ERR_LONG` returns in
`src/shell-resolver.asm`.

The shell already has shared error labels for syntax and long-command errors,
but some sites still inline the same load-error-and-return sequence.

Recommended shape:

- Replace exact inline tails with `JP ShellSyntaxErr` or `JP ShellLongErr`.
- Do not introduce a general error-dispatch abstraction for two or three cases.

Expected value: small byte savings, but very low risk and easy to verify.

### 5. Table-Drive TM8 Superblock Validation

Candidates:

- `EditorLoadReadSuperblock` in `src/editor-storage-loader.asm`.
- `ProjectLoadReadSuperblock` in `src/project-config-loader.asm`.

Both paths validate fixed bytes in the TM8 superblock with repeated offset/value
checks. That is data-shaped logic: a table of `(offset, expectedByte)` entries
plus a loop should be smaller and easier to compare against the on-disk format.

Recommended shape:

- Start with one loader, then consider sharing only after the first version is
  proof-green.
- Use a sentinel-terminated table.
- Preserve the exact error code returned by each loader unless a deliberate
  mapping layer is added.

Expected value: good compactness and maintainability win, with medium risk
because storage bootstrapping code must remain very predictable.

### 6. Normalize Editor Modified Commands Before Dispatch

Candidate: `EditorModifiedCommandFromKey` in `src/editor-keymap.asm`.

The Ctrl-modified command decoder has uppercase/lowercase duplication and a few
special ambiguous inputs. This may be smaller as normalization plus a compact
lookup table.

Recommended shape:

- Preserve the current Ctrl-C and ArrowUp ambiguity behavior exactly.
- Normalize alphabetic input once, then dispatch from a small table or ordered
  compare set.
- Treat this as a keymap-boundary improvement as much as a byte-saving
  experiment.

Expected value: moderate readability improvement. Byte savings are plausible
but must be measured because small Z80 dispatch tables can be deceptive.

### 7. Review GLCD Dirty-Row Masking

Candidate: repeated dirty-row byte/mask logic in `src/glcd-tile.asm`.

Several paths compute the dirty byte and bit mask for a tile row. A helper or
small table may reduce repeated arithmetic.

Recommended shape:

- Prototype only if the repeated sequences are still identical after re-reading
  the current file.
- Count `CALL` / `RET` overhead honestly. A helper can lose if each call site
  needs extra register setup.
- Keep fast display paths understandable; this is not the first pilot.

Expected value: possible compactness win, but lower priority than error mapping,
tail sharing, and superblock validation.

## Jump Tables: Use Sparingly

Jump tables are attractive when a branch tree is large, dense, and stable. They
are not automatically smaller on Z80. A table-driven dispatcher usually needs
range normalization, pointer lookup, and an indirect jump scaffold; for a small
set of commands, the table can cost more than the original compares.

Good jump-table candidates:

- Dense command/action families with at least several entries.
- Dispatch code that is already isolated behind a keymap or shell resolver
  boundary.
- Cases where table data replaces both code size and scattered policy.

Poor jump-table candidates:

- Two or three command branches.
- Branches with very different setup requirements.
- Code that has not yet been moved to a clear ownership boundary.
- Paths where the current compare order documents important precedence.

For the current codebase, table-driven data lookup is more compelling than
classic indirect jump dispatch in the first increments.

## Common Tails: Use When The Tail Is Real

Common tails are worth using when several routines genuinely end with the same
multi-instruction sequence and have the same flag/register expectations. They
are not worth using for one- or two-instruction returns.

Good candidates:

- Editor render-and-loop endings.
- Navigation commit/reset/render endings.
- Existing shell syntax/long error labels.

Avoid:

- Shared `RET`-only endings.
- Shared `XOR A` / `RET` or `SCF` / `RET` endings unless a natural fallthrough
  already exists.
- Tails that look similar but carry different flag meanings.

Acceptance rule: the shared tail should make the code easier to read even before
the byte savings are counted.

## Techniques To Avoid For Now

- Broad jump-table conversion across the editor before keymap extraction.
- Macro-style `op` libraries for compactness. Ops expand inline and can grow the
  binary if used casually.
- Generic error formatting that makes current short status strings harder to
  recognize.
- Replacing clear one-off branches with tiny tables just for style.
- Combining compactness work with AZM feature adoption in the same increment.

## Verification Policy

Each pilot should record:

- fresh `npm run z80:size` before and after,
- targeted proof command or Debug80 smoke command,
- exact files and labels changed,
- byte delta,
- whether readability improved enough to keep the pattern.

For doc-only planning changes, `git diff --check` is sufficient. For any Z80
change, also run the most relevant proof path and consider `npm run check` if
the touched path participates in the live editor image.
