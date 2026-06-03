# TEC-Side Shell Command Contract

This contract defines how the future TECM8 shell reads project metadata and
turns short commands such as `edit`, `asm`, and `run` into concrete file
operations. The project file is deliberately small: it records only the state
that is not obvious from convention.

## Active Volume And Project Config

The shell operates on one active TM8 volume at a time. A project volume is
configured when it contains:

```text
/.tecm8/project
```

That file is ASCII `key=value` text. Lines end with LF. A final LF is expected,
but the TEC-side reader should accept a final non-empty line without one. Blank
lines are only valid as the final LF terminator.

The default config created by the host tool is:

```text
tm8project=1
main=/src/main.asm
```

Required keys:

```text
tm8project
main
```

`tm8project` must be `1`. The shell should reject duplicate keys, missing
required keys, empty values for required keys, malformed lines without `=`, and
paths that fail the TM8 virtual filesystem path rules.

Unknown keys are rejected. A future format can add a new version marker rather
than making shell v1 carry preservation logic for fields it does not use.

## Derived Project Paths

The main source file is the durable project entry point. Output and map paths
are derived from the main source filename instead of being stored.

Derivation rules:

1. Take the local filename from `main`.
2. Remove the final extension, if present.
3. Use that stem under `/build`.
4. Append `.bin` for the runnable output and `.map` for the map/debug sidecar.

Examples:

```text
main=/src/main.asm       -> output=/build/main.bin, map=/build/main.map
main=/src/demo.asm       -> output=/build/demo.bin, map=/build/demo.map
main=/src/monitor.z80    -> output=/build/monitor.bin, map=/build/monitor.map
```

This is intentionally less flexible than a general build system. If a project
needs a different mainline name, it changes `main`; the rest follows by
convention.

## Path And Name Defaults

Stored paths are absolute TM8 paths. They use the same filename policy as the
volume catalog: lowercase letters, numbers, underscore, and hyphen in path
segments, with an extension separated by `.`.

When a user types a source filename without an extension, shell source commands
append `.asm`.

Relative command arguments are resolved against the shell current prefix, the
same state changed by `cd` and reported by `pwd`. They are not resolved against
the main file's prefix unless the shell current prefix happens to be there.

Examples when the shell current prefix is `/src`:

```text
edit main       -> /src/main.asm
edit draw       -> /src/draw.asm
edit /lib/draw  -> /lib/draw.asm
```

If the user supplies an extension, the shell preserves it. `.ASM` is the
preferred user-facing extension in prose, but stored TM8 paths are lowercase,
so the default physical path is `.asm`. `.z80` remains a compatibility path for
imported ASM80-era projects.

## Short Commands

The short command bindings are fixed in shell v1:

```text
edit -> main
asm  -> main
run  -> derived output
```

They are not stored in `/.tecm8/project`. This keeps the Z80 parser and project
state small. Future configuration screens can still change `main`, but the
command names themselves remain part of the shell.

## Command Resolution

Shell commands are resolved in this order:

1. Parse `/.tecm8/project`.
2. Resolve any user argument to an absolute TM8 path.
3. If no argument is present, use the command's project default.
4. Execute the tool against that resolved path.

For the default config, no-argument commands resolve to:

```text
edit -> main   -> /src/main.asm
asm  -> main   -> /src/main.asm
run  -> output -> /build/main.bin
```

The map path is not directly targeted by a short command in shell v1. `asm`
uses the derived map path as the default map/debug sidecar output when the
assembler reaches that phase.

## `edit`

`edit` opens one source file and returns to the shell when the editor exits.

No argument:

```text
edit
```

The shell opens the file named by `main`.

With a file argument:

```text
edit draw
edit /src/draw.asm
```

The shell resolves the argument to a TM8 path, appending `.asm` when no
extension is present, and opens that file. If the file does not exist, the
editor may create it after an explicit save; the shell should not need a
separate `new` command for ordinary source editing. Editing a named file does
not change `main`.

## `asm`

`asm` assembles the project mainline by default.

No argument:

```text
asm
```

The shell assembles the file named by `main`.

With a file argument:

```text
asm test
asm /src/test.asm
```

The shell assembles that one-off target and does not change `main`. One-off
assembly derives output and map names from the argument stem, not from the
project main stem, so `asm test` writes `/build/test.bin` and `/build/test.map`.
The preferred everyday workflow remains no-argument `asm`, because the project
main file is the durable build entry point.

Assembler defaults:

```text
source -> resolved command target
output -> derived /build/<source-stem>.bin
map    -> derived /build/<source-stem>.map
```

If assembly succeeds, `run` continues to use the derived project output.

## `run`

`run` executes the derived project output by default.

No argument:

```text
run
```

The shell runs `/build/<main-stem>.bin`, derived from `main`.

With a file argument:

```text
run /build/test.bin
```

The shell runs that one-off target and does not change project config. The
no-argument form remains the primary workflow.

## Errors

The shell should report short, actionable errors and return to the prompt:

```text
no project config
bad project config
missing main
bad path
file not found
assemble failed
run failed
```

Config parse errors should not launch tools. A malformed `/.tecm8/project`
means the shell cannot know which file is authoritative.

## Persistence Rules

Shell v1 writes `/.tecm8/project` only when project state changes:

- A future project configuration screen may update `main`.
- `edit`, `asm`, and `run` do not change config merely because they ran.

When rewriting the config, the shell should keep the file ASCII, keep required
keys present, reject unknown keys, and write a final LF.

## Host Tool Relationship

The host `fs project-*` commands are the current reference writer and validator
for this file:

```text
fs project-init VOLUME.TM8 [/src/main.asm]
fs project-info VOLUME.TM8
fs project-set-main VOLUME.TM8 /path/file
```

The TEC-side shell should match the same stored format rather than inventing a
separate runtime-only project state.
