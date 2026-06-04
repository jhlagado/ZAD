# MON3 Decomposition Plan

This document classifies MON3 as the starting point for a future MON3-light
ROM. The near-term assumption remains simple: MON3 is present, occupies the
fixed 16K ROM window at `C000h-FFFFh`, and TECM8 uses MON3-compatible service
calls rather than replacing the monitor outright.

The goal is not to discard MON3 or to force TECM8 to ship a completely new
monitor before it has earned that role. The goal is to keep MON3 recognisably
MON3 while understanding which parts are classic monitor identity, which parts
are hardware BIOS services, which parts are optional bundled extensions, and
which parts TECM8 should eventually replace with smaller or more purpose-built
code.

## Current Shape

The Debug80 TEC-1G MON3 bundle currently models MON3 BC25/v1.6 as a 16 KiB ROM
image. The bundled source is a useful sizing and decomposition reference:

```text
api_includes.z80        122 lines
disassembler.z80       1118 lines
glcd_library.z80       3097 lines
mon3.z80               3713 lines
packages.z80              9 lines
pata_fat32.z80         1695 lines
rtc.z80                1104 lines
sound.z80               122 lines
```

These line counts are not ROM byte counts. They are only a rough weight map:
GLCD, FAT/PATA/SD, RTC, the disassembler, and the main monitor are the large
areas to measure when a real MON3-light build exists.

The Debug80 source map gives a more useful rough ROM layout:

```text
C000-D7FF  main MON3 monitor code/data       about 6.0K
D800-E79A  GLCD library/font/banner          about 3.9K
E79B-EF6A  disassembler                      about 2.0K
EF6B-F021  sound                             about 0.2K
F022-FA77  PATA/FAT32/SD storage             about 2.6K
FA78-FFEB  RTC                               about 1.4K
FFEC-FFFF  release metadata                  tiny
```

These ranges explain the preferred saving strategy: preserve the classic MON3
surface first, then reclaim space by replacing large extensions or slimming
them behind compatible service boundaries.

MON3 exposes two important API surfaces:

- `RST 10h`, with `C` selecting the main MON3 API table.
- `RST 18h`, with `A` selecting the GLCD API table.

The main table includes software/version ID, initialization, beeps, segment and
ASCII conversion, LCD output, key scanning, matrix keyboard parsing, joystick
scan, serial I/O, Intel HEX and serial transfer helpers, data dump helpers,
menu and parameter drivers, timing, sound, system latch state, RTC, random
number generation, disassembly helpers, GLCD terminal state, disk open/read/
write, and RGB LED matrix scanning.

The GLCD table includes GLCD initialization, buffer clearing, text/graphics
mode selection, boxes, lines, circles, pixels, filled shapes, plot/update,
row/column text drawing, delays, buffer clear policy, character/sprite drawing,
inverse graphics, terminal initialization, character/string terminal output,
register display, cursor handling, auto-linefeed, underline, and plot-always
mode.

## Classification

It is useful to separate "classic MON3 core" from "MON3-light BIOS core." Some
features are core to MON3 as a monitor, but are not necessarily core to a TECM8
BIOS.

| Area | Classic MON3 role | MON3-light default | Notes |
| --- | --- | --- | --- |
| Reset, RST stubs, NMI/INT trampolines | Core | Keep | Compatibility anchor for existing programs and wrappers. |
| API call numbers and names | Core | Preserve where practical | Existing callers should not need a new ABI too early. |
| System latch state: shadow, protect, expand, caps | Core | Keep | Required for memory map, bank window, and compatibility. |
| Matrix keyboard scan and ASCII parsing | Device service | Keep | Primary TECM8 input path. |
| GLCD low-level init, plot, text, drawing primitives | Extension/device service | Keep first, later replace selectively | GLCD is central to TECM8, but MON3's terminal architecture may be too RAM-heavy. |
| Character LCD, seven-segment scan, hex keypad | Classic hardware surface | Keep as fallback/diagnostic | Lower priority than matrix keyboard and GLCD, but useful because the hardware is built in. |
| SD/FAT32 file and sector access | Extension/device service | Keep and stabilize | TECM8 depends on SD-backed storage. |
| PATA support | Legacy storage extension | Remove from TECM8 profile | PATA exists for older compatibility, not TECM8's main storage path. |
| Serial bit-bang I/O | Device service | Keep | Host transfer/debug remains valuable. |
| RTC | Extension/device service | Keep if compact or make optional | Useful, but not on the critical path for first TECM8. |
| Sound generation | Device service/fun monitor feature | Keep if compact | Small and useful for feedback; do not remove just because it is not essential. |
| Full menu and parameter frameworks | Monitor UI infrastructure | Shrink or keep only compact helpers | A tiny launcher can remain; large monitor UI should not dominate ROM. |
| Memory examine/edit, go, raw byte display | Classic monitor core | Keep | This is MON3's visible identity and should not be removed in the first strategy. |
| Copy/fill/move monitor tools | Classic monitor conveniences | Keep first, possibly shave later | These are less central than memory inspect/edit, but still part of classic MON3. |
| Disassembler and disassembly UI | Classic monitor identity | Keep first, replace only after better TECM8 tools exist | About 2K, but useful and recognisably classic. |
| Intel HEX user workflow | Classic transfer path | Remove or make optional | SD and serial project transfer should cover the normal path. |
| Tiny BASIC, packages, demos, extras | Bundled applications | Remove or relocate to disk/bank | Not part of the BIOS surface. |
| Help, credits, large prompts, novelty strings | Monitor UI data | Remove or relocate | Good ROM-saving candidates. |

## ROM-Saving Strategy

The first space target should be about 5K reclaimed without making MON3 stop
feeling like MON3. A 6K saving is a useful stretch, but it should come from
extension replacement and service slimming before cutting the disassembler or
classic monitor flow.

Likely first savings:

- GLCD: currently about 3.9K including the font and banner. TECM8 should keep
  useful low-level hardware and glyph knowledge, but replace the terminal/editor
  layer with a smaller TECM8 renderer. Plausible saving: 1.5K-2.5K.
- Storage: currently about 2.6K for PATA/FAT32/SD. TECM8 should keep SD-backed
  file/sector access and remove the PATA path. Plausible saving: 0.8K-1.3K,
  depending on how much FAT32 and UI code is shared.
- RTC: currently about 1.4K. The core DS1302 service layer is not that large;
  much of the weight is interactive clock setup, LCD/keypad UI, PRAM viewer,
  formatting, strings, and API table. Plausible saving: 0.4K-0.7K if the BIOS
  keeps read/write services but relocates or drops the interactive UI.
- Menu text/extras: bulky menu labels, help text, novelty strings, and bundled
  applications can be moved out of fixed ROM where they are not part of core
  monitor identity. Plausible saving: 0.5K-1.0K.

The disassembler remains a reserve option. Removing it would save roughly 2K,
but it should not be the first cut because it is useful, classic, and gives MON3
some of its character. It becomes a better candidate after TECM8 has a
source-aware debugger or a richer disassembly view elsewhere.

## RTC Notes

The RTC block is larger than a simple "read the clock" driver because it
contains several layers:

```text
DS1302 presence/reset/get/set time/date/day/mode   about 0.3K
time/date formatting and BCD conversion            about 0.1K-0.2K
RTC PRAM byte and burst access                     about 0.1K
low-level DS1302 bit-bang read/write               about 0.1K
interactive LCD/keypad clock setup                 about 0.4K
interactive RTC PRAM dump/viewer                   about 0.2K
cached time/checksum helpers, strings, API table   about 0.2K
```

The core DS1302 service layer is worth keeping if RTC hardware is present:
presence check, get/set time, get/set date, get/set day, 12/24-hour mode, raw
PRAM read/write, and perhaps BCD conversion. The interactive clock setup and
PRAM viewer are MON3 applications. They are useful, but they do not have to live
in the fixed BIOS if TECM8 needs space. They can become optional tools, disk
programs, or banked utilities.

## Compatibility Invariants

The first MON3-light profile should preserve continuity before it attempts deep
rewrites:

- Keep the visible ROM map assumption: MON3-compatible services live at
  `C000h-FFFFh`.
- Keep `RST 10h` for MON3-compatible services unless a measured reason forces a
  new entry path.
- Keep `RST 18h` or an equivalent GLCD vector while MON3 GLCD compatibility is
  still expected.
- Keep existing service names and call numbering where wrappers or user code
  already rely on them.
- Keep a documented `.asmi` contract for every BIOS service TECM8 calls.
- Treat MON3 low RAM as BIOS-owned while MON3-compatible storage or GLCD calls
  are active.
- Preserve enough character LCD, seven-segment, and hex keypad behavior for
  boot diagnostics and recovery.

Compatibility does not mean keeping every monitor feature in fixed ROM forever.
It means changes should happen behind stable service boundaries, with measured
size wins and explicit replacement paths.

## Services To Stabilize

The first stable BIOS vocabulary should focus on reusable hardware services:

- Storage: SD init, FAT32 mount/open, sector read, sector write, close/error.
- Input: matrix raw scan, modifier state, ASCII/key-code translation, wait key.
- Display: GLCD init, clear, cursor, character/string output, plot/update, draw
  glyph/sprite, optional primitive drawing.
- Secondary display: character LCD output, seven-segment scan, hex keypad scan.
- Serial: enable, disable, transmit byte/string, receive byte.
- System control: shadow, protect, expand, caps, bank select, bank call.
- Timing and sound: delays, beep, note/tune primitives.
- Utilities: byte/word formatting, segment conversion, string compare, random.
- RTC: read/write if compact enough for the selected build.

These services should remain below TECM8 project policy. The BIOS should not
understand TM8 directories, source records, project config, assembler outputs,
or editor block selection.

## TECM8 Replacement Candidates

Several MON3 components are useful references but should not define TECM8's
long-term shape:

- GLCD terminal: keep MON3 calls at first, then replace with a TECM8 renderer
  that supports the 20x10 6x6-cell display, an eight-line editor viewport,
  two chrome rows, and a four-pixel gutter.
- Shell/menu: keep a tiny MON3-style launcher only if compact; TECM8 should own
  the normal shell and command loop.
- Editor: build a sector-window editor above the virtual filesystem rather
  than treating the GLCD as a serial terminal with scrollback history.
- Disassembler/debugger: keep the MON3 disassembler until TECM8 has a genuinely
  better source-aware debugger or disassembly view elsewhere.
- Storage UI: keep SD/FAT32 primitives in BIOS, but move TM8 pack/unpack,
  project creation, import/export, and path policy above the BIOS.
- Larger applications: assembler, debugger, BASIC, scripting, examples, and
  games should live in banked ROM, RAM overlays, or disk files rather than in
  the fixed BIOS unless measurement proves otherwise.

## Phased Path

1. Current MON3 unchanged: TECM8 calls existing MON3 services through wrappers
   and proves behavior in Debug80.
2. Inventory build: extract API labels, module ranges, low-RAM ownership, and
   actual ROM byte ranges from MON3 maps.
3. MON3-light source build: create a build profile from the same source with no
   behavioral removal except build switches, so size measurement is reliable.
4. Obvious extension shave: remove PATA first, then Tiny BASIC/packages/demos,
   novelty applications, large help strings, and unused extension text.
5. SD-only storage BIOS: keep the sector/file service boundary, preserve call
   compatibility, and document the RAM workspace explicitly.
6. Display split: keep low-level GLCD init/plot/glyph capabilities, then replace
   MON3 terminal buffering with a TECM8 display renderer if RAM or ROM pressure
   justifies it.
7. RTC split: keep compact DS1302 services resident, but consider moving the
   interactive clock setup and PRAM viewer out of fixed ROM.
8. Monitor shave, not replacement: only after the extension savings are
   measured, consider trimming copy/fill/move UI or other conveniences. Keep
   memory inspect/edit, GO, breakpoint basics, and disassembly unless better
   TECM8 tools exist.
9. Stable TECM8 BIOS: publish `.asmi` contracts and register-care expectations
   for all resident services, with bank-call conventions for larger tools.

## Measurement Work Needed

Before promising exact ROM savings, the project needs a measured MON3 inventory:

- Build or obtain a MON3 map with label ranges and module sizes.
- Categorize each `RST 10h` and `RST 18h` service as keep, optional, replace,
  or remove.
- Identify which services share code paths, especially storage, GLCD terminal,
  menu/parameter drivers, and conversion utilities.
- Measure low-RAM dependencies for storage, GLCD, RTC, serial, and menu code.
- Produce a first PATA-free ROM size estimate.
- Produce a second estimate with GLCD terminal replacement, RTC UI split, and
  Tiny BASIC/packages/demos/help strings removed or relocated.
- Record any compatibility breaks and wrapper changes required by each cut.

The immediate next engineering goal should be a machine-readable MON3 service
inventory: extract the API tables and nearby labels from the Debug80 MON3
source/map, classify each service, and generate a documentation table that can
be reviewed before any ROM-shaving patch begins.
