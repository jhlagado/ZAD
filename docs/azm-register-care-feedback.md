# AZM Register-Care Feedback Loop

TECM8 should use AZM register-care as an active development tool for Z80 work,
not only as a proof-runner compile option. The goal is twofold:

- catch TECM8 register contract bugs earlier than emulator proofs do
- collect clear AZM edge cases that can be fed back into AZM development

## Routine Workflow

For any Z80-heavy change:

1. Write or update the emulator proof that exercises the behavior.
2. Run AZM register-care strict mode on the changed proof or module:

   ```text
   azm --rc strict --reg-report \
     --interface src/mon3-storage.asmi \
     proofs/shell-commands/shell-commands-proof.asm
   ```

   Include every required `--interface` file for external monitor or storage
   calls used by the proof.

3. Inspect the generated register-care report before changing contracts. Direct
   AZM CLI runs can currently exit successfully while printing
   `AZMN_REGISTER_CARE` warnings; for TECM8, any such diagnostic means the
   strict check failed and must be fixed or captured as AZM feedback.

4. If AZM's inferred contract is correct, regenerate the source contracts and
   review the generated diff:

   ```text
   azm --contracts --rc strict proofs/shell-commands/shell-commands-proof.asm
   ```

   Hand-edit `;!` blocks only as an explicit exception when the generator cannot
   express the intended contract, and record why.

5. If AZM reports something surprising, decide whether it is:
   - a real TECM8 register bug
   - a weak or missing `;!` contract in TECM8
   - an AZM inference/reporting edge case

6. Keep emulator proofs as the behavioral authority. Register-care is the
   calling-convention authority.

The TypeScript proof runners call AZM with `registerCare: 'strict'` and
`registerCareProfile: 'mon3'`, and they fail on any returned diagnostic. Direct
AZM runs are still useful because `--reg-report`, `--reg-interface`, and
`--contracts` expose more of the analyzer's reasoning than a pass/fail proof
runner.

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
TECM8 examples:
Related TECM8 commit before fix:
Related TECM8 commit after fix:
Workaround cost:
Suggested AZM feature, hint, or ignore modifier:
Outcome:
```

Include all examples that are still readable and relevant. A minimal repro is
useful for AZM tests, but the original TECM8 code is useful for understanding
whether the workaround improved structure or forced awkward code. When the code
has already been fixed, include the fixing commit hash so the AZM team can pull
the project, inspect the before/after, and judge whether the contract system
encouraged good localization or exposed a gap that needs a future hint or ignore
mechanism.

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
AZM register-care: proof runner strict passed
AZM report reviewed: yes/no
Contracts changed: yes/no
Feedback captured for AZM: yes/no
```

If a direct AZM report cannot be run, say why and keep the emulator proof result
separate from the register-care result.

## Resolved Feedback Candidates

### `ShellCopyStem` Stack Report

Initial direct CLI audit:

```text
azm --rc strict --reg-profile mon3 --reg-report \
  --source-root /Users/johnhardy/projects/TECM8 \
  -t bin -o proofs/shell-commands/azm-strict.bin \
  proofs/shell-commands/shell-commands-proof.asm
```

AZM reports `ShellCopyStem` as:

```text
Routine: ShellCopyStem
  stack: unbalanced
```

The root cause was TECM8 structure, not an AZM bug. `ShellCopyStem` jumped to
shared error labels that sat after the next `@` routine boundary. AZM checks
stack balance within routine regions bounded by `@` entries, so those cross-
boundary exits made the routine harder to prove and also exposed spaghetti-like
control flow.

The fix was to localize the routine:

- promote called helpers such as `ShellLoadProjectMain` to explicit `@` routine
  entries
- keep error exits inside the routine region that jumps to them, or avoid
  shared cross-boundary exits
- make post-call live registers explicit, such as initializing `BC` after MON3
  calls before saving/restoring it

After the rewrite, strict register-care succeeds for the current proof entry
points. This is the preferred outcome: use AZM's crude-but-useful `@` boundary
discipline to improve TECM8 structure before treating a report as an AZM issue.
