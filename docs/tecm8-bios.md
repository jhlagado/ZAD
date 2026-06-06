# TECM8 BIOS Direction

TECM8 should assume MON3 is present first. The near-term ROM model is not a
clean replacement, but a MON3-compatible service profile: keep the hardware
service routines that make the TEC-1G usable as a small general-purpose
computer, preserve continuity with MON3's calling conventions where practical,
and identify which monitor features could later be shaved down if ROM space
becomes tight.

The current MON3 ROM is 16K at C000h-FFFFh. A TECM8 BIOS should initially aim
for about 8K, with 10K still acceptable if the retained device support is
useful. Even a 10K BIOS leaves roughly 6K in the high ROM for resident TECM8
support code that should not depend on the banked expansion window.

See [MON3 Decomposition Plan](mon3-decomposition.md) for the working
classification of classic MON3 core, MON3-light BIOS services, removable
extensions, and TECM8 replacement candidates.

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

TECM8 should call MON3 or MON3-compatible services for hardware access. Above
that, TECM8 can grow into a normal user-facing system alongside MON3: a shell,
a filesystem view, a useful editor, and a launcher for larger tools.

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
prefer wrappers and `.asmi` contracts that keep MON3 naming and behavior
recognizable rather than inventing an unrelated ABI too early. See
[TECM8 BIOS API Draft](tecm8-bios-api.md) for the first proposed service map
and register contracts.

## Remove

If a future MON3-derived BIOS cut is made, the first candidates to shave down
are extensions and bundled applications, not the features that make MON3 feel
like MON3. The preferred strategy is to keep classic monitor identity intact
while replacing or slimming GLCD, storage, RTC UI, and optional text-heavy
components behind compatible service boundaries.

Candidates to remove or avoid carrying forward:

- PATA support and PATA user interface. TECM8 should use SD as the storage
  target.
- MON3's current GLCD terminal/editor-facing layer, once TECM8 has a smaller
  renderer that preserves low-level GLCD usefulness.
- RTC interactive clock setup and PRAM viewer, if compact RTC service calls are
  enough for the resident BIOS.
- Copy/fill/move monitor conveniences only after extension savings have been
  measured.
- Intel HEX loader UI if SD and serial transfer provide better project paths.
- Large menu and parameter UI frameworks except where compact internal helpers
  are cheaper to keep than rewrite.
- Tiny BASIC, packages, demos, hidden extras, and novelty monitor applications.
- Large text screens, help strings, credits, and monitor-facing prompts.
- Hardware diagnostic flows that belong in a diagnostic ROM, not the everyday
  TECM8 BIOS.

The disassembler, memory examine/edit UI, GO path, breakpoint basics, LCD,
seven-segment display, and hexadecimal keypad are classic MON3 identity. They
may be replaced later if TECM8 grows better source-aware tools, but they should
not be the first removal target. Keeping them also avoids forcing a brand-new
monitor identity before TECM8 is mature enough to carry that responsibility.

A tiny fallback monitor may still be useful in a later, more aggressive cut.
That should be treated as a separate profile, not the first MON3-compatible
BIOS direction.

Do not automatically discard MON3's LCD menu idea. A small menu launcher may
be useful at bootstrap or recovery time, especially if the existing MON3-style
menu control code is compact. The rule is size and role: a small launcher is
acceptable; a full monitor UI should not dominate the ROM.

## Storage Boundary

TECM8 currently uses MON3 storage through direct file/sector entry points. Any
future BIOS profile should make the storage boundary explicit and SD-only.

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

### GLCD RAM Cost

MON3's current GLCD library effectively reserves `0A00h-17FFh` as a GLCD/video
workspace. That is `0E00h` bytes, or 3584 bytes 3.5 KiB. The main pieces are a
1024-byte full 128x64 graphics buffer, drawing and cursor state around
`0E00h`, a 960-byte terminal scroll buffer, and a second 1024-byte terminal
graphics buffer.

That allocation makes sense for MON3 as a general-purpose graphics and terminal
library. A 128x64 one-bit framebuffer is inherently 1024 bytes, and keeping
separate terminal/scroll buffers makes cursor drawing, line scrolling, and
screen refresh easier and faster. It is also a large fixed cost for TECM8.

TECM8 should initially preserve MON3 compatibility. A later TECM8-focused GLCD
BIOS should also preserve full bitmap capability; a 128x64 one-bit framebuffer
is a useful and legitimate display model for graphs, sprites, and custom UI.
The optimization question is whether every text/editor view must also pay for
MON3's second terminal framebuffer and bitmap scrollback. The display layer
should make these modes explicit:

```text
graphics view   full bitmap framebuffer
terminal view   text output rendered through shared renderer
editor view     sector/window text viewport rendered to display
composite view  optional graphics background plus text/status overlay
```

If RAM pressure requires a smaller text path, the options are:

- Keep a small text model, such as a 16x4 character grid plus cursor state, and
  render rows directly to the GLCD.
- Use dirty-row or dirty-cell updates instead of always maintaining a second
  full terminal bitmap.
- Make full 128x64 graphics buffering optional and caller-supplied when a tool
  actually needs graphics.
- Treat scrolling as a text-buffer operation first, not necessarily as a
  preserved bitmap history.
- Keep drawing primitives available, but do not require every text UI to pay
  for the full graphics workspace.

Composite display is possible but should be deliberate. The ST7920 GLCD does
not provide hardware compositing, so a composite mode would be a software pass:
for example OR-ing a text/status overlay into a graphics bitmap, or using a
masked text-cell overlay that clears a cell before drawing glyphs. OR overlay
is cheap and useful for simple labels; masked text is cleaner but costs more
code and CPU.

The same display contract should be able to sit above a later TMS9918-style VDU
BIOS. A TMS path will likely use external video RAM for the display image, so
its CPU RAM pressure will be different: state, staging, name-table helpers, and
dirty tracking rather than a 1024-byte CPU framebuffer. TECM8 should therefore
define display services in terms of text, cursor, clear, plot/update, and
optional graphics operations, not in terms of MON3's exact GLCD buffers.

### GLCD Text Geometry

MON3's current GLCD terminal uses 6x6 pixel character cells, not 8x8 tiles.
On the 128x64 GLCD this gives a practical text terminal of 20 columns by 10
rows. The current TECM8 editor policy is to expose all ten rows as source text
in the 6x6 profile and temporarily redraw the last row as a status, command, or
error overlay only when needed:

```text
rows 0-9   editable source lines
row 9      transient status/errors overlay when active
```

That overlay row should be policy, not a hardware assumption. A later 6x8 font
profile may reduce the number of visible source rows or reserve an explicit
status row without changing the editor's source model.

The editor/debugger gutter does not need to consume a full character cell. A
4-pixel bitmap gutter can carry breakpoint, current-line, selection, dirty, or
diagnostic markers while still allowing 20 full 6-pixel text columns:

```text
128 px width - 4 px gutter = 124 px
124 px / 6 px cell = 20 full columns, with 4 px spare
```

This also clarifies the future TMS9918 relationship. The shared TECM8 display
model should be cell-based and metadata-based, not tied to identical cell
sizes. The GLCD backend can render compact 6x6 cells and software-composited
sprite/marker overlays; a TMS9918 backend can map similar concepts onto 8x8
tiles, a name table, and hardware sprites.

Selection should initially be represented as display metadata rather than
mandatory inverted text. On the GLCD, a selected line or selected block can be
shown as a vertical bar in the 4-pixel gutter, leaving the source text itself
unmodified and readable. Inverted text can still be supported later as an
optional backend attribute, but gutter-first selection is cheaper and maps
cleanly to future TMS9918 renderers as a left-column glyph, color treatment, or
sprite marker.

## RTC Boundary

MON3's RTC block is about 1.4K in the current Debug80 ROM map. It is not just a
small DS1302 read routine. It includes:

```text
DS1302 presence/reset/get/set time/date/day/mode
12/24-hour conversion
BCD/binary conversion
formatted time/date strings
raw RTC PRAM byte and burst access
interactive LCD/keypad clock setup
interactive RTC PRAM viewer
day-name/help strings and an API dispatch table
```

The BIOS-worthy part is the compact service layer: detect RTC, get/set time,
get/set date, get/set day, switch 12/24-hour mode, read/write PRAM bytes, and
possibly preserve checksum helpers if MON3 settings continue to live in RTC
PRAM. The interactive clock setup and PRAM viewer are useful MON3 applications,
but they are candidates to relocate or build as optional tools if fixed ROM
space becomes tight.

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
resident TECM8 system layer. This is where TECM8 becomes a richer companion
environment while preserving MON3 continuity underneath.

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

Likely rough split for a future TECM8 BIOS profile:

```text
SD/FAT32 sector/file services        2.0K-3.5K
GLCD text/graphics/terminal services 2.5K-4.5K
matrix keyboard and key parsing      0.8K-1.5K
serial bit-bang I/O                  0.5K-1.0K
system latch/banking helpers         0.3K-0.8K
sound/timing/RTC/small utilities     0.8K-1.8K
API table, boot glue, tiny monitor   0.5K-1.0K
```

These numbers are estimates, not measurements. They are not a proposal to strip
classic MON3 first. A MON3-compatible transition should try to reclaim roughly
5K by rewriting GLCD, cutting PATA while keeping SD, splitting RTC services
from RTC UI, and shaving optional strings/extensions. The disassembler is a
reserve saving of about 2K, but should remain classic core until TECM8 has a
better replacement.

The important constraint is the shape: hardware services stay resident and
compact, the shell/filesystem/editor layer can occupy carefully chosen fixed
space, and the heavier development tools move into RAM and banked expansion
ROM.

RAM should be budgeted with the same discipline as ROM. While MON3 is present,
storage services can make `0100h-07FFh` volatile, and GLCD terminal/graphics
services can make `0A00h-17FFh` effectively unavailable for TECM8 state. A
trimmed TECM8 BIOS should try to reduce those fixed reservations, especially by
removing PATA paths and by offering a text-first display layer that does not
always require MON3's full GLCD terminal workspace.

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
