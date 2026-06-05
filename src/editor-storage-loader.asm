; TECM8 editor source-sector loader.
;
; Proof-focused loader for source files in VOLUME.TM8. It opens the MON3
; FAT32 file, finds the requested prefix and filename, follows the TM8
; allocation chain, and copies one 512-byte source page to a caller buffer.

DISK_BUFF               .equ    0x0600

TM8_SECTOR_BYTES        .equ    512
TM8_BLOCK_BYTES         .equ    4096
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

; EditorLoadMainSector -
; Load the first sector of /src/main.asm into caller buffer HL.
;!      in        HL
;!      out       A,carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@EditorLoadMainSector:
        XOR     A
        JP      EditorLoadMainPage

; EditorLoadMainPage -
; Load one 512-byte sector page of /src/main.asm into caller buffer HL.
; Page A is limited to 0..127.
;!      in        A,HL
;!      out       A,carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@EditorLoadMainPage:
        LD      DE,EditorLoadMainPath
        JP      EditorLoadSourcePage

; EditorLoadSourcePage -
; Load one 512-byte sector page of a source file into caller buffer HL.
; Input:
;   A  = page index, limited to 0..127
;   DE = NUL-terminated TM8 path, e.g. /src/main.asm
;   HL = caller destination buffer
;!      in        A,DE,HL
;!      out       A,carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@EditorLoadSourcePage:
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
;!      in        A,DE,HL
;!      out       A,carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@EditorSaveSourcePage:
        LD      (EditorLoadSectorIndex),A
        LD      (EditorLoadDest),HL
        LD      (EditorLoadSourcePathPtr),DE
        CP      128
        JR      NC,EditorLoadPageErr
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
        XOR     A
        RET

EditorLoadOpenErr:
        LD      A,EDITOR_LOAD_ERR_OPEN
        SCF
        RET

EditorLoadPageErr:
        LD      A,EDITOR_LOAD_ERR_PAGE
        SCF
        RET

;!      out       A,carry,zero
;!      clobbers  B,DE,HL
@EditorLoadReadSuperblock:
        LD      HL,0
        LD      DE,0
        CALL    BiosFileReadSector
        JP      C,EditorLoadReadErr

        LD      HL,DISK_BUFF
        LD      DE,EditorLoadMagic
        LD      B,8
        CALL    EditorLoadMatchBytes
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

;!      out       A,carry,zero
;!      clobbers  BC,DE,HL
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

;!      out       A,carry,zero
;!      clobbers  BC,DE,HL
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

;!      in        HL
;!      out       A,carry,zero
;!      clobbers  B,DE,HL
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
        CALL    EditorLoadMatchBytes
        RET     NC
        JP      EditorLoadEntryNo

;!      out       A,carry,zero
;!      clobbers  BC,DE,HL
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
        RET     NC
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

;!      in        HL
;!      out       A,carry,zero
;!      clobbers  B,DE,HL
@EditorLoadMatchCatalogEntry:
        LD      (EditorLoadEntryBase),HL
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
        CALL    EditorLoadMatchBytes
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

EditorLoadEntryNo:
        XOR     A
        SCF
        RET

EditorLoadReturnErr:
        SCF
        RET

EditorLoadSizeErr:
        LD      A,EDITOR_LOAD_ERR_SIZE
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

;!      out       A,carry,zero
;!      clobbers  BC,DE,HL
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

;!      out       A,carry,zero
;!      clobbers  BC,DE,HL
@EditorLoadWriteSourceSector:
        LD      HL,(EditorLoadFirstBlock)
        CALL    EditorLoadResolveSourceBlock
        RET     C
        LD      HL,(EditorLoadResolvedBlock)
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

;!      in        HL
;!      out       A,carry,zero
;!      clobbers  BC,DE,HL
@EditorLoadResolveSourceBlock:
        LD      (EditorLoadResolvedBlock),HL
        LD      A,(EditorLoadBlockSteps)
        LD      (EditorLoadBlocksLeft),A

EditorLoadResolveLoop:
        LD      A,(EditorLoadBlocksLeft)
        OR      A
        JR      Z,EditorLoadResolveOk

        LD      HL,(EditorLoadResolvedBlock)
        CALL    EditorLoadReadAllocationEntry
        RET     C
        LD      (EditorLoadResolvedBlock),HL

        LD      A,(EditorLoadBlocksLeft)
        DEC     A
        LD      (EditorLoadBlocksLeft),A
        JR      EditorLoadResolveLoop

EditorLoadResolveOk:
        XOR     A
        RET

;!      in        HL
;!      out       HL,A,carry,zero
;!      clobbers  BC,DE
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

;!      in        HL
;!      out       DE,HL
;!      clobbers  A
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

;!      in        B,DE,HL
;!      out       A,carry,zero
;!      clobbers  B,DE,HL
@EditorLoadMatchBytes:
        LD      A,(DE)
        CP      (HL)
        JR      NZ,EditorLoadBytesBad
        INC     DE
        INC     HL
        DJNZ    EditorLoadMatchBytes
        XOR     A
        RET

EditorLoadBytesBad:
        SCF
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
