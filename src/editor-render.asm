; TECM8 editor dirty render policy and viewport visibility helpers.

;! out A,carry,zero
;! clobbers sign,parity,halfCarry,BC,DE,HL
@EditorKeyRenderDirty:
        CALL    EditorMarkDirty
        CALL    EditorHideCursor
        RET     C
        CALL    EditorEnsureCursorVisible
        RET     C
        CALL    EditorEnsureCursorVisibleColumn
        RET     C
        CALL    EditorRenderPageBuffer
        RET     C
        XOR     A
        RET

;! out A,carry,zero
;! clobbers sign,parity,halfCarry,BC,DE,HL
@EditorKeyRenderCurrentLineDirty:
        CALL    EditorMarkDirty
        CALL    EditorHideCursor
        RET     C
        CALL    EditorEnsureCursorVisible
        RET     C
        OR      A
        JP      NZ,EditorKeyRenderViewport
        CALL    EditorEnsureCursorVisibleColumn
        RET     C
        OR      A
        JP      NZ,EditorKeyRenderViewport
        CALL    EditorKeyCurrentRecord
        LD      A,(EditorCursorVisibleRow)
        CALL    EditorViewportRenderRecordRow
        RET     C
        LD      A,(EditorCursorVisibleRow)
        CALL    GlcdTileMarkRowDirty
        RET     C
        XOR     A
        RET

;! out A,carry,zero
;! clobbers sign,parity,halfCarry,BC,DE,HL
@EditorKeyRenderCurrentLineCellsDirty:
        CALL    EditorMarkDirty
        CALL    EditorHideCursor
        RET     C
        CALL    EditorEnsureCursorVisible
        RET     C
        OR      A
        JP      NZ,EditorKeyRenderViewport
        CALL    EditorEnsureCursorVisibleColumn
        RET     C
        OR      A
        JP      NZ,EditorKeyRenderViewport
        CALL    EditorKeyCurrentRecord
        LD      A,(EditorCursorVisibleRow)
        CALL    EditorViewportRenderRecordRow
        RET     C
        LD      A,(EditorLineDirtyEndCol)
        LD      B,A
        LD      A,(EditorViewportColOffset)
        LD      C,A
        LD      A,B
        CP      C
        JR      C,EditorKeyRenderCurrentLineCellsDone
        LD      A,(EditorViewportColOffset)
        ADD     A,TECM8_EDITOR_CURSOR_VISIBLE_COLS
        LD      C,A
        LD      A,(EditorLineDirtyStartCol)
        CP      C
        JR      NC,EditorKeyRenderCurrentLineCellsDone
        LD      A,(EditorLineDirtyStartCol)
        LD      B,A
        LD      A,(EditorViewportColOffset)
        LD      C,A
        LD      A,B
        CP      C
        JR      C,EditorKeyRenderCurrentLineCellsStartZero
        SUB     C
        JR      EditorKeyRenderCurrentLineCellsStartReady

EditorKeyRenderCurrentLineCellsStartZero:
        XOR     A

EditorKeyRenderCurrentLineCellsStartReady:
        LD      (EditorLineDirtyVisibleStart),A
        LD      A,(EditorViewportColOffset)
        ADD     A,TECM8_EDITOR_CURSOR_VISIBLE_COLS
        LD      C,A
        LD      A,(EditorLineDirtyEndCol)
        CP      C
        JR      NC,EditorKeyRenderCurrentLineCellsEndMax
        LD      B,A
        LD      A,(EditorViewportColOffset)
        LD      C,A
        LD      A,B
        SUB     C
        JR      EditorKeyRenderCurrentLineCellsEndReady

EditorKeyRenderCurrentLineCellsEndMax:
        LD      A,TECM8_EDITOR_CURSOR_VISIBLE_COLS - 1

EditorKeyRenderCurrentLineCellsEndReady:
        LD      (EditorLineDirtyVisibleEnd),A
        LD      A,(EditorCursorVisibleRow)
        LD      B,A
        LD      A,(EditorLineDirtyVisibleStart)
        LD      C,A
        CALL    GlcdTileMarkCellDirty
        RET     C
        LD      A,(EditorLineDirtyVisibleEnd)
        LD      C,A
        LD      A,(EditorLineDirtyVisibleStart)
        CP      C
        JR      Z,EditorKeyRenderCurrentLineCellsDone
        LD      A,(EditorCursorVisibleRow)
        LD      B,A
        LD      A,(EditorLineDirtyVisibleEnd)
        LD      C,A
        CALL    GlcdTileMarkCellDirty
        RET     C

EditorKeyRenderCurrentLineCellsDone:
        XOR     A
        RET

;! out A,carry,zero
;! clobbers sign,parity,halfCarry,BC,DE,HL
@EditorKeyRenderCursorRowMarkers:
        CALL    EditorHideCursor
        RET     C
        CALL    EditorEnsureCursorVisible
        RET     C
        LD      A,(EditorBlockSelectionActive)
        LD      B,A
        LD      A,(EditorPendingBlockMode)
        OR      B
        JR      NZ,EditorKeyRenderCursorRowMarkersNeeded
        LD      A,(EditorCursorVisibleRow)
        CALL    EditorViewportSetCurrentRow
        RET     C
        XOR     A
        RET

EditorKeyRenderCursorRowMarkersNeeded:
        LD      A,0xFF
        LD      (EditorCursorPreviousVisibleRow),A
        LD      A,(EditorCursorVisibleRow)
        CALL    EditorViewportSetCurrentRow
        RET     C
        LD      A,(EditorCursorPreviousRow)
        ; expects out A
        CALL    EditorLogicalRowVisible
        JR      C,EditorKeyRenderCursorNewOnly
        LD      (EditorCursorPreviousVisibleRow),A
        LD      A,(EditorCursorPreviousVisibleRow)
        CALL    EditorViewportRenderRowMarker
        RET     C
EditorKeyRenderCursorNewOnly:
        LD      A,(EditorCursorVisibleRow)
        CALL    EditorViewportRenderRowMarker
        RET     C
        LD      A,(EditorCursorPreviousVisibleRow)
        CP      0xFF
        JR      Z,EditorKeyRenderCursorFlushCurrent
        CALL    GlcdTileMarkGutterDirty
        RET     C
EditorKeyRenderCursorFlushCurrent:
        LD      A,(EditorCursorVisibleRow)
        CALL    GlcdTileMarkGutterDirty
        RET     C
        XOR     A
        RET

;! out A,carry
;! clobbers zero,sign,parity,halfCarry,BC,DE,HL
@EditorKeyRenderCursorMove:
        CALL    EditorEnsureCursorVisible
        RET     C
        OR      A
        JP      NZ,EditorKeyRenderViewport
        CALL    EditorEnsureCursorVisibleColumn
        RET     C
        OR      A
        JP      NZ,EditorKeyRenderViewport
        JP      EditorKeyRenderCursorRowMarkers

;! out A,carry,zero
;! clobbers sign,parity,halfCarry,BC,DE,HL
@EditorKeyRenderCursorColumnMove:
        CALL    EditorEnsureCursorVisibleColumn
        RET     C
        OR      A
        JP      NZ,EditorKeyRenderViewport
        XOR     A
        RET

;! out A,carry,zero
;! clobbers sign,parity,halfCarry,BC,DE,HL
@EditorKeyRenderViewport:
        CALL    EditorRenderPageBuffer
        RET     C
        JP      EditorInvalidateCursorOverlay

; EditorEnsureCursorVisible -
; Keep the 16-row logical cursor inside the 10-row GLCD viewport.
; Returns A=1 when the viewport top changed, A=0 when it did not.
;! out A,carry,zero
;! clobbers sign,parity,halfCarry,BC
@EditorEnsureCursorVisible:
        LD      A,(EditorCursorRow)
        LD      B,A
        LD      A,(EditorNavViewportTopRow)
        LD      C,A
        LD      A,B
        CP      C
        JR      C,EditorEnsureCursorScrollUp
        LD      A,C
        ADD     A,TECM8_EDITOR_CURSOR_VISIBLE_ROWS
        LD      C,A
        LD      A,B
        CP      C
        JR      NC,EditorEnsureCursorScrollDown
        LD      A,B
        LD      C,A
        LD      A,(EditorNavViewportTopRow)
        LD      B,A
        LD      A,C
        SUB     B
        LD      (EditorCursorVisibleRow),A
        LD      A,C
        LD      (EditorNavCurrentRow),A
        XOR     A
        RET

EditorEnsureCursorScrollUp:
        LD      A,(EditorCursorRow)
        LD      (EditorNavViewportTopRow),A
        LD      (EditorNavCurrentRow),A
        CALL    EditorNavSyncViewport
        RET     C
        XOR     A
        LD      (EditorCursorVisibleRow),A
        LD      A,1
        OR      A
        RET

EditorEnsureCursorScrollDown:
        LD      A,(EditorCursorRow)
        LD      (EditorNavCurrentRow),A
        SUB     TECM8_EDITOR_CURSOR_VISIBLE_ROWS - 1
        LD      (EditorNavViewportTopRow),A
        CALL    EditorNavSyncViewport
        RET     C
        LD      A,TECM8_EDITOR_CURSOR_VISIBLE_ROWS - 1
        LD      (EditorCursorVisibleRow),A
        LD      A,1
        OR      A
        RET

; EditorEnsureCursorVisibleColumn -
; Keep the 31-column logical cursor inside the 20-column GLCD text viewport.
; Returns A=1 when the horizontal viewport changed, A=0 when it did not.
;! out A,carry,zero
;! clobbers sign,parity,halfCarry,BC
@EditorEnsureCursorVisibleColumn:
        LD      A,(EditorCursorCol)
        LD      B,A
        LD      A,(EditorViewportColOffset)
        LD      C,A
        LD      A,B
        CP      C
        JR      C,EditorEnsureCursorColumnScrollLeft
        LD      A,C
        ADD     A,TECM8_EDITOR_CURSOR_VISIBLE_COLS
        LD      C,A
        LD      A,B
        CP      C
        JR      NC,EditorEnsureCursorColumnScrollRight
        LD      A,B
        LD      C,A
        LD      A,(EditorViewportColOffset)
        LD      B,A
        LD      A,C
        SUB     B
        LD      (EditorCursorVisibleCol),A
        XOR     A
        RET

EditorEnsureCursorColumnScrollLeft:
        LD      A,(EditorCursorCol)
        CALL    EditorViewportSetColOffset
        RET     C
        XOR     A
        LD      (EditorCursorVisibleCol),A
        LD      A,1
        OR      A
        RET

EditorEnsureCursorColumnScrollRight:
        LD      A,(EditorCursorCol)
        SUB     TECM8_EDITOR_CURSOR_VISIBLE_COLS - 1
        CALL    EditorViewportSetColOffset
        RET     C
        LD      A,TECM8_EDITOR_CURSOR_VISIBLE_COLS - 1
        LD      (EditorCursorVisibleCol),A
        LD      A,1
        OR      A
        RET

;! in A
;! out A,carry,zero
;! clobbers sign,parity,halfCarry,BC
@EditorLogicalRowVisible:
        LD      B,A
        LD      A,(EditorNavViewportTopRow)
        CP      B
        JR      Z,EditorLogicalRowVisibleTop
        JR      NC,EditorLogicalRowHidden

EditorLogicalRowVisibleTop:
        LD      A,B
        LD      B,A
        LD      A,(EditorNavViewportTopRow)
        LD      C,A
        LD      A,B
        SUB     C
        CP      TECM8_EDITOR_CURSOR_VISIBLE_ROWS
        JR      NC,EditorLogicalRowHidden
        XOR     A
        LD      A,B
        LD      B,A
        LD      A,(EditorNavViewportTopRow)
        LD      C,A
        LD      A,B
        SUB     C
        RET

EditorLogicalRowHidden:
        SCF
        RET

;! out A,carry
;! clobbers zero,sign,parity,halfCarry,HL
@EditorMarkDirty:
        JP      EditorMarkCurrentSectorDirty

EditorLineDirtyStartCol:
        .db     0

EditorLineDirtyEndCol:
        .db     0

EditorLineDirtyVisibleStart:
        .db     0

EditorLineDirtyVisibleEnd:
        .db     0
