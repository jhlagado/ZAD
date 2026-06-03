# AZM Register-Care Feedback Loop

TECM8 should use AZM register-care as an active development tool for Z80 work,
not only as a proof-runner compile option. The goal is twofold:

- catch TECM8 register contract bugs earlier than emulator proofs do
- collect clear AZM edge cases that can be fed back into AZM development

## Routine Workflow

For any Z80-heavy change:

1. Write or update the emulator proof that exercises the behavior.
2. Run AZM register-contract diagnostics on the changed proof or module:

   ```text
   node --experimental-strip-types tools/run-shell-commands-proof.ts
   ```

   The TypeScript proof runners use the AZM API so they do not write
   `.regcontracts.txt` audit files into the tree.

3. If the strict proof fails, inspect the returned diagnostics before changing
   contracts. Direct AZM CLI runs are still useful for one-off AZM development
   diagnostics. In ordinary use, run AZM with `--rc audit`, `--rc warn`,
   `--rc error`, or `--rc strict` and read the warnings or errors printed by the
   compiler. Do not enable `--reg-report` as part of normal TECM8 proof work.
   For TECM8, any strict `AZMN_REGISTER_CONTRACTS` diagnostic means the strict
   check failed and must be fixed or captured as AZM feedback.

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

The TypeScript proof runners call AZM with `registerContracts: 'strict'` and
`registerContractsProfile: 'mon3'`, and they fail on any returned diagnostic.
Direct AZM runs are still useful because `--reg-interface` and `--contracts`
expose more of the analyzer's reasoning than a pass/fail proof runner.

Register contracts are a diagnostics-first development feature. These are the
normal CLI shapes:

```sh
azm --rc audit program.asm
azm --contracts --rc audit program.asm
azm --rc error program.asm
azm --rc strict program.asm
```

Use the modes this way:

- `audit`: analyze contracts without failing the build; useful while editing.
- `warn`: print warnings but still build.
- `error`: fail on proven register contract conflicts.
- `strict`: fail on anything AZM cannot prove safe, including unknown routine
  boundaries and stack effects.

The important persistent surfaces are:

- AZMDoc contract comments in source, such as `;! in A`, `;! out HL`, and
  `;! clobbers BC`
- `.asmi` files for external routines or monitor/system APIs
- compiler diagnostics from `--rc warn`, `--rc error`, and `--rc strict`
- `--contracts` and `--fix` for source annotation and conservative contract
  updates

AZM can also write a text report with `--reg-report`, producing
`program.regcontracts.txt`. This is mainly for debugging, CI evidence, or large
audit sessions. It is not required for normal development and should not be
checked into source control. Avoid default examples such as
`azm --rc audit --reg-report program.asm`; use `azm --rc audit program.asm`
instead.

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
AZM diagnostics reviewed: yes/no
Contracts changed: yes/no
Feedback captured for AZM: yes/no
```

If direct AZM diagnostics cannot be run, say why and keep the emulator proof
result separate from the register-care result.

## Resolved Feedback Candidates

### `ShellCopyStem` Stack Report

Initial direct CLI audit:

```text
azm --rc strict --reg-profile mon3 \
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

### Strict Stack Effect Regression After AZM Register Contracts Rename

Routine: shell command proof and all direct callees
Source file: `proofs/shell-commands/shell-commands-proof.asm`,
`src/shell-commands.asm`
Command:

```text
node --experimental-strip-types tools/run-shell-commands-proof.ts
```

Expected contract: routines with ordinary `CALL`/`RET` structure and no unmatched
`PUSH`/`POP` should remain provable under strict register contracts when their
callee summaries are known.

AZM inferred/reported: current AZM at `/Users/johnhardy/projects/AZM`, commit
`9c8e8fc` (`Rename register care to register contracts`), reports
`AZMN_REGISTER_CONTRACTS` for the proof entry and nearly every routine in the
shell command resolver:

```text
Register contracts cannot prove stack discipline for Start: stack effect is unknown.
Register contracts cannot prove stack discipline for ResolveShellEditRequest: stack effect is unknown.
Register contracts cannot prove stack discipline for ResolveShellRunRequest: stack effect is unknown.
Register contracts cannot prove stack discipline for ResolveShellCommand: stack effect is unknown.
```

Why TECM8 expected something different: the same shell proof structure had
previously passed strict after the earlier `ShellCopyStem` localization work.
The current failure also reproduces against the previous TECM8 commit before the
edit-request change, so it is not caused by the new editor request resolver.

Minimal repro: current TECM8 shell proof is the useful repro because it contains
ordinary nested local calls, proof stubs, and an existing strict-clean history.

TECM8 examples:

- `@Start` calls proof assertion helpers and halts.
- `@AssertEditRequest` calls `ResolveShellEditRequest` and compares a mode byte
  plus source path.
- `@ResolveShellEditRequest` calls `ShellSkipSpaces`, `ShellMatchCommand`, and
  `ResolveShellCommand`, then returns normally.
- Existing `@ResolveShellRunRequest` now reports the same unknown stack effect,
  which shows the failure is broader than the new edit API.

Related TECM8 commit before fix: `e99fbe0c47990eaafc7e86323c4f60914c7f28e3`
(`Resolve shell run launch requests`)
Related TECM8 commit after fix: pending TECM8 commit for the edit request layer.
Related AZM fix: `fb123b42fcb59ed6e22768fa390d1738853a34a4`.
Workaround cost: TECM8 could temporarily run the behavioral proof with AZM
`error` mode, but that weakened the strict stack-discipline gate and was only
useful as a diagnostic fallback.
Suggested AZM feature, hint, or ignore modifier: provide a source-level way to
declare or infer that a direct callee is stack-balanced, or adjust strict
fixed-point inference so known internal `CALL`/terminal `RET` paths do not keep
propagating `hasUnknownStackEffect` once callee summaries have stabilized.
Outcome: resolved upstream in AZM; strict TECM8 shell proof passes again with
AZM `fb123b42`.
