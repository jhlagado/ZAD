; TECM8 editor navigation state.
;
; Minimal storage-backed page navigation for a TM8 source path.

TECM8_EDITOR_NAV_ERR_PAGE       .equ    0x50
TECM8_EDITOR_NAV_ERR_PATH       .equ    0x51
TECM8_EDITOR_NAV_ERR_BACKUP     .equ    0x52
TECM8_EDITOR_NAV_PATH_LEN       .equ    64
TECM8_EDITOR_NAV_PAGE_BYTES     .equ    TECM8_SECTOR_BYTES
TECM8_EDITOR_NAV_WINDOW_BYTES   .equ    TECM8_SECTOR_BYTES * 2
TECM8_EDITOR_NAV_WORKSPACE_BASE .equ    0x3000
TECM8_EDITOR_NAV_CACHE_BASE     .equ    0x3000
TECM8_EDITOR_NAV_PAGE_BASE      .equ    0x3200
TECM8_EDITOR_NAV_NEXT_BASE      .equ    0x3400
TECM8_EDITOR_NAV_BACKUP_BASE    .equ    0x3600
TECM8_EDITOR_NAV_WORKSPACE_END  .equ    0x3800

; EditorOpenMain -
; Reset navigation to page 0 and render /src/main.asm.
;! out A,carry
;! clobbers zero,sign,parity,halfCarry,BC,DE,HL
@EditorOpenMain:
        LD      HL,EditorNavMainPath
        JP      EditorOpenPath

; EditorOpenPath -
; Reset navigation to page 0 and render the source file at HL.
;! in HL
;! out A,carry
;! clobbers zero,sign,parity,halfCarry,BC,DE,HL
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
        LD      (EditorNavNextPageSynthetic),A
        LD      (EditorNavDirtySectors),A
        CALL    EditorNavResetViewport
        JP      EditorRenderCurrent

; EditorRenderCurrent -
; Load and render the current page.
;! out A,carry
;! clobbers zero,sign,parity,halfCarry,BC,DE,HL
@EditorRenderCurrent:
        LD      A,(EditorNavCurrentPage)
        CALL    EditorNavRenderPage
        RET     C
        CALL    EditorNavLoadNextWindowPage
        RET     C
        JP      EditorClearDirty

; EditorRenderPageBuffer -
; Render the already-loaded page buffer without reloading it from storage.
;! out carry,A
;! clobbers zero,sign,parity,halfCarry,BC,DE,HL
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
; Reset the in-page viewport to logical row 0 and sync cursor row bookkeeping.
;! out A,carry
;! clobbers zero,sign,parity,halfCarry
@EditorNavResetViewport:
        XOR     A
        LD      (EditorNavViewportTopRow),A
        LD      (EditorNavCurrentRow),A
        CALL    EditorViewportSetTopRow
        RET     C
        XOR     A
        CALL    EditorViewportSetColOffset
        RET     C
        XOR     A
        JP      EditorViewportSetCurrentRow

; EditorNavSyncViewport -
; Apply the navigation viewport top row and current row to the renderer.
;! out A,carry
;! clobbers zero,sign,parity,halfCarry,BC
@EditorNavSyncViewport:
        LD      A,(EditorNavCurrentPage)
        CALL    EditorViewportSetCurrentPage
        RET     C
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
;! out A,carry
;! clobbers zero,sign,parity,halfCarry,BC,DE,HL
@EditorSaveCurrentPage:
        LD      HL,EditorStatusSavingText
        CALL    EditorNavShowStatus
        RET     C
        CALL    EditorBackupCurrentPage
        JR      C,EditorSaveCurrentPageRestoreError
        CALL    EditorBackupCachedPageIfDirty
        JR      C,EditorSaveCurrentPageRestoreError
        CALL    EditorBackupNextPageIfDirty
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
        XOR     A
        LD      (EditorNavNextPageSynthetic),A

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
;! out A,carry,zero
;! clobbers sign,parity,halfCarry,BC,DE,HL
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
        JR      NZ,EditorBackupCurrentPageError
        LD      DE,EditorNavBackupPathBuffer
        CALL    EditorCreateSourceFile
        RET     C
        LD      A,(EditorNavCurrentPage)
        LD      DE,EditorNavBackupPathBuffer
        LD      HL,EditorNavBackupPageBuffer
        JP      EditorSaveSourcePage

EditorBackupCurrentPageLoadError:
        CP      EDITOR_LOAD_ERR_SIZE
        JR      NZ,EditorBackupCurrentPageError
        CALL    EditorNavClearBackupPageBuffer
        JR      EditorBackupCurrentPageLoaded

EditorBackupCurrentPageError:
        SCF
        RET

; EditorBackupCachedPageIfDirty -
; Preserve the original on-disk copy of a dirty cached previous page before
; save writes that cached page back.
;! out A,carry,zero
;! clobbers sign,parity,halfCarry,BC,DE,HL
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

; EditorBackupNextPageIfDirty -
; Preserve the original on-disk copy of a dirty adjacent next page before save
; writes the resident next-page buffer back.
;! out A,carry,zero
;! clobbers sign,parity,halfCarry,BC,DE,HL
@EditorBackupNextPageIfDirty:
        LD      A,(EditorNavDirtySectors)
        AND     2
        JR      Z,EditorBackupNextPageDone
        LD      A,(EditorNavNextPageValid)
        OR      A
        JR      Z,EditorBackupNextPageDone
        LD      A,(EditorNavCurrentPage)
        CP      127
        JR      Z,EditorBackupNextPageDone
        LD      (EditorNavBackupSavedCurrentPage),A
        INC     A
        LD      (EditorNavCurrentPage),A
        CALL    EditorBackupCurrentPage
        JR      C,EditorBackupNextPageError
        LD      A,(EditorNavBackupSavedCurrentPage)
        LD      (EditorNavCurrentPage),A
        XOR     A
        RET

EditorBackupNextPageError:
        LD      (EditorNavBackupError),A
        LD      A,(EditorNavBackupSavedCurrentPage)
        LD      (EditorNavCurrentPage),A
        LD      A,(EditorNavBackupError)
        SCF
        RET

EditorBackupNextPageDone:
        XOR     A
        RET

; EditorLoadCurrentBackupPage -
; Load the derived hidden backup path into the current page buffer.
;! out A,carry
;! clobbers zero,sign,parity,halfCarry,BC,DE,HL
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

; EditorLoadCurrentBackupWindow -
; Restore the current backup page and any resident adjacent next page.
;! out A,carry,zero
;! clobbers sign,parity,halfCarry,BC,DE,HL
@EditorLoadCurrentBackupWindow:
        CALL    EditorLoadCurrentBackupPage
        RET     C
        LD      A,(EditorNavDirtySectors)
        OR      1
        LD      (EditorNavDirtySectors),A
        LD      A,(EditorNavNextPageValid)
        OR      A
        JR      Z,EditorLoadCurrentBackupWindowDone
        LD      A,(EditorNavCurrentPage)
        CP      127
        JR      Z,EditorLoadCurrentBackupWindowDone
        INC     A
        LD      DE,EditorNavBackupPathBuffer
        LD      HL,EditorNavNextPageBuffer
        CALL    EditorLoadSourcePage
        JR      C,EditorLoadCurrentBackupWindowNextError
        LD      A,(EditorNavDirtySectors)
        OR      2
        LD      (EditorNavDirtySectors),A
        CALL    EditorNavRefreshAggregateDirty
        XOR     A
        RET

EditorLoadCurrentBackupWindowNextError:
        CP      EDITOR_LOAD_ERR_SIZE
        JR      NZ,EditorLoadCurrentBackupWindowError
        CALL    EditorNavClearNextPageBuffer
        LD      A,(EditorNavDirtySectors)
        OR      2
        LD      (EditorNavDirtySectors),A
        CALL    EditorNavRefreshAggregateDirty
        XOR     A
        RET

EditorLoadCurrentBackupWindowDone:
        CALL    EditorNavRefreshAggregateDirty
        XOR     A
        RET

EditorLoadCurrentBackupWindowError:
        SCF
        RET

; EditorClearDirty -
; Mark the current editor page clean after a successful load or save.
;! out carry,zero,A
;! clobbers sign,parity,halfCarry
@EditorClearDirty:
        XOR     A
        LD      (EditorNavDirty),A
        LD      (EditorNavDirtySectors),A
        RET

; EditorMarkCurrentSectorDirty -
; Mark the active source sector dirty. Cross-sector mutations can OR in the
; adjacent-sector bit directly when they modify EditorNavNextPageBuffer.
;! out A,carry,zero
;! clobbers sign,parity,halfCarry,HL
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
;! out A,carry,zero
;! clobbers sign,parity,halfCarry,BC,DE,HL
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
;! out A,carry
;! clobbers zero,sign,parity,halfCarry,BC,DE,HL
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
;! out A,carry,zero
;! clobbers sign,parity,halfCarry,BC,DE,HL
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
;! out A,carry,zero
;! clobbers sign,parity,halfCarry,BC,DE,HL
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
;! out A,carry,zero
;! clobbers sign,parity,halfCarry,BC,DE,HL
@EditorNavRenderNextWindowPage:
        LD      A,(EditorNavNextPageValid)
        OR      A
        RET     Z
        LD      A,(EditorNavPendingPage)
        LD      HL,EditorNavCurrentPage
        DEC     A
        CP      (HL)
        JR      NZ,EditorNavNextWindowPageMiss
        LD      A,(EditorNavNextPageSynthetic)
        OR      A
        JR      Z,EditorNavNextWindowPageReady
        LD      A,(EditorNavDirtySectors)
        AND     2
        JP      Z,EditorNavPageErr

EditorNavNextWindowPageReady:
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
;! out DE,HL,A,carry,zero
;! clobbers sign,parity,halfCarry,BC
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
;! out carry,zero,A
;! clobbers sign,parity,halfCarry
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
;! out A,carry,zero
;! clobbers sign,parity,halfCarry,BC,DE,HL
@EditorNavSlideNextPageToCurrent:
        LD      HL,EditorNavNextPageBuffer
        LD      DE,EditorNavPageBuffer
        LD      BC,TECM8_EDITOR_NAV_PAGE_BYTES
        LDIR
        XOR     A
        RET

;! in A
;! out A,carry
;! clobbers zero,sign,parity,halfCarry,BC,DE,HL
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
        SCF
        RET

; EditorNavLoadNextWindowPage -
; Preload the next source sector into the adjacent window buffer. A short file
; is represented as a blank sector so edits can grow into it before save.
;! out carry,zero,A
;! clobbers sign,parity,halfCarry,BC,DE,HL
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
        XOR     A
        LD      (EditorNavNextPageSynthetic),A
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
        XOR     A
        LD      (EditorNavNextPageSynthetic),A
        LD      A,1
        LD      (EditorNavNextPageValid),A
        XOR     A
        RET

EditorNavLoadNextWindowError:
        CP      EDITOR_LOAD_ERR_SIZE
        RET     NZ
        CALL    EditorNavClearNextPageBuffer
        LD      A,1
        LD      (EditorNavNextPageSynthetic),A
        LD      A,1
        LD      (EditorNavNextPageValid),A
        XOR     A
        RET

EditorNavNextWindowUnavailable:
        XOR     A
        LD      (EditorNavNextPageValid),A
        LD      (EditorNavNextPageSynthetic),A
        RET

;! out HL,A,carry,zero
;! clobbers sign,parity,halfCarry,BC
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

;! out HL,A,carry,zero
;! clobbers sign,parity,halfCarry,BC,DE
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

;! out A,carry,zero
;! clobbers sign,parity,halfCarry,BC,DE,HL
@EditorNavCopyCachedPageToNext:
        LD      HL,EditorNavCachePageBuffer
        LD      DE,EditorNavNextPageBuffer
        LD      BC,TECM8_EDITOR_NAV_PAGE_BYTES
        LDIR
        XOR     A
        RET

; EditorNavShowStatus -
; Render a transient status line before a slow storage operation.
;! in HL
;! out A,carry
;! clobbers zero,sign,parity,halfCarry,BC,DE,HL
@EditorNavShowStatus:
        LD      (EditorPromptTextPtr),HL
        JP      EditorViewportRenderStatusOverlay

; EditorNavShowError -
; Render a compact status-row error for an editor/storage error code.
; Input: A = error code
;! in A
;! out A,carry
;! clobbers zero,sign,parity,halfCarry,BC,DE,HL
@EditorNavShowError:
        LD      (EditorLastErrorCode),A
        ; expects out HL
        CALL    EditorNavErrorTextForCode
        LD      (EditorLastErrorTextPtr),HL
        JP      EditorNavShowStatus

; EditorNavErrorTextForCode -
; Map compact editor error codes to short user-visible text.
; Input: A = error code
; Output: HL = NUL-terminated message
;! in A
;! out HL,A,carry,zero
;! clobbers sign,parity,halfCarry
@EditorNavErrorTextForCode:
        CP      EDITOR_LOAD_ERR_OPEN
        JR      Z,EditorNavErrTextOpen
        CP      EDITOR_LOAD_ERR_SUPER
        JR      Z,EditorNavErrTextVolume
        CP      EDITOR_LOAD_ERR_PREFIX
        JR      Z,EditorNavErrTextPrefix
        CP      EDITOR_LOAD_ERR_FIND
        JR      Z,EditorNavErrTextFind
        CP      EDITOR_LOAD_ERR_SIZE
        JR      Z,EditorNavErrTextSize
        CP      EDITOR_LOAD_ERR_READ
        JR      Z,EditorNavErrTextRead
        CP      EDITOR_LOAD_ERR_BLOCK
        JR      Z,EditorNavErrTextAlloc
        CP      EDITOR_LOAD_ERR_PAGE
        JR      Z,EditorNavErrTextPage
        CP      EDITOR_LOAD_ERR_WRITE
        JR      Z,EditorNavErrTextWrite
        CP      EDITOR_LOAD_ERR_CREATE
        JR      Z,EditorNavErrTextFull
        CP      TECM8_EDITOR_NAV_ERR_PAGE
        JR      Z,EditorNavErrTextPage
        CP      TECM8_EDITOR_NAV_ERR_PATH
        JR      Z,EditorNavErrTextPath
        CP      TECM8_EDITOR_NAV_ERR_BACKUP
        JR      Z,EditorNavErrTextBackup
        CP      TECM8_EDITOR_ERR_ROW
        JR      Z,EditorNavErrTextView
        LD      HL,EditorErrUnknownText
        XOR     A
        RET

EditorNavErrTextOpen:
        LD      HL,EditorErrOpenText
        XOR     A
        RET

EditorNavErrTextVolume:
        LD      HL,EditorErrVolumeText
        XOR     A
        RET

EditorNavErrTextPrefix:
        LD      HL,EditorErrPrefixText
        XOR     A
        RET

EditorNavErrTextFind:
        LD      HL,EditorErrFindText
        XOR     A
        RET

EditorNavErrTextSize:
        LD      HL,EditorErrSizeText
        XOR     A
        RET

EditorNavErrTextRead:
        LD      HL,EditorErrReadText
        XOR     A
        RET

EditorNavErrTextAlloc:
        LD      HL,EditorErrAllocText
        XOR     A
        RET

EditorNavErrTextPage:
        LD      HL,EditorErrPageText
        XOR     A
        RET

EditorNavErrTextWrite:
        LD      HL,EditorErrWriteText
        XOR     A
        RET

EditorNavErrTextFull:
        LD      HL,EditorErrFullText
        XOR     A
        RET

EditorNavErrTextPath:
        LD      HL,EditorErrPathText
        XOR     A
        RET

EditorNavErrTextBackup:
        LD      HL,EditorErrBackupText
        XOR     A
        RET

EditorNavErrTextView:
        LD      HL,EditorErrViewText
        XOR     A
        RET

EditorNavPageErr:
        LD      A,TECM8_EDITOR_NAV_ERR_PAGE
        SCF
        RET

;! in B,DE,HL
;! out DE,HL,A,B,carry,zero
;! clobbers sign,parity,halfCarry
@EditorNavCopyPath:
        CALL    Tecm8StringCopyNulBounded
        RET     NC

EditorNavPathErr:
        LD      A,TECM8_EDITOR_NAV_ERR_PATH
        SCF
        RET

;! in B,DE,HL
;! out DE,HL,A,C,carry,zero
;! clobbers sign,parity,halfCarry,B
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

EditorNavNextPageSynthetic:
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

EditorErrOpenText:
        .db     "ERR OPEN 30",0

EditorErrVolumeText:
        .db     "ERR VOL 31",0

EditorErrPrefixText:
        .db     "ERR PREFIX 32",0

EditorErrFindText:
        .db     "ERR FIND 33",0

EditorErrSizeText:
        .db     "ERR SIZE 34",0

EditorErrReadText:
        .db     "ERR READ 35",0

EditorErrAllocText:
        .db     "ERR ALLOC 36",0

EditorErrPageText:
        .db     "ERR PAGE 37",0

EditorErrWriteText:
        .db     "ERR WRITE 38",0

EditorErrFullText:
        .db     "ERR FULL 39",0

EditorErrPathText:
        .db     "ERR PATH 51",0

EditorErrBackupText:
        .db     "ERR BACKUP 52",0

EditorErrViewText:
        .db     "ERR VIEW 02",0

EditorErrUnknownText:
        .db     "ERR CODE",0

EditorLastErrorCode:
        .db     0

EditorLastErrorTextPtr:
        .dw     0

EditorNavCachePageBuffer       .equ    TECM8_EDITOR_NAV_CACHE_BASE

EditorNavPageBuffer            .equ    TECM8_EDITOR_NAV_PAGE_BASE

EditorNavNextPageBuffer        .equ    TECM8_EDITOR_NAV_NEXT_BASE

EditorNavBackupPageBuffer      .equ    TECM8_EDITOR_NAV_BACKUP_BASE
