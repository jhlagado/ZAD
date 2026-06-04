; TECM8 editor interaction loop.
;
; Minimal proof-oriented key stream for page movement.

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
TECM8_EDITOR_CURSOR_MAX_ROW             .equ    9
TECM8_EDITOR_CURSOR_MAX_COL             .equ    31
TECM8_EDITOR_INTERACTION_ERR_EOF        .equ    0x34

; TECM8_EDITOR_CURSOR_RESET -
; Reset the visible cursor to the top-left source cell.
;!      out       A,carry
;!      clobbers  A,zero,sign,parity,halfCarry
@TECM8_EDITOR_CURSOR_RESET:
        XOR     A
        LD      (EditorCursorRow),A
        LD      (EditorCursorCol),A
        RET

; TECM8_EDITOR_RUN_KEYS -
; Consume a NUL-terminated key stream. `d`/`u` page, `h`/`j`/`k`/`l` move
; the visible cursor, and unknown keys are ignored.
; Input:
;   HL = NUL-terminated key stream
;!      in        HL
;!      out       A,carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@TECM8_EDITOR_RUN_KEYS:
        LD      (EditorKeyStreamPtr),HL

EditorKeyLoop:
        LD      HL,(EditorKeyStreamPtr)
        LD      A,(HL)
        OR      A
        JP      Z,EditorKeyDone
        INC     HL
        LD      (EditorKeyStreamPtr),HL

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
        JR      Z,EditorKeyCursorDown
        CP      TECM8_EDITOR_KEY_CURSOR_DOWN_UPPER
        JR      Z,EditorKeyCursorDown
        CP      TECM8_EDITOR_KEY_CURSOR_UP_LOWER
        JR      Z,EditorKeyCursorUp
        CP      TECM8_EDITOR_KEY_CURSOR_UP_UPPER
        JR      Z,EditorKeyCursorUp
        CP      TECM8_EDITOR_KEY_CURSOR_RIGHT_LOWER
        JR      Z,EditorKeyCursorRight
        CP      TECM8_EDITOR_KEY_CURSOR_RIGHT_UPPER
        JR      Z,EditorKeyCursorRight
        JR      EditorKeyLoop

EditorKeyPageDown:
        CALL    TECM8_EDITOR_PAGE_DOWN
        JR      C,EditorKeyNavigationErr
        JR      EditorKeyLoop

EditorKeyPageUp:
        CALL    TECM8_EDITOR_PAGE_UP
        JR      C,EditorKeyNavigationErr
        JR      EditorKeyLoop

EditorKeyNavigationErr:
        CP      TECM8_EDITOR_NAV_ERR_PAGE
        JR      Z,EditorKeyLoop
        CP      TECM8_EDITOR_INTERACTION_ERR_EOF
        JR      Z,EditorKeyLoop
        SCF
        RET

EditorKeyCursorLeft:
        LD      A,(EditorCursorCol)
        OR      A
        JR      Z,EditorKeyLoop
        DEC     A
        LD      (EditorCursorCol),A
        JR      EditorKeyLoop

EditorKeyCursorDown:
        LD      A,(EditorCursorRow)
        CP      TECM8_EDITOR_CURSOR_MAX_ROW
        JR      Z,EditorKeyLoop
        INC     A
        LD      (EditorCursorRow),A
        JR      EditorKeyLoop

EditorKeyCursorUp:
        LD      A,(EditorCursorRow)
        OR      A
        JR      Z,EditorKeyLoop
        DEC     A
        LD      (EditorCursorRow),A
        JR      EditorKeyLoop

EditorKeyCursorRight:
        LD      A,(EditorCursorCol)
        CP      TECM8_EDITOR_CURSOR_MAX_COL
        JP      Z,EditorKeyLoop
        INC     A
        LD      (EditorCursorCol),A
        JP      EditorKeyLoop

EditorKeyDone:
        XOR     A
        RET

EditorKeyStreamPtr:
        .dw     0

EditorCursorRow:
        .db     0

EditorCursorCol:
        .db     0
