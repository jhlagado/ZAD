# Storage Proof Artifacts

This directory contains the small MON3-facing proof stub for the TM8 storage
assumption.

Tracked source artifacts:

- `mon3-sector-proof.z80` sketches the direct MON3 calls used by
  `tools/run-storage-proof.ts`.
- `.gitignore` keeps generated images and run manifests out of git.

Generated artifacts:

- `tm8proof-fat32.img` is created by `tools/create-storage-proof-image.ts`.
- `tm8proof-fat32.json` records the generated image layout.
- `last-run.json` records the most recent successful MON3 proof markers.

Run the complete proof audit from the repo root:

```text
node --experimental-strip-types tools/audit-storage-proof.ts
```
