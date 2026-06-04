; TECM8 editor interaction loop.
;
; Proof-oriented key stream for page movement, cursor movement, and in-page
; source-record editing.

TECM8_EDITOR_KEY_PAGE_DOWN_LOWER        .equ    "d"
TECM8_EDITOR_KEY_PAGE_DOWN_UPPER        .equ    "D"
TECM8_EDITOR_KEY_PAGE_UP_LOWER          .equ    "u"
TECM8_EDITOR_KEY_PAGE_UP_UPPER          .equ    "U"
TECM8_EDITOR_KEY_CURSOR_LEFT_LOWER      .equ    "h"
TECM8_EDITOR_KEY_CURSOR_LEFT_UPPER      .equ    "H"
TECM8_EDITOR_KEY_CURSOR_DOWN_LOWER      .equ    "j"
TECM8_EDITOR_KEY_CURSOR_DOWN_UPPER      .equ    "J"
TECM8_EDITOR_KEY_CURSOR_UP_LOWER        .equ    "k"
TECM8_EDITOR_KEY_CURSOR_UP_UPPER        .equ    "K"
TECM8_EDITOR_KEY_CURSOR_RIGHT_LOWER     .equ    "l"
TECM8_EDITOR_KEY_CURSOR_RIGHT_UPPER     .equ    "L"
TECM8_EDITOR_KEY_BACKSPACE              .equ    8
TECM8_EDITOR_KEY_INSERT_MODE            .equ    9
TECM8_EDITOR_KEY_NEWLINE                .equ    13
TECM8_EDITOR_KEY_DELETE                 .equ    127
TECM8_EDITOR_KEY_PRINTABLE_MIN          .equ    32
TECM8_EDITOR_KEY_PRINTABLE_MAX          .equ    126
TECM8_EDITOR_CURSOR_MAX_ROW             .equ    9
TECM8_EDITOR_CURSOR_MAX_COL             .equ    31
TECM8_EDITOR_CURSOR_VISIBLE_ROWS        .equ    8
TECM8_EDITOR_CURSOR_VISIBLE_COLS        .equ    20
TECM8_EDITOR_INTERACTION_ERR_EOF        .equ    0x34
TECM8_EDITOR_EDIT_RECORD_BYTES          .equ    32
TECM8_EDITOR_EDIT_RECORD_TEXT_MAX       .equ    31

; EditorCursorReset -
; Reset the visible cursor to the top-left source cell.
;!      out       A,carry
;!      clobbers  A,zero,sign,parity,halfCarry
@EditorCursorReset:
        XOR     A
        LD      (EditorCursorRow),A
        LD      (EditorCursorCol),A
        LD      (EditorCursorRendered),A
        RET

; EditorRenderCursor -
; Overlay the logical cursor when it is inside the visible edit pane.
;!      out       A,carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
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
        LD      A,(EditorCursorCol)
        CP      TECM8_EDITOR_CURSOR_VISIBLE_COLS
        JR      NC,EditorCursorRenderDone
        LD      C,A
        LD      A,(EditorCursorRow)
        CP      TECM8_EDITOR_CURSOR_VISIBLE_ROWS
        JR      NC,EditorCursorRenderDone
        CALL    DisplayRenderCursorCell
        RET     C
        LD      A,(EditorCursorRow)
        LD      (EditorCursorRenderedRow),A
        LD      A,(EditorCursorCol)
        LD      (EditorCursorRenderedCol),A
        LD      A,1
        LD      (EditorCursorRendered),A

EditorCursorRenderDone:
        XOR     A
        RET

; EditorRunKeys -
; Consume a NUL-terminated key stream. In command mode, `d`/`u` page and
; `h`/`j`/`k`/`l` move the visible cursor. TAB enters insert mode for this
; stream, printable ASCII inserts, backspace deletes before the cursor, delete
; removes the character at the cursor, newline splits the current record, and
; unknown keys are ignored.
; Input:
;   HL = NUL-terminated key stream
;!      in        HL
;!      out       A,carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@EditorRunKeys:
        LD      (EditorKeyStreamPtr),HL
        XOR     A
        LD      (EditorInsertMode),A

EditorKeyLoop:
        LD      HL,(EditorKeyStreamPtr)
        LD      A,(HL)
        OR      A
        JP      Z,EditorKeyDone
        INC     HL
        LD      (EditorKeyStreamPtr),HL
        LD      (EditorPendingChar),A

        CP      TECM8_EDITOR_KEY_INSERT_MODE
        JR      Z,EditorKeyInsertMode
        CP      TECM8_EDITOR_KEY_NEWLINE
        JP      Z,EditorKeySplitLine
        LD      A,(EditorInsertMode)
        OR      A
        JR      NZ,EditorKeyMaybeInsertMode
        LD      A,(EditorPendingChar)
        CP      TECM8_EDITOR_KEY_PAGE_DOWN_LOWER
        JR      Z,EditorKeyPageDown
        CP      TECM8_EDITOR_KEY_PAGE_DOWN_UPPER
        JR      Z,EditorKeyPageDown
        CP      TECM8_EDITOR_KEY_PAGE_UP_LOWER
        JR      Z,EditorKeyPageUp
        CP      TECM8_EDITOR_KEY_PAGE_UP_UPPER
        JR      Z,EditorKeyPageUp
        CP      TECM8_EDITOR_KEY_CURSOR_LEFT_LOWER
        JP      Z,EditorKeyCursorLeft
        CP      TECM8_EDITOR_KEY_CURSOR_LEFT_UPPER
        JP      Z,EditorKeyCursorLeft
        CP      TECM8_EDITOR_KEY_CURSOR_DOWN_LOWER
        JP      Z,EditorKeyCursorDown
        CP      TECM8_EDITOR_KEY_CURSOR_DOWN_UPPER
        JP      Z,EditorKeyCursorDown
        CP      TECM8_EDITOR_KEY_CURSOR_UP_LOWER
        JP      Z,EditorKeyCursorUp
        CP      TECM8_EDITOR_KEY_CURSOR_UP_UPPER
        JP      Z,EditorKeyCursorUp
        CP      TECM8_EDITOR_KEY_CURSOR_RIGHT_LOWER
        JP      Z,EditorKeyCursorRight
        CP      TECM8_EDITOR_KEY_CURSOR_RIGHT_UPPER
        JP      Z,EditorKeyCursorRight
        CP      TECM8_EDITOR_KEY_BACKSPACE
        JP      Z,EditorKeyBackspace
        CP      TECM8_EDITOR_KEY_DELETE
        JP      Z,EditorKeyDelete
        CP      TECM8_EDITOR_KEY_PRINTABLE_MIN
        JP      C,EditorKeyLoop
        CP      TECM8_EDITOR_KEY_PRINTABLE_MAX + 1
        JP      NC,EditorKeyLoop
        JP      EditorKeyInsertPrintable
        JP      EditorKeyLoop

EditorKeyMaybeInsertMode:
        LD      A,(EditorPendingChar)
        CP      TECM8_EDITOR_KEY_NEWLINE
        JP      Z,EditorKeySplitLine
        CP      TECM8_EDITOR_KEY_BACKSPACE
        JP      Z,EditorKeyBackspace
        CP      TECM8_EDITOR_KEY_DELETE
        JP      Z,EditorKeyDelete
        CP      TECM8_EDITOR_KEY_PRINTABLE_MIN
        JP      C,EditorKeyLoop
        CP      TECM8_EDITOR_KEY_PRINTABLE_MAX + 1
        JP      NC,EditorKeyLoop
        JP      EditorKeyInsertPrintable

EditorKeyInsertMode:
        LD      A,1
        LD      (EditorInsertMode),A
        JP      EditorKeyLoop

EditorKeyPageDown:
        CALL    EditorPageDown
        JR      C,EditorKeyNavigationErr
        XOR     A
        LD      (EditorCursorRendered),A
        JP      EditorKeyLoop

EditorKeyPageUp:
        CALL    EditorPageUp
        JR      C,EditorKeyNavigationErr
        XOR     A
        LD      (EditorCursorRendered),A
        JP      EditorKeyLoop

EditorKeyNavigationErr:
        CP      TECM8_EDITOR_NAV_ERR_PAGE
        JP      Z,EditorKeyLoop
        CP      TECM8_EDITOR_INTERACTION_ERR_EOF
        JP      Z,EditorKeyLoop
        SCF
        RET

EditorKeyCursorLeft:
        LD      A,(EditorCursorCol)
        OR      A
        JP      Z,EditorKeyLoop
        DEC     A
        LD      (EditorCursorCol),A
        JP      EditorKeyLoop

EditorKeyCursorDown:
        LD      A,(EditorCursorRow)
        CP      TECM8_EDITOR_CURSOR_MAX_ROW
        JP      Z,EditorKeyLoop
        INC     A
        LD      (EditorCursorRow),A
        JP      EditorKeyLoop

EditorKeyCursorUp:
        LD      A,(EditorCursorRow)
        OR      A
        JP      Z,EditorKeyLoop
        DEC     A
        LD      (EditorCursorRow),A
        JP      EditorKeyLoop

EditorKeyCursorRight:
        LD      A,(EditorCursorCol)
        CP      TECM8_EDITOR_CURSOR_MAX_COL
        JP      Z,EditorKeyLoop
        INC     A
        LD      (EditorCursorCol),A
        JP      EditorKeyLoop

EditorKeyInsertPrintable:
        LD      A,(EditorPendingChar)
        CALL    EditorInsertChar
        RET     C
        CALL    EditorKeyRenderDirty
        RET     C
        JP      EditorKeyLoop

EditorKeySplitLine:
        CALL    EditorSplitLine
        RET     C
        CALL    EditorKeyRenderDirty
        RET     C
        JP      EditorKeyLoop

EditorKeyBackspace:
        CALL    EditorBackspaceChar
        RET     C
        CALL    EditorKeyRenderDirty
        RET     C
        JP      EditorKeyLoop

EditorKeyDelete:
        CALL    EditorDeleteChar
        RET     C
        CALL    EditorKeyRenderDirty
        RET     C
        JP      EditorKeyLoop

EditorKeyDone:
        CALL    EditorRenderCursor
        RET

; EditorInsertChar -
; Insert printable A into the current fixed-width source record.
;!      in        A
;!      out       A,carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@EditorInsertChar:
        LD      (EditorPendingChar),A
        CALL    EditorKeyCurrentRecord
        LD      A,(HL)
        CP      TECM8_EDITOR_EDIT_RECORD_TEXT_MAX
        JR      NC,EditorInsertDone
        LD      B,A
        LD      A,(EditorCursorCol)
        CP      B
        JR      C,EditorInsertColReady
        JR      Z,EditorInsertColReady
        LD      A,B
        LD      (EditorCursorCol),A

EditorInsertColReady:
        LD      C,A
        LD      A,B
        SUB     C
        LD      B,A
        LD      (EditorRecordBase),HL
        OR      A
        JR      Z,EditorInsertWriteChar
        LD      HL,(EditorRecordBase)
        LD      D,0
        LD      E,C
        ADD     HL,DE
        LD      D,0
        LD      E,B
        ADD     HL,DE
        LD      D,H
        LD      E,L
        INC     DE

EditorInsertShiftLoop:
        LD      A,(HL)
        LD      (DE),A
        DEC     HL
        DEC     DE
        DJNZ    EditorInsertShiftLoop

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
        INC     (HL)
        CALL    EditorKeyAdvanceCursor

EditorInsertDone:
        XOR     A
        RET

; EditorBackspaceChar -
; Delete the character before the cursor in the current source record.
;!      out       A,carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
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
;!      out       A,carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@EditorSplitLine:
        LD      A,(EditorCursorRow)
        CP      15
        JP      NC,EditorSplitDone

        LD      A,15
        CALL    EditorKeyRecordAtRow
        LD      A,(HL)
        OR      A
        JP      NZ,EditorSplitDone

        CALL    EditorKeyCurrentRecord
        LD      (EditorRecordBase),HL
        LD      A,(HL)
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
        CALL    EditorKeyRecordAtRow
        LD      (EditorLineDest),HL

EditorSplitShiftLoop:
        LD      A,(EditorLineRowsLeft)
        OR      A
        JR      Z,EditorSplitShiftDone
        LD      HL,(EditorLineSrc)
        LD      DE,(EditorLineDest)
        LD      BC,TECM8_EDITOR_EDIT_RECORD_BYTES
        LDIR
        LD      HL,(EditorLineSrc)
        LD      DE,0 - TECM8_EDITOR_EDIT_RECORD_BYTES
        ADD     HL,DE
        LD      (EditorLineSrc),HL
        LD      HL,(EditorLineDest)
        LD      DE,0 - TECM8_EDITOR_EDIT_RECORD_BYTES
        ADD     HL,DE
        LD      (EditorLineDest),HL
        LD      A,(EditorLineRowsLeft)
        DEC     A
        LD      (EditorLineRowsLeft),A
        JR      EditorSplitShiftLoop

EditorSplitShiftDone:
        LD      HL,(EditorRecordBase)
        LD      A,(EditorLineColumn)
        LD      (HL),A
        LD      A,(EditorLineLength)
        LD      B,A
        LD      A,(EditorLineColumn)
        LD      C,A
        LD      A,B
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

EditorSplitDone:
        XOR     A
        RET

; EditorJoinPreviousLine -
; Join the current record into the previous one when the cursor is at column 0.
; The join is a no-op on row 0 or when the combined text would exceed 31 bytes.
;!      out       A,carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@EditorJoinPreviousLine:
        LD      A,(EditorCursorCol)
        OR      A
        JP      NZ,EditorJoinDone
        LD      A,(EditorCursorRow)
        OR      A
        JP      Z,EditorJoinDone
        LD      (EditorLineCurrentRow),A
        CALL    EditorKeyCurrentRecord
        LD      (EditorLineCurrentBase),HL
        LD      A,(HL)
        LD      (EditorLineCurrentLength),A
        LD      A,(EditorCursorRow)
        DEC     A
        CALL    EditorKeyRecordAtRow
        LD      (EditorLinePrevBase),HL
        LD      A,(HL)
        LD      (EditorLinePrevLength),A
        LD      B,A
        LD      A,(EditorLineCurrentLength)
        ADD     A,B
        CP      TECM8_EDITOR_EDIT_RECORD_TEXT_MAX + 1
        JP      NC,EditorJoinDone
        LD      (EditorLineJoinedLength),A
        LD      HL,(EditorLinePrevBase)
        LD      A,(EditorLineJoinedLength)
        LD      (HL),A
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

EditorJoinShiftLoop:
        LD      A,(EditorLineRowsLeft)
        OR      A
        JR      Z,EditorJoinClearLast
        LD      HL,(EditorLineSrc)
        LD      DE,(EditorLineDest)
        LD      BC,TECM8_EDITOR_EDIT_RECORD_BYTES
        LDIR
        LD      HL,(EditorLineSrc)
        LD      DE,TECM8_EDITOR_EDIT_RECORD_BYTES
        ADD     HL,DE
        LD      (EditorLineSrc),HL
        LD      HL,(EditorLineDest)
        LD      DE,TECM8_EDITOR_EDIT_RECORD_BYTES
        ADD     HL,DE
        LD      (EditorLineDest),HL
        LD      A,(EditorLineRowsLeft)
        DEC     A
        LD      (EditorLineRowsLeft),A
        JR      EditorJoinShiftLoop

EditorJoinClearLast:
        LD      A,15
        CALL    EditorKeyRecordAtRow
        CALL    EditorKeyClearRecord
        LD      A,(EditorCursorRow)
        DEC     A
        LD      (EditorCursorRow),A
        LD      A,(EditorLinePrevLength)
        LD      (EditorCursorCol),A

EditorJoinDone:
        XOR     A
        RET

; EditorDeleteChar -
; Delete the character at the cursor in the current source record.
;!      out       A,carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@EditorDeleteChar:
        CALL    EditorKeyCurrentRecord
        LD      A,(HL)
        LD      B,A
        LD      A,(EditorCursorCol)
        CP      B
        JR      NC,EditorDeleteDone
        LD      C,A
        LD      A,B
        SUB     C
        DEC     A
        LD      B,A
        LD      (EditorRecordBase),HL
        OR      A
        JR      Z,EditorDeleteShorten
        INC     HL
        LD      D,0
        LD      E,C
        ADD     HL,DE
        LD      D,H
        LD      E,L
        INC     HL

EditorDeleteShiftLoop:
        LD      A,(HL)
        LD      (DE),A
        INC     HL
        INC     DE
        DJNZ    EditorDeleteShiftLoop

EditorDeleteShorten:
        LD      HL,(EditorRecordBase)
        DEC     (HL)

EditorDeleteDone:
        XOR     A
        RET

;!      out       A,carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@EditorKeyRenderDirty:
        XOR     A
        LD      (EditorCursorRendered),A
        CALL    EditorRenderPageBuffer
        RET     C
        XOR     A
        RET

;!      out       A,HL,carry,zero
;!      clobbers  A,B,DE,sign,parity,halfCarry
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

;!      in        A
;!      out       A,HL,carry,zero
;!      clobbers  A,B,DE,sign,parity,halfCarry
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

;!      in        A,HL
;!      out       A,carry,zero
;!      clobbers  A,B,C,DE,HL,sign,parity,halfCarry
@EditorKeyZeroRecordPadding:
        LD      C,A
        LD      A,TECM8_EDITOR_EDIT_RECORD_TEXT_MAX
        SUB     C
        JR      Z,EditorKeyZeroRecordPaddingDone
        LD      B,A
        INC     HL
        LD      D,0
        LD      E,C
        ADD     HL,DE
        XOR     A

EditorKeyZeroRecordPaddingLoop:
        LD      (HL),A
        INC     HL
        DJNZ    EditorKeyZeroRecordPaddingLoop

EditorKeyZeroRecordPaddingDone:
        XOR     A
        RET

;!      in        HL
;!      out       A,carry,zero
;!      clobbers  A,B,HL
@EditorKeyClearRecord:
        LD      B,TECM8_EDITOR_EDIT_RECORD_BYTES
        XOR     A

EditorKeyClearRecordLoop:
        LD      (HL),A
        INC     HL
        DJNZ    EditorKeyClearRecordLoop
        XOR     A
        RET

;!      out       A,carry
;!      clobbers  A,zero,sign,parity,halfCarry
@EditorKeyAdvanceCursor:
        LD      A,(EditorCursorCol)
        CP      TECM8_EDITOR_CURSOR_MAX_COL
        JR      Z,EditorKeyAdvanceDone
        INC     A
        LD      (EditorCursorCol),A

EditorKeyAdvanceDone:
        XOR     A
        RET

EditorKeyStreamPtr:
        .dw     0

EditorPendingChar:
        .db     0

EditorInsertMode:
        .db     0

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

EditorCursorRow:
        .db     0

EditorCursorCol:
        .db     0

EditorCursorRendered:
        .db     0

EditorCursorRenderedRow:
        .db     0

EditorCursorRenderedCol:
        .db     0
