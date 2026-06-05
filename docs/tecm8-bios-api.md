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
        LD      C,BiosDisplayPutChar
        LD      A,"A"
        RST     0x10
```

The existing MON3 `RST 10h` convention should be preserved unless there is a
strong reason to add a new entry point. Direct-call entry points and TECM8
external routines should publish AZM `.asmi` interfaces so TECM8 code can
use register-care contracts for monitor services. RST-numbered MON3 services
are handled by AZM's `mon3` register-contracts profile when the service number
is loaded into `C` immediately before `RST 10h`.

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
| existing/direct | `BiosSdInit` | Initialize SD hardware and verify card readiness. |
| existing/direct | `BiosFatMount` | Mount the FAT32 volume and cache needed geometry. |
| existing/direct | `BiosFileOpen` | Open a FAT32 file by path/name for sector access. |
| existing/direct | `BiosFileReadSector` | Read a 512-byte sector from the open file. |
| existing/direct | `BiosFileWriteSector` | Write a 512-byte sector to the open file. |
| extension | `BiosFileClose` | Close or invalidate the current file handle. |

Draft contracts:

```text
BiosSdInit
  in:  none
  out: carry clear on ready
       carry set, A = error
  clobbers: A, BC, DE, HL, flags

BiosFatMount
  in:  none
  out: carry clear on mounted
       carry set, A = error
  clobbers: A, BC, DE, HL, flags

BiosFileOpen
  in:  HL = NUL-terminated FAT32 filename/path
  out: carry clear on open
       carry set, A = error
  clobbers: A, BC, DE, HL, flags

BiosFileReadSector
  in:  HLDE = byte offset within open file, 512-byte aligned
  out: carry clear on read
       sector bytes loaded into MON3-compatible DISK_BUFF
       carry set, A = error
  clobbers: A, BC, DE, HL, flags

BiosFileWriteSector
  in:  HLDE = byte offset within open file, 512-byte aligned
       sector bytes already staged in MON3-compatible DISK_BUFF
  out: carry clear on write
       carry set, A = error
  clobbers: A, BC, DE, HL, flags

BiosFileClose
  in:  none
  out: carry clear
  clobbers: A, flags
```

The current external interface is [src/mon3.asmi](../src/mon3.asmi). The first
implementation module is [src/tecm8-bios.asm](../src/tecm8-bios.asm), which
currently keeps the storage wrappers as thin MON3-compatible calls. TECM8-owned
wrapper contracts live in local AZMDoc `;!` blocks, not duplicate interface
files.

Open issue: current TECM8 proof code relies on MON3's fixed `DISK_BUFF`. A
future wrapper could add caller-supplied buffers, but the compatibility layer
should keep the MON3 buffer convention until measurement or implementation
pressure justifies changing it.

RAM note: MON3's storage package uses more than the 512-byte `DISK_BUFF`.
Current MON3 source places the FAT/PATA/SD workspace roughly at `0100h-07FFh`,
with `DISK_BUFF` at `0600h-07FFh`. TECM8 code that calls MON3-compatible
storage should treat this range as BIOS-owned or volatile.

## Display Calls

The GLCD is the primary first display, but TECM8 code should target a small
display contract rather than hard-code MON3's GLCD routine names. The first
implementation is MON3-backed and GLCD-oriented; later implementations may
route the same names to a smaller TECM8 GLCD renderer or to a TMS9918-style VDU
layer.

| Call | TECM8 wrapper | MON3 continuity |
| ---: | --- | --- |
| existing | `BiosDisplayInit` | Initializes MON3's GLCD terminal path. |
| existing | `BiosDisplayClear` | Reinitializes/clears the MON3 GLCD terminal buffer. |
| existing/extension | `BiosDisplaySetCursor` | Uses MON3 graphics cursor coordinates. |
| existing | `BiosDisplayPutChar` | Sends one character through the MON3 GLCD terminal. |
| existing | `BiosDisplayPutString` | Sends a NUL-terminated string through the MON3 GLCD terminal. |
| existing/extension | `BiosDisplayDrawCharAt` | Draws one 6x6 GLCD font character at pixel coordinates without terminal scrollback. |
| existing | `BiosDisplayUpdate` | Plots the current MON3 GLCD viewport to the display. |
| existing | `BiosDisplaySetBitmapMode` | Selects MON3 GLCD graphics mode for bitmap operations. |

Current prototype contracts:

```text
BiosDisplayInit
  in:  none
  out: carry clear on ready
  clobbers: A, BC, DE, HL, flags

BiosDisplayClear
  in:  none
  out: carry clear on success
  clobbers: A, BC, DE, HL, flags

BiosDisplaySetCursor
  in:  B = X pixel
       C = Y pixel
  out: carry clear on success
  clobbers: A, BC, DE, HL, flags

BiosDisplayPutChar
  in:  A = ASCII character
  out: carry clear on success
  clobbers: A, BC, DE, HL, flags

BiosDisplayPutString
  in:  HL = NUL-terminated ASCII string
  out: carry clear on success
  clobbers: A, BC, DE, HL, flags

BiosDisplayDrawCharAt
  in:  A = ASCII character
       B = X pixel
       C = Y pixel
  out: carry clear on success
       carry set, A = range error if B >= 128 or C >= 64
  clobbers: A, BC, DE, HL, flags

BiosDisplayUpdate
  in:  none
  out: carry clear on success
  clobbers: A, BC, DE, HL, flags

BiosDisplaySetBitmapMode
  in:  none
  out: carry clear on success
  clobbers: A, BC, DE, HL, flags
```

Most current MON3-backed display wrappers are success-only and clear carry after
returning from MON3. `BiosDisplayDrawCharAt` is the current exception:
it performs wrapper-level coordinate validation and returns carry set with a
compact range error before calling MON3 when the requested pixel position is
outside the 128x64 GLCD area. A later TECM8-native display driver can add more
meaningful carry-set errors if it has detectable failure modes.

Legacy `TECM8_BIOS_GLCD_*` names may remain useful as aliases if direct MON3
compatibility becomes valuable, but new TECM8 code should prefer the
`BiosDisplay*` contract.

RAM note: MON3's GLCD library effectively uses `0A00h-17FFh` as a video
workspace, a 3584-byte 3.5 KiB range containing a full graphics buffer,
terminal scroll buffer, terminal graphics buffer, and cursor/drawing state. A
future TECM8-focused display BIOS may keep these MON3 calls for compatibility
while adding a smaller text-first path that does not require the full workspace.

## Input Calls

The matrix keyboard is the main input device. The BIOS should expose raw and
parsed input, leaving command-line editing to TECM8.

| Call | Name | Purpose |
| ---: | --- | --- |
| `30h` | `TECM8_BIOS_KEY_SCAN_RAW` | Return raw matrix key/modifier state. |
| `31h` | `TECM8_BIOS_KEY_SCAN_ASCII` | Return translated ASCII/key code if available. |
| `32h` | `TECM8_BIOS_KEY_WAIT` | Wait for a key event. |
| `33h` | `TECM8_BIOS_KEY_SET_REPEAT` | Configure repeat timing. |
| existing/direct | `BiosInputPollAscii` | Poll MON3 `matrixScan` + `parseMatrixScan` once. |

Draft contracts:

```text
TECM8_BIOS_KEY_SCAN_RAW
  in:  none
  out: carry set if key event is available
       carry clear if no key event is available
       E = primary key
       D = modifier or secondary key
  clobbers: A, DE, flags

TECM8_BIOS_KEY_SCAN_ASCII
  in:  none
  out: carry set if translated key is available
       carry clear if no key event is available
       A = ASCII byte or TECM8 key code
  clobbers: A, DE, HL, flags

BiosInputPollAscii
  in:  none
  out: carry set if MON3 returned debounced ASCII in A
       carry clear if no ASCII key is ready
  clobbers: A, BC, DE, HL, flags

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
| `52h` | `BiosBankSelect` | Select expansion bank. |
| `53h` | `BiosBankCall` | Call a routine through the banked window. |
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

BiosBankSelect
  in:  A = bank number
  out: carry clear on selected
       carry set, A = error
  clobbers: A, flags

BiosBankCall
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
- Whether a later storage wrapper should add caller buffers above MON3's fixed
  `DISK_BUFF` compatibility layer.
- Whether `BANK_CALL` should preserve all primary registers by convention.
- Which GLCD routines are primitives and which belong in the resident TECM8
  system layer.
- Whether the compact LCD menu launcher belongs in compatibility services or
  resident TECM8 services.
- How much of this API should be mirrored in `.asmi` files before external code
  exists.
