; TECM8 editor fixed-record helpers and line-edit scratch state.

;! out A,carry,zero,HL
;! clobbers sign,parity,halfCarry,B,DE
@EditorKeyCurrentRecord:
        LD      HL,EditorNavPageBuffer
        LD      A,(EditorCursorRow)
        OR      A
        RET     Z
        LD      B,A
        LD      DE,TECM8_EDITOR_EDIT_RECORD_BYTES

EditorRecordOffsetLoop:
        ADD     HL,DE
        DJNZ    EditorRecordOffsetLoop
        XOR     A
        RET

;! in A
;! out A,carry,zero,HL
;! clobbers sign,parity,halfCarry,B,DE
@EditorKeyRecordAtRow:
        LD      HL,EditorNavPageBuffer
        OR      A
        RET     Z
        LD      B,A
        LD      DE,TECM8_EDITOR_EDIT_RECORD_BYTES

EditorRecordAtRowOffsetLoop:
        ADD     HL,DE
        DJNZ    EditorRecordAtRowOffsetLoop
        XOR     A
        RET

;! in A,HL
;! out A,carry,zero
;! clobbers sign,parity,halfCarry,BC,DE,HL
@EditorKeyZeroRecordPadding:
        JP      Tecm8RecordZeroPadding

;! in HL
;! out A,carry,zero
;! clobbers sign,parity,halfCarry
@EditorKeyReadRecordLength:
        JP      Tecm8RecordReadLength

;! in A,HL
;! out A,carry,zero
;! clobbers sign,parity,halfCarry,B
@EditorKeyWriteRecordLength:
        JP      Tecm8RecordWriteLength

;! in HL
;! out A,carry,zero
;! clobbers sign,parity,halfCarry,B,HL
@EditorKeyClearRecord:
        JP      Tecm8RecordClear

;! out A,carry,zero
;! clobbers sign,parity,halfCarry
@EditorKeyAdvanceCursor:
        LD      A,(EditorCursorCol)
        CP      TECM8_EDITOR_CURSOR_MAX_COL
        JR      Z,EditorKeyAdvanceDone
        INC     A
        LD      (EditorCursorCol),A

EditorKeyAdvanceDone:
        XOR     A
        RET

EditorRecordBase:
        .dw     0

EditorLineSrc:
        .dw     0

EditorLineDest:
        .dw     0

EditorLineCurrentBase:
        .dw     0

EditorLinePrevBase:
        .dw     0

EditorLineLength:
        .db     0

EditorLineColumn:
        .db     0

EditorLineTailLength:
        .db     0

EditorLineRowsLeft:
        .db     0

EditorLineCurrentRow:
        .db     0

EditorLineCurrentLength:
        .db     0

EditorLinePrevLength:
        .db     0

EditorLineJoinedLength:
        .db     0
