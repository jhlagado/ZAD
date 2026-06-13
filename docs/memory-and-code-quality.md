# Memory and Code Quality Manifest

TECM8 is being built for a small Z80 system, not for a modern workstation. The
early implementation should stay clear and proof-driven, but the project should
always keep future compactness in mind. Code size and memory management are
product constraints, not afterthoughts.

## Baseline Machine

The initial target is a classic 64K Z80 address space with MON3 present. The
working assumption is:

```text
64K address space
16K MON3/TECM8 fixed ROM mapped at C000h-FFFFh
16K expansion window at 8000h-BFFFh
32K expansion potential, exposed as two 16K banks
24K realistic working RAM target
```

The nominal RAM space may be larger, but TECM8 should not assume all of it is
available for source editing, assembly, and shell state. Display systems and
other hardware will consume RAM. A GLCD bitmap, a TMS9918-style VDU buffer, or
other graphics work areas can make the practical programming workspace feel
closer to 24K than the raw address map suggests.

Mass storage through SD/FAT32 and TM8 volumes helps by making scratch files,
project files, and exported artifacts practical. The preferred TECM8 direction
is still ROM-based rather than CP/M-style disk-resident transient programs:
editor, assembler, runner, and debugger code should live in fixed or banked ROM
where possible, with disk used for user projects, backups, build output, maps,
and optional large data.

## TEC-1G Memory Map

TECM8 should use the standard TEC-1G/MON3 memory map as documented by the
TEC-1G platform work and modeled in Debug80:

```text
0000h-00FFh  RAM, RST vectors
0100h-07FFh  RAM
0800h-0FFFh  monitor RAM
1000h-3FFFh  RAM
4000h-7FFFh  user RAM, protect-capable
8000h-BFFFh  16K expansion window, banked
C000h-FFFFh  16K ROM, MON3
```

Debug80 models MON3 as a 16K ROM loaded at C000h. The bundled Debug80 MON3
image and the current MON3 release images used by this project are 16,384
bytes, matching the C000h-FFFFh range. TECM8 should therefore treat MON3 as a
16K high ROM service layer, not an 8K monitor occupying the bottom of memory.

Shadow mode maps MON3 ROM C000h-C7FFh into 0000h-07FFh for legacy monitor
startup and vectors. This is a 2K shadow window, and it is the likely source of
confusion with older low-monitor layouts. With shadow disabled, 0000h-07FFh is
RAM.

## MON3 Low-RAM Use

The raw memory map above is only the hardware view. MON3 itself makes heavy use
of low RAM below the conventional `4000h` user-program start. TECM8 should treat
these areas as MON3-owned or MON3-volatile while it is using MON3 services:

```text
0000h-00FFh  RAM copy of MON3 low vectors and restart stubs
0100h-07FFh  MON3 FAT/PATA/SD storage workspace
0600h-07FFh  DISK_BUFF, 512-byte sector buffer inside that workspace
0800h-087Fh  MON3 stack
0880h-089Fh  core monitor variables and device state
08A0h-08FFh  monitor scratch, menu, parameter, and copy state
0900h-0967h  data view, breakpoint, and disassembler scratch overlap
0A00h-17FFh  practical MON3 GLCD/video workspace
1800h-3FFFh  first plausible low-RAM TECM8 workspace, subject to audit
4000h-7FFFh  conventional protected user-program RAM
```

The storage allocation is larger than the visible `DISK_BUFF`. MON3's FAT/PATA
package allocates downward from `0800h`: FAT geometry, volume label, file
control block, SD command frame, root-file cluster list, directory menu data,
and the 512-byte sector buffer together cover roughly `0100h-07FFh`. Removing
PATA from a future BIOS should save ROM and simplify code paths, but SD/FAT32
will still need at least a sector buffer and a compact file-control workspace.

MON3 starts by setting `SP` to `0880h`, forcing shadow ROM off, and copying the
first 256 bytes of ROM from `C000h-C0FFh` down to `0000h-00FFh`. That leaves
RST vectors and low restart stubs callable from RAM after the low ROM shadow is
disabled.

The GLCD range is best treated as `0A00h-17FFh`: `0E00h` bytes, or 3584 bytes
3.5 KiB. The current MON3 GLCD library uses:

```text
0A00h-0DFFh  GBUF, 1024-byte full 128x64 1bpp graphics buffer
0E00h-0E19h  line drawing, cursor, viewport, and terminal state
1000h-13BFh  SBUF, 960-byte terminal scroll buffer
13C0h-17BFh  TGBUF, 1024-byte terminal graphics buffer
```

This is defensible for a general graphics library: a 128x64 bitmap alone costs
1024 bytes, and MON3 keeps extra terminal buffers so it can scroll text, redraw
cursor state, and plot a prepared buffer to the ST7920 GLCD. It is also a large
cost for TECM8, because it removes about 3.5 KiB from the low-RAM working set
before editor, shell, assembler, or project state are considered.

TECM8 should therefore plan for an explicit video workspace rather than hard
coding GLCD assumptions into unrelated code. A future TMS9918-style VDU layer
may not need the same CPU RAM framebuffer, because the TMS has its own video
RAM, but it will still need BIOS state, staging buffers, and text/dirty-region
helpers. The GLCD and TMS paths should share a high-level display contract
where practical while allowing different backing storage underneath.

The TEC-1G system control latch at port FFh controls the relevant memory
features:

```text
bit 0  ~SHADOW, active low; 0 maps C000h-C7FFh into 0000h-07FFh
bit 1  PROTECT; protects writes to 4000h-7FFFh
bit 2  EXPAND; enables the banked 8000h-BFFFh expansion window
bit 3  E_A14; selects one of two current 16K expansion banks
bits 3-6 future memory expansion bank field in Debug80
bit 7  CAPSLOCK
```

The expansion window is the natural place to think about editor, assembler,
runner, debugger, help text, and table overlays. It exposes 16K at a time, and
the currently modeled bank select gives two 16K banks for 32K of expansion
content. Together with the fixed 16K ROM, the practical first ROM budget is
therefore 48K total, with only 32K addressable at one time.

Some less central MON3 utilities may eventually be candidates for relocation or
replacement if TECM8 controls a modified ROM image and needs that space. The
initial target is not to discard MON3, but to keep its useful BIOS-like service
surface while replacing optional monitor UI, PATA support, and unsuitable GLCD
terminal assumptions with TECM8 resident shell and display/storage services.
The first implementation should use MON3 services rather than duplicating
working hardware drivers.

Further expansion memory may exist later, but the first design should prove
useful inside the classic machine model before depending on it.

The long-term split starts with MON3 compatibility, identifies hardware
services TECM8 should wrap, and only later considers shaving monitor/PATA
components from a modified ROM to free resident space for TECM8 support around
banked tools. The callable service surface is tracked in
[TECM8 BIOS API Draft](tecm8-bios-api.md), while ROM-saving analysis lives in
[MON3 Decomposition Plan](mon3/decomposition.md).

## Resident Versus Overlay Code

The system should separate always-resident code from banked tool code. TECM8's
shell is not a disposable utility; it is the operating-system personality that
replaces the classic monitor as the normal front door of the TEC-1G. The editor,
assembler, runner, and debugger are separate projects launched by that shell.

Likely resident code:

```text
boot-to-shell entry
shell prompt and command loop
line input and command dispatch
project config reader
current volume/path state
basic error/status display
MON3 storage wrapper
matrix keyboard and display service wrappers
bank-call or overlay-call trampoline
small shared string/path helpers
stable TECM8 BIOS jump table
```

Likely overlay or banked code:

```text
editor bank
assembler bank
program runner/loader bank or resident loader helper
source-aware debugger bank
help text and UI tables
assembler opcode tables
larger map/debug readers
```

The design preference is that banked tools call resident services through a
stable API, not that the resident shell depends deeply on banked tool internals.
That keeps the shell small and makes it possible to swap editor, assembler,
runner, and debugger code without rewriting the control flow. It also lets a
future trimmed MON3/TECM8 ROM boot straight into the shell while preserving the
MON3-compatible service names that existing code and habits rely on.

The first concrete bank target is the editor. It is already large enough to
stress a 16K bank, so editor quality work should focus on proving whether a
compact, bank-ready editor can fit cleanly before adding optional features such
as named block read/write.

## RAM Discipline

TECM8 should assume RAM is scarce. The editor should not require loading an
entire large project into memory. The assembler should avoid keeping more state
live than necessary. Debugger features should be designed as a later, more
expensive layer rather than being permanently resident from the start.

Useful RAM principles:

- Keep shared state layout explicit and centralized.
- Reserve a named video workspace instead of letting each display library
  silently consume low RAM.
- Prefer bounded buffers with byte-sized capacities where practical.
- Keep command input, path buffers, and project metadata small.
- Treat source files as disk-backed records, not one giant in-memory document.
- Let mass storage carry inactive source, maps, overlays, and scratch data.
- Keep display buffers accounted for; they are part of the working set.
- Avoid making the shell responsible for tool-private state.

The current 24K realistic RAM target is not a hard formal allocation yet. It is
a design pressure: code and data should be shaped so future allocation planning
does not require a full rewrite.

The current editor source workspace is explicitly assigned to `3000h-37FFh`,
below the `4000h` launch address and above MON3's low display/storage workspace.
It holds the previous-page cache, active page, adjacent next page, and backup
scratch sectors. `3800h-3FFFh` remains reserved for future editor workspace.

## Code Compactness

The project is still in a greenfield stage. Clear, testable, contract-driven
code is more important than premature byte shaving. However, compactness should
shape routine boundaries now.

Good early habits:

- Keep routines small enough to inspect and prove.
- Use AZM register contracts consistently.
- Factor common string, path, buffer, and command parsing behavior.
- Prefer reusable helpers when they prevent duplicated logic.
- Keep tables and text separate from executable flow.
- Avoid hidden dependencies between features that may later live in different
  ROM banks.
- Make buffer formats and call contracts stable before optimizing internals.

This may sometimes trade a few bytes for decomposition. That is acceptable
while the architecture is still settling. Later, measured hot spots and large
helpers can be inlined, specialized, or banked once there is real size data.

## Later Shrinking Techniques

When code size becomes an active constraint, likely techniques include:

```text
moving editor/assembler/debugger into banked ROM overlays
sharing path and filename scanners across tools
using compact command dispatch tables
compressing help text and diagnostic strings
specializing general helpers only where measurement justifies it
moving rarely used setup/config screens out of resident code
streaming assembler inputs and outputs through TM8 storage
storing maps/debug data on disk and loading views on demand
```

The goal is a 1980s-style compact system: one that feels capable because it is
careful about what is resident, what is banked, what is on disk, and what is
recomputed or reloaded when needed.

## Measurement

Once TEC-side code grows beyond early proof stubs, TECM8 should track rough
code and data size by module. Exact byte accounting is not needed at every
step, but the project should know when resident code is growing too quickly.

Useful recurring measurements:

```text
resident shell code bytes
shared helper code bytes
editor overlay bytes
assembler overlay bytes
debugger overlay bytes
static RAM buffers
display RAM assumptions
largest live working set
```

This document does not impose hard limits yet. It records the pressure that
will guide future refactoring: keep the system decomposable, keep resident code
small, and make later bank switching and code shrinking possible.
