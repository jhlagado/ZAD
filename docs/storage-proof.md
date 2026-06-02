# Storage Proof

## Goal

Prove the narrow storage assumption that ZAD depends on:

```text
A pre-created .ZAD file can be treated as a block device by TEC-side code,
through the same storage path expected for the real project.
```

This is not a filesystem proof. It only proves that an existing `VOLUME.ZAD`
file can be opened through MON3, read in 512-byte units, written back after a
read, and verified from the host side.

Run the TypeScript proof tools with Node's type-strip flag:

```text
node --experimental-strip-types tools/check-storage-proof-status.ts --strict
```

## Test Image

`tools/create-storage-proof-image.ts` creates a minimal FAT32 SD-card image at:

```text
proofs/storage/zadproof-fat32.img
```

The image contains one host-created root file:

```text
VOLUME.ZAD
```

The file is 4 MiB, contiguous, and filled with recognizable 512-byte sector
markers. The generated manifest records the exact LBAs and byte offsets.

Proposed ZAD layout offsets covered by the proof:

```text
file-relative sector 0     block 0, superblock
file-relative sector 8     block 1, allocation table
file-relative sector 16    block 2, first catalog sector
file-relative sector 79    block 9, last catalog sector
file-relative sector 80    block 10, first data sector
```

Create and verify a pristine image:

```text
node --experimental-strip-types tools/create-storage-proof-image.ts
node --experimental-strip-types tools/create-storage-proof-image.ts --verify-only
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

1. Opens `VOLUME.ZAD`.
2. Reads file-relative sectors `0`, `8`, `16`, `79`, and `80`.
3. Copies a marker into `DISK_BUFF` after each read.
4. Calls `writeSector` after each read.
5. Verifies the resulting host image bytes at the exact file offsets.

Run it:

```text
node --experimental-strip-types tools/run-storage-proof.ts
```

Verified on 2026-06-02:

```text
result: ok
instructions: 2736629
sector 0  offset 1134592  ZAD MON3 WRITE SUPERBLOCK 0000
sector 8  offset 1138688  ZAD MON3 WRITE ALLOC 0008
sector 16 offset 1142784  ZAD MON3 WRITE CATALOG 0016
sector 79 offset 1175040  ZAD MON3 WRITE CATALOG 0079
sector 80 offset 1175552  ZAD MON3 WRITE DATA 0080
```

The runner writes the same data to `proofs/storage/last-run.json`.

To run the full current-status check:

```text
node --experimental-strip-types tools/check-storage-proof-status.ts
```

This leaves `zadproof-fat32.img` in the passed-proof state and reports whether
the unmodified Debug80 gate has passed yet. Add `--strict` when the check should
exit non-zero until the unmodified path passes.

To run the complete proof audit, including patched Debug80 temp-runtime
preparation and requirement-by-requirement evidence:

```text
node --experimental-strip-types tools/audit-storage-proof.ts
```

Verified audit result on 2026-06-02:

```text
realDebug80.goalCompleteWithoutShim: true
noShimDebug80.status: ok
requirements: all ZAD storage requirements proven against the real Debug80 checkout
```

The same audit also reports whether Debug80 source and compiled `out` contain
the required SD-SPI behavior. Debug80 commit `901846b` preserves SD SPI command
frames across MON3 idle gaps and rebuilds the compiled runtime.

## Emulator Compatibility

The runner currently applies a local MON3 SD-SPI compatibility patch before
creating Debug80's TEC-1G runtime. This patch is deliberately scoped to the
emulated SD card behavior:

- returns MISO in bit 7, which MON3 samples with `IN A,(FD)` followed by `RLA`;
- returns SDHC OCR as `0C0h`, which MON3 accepts as a valid SDHC card;
- preserves an SD command/response transaction across MON3's byte-idle CS-high
  gaps.

Running the same proof without the local compatibility patch is the important
regression gate:

```text
node --experimental-strip-types tools/run-storage-proof.ts --no-sd-compat-patch
```

Pre-fix result on 2026-06-02:

```text
openFile -> initDisk -> initSD -> checkSDCardPresent
FATerror8: no SD card
```

Post-fix result on 2026-06-02:

```text
result: ok
```

The proposed Debug80 source patch can be validated in an isolated temp copy
without mutating the real Debug80 checkout:

```text
node --experimental-strip-types tools/prepare-patched-debug80-runtime.ts --target /private/tmp/zad-debug80-patched-tool
```

Result on 2026-06-02:

```text
Test Files  2 passed (2)
Tests       16 passed (16)
```

Then run the no-shim storage proof against the generated patched runtime:

```text
DEBUG80_ROOT=/private/tmp/zad-debug80-patched-tool node --experimental-strip-types tools/check-storage-proof-status.ts --strict
```

The tool-generated patched temp runtime reports:

```text
noShimDebug80: ok
goalCompleteWithoutShim: true
```

and verifies the same five host-side markers at sectors `0`, `8`, `16`, `79`,
and `80`. The real Debug80 checkout now passes the same no-shim proof.

Before the stack fix in this runner, the proof stack was accidentally placed in
MON3 ROM space at `DFF0h`; that made `RET` instructions pop invalid return
addresses. The runner now uses RAM stack `7FF0h`.

## Requirement Status

| Requirement | Current status |
| --- | --- |
| Host-created `VOLUME.ZAD` file can exist on an emulated/card FAT32 volume | Proven by `tools/create-storage-proof-image.ts`. |
| MON3 or Debug80/MON3 path can open the existing file | Proven no-shim against the real Debug80 checkout. |
| ZAD can read arbitrary 512-byte sectors inside the file | Proven no-shim with real Debug80 for sectors 0, 8, 16, 79, and 80 through MON3 `readSector`. |
| ZAD can write back sectors that were previously read | Proven no-shim with real Debug80 for the same sectors through MON3 `writeSector`. |
| Writes can be verified from the host side | Proven by host byte checks in `tools/run-storage-proof.ts`, `tools/check-storage-proof-status.ts`, and `tools/audit-storage-proof.ts`. |
| Proposed layout offsets are reliable | Proven for superblock, allocation table, catalog start/end, and first data sector. |
| Real Debug80 checkout passes no-shim path | Proven after Debug80 commit `901846b`. |

## Next Step

Keep the no-shim proof as the regression gate while moving on to the next ZAD
storage layer:

```text
node --experimental-strip-types tools/run-storage-proof.ts --no-sd-compat-patch
```

The historical Debug80 source patch is captured in:

```text
patches/debug80-mon3-sd-spi.patch
```

The diagnosed Debug80-specific failures are recorded in:

```text
docs/debug80-emulation-notes.md
```

The proof no longer requires `DEBUG80_ROOT` to point at the generated patched
runtime.
