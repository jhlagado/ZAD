; TECM8 editor navigation state.
;
; Minimal storage-backed page navigation for a TM8 source path.

TECM8_EDITOR_NAV_ERR_PAGE       .equ    0x50
TECM8_EDITOR_NAV_ERR_PATH       .equ    0x51
TECM8_EDITOR_NAV_ERR_BACKUP     .equ    0x52
TECM8_EDITOR_NAV_PATH_LEN       .equ    64

; EditorOpenMain -
; Reset navigation to page 0 and render /src/main.asm.
;!      out       A,carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@EditorOpenMain:
        LD      HL,EditorNavMainPath
        JP      EditorOpenPath

; EditorOpenPath -
; Reset navigation to page 0 and render the source file at HL.
;!      in        HL
;!      out       A,carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@EditorOpenPath:
        LD      DE,EditorNavPathBuffer
        LD      B,TECM8_EDITOR_NAV_PATH_LEN
        CALL    EditorNavCopyPath
        RET     C
        LD      HL,EditorNavPathBuffer
        LD      (EditorNavPathPtr),HL
        XOR     A
        LD      (EditorNavCurrentPage),A
        JP      EditorRenderCurrent

; EditorRenderCurrent -
; Load and render the current page.
;!      out       A,carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@EditorRenderCurrent:
        LD      A,(EditorNavCurrentPage)
        CALL    EditorNavRenderPage
        RET     C
        JP      EditorClearDirty

; EditorRenderPageBuffer -
; Render the already-loaded page buffer without reloading it from storage.
;!      out       A,carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@EditorRenderPageBuffer:
        LD      HL,EditorNavPageBuffer
        CALL    EditorViewportRender
        RET     C
        CALL    BiosDisplayUpdate
        RET

; EditorSaveCurrentPage -
; Save the already-loaded page buffer back to the current source page.
;!      out       A,carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@EditorSaveCurrentPage:
        CALL    EditorBackupCurrentPage
        RET     C
        LD      A,(EditorNavCurrentPage)
        LD      DE,(EditorNavPathPtr)
        LD      HL,EditorNavPageBuffer
        CALL    EditorSaveSourcePage
        RET     C
        JP      EditorClearDirty

; EditorBackupCurrentPage -
; Save the current on-disk page to the derived hidden backup path.
; The backup file must already exist in this first implementation.
;!      out       A,carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@EditorBackupCurrentPage:
        LD      HL,(EditorNavPathPtr)
        LD      DE,EditorNavBackupPathBuffer
        LD      B,TECM8_EDITOR_NAV_PATH_LEN
        CALL    EditorNavDeriveBackupPath
        RET     C
        LD      A,(EditorNavCurrentPage)
        LD      DE,(EditorNavPathPtr)
        LD      HL,EditorNavBackupPageBuffer
        CALL    EditorLoadSourcePage
        RET     C
        LD      A,(EditorNavCurrentPage)
        LD      DE,EditorNavBackupPathBuffer
        LD      HL,EditorNavBackupPageBuffer
        JP      EditorSaveSourcePage

; EditorClearDirty -
; Mark the current editor page clean after a successful load or save.
;!      out       A,carry
;!      clobbers  A,zero,sign,parity,halfCarry
@EditorClearDirty:
        XOR     A
        LD      (EditorNavDirty),A
        RET

; EditorPageDown -
; Advance one page, render it, and commit the page only if rendering succeeds.
;!      out       A,carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@EditorPageDown:
        LD      A,(EditorNavCurrentPage)
        CP      127
        JR      Z,EditorNavPageErr
        INC     A
        LD      (EditorNavPendingPage),A
        CALL    EditorNavRenderPage
        RET     C
        LD      A,(EditorNavPendingPage)
        LD      (EditorNavCurrentPage),A
        JP      EditorClearDirty

; EditorPageUp -
; Move back one page, render it, and commit the page only if rendering succeeds.
;!      out       A,carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@EditorPageUp:
        LD      A,(EditorNavCurrentPage)
        OR      A
        JR      Z,EditorNavPageErr
        DEC     A
        LD      (EditorNavPendingPage),A
        CALL    EditorNavRenderPage
        RET     C
        LD      A,(EditorNavPendingPage)
        LD      (EditorNavCurrentPage),A
        JP      EditorClearDirty

;!      in        A
;!      out       A,carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@EditorNavRenderPage:
        LD      DE,(EditorNavPathPtr)
        LD      HL,EditorNavPageBuffer
        CALL    EditorLoadSourcePage
        RET     C
        JP      EditorRenderPageBuffer

EditorNavPageErr:
        LD      A,TECM8_EDITOR_NAV_ERR_PAGE
        SCF
        RET

;!      in        B,DE,HL
;!      out       A,carry,zero
;!      clobbers  B,DE,HL
@EditorNavCopyPath:
        LD      A,B
        OR      A
        JR      Z,EditorNavPathErr

EditorNavCopyPathLoop:
        LD      A,(HL)
        LD      (DE),A
        INC     HL
        INC     DE
        OR      A
        RET     Z
        DEC     B
        JR      NZ,EditorNavCopyPathLoop

EditorNavPathErr:
        LD      A,TECM8_EDITOR_NAV_ERR_PATH
        SCF
        RET

;!      in        B,DE,HL
;!      out       A,carry,zero
;!      clobbers  A,B,C,DE,HL
@EditorNavDeriveBackupPath:
        LD      (EditorNavBackupSourcePtr),HL
        LD      C,B
        LD      A,C
        OR      A
        JP      Z,EditorNavBackupErr

EditorNavBackupScanLoop:
        LD      A,(HL)
        OR      A
        JR      Z,EditorNavBackupBuild
        CP      "/"
        JR      NZ,EditorNavBackupScanNext
        LD      (EditorNavBackupNamePtr),HL
        INC     HL
        LD      (EditorNavBackupLocalPtr),HL
        JR      EditorNavBackupScanUsed

EditorNavBackupScanNext:
        INC     HL

EditorNavBackupScanUsed:
        DEC     C
        JR      NZ,EditorNavBackupScanLoop
        JP      EditorNavBackupErr

EditorNavBackupBuild:
        LD      HL,(EditorNavBackupLocalPtr)
        LD      A,(HL)
        OR      A
        JP      Z,EditorNavBackupErr
        LD      HL,(EditorNavBackupNamePtr)
        LD      A,H
        OR      L
        JP      Z,EditorNavBackupErr
        LD      HL,(EditorNavBackupSourcePtr)
        LD      C,B

EditorNavBackupCopyPrefix:
        LD      A,(HL)
        LD      (DE),A
        INC     HL
        INC     DE
        DEC     C
        JP      Z,EditorNavBackupErr
        LD      A,(EditorNavBackupLocalPtr)
        CP      L
        JR      NZ,EditorNavBackupCopyPrefix
        LD      A,(EditorNavBackupLocalPtr + 1)
        CP      H
        JR      NZ,EditorNavBackupCopyPrefix
        LD      A,"."
        LD      (DE),A
        INC     DE
        DEC     C
        JP      Z,EditorNavBackupErr

EditorNavBackupCopyName:
        LD      A,(HL)
        OR      A
        JR      Z,EditorNavBackupStartSuffix
        LD      (DE),A
        INC     HL
        INC     DE
        DEC     C
        JP      Z,EditorNavBackupErr
        JR      EditorNavBackupCopyName

EditorNavBackupStartSuffix:
        LD      HL,EditorNavBackupSuffix

EditorNavBackupSuffixLoop:
        LD      A,(HL)
        LD      (DE),A
        INC     HL
        INC     DE
        OR      A
        JR      Z,EditorNavBackupOk
        DEC     C
        JP      Z,EditorNavBackupErr
        JR      EditorNavBackupSuffixLoop

EditorNavBackupOk:
        XOR     A
        RET

EditorNavBackupErr:
        LD      A,TECM8_EDITOR_NAV_ERR_BACKUP
        SCF
        RET

EditorNavCurrentPage:
        .db     0

EditorNavDirty:
        .db     0

EditorNavPendingPage:
        .db     0

EditorNavPathPtr:
        .dw     0

EditorNavMainPath:
        .db     "/src/main.asm",0

EditorNavPathBuffer:
        .ds     TECM8_EDITOR_NAV_PATH_LEN

EditorNavBackupPathBuffer:
        .ds     TECM8_EDITOR_NAV_PATH_LEN

EditorNavBackupPageBuffer:
        .ds     512

EditorNavBackupNamePtr:
        .dw     0

EditorNavBackupLocalPtr:
        .dw     0

EditorNavBackupSourcePtr:
        .dw     0

EditorNavBackupSuffix:
        .db     ".b",0

EditorNavPageBuffer:
        .ds     512
