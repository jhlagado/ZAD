# AZM Register-Care Feedback Loop

TECM8 should use AZM register-care as an active development tool for Z80 work,
not only as a proof-runner compile option. The goal is twofold:

- catch TECM8 register contract bugs earlier than emulator proofs do
- collect clear AZM edge cases that can be fed back into AZM development

## Routine Workflow

For any Z80-heavy change:

1. Write or update the emulator proof that exercises the behavior.
2. Run AZM register-care audit on the changed proof or module:

   ```text
   azm --rc audit --reg-report proofs/shell-commands/shell-commands-proof.asm
   ```

3. Inspect the generated register-care report before changing contracts.
4. If AZM's inferred contract is correct, update the handwritten `;!` block or
   let AZM annotate the source on a throwaway diff:

   ```text
   azm --contracts --rc audit proofs/shell-commands/shell-commands-proof.asm
   ```

5. If AZM reports something surprising, decide whether it is:
   - a real TECM8 register bug
   - a weak or missing `;!` contract in TECM8
   - an AZM inference/reporting edge case

6. Keep emulator proofs as the behavioral authority. Register-care is the
   calling-convention authority.

The existing TypeScript proof runners already call AZM with
`registerCare: 'audit'` and `registerCareProfile: 'mon3'`. Direct AZM runs are
still useful because `--reg-report`, `--reg-interface`, and `--contracts` expose
more of the analyzer's reasoning than a pass/fail proof runner.

## Safe Annotation Rules

Generated AZMDoc is useful, but it should not be accepted blindly.

- Review every generated `;!` change before committing.
- Keep public routine contracts precise and small.
- Prefer explicit register pairs such as `BC`, `DE`, and `HL` when the pair is
  used as a pair.
- Prefer individual flags such as `carry` and `zero` over broad `F`/`AF`
  contracts.
- Do not annotate ordinary branch labels. Promote a label to `@RoutineName:`
  only when it is a real callable routine boundary.
- Treat a mismatch between code and contract as a bug until proven otherwise.

## Feedback Template

When AZM finds something that looks wrong, reduce it while the context is still
fresh:

```text
Routine:
Source file:
Command:
Expected contract:
AZM inferred/reported:
Why TECM8 expected something different:
Minimal repro:
Outcome:
```

Useful TECM8 cases for AZM feedback include:

- routines returning status in `A` plus `carry` or `zero`
- helper calls that reuse `DE` as both pointer and scratch pair
- MON3 boundary calls described by external contracts
- routines that copy strings with `BC` counters and `HL`/`DE` pointers
- proof stubs that replace storage routines such as `LoadProjectConfig`
- derived-path routines where a register changes role mid-routine

## Completion Expectation

For a completed Z80 goal, the final verification notes should say which
register-care path was run:

```text
AZM register-care: proof runner audit passed
AZM report reviewed: yes/no
Contracts changed: yes/no
Feedback captured for AZM: yes/no
```

If a direct AZM report cannot be run, say why and keep the emulator proof result
separate from the register-care result.

## Current Feedback Candidates

### `ShellCopyStem` Stack Report

Initial direct CLI audit:

```text
azm --rc audit --reg-profile mon3 --reg-report \
  --source-root /Users/johnhardy/projects/TECM8 \
  -t bin -o proofs/shell-commands/azm-regcare.bin \
  proofs/shell-commands/shell-commands-proof.asm
```

AZM reports `ShellCopyStem` as:

```text
Routine: ShellCopyStem
  stack: unbalanced
```

The routine uses a local `PUSH HL` before comparing the current source pointer
with `ShellStemEnd`, then exits through either `ShellCopyStemNotEnd` or
`ShellCopyStemAtEnd`, both of which pop `HL` before continuing. The emulator
proof passes, so this is a good candidate to reduce before changing the code.

Possible outcomes:

- AZM is correctly seeing an edge path that leaves the stack unbalanced.
- AZM cannot prove the loop-local push/pop balance through the split branch.
- The routine should be rewritten to avoid stack-temporary comparison if the
  reduced repro shows the source is unnecessarily hard for the analyzer.
