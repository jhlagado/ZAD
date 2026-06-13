; TECM8 editor/file listing support.
;
; Lists visible local filenames in one TM8 prefix. Leading-dot names are hidden
; from the ordinary listing so editor backups do not clutter navigation.

EDITOR_LIST_ERR_PATH       .equ    0x60
EDITOR_LIST_ERR_LONG       .equ    0x61

; EditorListVisibleFiles -
; List non-hidden local filenames for one TM8 prefix.
; Input:
;   DE = NUL-terminated prefix path, "/" or "/src"
;   HL = destination buffer
;   B  = destination capacity, including final NUL
; Output:
;   carry clear, destination contains newline-separated names and final NUL
;   carry set, A=EDITOR_LOAD_ERR_*, EDITOR_LIST_ERR_PATH, or
;                EDITOR_LIST_ERR_LONG
;! in B,DE,HL
;! out A,carry,zero
;! clobbers A,BC,DE,HL,zero,sign,parity,halfCarry
@EditorListVisibleFiles:
        LD      A,B
        OR      A
        JP      Z,EditorListLongErr
        LD      (EditorListOutPtr),HL
        LD      A,B
        LD      (EditorListRemainingCap),A
        LD      (EditorListPrefixPathPtr),DE
        CALL    EditorListParsePrefixPath
        RET     C

        LD      HL,EditorLoadVolumeName
        CALL    BiosFileOpen
        JP      C,EditorLoadOpenErr

        CALL    EditorLoadReadSuperblock
        RET     C
        LD      A,(EditorLoadPrefixLen)
        OR      A
        JR      Z,EditorListRootPrefix
        CALL    EditorLoadFindSourcePrefix
        RET     C
        JR      EditorListPrefixReady

EditorListRootPrefix:
        LD      (EditorLoadSrcPrefixId),A

EditorListPrefixReady:
        CALL    EditorListCatalog
        RET     C
        LD      HL,(EditorListOutPtr)
        LD      (HL),0
        XOR     A
        RET

;! out A,carry,zero
;! clobbers A,BC,DE,HL,zero,sign,parity,halfCarry
@EditorListParsePrefixPath:
        LD      HL,(EditorListPrefixPathPtr)
        LD      A,(HL)
        CP      "/"
        JR      NZ,EditorListPathErr
        INC     HL
        LD      (EditorLoadPrefixPtr),HL
        LD      A,(HL)
        OR      A
        JR      Z,EditorListParsedPrefix
        LD      B,0
        LD      C,0

EditorListPrefixLenLoop:
        LD      A,(HL)
        OR      A
        JR      Z,EditorListStorePrefixLen
        LD      C,A
        INC     B
        INC     HL
        LD      A,B
        CP      TM8_PREFIX_TEXT_BYTES + 1
        JR      NC,EditorListPathErr
        JR      EditorListPrefixLenLoop

EditorListStorePrefixLen:
        LD      A,B
        OR      A
        JR      Z,EditorListParsedPrefix
        LD      A,C
        CP      "/"
        JR      Z,EditorListPathErr
        LD      A,B

EditorListParsedPrefix:
        LD      (EditorLoadPrefixLen),A
        XOR     A
        RET

EditorListPathErr:
        LD      A,EDITOR_LIST_ERR_PATH
        SCF
        RET

;! out A,carry,zero
;! clobbers A,BC,DE,HL,zero,sign,parity,halfCarry
@EditorListCatalog:
        LD      DE,TM8_CATALOG_SECTOR * TM8_SECTOR_BYTES
        LD      A,TM8_CATALOG_SECTORS
        LD      (EditorLoadSectorsLeft),A

EditorListCatalogSector:
        LD      (EditorListCatalogOffset),DE
        LD      HL,0
        CALL    BiosFileReadSector
        JP      C,EditorLoadReadErr
        LD      DE,(EditorListCatalogOffset)

        LD      HL,DISK_BUFF
        LD      B,TM8_ENTRIES_SECTOR
        LD      C,0

EditorListCatalogEntry:
        PUSH    BC
        PUSH    DE
        PUSH    HL
        CALL    EditorListMaybeCopyEntry
        POP     HL
        POP     DE
        POP     BC
        RET     C

        PUSH    DE
        LD      DE,TM8_CATALOG_ENTRY
        ADD     HL,DE
        POP     DE
        DJNZ    EditorListCatalogEntry

        EX      DE,HL
        LD      BC,TM8_SECTOR_BYTES
        ADD     HL,BC
        EX      DE,HL
        LD      A,(EditorLoadSectorsLeft)
        DEC     A
        LD      (EditorLoadSectorsLeft),A
        JR      NZ,EditorListCatalogSector
        XOR     A
        RET

;! in HL
;! out A,carry,zero
;! clobbers A,BC,DE,HL,zero,sign,parity,halfCarry
@EditorListMaybeCopyEntry:
        LD      A,(HL)
        CP      TM8_ENTRY_ACTIVE
        JR      NZ,EditorListEntryDone
        INC     HL
        INC     HL
        LD      A,(EditorLoadSrcPrefixId)
        CP      (HL)
        JR      NZ,EditorListEntryDone
        INC     HL
        LD      A,(HL)
        OR      A
        JR      Z,EditorListEntryDone
        CP      TM8_CATALOG_NAME_BYTES + 1
        JR      NC,EditorListEntryDone
        LD      B,A
        INC     HL
        LD      A,(HL)
        CP      "."
        JR      Z,EditorListEntryDone
        CALL    EditorListCopyName
        RET     C

EditorListEntryDone:
        XOR     A
        RET

;! in B,HL
;! out A,carry,zero
;! clobbers A,B,C,DE,HL,zero,sign,parity,halfCarry
@EditorListCopyName:
        LD      DE,(EditorListOutPtr)

EditorListCopyNameLoop:
        LD      A,(EditorListRemainingCap)
        CP      2
        JR      C,EditorListLongErr
        LD      A,(HL)
        LD      (DE),A
        INC     HL
        INC     DE
        LD      A,(EditorListRemainingCap)
        DEC     A
        LD      (EditorListRemainingCap),A
        DJNZ    EditorListCopyNameLoop

        LD      A,(EditorListRemainingCap)
        CP      2
        JR      C,EditorListLongErr
        LD      A,0x0A
        LD      (DE),A
        INC     DE
        LD      A,(EditorListRemainingCap)
        DEC     A
        LD      (EditorListRemainingCap),A
        LD      (EditorListOutPtr),DE
        XOR     A
        RET

EditorListLongErr:
        LD      A,EDITOR_LIST_ERR_LONG
        SCF
        RET

EditorListPrefixPathPtr:
        .dw     0

EditorListOutPtr:
        .dw     0

EditorListRemainingCap:
        .db     0

EditorListCatalogOffset:
        .dw     0
