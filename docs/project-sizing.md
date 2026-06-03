# Project Sizing Case Studies

## Purpose

This note records the sizing assumptions behind the version 1 TM8 volume
defaults. The goal is to keep the limits large enough for serious TEC-1G work
while preserving byte-sized identifiers and simple Z80 arithmetic.

Current working limits:

```text
volume size:      4MB
block size:       4K
file entries:     256
prefix entries:   128
catalog size:     32K
```

## Source Storage Model

Source files are modeled as fixed 32-byte line records:

```text
byte 0      length, 0-31
byte 1-31   text bytes
```

This gives:

```text
512-byte sector = 16 lines
4K block        = 128 lines
```

The line count is more relevant than host file byte size, because host source
files often contain long comments and spacing that will not map directly to the
compact TECM8 line-record format.

## Tetro Reference

The Tetro project is a realistic small project with decomposed assembly files.

Measured `.asm` line count:

```text
files:       32
total lines: 5,676
average:     177.38 lines/file
max:         827 lines
```

Stored as 32-byte records:

```text
logical record bytes: 181,632
allocated with 4K blocks: 245,760
```

Fit counts:

```text
<= 128 lines / 4K:   20 files
<= 256 lines / 8K:   26 files
<= 384 lines / 12K:  28 files
<= 512 lines / 16K:  29 files
```

This supports 4K allocation blocks: many files fit in one block, and files just
over 128 lines only grow to two 4K blocks. Using 8K blocks would waste more
space across small modules.

## MON3-Scale Reference

The current MON3 `src` tree is a useful upper-end reference for a TEC-1G-scale
system project. It is not organized in the style TECM8 should encourage, because
several files are large library-style monoliths.

Current MON3 `src` line counts:

```text
3713  mon3.z80
3097  glcd_library.z80
1695  pata_fat32.z80
1118  disassembler.z80
1104  rtc.z80
122   sound.z80
122   api_includes.z80
9     packages.z80
```

Total:

```text
files:       8
total lines: 10,980
```

Stored directly as 32-byte source records:

```text
logical record bytes: 351,360
allocated with 4K blocks: 368,640
```

So even MON3-sized source occupies only about 360K before build artifacts.

## Decomposition Estimate

The existing MON3 files are too large for comfortable GLCD editing. If split
into smaller TM8-style modules:

```text
128-line modules: 90 files
256-line modules: 48 files
```

The storage requirement remains roughly the same:

```text
128-line modules: 90 * 4K = 368,640 bytes
256-line modules: about 380,928 bytes
```

The important pressure is therefore catalog capacity and organization, not raw
volume space.

For a decomposed MON3-scale project, a plausible prefix layout might include:

```text
src/monitor/boot
src/monitor/menu
src/monitor/input
src/monitor/display
src/monitor/breakpoints
src/glcd/core
src/glcd/draw
src/glcd/text
src/glcd/terminal
src/storage/fat
src/storage/pata
src/storage/sd
src/rtc
src/disasm/core
src/disasm/tables
src/api
src/sound
build/bin
build/map
docs
```

Expected prefix use:

```text
typical decomposed large project: 20-40 prefixes
comfortable upper case:          50-60 prefixes
hard v1 limit:                   128 prefixes
```

Expected file use for a MON3-scale project:

```text
source modules:      50-100
build artifacts:     2-5
docs/notes/libs:     20-50
hard v1 limit:       256 files
```

This leaves room under the 256-file limit, but generated files and backups
should be managed deliberately.

## Volume Utilization

A 4MB volume has:

```text
total blocks:    1024
metadata blocks: 10
data blocks:     1014
data capacity:   4,153,344 bytes
```

A decomposed MON3-scale source tree consumes roughly:

```text
~360K source data
```

Even after adding:

```text
16K binary
40K-50K Intel HEX
8K-32K compact map
libraries, notes, backups
```

the project remains comfortably inside 4MB.

An 8MB volume is also reasonable on modern SD media, but current evidence does
not require it for TEC-1G-scale projects. The 4MB default keeps images small
while leaving substantial headroom.

## Build Artifact Model

TECM8 is expected to assemble through source-level inclusion rather than a
separate object/link pipeline.

A project normally has:

```text
one root source file
many included source modules
one binary output
one Intel HEX output, if requested
one compact map/debug output
```

It should not create many small object files during a normal build. This keeps
file count and storage use under control.

Future module or load-time linking systems may add more artifact types, but
they are not part of the first assembler target.
