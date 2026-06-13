; TECM8 editor cursor overlay and blink handling.

; EditorCursorReset -
; Reset the visible cursor to the top-left source cell.
;! out A,carry
;! clobbers zero,sign,parity,halfCarry
@EditorCursorReset:
        XOR     A
        LD      (EditorCursorRow),A
        LD      (EditorCursorVisibleRow),A
        LD      (EditorCursorVisibleCol),A
        LD      (EditorNavCurrentRow),A
        LD      (EditorCursorCol),A
        LD      (EditorCursorRendered),A
        LD      (EditorCursorBlinkCounter),A
        LD      (EditorCursorBlinkCounterHi),A
        CALL    EditorBlockSelectionClearState
        CALL    EditorPendingBlockClearState
        CALL    EditorNavResetViewport
        RET     C
        XOR     A
        CALL    EditorViewportSetColOffset
        RET     C
        XOR     A
        JP      EditorViewportSetCurrentRow

; EditorCursorResetState -
; Reset cursor state after a page render has already reset the viewport.
;! out A,carry,zero,sign,parity,halfCarry
@EditorCursorResetState:
        XOR     A
        LD      (EditorCursorRow),A
        LD      (EditorCursorVisibleRow),A
        LD      (EditorCursorVisibleCol),A
        LD      (EditorNavCurrentRow),A
        LD      (EditorCursorCol),A
        LD      (EditorCursorRendered),A
        LD      (EditorCursorBlinkCounter),A
        LD      (EditorCursorBlinkCounterHi),A
        CALL    EditorBlockSelectionClearState
        RET

; EditorCursorResetStateKeepSelection -
; Reset cursor state after a page render while preserving block selection.
;! out carry,zero,A,sign,parity,halfCarry
@EditorCursorResetStateKeepSelection:
        XOR     A
        LD      (EditorCursorRow),A
        LD      (EditorCursorVisibleRow),A
        LD      (EditorCursorVisibleCol),A
        LD      (EditorNavCurrentRow),A
        LD      (EditorCursorCol),A
        LD      (EditorCursorRendered),A
        LD      (EditorCursorBlinkCounter),A
        LD      (EditorCursorBlinkCounterHi),A
        RET

; EditorRenderCursor -
; Overlay the logical cursor when it is inside the visible edit pane.
;! out A,carry,zero
;! clobbers sign,parity,halfCarry,BC,DE,HL
@EditorRenderCursor:
        LD      A,(EditorCursorRendered)
        OR      A
        JR      Z,EditorCursorRenderCheckVisible
        LD      A,(EditorCursorRenderedCol)
        LD      C,A
        LD      A,(EditorCursorRenderedRow)
        CALL    DisplayEraseCursorCell
        RET     C
        XOR     A
        LD      (EditorCursorRendered),A

EditorCursorRenderCheckVisible:
        LD      A,(EditorCursorVisibleCol)
        CP      TECM8_EDITOR_CURSOR_VISIBLE_COLS
        JR      NC,EditorCursorRenderDone
        LD      C,A
        LD      A,(EditorCursorVisibleRow)
        CP      TECM8_EDITOR_CURSOR_VISIBLE_ROWS
        JR      NC,EditorCursorRenderDone
        CALL    DisplayRenderCursorCell
        RET     C
        LD      A,(EditorCursorVisibleRow)
        LD      (EditorCursorRenderedRow),A
        LD      A,(EditorCursorVisibleCol)
        LD      (EditorCursorRenderedCol),A
        LD      A,1
        LD      (EditorCursorRendered),A

EditorCursorRenderDone:
        XOR     A
        RET

; EditorHideCursor -
; Erase any rendered cursor without drawing a replacement.
;! out A,carry,zero
;! clobbers sign,parity,halfCarry,BC,DE,HL
@EditorHideCursor:
        LD      A,(EditorCursorRendered)
        OR      A
        JR      Z,EditorHideCursorDone
        LD      A,(EditorCursorRenderedCol)
        LD      C,A
        LD      A,(EditorCursorRenderedRow)
        CALL    DisplayEraseCursorCell
        RET     C
        XOR     A
        LD      (EditorCursorRendered),A

EditorHideCursorDone:
        XOR     A
        RET

; EditorCursorBlinkReset -
; Restart the idle blink countdown after a key event or explicit cursor render.
;! out A,carry,zero,sign,parity,halfCarry
;! clobbers HL
@EditorCursorBlinkReset:
        LD      HL,TECM8_EDITOR_CURSOR_BLINK_IDLE_TICKS
        LD      (EditorCursorBlinkCounter),HL
        XOR     A
        RET

; EditorCursorBlinkStep -
; Advance the cooperative cursor blink state once from the live idle path.
;! out A,carry,zero
;! clobbers sign,parity,halfCarry,BC,DE,HL
@EditorCursorBlinkStep:
        LD      A,(EditorPromptActive)
        OR      A
        JR      NZ,EditorCursorBlinkNoop
        LD      HL,(EditorCursorBlinkCounter)
        LD      A,H
        OR      L
        JR      Z,EditorCursorBlinkDue
        DEC     HL
        LD      (EditorCursorBlinkCounter),HL
        LD      A,H
        OR      L
        JR      Z,EditorCursorBlinkDue
        XOR     A
        RET

EditorCursorBlinkDue:
        LD      HL,TECM8_EDITOR_CURSOR_BLINK_IDLE_TICKS
        LD      (EditorCursorBlinkCounter),HL
        LD      A,(EditorCursorBlinkToggleCount)
        INC     A
        LD      (EditorCursorBlinkToggleCount),A
        LD      A,(EditorCursorRendered)
        OR      A
        JR      NZ,EditorCursorBlinkHide
        CALL    EditorRenderCursor
        RET     C
        XOR     A
        RET

EditorCursorBlinkHide:
        CALL    EditorHideCursor
        RET     C

EditorCursorBlinkNoop:
        XOR     A
        RET

; EditorInvalidateCursorOverlay -
; Mark the cursor overlay absent after a full redraw replaces the pixels under it.
;! out carry,zero,A,sign,parity,halfCarry
@EditorInvalidateCursorOverlay:
        XOR     A
        LD      (EditorCursorRendered),A
        RET
