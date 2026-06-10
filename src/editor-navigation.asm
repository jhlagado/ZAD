; TECM8 editor navigation state.
;
; Minimal storage-backed page navigation for a TM8 source path.

TECM8_EDITOR_NAV_ERR_PAGE       .equ    0x50
TECM8_EDITOR_NAV_ERR_PATH       .equ    0x51
TECM8_EDITOR_NAV_ERR_BACKUP     .equ    0x52
TECM8_EDITOR_NAV_PATH_LEN       .equ    64
TECM8_EDITOR_NAV_PAGE_BYTES     .equ    512
TECM8_EDITOR_NAV_WINDOW_BYTES   .equ    1024
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
        LD      (EditorNavNextPageValid),A
        LD      (EditorNavDirtySectors),A
        CALL    EditorNavResetViewport
        JP      EditorRenderCurrent

; EditorRenderCurrent -
; Load and render the current page.
;!      out       A,carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@EditorRenderCurrent:
        LD      A,(EditorNavCurrentPage)
        CALL    EditorNavRenderPage
        RET     C
        CALL    EditorNavLoadNextWindowPage
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
        CALL    EditorNavSyncViewport
        RET     C
        LD      HL,EditorNavPageBuffer
        CALL    EditorViewportRender
        RET     C
        CALL    GlcdTileFlushFull
        RET

; EditorNavResetViewport -
; Reset the in-page viewport to logical row 0 and mark visible row 0 current.
;!      out       A,carry
;!      clobbers  A,zero,sign,parity,halfCarry
@EditorNavResetViewport:
        XOR     A
        LD      (EditorNavViewportTopRow),A
        LD      (EditorNavCurrentRow),A
        CALL    EditorViewportSetTopRow
        RET     C
        XOR     A
        JP      EditorViewportSetCurrentRow

; EditorNavSyncViewport -
; Apply the navigation viewport top row and current row to the renderer.
;!      out       A,carry
;!      clobbers  A,BC,zero,sign,parity,halfCarry
@EditorNavSyncViewport:
        LD      A,(EditorNavViewportTopRow)
        CALL    EditorViewportSetTopRow
        RET     C
        LD      A,(EditorNavCurrentRow)
        LD      B,A
        LD      A,(EditorNavViewportTopRow)
        LD      C,A
        LD      A,B
        SUB     C
        JP      EditorViewportSetCurrentRow

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
        CALL    EditorBackupCachedPageIfDirty
        JR      C,EditorSaveCurrentPageRestoreError
        LD      A,(EditorNavDirtySectors)
        AND     1
        JR      Z,EditorSaveCurrentPageMaybeNext
        LD      A,(EditorNavCurrentPage)
        LD      DE,(EditorNavPathPtr)
        LD      HL,EditorNavPageBuffer
        CALL    EditorSaveSourcePage
        JR      C,EditorSaveCurrentPageRestoreError

EditorSaveCurrentPageMaybeNext:
        LD      A,(EditorNavDirtySectors)
        AND     2
        JR      Z,EditorSaveCurrentPageDone
        LD      A,(EditorNavNextPageValid)
        OR      A
        JR      Z,EditorSaveCurrentPageDone
        LD      A,(EditorNavCurrentPage)
        CP      127
        JR      Z,EditorSaveCurrentPageDone
        INC     A
        LD      DE,(EditorNavPathPtr)
        LD      HL,EditorNavNextPageBuffer
        CALL    EditorSaveSourcePage
        JR      C,EditorSaveCurrentPageRestoreError

EditorSaveCurrentPageDone:
        LD      A,(EditorNavCachedPageDirty)
        OR      A
        JR      Z,EditorSaveCurrentPageClean
        LD      A,(EditorNavCacheValid)
        OR      A
        JR      Z,EditorSaveCurrentPageClean
        LD      A,(EditorNavCachedPage)
        LD      DE,(EditorNavPathPtr)
        LD      HL,EditorNavCachePageBuffer
        CALL    EditorSaveSourcePage
        JR      C,EditorSaveCurrentPageRestoreError
        XOR     A
        LD      (EditorNavCachedPageDirty),A

EditorSaveCurrentPageClean:
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
        JR      C,EditorBackupCurrentPageLoadError

EditorBackupCurrentPageLoaded:
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

EditorBackupCurrentPageLoadError:
        CP      EDITOR_LOAD_ERR_SIZE
        RET     NZ
        CALL    EditorNavClearBackupPageBuffer
        JR      EditorBackupCurrentPageLoaded

; EditorBackupCachedPageIfDirty -
; Preserve the original on-disk copy of a dirty cached previous page before
; save writes that cached page back.
;!      out       A,carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@EditorBackupCachedPageIfDirty:
        LD      A,(EditorNavCachedPageDirty)
        OR      A
        JR      Z,EditorBackupCachedPageDone
        LD      A,(EditorNavCacheValid)
        OR      A
        JR      Z,EditorBackupCachedPageDone
        LD      A,(EditorNavCurrentPage)
        LD      (EditorNavBackupSavedCurrentPage),A
        LD      A,(EditorNavCachedPage)
        LD      (EditorNavCurrentPage),A
        CALL    EditorBackupCurrentPage
        JR      C,EditorBackupCachedPageError
        LD      A,(EditorNavBackupSavedCurrentPage)
        LD      (EditorNavCurrentPage),A
        XOR     A
        RET

EditorBackupCachedPageError:
        LD      (EditorNavBackupError),A
        LD      A,(EditorNavBackupSavedCurrentPage)
        LD      (EditorNavCurrentPage),A
        LD      A,(EditorNavBackupError)
        SCF
        RET

EditorBackupCachedPageDone:
        XOR     A
        RET

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
        LD      (EditorNavDirtySectors),A
        RET

; EditorMarkCurrentSectorDirty -
; Mark the active source sector dirty. Cross-sector mutations can OR in the
; adjacent-sector bit directly when they modify EditorNavNextPageBuffer.
;!      out       A,carry
;!      clobbers  A,HL,zero,sign,parity,halfCarry
@EditorMarkCurrentSectorDirty:
        LD      A,1
        LD      (EditorNavDirty),A
        LD      HL,EditorNavDirtySectors
        OR      (HL)
        LD      (HL),A
        XOR     A
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
        CALL    EditorNavRenderNextWindowPage
        RET     C
        OR      A
        JR      NZ,EditorNavCommitPendingPageFromWindow
        CALL    EditorNavRenderCachedPendingPage
        RET     C
        OR      A
        JR      NZ,EditorNavCommitPendingPagePreserveDirty
        CALL    EditorNavRememberCurrentPage
        LD      A,(EditorNavPendingPage)
        CALL    EditorNavRenderPage
        RET     C
EditorNavCommitPendingPage:
        LD      A,(EditorNavPendingPage)
        LD      (EditorNavCurrentPage),A
        CALL    EditorNavResetViewport
        RET     C
        CALL    EditorRenderPageBuffer
        RET     C
        JP      EditorClearDirty

EditorNavCommitPendingPagePreserveDirty:
        LD      A,(EditorNavPendingPage)
        LD      (EditorNavCurrentPage),A
        CALL    EditorNavResetViewport
        RET     C
        CALL    EditorRenderPageBuffer
        RET     C
        JP      EditorNavLoadNextWindowPage

EditorNavCommitPendingPageFromWindow:
        LD      A,(EditorNavPendingPage)
        LD      (EditorNavCurrentPage),A
        CALL    EditorNavResetViewport
        RET     C
        CALL    EditorRenderPageBuffer
        RET     C
        CALL    EditorNavLoadNextWindowPage
        RET     C
        XOR     A
        RET

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
        JR      NZ,EditorNavCommitPendingPagePreserveDirty
        CALL    EditorNavRememberCurrentPage
        LD      A,(EditorNavPendingPage)
        CALL    EditorNavRenderPage
        RET     C
        LD      A,(EditorNavPendingPage)
        LD      (EditorNavCurrentPage),A
        CALL    EditorNavResetViewport
        RET     C
        CALL    EditorRenderPageBuffer
        RET     C
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
        LD      A,(EditorNavDirtySectors)
        AND     1
        JR      NZ,EditorNavRememberCurrentDirtyReady
        LD      A,(EditorNavDirty)
        OR      A
        JR      Z,EditorNavRememberCurrentDirtyReady
        LD      A,1

EditorNavRememberCurrentDirtyReady:
        LD      (EditorNavCachedPageDirty),A
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
        LD      A,(EditorNavDirtySectors)
        AND     1
        LD      (EditorNavSwapByte),A
        LD      A,(EditorNavCachedPageDirty)
        OR      A
        JR      Z,EditorNavCachedCleanToCurrent
        LD      A,(EditorNavDirtySectors)
        OR      1
        JR      EditorNavCachedCurrentDirtyReady

EditorNavCachedCleanToCurrent:
        LD      A,(EditorNavDirtySectors)
        AND     0xFE

EditorNavCachedCurrentDirtyReady:
        LD      (EditorNavDirtySectors),A
        LD      A,(EditorNavSwapByte)
        LD      (EditorNavCachedPageDirty),A
        CALL    EditorNavRefreshAggregateDirty
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

; EditorNavRenderNextWindowPage -
; Slide the preloaded adjacent sector into the active page when paging down by
; one sector. Returns NC,A=1 on window hit, NC,A=0 on miss, or C on render
; failure.
;!      out       A,carry,zero
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@EditorNavRenderNextWindowPage:
        LD      A,(EditorNavNextPageValid)
        OR      A
        RET     Z
        LD      A,(EditorNavPendingPage)
        LD      HL,EditorNavCurrentPage
        DEC     A
        CP      (HL)
        JR      NZ,EditorNavNextWindowPageMiss
        CALL    EditorNavRememberCurrentPage
        CALL    EditorNavSlideNextPageToCurrent
        LD      A,(EditorNavWindowHitCount)
        INC     A
        LD      (EditorNavWindowHitCount),A
        LD      A,(EditorNavDirtySectors)
        SRL     A
        LD      (EditorNavDirtySectors),A
        CALL    EditorNavRefreshAggregateDirty
        CALL    EditorRenderPageBuffer
        RET     C
        LD      A,1
        RET

EditorNavNextWindowPageMiss:
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

; EditorNavRefreshAggregateDirty -
; Keep the legacy EditorNavDirty flag compatible with the per-sector dirty bits.
;!      out       A,carry,zero
;!      clobbers  A,zero,sign,parity,halfCarry
@EditorNavRefreshAggregateDirty:
        LD      A,(EditorNavDirtySectors)
        OR      A
        JR      NZ,EditorNavRefreshAggregateSet
        LD      A,(EditorNavCachedPageDirty)
        OR      A
        JR      Z,EditorNavRefreshAggregateClean

EditorNavRefreshAggregateSet:
        LD      A,1
        LD      (EditorNavDirty),A
        XOR     A
        RET

EditorNavRefreshAggregateClean:
        LD      (EditorNavDirty),A
        RET

; EditorNavSlideNextPageToCurrent -
; Copy the adjacent sector into the active sector buffer.
;!      out       A,carry,zero
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@EditorNavSlideNextPageToCurrent:
        LD      HL,EditorNavNextPageBuffer
        LD      DE,EditorNavPageBuffer
        LD      BC,TECM8_EDITOR_NAV_PAGE_BYTES
        LDIR
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

; EditorNavLoadNextWindowPage -
; Preload the next source sector into the adjacent window buffer. A short file
; is represented as a blank sector so edits can grow into it before save.
;!      out       A,carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@EditorNavLoadNextWindowPage:
        LD      A,(EditorNavCurrentPage)
        CP      127
        JR      Z,EditorNavNextWindowUnavailable
        INC     A
        LD      (EditorNavNextPageNumber),A
        LD      B,A
        LD      A,(EditorNavCacheValid)
        OR      A
        JR      Z,EditorNavLoadNextWindowFromDisk
        LD      A,(EditorNavCachedPage)
        CP      B
        JR      NZ,EditorNavLoadNextWindowFromDisk
        CALL    EditorNavCopyCachedPageToNext
        LD      A,(EditorNavCachedPageDirty)
        OR      A
        JR      Z,EditorNavLoadNextWindowCachedClean
        LD      A,(EditorNavDirtySectors)
        OR      2
        LD      (EditorNavDirtySectors),A
        CALL    EditorNavRefreshAggregateDirty

EditorNavLoadNextWindowCachedClean:
        LD      A,1
        LD      (EditorNavNextPageValid),A
        XOR     A
        RET

EditorNavLoadNextWindowFromDisk:
        LD      A,(EditorNavNextPageNumber)
        LD      DE,(EditorNavPathPtr)
        LD      HL,EditorNavNextPageBuffer
        CALL    EditorLoadSourcePage
        JR      C,EditorNavLoadNextWindowError
        LD      A,1
        LD      (EditorNavNextPageValid),A
        XOR     A
        RET

EditorNavLoadNextWindowError:
        CP      EDITOR_LOAD_ERR_SIZE
        RET     NZ
        CALL    EditorNavClearNextPageBuffer
        LD      A,1
        LD      (EditorNavNextPageValid),A
        XOR     A
        RET

EditorNavNextWindowUnavailable:
        XOR     A
        LD      (EditorNavNextPageValid),A
        RET

;!      out       A,carry,zero
;!      clobbers  A,BC,HL,zero,sign,parity,halfCarry
@EditorNavClearBackupPageBuffer:
        LD      HL,EditorNavBackupPageBuffer
        LD      BC,TECM8_EDITOR_NAV_PAGE_BYTES
        XOR     A

EditorNavClearBackupPageBufferLoop:
        XOR     A
        LD      (HL),A
        INC     HL
        DEC     BC
        LD      A,B
        OR      C
        JR      NZ,EditorNavClearBackupPageBufferLoop
        XOR     A
        RET

;!      out       A,carry,zero
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@EditorNavClearNextPageBuffer:
        LD      HL,EditorNavNextPageBuffer
        LD      BC,TECM8_EDITOR_NAV_PAGE_BYTES
        XOR     A

EditorNavClearNextPageBufferLoop:
        XOR     A
        LD      (HL),A
        INC     HL
        DEC     BC
        LD      A,B
        OR      C
        JR      NZ,EditorNavClearNextPageBufferLoop
        XOR     A
        RET

;!      out       A,carry,zero
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@EditorNavCopyCachedPageToNext:
        LD      HL,EditorNavCachePageBuffer
        LD      DE,EditorNavNextPageBuffer
        LD      BC,TECM8_EDITOR_NAV_PAGE_BYTES
        LDIR
        XOR     A
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

EditorNavCachedPageDirty:
        .db     0

EditorNavWindowHitCount:
        .db     0

EditorNavNextPageValid:
        .db     0

EditorNavNextPageNumber:
        .db     0

EditorNavDirtySectors:
        .db     0

EditorNavViewportTopRow:
        .db     0

EditorNavCurrentRow:
        .db     0

EditorNavSwapByte:
        .db     0

EditorNavBackupSavedCurrentPage:
        .db     0

EditorNavBackupError:
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

EditorNavNextPageBuffer:
        .ds     TECM8_EDITOR_NAV_PAGE_BYTES
