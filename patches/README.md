# Patches

This directory contains patches used to validate ZAD assumptions against
external tools.

## Debug80 MON3 SD-SPI Patch

`debug80-mon3-sd-spi.patch` fixes the TEC-1G SD-SPI behavior needed by MON3's
bit-banged SD routines:

- preserve an active SD command/response transaction across MON3's byte-idle
  CS-high gaps;
- add regression coverage for MON3-style command framing and SDHC init.

The real Debug80 checkout is expected at:

```text
/Users/johnhardy/projects/debug80
```

For older Debug80 checkouts, check that the patch still applies:

```text
cd /Users/johnhardy/projects/debug80
git apply --check /Users/johnhardy/projects/ZAD/patches/debug80-mon3-sd-spi.patch
```

Validate in an isolated temp copy without mutating Debug80:

```text
cd /Users/johnhardy/projects/ZAD
node --experimental-strip-types tools/prepare-patched-debug80-runtime.ts --target /private/tmp/zad-debug80-patched-tool
DEBUG80_ROOT=/private/tmp/zad-debug80-patched-tool node --experimental-strip-types tools/check-storage-proof-status.ts --strict
```

Run the complete ZAD storage proof audit:

```text
node --experimental-strip-types tools/audit-storage-proof.ts
```
