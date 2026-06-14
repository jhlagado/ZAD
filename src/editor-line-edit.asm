; TECM8 editor line mutation routines.

; EditorInsertChar -
; Insert printable A into the current fixed-width source record.
; Returns A=1 when the buffer changed, A=0 when insertion was a no-op.
;! in A
;! out A,carry,zero
;! clobbers sign,parity,halfCarry,BC,DE,HL
@EditorInsertChar:
        LD      (EditorPendingChar),A
        CALL    EditorKeyCurrentRecord
        CALL    EditorKeyReadRecordLength
        CP      TECM8_EDITOR_EDIT_RECORD_TEXT_MAX
        JR      NC,EditorInsertDone
        LD      (EditorLineLength),A
        LD      B,A
        LD      A,(EditorCursorCol)
        CP      B
        JR      C,EditorInsertColReady
        JR      Z,EditorInsertColReady
        LD      A,B
        LD      (EditorCursorCol),A

EditorInsertColReady:
        LD      C,A
        LD      (EditorLineDirtyStartCol),A
        LD      A,(EditorLineLength)
        LD      (EditorLineDirtyEndCol),A
        LD      A,B
        SUB     C
        LD      B,A
        LD      (EditorRecordBase),HL
        LD      HL,(EditorRecordBase)
        CALL    Tecm8RecordShiftTextRight

EditorInsertWriteChar:
        LD      HL,(EditorRecordBase)
        INC     HL
        LD      D,0
        LD      A,(EditorCursorCol)
        LD      E,A
        ADD     HL,DE
        LD      A,(EditorPendingChar)
        LD      (HL),A
        LD      HL,(EditorRecordBase)
        LD      A,(EditorLineLength)
        INC     A
        CALL    EditorKeyWriteRecordLength
        CALL    EditorKeyAdvanceCursor
        LD      A,1
        RET

EditorInsertDone:
        XOR     A
        RET

; EditorBackspaceChar -
; Delete the character before the cursor in the current source record.
; Returns A=1 when the buffer changed, A=0 when backspace was a no-op.
;! out A,carry,zero
;! clobbers sign,parity,halfCarry,BC,DE,HL
@EditorBackspaceChar:
        LD      A,(EditorCursorCol)
        OR      A
        JP      Z,EditorJoinPreviousLine
        DEC     A
        LD      (EditorCursorCol),A
        CALL    EditorDeleteChar
        RET

EditorBackspaceDone:
        XOR     A
        RET

; EditorSplitLine -
; Split the current fixed-width source record at the cursor. The split is a
; no-op when the cursor is on the final page row or the final record is in use.
; Returns A=1 when the buffer changed, A=0 when the split was a no-op.
;! out A,carry,zero
;! clobbers sign,parity,halfCarry,BC,DE,HL
@EditorSplitLine:
        LD      A,(EditorCursorRow)
        CP      15
        JP      Z,EditorSplitFinalRow
        JP      NC,EditorSplitDone

        LD      A,15
        CALL    EditorKeyRecordAtRow
        ; expects out A
        CALL    EditorKeyReadRecordLength
        OR      A
        JR      Z,EditorSplitTailAvailable
        CALL    EditorSplitPushLastRecordToNextPage
        OR      A
        JP      Z,EditorSplitDone

EditorSplitTailAvailable:

        ; expects out HL
        CALL    EditorKeyCurrentRecord
        LD      (EditorRecordBase),HL
        ; expects out A
        CALL    EditorKeyReadRecordLength
        LD      (EditorLineLength),A
        LD      B,A
        LD      A,(EditorCursorCol)
        CP      B
        JR      C,EditorSplitCursorReady
        JR      Z,EditorSplitCursorReady
        LD      A,B
        LD      (EditorCursorCol),A

EditorSplitCursorReady:
        LD      (EditorLineColumn),A
        LD      A,(EditorCursorRow)
        LD      C,A
        LD      A,15
        SUB     C
        LD      (EditorLineRowsLeft),A
        LD      A,14
        CALL    EditorKeyRecordAtRow
        LD      (EditorLineSrc),HL
        LD      A,15
        ; expects out HL
        CALL    EditorKeyRecordAtRow
        LD      (EditorLineDest),HL

        LD      A,(EditorLineRowsLeft)
        LD      HL,(EditorLineSrc)
        LD      DE,(EditorLineDest)
        CALL    Tecm8RecordShiftRecordsDown

EditorSplitShiftDone:
        LD      HL,(EditorRecordBase)
        LD      A,(EditorLineColumn)
        CALL    EditorKeyWriteRecordLength
        LD      A,(EditorLineLength)
        LD      (EditorLineTailLength),A
        LD      A,(EditorLineColumn)
        LD      C,A
        LD      A,(EditorLineTailLength)
        SUB     C
        LD      (EditorLineTailLength),A
        LD      HL,(EditorRecordBase)
        LD      DE,TECM8_EDITOR_EDIT_RECORD_BYTES
        ADD     HL,DE
        LD      (EditorLineDest),HL
        LD      A,(EditorLineTailLength)
        LD      (HL),A
        OR      A
        JR      Z,EditorSplitZeroPadding
        LD      HL,(EditorRecordBase)
        INC     HL
        LD      D,0
        LD      A,(EditorLineColumn)
        LD      E,A
        ADD     HL,DE
        LD      DE,(EditorLineDest)
        INC     DE
        LD      A,(EditorLineTailLength)
        LD      B,A

EditorSplitTailLoop:
        LD      A,(HL)
        LD      (DE),A
        INC     HL
        INC     DE
        DJNZ    EditorSplitTailLoop

EditorSplitZeroPadding:
        LD      HL,(EditorRecordBase)
        LD      A,(EditorLineColumn)
        CALL    EditorKeyZeroRecordPadding
        LD      HL,(EditorLineDest)
        LD      A,(EditorLineTailLength)
        CALL    EditorKeyZeroRecordPadding

EditorSplitCursorDown:
        LD      A,(EditorCursorRow)
        INC     A
        LD      (EditorCursorRow),A
        XOR     A
        LD      (EditorCursorCol),A
        LD      A,1
        RET

EditorSplitDone:
        XOR     A
        RET

; EditorSplitFinalRow -
; Split active row 15 into adjacent next-sector row 0, shifting the adjacent
; sector down first. The next sector must be resident and have a free tail row.
;! out A,carry,zero
;! clobbers sign,parity,halfCarry,BC,DE,HL
@EditorSplitFinalRow:
        LD      A,(EditorNavNextPageValid)
        OR      A
        JP      Z,EditorSplitFinalDone
        LD      HL,EditorNavNextPageBuffer + (15 * TECM8_EDITOR_EDIT_RECORD_BYTES)
        CALL    EditorKeyReadRecordLength
        OR      A
        JP      NZ,EditorSplitFinalDone

        ; expects out HL
        CALL    EditorKeyCurrentRecord
        LD      (EditorRecordBase),HL
        ; expects out A
        CALL    EditorKeyReadRecordLength
        LD      (EditorLineLength),A
        LD      B,A
        LD      A,(EditorCursorCol)
        CP      B
        JR      C,EditorSplitFinalCursorReady
        JR      Z,EditorSplitFinalCursorReady
        LD      A,B
        LD      (EditorCursorCol),A

EditorSplitFinalCursorReady:
        LD      (EditorLineColumn),A
        LD      HL,EditorNavNextPageBuffer + (14 * TECM8_EDITOR_EDIT_RECORD_BYTES)
        LD      (EditorLineSrc),HL
        LD      HL,EditorNavNextPageBuffer + (15 * TECM8_EDITOR_EDIT_RECORD_BYTES)
        LD      (EditorLineDest),HL
        LD      A,15
        LD      (EditorLineRowsLeft),A

        LD      A,(EditorLineRowsLeft)
        LD      HL,(EditorLineSrc)
        LD      DE,(EditorLineDest)
        CALL    Tecm8RecordShiftRecordsDown

EditorSplitFinalWriteRecords:
        LD      HL,(EditorRecordBase)
        LD      A,(EditorLineColumn)
        CALL    EditorKeyWriteRecordLength
        LD      A,(EditorLineLength)
        LD      B,A
        LD      A,(EditorLineColumn)
        LD      C,A
        LD      A,B
        SUB     C
        LD      (EditorLineTailLength),A
        LD      HL,EditorNavNextPageBuffer
        LD      (EditorLineDest),HL
        LD      A,(EditorLineTailLength)
        LD      (HL),A
        OR      A
        JR      Z,EditorSplitFinalZeroPadding
        LD      HL,(EditorRecordBase)
        INC     HL
        LD      D,0
        LD      A,(EditorLineColumn)
        LD      E,A
        ADD     HL,DE
        LD      DE,(EditorLineDest)
        INC     DE
        LD      A,(EditorLineTailLength)
        LD      B,A

EditorSplitFinalTailLoop:
        LD      A,(HL)
        LD      (DE),A
        INC     HL
        INC     DE
        DJNZ    EditorSplitFinalTailLoop

EditorSplitFinalZeroPadding:
        LD      HL,(EditorRecordBase)
        LD      A,(EditorLineColumn)
        CALL    EditorKeyZeroRecordPadding
        LD      HL,(EditorLineDest)
        LD      A,(EditorLineTailLength)
        CALL    EditorKeyZeroRecordPadding
        LD      A,(EditorNavDirtySectors)
        OR      2
        LD      (EditorNavDirtySectors),A
        CALL    EditorNavRefreshAggregateDirty
        LD      A,(EditorNavCurrentPage)
        CP      127
        JR      Z,EditorSplitFinalStay
        LD      A,(EditorNavDirtySectors)
        OR      1
        LD      (EditorNavDirtySectors),A
        CALL    EditorNavRememberCurrentPage
        RET     C
        CALL    EditorNavRefreshAggregateDirty
        LD      A,(EditorNavCurrentPage)
        INC     A
        LD      (EditorNavCurrentPage),A
        CALL    EditorNavSlideNextPageToCurrent
        CALL    EditorNavLoadNextWindowPage
        RET     C
        XOR     A
        LD      (EditorCursorRow),A
        LD      (EditorCursorCol),A
        LD      A,(EditorNavDirtySectors)
        SRL     A
        OR      1
        LD      (EditorNavDirtySectors),A
        CALL    EditorNavRefreshAggregateDirty
        LD      A,1
        RET

EditorSplitFinalStay:
        XOR     A
        LD      (EditorCursorCol),A
        LD      A,1
        RET

EditorSplitFinalDone:
        XOR     A
        RET

; EditorSplitPushLastRecordToNextPage -
; Move current sector row 15 into next sector row 0, shifting the next sector
; down one record. Returns A=1 on success, A=0 when the next sector cannot
; accept the pushed record.
;! out A,carry,zero
;! clobbers sign,parity,halfCarry,BC,DE,HL
@EditorSplitPushLastRecordToNextPage:
        LD      A,(EditorNavNextPageValid)
        OR      A
        JR      Z,EditorSplitPushNextDone
        LD      HL,EditorNavNextPageBuffer + (15 * TECM8_EDITOR_EDIT_RECORD_BYTES)
        CALL    EditorKeyReadRecordLength
        OR      A
        JR      NZ,EditorSplitPushNextDone

        LD      HL,EditorNavNextPageBuffer + (14 * TECM8_EDITOR_EDIT_RECORD_BYTES)
        LD      (EditorLineSrc),HL
        LD      HL,EditorNavNextPageBuffer + (15 * TECM8_EDITOR_EDIT_RECORD_BYTES)
        LD      (EditorLineDest),HL
        LD      A,15
        LD      (EditorLineRowsLeft),A

        LD      A,(EditorLineRowsLeft)
        LD      HL,(EditorLineSrc)
        LD      DE,(EditorLineDest)
        CALL    Tecm8RecordShiftRecordsDown

EditorSplitPushCopyLast:
        LD      HL,EditorNavPageBuffer + (15 * TECM8_EDITOR_EDIT_RECORD_BYTES)
        LD      DE,EditorNavNextPageBuffer
        LD      BC,TECM8_EDITOR_EDIT_RECORD_BYTES
        LDIR
        LD      HL,EditorNavPageBuffer + (15 * TECM8_EDITOR_EDIT_RECORD_BYTES)
        CALL    EditorKeyClearRecord
        LD      A,(EditorNavDirtySectors)
        OR      2
        LD      (EditorNavDirtySectors),A
        CALL    EditorNavRefreshAggregateDirty
        LD      A,1
        RET

EditorSplitPushNextDone:
        XOR     A
        RET

; EditorJoinPreviousLine -
; Join the current record into the previous one when the cursor is at column 0.
; The join is a no-op on row 0 or when the combined text would exceed 31 bytes.
; Returns A=1 when the buffer changed, A=0 when the join was a no-op.
;! out A,carry,zero
;! clobbers sign,parity,halfCarry,BC,DE,HL
@EditorJoinPreviousLine:
        LD      A,(EditorCursorCol)
        OR      A
        JP      NZ,EditorJoinDone
        LD      A,(EditorCursorRow)
        OR      A
        JP      Z,EditorJoinPreviousPageLine
        LD      (EditorLineCurrentRow),A
        ; expects out HL
        CALL    EditorKeyCurrentRecord
        LD      (EditorLineCurrentBase),HL
        CALL    EditorKeyReadRecordLength
        LD      (EditorLineCurrentLength),A
        LD      A,(EditorCursorRow)
        DEC     A
        CALL    EditorKeyRecordAtRow
        LD      (EditorLinePrevBase),HL
        ; expects out A
        CALL    EditorKeyReadRecordLength
        LD      (EditorLinePrevLength),A
        LD      B,A
        LD      A,(EditorLineCurrentLength)
        ADD     A,B
        CP      TECM8_EDITOR_EDIT_RECORD_TEXT_MAX + 1
        JP      NC,EditorJoinDone
        LD      (EditorLineJoinedLength),A
        LD      HL,(EditorLinePrevBase)
        LD      A,(EditorLineJoinedLength)
        CALL    EditorKeyWriteRecordLength
        INC     HL
        LD      D,0
        LD      A,(EditorLinePrevLength)
        LD      E,A
        ADD     HL,DE
        LD      DE,(EditorLineCurrentBase)
        INC     DE
        LD      A,(EditorLineCurrentLength)
        LD      B,A
        OR      A
        JR      Z,EditorJoinZeroPrevPadding

EditorJoinCopyLoop:
        LD      A,(DE)
        LD      (HL),A
        INC     DE
        INC     HL
        DJNZ    EditorJoinCopyLoop

EditorJoinZeroPrevPadding:
        LD      HL,(EditorLinePrevBase)
        LD      A,(EditorLineJoinedLength)
        CALL    EditorKeyZeroRecordPadding

EditorJoinShiftRows:
        LD      A,(EditorLineCurrentRow)
        LD      C,A
        LD      A,15
        SUB     C
        LD      (EditorLineRowsLeft),A
        LD      HL,(EditorLineCurrentBase)
        LD      (EditorLineDest),HL
        LD      DE,TECM8_EDITOR_EDIT_RECORD_BYTES
        ADD     HL,DE
        LD      (EditorLineSrc),HL

        LD      A,(EditorLineRowsLeft)
        LD      HL,(EditorLineSrc)
        LD      DE,(EditorLineDest)
        CALL    Tecm8RecordShiftRecordsUp

EditorJoinClearLast:
        LD      A,15
        ; expects out HL
        CALL    EditorKeyRecordAtRow
        CALL    EditorKeyClearRecord
        LD      A,(EditorCursorRow)
        DEC     A
        LD      (EditorCursorRow),A
        LD      A,(EditorLinePrevLength)
        LD      (EditorCursorCol),A
        LD      A,1
        RET

EditorJoinDone:
        XOR     A
        RET

; EditorJoinPreviousPageLine -
; Join current row 0 into cached previous-page row 15, then make the previous
; page active. Returns A=1 on success, A=0 when the cached previous page cannot
; accept the join.
;! out A,carry,zero
;! clobbers sign,parity,halfCarry,BC,DE,HL
@EditorJoinPreviousPageLine:
        LD      A,(EditorNavCacheValid)
        OR      A
        JP      Z,EditorJoinDone
        LD      A,(EditorNavCurrentPage)
        OR      A
        JP      Z,EditorJoinDone
        DEC     A
        LD      HL,EditorNavCachedPage
        CP      (HL)
        JP      NZ,EditorJoinDone

        LD      HL,EditorNavPageBuffer
        LD      (EditorLineCurrentBase),HL
        ; expects out A
        CALL    EditorKeyReadRecordLength
        LD      (EditorLineCurrentLength),A
        LD      HL,EditorNavCachePageBuffer + (15 * TECM8_EDITOR_EDIT_RECORD_BYTES)
        LD      (EditorLinePrevBase),HL
        ; expects out A
        CALL    EditorKeyReadRecordLength
        LD      (EditorLinePrevLength),A
        LD      B,A
        LD      A,(EditorLineCurrentLength)
        ADD     A,B
        CP      TECM8_EDITOR_EDIT_RECORD_TEXT_MAX + 1
        JP      NC,EditorJoinDone
        LD      (EditorLineJoinedLength),A

        LD      HL,(EditorLinePrevBase)
        LD      A,(EditorLineJoinedLength)
        CALL    EditorKeyWriteRecordLength
        INC     HL
        LD      D,0
        LD      A,(EditorLinePrevLength)
        LD      E,A
        ADD     HL,DE
        LD      DE,(EditorLineCurrentBase)
        INC     DE
        LD      A,(EditorLineCurrentLength)
        LD      B,A
        OR      A
        JR      Z,EditorJoinPreviousPageZeroPadding

EditorJoinPreviousPageCopyLoop:
        LD      A,(DE)
        LD      (HL),A
        INC     DE
        INC     HL
        DJNZ    EditorJoinPreviousPageCopyLoop

EditorJoinPreviousPageZeroPadding:
        LD      HL,(EditorLinePrevBase)
        LD      A,(EditorLineJoinedLength)
        CALL    EditorKeyZeroRecordPadding

        LD      HL,EditorNavPageBuffer + TECM8_EDITOR_EDIT_RECORD_BYTES
        LD      (EditorLineSrc),HL
        LD      HL,EditorNavPageBuffer
        LD      (EditorLineDest),HL
        LD      A,15
        LD      (EditorLineRowsLeft),A

        LD      A,(EditorLineRowsLeft)
        LD      HL,(EditorLineSrc)
        LD      DE,(EditorLineDest)
        CALL    Tecm8RecordShiftRecordsUp

EditorJoinPreviousPageClearLast:
        LD      HL,EditorNavPageBuffer + (15 * TECM8_EDITOR_EDIT_RECORD_BYTES)
        CALL    EditorKeyClearRecord

        LD      HL,EditorNavPageBuffer
        LD      DE,EditorNavNextPageBuffer
        LD      BC,TECM8_EDITOR_EDIT_RECORD_BYTES * 16
        LDIR
        LD      HL,EditorNavCachePageBuffer
        LD      DE,EditorNavPageBuffer
        LD      BC,TECM8_EDITOR_EDIT_RECORD_BYTES * 16
        LDIR

        LD      A,(EditorNavCurrentPage)
        DEC     A
        LD      (EditorNavCurrentPage),A
        LD      A,1
        LD      (EditorNavNextPageValid),A
        XOR     A
        LD      (EditorNavCacheValid),A
        LD      (EditorNavCachedPageDirty),A
        LD      A,3
        LD      (EditorNavDirtySectors),A
        CALL    EditorNavRefreshAggregateDirty
        LD      A,15
        LD      (EditorCursorRow),A
        LD      (EditorNavCurrentRow),A
        LD      A,6
        LD      (EditorNavViewportTopRow),A
        CALL    EditorNavSyncViewport
        RET     C
        LD      A,TECM8_EDITOR_CURSOR_VISIBLE_ROWS - 1
        LD      (EditorCursorVisibleRow),A
        LD      A,(EditorLinePrevLength)
        LD      (EditorCursorCol),A
        LD      A,1
        RET

; EditorDeleteChar -
; Delete the character at the cursor in the current source record.
; Returns A=1 when the buffer changed, A=0 when delete was a no-op.
;! out A,carry,zero
;! clobbers sign,parity,halfCarry,BC,DE,HL
@EditorDeleteChar:
        CALL    EditorKeyCurrentRecord
        ; expects out A
        CALL    EditorKeyReadRecordLength
        LD      (EditorLineLength),A
        LD      B,A
        LD      A,(EditorCursorCol)
        CP      B
        JR      NC,EditorDeleteDone
        LD      C,A
        LD      (EditorLineDirtyStartCol),A
        LD      A,B
        DEC     A
        LD      (EditorLineDirtyEndCol),A
        LD      A,B
        SUB     C
        DEC     A
        LD      B,A
        LD      (EditorRecordBase),HL
        LD      HL,(EditorRecordBase)
        CALL    Tecm8RecordShiftTextLeft

EditorDeleteShorten:
        LD      HL,(EditorRecordBase)
        LD      A,(EditorLineLength)
        DEC     A
        CALL    EditorKeyWriteRecordLength
        LD      A,1
        RET

EditorDeleteDone:
        XOR     A
        RET
