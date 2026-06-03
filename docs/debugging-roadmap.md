# Debugging Roadmap

## Status

The debugger is a stretch goal. The first internal milestone on the path there
is a shell, virtual filesystem, and editor; the first customer-facing baseline
is the full edit/assemble/run loop. The source format and filesystem should be
designed so a debugger can be added later.

## Debugging Vision

The goal is a source-aware interactive debugging environment:

```text
project demo
asm
debug
```

At a breakpoint or step location, the debugger should show:

- current source line,
- nearby source context,
- registers,
- flags,
- current PC/SP,
- breakpoint/run/step controls.

## Memory Principle

The debugger does not need the editor in memory.

Workflow:

```text
edit
save
quit
asm
debug
```

`asm` assembles the configured project main file and writes derived
`/build/<main-stem>.bin` and `/build/<main-stem>.map` outputs. `debug` opens
those derived project outputs by default. The editor memory can be reused by
assembler, runner, or debugger overlays.

## Source Paging

The fixed line-record source format supports direct source paging.

With 32-byte records:

```text
512-byte sector = 16 source lines
```

If execution stops at line 183:

```text
sector = 183 / 16
row    = 183 % 16
```

The debugger can load one source sector and display more lines than fit on the
GLCD. It does not need the whole file in RAM.

## Map Format

The assembler should produce a compact binary map, not only a verbose listing.

The debugger needs records such as:

```text
address -> file id, line number
symbol  -> address
```

Possible address map record:

```text
address: 2 bytes
file id: 2 bytes
line:    2 bytes
flags:   1 byte
```

The exact format should be optimized later, but it must support fast lookup by
program counter.

## Object Code

For early debugger work, assume target object code is modest:

```text
8K object code budget
```

This is not a hard architectural limit, but it gives the first debugger a
realistic RAM target.

## Source Size Expectations

Assembly source is usually much larger than object code. A 32-byte source line
may emit 0-4 object bytes in typical code, except for data tables.

Practical source policy:

- Encourage source files around 4K to 8K.
- Encourage decomposition into smaller modules.
- Avoid very long source files for GLCD editing comfort.

## Debugger Overlay Strategy

Potential live memory needs:

```text
debugger code/overlay
object code
compact map or map cache
source sector cache
register/state area
UI scratch
stack
```

The debugger should page source and possibly map data from disk rather than
keeping everything resident.

## Future Commands

Possible debugger commands:

```text
step
next
run
break
clear
regs
mem
src
quit
```

The first implementation may be command-line driven. A more visual GLCD or
TMS9918 debugger view can come later.
