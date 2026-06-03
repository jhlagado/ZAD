# TECM8 Documentation

TECM8 is a self-hosted Z80 Assembly development environment for the TEC-1G. The
first customer-facing target is a Turbo Pascal 3-style edit/assemble/run
workflow on the machine itself: shell, project workspace, editor,
assembler/tool runner, and return to the prompt.

The preferred source extension is `.ASM`. `.Z80` remains supported for imported
ASM80-era code, but TECM8 examples should lead with `.ASM`. The advanced goal is
a source-aware debugger with source maps, breakpoints, stepping, and register
display.

The name is spelled `TECM8` and pronounced "TecMate": a companion for the TEC.
Use `TM8` where a short three-character identifier is needed.

Install the maintained proof/tooling dependencies from the repo root:

```text
npm install
```

Useful project commands:

```text
npm run check
npm run proof:storage:check
npm run audit:storage
npm run quality
```

Start here:

- [Project Overview](project-overview.md)
- [Storage Proof](storage-proof.md)
- [Virtual Filesystem](virtual-filesystem.md)
- [Editor Design](editor-design.md)
- [Project Sizing Case Studies](project-sizing.md)
- [Debugging Roadmap](debugging-roadmap.md)
- [Implementation Plan](implementation-plan.md)
