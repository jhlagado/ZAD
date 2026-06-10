; TECM8 editor interaction loop.
;
; Proof-oriented key stream for page movement, cursor movement, and in-page
; source-record editing.

TECM8_EDITOR_ACTION_NONE                .equ    0
TECM8_EDITOR_ACTION_PAGE_DOWN           .equ    1
TECM8_EDITOR_ACTION_PAGE_UP             .equ    2
TECM8_EDITOR_ACTION_CURSOR_LEFT         .equ    3
TECM8_EDITOR_ACTION_CURSOR_DOWN         .equ    4
TECM8_EDITOR_ACTION_CURSOR_UP           .equ    5
TECM8_EDITOR_ACTION_CURSOR_RIGHT        .equ    6
TECM8_EDITOR_KEY_ARROW_UP                .equ    0x03
TECM8_EDITOR_KEY_ARROW_DOWN              .equ    0x04
TECM8_EDITOR_KEY_ARROW_LEFT              .equ    0x05
TECM8_EDITOR_KEY_ARROW_RIGHT             .equ    0x06
TECM8_EDITOR_KEY_BACKSPACE              .equ    8
TECM8_EDITOR_KEY_INSERT_MODE            .equ    9
TECM8_EDITOR_KEY_NEWLINE                .equ    13
TECM8_EDITOR_KEY_QUIT                   .equ    17
TECM8_EDITOR_KEY_RESTORE                .equ    18
TECM8_EDITOR_KEY_SAVE                   .equ    19
TECM8_EDITOR_KEY_ALT_QUIT               .equ    24
TECM8_EDITOR_KEY_ESCAPE                 .equ    27
TECM8_EDITOR_KEY_DELETE                 .equ    127
TECM8_EDITOR_KEY_PRINTABLE_MIN          .equ    32
TECM8_EDITOR_KEY_PRINTABLE_MAX          .equ    126
TECM8_EDITOR_KEY_MOD_CTRL               .equ    0x02
TECM8_EDITOR_KEY_MOD_ALT                .equ    0x08
TECM8_EDITOR_KEY_MOD_PAGE               .equ    0x0A
TECM8_EDITOR_CURSOR_MAX_ROW             .equ    15
TECM8_EDITOR_CURSOR_MAX_COL             .equ    19
TECM8_EDITOR_CURSOR_VISIBLE_ROWS        .equ    10
TECM8_EDITOR_CURSOR_VISIBLE_COLS        .equ    20
TECM8_EDITOR_EDIT_RECORD_LENGTH_MASK    .equ    0x1F
TECM8_EDITOR_EDIT_RECORD_METADATA_MASK  .equ    0xE0
TECM8_EDITOR_INTERACTION_ERR_EOF        .equ    0x34
TECM8_EDITOR_EDIT_RECORD_BYTES          .equ    32
TECM8_EDITOR_EDIT_RECORD_TEXT_MAX       .equ    31
TECM8_EDITOR_PROMPT_RESULT_NONE         .equ    0
TECM8_EDITOR_PROMPT_RESULT_YES          .equ    1
TECM8_EDITOR_PROMPT_RESULT_NO           .equ    2
TECM8_EDITOR_PROMPT_ACTION_NONE         .equ    0
TECM8_EDITOR_PROMPT_ACTION_RESTORE      .equ    1
TECM8_EDITOR_PROMPT_ACTION_QUIT         .equ    2
TECM8_EDITOR_LIVE_IDLE_SPINS            .equ    0x10

; EditorCursorReset -
; Reset the visible cursor to the top-left source cell.
;!      out       A,carry
;!      clobbers  A,zero,sign,parity,halfCarry
@EditorCursorReset:
        XOR     A
        LD      (EditorCursorRow),A
        LD      (EditorCursorVisibleRow),A
        LD      (EditorNavCurrentRow),A
        LD      (EditorCursorCol),A
        LD      (EditorCursorRendered),A
        CALL    EditorNavResetViewport
        RET     C
        JP      EditorViewportSetCurrentRow

; EditorCursorResetState -
; Reset cursor state after a page render has already reset the viewport.
;!      out       A,zero,sign,parity,halfCarry
;!      clobbers  A
@EditorCursorResetState:
        XOR     A
        LD      (EditorCursorRow),A
        LD      (EditorCursorVisibleRow),A
        LD      (EditorNavCurrentRow),A
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
        LD      A,(EditorCursorVisibleRow)
        CP      TECM8_EDITOR_CURSOR_VISIBLE_ROWS
        JR      NC,EditorCursorRenderDone
        CALL    DisplayRenderCursorCell
        RET     C
        LD      A,(EditorCursorVisibleRow)
        LD      (EditorCursorRenderedRow),A
        LD      A,(EditorCursorCol)
        LD      (EditorCursorRenderedCol),A
        LD      A,1
        LD      (EditorCursorRendered),A

EditorCursorRenderDone:
        XOR     A
        RET

; EditorHideCursor -
; Erase any rendered cursor without drawing a replacement.
;!      out       A,carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
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

; EditorInvalidateCursorOverlay -
; Mark the cursor overlay absent after a full redraw replaces the pixels under it.
;!      out       A,zero,sign,parity,halfCarry
;!      clobbers  A
@EditorInvalidateCursorOverlay:
        XOR     A
        LD      (EditorCursorRendered),A
        RET

; EditorRunKeys -
; Consume a NUL-terminated key stream. Movement and paging are dispatched as
; editor actions so matrix-key input can bind to the same commands without
; pretending arrow keys are printable ASCII. TAB enters insert mode, printable
; ASCII inserts, backspace deletes before the cursor, delete removes the
; character at the cursor, newline splits the current record, and unknown keys
; are ignored.
; Input:
;   HL = NUL-terminated key stream
;!      in        HL
;!      out       A,carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@EditorRunKeys:
        LD      (EditorKeyStreamPtr),HL
        XOR     A
        LD      (EditorKeyStreamModifier),A
        LD      (EditorInsertMode),A
        LD      (EditorQuitRequested),A
        JP      EditorKeyLoop

; EditorRunModifiedKey -
; Consume one live key event with modifier flags from BiosInputPollKey.
; Input:
;   A = translated key
;   B = modifier flags
;!      in        A,B
;!      out       A,carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@EditorRunModifiedKey:
        LD      (EditorLiveKeyBuffer),A
        LD      A,B
        LD      (EditorKeyStreamModifier),A
        LD      HL,EditorLiveKeyBuffer
        LD      (EditorKeyStreamPtr),HL

EditorKeyLoop:
        LD      A,(EditorQuitRequested)
        OR      A
        JP      NZ,EditorKeyDone
        LD      HL,(EditorKeyStreamPtr)
        LD      A,(HL)
        OR      A
        JP      Z,EditorKeyDone
        INC     HL
        LD      (EditorKeyStreamPtr),HL
        LD      (EditorPendingChar),A
        LD      A,(EditorKeyStreamModifier)
        LD      (EditorPendingModifier),A

        LD      A,(EditorPromptActive)
        OR      A
        JP      NZ,EditorKeyPrompt
        CALL    EditorModifiedCommandFromKey
        RET     C
        OR      A
        JP      NZ,EditorDispatchModifiedCommand
        LD      A,(EditorPendingChar)
        CP      TECM8_EDITOR_KEY_INSERT_MODE
        JP      Z,EditorKeyInsertMode
        CP      TECM8_EDITOR_KEY_NEWLINE
        JP      Z,EditorKeySplitLine
        CP      TECM8_EDITOR_KEY_QUIT
        JP      Z,EditorKeyQuit
        CP      TECM8_EDITOR_KEY_RESTORE
        JP      Z,EditorKeyRestorePrompt
        CP      TECM8_EDITOR_KEY_SAVE
        JP      Z,EditorKeySave
        CP      TECM8_EDITOR_KEY_ALT_QUIT
        JP      Z,EditorKeyQuit
        LD      A,(EditorInsertMode)
        OR      A
        JR      NZ,EditorKeyMaybeInsertMode
        LD      A,(EditorPendingChar)
        CALL    EditorActionFromKey
        RET     C
        OR      A
        JP      NZ,EditorDispatchAction
        LD      A,(EditorPendingChar)
        CP      TECM8_EDITOR_KEY_BACKSPACE
        JP      Z,EditorKeyBackspace
        CP      TECM8_EDITOR_KEY_DELETE
        JP      Z,EditorKeyDelete
        CALL    EditorShouldIgnoreModifiedPrintable
        RET     C
        OR      A
        JP      NZ,EditorKeyUnknownModifiedPrintable
        LD      A,(EditorPendingChar)
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
        CALL    EditorShouldIgnoreModifiedPrintable
        RET     C
        OR      A
        JP      NZ,EditorKeyUnknownModifiedPrintable
        LD      A,(EditorPendingChar)
        CP      TECM8_EDITOR_KEY_PRINTABLE_MIN
        JP      C,EditorKeyLoop
        CP      TECM8_EDITOR_KEY_PRINTABLE_MAX + 1
        JP      NC,EditorKeyLoop
        JP      EditorKeyInsertPrintable

EditorKeyInsertMode:
        LD      A,1
        LD      (EditorInsertMode),A
        JP      EditorKeyLoop

EditorKeyPrompt:
        LD      A,(EditorPendingChar)
        CALL    EditorPromptHandleKey
        RET     C
        CALL    EditorPromptDispatch
        RET     C
        JP      EditorKeyLoop

EditorDispatchAction:
        CP      TECM8_EDITOR_ACTION_PAGE_DOWN
        JP      Z,EditorKeyPageDown
        CP      TECM8_EDITOR_ACTION_PAGE_UP
        JP      Z,EditorKeyPageUp
        CP      TECM8_EDITOR_ACTION_CURSOR_LEFT
        JP      Z,EditorKeyCursorLeft
        CP      TECM8_EDITOR_ACTION_CURSOR_DOWN
        JP      Z,EditorKeyCursorDown
        CP      TECM8_EDITOR_ACTION_CURSOR_UP
        JP      Z,EditorKeyCursorUp
        CP      TECM8_EDITOR_ACTION_CURSOR_RIGHT
        JP      Z,EditorKeyCursorRight
        JP      EditorKeyLoop

EditorDispatchModifiedCommand:
        CP      TECM8_EDITOR_KEY_SAVE
        JP      Z,EditorKeySave
        CP      TECM8_EDITOR_KEY_QUIT
        JP      Z,EditorKeyQuit
        CP      TECM8_EDITOR_KEY_ALT_QUIT
        JP      Z,EditorKeyQuit
        CP      TECM8_EDITOR_KEY_RESTORE
        JP      Z,EditorKeyRestorePrompt
        JP      EditorKeyLoop

EditorKeySave:
        LD      A,(EditorNavDirty)
        OR      A
        JP      Z,EditorKeyCleanSave
        CALL    EditorHideCursor
        RET     C
        CALL    EditorSaveCurrentPage
        RET     C
        JP      EditorKeyLoop

EditorKeyCleanSave:
        LD      HL,EditorStatusCleanText
        CALL    EditorKeyShowStatus
        RET     C
        JP      EditorKeyLoop

EditorKeyRestorePrompt:
        LD      A,TECM8_EDITOR_PROMPT_ACTION_RESTORE
        LD      (EditorPromptAction),A
        LD      HL,EditorRestorePromptText
        CALL    EditorPromptAskYesNo
        RET     C
        JP      EditorKeyLoop

EditorKeyQuit:
        LD      A,(EditorNavDirty)
        OR      A
        JR      NZ,EditorKeyQuitPrompt
        LD      A,1
        LD      (EditorQuitRequested),A
        JP      EditorKeyLoop

EditorKeyQuitPrompt:
        LD      A,TECM8_EDITOR_PROMPT_ACTION_QUIT
        LD      (EditorPromptAction),A
        LD      HL,EditorQuitPromptText
        CALL    EditorPromptAskYesNo
        RET     C
        JP      EditorKeyLoop

EditorKeyPageDown:
        CALL    EditorPageDown
        JR      C,EditorKeyNavigationErr
        CALL    EditorCursorResetState
        CALL    EditorInvalidateCursorOverlay
        JP      EditorKeyLoop

EditorKeyPageUp:
        CALL    EditorPageUp
        JR      C,EditorKeyNavigationErr
        CALL    EditorCursorResetState
        CALL    EditorInvalidateCursorOverlay
        JP      EditorKeyLoop

EditorKeyDirtyPageBlocked:
        LD      HL,EditorStatusSaveFirstText
        CALL    EditorKeyShowStatus
        RET     C
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
        LD      (EditorCursorPreviousRow),A
        INC     A
        LD      (EditorCursorRow),A
        CALL    EditorKeyRenderCursorMove
        RET     C
        JP      EditorKeyLoop

EditorKeyCursorUp:
        LD      A,(EditorCursorRow)
        OR      A
        JP      Z,EditorKeyLoop
        LD      (EditorCursorPreviousRow),A
        DEC     A
        LD      (EditorCursorRow),A
        CALL    EditorKeyRenderCursorMove
        RET     C
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
        OR      A
        JP      Z,EditorKeyLoop
        CALL    EditorKeyRenderCurrentLineDirty
        RET     C
        JP      EditorKeyLoop

EditorKeySplitLine:
        CALL    EditorSplitLine
        RET     C
        OR      A
        JP      Z,EditorKeyLoop
        CALL    EditorKeyRenderDirty
        RET     C
        JP      EditorKeyLoop

EditorKeyBackspace:
        LD      A,(EditorCursorCol)
        OR      A
        JR      Z,EditorKeyBackspaceJoin
        CALL    EditorBackspaceChar
        RET     C
        OR      A
        JP      Z,EditorKeyLoop
        CALL    EditorKeyRenderCurrentLineDirty
        RET     C
        JP      EditorKeyLoop

EditorKeyBackspaceJoin:
        CALL    EditorBackspaceChar
        RET     C
        OR      A
        JP      Z,EditorKeyLoop
        CALL    EditorKeyRenderDirty
        RET     C
        JP      EditorKeyLoop

EditorKeyDelete:
        CALL    EditorDeleteChar
        RET     C
        OR      A
        JP      Z,EditorKeyLoop
        CALL    EditorKeyRenderCurrentLineDirty
        RET     C
        JP      EditorKeyLoop

EditorKeyUnknownModifiedPrintable:
        LD      HL,EditorStatusUnknownKeyText
        CALL    EditorKeyShowStatus
        RET     C
        JP      EditorKeyLoop

;!      in        HL
;!      out       A,carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@EditorKeyShowStatus:
        LD      (EditorStatusTextPtr),HL
        CALL    EditorHideCursor
        RET     C
        LD      HL,(EditorStatusTextPtr)
        JP      EditorNavShowStatus

EditorKeyDone:
        LD      A,(EditorPromptActive)
        OR      A
        JR      NZ,EditorKeyDoneNoCursor
        CALL    EditorRenderCursor
        RET     C
        XOR     A
        LD      (EditorKeyStreamModifier),A
        RET

EditorKeyDoneNoCursor:
        XOR     A
        LD      (EditorKeyStreamModifier),A
        RET

; EditorRunLive -
; Poll TECM8 key events from the MON3-backed matrix scanner until the editor
; requests quit. A/B carry the editor-facing translated key and modifier flags;
; raw D/E remains available at the BIOS layer for diagnostics.
;!      out       A,carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@EditorRunLive:
        XOR     A
        LD      (EditorQuitRequested),A
        LD      (EditorInsertMode),A
        CALL    EditorRenderCursor
        RET     C

EditorLiveLoop:
        LD      A,(EditorQuitRequested)
        OR      A
        JP      NZ,EditorLiveDone
        CALL    BiosInputPollKey
        JR      NC,EditorLiveIdle
        CALL    EditorRunModifiedKey
        RET     C
        JP      EditorLiveLoop

EditorLiveIdle:
        LD      B,TECM8_EDITOR_LIVE_IDLE_SPINS

EditorLiveIdleLoop:
        DJNZ    EditorLiveIdleLoop
        JP      EditorLiveLoop

EditorLiveDone:
        CALL    EditorRenderCursor
        RET

; EditorActionFromKey -
; Map one raw key byte to a named editor action. This isolates the temporary
; proof key choices from movement semantics; a later matrix-key reader should
; return these same action values for physical arrow keys and page commands.
; Input:
;   A = raw key byte
; Output:
;   A = TECM8_EDITOR_ACTION_* or TECM8_EDITOR_ACTION_NONE
;!      in        A
;!      out       A,carry
;!      clobbers  A,zero,sign,parity,halfCarry
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
        AND     TECM8_EDITOR_KEY_MOD_PAGE
        JR      NZ,EditorActionPageUp
        JR      EditorActionCursorUp

EditorActionArrowDown:
        LD      A,(EditorPendingModifier)
        AND     TECM8_EDITOR_KEY_MOD_PAGE
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
; Prefer modifier-aware editor commands before printable insertion. This keeps
; Alt-S/Alt-X usable for macOS Debug80 testing and also catches Ctrl-letter
; events when the host path reports a printable letter plus modifier flags
; instead of an ASCII control byte.
; Input: EditorPendingChar, EditorPendingModifier
; Output: A = TECM8_EDITOR_KEY_* command or 0
;!      out       A,carry
;!      clobbers  A,zero,sign,parity,halfCarry
@EditorModifiedCommandFromKey:
        LD      A,(EditorPendingModifier)
        AND     TECM8_EDITOR_KEY_MOD_PAGE
        JR      Z,EditorModifiedCommandNone
        LD      A,(EditorPendingChar)
        CP      "s"
        JR      Z,EditorModifiedCommandSave
        CP      "S"
        JR      Z,EditorModifiedCommandSave
        CP      "x"
        JR      Z,EditorModifiedCommandAltQuit
        CP      "X"
        JR      Z,EditorModifiedCommandAltQuit
        CP      "q"
        JR      Z,EditorModifiedCommandQuit
        CP      "Q"
        JR      Z,EditorModifiedCommandQuit
        CP      "r"
        JR      Z,EditorModifiedCommandRestore
        CP      "R"
        JR      Z,EditorModifiedCommandRestore

EditorModifiedCommandNone:
        XOR     A
        RET

EditorModifiedCommandSave:
        LD      A,TECM8_EDITOR_KEY_SAVE
        RET

EditorModifiedCommandAltQuit:
        LD      A,TECM8_EDITOR_KEY_ALT_QUIT
        RET

EditorModifiedCommandQuit:
        LD      A,TECM8_EDITOR_KEY_QUIT
        RET

EditorModifiedCommandRestore:
        LD      A,TECM8_EDITOR_KEY_RESTORE
        RET

; EditorShouldIgnoreModifiedPrintable -
; Return A=1 when a Ctrl/Alt-modified printable key did not match a known
; command. This prevents a failed host modifier chord from inserting text.
;!      out       A,carry
;!      clobbers  A,zero,sign,parity,halfCarry
@EditorShouldIgnoreModifiedPrintable:
        LD      A,(EditorPendingModifier)
        AND     TECM8_EDITOR_KEY_MOD_PAGE
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

; EditorInsertChar -
; Insert printable A into the current fixed-width source record.
; Returns A=1 when the buffer changed, A=0 when insertion was a no-op.
;!      in        A
;!      out       A,carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
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
; Returns A=1 when the buffer changed, A=0 when the split was a no-op.
;!      out       A,carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@EditorSplitLine:
        LD      A,(EditorCursorRow)
        CP      15
        JP      Z,EditorSplitFinalRow
        JP      NC,EditorSplitDone

        LD      A,15
        CALL    EditorKeyRecordAtRow
        CALL    EditorKeyReadRecordLength
        OR      A
        JR      Z,EditorSplitTailAvailable
        CALL    EditorSplitPushLastRecordToNextPage
        OR      A
        JP      Z,EditorSplitDone

EditorSplitTailAvailable:

        CALL    EditorKeyCurrentRecord
        LD      (EditorRecordBase),HL
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
;!      out       A,carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@EditorSplitFinalRow:
        LD      A,(EditorNavNextPageValid)
        OR      A
        JP      Z,EditorSplitFinalDone
        LD      HL,EditorNavNextPageBuffer + (15 * TECM8_EDITOR_EDIT_RECORD_BYTES)
        CALL    EditorKeyReadRecordLength
        OR      A
        JP      NZ,EditorSplitFinalDone

        CALL    EditorKeyCurrentRecord
        LD      (EditorRecordBase),HL
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

EditorSplitFinalNextShiftLoop:
        LD      A,(EditorLineRowsLeft)
        OR      A
        JR      Z,EditorSplitFinalWriteRecords
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
        JR      EditorSplitFinalNextShiftLoop

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
;!      out       A,carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
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

EditorSplitPushNextShiftLoop:
        LD      A,(EditorLineRowsLeft)
        OR      A
        JR      Z,EditorSplitPushCopyLast
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
        JR      EditorSplitPushNextShiftLoop

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
;!      out       A,carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@EditorJoinPreviousLine:
        LD      A,(EditorCursorCol)
        OR      A
        JP      NZ,EditorJoinDone
        LD      A,(EditorCursorRow)
        OR      A
        JP      Z,EditorJoinPreviousPageLine
        LD      (EditorLineCurrentRow),A
        CALL    EditorKeyCurrentRecord
        LD      (EditorLineCurrentBase),HL
        CALL    EditorKeyReadRecordLength
        LD      (EditorLineCurrentLength),A
        LD      A,(EditorCursorRow)
        DEC     A
        CALL    EditorKeyRecordAtRow
        LD      (EditorLinePrevBase),HL
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
        LD      A,1
        RET

EditorJoinDone:
        XOR     A
        RET

; EditorJoinPreviousPageLine -
; Join current row 0 into cached previous-page row 15, then make the previous
; page active. Returns A=1 on success, A=0 when the cached previous page cannot
; accept the join.
;!      out       A,carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
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
        CALL    EditorKeyReadRecordLength
        LD      (EditorLineCurrentLength),A
        LD      HL,EditorNavCachePageBuffer + (15 * TECM8_EDITOR_EDIT_RECORD_BYTES)
        LD      (EditorLinePrevBase),HL
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

EditorJoinPreviousPageShiftLoop:
        LD      A,(EditorLineRowsLeft)
        OR      A
        JR      Z,EditorJoinPreviousPageClearLast
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
        JR      EditorJoinPreviousPageShiftLoop

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
        LD      A,(EditorLinePrevLength)
        LD      (EditorCursorCol),A
        LD      A,1
        RET

; EditorDeleteChar -
; Delete the character at the cursor in the current source record.
; Returns A=1 when the buffer changed, A=0 when delete was a no-op.
;!      out       A,carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@EditorDeleteChar:
        CALL    EditorKeyCurrentRecord
        CALL    EditorKeyReadRecordLength
        LD      (EditorLineLength),A
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
        LD      A,(EditorLineLength)
        DEC     A
        CALL    EditorKeyWriteRecordLength
        LD      A,1
        RET

EditorDeleteDone:
        XOR     A
        RET

;!      out       A,carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@EditorKeyRenderDirty:
        CALL    EditorMarkDirty
        CALL    EditorHideCursor
        RET     C
        CALL    EditorEnsureCursorVisible
        RET     C
        CALL    EditorRenderPageBuffer
        RET     C
        XOR     A
        RET

;!      out       A,carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@EditorKeyRenderCurrentLineDirty:
        CALL    EditorMarkDirty
        CALL    EditorHideCursor
        RET     C
        CALL    EditorEnsureCursorVisible
        RET     C
        CALL    EditorKeyCurrentRecord
        LD      A,(EditorCursorVisibleRow)
        CALL    EditorViewportRenderRecordRow
        RET     C
        CALL    GlcdTileFlushFull
        RET     C
        XOR     A
        RET

;!      out       A,carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@EditorKeyRenderCursorRowMarkers:
        CALL    EditorHideCursor
        RET     C
        CALL    EditorEnsureCursorVisible
        RET     C
        LD      A,(EditorCursorVisibleRow)
        CALL    EditorViewportSetCurrentRow
        RET     C
        LD      A,(EditorCursorPreviousRow)
        CALL    EditorLogicalRowVisible
        JR      C,EditorKeyRenderCursorNewOnly
        LD      (EditorCursorPreviousVisibleRow),A
        LD      A,(EditorCursorPreviousRow)
        CALL    EditorKeyRecordAtRow
        LD      A,(EditorCursorPreviousVisibleRow)
        CALL    EditorViewportRenderRecordRow
        RET     C
EditorKeyRenderCursorNewOnly:
        LD      A,(EditorCursorRow)
        CALL    EditorKeyCurrentRecord
        LD      A,(EditorCursorVisibleRow)
        CALL    EditorViewportRenderRecordRow
        RET     C
        CALL    GlcdTileFlushFull
        RET     C
        XOR     A
        RET

;!      out       A,carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@EditorKeyRenderCursorMove:
        CALL    EditorEnsureCursorVisible
        RET     C
        OR      A
        JP      NZ,EditorKeyRenderViewport
        JP      EditorKeyRenderCursorRowMarkers

;!      out       A,carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@EditorKeyRenderViewport:
        CALL    EditorRenderPageBuffer
        RET     C
        JP      EditorInvalidateCursorOverlay

; EditorEnsureCursorVisible -
; Keep the 16-row logical cursor inside the 10-row GLCD viewport.
; Returns A=1 when the viewport top changed, A=0 when it did not.
;!      out       A,carry,zero
;!      clobbers  A,BC,zero,sign,parity,halfCarry
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

;!      in        A
;!      out       A,carry,zero
;!      clobbers  A,BC,zero,sign,parity,halfCarry
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

;!      out       A,carry
;!      clobbers  A,zero,sign,parity,halfCarry
@EditorMarkDirty:
        JP      EditorMarkCurrentSectorDirty

; EditorPromptAskYesNo -
; Activate a status-line yes/no prompt using the NUL-terminated text at HL.
;!      in        HL
;!      out       A,carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@EditorPromptAskYesNo:
        LD      (EditorPromptTextPtr),HL
        CALL    EditorHideCursor
        RET     C
        XOR     A
        LD      (EditorPromptResult),A
        LD      A,1
        LD      (EditorPromptActive),A
        JP      EditorViewportRenderStatusOverlay

;!      in        A
;!      out       A,carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@EditorPromptHandleKey:
        CP      "y"
        JR      Z,EditorPromptYes
        CP      "Y"
        JR      Z,EditorPromptYes
        CP      "n"
        JR      Z,EditorPromptNo
        CP      "N"
        JR      Z,EditorPromptNo
        CP      TECM8_EDITOR_KEY_ESCAPE
        JR      Z,EditorPromptNo
        XOR     A
        RET

EditorPromptYes:
        LD      A,TECM8_EDITOR_PROMPT_RESULT_YES
        JR      EditorPromptComplete

EditorPromptNo:
        LD      A,TECM8_EDITOR_PROMPT_RESULT_NO

EditorPromptComplete:
        LD      (EditorPromptResult),A
        XOR     A
        LD      (EditorPromptActive),A
        JP      EditorViewportRestoreStatusRow

;!      out       A,carry,zero
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@EditorPromptDispatch:
        LD      A,(EditorPromptActive)
        OR      A
        RET     NZ
        LD      A,(EditorPromptAction)
        CP      TECM8_EDITOR_PROMPT_ACTION_RESTORE
        JR      Z,EditorPromptDispatchRestore
        CP      TECM8_EDITOR_PROMPT_ACTION_QUIT
        JR      Z,EditorPromptDispatchQuit
        XOR     A
        RET

EditorPromptDispatchRestore:
        XOR     A
        LD      (EditorPromptAction),A
        LD      A,(EditorPromptResult)
        CP      TECM8_EDITOR_PROMPT_RESULT_YES
        JR      Z,EditorRestoreConfirmed
        XOR     A
        RET

EditorPromptDispatchQuit:
        XOR     A
        LD      (EditorPromptAction),A
        LD      A,(EditorPromptResult)
        CP      TECM8_EDITOR_PROMPT_RESULT_YES
        JR      Z,EditorQuitConfirmed
        XOR     A
        RET

EditorQuitConfirmed:
        LD      A,1
        LD      (EditorQuitRequested),A
        XOR     A
        RET

EditorRestoreConfirmed:
        CALL    EditorLoadCurrentBackupPage
        RET     C
        CALL    EditorKeyRenderDirty
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
;!      clobbers  A,zero,sign,parity,halfCarry
@EditorKeyReadRecordLength:
        LD      A,(HL)
        AND     TECM8_EDITOR_EDIT_RECORD_LENGTH_MASK
        RET

;!      in        A,HL
;!      out       A,carry,zero
;!      clobbers  A,B,zero,sign,parity,halfCarry
@EditorKeyWriteRecordLength:
        AND     TECM8_EDITOR_EDIT_RECORD_LENGTH_MASK
        LD      B,A
        LD      A,(HL)
        AND     TECM8_EDITOR_EDIT_RECORD_METADATA_MASK
        OR      B
        LD      (HL),A
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

EditorLiveKeyBuffer:
        .db     0,0

EditorKeyStreamModifier:
        .db     0

EditorPendingModifier:
        .db     0

EditorPendingChar:
        .db     0

EditorInsertMode:
        .db     0

EditorPromptAction:
        .db     0

EditorQuitRequested:
        .db     0

EditorRecordBase:
        .dw     0

EditorStatusTextPtr:
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

EditorCursorVisibleRow:
        .db     0

EditorCursorCol:
        .db     0

EditorCursorRendered:
        .db     0

EditorCursorRenderedRow:
        .db     0

EditorCursorRenderedCol:
        .db     0

EditorCursorPreviousRow:
        .db     0

EditorCursorPreviousVisibleRow:
        .db     0

EditorRestorePromptText:
        .db     "Restore backup? Y/N",0

EditorQuitPromptText:
        .db     "Discard changes? Y/N",0
