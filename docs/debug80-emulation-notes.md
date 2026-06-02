# Debug80 Emulation Notes

These are failures found while proving the ZAD storage assumption. They are
recorded separately because they look like Debug80 TEC-1G/MON3 emulation gaps,
not ZAD disk-format problems.

Current status on 2026-06-02: resolved in Debug80 commit `901846b` and verified
by the ZAD strict storage proof.

```text
node --experimental-strip-types tools/check-storage-proof-status.ts --strict
```

## 1. Compiled Debug80 SD SPI Fails MON3 Card Detection

Reproduce from the ZAD repo:

```text
node --experimental-strip-types tools/run-storage-proof.ts --no-sd-compat-patch
```

Pre-fix observed result on 2026-06-02:

```text
openFile -> initDisk -> initSD -> checkSDCardPresent
FATerror8: no SD card
```

Diagnosis:

- MON3 samples MISO from bit 7 using `IN A,(FD)` followed by `RLA`.
- The compiled Debug80 runtime in `/Users/johnhardy/projects/debug80/out` still
  returns MISO in bit 0.
- Current Debug80 source already returns bit 7, so this part appears to be a
  stale compiled-output problem.

Pre-fix impact:

MON3 cannot detect the emulated SD card, so the unmodified compiled Debug80 path
does not reach FAT32 mount or `VOLUME.ZAD` open.

## 2. Compiled Debug80 SDHC OCR Is Rejected By MON3

Observed during local compatibility testing before patching OCR behavior:

```text
FATerror10: invalid SD card
DISK_BUFF=0x40 0x00 0x00 0x00
```

Diagnosis:

- MON3 accepts OCR bit 7 set, with `0C0h` meaning valid SDHC.
- The compiled Debug80 runtime returns `040h` for high-capacity cards.
- Current Debug80 source already returns `0C0h`, so this also appears to be a
  stale compiled-output problem.

Impact:

Even after card detection, MON3 rejects the card before FAT32 access.

## 3. Debug80 SD SPI Resets Transactions Across MON3 Byte-Idle CS Gaps

MON3's `spiWrite` routine writes an idle bus value after each byte. In practice
that means Debug80 sees CS inactive between command bytes.

Current source behavior:

```text
if (!nextCsActive) {
  this.resetTransaction();
  ...
}
```

Diagnosis:

- Existing Debug80 SD tests keep CS active for the whole command frame.
- MON3 idles CS between bytes.
- Resetting the transaction on every CS-high idle prevents the emulator from
  accumulating MON3's six-byte SD command frames.

Impact:

The SD emulator can pass direct helper tests while failing real MON3 bit-banged
storage code.

Proposed fix:

`patches/debug80-mon3-sd-spi.patch` preserves active command/response state
across MON3 byte-idle gaps and adds regression tests for the MON3 command
pattern.

## Issue-Ready Summary

Title:

```text
TEC-1G SD SPI emulation does not match MON3 bit-banged SD command framing
```

Reproduction:

```text
cd /Users/johnhardy/projects/ZAD
node --experimental-strip-types tools/check-storage-proof-status.ts
```

Full audit, including patched temp-runtime validation:

```text
node --experimental-strip-types tools/audit-storage-proof.ts
```

The audit also reports SD-SPI source/runtime readiness. Current real Debug80
diagnostics before commit `901846b`:

```text
patchAppliesCleanly: true
sourceSdSpi.misoBit7: true
sourceSdSpi.highCapacityOcrValid: true
sourceSdSpi.preservesMon3ByteIdleCs: false
sourceSdSpi.resetsOnInactiveCs: true
compiledSdSpi.misoBit7: false
compiledSdSpi.highCapacityOcrValid: false
compiledSdSpi.preservesMon3ByteIdleCs: false
compiledSdSpi.resetsOnInactiveCs: true
```

Interpretation:

- Debug80 source already contains the MISO bit-7 and valid SDHC OCR changes.
- Debug80 source still needs the MON3 byte-idle CS transaction preservation
  patch.
- Debug80 `out` is stale relative to source for MISO and OCR, and must be
  rebuilt after applying the CS patch.

Pre-fix status:

```text
pristineImage: ok
noShimDebug80: failed, FATerror8: no SD card
shimmedMon3Proof: ok
goalCompleteWithoutShim: false
```

Verified after Debug80 was fixed and rebuilt:

```text
node --experimental-strip-types tools/run-storage-proof.ts --no-sd-compat-patch
```

opens the host-created `VOLUME.ZAD`, writes proof markers through MON3
`readSector`/`writeSector`, and reports `result: ok`.

Patch validation:

```text
cd /Users/johnhardy/projects/debug80
git apply --check /Users/johnhardy/projects/ZAD/patches/debug80-mon3-sd-spi.patch
```

Focused Debug80 tests to run after applying the patch:

```text
npx vitest run tests/platforms/tec1g/sd-spi.test.ts tests/platforms/tec1g/sd-spi-runtime.test.ts
```

## Patched-Copy Validation

The patch can also be validated in an isolated temp copy:

```text
node --experimental-strip-types tools/prepare-patched-debug80-runtime.ts --target /private/tmp/zad-debug80-patched-tool
```

This copies Debug80 source, applies `patches/debug80-mon3-sd-spi.patch` when it
is not already present, runs `npx tsc`, and runs the focused SD tests:

```text
npx vitest run tests/platforms/tec1g/sd-spi.test.ts tests/platforms/tec1g/sd-spi-runtime.test.ts
```

Result on 2026-06-02:

```text
Test Files  2 passed (2)
Tests       16 passed (16)
```

Then, from the ZAD repo:

```text
DEBUG80_ROOT=/private/tmp/zad-debug80-patched-tool node --experimental-strip-types tools/check-storage-proof-status.ts --strict
```

The patched temp runtime passes the no-shim MON3 proof:

```text
shimmedMon3Proof: ok
noShimDebug80: ok
goalCompleteWithoutShim: true
```

This showed the proposed Debug80 fix was sufficient for the ZAD storage proof.
The same behavior is now present in the real Debug80 checkout.

## Not Classified As Debug80 Failures

The proof runner initially used stack `DFF0h`, which is in the MON3 ROM range
for this runtime configuration. That made returns pop invalid addresses. The
runner now uses RAM stack `7FF0h`.

The proof also currently calls MON3 storage routines directly instead of through
the `RST 10h` API dispatcher. That is a proof-runner scope choice, not yet a
diagnosed Debug80 failure. It should be tested separately before ZAD relies on
the dispatcher path.
