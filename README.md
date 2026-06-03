# TECM8

TECM8 is a self-contained development environment for the TEC-1G: a small
Z80 machine with a matrix keyboard, GLCD, and FAT32-backed storage through MON3.

The target source language is Z80 Assembly. The first product target borrows the
useful parts of early Turbo Pascal: a project has a main source file, the
environment remembers the current file of interest, and common work uses short
commands like `edit`, `asm`, and `run` rather than long command lines.
`.Z80` source remains a compatibility path for imported ASM80-era projects, but
TECM8 examples and tools should prefer `.ASM`.
The intended assembly dialect is an AZM-like cleaned-up ASM80 baseline: the
useful core of ASM80 without every historical compatibility wildcard.

The advanced goal is a source-aware debugger with object loading, source maps,
breakpoints, stepping, register display, and source context. That is deliberately
separate from the first edit/assemble/run baseline.

Project storage is built around a portable `VOLUME.TM8` workspace file. Current
host tools create, inspect, and import these volumes; Phase 2 adds export,
cross-volume copy, pack, and unpack so projects can move cleanly between a
laptop and the TEC-1G.

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
