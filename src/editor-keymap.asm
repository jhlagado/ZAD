; TECM8 editor key normalization and command lookup.

; EditorActionFromKey -
; Map one translated physical arrow key byte to a named editor movement action.
; Alphabetic keys are never navigation inputs.
; Input:
;   A = raw key byte
; Output:
;   A = TECM8_EDITOR_ACTION_* or TECM8_EDITOR_ACTION_NONE
;! in A
;! out A,carry
;! clobbers zero,sign,parity,halfCarry
@EditorActionFromKey:
        CP      TECM8_EDITOR_KEY_ARROW_UP
        JR      Z,EditorActionArrowUp
        CP      TECM8_EDITOR_KEY_ARROW_DOWN
        JR      Z,EditorActionArrowDown
        CP      TECM8_EDITOR_KEY_ARROW_LEFT
        JR      Z,EditorActionCursorLeft
        CP      TECM8_EDITOR_KEY_ARROW_RIGHT
        JR      Z,EditorActionCursorRight
        XOR     A
        RET

EditorActionArrowUp:
        LD      A,(EditorPendingModifier)
        AND     TECM8_EDITOR_KEY_MOD_CTRL
        JR      NZ,EditorActionPageUp
        JR      EditorActionCursorUp

EditorActionArrowDown:
        LD      A,(EditorPendingModifier)
        AND     TECM8_EDITOR_KEY_MOD_CTRL
        JR      NZ,EditorActionPageDown
        JR      EditorActionCursorDown

EditorActionPageDown:
        LD      A,TECM8_EDITOR_ACTION_PAGE_DOWN
        RET

EditorActionPageUp:
        LD      A,TECM8_EDITOR_ACTION_PAGE_UP
        RET

EditorActionCursorLeft:
        LD      A,TECM8_EDITOR_ACTION_CURSOR_LEFT
        RET

EditorActionCursorDown:
        LD      A,TECM8_EDITOR_ACTION_CURSOR_DOWN
        RET

EditorActionCursorUp:
        LD      A,TECM8_EDITOR_ACTION_CURSOR_UP
        RET

EditorActionCursorRight:
        LD      A,TECM8_EDITOR_ACTION_CURSOR_RIGHT
        RET

; EditorModifiedCommandFromKey -
; Prefer Control-aware editor commands before printable insertion. This catches
; Ctrl-letter events when the host path reports a printable letter plus modifier
; flags instead of an ASCII control byte.
; Input: EditorPendingChar, EditorPendingModifier
; Output: A = TECM8_EDITOR_KEY_* command or 0
;! out A,carry
;! clobbers zero,sign,parity,halfCarry
@EditorModifiedCommandFromKey:
        LD      A,(EditorPendingModifier)
        AND     TECM8_EDITOR_KEY_MOD_CTRL
        JR      Z,EditorModifiedCommandNone
        LD      A,(EditorPendingChar)
        CP      "s"
        JR      Z,EditorModifiedCommandSave
        CP      "S"
        JR      Z,EditorModifiedCommandSave
        CP      "q"
        JR      Z,EditorModifiedCommandQuit
        CP      "Q"
        JR      Z,EditorModifiedCommandQuit
        CP      "z"
        JR      Z,EditorModifiedCommandRestore
        CP      "Z"
        JR      Z,EditorModifiedCommandRestore
        CP      "c"
        JR      Z,EditorModifiedCommandCopy
        CP      "C"
        JR      Z,EditorModifiedCommandCopy
        CP      "x"
        JR      Z,EditorModifiedCommandMove
        CP      "X"
        JR      Z,EditorModifiedCommandMove
        CP      "v"
        JR      Z,EditorModifiedCommandPaste
        CP      "V"
        JR      Z,EditorModifiedCommandPaste
        LD      A,(EditorPendingChar)
        CP      TECM8_EDITOR_KEY_CTRL_C
        JR      Z,EditorModifiedCommandControlByteCopy
        CP      TECM8_EDITOR_KEY_CTRL_X
        JR      Z,EditorModifiedCommandMove
        CP      TECM8_EDITOR_KEY_CTRL_V
        JR      Z,EditorModifiedCommandPaste
        CP      TECM8_EDITOR_KEY_CTRL_Y
        JR      Z,EditorModifiedCommandDeleteLine

EditorModifiedCommandNone:
        XOR     A
        RET

; Byte 0x03 is a copy command only when it came from the C key with Control.
; If the physical matrix key was Up Arrow, movement handling owns the event.
EditorModifiedCommandControlByteCopy:
        LD      A,(BiosInputRawPrimary)
        CP      TECM8_EDITOR_KEY_ARROW_UP
        JR      Z,EditorModifiedCommandNone
        JP      EditorModifiedCommandCopy

EditorModifiedCommandSave:
        LD      A,TECM8_EDITOR_KEY_SAVE
        RET

EditorModifiedCommandQuit:
        LD      A,TECM8_EDITOR_KEY_QUIT
        RET

EditorModifiedCommandRestore:
        LD      A,TECM8_EDITOR_KEY_RESTORE
        RET

EditorModifiedCommandCopy:
        LD      A,"C"
        RET

EditorModifiedCommandMove:
        LD      A,"X"
        RET

EditorModifiedCommandPaste:
        LD      A,"V"
        RET

EditorModifiedCommandDeleteLine:
        LD      A,"Y"
        RET

; EditorShouldIgnoreModifiedPrintable -
; Return A=1 when a Ctrl-modified printable key did not match a known command.
; This prevents a failed host modifier chord from inserting text.
;! out A,carry,zero
;! clobbers sign,parity,halfCarry
@EditorShouldIgnoreModifiedPrintable:
        LD      A,(EditorPendingModifier)
        AND     TECM8_EDITOR_KEY_MOD_CTRL
        JR      Z,EditorShouldIgnoreModifiedPrintableNo
        LD      A,(EditorPendingChar)
        CP      TECM8_EDITOR_KEY_PRINTABLE_MIN
        JR      C,EditorShouldIgnoreModifiedPrintableNo
        CP      TECM8_EDITOR_KEY_PRINTABLE_MAX + 1
        JR      NC,EditorShouldIgnoreModifiedPrintableNo
        LD      A,1
        OR      A
        RET

EditorShouldIgnoreModifiedPrintableNo:
        XOR     A
        RET
