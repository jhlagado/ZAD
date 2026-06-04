# TECM8 BIOS Direction

TECM8 should eventually boot into the development environment, not into the
full MON3 monitor. The long-term ROM model is therefore a trimmed MON3-derived
BIOS: keep the hardware service routines that make the TEC-1G usable as a
small general-purpose computer, and remove the interactive monitor features
that TECM8 replaces.

The current MON3 ROM is 16K at C000h-FFFFh. A TECM8 BIOS should initially aim
for about 8K, with 10K still acceptable if the retained device support is
useful. Even a 10K BIOS leaves roughly 6K in the high ROM for resident TECM8
support code that should not depend on the banked expansion window.

## Role

The BIOS is not the user interface. It is the stable machine service layer
under TECM8:

```text
boot into TECM8
provide storage primitives
provide display primitives
provide keyboard/input primitives
provide serial I/O
provide system latch and bank control
provide small timing/sound/utility calls
avoid monitor workflows and application UI
```

TECM8 should call BIOS services for hardware access. Above that, TECM8 can
grow into the normal user-facing system that replaces the everyday MON3
experience: a shell, a filesystem view, a useful editor, and a launcher for
larger tools.

The distinction is not simply "BIOS versus application." TECM8 has a middle
layer of resident system services that may be generally useful beyond assembly
projects. The shell, file loading/saving, and editor can be treated as closer
to the system than the assembler and debugger, because they are useful for
text files, scripts, configuration, and future languages as well as Z80
Assembly.

## Keep

The retained service set should be biased toward hardware access and compact
building blocks.

Priority services:

- SD/FAT32 storage primitives for opening the active volume and reading or
  writing sectors.
- Matrix keyboard scanning, key-repeat parsing, modifier handling, and ASCII
  translation where practical.
- GLCD initialization, text terminal output, character/string output, clear,
  cursor positioning, graphics buffer plotting, and small drawing helpers.
- Serial bit-bang transmit and receive, because host-to-TEC transfer remains
  valuable even when TECM8 is the primary environment.
- System control latch helpers for shadow, protect, expand, caps, and bank
  selection state.
- Delay/timing helpers needed by LCD, GLCD, SD, serial, keyboard, and sound.
- Sound generation and small audio feedback routines.
- RTC support if the code size is modest and the service boundary remains
  clean.
- Seven-segment scanning, hexadecimal keypad input, and character conversion
  routines as lower-priority compatibility services.
- Small utility routines such as byte/word-to-ASCII, ASCII-to-segment, string
  compare, and simple random number generation if they are already compact.

Useful API surfaces from MON3 include matrix scan, matrix-to-ASCII parsing,
GLCD terminal calls, LCD character/string calls, serial calls, sound calls, and
get/set calls for shadow/protect/expand/caps/GLCD terminal state. TECM8 should
wrap these behind its own names rather than depending directly on every MON3
entry point forever.

## Remove

The first BIOS cut should remove features whose main purpose is the MON3 human
monitor experience.

Candidates to remove or avoid carrying forward:

- PATA support and PATA user interface. TECM8 should use SD as the storage
  target.
- Full monitor command loop.
- Memory examine/edit UI.
- Copy/fill/move monitor conveniences.
- Disassembler and disassembly UI.
- Intel HEX loader UI if SD and serial transfer provide better project paths.
- Large menu and parameter UI frameworks except where compact internal helpers
  are cheaper to keep than rewrite.
- Tiny BASIC, packages, demos, hidden extras, and novelty monitor applications.
- Large text screens, help strings, credits, and monitor-facing prompts.
- Hardware diagnostic flows that belong in a diagnostic ROM, not the everyday
  TECM8 BIOS.

A tiny fallback monitor may still be useful. It should be deliberately
fractional: enough to show addresses, raw bytes, or basic state and escape
from serious boot problems, but not enough to compete with TECM8 as the normal
interface. The seven-segment display and hexadecimal keypad are built into the
TEC-1, so it is reasonable to keep a remnant-level path for them. That path
should be a compatibility and recovery feature, not a full monitor with
disassembly, block copy, fill, move, or elaborate memory traversal workflows.

Do not automatically discard MON3's LCD menu idea. A small menu launcher may
be useful at bootstrap or recovery time, especially if the existing MON3-style
menu control code is compact. The rule is size and role: a small launcher is
acceptable; a full monitor UI should not dominate the ROM.

## Storage Boundary

TECM8 currently uses MON3 storage through direct file/sector entry points. The
BIOS version should make the storage boundary explicit and SD-only.

Desired storage calls:

```text
init SD
mount FAT32 card or locate active VOLUME.TM8
open named FAT32 file
read 512-byte sector at byte offset
write 512-byte sector at byte offset
report compact error code
```

TECM8's own TM8 virtual filesystem should remain above this layer. The BIOS
does not need to understand TECM8 files, source records, projects, or build
outputs. It only needs to reliably move sectors between the SD-backed FAT32
container file and RAM.

## Display Boundary

The GLCD is the primary TECM8 display target. BIOS display services should make
common text output cheap without forcing TECM8 to adopt MON3's menu model.

Desired GLCD calls:

```text
init GLCD
clear text plane
clear graphics buffer
set text cursor
write character
write zero-terminated string
plot graphics buffer
optional draw character/sprite helper
optional terminal mode toggle
```

The 20x4 LCD and seven-segment display can remain as secondary device services
if they fit cleanly. They are useful for compatibility, boot diagnostics, and
small status displays, but they should not drive TECM8's main UI design.

## Input Boundary

The matrix keyboard is the main input device. BIOS input should expose both raw
and parsed forms:

```text
scan matrix
return raw key/modifier state
parse repeat timing
translate to ASCII where possible
scan hexadecimal keypad as compatibility input
```

TECM8 may still need its own line editor and command editing behavior. The BIOS
should provide dependable key events, not a full text editor.

## Banking Boundary

The banked 8000h-BFFFh expansion window is the natural home for the large
TECM8 tools. BIOS calls should make bank selection boring and stable:

```text
get current expansion state
enable or disable expansion window
select current 16K bank
preserve unrelated SYS_CTRL bits
optionally provide a bank-call trampoline
```

The bank-call trampoline may become one of the most valuable resident pieces:
TECM8 can keep a small shell/kernel in fixed memory while editor, assembler,
runner, debugger, help, and tables are swapped through the expansion window.

## Resident TECM8 System Layer

The BIOS direction should allow a second tier above raw hardware services: a
resident TECM8 system layer. This is where TECM8 starts replacing MON3 as the
normal way users interact with the machine.

Good resident candidates:

- command shell and launcher
- TM8 filesystem navigation and file open/save helpers
- general-purpose text editor core
- script or command-file runner if one emerges
- simple configuration screens
- compact GLCD terminal and status UI
- optional compact LCD menu launcher
- fallback raw byte/address display on seven-segment hardware

These are more general-purpose than the assembler. They can serve assembly
projects, text editing, scripts, BASIC-like experiments, configuration files,
or other future file types. The editor should not be assembly-only by design;
assembly source is the first user, not the only possible user.

Heavier tools remain better banked or overlay candidates:

- assembler
- source-aware debugger
- map/debug readers
- large help system
- opcode tables
- language-specific tooling
- future BASIC or scripting implementation if it grows beyond a compact shell
  extension

This split keeps the everyday environment close to the machine while preserving
the expansion window for large, replaceable tools.

## ROM Budget

The first planning budget should be:

```text
8K target BIOS
10K acceptable BIOS ceiling
6K minimum reclaimed high-ROM space if BIOS reaches 10K
8K reclaimed high-ROM space if BIOS reaches 8K
```

Likely rough split:

```text
SD/FAT32 sector/file services        2.0K-3.5K
GLCD text/graphics/terminal services 2.5K-4.5K
matrix keyboard and key parsing      0.8K-1.5K
serial bit-bang I/O                  0.5K-1.0K
system latch/banking helpers         0.3K-0.8K
sound/timing/RTC/small utilities     0.8K-1.8K
API table, boot glue, tiny monitor   0.5K-1.0K
```

These numbers are estimates, not measurements. The important constraint is the
shape: hardware services stay resident and compact, the shell/filesystem/editor
layer can occupy carefully chosen fixed space, and the heavier development
tools move into RAM and banked expansion ROM.

## Resident TECM8 Opportunity

The reclaimed high-ROM space should be reserved for resident TECM8 support
that benefits from being always visible:

- boot handoff into TECM8
- shell/kernel entry point
- BIOS call wrappers
- bank-call trampoline
- fatal error and fallback display path
- active project/volume state
- compact path and filename helpers
- command dispatch glue
- overlay loader
- compact editor/file service entry points if they prove broadly useful

The assembler, runner, debugger, maps, help, and large tables should not
compete for this fixed high-ROM space unless measurement proves there is room.
The editor is a special case: a small general-purpose editor core may deserve
resident status, while larger editing modes, help, syntax features, or
language-specific behavior can still live in banked tools.
