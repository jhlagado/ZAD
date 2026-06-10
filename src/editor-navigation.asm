; TECM8 editor navigation state.
;
; Minimal storage-backed page navigation for a TM8 source path.

TECM8_EDITOR_NAV_ERR_PAGE       .equ    0x50
TECM8_EDITOR_NAV_ERR_PATH       .equ    0x51
TECM8_EDITOR_NAV_ERR_BACKUP     .equ    0x52
TECM8_EDITOR_NAV_PATH_LEN       .equ    64
TECM8_EDITOR_NAV_PAGE_BYTES     .equ    512
TECM8_EDITOR_NAV_CACHE_BASE     .equ    0x3000

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
        LD      (EditorNavCacheValid),A
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
        LD      A,(EditorRenderPageBufferCount)
        INC     A
        LD      (EditorRenderPageBufferCount),A
        LD      HL,EditorNavPageBuffer
        CALL    EditorViewportRender
        RET     C
        CALL    GlcdTileFlushFull
        RET

; EditorSaveCurrentPage -
; Save the already-loaded page buffer back to the current source page.
;!      out       A,carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@EditorSaveCurrentPage:
        LD      HL,EditorStatusSavingText
        CALL    EditorNavShowStatus
        RET     C
        CALL    EditorBackupCurrentPage
        JR      C,EditorSaveCurrentPageRestoreError
        LD      A,(EditorNavCurrentPage)
        LD      DE,(EditorNavPathPtr)
        LD      HL,EditorNavPageBuffer
        CALL    EditorSaveSourcePage
        JR      C,EditorSaveCurrentPageRestoreError
        CALL    EditorClearDirty
        JP      EditorViewportRestoreStatusRow

EditorSaveCurrentPageRestoreError:
        PUSH    AF
        CALL    EditorViewportRestoreStatusRow
        POP     AF
        RET

; EditorBackupCurrentPage -
; Save the current on-disk page to the derived hidden backup path.
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
        CALL    EditorSaveSourcePage
        RET     NC
        CP      EDITOR_LOAD_ERR_FIND
        RET     NZ
        LD      DE,EditorNavBackupPathBuffer
        CALL    EditorCreateSourceFile
        RET     C
        LD      A,(EditorNavCurrentPage)
        LD      DE,EditorNavBackupPathBuffer
        LD      HL,EditorNavBackupPageBuffer
        JP      EditorSaveSourcePage

; EditorLoadCurrentBackupPage -
; Load the derived hidden backup path into the current page buffer.
;!      out       A,carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@EditorLoadCurrentBackupPage:
        LD      HL,(EditorNavPathPtr)
        LD      DE,EditorNavBackupPathBuffer
        LD      B,TECM8_EDITOR_NAV_PATH_LEN
        CALL    EditorNavDeriveBackupPath
        RET     C
        LD      HL,EditorStatusLoadingText
        CALL    EditorNavShowStatus
        RET     C
        LD      A,(EditorNavCurrentPage)
        LD      DE,EditorNavBackupPathBuffer
        LD      HL,EditorNavPageBuffer
        CALL    EditorLoadSourcePage
        JR      C,EditorLoadCurrentBackupPageRestoreError
        XOR     A
        RET

EditorLoadCurrentBackupPageRestoreError:
        PUSH    AF
        CALL    EditorViewportRestoreStatusRow
        POP     AF
        RET

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
        JP      Z,EditorNavPageErr
        INC     A
        LD      (EditorNavPendingPage),A
        CALL    EditorNavRenderCachedPendingPage
        RET     C
        OR      A
        JR      NZ,EditorNavCommitPendingPage
        CALL    EditorNavRememberCurrentPage
        LD      A,(EditorNavPendingPage)
        CALL    EditorNavRenderPage
        RET     C
EditorNavCommitPendingPage:
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
        JP      Z,EditorNavPageErr
        DEC     A
        LD      (EditorNavPendingPage),A
        CALL    EditorNavRenderCachedPendingPage
        RET     C
        OR      A
        JR      NZ,EditorNavCommitPendingPage
        CALL    EditorNavRememberCurrentPage
        LD      A,(EditorNavPendingPage)
        CALL    EditorNavRenderPage
        RET     C
        LD      A,(EditorNavPendingPage)
        LD      (EditorNavCurrentPage),A
        JP      EditorClearDirty

; EditorNavRememberCurrentPage -
; Keep the clean current page in the one-page RAM cache before loading another.
;!      out       A,carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@EditorNavRememberCurrentPage:
        LD      A,(EditorNavCacheStoreCount)
        INC     A
        LD      (EditorNavCacheStoreCount),A
        LD      HL,EditorNavPageBuffer
        LD      DE,EditorNavCachePageBuffer
        LD      BC,TECM8_EDITOR_NAV_PAGE_BYTES
        LDIR
        LD      A,(EditorNavCurrentPage)
        LD      (EditorNavCachedPage),A
        LD      A,1
        LD      (EditorNavCacheValid),A
        XOR     A
        RET

; EditorNavRenderCachedPendingPage -
; Swap the pending page from the RAM cache into the live buffer when available.
; Returns NC,A=1 on cache hit, NC,A=0 on miss, or C on render failure.
;!      out       A,carry,zero
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@EditorNavRenderCachedPendingPage:
        LD      A,(EditorNavCacheValid)
        OR      A
        RET     Z
        LD      A,(EditorNavPendingPage)
        LD      HL,EditorNavCachedPage
        CP      (HL)
        JR      NZ,EditorNavCachedPageMiss
        CALL    EditorNavSwapCachePage
        LD      A,(EditorNavCurrentPage)
        LD      (EditorNavCachedPage),A
        LD      A,(EditorNavCacheHitCount)
        INC     A
        LD      (EditorNavCacheHitCount),A
        CALL    EditorRenderPageBuffer
        RET     C
        LD      A,1
        RET

EditorNavCachedPageMiss:
        XOR     A
        RET

; EditorNavSwapCachePage -
; Exchange the live page buffer with the cached page buffer.
;!      out       A,carry,zero
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@EditorNavSwapCachePage:
        LD      HL,EditorNavPageBuffer
        LD      DE,EditorNavCachePageBuffer
        LD      BC,TECM8_EDITOR_NAV_PAGE_BYTES

EditorNavSwapCachePageLoop:
        LD      A,(HL)
        LD      (EditorNavSwapByte),A
        LD      A,(DE)
        LD      (HL),A
        LD      A,(EditorNavSwapByte)
        LD      (DE),A
        INC     HL
        INC     DE
        DEC     BC
        LD      A,B
        OR      C
        JR      NZ,EditorNavSwapCachePageLoop
        XOR     A
        RET

;!      in        A
;!      out       A,carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@EditorNavRenderPage:
        LD      (EditorNavRenderPageInput),A
        LD      HL,EditorStatusLoadingText
        CALL    EditorNavShowStatus
        RET     C
        LD      A,(EditorNavRenderPageInput)
        LD      DE,(EditorNavPathPtr)
        LD      HL,EditorNavPageBuffer
        CALL    EditorLoadSourcePage
        JR      C,EditorNavRenderPageRestoreError
        JP      EditorRenderPageBuffer

EditorNavRenderPageRestoreError:
        PUSH    AF
        CALL    EditorViewportRestoreStatusRow
        POP     AF
        RET

; EditorNavShowStatus -
; Render a transient status line before a slow storage operation.
;!      in        HL
;!      out       A,carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@EditorNavShowStatus:
        LD      (EditorPromptTextPtr),HL
        JP      EditorViewportRenderStatusOverlay

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

EditorNavRenderPageInput:
        .db     0

EditorNavCachedPage:
        .db     0

EditorNavCacheValid:
        .db     0

EditorNavCacheHitCount:
        .db     0

EditorNavCacheStoreCount:
        .db     0

EditorNavSwapByte:
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
EditorRenderPageBufferCount:
        .db     0

EditorNavBackupNamePtr:
        .dw     0

EditorNavBackupLocalPtr:
        .dw     0

EditorNavBackupSourcePtr:
        .dw     0

EditorNavBackupSuffix:
        .db     ".b",0

EditorStatusLoadingText:
        .db     "Loading...",0

EditorStatusSavingText:
        .db     "Saving...",0

EditorStatusCleanText:
        .db     "Clean",0

EditorStatusSaveFirstText:
        .db     "Save first",0

EditorStatusUnknownKeyText:
        .db     "KEY",0

EditorNavCachePageBuffer       .equ    TECM8_EDITOR_NAV_CACHE_BASE

EditorNavPageBuffer:
        .ds     TECM8_EDITOR_NAV_PAGE_BYTES
