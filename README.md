# TECM8

TECM8 is a self-contained development environment for the TEC-1G: a small
Z80 machine with a matrix keyboard, GLCD, and FAT32-backed storage through MON3.

The target source language is Z80 Assembly. The first product target borrows the
useful parts of early Turbo Pascal: a project has a main source file, the
environment can open named source files directly, and common work uses short
commands like `edit`, `asm`, and `run` rather than long command lines.
`.Z80` source remains a compatibility path for imported ASM80-era projects, but
TECM8 examples and tools should prefer `.ASM`.
The intended assembly dialect is an AZM-like cleaned-up ASM80 baseline: the
useful core of ASM80 without every historical compatibility wildcard.

The advanced goal is a source-aware debugger with object loading, source maps,
breakpoints, stepping, register display, and source context. That is deliberately
separate from the first edit/assemble/run baseline.

Project storage is built around a portable `VOLUME.TM8` workspace file. Current
host tools create, inspect, import, export, copy, unpack, and pack files across
these volumes so projects can move cleanly between a laptop and the TEC-1G.
Separate `fs import-text` and `fs export-text` commands convert source text to
and from TECM8's fixed 32-byte editor records.
The root `/tecm8.prj` file stores the project main file as simple ASCII
`key=value` metadata for the future TEC-side shell.

Start with the documentation:

- [Project Overview](docs/project-overview.md)
- [Live Roadmap](docs/roadmap.md)
- [Implementation Plan](docs/implementation-plan.md)
- [Workspace Disk Format](docs/workspace-disk-format.md)
- [Virtual Filesystem](docs/virtual-filesystem.md)
- [TEC-Side Shell Command Contract](docs/shell-command-contract.md)
- [TECM8 AZM Style Guide](docs/azm-style-guide.md)
- [Editor Design](docs/editor-design.md)
- [Memory and Code Quality Manifest](docs/memory-and-code-quality.md)
- [Code Quality Audit](docs/code-quality-audit.md)
- [TECM8 BIOS Direction](docs/tecm8-bios.md)
- [TECM8 BIOS API Draft](docs/tecm8-bios-api.md)
- [Debugging Roadmap](docs/debugging-roadmap.md)

Useful local checks:

```text
npm install
npm run check
```

`npm run check` includes the Fallow dead-code gate (`npm run quality`).
`npm run quality:health` and `npm run quality:dupes` are advisory locators;
see the [Code Quality Audit](docs/code-quality-audit.md) for the gate policy.
