# Storage Proof

## Goal

Prove the narrow storage assumption that TECM8 depends on:

```text
A pre-created .TM8 file can be treated as a block device by TEC-side code,
through the same storage path expected for the real project.
```

This is not a filesystem proof. It proves that an existing `VOLUME.TM8` file can
be opened through MON3, read in 512-byte units, written back after a read, and
verified from the host side.

Run the maintained storage proof check from the repo root:

```text
npm run proof:storage:check
```

## Test Image

`tools/create-storage-proof-image.ts` creates a minimal FAT32 SD-card image at:

```text
proofs/storage/tm8proof-fat32.img
```

The image contains one host-created root file:

```text
VOLUME.TM8
```

The file is 4 MiB, contiguous, and filled with recognizable 512-byte sector
markers. The generated manifest records the exact LBAs and byte offsets.

TECM8 v1 layout offsets covered by the proof:

```text
file-relative sector 0     block 0, superblock
file-relative sector 8     block 1, allocation table
file-relative sector 16    block 2, first catalog sector
file-relative sector 79    block 9, last catalog sector
file-relative sector 80    block 10, first data sector
```

Create and verify a pristine image:

```text
npm run proof:storage:image
npm run proof:storage:image:verify
```

`--verify-only` checks the pristine generated markers. After the MON3 proof has
written into the image, regenerate it before running `--verify-only` again.

## MON3 Runner

`tools/run-storage-proof.ts` builds a tiny proof program at `4000h`, loads the
matching MON3 ROM, enables TEC-1G SD image backing, and calls MON3 storage
routines directly:

```text
openFile    F5A1h
readSector  F5D5h
writeSector F66Dh
DISK_BUFF   0600h
```

The proof program:

1. Opens `VOLUME.TM8`.
2. Reads file-relative sectors `0`, `8`, `16`, `79`, and `80`.
3. Copies a marker into `DISK_BUFF` after each read.
4. Calls `writeSector` after each read.
5. Verifies the resulting host image bytes at the exact file offsets.

Run it:

```text
npm run proof:storage
```

Verified on 2026-06-02:

```text
result: ok
instructions: 2736745
sector 0  offset 1134592  TM8 MON3 WRITE SUPERBLOCK 0000
sector 8  offset 1138688  TM8 MON3 WRITE ALLOC 0008
sector 16 offset 1142784  TM8 MON3 WRITE CATALOG 0016
sector 79 offset 1175040  TM8 MON3 WRITE CATALOG 0079
sector 80 offset 1175552  TM8 MON3 WRITE DATA 0080
```

The runner writes the same data to `proofs/storage/last-run.json`.

Run the current-status check:

```text
npm run proof:storage:check
```

Run the complete proof audit with requirement-by-requirement evidence:

```text
npm run audit:storage
```

Verified audit result on 2026-06-02:

```text
result: ok
storageProof.status: ok
requirements: all TM8 storage requirements proven against the current Debug80 checkout
```

## Requirement Status

| Requirement | Current status |
| --- | --- |
| Host-created `VOLUME.TM8` file can exist on an emulated/card FAT32 volume | Proven by `tools/create-storage-proof-image.ts`. |
| MON3 or Debug80/MON3 path can open the existing file | Proven against the current Debug80 checkout. |
| TECM8 can read arbitrary 512-byte sectors inside the file | Proven for sectors 0, 8, 16, 79, and 80 through MON3 `readSector`. |
| TECM8 can write back sectors that were previously read | Proven for the same sectors through MON3 `writeSector`. |
| Writes can be verified from the host side | Proven by host byte checks in `tools/run-storage-proof.ts`, `tools/check-storage-proof-status.ts`, and `tools/audit-storage-proof.ts`. |
| Version 1 layout offsets are reliable | Proven for superblock, allocation table, catalog start/end, and first data sector. |

## Next Step

Use this proof as the storage regression gate while moving on to the next TECM8
storage layer:

```text
npm run proof:storage:check
```
