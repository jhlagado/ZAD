; TECM8 editor interaction loop.
;
; Minimal proof-oriented key stream for page movement.

TECM8_EDITOR_KEY_PAGE_DOWN_LOWER        .equ    "d"
TECM8_EDITOR_KEY_PAGE_DOWN_UPPER        .equ    "D"
TECM8_EDITOR_KEY_PAGE_UP_LOWER          .equ    "u"
TECM8_EDITOR_KEY_PAGE_UP_UPPER          .equ    "U"
TECM8_EDITOR_INTERACTION_ERR_EOF        .equ    0x34

; TECM8_EDITOR_RUN_KEYS -
; Consume a NUL-terminated key stream. `d` pages down, `u` pages up, and
; unknown keys are ignored.
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
        JR      Z,EditorKeyDone
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

EditorKeyDone:
        XOR     A
        RET

EditorKeyStreamPtr:
        .dw     0
