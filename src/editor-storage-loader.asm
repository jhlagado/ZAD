; TECM8 editor source-sector loader.
;
; Proof-focused loader for source files in VOLUME.TM8. It opens the MON3
; FAT32 file, finds the requested prefix and filename, follows the TM8
; allocation chain, and copies one 512-byte source page to a caller buffer.

DISK_BUFF               .equ    0x0600

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
TM8_SOURCE_MIN_BYTES    .equ    256
TM8_CATALOG_NAME_BYTES  .equ    40
TM8_PREFIX_TEXT_BYTES   .equ    121

EDITOR_LOAD_OK          .equ    0
EDITOR_LOAD_ERR_OPEN    .equ    0x30
EDITOR_LOAD_ERR_SUPER   .equ    0x31
EDITOR_LOAD_ERR_PREFIX  .equ    0x32
EDITOR_LOAD_ERR_FIND    .equ    0x33
EDITOR_LOAD_ERR_SIZE    .equ    0x34
EDITOR_LOAD_ERR_READ    .equ    0x35
EDITOR_LOAD_ERR_BLOCK   .equ    0x36
EDITOR_LOAD_ERR_PAGE    .equ    0x37
EDITOR_LOAD_ERR_WRITE   .equ    0x38
EDITOR_LOAD_ERR_CREATE  .equ    0x39

; EditorLoadMainSector -
; Load the first sector of /src/main.asm into caller buffer HL.
;! in HL
;! out A,carry
;! clobbers zero,sign,parity,halfCarry,BC,DE,HL
@EditorLoadMainSector:
        XOR     A
        JP      EditorLoadMainPage

; EditorLoadMainPage -
; Load one 512-byte sector page of /src/main.asm into caller buffer HL.
; Page A is limited to 0..127.
;! in A,HL
;! out A,carry
;! clobbers zero,sign,parity,halfCarry,BC,DE,HL
@EditorLoadMainPage:
        LD      DE,EditorLoadMainPath
        JP      EditorLoadSourcePage

; EditorLoadSourcePage -
; Load one 512-byte sector page of a source file into caller buffer HL.
; Input:
;   A  = page index, limited to 0..127
;   DE = NUL-terminated TM8 path, e.g. /src/main.asm
;   HL = caller destination buffer
;! in A,DE,HL
;! out A,carry,zero
;! clobbers sign,parity,halfCarry,BC,DE,HL
@EditorLoadSourcePage:
        PUSH    AF
        XOR     A
        LD      (EditorLoadAllowShort),A
        LD      (EditorSaveGrowMode),A
        POP     AF
        LD      (EditorLoadSectorIndex),A
        LD      (EditorLoadDest),HL
        LD      (EditorLoadSourcePathPtr),DE
        CP      128
        JP      NC,EditorLoadPageErr
        AND     7
        LD      (EditorLoadSectorInBlock),A
        LD      A,(EditorLoadSectorIndex)
        RRCA
        RRCA
        RRCA
        AND     0x1F
        LD      (EditorLoadBlockSteps),A
        LD      A,(EditorLoadSectorIndex)
        ADD     A,A
        INC     A
        LD      (EditorLoadRequiredSizeHigh),A

        CALL    EditorLoadParseSourcePath
        RET     C

        LD      HL,EditorLoadVolumeName
        CALL    BiosFileOpen
        JP      C,EditorLoadOpenErr

        CALL    EditorLoadReadSuperblock
        RET     C
        LD      A,(EditorLoadPrefixLen)
        OR      A
        JR      Z,EditorLoadRootPrefix
        CALL    EditorLoadFindSourcePrefix
        RET     C
        JR      EditorLoadPrefixReady

EditorLoadRootPrefix:
        LD      (EditorLoadSrcPrefixId),A

EditorLoadPrefixReady:
        CALL    EditorLoadFindSource
        RET     C
        CALL    EditorLoadReadSourceSector
        RET     C
        XOR     A
        RET

; EditorSaveSourcePage -
; Save one 512-byte sector page from caller buffer HL into a source file.
; Input:
;   A  = page index, limited to 0..127
;   DE = NUL-terminated TM8 path, e.g. /src/main.asm
;   HL = caller source buffer
;! in A,DE,HL
;! out A,carry
;! clobbers BC,DE,HL,zero,sign,parity,halfCarry
@EditorSaveSourcePage:
        PUSH    AF
        LD      A,1
        LD      (EditorSaveGrowMode),A
        POP     AF
        JR      EditorSaveSourcePageCommon

; EditorSaveSourcePageNoGrow -
; Save one sector without catalog-size growth. Used by fixed-size backup files.
;! in A,DE,HL
;! out A,carry,zero
;! clobbers sign,parity,halfCarry,BC,DE,HL
@EditorSaveSourcePageNoGrow:
        PUSH    AF
        XOR     A
        LD      (EditorSaveGrowMode),A
        POP     AF

EditorSaveSourcePageCommon:
        LD      (EditorLoadSectorIndex),A
        LD      (EditorLoadDest),HL
        LD      (EditorLoadSourcePathPtr),DE
        LD      A,1
        LD      (EditorLoadAllowShort),A
        LD      A,(EditorLoadSectorIndex)
        CP      128
        JP      NC,EditorLoadPageErr
        AND     7
        LD      (EditorLoadSectorInBlock),A
        LD      A,(EditorLoadSectorIndex)
        RRCA
        RRCA
        RRCA
        AND     0x1F
        LD      (EditorLoadBlockSteps),A
        LD      A,(EditorLoadSectorIndex)
        ADD     A,A
        INC     A
        LD      (EditorLoadRequiredSizeHigh),A
        ADD     A,1
        LD      (EditorSaveRequiredSizeHigh),A
        LD      A,0
        ADC     A,0
        LD      (EditorSaveRequiredSizeUpper),A

        CALL    EditorLoadParseSourcePath
        RET     C

        LD      HL,EditorLoadVolumeName
        CALL    BiosFileOpen
        JP      C,EditorLoadOpenErr

        CALL    EditorLoadReadSuperblock
        RET     C
        LD      A,(EditorLoadPrefixLen)
        OR      A
        JR      Z,EditorSaveRootPrefix
        CALL    EditorLoadFindSourcePrefix
        RET     C
        JR      EditorSavePrefixReady

EditorSaveRootPrefix:
        LD      (EditorLoadSrcPrefixId),A

EditorSavePrefixReady:
        CALL    EditorLoadFindSource
        RET     C
        CALL    EditorLoadWriteSourceSector
        RET     C
        LD      A,(EditorSaveGrowMode)
        OR      A
        JR      Z,EditorSaveSourcePageClean
        CALL    EditorSaveExtendCatalogSize
        RET     C

EditorSaveSourcePageClean:
        XOR     A
        RET

; EditorCreateSourceFile -
; Create a one-block source file for an already-existing TM8 prefix.
; Input:
;   DE = NUL-terminated TM8 path, e.g. /src/.main.asm.b
;! in DE
;! out A,carry,zero
;! clobbers sign,parity,halfCarry,BC,DE,HL
@EditorCreateSourceFile:
        LD      (EditorLoadSourcePathPtr),DE
        CALL    EditorLoadParseSourcePath
        RET     C

        LD      HL,EditorLoadVolumeName
        CALL    BiosFileOpen
        JP      C,EditorLoadOpenErr

        CALL    EditorLoadReadSuperblock
        RET     C
        LD      A,(EditorLoadPrefixLen)
        OR      A
        JR      Z,EditorCreateRootPrefix
        CALL    EditorLoadFindSourcePrefix
        RET     C
        JR      EditorCreatePrefixReady

EditorCreateRootPrefix:
        LD      (EditorLoadSrcPrefixId),A

EditorCreatePrefixReady:
        CALL    EditorCreateFindCatalogSlot
        RET     C
        CALL    EditorCreateNextFileId
        RET     C
        CALL    EditorCreateFindFreeBlock
        RET     C
        CALL    EditorCreateMarkAllocatedBlock
        RET     C
        CALL    EditorCreateWriteCatalogEntry
        RET     C
        CALL    EditorCreateUpdateSuperblock
        RET     C
        JP      EditorCreateBlankCreatedSource

EditorLoadOpenErr:
        LD      A,EDITOR_LOAD_ERR_OPEN
        SCF
        RET

EditorLoadPageErr:
        LD      A,EDITOR_LOAD_ERR_PAGE
        SCF
        RET

;! out A,carry,zero
;! clobbers sign,parity,halfCarry,B,DE,HL
@EditorLoadReadSuperblock:
        LD      HL,0
        LD      DE,0
        CALL    BiosFileReadSector
        JP      C,EditorLoadReadErr

        LD      HL,DISK_BUFF
        LD      DE,EditorLoadMagic
        LD      B,8
        CALL    Tecm8StringMatchBytes
        JP      C,EditorLoadSuperErr

        LD      HL,DISK_BUFF + 8
        LD      A,(HL)
        CP      1
        JP      NZ,EditorLoadSuperErr
        INC     HL
        LD      A,(HL)
        OR      A
        JP      NZ,EditorLoadSuperErr

        LD      HL,DISK_BUFF + 10
        LD      A,(HL)
        OR      A
        JP      NZ,EditorLoadSuperErr
        INC     HL
        LD      A,(HL)
        CP      2
        JP      NZ,EditorLoadSuperErr

        LD      HL,DISK_BUFF + 12
        LD      A,(HL)
        OR      A
        JP      NZ,EditorLoadSuperErr
        INC     HL
        LD      A,(HL)
        CP      16
        JP      NZ,EditorLoadSuperErr

        LD      HL,DISK_BUFF + 14
        LD      A,(HL)
        OR      A
        JP      NZ,EditorLoadSuperErr
        INC     HL
        LD      A,(HL)
        CP      4
        JP      NZ,EditorLoadSuperErr

        LD      HL,DISK_BUFF + 16
        LD      A,(HL)
        OR      A
        JP      NZ,EditorLoadSuperErr
        INC     HL
        LD      A,(HL)
        OR      A
        JP      NZ,EditorLoadSuperErr
        INC     HL
        LD      A,(HL)
        CP      TM8_VOLUME_BYTE_2
        JP      NZ,EditorLoadSuperErr
        INC     HL
        LD      A,(HL)
        OR      A
        JP      NZ,EditorLoadSuperErr

        LD      HL,DISK_BUFF + 20
        LD      A,(HL)
        CP      TM8_ALLOC_START_BLOCK
        JP      NZ,EditorLoadSuperErr
        INC     HL
        LD      A,(HL)
        OR      A
        JP      NZ,EditorLoadSuperErr

        LD      HL,DISK_BUFF + 22
        LD      A,(HL)
        CP      TM8_ALLOC_BLOCKS
        JP      NZ,EditorLoadSuperErr
        INC     HL
        LD      A,(HL)
        OR      A
        JP      NZ,EditorLoadSuperErr

        LD      HL,DISK_BUFF + 24
        LD      A,(HL)
        CP      TM8_PREFIX_START_BLOCK
        JP      NZ,EditorLoadSuperErr
        INC     HL
        LD      A,(HL)
        OR      A
        JP      NZ,EditorLoadSuperErr

        LD      HL,DISK_BUFF + 26
        LD      A,(HL)
        CP      TM8_PREFIX_BLOCKS
        JP      NZ,EditorLoadSuperErr
        INC     HL
        LD      A,(HL)
        OR      A
        JP      NZ,EditorLoadSuperErr

        LD      HL,DISK_BUFF + 28
        LD      A,(HL)
        CP      TM8_PREFIX_ENTRY
        JP      NZ,EditorLoadSuperErr
        INC     HL
        LD      A,(HL)
        OR      A
        JP      NZ,EditorLoadSuperErr

        LD      HL,DISK_BUFF + 30
        LD      A,(HL)
        CP      TM8_PREFIX_COUNT
        JP      NZ,EditorLoadSuperErr
        INC     HL
        LD      A,(HL)
        OR      A
        JP      NZ,EditorLoadSuperErr

        LD      HL,DISK_BUFF + 32
        LD      A,(HL)
        CP      TM8_CATALOG_START_BLOCK
        JP      NZ,EditorLoadSuperErr
        INC     HL
        LD      A,(HL)
        OR      A
        JR      NZ,EditorLoadSuperErr

        LD      HL,DISK_BUFF + 34
        LD      A,(HL)
        CP      TM8_CATALOG_BLOCKS
        JR      NZ,EditorLoadSuperErr
        INC     HL
        LD      A,(HL)
        OR      A
        JR      NZ,EditorLoadSuperErr

        LD      HL,DISK_BUFF + 36
        LD      A,(HL)
        CP      TM8_CATALOG_ENTRY
        JR      NZ,EditorLoadSuperErr
        INC     HL
        LD      A,(HL)
        OR      A
        JR      NZ,EditorLoadSuperErr

        LD      HL,DISK_BUFF + 38
        LD      A,(HL)
        OR      A
        JR      NZ,EditorLoadSuperErr
        INC     HL
        LD      A,(HL)
        CP      1
        JR      NZ,EditorLoadSuperErr

        LD      HL,DISK_BUFF + 40
        LD      A,(HL)
        CP      TM8_DATA_START_BLOCK
        JR      NZ,EditorLoadSuperErr
        INC     HL
        LD      A,(HL)
        OR      A
        JR      NZ,EditorLoadSuperErr

        XOR     A
        RET

EditorLoadSuperErr:
        LD      A,EDITOR_LOAD_ERR_SUPER
        SCF
        RET

EditorLoadReadErr:
        LD      A,EDITOR_LOAD_ERR_READ
        SCF
        RET

EditorLoadWriteErr:
        LD      A,EDITOR_LOAD_ERR_WRITE
        SCF
        RET

EditorLoadCreateErr:
        LD      A,EDITOR_LOAD_ERR_CREATE
        SCF
        RET

;! out A,carry,zero
;! clobbers sign,parity,halfCarry,BC,DE,HL
@EditorLoadParseSourcePath:
        LD      HL,(EditorLoadSourcePathPtr)
        LD      A,(HL)
        CP      "/"
        JP      NZ,EditorLoadFindErr
        INC     HL
        LD      (EditorLoadPrefixPtr),HL
        LD      (EditorLoadNamePtr),HL
        XOR     A
        LD      (EditorLoadPrefixLen),A
        LD      B,0

EditorLoadParsePath:
        LD      A,(HL)
        OR      A
        JR      Z,EditorLoadParsePathDone
        CP      "/"
        JR      Z,EditorLoadParseSlash
        INC     B
        INC     HL
        JR      EditorLoadParsePath

EditorLoadParseSlash:
        LD      A,B
        LD      (EditorLoadPrefixLen),A
        INC     HL
        LD      (EditorLoadNamePtr),HL
        INC     B
        JP      Z,EditorLoadFindErr
        JR      EditorLoadParsePath

EditorLoadParsePathDone:
        LD      A,B
        OR      A
        JP      Z,EditorLoadFindErr
        LD      C,A
        LD      A,(EditorLoadPrefixLen)
        CP      TM8_PREFIX_TEXT_BYTES + 1
        JP      NC,EditorLoadFindErr
        OR      A
        JR      Z,EditorLoadParseRootName
        LD      D,A
        LD      A,C
        SUB     D
        JP      C,EditorLoadFindErr
        DEC     A
        JR      EditorLoadParseStoreNameLen

EditorLoadParseRootName:
        LD      A,C

EditorLoadParseStoreNameLen:
        OR      A
        JP      Z,EditorLoadFindErr
        CP      TM8_CATALOG_NAME_BYTES + 1
        JP      NC,EditorLoadFindErr
        LD      (EditorLoadNameLen),A
        XOR     A
        RET

;! out HL,A,carry,zero
;! clobbers sign,parity,halfCarry,BC,DE
@EditorLoadFindSourcePrefix:
        LD      DE,TM8_PREFIX_SECTOR * TM8_SECTOR_BYTES
        LD      A,TM8_PREFIX_SECTORS
        LD      (EditorLoadSectorsLeft),A

EditorLoadPrefixSector:
        PUSH    DE
        LD      HL,0
        CALL    BiosFileReadSector
        POP     DE
        JP      C,EditorLoadReadErr

        LD      HL,DISK_BUFF
        LD      BC,TM8_PREFIXES_SECTOR * 256

EditorLoadPrefixEntry:
        PUSH    BC
        PUSH    DE
        PUSH    HL
        CALL    EditorLoadMatchPrefixEntry
        POP     HL
        POP     DE
        POP     BC
        RET     NC

        LD      DE,TM8_PREFIX_ENTRY
        ADD     HL,DE
        DJNZ    EditorLoadPrefixEntry

        EX      DE,HL
        LD      BC,TM8_SECTOR_BYTES
        ADD     HL,BC
        EX      DE,HL
        LD      A,(EditorLoadSectorsLeft)
        DEC     A
        LD      (EditorLoadSectorsLeft),A
        JR      NZ,EditorLoadPrefixSector

        LD      A,EDITOR_LOAD_ERR_PREFIX
        SCF
        RET

;! in HL
;! out A,carry,zero
;! clobbers sign,parity,halfCarry,B,DE,HL
@EditorLoadMatchPrefixEntry:
        LD      A,(HL)
        CP      TM8_ENTRY_ACTIVE
        JP      NZ,EditorLoadEntryNo
        INC     HL
        LD      A,(HL)
        LD      (EditorLoadSrcPrefixId),A
        INC     HL
        LD      A,(HL)
        LD      B,A
        LD      A,(EditorLoadPrefixLen)
        CP      B
        JP      NZ,EditorLoadEntryNo
        INC     HL
        LD      DE,(EditorLoadPrefixPtr)
        LD      A,(EditorLoadPrefixLen)
        LD      B,A
        CALL    Tecm8StringMatchBytes
        RET     NC
        JP      EditorLoadEntryNo

;! out HL,A,carry,zero
;! clobbers sign,parity,halfCarry,BC,DE
@EditorLoadFindSource:
        LD      DE,TM8_CATALOG_SECTOR * TM8_SECTOR_BYTES
        LD      A,TM8_CATALOG_SECTORS
        LD      (EditorLoadSectorsLeft),A

EditorLoadCatalogSector:
        PUSH    DE
        LD      HL,0
        CALL    BiosFileReadSector
        POP     DE
        JP      C,EditorLoadReadErr

        LD      HL,DISK_BUFF
        LD      BC,TM8_ENTRIES_SECTOR * 256

EditorLoadCatalogEntry:
        PUSH    BC
        PUSH    DE
        PUSH    HL
        CALL    EditorLoadMatchCatalogEntry
        POP     HL
        POP     DE
        POP     BC
        JR      C,EditorLoadCatalogEntryMiss
        LD      (EditorLoadCatalogSectorOffset),DE
        XOR     A
        RET

EditorLoadCatalogEntryMiss:
        CP      EDITOR_LOAD_ERR_SIZE
        JP      Z,EditorLoadReturnErr
        CP      EDITOR_LOAD_ERR_BLOCK
        JP      Z,EditorLoadReturnErr
        CP      EDITOR_LOAD_ERR_PAGE
        JP      Z,EditorLoadReturnErr

        LD      DE,TM8_CATALOG_ENTRY
        ADD     HL,DE
        DJNZ    EditorLoadCatalogEntry

        EX      DE,HL
        LD      BC,TM8_SECTOR_BYTES
        ADD     HL,BC
        EX      DE,HL
        LD      A,(EditorLoadSectorsLeft)
        DEC     A
        LD      (EditorLoadSectorsLeft),A
        JR      NZ,EditorLoadCatalogSector

        LD      A,EDITOR_LOAD_ERR_FIND
        SCF
        RET

;! in HL
;! out A,E,carry,zero
;! clobbers sign,parity,halfCarry,B,D,HL
@EditorLoadMatchCatalogEntry:
        LD      (EditorLoadEntryBase),HL
        PUSH    HL
        LD      DE,0 - DISK_BUFF
        ADD     HL,DE
        LD      (EditorLoadCatalogEntryOffset),HL
        POP     HL
        LD      A,(HL)
        CP      TM8_ENTRY_ACTIVE
        JR      NZ,EditorLoadEntryNo
        INC     HL
        INC     HL
        LD      A,(EditorLoadSrcPrefixId)
        CP      (HL)
        JR      NZ,EditorLoadEntryNo
        INC     HL
        LD      A,(HL)
        LD      B,A
        LD      A,(EditorLoadNameLen)
        CP      B
        JR      NZ,EditorLoadEntryNo
        INC     HL
        LD      DE,(EditorLoadNamePtr)
        LD      A,(EditorLoadNameLen)
        LD      B,A
        CALL    Tecm8StringMatchBytes
        JR      C,EditorLoadEntryNo

        LD      HL,(EditorLoadEntryBase)
        LD      DE,44
        ADD     HL,DE
        LD      E,(HL)
        INC     HL
        LD      D,(HL)
        INC     HL
        LD      A,D
        CP      4
        JP      NC,EditorLoadBlockErr
        LD      A,D
        OR      A
        JR      NZ,EditorLoadFirstBlockOk
        LD      A,E
        CP      10
        JR      C,EditorLoadBlockErr

EditorLoadFirstBlockOk:
        LD      (EditorLoadFirstBlock),DE
        LD      HL,(EditorLoadEntryBase)
        LD      DE,46
        ADD     HL,DE
        LD      E,(HL)
        INC     HL
        LD      D,(HL)
        INC     HL
        LD      A,(HL)
        OR      A
        JR      NZ,EditorLoadSizeOk
        INC     HL
        LD      A,(HL)
        OR      A
        JR      NZ,EditorLoadSizeOk
        LD      A,D
        LD      B,A
        LD      A,(EditorLoadRequiredSizeHigh)
        LD      C,A
        LD      A,B
        CP      C
        JR      C,EditorLoadSizeErr

EditorLoadSizeOk:
        XOR     A
        RET

EditorLoadSizeErr:
        LD      A,(EditorLoadAllowShort)
        OR      A
        JR      NZ,EditorLoadSizeOk
        LD      A,EDITOR_LOAD_ERR_SIZE
        SCF
        RET

EditorLoadEntryNo:
        XOR     A
        SCF
        RET

EditorLoadReturnErr:
        SCF
        RET

EditorLoadFindErr:
        LD      A,EDITOR_LOAD_ERR_FIND
        SCF
        RET

EditorLoadBlockErr:
        LD      A,EDITOR_LOAD_ERR_BLOCK
        SCF
        RET

;! out A,carry,zero
;! clobbers sign,parity,halfCarry,BC,DE,HL
@EditorLoadReadSourceSector:
        LD      HL,(EditorLoadFirstBlock)
        CALL    EditorLoadResolveSourceBlock
        RET     C
        LD      HL,(EditorLoadResolvedBlock)
        CALL    EditorLoadBlockToOffset
        LD      A,(EditorLoadSectorInBlock)
        ADD     A,A
        ADD     A,D
        LD      D,A
        CALL    BiosFileReadSector
        JP      C,EditorLoadReadErr

        LD      HL,DISK_BUFF
        LD      DE,(EditorLoadDest)
        LD      BC,TM8_SECTOR_BYTES
        LDIR
        XOR     A
        RET

;! out A,carry,zero
;! clobbers sign,parity,halfCarry,BC,DE,HL
@EditorCreateFindFreeBlock:
        LD      DE,TM8_ALLOC_START_BLOCK * TM8_BLOCK_BYTES
        LD      (EditorCreateAllocOffset),DE
        LD      HL,0
        LD      (EditorCreateBlockCandidate),HL
        LD      A,TM8_TOTAL_BLOCKS / (TM8_SECTOR_BYTES / 2)
        LD      (EditorCreateAllocSectorsLeft),A

EditorCreateFreeBlockSector:
        LD      DE,(EditorCreateAllocOffset)
        PUSH    DE
        LD      HL,0
        CALL    BiosFileReadSector
        POP     DE
        JP      C,EditorLoadReadErr

        LD      HL,(EditorCreateBlockCandidate)
        LD      A,H
        OR      L
        JR      NZ,EditorCreateFreeBlockWholeSector
        LD      HL,DISK_BUFF + (TM8_DATA_START_BLOCK * 2)
        LD      DE,TM8_DATA_START_BLOCK
        LD      B,(TM8_SECTOR_BYTES / 2) - TM8_DATA_START_BLOCK
        JR      EditorCreateFreeBlockLoopReady

EditorCreateFreeBlockWholeSector:
        LD      HL,DISK_BUFF
        LD      DE,(EditorCreateBlockCandidate)
        LD      B,0

EditorCreateFreeBlockLoopReady:
EditorCreateFreeBlockLoop:
        LD      A,(HL)
        INC     HL
        OR      (HL)
        JR      Z,EditorCreateFreeBlockFound
        INC     HL
        INC     DE
        DJNZ    EditorCreateFreeBlockLoop
        LD      (EditorCreateBlockCandidate),DE
        LD      HL,(EditorCreateAllocOffset)
        LD      BC,TM8_SECTOR_BYTES
        ADD     HL,BC
        LD      (EditorCreateAllocOffset),HL
        LD      A,(EditorCreateAllocSectorsLeft)
        DEC     A
        LD      (EditorCreateAllocSectorsLeft),A
        JR      NZ,EditorCreateFreeBlockSector
        JP      EditorLoadCreateErr

EditorCreateFreeBlockFound:
        LD      (EditorCreateFreeBlock),DE
        XOR     A
        RET

;! out A,carry,zero
;! clobbers sign,parity,halfCarry,BC,DE,HL
@EditorCreateMarkAllocatedBlock:
        LD      HL,(EditorCreateFreeBlock)
        LD      A,H
        ADD     A,A
        ADD     A,0x10
        LD      D,A
        LD      E,0
        LD      (EditorCreateAllocSectorHigh),A
        LD      HL,0
        CALL    BiosFileReadSector
        JP      C,EditorLoadReadErr

        LD      A,(EditorCreateFreeBlock)
        ADD     A,A
        LD      L,A
        LD      H,0
        JR      NC,EditorCreateMarkOffsetOk
        INC     H

EditorCreateMarkOffsetOk:
        LD      DE,DISK_BUFF
        ADD     HL,DE
        LD      (HL),0xFF
        INC     HL
        LD      (HL),0xFF

        LD      A,(EditorCreateAllocSectorHigh)
        LD      D,A
        LD      E,0
        LD      HL,0
        CALL    BiosFileWriteSector
        JP      C,EditorLoadWriteErr
        XOR     A
        RET

;! out A,carry,zero
;! clobbers sign,parity,halfCarry,BC,DE,HL
@EditorCreateFindCatalogSlot:
        LD      DE,TM8_CATALOG_SECTOR * TM8_SECTOR_BYTES
        LD      A,TM8_CATALOG_SECTORS
        LD      (EditorLoadSectorsLeft),A

EditorCreateFreeCatalogSector:
        PUSH    DE
        LD      HL,0
        CALL    BiosFileReadSector
        POP     DE
        JP      C,EditorLoadReadErr

        LD      HL,DISK_BUFF
        LD      B,TM8_ENTRIES_SECTOR

EditorCreateFreeCatalogEntry:
        LD      A,(HL)
        OR      A
        JR      Z,EditorCreateFreeCatalogFound
        PUSH    DE
        LD      DE,TM8_CATALOG_ENTRY
        ADD     HL,DE
        POP     DE
        DJNZ    EditorCreateFreeCatalogEntry

        EX      DE,HL
        LD      BC,TM8_SECTOR_BYTES
        ADD     HL,BC
        EX      DE,HL
        LD      A,(EditorLoadSectorsLeft)
        DEC     A
        LD      (EditorLoadSectorsLeft),A
        JR      NZ,EditorCreateFreeCatalogSector
        JP      EditorLoadCreateErr

EditorCreateFreeCatalogFound:
        XOR     A
        RET

;! out A,carry,zero
;! clobbers sign,parity,halfCarry,BC,DE,HL
@EditorCreateNextFileId:
        XOR     A
        LD      (EditorCreateFileId),A

EditorCreateNextFileIdTry:
        CALL    EditorCreateFileIdUsed
        RET     C
        OR      A
        JR      Z,EditorCreateNextFileIdOk
        LD      A,(EditorCreateFileId)
        INC     A
        LD      (EditorCreateFileId),A
        JR      NZ,EditorCreateNextFileIdTry
        JP      EditorLoadCreateErr

EditorCreateNextFileIdOk:
        XOR     A
        RET

;! out HL,A,carry,zero
;! clobbers sign,parity,halfCarry,BC,DE
@EditorCreateFileIdUsed:
        LD      DE,TM8_CATALOG_SECTOR * TM8_SECTOR_BYTES
        LD      A,TM8_CATALOG_SECTORS
        LD      (EditorLoadSectorsLeft),A

EditorCreateFileIdSector:
        PUSH    DE
        LD      HL,0
        CALL    BiosFileReadSector
        POP     DE
        JP      C,EditorLoadReadErr

        LD      HL,DISK_BUFF
        LD      B,TM8_ENTRIES_SECTOR

EditorCreateFileIdEntry:
        LD      A,(HL)
        CP      TM8_ENTRY_ACTIVE
        JR      NZ,EditorCreateFileIdAdvance
        INC     HL
        LD      A,(EditorCreateFileId)
        CP      (HL)
        JR      Z,EditorCreateFileIdFound
        DEC     HL

EditorCreateFileIdAdvance:
        PUSH    DE
        LD      DE,TM8_CATALOG_ENTRY
        ADD     HL,DE
        POP     DE
        DJNZ    EditorCreateFileIdEntry

        EX      DE,HL
        LD      BC,TM8_SECTOR_BYTES
        ADD     HL,BC
        EX      DE,HL
        LD      A,(EditorLoadSectorsLeft)
        DEC     A
        LD      (EditorLoadSectorsLeft),A
        JR      NZ,EditorCreateFileIdSector
        XOR     A
        RET

EditorCreateFileIdFound:
        LD      A,1
        RET

;! out A,carry,zero
;! clobbers sign,parity,halfCarry,BC,DE,HL
@EditorCreateWriteCatalogEntry:
        LD      DE,TM8_CATALOG_SECTOR * TM8_SECTOR_BYTES
        LD      A,TM8_CATALOG_SECTORS
        LD      (EditorLoadSectorsLeft),A

EditorCreateCatalogSector:
        PUSH    DE
        LD      HL,0
        CALL    BiosFileReadSector
        POP     DE
        JP      C,EditorLoadReadErr

        LD      HL,DISK_BUFF
        LD      B,TM8_ENTRIES_SECTOR

EditorCreateCatalogEntry:
        LD      A,(HL)
        OR      A
        JR      Z,EditorCreateCatalogFound
        PUSH    DE
        LD      DE,TM8_CATALOG_ENTRY
        ADD     HL,DE
        POP     DE
        LD      A,(EditorCreateFileId)
        DJNZ    EditorCreateCatalogEntry

        EX      DE,HL
        LD      BC,TM8_SECTOR_BYTES
        ADD     HL,BC
        EX      DE,HL
        LD      A,(EditorLoadSectorsLeft)
        DEC     A
        LD      (EditorLoadSectorsLeft),A
        JR      NZ,EditorCreateCatalogSector
        JP      EditorLoadCreateErr

EditorCreateCatalogFound:
        LD      (EditorCreateEntryBase),HL
        LD      A,TM8_ENTRY_ACTIVE
        LD      (HL),A
        INC     HL
        LD      A,(EditorCreateFileId)
        LD      (HL),A
        INC     HL
        LD      A,(EditorLoadSrcPrefixId)
        LD      (HL),A
        INC     HL
        LD      A,(EditorLoadNameLen)
        LD      (HL),A
        INC     HL
        LD      DE,(EditorLoadNamePtr)
        LD      A,(EditorLoadNameLen)
        LD      B,A

EditorCreateCatalogNameLoop:
        LD      A,(DE)
        LD      (HL),A
        INC     DE
        INC     HL
        DJNZ    EditorCreateCatalogNameLoop

        LD      HL,(EditorCreateEntryBase)
        LD      DE,44
        ADD     HL,DE
        LD      DE,(EditorCreateFreeBlock)
        LD      (HL),E
        INC     HL
        LD      (HL),D
        INC     HL
        LD      (HL),0
        INC     HL
        LD      (HL),0x10
        INC     HL
        LD      (HL),0
        INC     HL
        LD      (HL),0
        INC     HL
        LD      (HL),1

        LD      A,(EditorLoadSectorsLeft)
        LD      B,A
        LD      A,TM8_CATALOG_SECTORS
        SUB     B
        ADD     A,TM8_CATALOG_SECTOR
        ADD     A,A
        LD      D,A
        LD      E,0
        LD      HL,0
        CALL    BiosFileWriteSector
        JP      C,EditorLoadWriteErr
        XOR     A
        RET

;! out A,carry,zero
;! clobbers sign,parity,halfCarry,DE,HL
@EditorCreateUpdateSuperblock:
        LD      HL,0
        LD      DE,0
        CALL    BiosFileReadSector
        JP      C,EditorLoadReadErr

        LD      HL,DISK_BUFF + 42
        LD      A,(HL)
        OR      A
        JR      Z,EditorCreateFreeCountBorrow
        DEC     (HL)
        JR      EditorCreateFreeCountOk

EditorCreateFreeCountBorrow:
        LD      (HL),0xFF
        INC     HL
        DEC     (HL)

EditorCreateFreeCountOk:
        CALL    EditorCreateRecomputeSuperblockChecksum
        LD      HL,0
        LD      DE,0
        CALL    BiosFileWriteSector
        JP      C,EditorLoadWriteErr
        XOR     A
        RET

;! out A,carry,zero
;! clobbers sign,parity,halfCarry,BC,DE,HL
@EditorCreateBlankCreatedSource:
        XOR     A
        LD      (EditorCreateBlankPageIndex),A

EditorCreateBlankCreatedSourceLoop:
        LD      A,(EditorCreateBlankPageIndex)
        LD      DE,(EditorLoadSourcePathPtr)
        LD      HL,EditorCreateBlankPageBuffer
        CALL    EditorSaveSourcePageNoGrow
        RET     C
        LD      A,(EditorCreateBlankPageIndex)
        INC     A
        LD      (EditorCreateBlankPageIndex),A
        CP      8
        JR      NZ,EditorCreateBlankCreatedSourceLoop
        XOR     A
        RET

;! out carry,zero,A
;! clobbers sign,parity,halfCarry,BC,DE,HL
@EditorCreateRecomputeSuperblockChecksum:
        LD      HL,DISK_BUFF + 72
        XOR     A
        LD      (HL),A
        INC     HL
        LD      (HL),A
        INC     HL
        LD      (HL),A
        INC     HL
        LD      (HL),A

        LD      HL,DISK_BUFF
        LD      BC,TM8_SECTOR_BYTES
        LD      DE,0

EditorCreateChecksumLoop:
        LD      A,E
        ADD     A,(HL)
        LD      E,A
        JR      NC,EditorCreateChecksumNoCarry
        INC     D

EditorCreateChecksumNoCarry:
        INC     HL
        DEC     BC
        LD      A,B
        OR      C
        JR      NZ,EditorCreateChecksumLoop

        LD      HL,DISK_BUFF + 72
        LD      (HL),E
        INC     HL
        LD      (HL),D
        INC     HL
        XOR     A
        LD      (HL),A
        INC     HL
        LD      (HL),A
        RET

;! out A,carry,zero
;! clobbers sign,parity,halfCarry,BC,DE,HL
@EditorLoadWriteSourceSector:
        LD      HL,(EditorLoadFirstBlock)
        CALL    EditorLoadResolveSourceBlock
        RET     C
        LD      HL,(EditorLoadResolvedBlock)
        ; expects out HL
        CALL    EditorLoadBlockToOffset
        LD      A,(EditorLoadSectorInBlock)
        ADD     A,A
        ADD     A,D
        LD      D,A
        LD      (EditorLoadSectorOffsetHigh),A
        LD      (EditorLoadSectorOffsetUpper),HL
        CALL    BiosFileReadSector
        JP      C,EditorLoadReadErr

        LD      HL,(EditorLoadDest)
        LD      DE,DISK_BUFF
        LD      BC,TM8_SECTOR_BYTES
        LDIR

        LD      A,(EditorLoadSectorOffsetHigh)
        LD      D,A
        LD      E,0
        LD      HL,(EditorLoadSectorOffsetUpper)
        CALL    BiosFileWriteSector
        JP      C,EditorLoadWriteErr

        XOR     A
        RET

; EditorSaveExtendCatalogSize -
; Grow the matched source file's catalog byte size to include the just-written
; sector. This is monotonic and preserves already-large 32-bit catalog sizes.
;! out A,carry,zero
;! clobbers sign,parity,halfCarry,BC,DE,HL
@EditorSaveExtendCatalogSize:
        CALL    EditorLoadFindSource
        RET     C
        LD      A,(EditorLoadSectorsLeft)
        LD      B,A
        LD      A,TM8_CATALOG_SECTORS
        SUB     B
        ADD     A,TM8_CATALOG_SECTOR
        ADD     A,A
        LD      D,A
        LD      E,0
        LD      (EditorLoadCatalogSectorOffset),DE
        LD      A,D
        CP      0x60
        JP      C,EditorLoadBlockErr
        LD      HL,0
        CALL    BiosFileReadSector
        JP      C,EditorLoadReadErr

        LD      DE,(EditorLoadCatalogEntryOffset)
        LD      HL,DISK_BUFF + 46
        ADD     HL,DE
        INC     HL
        INC     HL
        LD      A,(HL)
        LD      B,A
        LD      A,(EditorSaveRequiredSizeUpper)
        CP      B
        JR      C,EditorSaveCatalogSizeOk
        JR      NZ,EditorSaveCatalogUpdate
        INC     HL
        LD      A,(HL)
        OR      A
        JR      NZ,EditorSaveCatalogSizeOk
        DEC     HL
        DEC     HL
        DEC     HL
        INC     HL
        LD      A,(HL)
        LD      B,A
        LD      A,(EditorSaveRequiredSizeHigh)
        CP      B
        JR      C,EditorSaveCatalogSizeOk
        JR      Z,EditorSaveCatalogSizeOk

EditorSaveCatalogUpdate:
        LD      DE,(EditorLoadCatalogEntryOffset)
        LD      HL,DISK_BUFF + 46
        ADD     HL,DE
        XOR     A
        LD      (HL),A
        INC     HL
        LD      A,(EditorSaveRequiredSizeHigh)
        LD      (HL),A
        INC     HL
        LD      A,(EditorSaveRequiredSizeUpper)
        LD      (HL),A
        INC     HL
        XOR     A
        LD      (HL),A

        LD      DE,(EditorLoadCatalogSectorOffset)
        LD      HL,0
        CALL    BiosFileWriteSector
        JP      C,EditorLoadWriteErr

EditorSaveCatalogSizeOk:
        XOR     A
        RET

;! in HL
;! out A,carry,zero
;! clobbers sign,parity,halfCarry,BC,DE,HL
@EditorLoadResolveSourceBlock:
        LD      (EditorLoadResolvedBlock),HL
        LD      A,(EditorLoadBlockSteps)
        LD      (EditorLoadBlocksLeft),A

EditorLoadResolveLoop:
        LD      A,(EditorLoadBlocksLeft)
        OR      A
        JR      Z,EditorLoadResolveOk

        LD      HL,(EditorLoadResolvedBlock)
        ; expects out HL
        CALL    EditorLoadResolveNextBlock
        RET     C
        LD      (EditorLoadResolvedBlock),HL

        LD      A,(EditorLoadBlocksLeft)
        DEC     A
        LD      (EditorLoadBlocksLeft),A
        JR      EditorLoadResolveLoop

EditorLoadResolveOk:
        XOR     A
        RET

;! in HL
;! out HL,A,carry,zero
;! clobbers sign,parity,halfCarry,BC,DE
@EditorLoadResolveNextBlock:
        LD      A,(EditorSaveGrowMode)
        OR      A
        JP      NZ,EditorSaveReadOrGrowAllocationEntry
        JP      EditorLoadReadAllocationEntry

;! in HL
;! out HL,A,carry,zero
;! clobbers sign,parity,halfCarry,BC,DE
@EditorSaveReadOrGrowAllocationEntry:
        LD      (EditorSavePreviousBlock),HL
        LD      (EditorLoadCurrentBlock),HL
        LD      A,H
        CP      4
        JP      NC,EditorLoadBlockErr
        ADD     A,A
        ADD     A,0x10
        LD      D,A
        LD      E,0
        LD      HL,0
        CALL    BiosFileReadSector
        JP      C,EditorLoadReadErr

        LD      A,(EditorLoadCurrentBlock)
        ADD     A,A
        LD      E,A
        LD      D,0
        JR      NC,EditorSaveReadGrowOffsetOk
        INC     D

EditorSaveReadGrowOffsetOk:
        LD      HL,DISK_BUFF
        ADD     HL,DE
        LD      E,(HL)
        INC     HL
        LD      D,(HL)

        LD      A,D
        CP      0xFF
        JR      NZ,EditorSaveReadGrowNotEndHigh
        LD      A,E
        CP      0xFF
        JP      Z,EditorSaveGrowAllocateBlock

EditorSaveReadGrowNotEndHigh:
        LD      A,D
        CP      4
        JP      NC,EditorLoadBlockErr
        OR      A
        JR      NZ,EditorSaveReadGrowOk
        LD      A,E
        CP      TM8_DATA_START_BLOCK
        JP      C,EditorLoadBlockErr

EditorSaveReadGrowOk:
        EX      DE,HL
        XOR     A
        RET

EditorSaveGrowAllocateBlock:
        CALL    EditorCreateFindFreeBlock
        RET     C
        CALL    EditorCreateMarkAllocatedBlock
        RET     C
        CALL    EditorCreateUpdateSuperblock
        RET     C
        LD      HL,(EditorSavePreviousBlock)
        LD      DE,(EditorCreateFreeBlock)
        CALL    EditorSaveWriteAllocationEntryValue
        RET     C
        LD      HL,(EditorCreateFreeBlock)
        XOR     A
        RET

;! in DE,HL
;! out A,carry,zero
;! clobbers sign,parity,halfCarry,BC,DE,HL
@EditorSaveWriteAllocationEntryValue:
        LD      (EditorLoadCurrentBlock),HL
        LD      (EditorSaveAllocationValue),DE
        LD      A,H
        CP      4
        JP      NC,EditorLoadBlockErr
        ADD     A,A
        ADD     A,0x10
        LD      D,A
        LD      E,0
        LD      (EditorCreateAllocSectorHigh),A
        LD      HL,0
        CALL    BiosFileReadSector
        JP      C,EditorLoadReadErr

        LD      A,(EditorLoadCurrentBlock)
        ADD     A,A
        LD      E,A
        LD      D,0
        JR      NC,EditorSaveWriteAllocOffsetOk
        INC     D

EditorSaveWriteAllocOffsetOk:
        LD      HL,DISK_BUFF
        ADD     HL,DE
        LD      DE,(EditorSaveAllocationValue)
        LD      (HL),E
        INC     HL
        LD      (HL),D

        LD      A,(EditorCreateAllocSectorHigh)
        LD      D,A
        LD      E,0
        LD      HL,0
        CALL    BiosFileWriteSector
        JP      C,EditorLoadWriteErr
        XOR     A
        RET

;! in HL
;! out A,carry,zero,HL
;! clobbers sign,parity,halfCarry,BC,DE
@EditorLoadReadAllocationEntry:
        LD      (EditorLoadCurrentBlock),HL
        LD      A,H
        CP      4
        JP      NC,EditorLoadBlockErr
        ADD     A,A
        ADD     A,0x10
        LD      D,A
        LD      E,0
        LD      HL,0
        CALL    BiosFileReadSector
        JP      C,EditorLoadReadErr

        LD      A,(EditorLoadCurrentBlock)
        ADD     A,A
        LD      E,A
        LD      D,0
        JR      NC,EditorLoadAllocationOffsetOk
        INC     D

EditorLoadAllocationOffsetOk:
        LD      HL,DISK_BUFF
        ADD     HL,DE
        LD      E,(HL)
        INC     HL
        LD      D,(HL)

        LD      A,D
        CP      0xFF
        JR      NZ,EditorLoadAllocationNotEndHigh
        LD      A,E
        CP      0xFF
        JP      Z,EditorLoadBlockErr

EditorLoadAllocationNotEndHigh:
        LD      A,D
        CP      4
        JP      NC,EditorLoadBlockErr
        OR      A
        JR      NZ,EditorLoadAllocationOk
        LD      A,E
        CP      TM8_DATA_START_BLOCK
        JP      C,EditorLoadBlockErr

EditorLoadAllocationOk:
        EX      DE,HL
        XOR     A
        RET

;! in HL
;! out DE,HL
;! clobbers A,F
@EditorLoadBlockToOffset:
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

EditorLoadMagic:
        .db     "TECM8VOL"

EditorLoadVolumeName:
        .db     "VOLUME.TM8",0

EditorLoadMainPath:
        .db     "/src/main.asm",0

EditorLoadDest:
        .dw     0

EditorLoadFirstBlock:
        .dw     0

EditorLoadEntryBase:
        .dw     0

EditorLoadSectorsLeft:
        .db     0

EditorLoadSrcPrefixId:
        .db     0

EditorLoadSectorIndex:
        .db     0

EditorLoadSectorInBlock:
        .db     0

EditorLoadBlockSteps:
        .db     0

EditorLoadBlocksLeft:
        .db     0

EditorLoadRequiredSizeHigh:
        .db     0

EditorSaveRequiredSizeHigh:
        .db     0

EditorSaveRequiredSizeUpper:
        .db     0

EditorSaveGrowMode:
        .db     0

EditorLoadAllowShort:
        .db     0

EditorLoadResolvedBlock:
        .dw     0

EditorLoadCurrentBlock:
        .dw     0

EditorLoadSourcePathPtr:
        .dw     0

EditorLoadPrefixPtr:
        .dw     0

EditorLoadNamePtr:
        .dw     0

EditorLoadPrefixLen:
        .db     0

EditorLoadNameLen:
        .db     0

EditorLoadSectorOffsetHigh:
        .db     0

EditorLoadSectorOffsetUpper:
        .dw     0

EditorLoadCatalogSectorOffset:
        .dw     0

EditorLoadCatalogEntryOffset:
        .dw     0

EditorCreateFreeBlock:
        .dw     0

EditorCreateBlockCandidate:
        .dw     0

EditorCreateAllocOffset:
        .dw     0

EditorCreateEntryBase:
        .dw     0

EditorCreateFileId:
        .db     0

EditorCreateAllocSectorsLeft:
        .db     0

EditorCreateAllocSectorHigh:
        .db     0

EditorCreateBlankPageIndex:
        .db     0

EditorCreateBlankPageBuffer:
        .ds     TM8_SECTOR_BYTES

EditorSavePreviousBlock:
        .dw     0

EditorSaveAllocationValue:
        .dw     0
