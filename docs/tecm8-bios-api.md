# TECM8 BIOS API Draft

This document defines the first proposed TECM8 BIOS service map. It is a
planning contract, not an implemented ABI yet. The goal is to give TECM8 code a
stable vocabulary for the services it expects from MON3 and any later
MON3-compatible trimmed BIOS profile.

The service map should be small, grouped, and conservative. It should preserve
continuity with MON3's RST-style calling model, service naming, and existing
hardware behavior where practical. The first step is to document and wrap MON3,
not to replace it wholesale.

## Calling Model

The preferred calling model is MON3's existing style: a small RST entry with
the call number in `C`.

```asm
        LD      C,TECM8_BIOS_GLCD_PUT_CHAR
        LD      A,"A"
        RST     0x10
```

The existing MON3 `RST 10h` convention should be preserved unless there is a
strong reason to add a new entry point. The final table should also publish an
AZM `.asmi` interface so TECM8 code can use register-care contracts for every
external service.

General rules:

- Carry clear means success unless a call states otherwise.
- Carry set means failure, with `A` containing a compact error code.
- Calls should preserve registers unless the contract says otherwise.
- Pointer inputs use `HL`, `DE`, or `BC` as stated by the call contract.
- Strings are ASCII and NUL-terminated unless a call explicitly takes a length.
- Sector buffers are 512 bytes.
- The BIOS should avoid owning TECM8 project state; TECM8 owns project and TM8
  virtual filesystem policy above the BIOS.

## Service Groups

The grouped ranges below are a TECM8 planning view, not a demand to renumber
MON3. Existing MON3 call numbers and names should remain valid. New TECM8-only
services can use grouped extension ranges if a later BIOS profile has room.

```text
00h-0Fh  identity, boot, status, errors
10h-1Fh  SD/FAT32 storage primitives
20h-2Fh  GLCD display and terminal services
30h-3Fh  input services
40h-4Fh  serial services
50h-5Fh  system control and banking
60h-6Fh  sound, timing, RTC, utilities
70h-7Fh  compatibility display/input services
80h-8Fh  resident TECM8 system services, if promoted into ROM
```

## Core Calls

| Call | Name | Purpose |
| ---: | --- | --- |
| Call | TECM8 wrapper | MON3 continuity |
| ---: | --- | --- |
| `00h` | `TECM8_BIOS_ID` | Wraps MON3 `_softwareID` / `_versionID` style calls. |
| `01h` | `TECM8_BIOS_BOOT_TECM8` | TECM8 extension, not a replacement for MON3 boot. |
| `02h` | `TECM8_BIOS_GET_STATUS` | TECM8 extension over MON3 status/control state. |
| `03h` | `TECM8_BIOS_GET_LAST_ERROR` | TECM8 extension for uniform wrapper errors. |

Draft contracts:

```text
TECM8_BIOS_ID
  in:  none
  out: HL = NUL-terminated identity string
       BC = major/version family
       DE = minor/build
  clobbers: A, flags

TECM8_BIOS_BOOT_TECM8
  in:  none
  out: does not return on success
       carry set, A = error if boot cannot continue
  clobbers: A, BC, DE, HL, flags

TECM8_BIOS_GET_STATUS
  in:  none
  out: A = status flags
       HL = optional status block
  clobbers: flags

TECM8_BIOS_GET_LAST_ERROR
  in:  none
  out: A = error code
       HL = optional NUL-terminated error text, or 0000h
  clobbers: flags
```

## Storage Calls

The TECM8 storage profile should be SD-only. PATA can remain in existing MON3
builds, but TECM8 should not depend on PATA and a future shaved BIOS profile
should omit it. FAT32 is the outer host-visible filesystem; TM8 remains a
TECM8-managed virtual filesystem inside a FAT32 container file.

| Call | TECM8 wrapper | Purpose |
| ---: | --- | --- |
| existing/direct | `TECM8_BIOS_SD_INIT` | Initialize SD hardware and verify card readiness. |
| existing/direct | `TECM8_BIOS_FAT_MOUNT` | Mount the FAT32 volume and cache needed geometry. |
| existing/direct | `TECM8_BIOS_FILE_OPEN` | Open a FAT32 file by path/name for sector access. |
| existing/direct | `TECM8_BIOS_FILE_READ_SECTOR` | Read a 512-byte sector from the open file. |
| existing/direct | `TECM8_BIOS_FILE_WRITE_SECTOR` | Write a 512-byte sector to the open file. |
| extension | `TECM8_BIOS_FILE_CLOSE` | Close or invalidate the current file handle. |

Draft contracts:

```text
TECM8_BIOS_SD_INIT
  in:  none
  out: carry clear on ready
       carry set, A = error
  clobbers: A, BC, DE, HL, flags

TECM8_BIOS_FAT_MOUNT
  in:  none
  out: carry clear on mounted
       carry set, A = error
  clobbers: A, BC, DE, HL, flags

TECM8_BIOS_FILE_OPEN
  in:  HL = NUL-terminated FAT32 filename/path
  out: carry clear on open
       carry set, A = error
  clobbers: A, BC, DE, HL, flags

TECM8_BIOS_FILE_READ_SECTOR
  in:  HLDE = byte offset within open file, 512-byte aligned
       IX = destination buffer
  out: carry clear on read
       carry set, A = error
  clobbers: A, BC, DE, HL, IX, flags

TECM8_BIOS_FILE_WRITE_SECTOR
  in:  HLDE = byte offset within open file, 512-byte aligned
       IX = source buffer
  out: carry clear on write
       carry set, A = error
  clobbers: A, BC, DE, HL, IX, flags

TECM8_BIOS_FILE_CLOSE
  in:  none
  out: carry clear
  clobbers: A, flags
```

Open issue: current TECM8 proof code relies on MON3's fixed `DISK_BUFF`. A BIOS
API with caller-supplied `IX` buffers is cleaner, but an early compatibility
shim may still use the MON3 buffer internally.

## GLCD Calls

The GLCD is the primary TECM8 display. TECM8 should keep MON3 GLCD terminal
calls usable and wrap them with clearer contracts where needed.

| Call | TECM8 wrapper | MON3 continuity |
| ---: | --- | --- |
| existing | `TECM8_BIOS_GLCD_INIT` | MON3 GLCD init routine. |
| existing | `TECM8_BIOS_GLCD_CLEAR_TEXT` | MON3 clear text LCD/GLCD text routine. |
| existing | `TECM8_BIOS_GLCD_CLEAR_GRAPHICS` | MON3 clear graphics routine. |
| existing/extension | `TECM8_BIOS_GLCD_SET_CURSOR` | Cursor positioning for terminal output. |
| existing | `TECM8_BIOS_GLCD_PUT_CHAR` | MON3 send-char terminal call. |
| existing | `TECM8_BIOS_GLCD_PUT_STRING` | MON3 send-string terminal call. |
| existing | `TECM8_BIOS_GLCD_PLOT_BUFFER` | MON3 plot graphics buffer routine. |
| existing | `TECM8_BIOS_GLCD_SET_MODE` | MON3 GLCD terminal state get/set behavior. |

Draft contracts:

```text
TECM8_BIOS_GLCD_INIT
  in:  none
  out: carry clear on ready
       carry set, A = error
  clobbers: A, BC, DE, HL, flags

TECM8_BIOS_GLCD_SET_CURSOR
  in:  B = column
       C = row
  out: carry clear on success
       carry set, A = error
  clobbers: A, flags

TECM8_BIOS_GLCD_PUT_CHAR
  in:  A = ASCII character
  out: carry clear on success
       carry set, A = error
  clobbers: A, flags

TECM8_BIOS_GLCD_PUT_STRING
  in:  HL = NUL-terminated ASCII string
  out: carry clear on success
       carry set, A = error
       HL = byte after NUL on success
  clobbers: A, HL, flags

TECM8_BIOS_GLCD_PLOT_BUFFER
  in:  HL = graphics buffer address, or 0000h for BIOS default buffer
  out: carry clear on success
       carry set, A = error
  clobbers: A, BC, DE, HL, flags
```

## Input Calls

The matrix keyboard is the main input device. The BIOS should expose raw and
parsed input, leaving command-line editing to TECM8.

| Call | Name | Purpose |
| ---: | --- | --- |
| `30h` | `TECM8_BIOS_KEY_SCAN_RAW` | Return raw matrix key/modifier state. |
| `31h` | `TECM8_BIOS_KEY_SCAN_ASCII` | Return translated ASCII/key code if available. |
| `32h` | `TECM8_BIOS_KEY_WAIT` | Wait for a key event. |
| `33h` | `TECM8_BIOS_KEY_SET_REPEAT` | Configure repeat timing. |

Draft contracts:

```text
TECM8_BIOS_KEY_SCAN_RAW
  in:  none
  out: carry clear if key event is available
       carry set if no key event is available
       E = primary key
       D = modifier or secondary key
  clobbers: A, DE, flags

TECM8_BIOS_KEY_SCAN_ASCII
  in:  none
  out: carry clear if translated key is available
       carry set if no key event is available
       A = ASCII byte or TECM8 key code
  clobbers: A, DE, HL, flags

TECM8_BIOS_KEY_WAIT
  in:  none
  out: A = ASCII byte or TECM8 key code
  clobbers: A, DE, HL, flags
```

## Serial Calls

Bit-bang serial remains useful for host transfer and diagnostics.

| Call | Name | Purpose |
| ---: | --- | --- |
| `40h` | `TECM8_BIOS_SERIAL_ENABLE` | Enable serial I/O. |
| `41h` | `TECM8_BIOS_SERIAL_DISABLE` | Disable serial I/O. |
| `42h` | `TECM8_BIOS_SERIAL_TX_BYTE` | Send one byte. |
| `43h` | `TECM8_BIOS_SERIAL_RX_BYTE` | Receive one byte. |
| `44h` | `TECM8_BIOS_SERIAL_TX_STRING` | Send a NUL-terminated string. |

Draft contracts:

```text
TECM8_BIOS_SERIAL_TX_BYTE
  in:  A = byte
  out: carry clear on sent
       carry set, A = error
  clobbers: A, BC, flags

TECM8_BIOS_SERIAL_RX_BYTE
  in:  none
  out: carry clear, A = byte
       carry set, A = error or no data
  clobbers: A, BC, flags

TECM8_BIOS_SERIAL_TX_STRING
  in:  HL = NUL-terminated string
  out: carry clear on sent
       carry set, A = error
       HL = byte after NUL on success
  clobbers: A, BC, HL, flags
```

## System Control And Banking Calls

These calls wrap the TEC-1G system latch so callers do not accidentally disturb
unrelated bits.

| Call | Name | Purpose |
| ---: | --- | --- |
| `50h` | `TECM8_BIOS_SYS_GET` | Return cached system control state. |
| `51h` | `TECM8_BIOS_SYS_SET` | Set masked system control bits. |
| `52h` | `TECM8_BIOS_BANK_SELECT` | Select expansion bank. |
| `53h` | `TECM8_BIOS_BANK_CALL` | Call a routine through the banked window. |
| `54h` | `TECM8_BIOS_PROTECT_SET` | Enable or disable protect mode. |
| `55h` | `TECM8_BIOS_SHADOW_SET` | Enable or disable shadow mode. |

Draft contracts:

```text
TECM8_BIOS_SYS_GET
  in:  none
  out: A = cached SYS_CTRL byte
  clobbers: flags

TECM8_BIOS_SYS_SET
  in:  A = new bit values
       B = mask of bits to update
  out: A = resulting SYS_CTRL byte
  clobbers: A, flags

TECM8_BIOS_BANK_SELECT
  in:  A = bank number
  out: carry clear on selected
       carry set, A = error
  clobbers: A, flags

TECM8_BIOS_BANK_CALL
  in:  A = bank number
       HL = routine address inside 8000h-BFFFh window
  out: returns from banked routine with original bank restored
       carry set, A = error if bank cannot be selected
  clobbers: banked routine contract
```

Open issue: `BANK_CALL` needs a stricter contract before implementation. It
may need to preserve more registers than ordinary services because it becomes a
core resident-system primitive.

## Sound, Timing, RTC, Utilities

| Call | Name | Purpose |
| ---: | --- | --- |
| `60h` | `TECM8_BIOS_BEEP` | Short audio feedback. |
| `61h` | `TECM8_BIOS_SOUND_PLAY_NOTE` | Play one note/tone. |
| `62h` | `TECM8_BIOS_DELAY_US` | Busy-wait microsecond delay. |
| `63h` | `TECM8_BIOS_DELAY_MS` | Busy-wait millisecond delay. |
| `64h` | `TECM8_BIOS_RTC_READ` | Read RTC fields or raw bytes. |
| `65h` | `TECM8_BIOS_BYTE_TO_HEX` | Convert byte to two ASCII hex chars. |
| `66h` | `TECM8_BIOS_WORD_TO_HEX` | Convert word to four ASCII hex chars. |
| `67h` | `TECM8_BIOS_RANDOM_BYTE` | Return a small random byte. |

Draft contracts:

```text
TECM8_BIOS_BEEP
  in:  none
  out: carry clear
  clobbers: A, flags

TECM8_BIOS_DELAY_MS
  in:  HL = delay count
  out: carry clear
  clobbers: A, BC, DE, HL, flags

TECM8_BIOS_BYTE_TO_HEX
  in:  A = byte
       DE = destination, at least 2 bytes
  out: DE = byte after written text
  clobbers: A, DE, flags

TECM8_BIOS_WORD_TO_HEX
  in:  HL = word
       DE = destination, at least 4 bytes
  out: DE = byte after written text
  clobbers: A, DE, HL, flags
```

## Compatibility Calls

Compatibility calls should stay low priority. They are useful because the
TEC-1 has seven-segment displays, the hexadecimal keypad, and a character LCD,
but they should not dominate the TECM8 UI.

| Call | Name | Purpose |
| ---: | --- | --- |
| `70h` | `TECM8_BIOS_LCD_PUT_CHAR` | Write one character to the character LCD. |
| `71h` | `TECM8_BIOS_LCD_PUT_STRING` | Write a NUL-terminated string to the LCD. |
| `72h` | `TECM8_BIOS_LCD_COMMAND` | Send LCD command byte. |
| `73h` | `TECM8_BIOS_SEG_SCAN` | Scan seven-segment display buffer. |
| `74h` | `TECM8_BIOS_HEX_KEY_SCAN` | Scan hexadecimal keypad. |
| `75h` | `TECM8_BIOS_TINY_MENU` | Optional compact LCD menu launcher. |

## Resident TECM8 Services

The `80h-8Fh` range is reserved for TECM8 extension services that may migrate
into fixed ROM if they prove broadly useful. These are not MON3 replacements;
they are TECM8 additions layered on top of MON3-compatible services.

| Call | Name | Purpose |
| ---: | --- | --- |
| `80h` | `TECM8_SYS_SHELL_ENTRY` | Enter the resident shell. |
| `81h` | `TECM8_SYS_OPEN_ACTIVE_VOLUME` | Open the active `VOLUME.TM8`. |
| `82h` | `TECM8_SYS_TM8_READ_BLOCK` | Read a TM8 block from the active volume. |
| `83h` | `TECM8_SYS_TM8_WRITE_BLOCK` | Write a TM8 block to the active volume. |
| `84h` | `TECM8_SYS_EDIT_TEXT_FILE` | Enter compact editor core for one file. |
| `85h` | `TECM8_SYS_RUN_COMMAND` | Run a NUL-terminated shell command. |

These calls should not be part of the first BIOS requirement. They record the
second-tier direction: TECM8 may eventually promote shell, filesystem, and
editor services into resident ROM because they are useful beyond the assembler,
while MON3-compatible hardware calls remain available underneath.

## Error Codes

Draft common error codes:

```text
00h  OK
01h  unsupported call
02h  bad argument
03h  buffer too small
04h  device not ready
05h  timeout
06h  media not present
07h  mount failed
08h  file not found
09h  read failed
0Ah  write failed
0Bh  bad bank
0Ch  busy
0Dh  cancelled
0Eh  hardware fault
0Fh  unknown error
```

## Open Decisions

- Whether all final calls stay on MON3 `RST 10h`, or whether TECM8 extension
  calls get a secondary entry point.
- Whether storage should use caller buffers from the start or maintain MON3's
  fixed `DISK_BUFF` as the primary compatibility layer.
- Whether `BANK_CALL` should preserve all primary registers by convention.
- Which GLCD routines are primitives and which belong in the resident TECM8
  system layer.
- Whether the compact LCD menu launcher belongs in compatibility services or
  resident TECM8 services.
- How much of this API should be mirrored in `.asmi` files before code exists.
