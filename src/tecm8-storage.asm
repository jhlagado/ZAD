; TECM8 shared TM8 storage helpers.
;
; These routines hold format-level helpers that are shared by the project
; loader, editor storage loader, and future shell/filesystem paths.

TM8_SECTOR_BYTES        .equ    TECM8_SECTOR_BYTES
TM8_BLOCK_BYTES         .equ    TECM8_SECTOR_BYTES * 8
TM8_TOTAL_BLOCKS        .equ    1024
TM8_VOLUME_BYTE_2       .equ    0x40
TM8_ALLOC_START_BLOCK   .equ    1
TM8_ALLOC_BLOCKS        .equ    1
TM8_PREFIX_START_BLOCK  .equ    2
TM8_PREFIX_BLOCKS       .equ    4
TM8_PREFIX_SECTOR       .equ    16
TM8_PREFIX_SECTORS      .equ    32
TM8_PREFIX_ENTRY        .equ    128
TM8_PREFIX_COUNT        .equ    128
TM8_PREFIXES_SECTOR     .equ    4
TM8_CATALOG_START_BLOCK .equ    6
TM8_CATALOG_BLOCKS      .equ    4
TM8_CATALOG_SECTOR      .equ    48
TM8_CATALOG_SECTORS     .equ    32
TM8_CATALOG_ENTRY       .equ    64
TM8_CATALOG_COUNT       .equ    256
TM8_ENTRIES_SECTOR      .equ    8
TM8_DATA_START_BLOCK    .equ    10

TM8_ENTRY_ACTIVE        .equ    0x01
TM8_CATALOG_NAME_BYTES  .equ    40
TM8_PREFIX_TEXT_BYTES   .equ    121

; Tecm8StorageValidateCoreSuperblock -
; Validate the TM8 v1 fields shared by all current readers.
; Input:
;   HL = sector-0 buffer
; Output:
;   carry clear if the core fields match the fixed v1 layout
;   carry set if any checked field is invalid
;! in HL
;! out A,carry,zero
;! clobbers sign,parity,halfCarry,B,DE,HL
@Tecm8StorageValidateCoreSuperblock:
        PUSH    HL
        LD      DE,Tecm8StorageMagic
        LD      B,8
        CALL    Tecm8StringMatchBytes
        POP     HL
        RET     C

        LD      DE,8
        ADD     HL,DE
        LD      A,(HL)
        CP      1
        JR      NZ,Tecm8StorageCoreSuperErr
        INC     HL
        LD      A,(HL)
        OR      A
        JR      NZ,Tecm8StorageCoreSuperErr

        INC     HL
        LD      A,(HL)
        OR      A
        JR      NZ,Tecm8StorageCoreSuperErr
        INC     HL
        LD      A,(HL)
        CP      2
        JR      NZ,Tecm8StorageCoreSuperErr

        LD      DE,21
        ADD     HL,DE
        LD      A,(HL)
        CP      TM8_CATALOG_START_BLOCK
        JR      NZ,Tecm8StorageCoreSuperErr
        INC     HL
        LD      A,(HL)
        OR      A
        JR      NZ,Tecm8StorageCoreSuperErr

        LD      DE,3
        ADD     HL,DE
        LD      A,(HL)
        CP      TM8_CATALOG_ENTRY
        JR      NZ,Tecm8StorageCoreSuperErr
        INC     HL
        LD      A,(HL)
        OR      A
        JR      NZ,Tecm8StorageCoreSuperErr

        XOR     A
        RET

Tecm8StorageCoreSuperErr:
        SCF
        RET

; Tecm8StorageAdvanceSectorOffset -
; Advance a MON3 byte offset in DE by one TM8 sector.
;! in DE
;! out DE
;! clobbers B,C,H,L,F
@Tecm8StorageAdvanceSectorOffset:
        EX      DE,HL
        LD      BC,TM8_SECTOR_BYTES
        ADD     HL,BC
        EX      DE,HL
        RET

; Tecm8StorageBlockToOffset —
; Convert a 4K TM8 block number in HL to MON3 HLDE byte offset.
;! in HL
;! out DE,HL
;! clobbers A,F
@Tecm8StorageBlockToOffset:
        LD      A,L
        AND     0x0F
        RLCA
        RLCA
        RLCA
        RLCA
        LD      D,A
        LD      E,0

        LD      A,H
        RRCA
        RRCA
        RRCA
        RRCA
        AND     0xF0
        LD      H,A
        LD      A,L
        RRCA
        RRCA
        RRCA
        RRCA
        AND     0x0F
        OR      H
        LD      L,A
        LD      H,0
        RET

Tecm8StorageMagic:
        .db     "TECM8VOL"
