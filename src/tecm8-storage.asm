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
