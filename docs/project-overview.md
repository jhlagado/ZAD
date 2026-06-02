# TECM8 Project Overview

## Vision

TECM8 is intended to give the TEC-1G a Turbo Pascal-like development experience:
edit code, save it, build it, run it, and eventually debug it from the machine
itself.

The first target is the TEC-1G with matrix keyboard, graphical LCD, and
PATA/SD-backed FAT32 storage through MON3. A later display target is a TMS9918
VDU board, likely using a 32x24 tile display.

The project should not try to become a full modern operating system. It should
be a practical single-user development environment shaped around the limits and
strengths of a Z80 machine.

## Name

`TECM8` is pronounced "TecMate": a companion for the TEC. Use `TM8` where a
short three-character identifier is needed, such as FAT 8.3 volume extensions.

The system still has two major halves:

- **Development workspace**: shell, filesystem, editor, assembler, build tools.
- **Interactive debugging environment**: object loader, source map reader,
  breakpoint/step/run support, and source-aware debug display.

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
- Avoid FAT32 long filename and directory complexity by using a virtual
  filesystem inside one FAT32 container file.
- Size the first volume format for a decomposed MON3-scale project while keeping
  file and prefix identifiers byte-sized.

## First User Experience

The first practical goal is not a full IDE. It is a small command-line workspace
with a Notepad/WordStar-like editor.

Example:

```text
/
> cd /projects/tecm8
/projects/tecm8
> ls
editor.z80
storage.z80

> edit editor.z80
```

The `cd` command changes the current path prefix. It does not require a real
directory object. A path begins to feel real when files exist under that prefix.

## Long-Term User Experience

Later versions should support workflows like:

```text
edit /projects/demo/main.z80
asm /projects/demo/main.z80 -o /build/demo.bin -m /build/demo.map
run /build/demo.bin
debug /build/demo.bin /build/demo.map
```

The long-term stretch goal is a source-aware debugger, closer to a Turbo Pascal
5 experience than a simple monitor.

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
- **Assembler/tool runner**: compile source into object and map files.
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
