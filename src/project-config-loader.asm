; TECM8 project config loader.
;
; Loads /tecm8.prj from the root of VOLUME.TM8 through the TECM8 BIOS storage
; wrappers, then calls the project config parser. This is a deliberately small
; v1 reader: it validates the TM8 superblock fields needed for the fixed catalog
; layout, finds the root file catalog entry for tecm8.prj, and reads one
; 512-byte sector from the entry's first data block.

PROJECT_LOAD_DISK_BUFF .equ  0x0600

PROJECT_LOAD_ROOT_PREFIX .equ 0x00
PROJECT_LOAD_PROJECT_NAME_LEN .equ 9

PROJECT_LOAD_OK         .equ 0
PROJECT_LOAD_ERR_OPEN   .equ 0x20
PROJECT_LOAD_ERR_SUPER  .equ 0x21
PROJECT_LOAD_ERR_FIND   .equ 0x22
PROJECT_LOAD_ERR_SIZE   .equ 0x23
PROJECT_LOAD_ERR_READ   .equ 0x24
PROJECT_LOAD_ERR_BLOCK  .equ 0x25

PROJECT_CFG_TEXT_BUF    .equ 0x0A00

; LoadProjectConfig —
; Open VOLUME.TM8, load /tecm8.prj, parse it, and copy the main path.
; Input:
;   DE = destination buffer for the main path
;   B  = destination byte capacity, including final NUL
; Output:
;   carry clear, A=PROJECT_LOAD_OK, destination is NUL-terminated main path
;   carry set, A=PROJECT_LOAD_ERR_* or PROJECT_CFG_ERR_*
;! in B,DE
;! out A,C,carry,zero
;! clobbers sign,parity,halfCarry,B,DE,HL
@LoadProjectConfig:
        LD      (ProjectLoadMainDest),DE
        LD      A,B
        LD      (ProjectLoadMainCap),A

        LD      HL,ProjectLoadVolumeName
        CALL    BiosFileOpen
        JP      C,ProjectLoadOpenErr

        CALL    ProjectLoadReadSuperblock
        RET     C

        CALL    ProjectLoadFindConfig
        RET     C

        CALL    ProjectLoadReadConfigText
        RET     C

        LD      HL,PROJECT_CFG_TEXT_BUF
        LD      DE,(ProjectLoadMainDest)
        LD      A,(ProjectLoadMainCap)
        LD      B,A
        CALL    ParseProjectConfig
        RET     C

        XOR     A
        RET

ProjectLoadOpenErr:
        LD      A,PROJECT_LOAD_ERR_OPEN
        SCF
        RET

; ProjectLoadReadSuperblock —
; Read sector 0 of VOLUME.TM8 and validate the fixed v1 fields needed here.
;! out A,carry,zero
;! clobbers sign,parity,halfCarry,DE,HL
@ProjectLoadReadSuperblock:
        LD      HL,0
        LD      DE,0
        CALL    BiosFileReadSector
        JP      C,ProjectLoadReadErr

        LD      HL,PROJECT_LOAD_DISK_BUFF
        CALL    Tecm8StorageValidateCoreSuperblock
        JR      C,ProjectLoadSuperErr
        XOR     A
        RET

ProjectLoadSuperErr:
        LD      A,PROJECT_LOAD_ERR_SUPER
        SCF
        RET

ProjectLoadReadErr:
        LD      A,PROJECT_LOAD_ERR_READ
        SCF
        RET

; ProjectLoadFindConfig —
; Scan the v1 file catalog for root file tecm8.prj.
;! out HL,A,carry,zero
;! clobbers sign,parity,halfCarry,BC,DE
@ProjectLoadFindConfig:
        LD      DE,TM8_CATALOG_SECTOR * TM8_SECTOR_BYTES
        LD      A,TM8_CATALOG_SECTORS
        LD      (ProjectLoadCatalogLeft),A

ProjectLoadCatalogSector:
        CALL    Tecm8StorageReadSectorPreserveOffset
        JP      C,ProjectLoadReadErr

        LD      HL,PROJECT_LOAD_DISK_BUFF
        LD      BC,TM8_ENTRIES_SECTOR * 256

ProjectLoadCatalogEntry:
        PUSH    BC
        PUSH    DE
        PUSH    HL
        CALL    ProjectLoadMatchCatalogEntry
        POP     HL
        POP     DE
        POP     BC
        RET     NC
        CP      PROJECT_LOAD_ERR_SIZE
        RET     Z
        CP      PROJECT_LOAD_ERR_BLOCK
        RET     Z

        CALL    Tecm8StorageAdvanceCatalogEntryPtr
        DJNZ    ProjectLoadCatalogEntry

        CALL    Tecm8StorageAdvanceSectorOffset
        LD      A,(ProjectLoadCatalogLeft)
        DEC     A
        LD      (ProjectLoadCatalogLeft),A
        JR      NZ,ProjectLoadCatalogSector

        LD      A,PROJECT_LOAD_ERR_FIND
        SCF
        RET

; ProjectLoadMatchCatalogEntry —
; Check one 64-byte catalog entry at HL for root tecm8.prj.
; Output: carry clear on match and ProjectLoadFirstBlock/Size set.
;! in HL
;! out A,carry,zero
;! clobbers sign,parity,halfCarry,DE,HL
@ProjectLoadMatchCatalogEntry:
        LD      (ProjectLoadEntryBase),HL
        LD      A,(HL)
        CP      TM8_ENTRY_ACTIVE
        JR      NZ,ProjectLoadEntryNo

        INC     HL
        INC     HL
        LD      A,(HL)
        CP      PROJECT_LOAD_ROOT_PREFIX
        JR      NZ,ProjectLoadEntryNo

        INC     HL
        LD      A,(HL)
        CP      PROJECT_LOAD_PROJECT_NAME_LEN
        JR      NZ,ProjectLoadEntryNo

        INC     HL
        LD      DE,ProjectLoadFileName
        LD      B,PROJECT_LOAD_PROJECT_NAME_LEN
        CALL    Tecm8StringMatchBytes
        JR      C,ProjectLoadEntryNo

        LD      HL,(ProjectLoadEntryBase)
        LD      DE,44
        ADD     HL,DE

        LD      E,(HL)
        INC     HL
        LD      D,(HL)
        INC     HL
        LD      A,D
        CP      4
        JR      NC,ProjectLoadBlockErr
        LD      A,D
        OR      A
        JR      NZ,ProjectLoadFirstBlockOk
        LD      A,E
        CP      10
        JR      C,ProjectLoadBlockErr

ProjectLoadFirstBlockOk:
        LD      (ProjectLoadFirstBlock),DE
        LD      HL,(ProjectLoadEntryBase)
        LD      DE,46
        ADD     HL,DE
        LD      E,(HL)
        INC     HL
        LD      D,(HL)
        LD      A,D
        CP      2
        JP      NC,ProjectLoadSizeErr
        INC     HL
        LD      (ProjectLoadFileSize),DE

        LD      A,(HL)
        OR      A
        JR      NZ,ProjectLoadSizeErr
        INC     HL
        LD      A,(HL)
        OR      A
        JR      NZ,ProjectLoadSizeErr

        XOR     A
        RET

ProjectLoadEntryNo:
        SCF
        RET

ProjectLoadSizeErr:
        LD      A,PROJECT_LOAD_ERR_SIZE
        SCF
        RET

ProjectLoadBlockErr:
        LD      A,PROJECT_LOAD_ERR_BLOCK
        SCF
        RET

; ProjectLoadReadConfigText —
; Read the first sector of the config file's first block and NUL-terminate the
; exact byte count in PROJECT_CFG_TEXT_BUF.
;! out carry,zero,A
;! clobbers sign,parity,halfCarry,BC,DE,HL
@ProjectLoadReadConfigText:
        LD      HL,(ProjectLoadFirstBlock)
        CALL    Tecm8StorageBlockToOffset
        CALL    BiosFileReadSector
        JP      C,ProjectLoadReadErr

        LD      HL,PROJECT_LOAD_DISK_BUFF
        LD      DE,PROJECT_CFG_TEXT_BUF
        LD      BC,(ProjectLoadFileSize)
        LD      A,B
        OR      C
        JR      Z,ProjectLoadEmptyText
        LDIR

ProjectLoadEmptyText:
        XOR     A
        LD      (DE),A
        RET

ProjectLoadVolumeName:
        .db     "VOLUME.TM8",0

ProjectLoadFileName:
        .db     "tecm8.prj"

ProjectLoadMainDest:
        .dw     0

ProjectLoadFirstBlock:
        .dw     0

ProjectLoadFileSize:
        .dw     0

ProjectLoadMainCap:
        .db     0

ProjectLoadCatalogLeft:
        .db     0

ProjectLoadEntryBase:
        .dw     0
