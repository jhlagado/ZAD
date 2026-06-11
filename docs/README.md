# TECM8 Documentation

TECM8 is a self-hosted Z80 Assembly development environment for the TEC-1G. The
first customer-facing target is an early Turbo Pascal-style project workflow on
the machine itself: a remembered main file, direct named-file editing, short
`edit`/`asm`/`run` commands, and return to the prompt.

The preferred source extension is `.ASM`. `.Z80` remains supported for imported
ASM80-era code, but TECM8 examples should lead with `.ASM`. The advanced goal is
a source-aware debugger with source maps, breakpoints, stepping, and register
display.

The name is spelled `TECM8` and pronounced "TecMate": a companion for the TEC-1.
Use `TM8` where a short three-character identifier is needed.

Install the maintained proof/tooling dependencies from the repo root:

```text
npm install
```

Useful project commands:

```text
npm run check
npm run proof:project-config
npm run proof:project-config:storage
npm run proof:shell-commands
npm run proof:storage:check
npm run audit:storage
npm run quality
```

Start here:

- [Live Roadmap](roadmap.md)
- [Codebase Tour](codebase.md)
- [Virtual Filesystem](virtual-filesystem.md)
- [TEC-Side Shell Command Contract](shell-command-contract.md)
- [TECM8 AZM Style Guide](azm-style-guide.md)
- [Editor Design](editor-design.md)
- [Debug80 Editor Session](debug80-editor-session.md)
- [Memory and Code Quality Manifest](memory-and-code-quality.md)
- [MON3 Decomposition Plan](mon3-decomposition.md)
- [MON3 Service Inventory](mon3-service-inventory.md)
- [MON3 Storage Split Report](mon3-storage-split.md)
- [MON3 GLCD Split Report](mon3-glcd-split.md)
- [TECM8 BIOS API Draft](tecm8-bios-api.md)
