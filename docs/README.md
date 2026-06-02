# TECM8 Documentation

TECM8 is a self-hosted development environment for the TEC-1G. The long-term goal
is a project workspace with a file browser, editor, assembler/tool runner, and
eventually an interactive debugger.

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
