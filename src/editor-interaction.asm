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

; TECM8_EDITOR_CURSOR_RESET -
; Reset the visible cursor to the top-left source cell.
;!      out       A,carry
;!      clobbers  A,zero,sign,parity,halfCarry
@TECM8_EDITOR_CURSOR_RESET:
        XOR     A
        LD      (EditorCursorRow),A
        LD      (EditorCursorCol),A
        LD      (EditorCursorRendered),A
        RET

; TECM8_EDITOR_RENDER_CURSOR -
; Overlay the logical cursor when it is inside the visible edit pane.
;!      out       A,carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@TECM8_EDITOR_RENDER_CURSOR:
        LD      A,(EditorCursorRendered)
        OR      A
        JR      Z,EditorCursorRenderCheckVisible
        LD      A,(EditorCursorRenderedCol)
        LD      C,A
        LD      A,(EditorCursorRenderedRow)
        CALL    TECM8_DISPLAY_ERASE_CURSOR_CELL
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
        CALL    TECM8_DISPLAY_RENDER_CURSOR_CELL
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

; TECM8_EDITOR_RUN_KEYS -
; Consume a NUL-terminated key stream. In command mode, `d`/`u` page and
; `h`/`j`/`k`/`l` move the visible cursor. TAB enters insert mode for this
; stream, printable ASCII inserts, backspace deletes before the cursor, delete
; removes the character at the cursor, and unknown keys are ignored.
; Input:
;   HL = NUL-terminated key stream
;!      in        HL
;!      out       A,carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@TECM8_EDITOR_RUN_KEYS:
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
        JR      Z,EditorKeyCursorLeft
        CP      TECM8_EDITOR_KEY_CURSOR_LEFT_UPPER
        JR      Z,EditorKeyCursorLeft
        CP      TECM8_EDITOR_KEY_CURSOR_DOWN_LOWER
        JP      Z,EditorKeyCursorDown
        CP      TECM8_EDITOR_KEY_CURSOR_DOWN_UPPER
        JR      Z,EditorKeyCursorDown
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
        JR      C,EditorKeyLoop
        CP      TECM8_EDITOR_KEY_PRINTABLE_MAX + 1
        JR      NC,EditorKeyLoop
        JP      EditorKeyInsertPrintable
        JP      EditorKeyLoop

EditorKeyMaybeInsertMode:
        LD      A,(EditorPendingChar)
        CP      TECM8_EDITOR_KEY_BACKSPACE
        JP      Z,EditorKeyBackspace
        CP      TECM8_EDITOR_KEY_DELETE
        JP      Z,EditorKeyDelete
        CP      TECM8_EDITOR_KEY_PRINTABLE_MIN
        JR      C,EditorKeyLoop
        CP      TECM8_EDITOR_KEY_PRINTABLE_MAX + 1
        JR      NC,EditorKeyLoop
        JP      EditorKeyInsertPrintable

EditorKeyInsertMode:
        LD      A,1
        LD      (EditorInsertMode),A
        JP      EditorKeyLoop

EditorKeyPageDown:
        CALL    TECM8_EDITOR_PAGE_DOWN
        JR      C,EditorKeyNavigationErr
        XOR     A
        LD      (EditorCursorRendered),A
        JP      EditorKeyLoop

EditorKeyPageUp:
        CALL    TECM8_EDITOR_PAGE_UP
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
        CALL    TECM8_EDITOR_INSERT_CHAR
        RET     C
        CALL    EditorKeyRenderDirty
        RET     C
        JP      EditorKeyLoop

EditorKeyBackspace:
        CALL    TECM8_EDITOR_BACKSPACE_CHAR
        RET     C
        CALL    EditorKeyRenderDirty
        RET     C
        JP      EditorKeyLoop

EditorKeyDelete:
        CALL    TECM8_EDITOR_DELETE_CHAR
        RET     C
        CALL    EditorKeyRenderDirty
        RET     C
        JP      EditorKeyLoop

EditorKeyDone:
        CALL    TECM8_EDITOR_RENDER_CURSOR
        RET

; TECM8_EDITOR_INSERT_CHAR -
; Insert printable A into the current fixed-width source record.
;!      in        A
;!      out       A,carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@TECM8_EDITOR_INSERT_CHAR:
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

; TECM8_EDITOR_BACKSPACE_CHAR -
; Delete the character before the cursor in the current source record.
;!      out       A,carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@TECM8_EDITOR_BACKSPACE_CHAR:
        LD      A,(EditorCursorCol)
        OR      A
        JR      Z,EditorBackspaceDone
        DEC     A
        LD      (EditorCursorCol),A
        CALL    TECM8_EDITOR_DELETE_CHAR
        RET

EditorBackspaceDone:
        XOR     A
        RET

; TECM8_EDITOR_DELETE_CHAR -
; Delete the character at the cursor in the current source record.
;!      out       A,carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@TECM8_EDITOR_DELETE_CHAR:
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
        CALL    TECM8_EDITOR_RENDER_PAGE_BUFFER
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
