# AZM Adoption Opportunities

This document records TECM8-specific opportunities to use native AZM language
features more deliberately. It complements the live roadmap and the code-quality
execution plan: the roadmap names the direction, while this document explains
why the features are useful and where to try them first.

## Current State

TECM8 already uses a strong part of AZM: public routine entries use `@` labels
and most source modules carry AZMDoc `;!` register contracts. Build and proof
tooling compiles with strict register-care settings and the MON3 profile.

The codebase does not yet use several other native AZM features:

- `.import` module loading and public/private label visibility.
- `.type`, `.field`, `.typealias`, `sizeof`, `offset`, or layout casts.
- `.enum` grouped constants.
- `op` inline instruction idioms.
- `.cstr`, `.pstr`, or `.istr` string directives.

The installed assembler dependency is `@jhlagado/azm@0.2.10`, which is new
enough for the first-release `.import` feature. TECM8 proof scripts emit native
bin and D8M artifacts, so `.import` fits the current local toolchain. The main
caution is ASM80-lowered `.z80` output: AZM currently rejects `.import` source
units for that output path.

## Adoption Guardrail

Adopt only one new AZM feature per increment of work. Each increment should
isolate one feature, one candidate area, and one verification path. The goal is
to learn whether that feature improves TECM8 code quality in practice before it
spreads through the source tree.

This applies even when several features look clearly beneficial. Do not combine
an `.import` conversion with a layout-type conversion, enum migration, string
directive cleanup, or op introduction in the same code increment. Keeping each
change separate makes the effect measurable and makes rollback straightforward
if a feature does not fit the codebase as well as expected.

## Recommended Adoption Order

### 1. Use `.import` For Routine Modules

`src/main.asm` currently composes the editor image with textual `.include`
directives. That keeps every helper label in one global namespace and makes
large modules harder to treat as real units.

Use `.import` for source files that behave like routine modules. Public entries
remain `@Name:` and are callable from other modules as `Name`; plain labels
inside the imported file become private implementation details.

Keep `.include` for:

- shared equates and layout declarations,
- enum declarations,
- op declarations,
- proof fixtures that intentionally need textual insertion,
- compatibility source that should remain a single translation unit.

First candidates:

- Pilot one leaf-like module or proof path before converting `src/main.asm`.
- Convert the main editor include list only after the pilot proves Debug80 D8M
  source mapping and strict register contracts still behave as expected.
- Avoid `.import` in any workflow that still needs ASM80-compatible lowered
  `.z80` output.

Expected value:

- Smaller public surface per module.
- Fewer accidental label collisions.
- Better pressure toward real module boundaries before banked tools arrive.

### 2. Introduce Layout Types For Memory Records

TECM8 has many hand-maintained memory layouts: display row descriptors, editor
source records, shell request blocks, navigation state, and TM8 on-disk
structures. These are currently represented with `.equ`, `.db`, `.dw`, and
`.ds` blocks. That works, but it leaves field offsets and record sizes spread
through comments and repeated arithmetic.

Use `.type` and derived constants where the memory shape has fields:

```asm
DisplayRowDescriptor .type
marker               .field byte
textPtr              .field word
                     .endtype

DISPLAY_ROW_DESCRIPTOR_SIZE .equ sizeof(DisplayRowDescriptor)
DISPLAY_ROW_MARKER          .equ offset(DisplayRowDescriptor, marker)
DISPLAY_ROW_TEXT_PTR        .equ offset(DisplayRowDescriptor, textPtr)
```

First candidates:

- `DisplayRowDescriptor`: one marker byte plus one text pointer.
- `EditorSourceRecord`: length/metadata byte plus 31 text bytes.
- `ShellDispatch` or shell request blocks.
- TM8 superblock, prefix, catalog, and allocation-entry layouts.

Expected value:

- Offset and size changes become assembler-checked.
- Record access code can use names derived from one declaration.
- Docs and code can describe the same structure with the same names.

Use layout casts only where the index is an assembler-time constant. Runtime
indexing should remain ordinary Z80 address arithmetic.

### 3. Use `.enum` For Grouped State Values

Several constant families are really enumerations:

- `SHELL_CMD_*`, `SHELL_ERR_*`, `SHELL_PROGRAM_*`, `SHELL_PROJECT_*`.
- `TECM8_EDITOR_ACTION_*`.
- editor prompt actions and prompt results.
- pending block modes.
- `EDITOR_LOAD_ERR_*`.
- `TECM8_DISPLAY_MARKER_*`.

Use `.enum` when values are a closed set and call sites benefit from grouped
names. Do not churn every constant just because the syntax exists; start with a
small family whose values are passed through several routines.

Expected value:

- Clearer grouping.
- Fewer unrelated constants sharing a flat namespace.
- Better future docs for shell/editor state machines.

### 4. Use String Directives For Explicit String Storage

TECM8 stores many NUL-terminated strings as `.db "text",0`. `.cstr "text"`
emits the same storage with a clearer contract.

Good candidates:

- shell command names and path suffixes,
- editor status and error strings,
- proof strings that are meant to be NUL-terminated.

Keep `.db` for mixed byte streams, key scripts, fixed-width records, and data
where the terminator policy is not a C string.

Expected value:

- Low-risk readability improvement.
- The data declaration states the string convention directly.

### 5. Use `op` Only For Tiny Repeated Idioms

Ops expand inline at each call site. They are useful when a short instruction
idiom needs a name and call overhead would be wasteful. They are risky when used
as general macros because TECM8 is close to its current 16K bank limit.

Good candidates:

- 1-3 instruction register idioms.
- compare-and-branch sequences whose flag meaning is otherwise obscure.
- proof-only helper idioms.

Avoid ops for:

- longer routines,
- logic that should have a `;!` contract,
- code repeated often enough that a subroutine is smaller,
- anything that hides meaningful register or flag effects.

Expected value:

- More readable call sites for small Z80 instruction gaps.
- No call/ret overhead for genuinely tiny idioms.

Acceptance rule:

- Measure binary size before and after any op adoption.
- Prefer a subroutine when the op increases code size or deserves a contract.

## Concrete Pilot Sequence

Each numbered item below should be its own increment unless there is a specific
reason to do otherwise. Do not batch multiple AZM feature adoptions into one
refactor.

1. Add shared AZM declaration files only where they emit no bytes:
   `tecm8-equates.asm`, later `tecm8-layouts.asm`, and possibly
   `tecm8-ops.asm`.
2. Convert one low-risk data shape to `.type` and derived `sizeof` / `offset`
   constants.
3. Convert one grouped constant family to `.enum`.
4. Convert obvious NUL strings to `.cstr` in one module.
5. Pilot `.import` on a leaf module or proof fixture.
6. Measure `npm run z80:size` and run the targeted proof for each pilot.
7. Promote the pattern to the code-quality execution plan only after the pilot
   keeps strict register contracts and Debug80 source maps healthy.

## Not In Scope

- Broad assembler syntax churn for style alone.
- Bank switching or overlay implementation.
- Rewriting all constants into enums in one pass.
- Macro-style op libraries.
- Any change that requires dropping strict register contracts.
