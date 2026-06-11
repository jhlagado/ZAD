# MON3 Storage Split Report

Generated from Debug80 MON3 bundle source and `mon3.d8.json`.

This is a rough label-range measurement of `pata_fat32.z80`. It measures
address ranges between known labels, so the numbers include code and data
inside those ranges. The categories are planning aids for an SD-only TECM8
profile, not linker-enforced boundaries.

Measured storage module span: 2646 bytes (`0A56`).

## Category Split

| Category | ID | Bytes | Hex | Disposition | Ranges | Notes |
| --- | --- | ---: | --- | --- | --- | --- |
| PATA-specific hardware path | `pata-specific` | 167 | `00A7` | `remove` | `initPata1`-`IDEreadSector` (67 bytes)<br>`readPATA`-`doERR` (38 bytes)<br>`writePATA`-`AtoLCD` (62 bytes) | PATA status polling, PATA data loops, and LBA register setup. SD-only TECM8 should remove this path. |
| Shared block-device/error glue | `block-device-shared` | 169 | `00A9` | `keep` | `IDEreadSector`-`readPATA` (56 bytes)<br>`doERR`-`writePATA` (92 bytes)<br>`AtoLCD`-`FATmount` (21 bytes) | Current read/write wrappers, MON3 LCD error output, and byte-to-LCD helper. Needs refactoring if PATA is cut. |
| FAT32/file-sector core | `fat-core` | 867 | `0363` | `keep` | `FATmount`-`FATgetRootDir` (267 bytes)<br>`FATreadSector`-`saveFileName` (166 bytes)<br>`getFirstCluster`-`loadRAM` (376 bytes)<br>`BCDEtimeA`-`RTCAPI` (58 bytes) | Mount, cluster math, open/read/write sector services, and small arithmetic helpers needed for TECM8 storage. |
| Storage UI/load-save workflows | `storage-ui` | 853 | `0355` | `optional` | `loadFromDisk`-`initPata1` (25 bytes)<br>`FATgetRootDir`-`FATreadSector` (501 bytes)<br>`saveFileName`-`getFirstCluster` (50 bytes)<br>`loadRAM`-`checkSDCardPresent` (150 bytes)<br>`LOAD_CFG`-`BCDEtimeA` (127 bytes) | MON3 menu loader, Intel HEX load path, RAM backup/restore, LCD progress UI, and storage configuration strings. |
| SD/SPI hardware path | `sd-spi` | 367 | `016F` | `keep` | `checkSDCardPresent`-`MSG_TIMEOUT` (319 bytes)<br>`spiCMD0`-`LOAD_CFG` (48 bytes) | SD card detection, command setup, SPI read/write, block read/write, initialization, and SD command tables. |
| Storage messages | `messages` | 223 | `00DF` | `optional` | `MSG_TIMEOUT`-`spiCMD0` (223 bytes) | MON3-facing storage error messages. A TECM8 BIOS may keep compact error codes and move text elsewhere. |

## SD-only Minimum

SD-only minimum keep set: `block-device-shared`, `fat-core`, `sd-spi`.

Estimated resident keep bytes: 1403 bytes.

PATA-only bytes: 167 bytes.

Optional storage UI/message bytes: 1076 bytes.

Plausible reclaim from PATA + optional storage UI/messages: 1243 bytes.

The important result is that PATA-only code is small. Most practical savings
come from removing PATA plus relocating MON3 storage UI, RAM backup/restore,
Intel HEX loading, and human-readable storage messages. FAT32/file-sector
services and SD/SPI access remain the TECM8-critical surface.

Key labels for the SD-only service set:

| Label | Address | Source |
| --- | --- | --- |
| `openFile` | `F5A1` | `pata_fat32.z80:1001` |
| `readSector` | `F5D5` | `pata_fat32.z80:1055` |
| `writeSector` | `F66D` | `pata_fat32.z80:1163` |
| `FATmount` | `F18B` | `pata_fat32.z80:376` |
| `FATreadSector` | `F48B` | `pata_fat32.z80:805` |
| `FATgetSector` | `F4AE` | `pata_fat32.z80:830` |
| `FATgetFAT` | `F4D5` | `pata_fat32.z80:857` |
| `checkSDCardPresent` | `F771` | `pata_fat32.z80:1341` |
| `sendSPICommand` | `F79B` | `pata_fat32.z80:1374` |
| `readSPIBlock` | `F7BC` | `pata_fat32.z80:1407` |
| `writeSPIBlock` | `F7DB` | `pata_fat32.z80:1432` |
| `initSD` | `F803` | `pata_fat32.z80:1464` |

