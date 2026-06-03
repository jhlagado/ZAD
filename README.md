# TECM8

TECM8 is a self-contained development environment for the TEC-1G: a small
Z80 machine with a matrix keyboard, GLCD, and FAT32-backed storage through MON3.

The target source language is Z80 Assembly. The first product target is a Turbo
Pascal 3-style edit/assemble/run workflow: a user should be able to boot into a
compact shell, browse a project volume, edit `.ASM` source, assemble it, run the
result, and return to the prompt.
`.Z80` source remains a compatibility path for imported ASM80-era projects, but
TECM8 examples and tools should prefer `.ASM`.
The intended assembly dialect is an AZM-like cleaned-up ASM80 baseline: the
useful core of ASM80 without every historical compatibility wildcard.

The advanced goal is a source-aware debugger with object loading, source maps,
breakpoints, stepping, register display, and source context. That is deliberately
separate from the first edit/assemble/run baseline.

Project storage is built around a portable `VOLUME.TM8` workspace file. Host
tools create, inspect, import, export, copy, pack, and unpack these volumes so
projects can move cleanly between a laptop and the TEC-1G.

Start with the documentation:

- [Project Overview](docs/project-overview.md)
- [Implementation Plan](docs/implementation-plan.md)
- [Workspace Disk Format](docs/workspace-disk-format.md)
- [Virtual Filesystem](docs/virtual-filesystem.md)
- [Editor Design](docs/editor-design.md)
- [Debugging Roadmap](docs/debugging-roadmap.md)

Useful local checks:

```text
npm install
npm run check
```
