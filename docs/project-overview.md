# TECM8 Project Overview

## Vision

TECM8 is intended to be a Z80 Assembly development environment for the TEC-1G.
Its first complete user experience should borrow the useful parts of early
Turbo Pascal: a project has a main source file, the environment remembers the
project entry point, and the common edit/assemble/run loop uses short commands
rather than long command lines.

The first target is the TEC-1G with matrix keyboard, graphical LCD, and
PATA/SD-backed FAT32 storage through MON3. A later display target is a TMS9918
VDU board, likely using a 32x24 tile display.

The project should not try to become a full modern operating system. It should
be a practical single-user development environment shaped around the limits and
strengths of a Z80 machine: a command shell that launches focused tools and
applications, then returns to the shell when they exit.

## Name

`TECM8` is pronounced "TecMate": a companion for the TEC-1. Use `TM8` where a
short three-character identifier is needed, such as FAT 8.3 volume extensions.

The system has three user-facing layers:

- **Project workspace**: a portable `VOLUME.TM8` containing source files,
  copied libraries, examples, build outputs, and metadata.
- **Edit/assemble/run environment**: the first complete product target, with a
  Turbo Pascal 3-like emphasis on project defaults and short commands.
- **Source-aware debugging environment**: the advanced goal, with object
  loading, source maps, breakpoints, stepping, registers, and source context.

## Guiding Principles

- Disk is the source of truth.
- A TM8 volume is a project workspace, not the whole mass-storage device.
- Tools are overlays, not permanently resident applications.
- Keep live RAM usage small by loading only the working view of a file.
- Prefer fixed-size records and blocks where that simplifies Z80 arithmetic.
- Use MON3 services initially instead of duplicating working hardware drivers.
- Build for GLCD first, but keep editor and filesystem logic display-neutral.
- Encourage small source files and decomposition.
- Copy dependencies into a project volume rather than maintaining live external
  dependency links.
- Prefer `.ASM` for user source files. `.Z80` should remain supported for
  imported ASM80-era code, but TECM8 examples and tools should lead with
  `.ASM`.
- Target an assembly dialect based on the cleaner AZM baseline: compatible
  with the useful core of ASM80, but without carrying every historical
  compatibility wildcard.
- Avoid FAT32 long filename and directory complexity by using a virtual
  filesystem inside one FAT32 container file.
- Size the first volume format for a decomposed MON3-scale project while keeping
  file and prefix identifiers byte-sized.

## First User Experience

The first complete product goal is a small command-line workspace with a
Notepad/WordStar-like editor and an assembler/run loop. The experience should
feel closer to early Turbo Pascal than to a Unix build pipeline or modern IDE:
one compact shell, focused tools, project-level defaults, fast exit back to the
prompt, and project files that are easy to inspect.

Example:

```text
/
> cd /projects/tecm8
/projects/tecm8
> ls
main.asm
storage.asm

> edit main
```

The `cd` command changes the current path prefix. It does not require a real
directory object. A path begins to feel real when files exist under that prefix.
For source files, the `.ASM` extension is assumed when the user omits an
extension.

## Edit/Assemble/Run Baseline

The baseline customer-facing result is a project-centered edit/assemble/run
environment. A project has a main source file, usually `/src/main.asm`, created
or selected when the project is created. That file is the mainline of the
program and includes the other project source files as needed.

The shell should remember the main file: the file assembled and run by default.
Other source files can be opened by name with `edit driver`, `edit math`, or an
absolute path.

The remembered project state lives in the root `/tecm8.prj` file inside the
active volume. It is a small line-oriented ASCII file rather than JSON, so
TEC-side Z80 code can scan it without a complex parser:

```text
tm8project=1
main=/src/main.asm
```

The config records the main file only. Build output and map paths are derived
from the main source filename by convention: `/src/main.asm` builds to
`/build/main.bin` and `/build/main.map`. The exact TEC-side parse and
resolution rules are defined in
[TEC-Side Shell Command Contract](shell-command-contract.md).

The common flow should therefore be short:

```text
project demo
edit
asm
run
```

`edit` with no argument opens the main file. For source files, `edit math`
opens `math.asm`. `asm` assembles the project's main file and writes derived
`/build/<main-stem>.bin` and
`/build/<main-stem>.map` outputs. `run` runs that derived project output. Most
users should not need to type output paths or switches during ordinary work.

Project configuration screens can handle less common settings such as changing
the main file and adjusting assembler options. Output and map names are
conventions derived from the main file, not separate project fields. The
command line remains deliberately simple.

The user should be able to sit at the TEC-1G, open a project, edit any source
file, assemble the main file, run the result, and return to the shell. This is
the first major "done" line for the product.

The assembler should treat `.ASM` as the preferred source extension. `.Z80`
remains a compatibility extension for imported ASM80-style projects. The source
dialect should follow an AZM-like baseline: a cleaned-up core derived from
ASM80, deliberately avoiding the broadest historical ASM80 compatibility
features unless they prove necessary.

## Advanced User Experience

Later versions should support workflows like:

```text
project demo
edit draw
asm
run
debug
```

The advanced goal is a source-aware debugger. It should show source context,
registers, flags, current PC/SP, and breakpoint/run/step controls. This is a
separate level of complexity beyond the Turbo Pascal 3-style baseline and
should not block the first edit/assemble/run environment.

## Host Companion Tools

The laptop-side tools make the system practical without becoming the primary
experience. They create and inspect TM8 project volumes today, and they can
import and export raw host files. They can also copy raw files between TM8
volumes so users can seed examples and move libraries into a project. The
`fs unpack` command exports a TM8 volume into an ordinary host folder tree, and
`fs pack` rebuilds a volume from a host folder.

From a user's perspective:

```text
fs format VOLUME.TM8
fs project-init VOLUME.TM8 /src/main.asm
fs import VOLUME.TM8 main.asm /src/main.asm
fs export VOLUME.TM8 /src/main.asm main-backup.asm
fs copy LIBS.TM8:/lib/glcd/terminal.asm VOLUME.TM8:/lib/glcd/terminal.asm
fs unpack VOLUME.TM8 my-project
fs pack my-project VOLUME.TM8
```

The host tool remains stateless and absolute-path based. Interactive state such
as `cd` and `pwd` belongs to the TEC-side shell.

## Platform Assumptions

Current assumptions, to be verified as work begins:

- Z80 CPU.
- MON3 available as the initial BIOS/monitor layer.
- GLCD and matrix keyboard available.
- MON3 can open an existing FAT32 file and read/write sectors through its
  PATA/SD code.
- A workspace container file can be pre-created on a host machine.
- The TEC-1G environment can rewrite sectors inside that existing file.

## Major Components

- **Resident kernel/shell**: command loop, path prefix, console, tool dispatch.
- **Storage wrapper**: MON3 file open, sector read, sector write.
- **Virtual filesystem**: internal prefix table, file catalog, and block
  allocator.
- **Editor**: fixed-record source editor for GLCD.
- **Import/export tools**: move files between host-visible FAT files and the
  internal virtual filesystem.
- **Volume import tools**: copy libraries or examples from another TM8 volume
  into the active project volume as a one-off operation.
- **Assembler/tool runner**: assemble `.ASM` source into object and map files.
- **Debugger**: source-aware runtime debugger, added later.

## Project Volumes

The preferred model is one TM8 volume per active project.

The FAT32 card may contain several volumes:

```text
VOLUME.TM8      active project
LIBS.TM8       shared library sources
DEMOS.TM8      examples
TETRO.TM8      another project
```

The TEC-1G normally works inside one mounted volume. Files from another volume
can be copied into the active project, but this is a static import, not dynamic
linking or package management. The programmer should be able to inspect and own
the code copied into a project.

The current default volume size is 4MB with 4K allocation blocks, 256 file
entries, and 128 prefix entries. This is expected to fit a decomposed MON3-scale
project with build artifacts and copied libraries. See
[Project Sizing Case Studies](project-sizing.md).

Runtime memory is a separate pressure from TM8 volume size. TECM8 should be
designed for the TEC-1G/MON3 map: MON3 as 16K ROM at C000h-FFFFh, RAM and
monitor workspace below it, and a banked 16K expansion window at 8000h-BFFFh
for larger tools. The practical RAM working set may be closer to 24K once
display buffers and other hardware needs are considered. Code should remain
clear and proof-driven now, but routine boundaries should support future
banking, overlays, and code shrinking. See
[Memory and Code Quality Manifest](memory-and-code-quality.md).

The editor should be designed as a sector-window tool, not a terminal
scrollback tool. With 32-byte source records, a 512-byte sector holds 16 lines
and a 4K TM8 block holds 128 lines. The GLCD may show only a small viewport, so
the editor should page source sectors in and redraw from records rather than
depending on a whole-file buffer. See [Editor Design](editor-design.md).
