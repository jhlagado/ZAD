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
TECM8_EDITOR_CURSOR_MAX_COL             .equ    30
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
        LD      (EditorCursorVisibleCol),A
        LD      (EditorNavCurrentRow),A
        LD      (EditorCursorCol),A
        LD      (EditorCursorRendered),A
        CALL    EditorNavResetViewport
        RET     C
        XOR     A
        CALL    EditorViewportSetColOffset
        RET     C
        XOR     A
        JP      EditorViewportSetCurrentRow

; EditorCursorResetState -
; Reset cursor state after a page render has already reset the viewport.
;!      out       A,zero,sign,parity,halfCarry
;!      clobbers  A
@EditorCursorResetState:
        XOR     A
        LD      (EditorCursorRow),A
        LD      (EditorCursorVisibleRow),A
        LD      (EditorCursorVisibleCol),A
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
        CALL    EditorKeyRenderCursorColumnMove
        RET     C
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
        CALL    EditorKeyRenderCursorColumnMove
        RET     C
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
        JR      NZ,EditorKeyBackspaceDirty
        CALL    EditorKeyRenderCursorColumnMove
        RET     C
        JP      EditorKeyLoop

EditorKeyBackspaceDirty:
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

        .include "editor-buffer.asm"

;!      out       A,carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
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

;!      out       A,carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
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
        CALL    EditorEnsureCursorVisibleColumn
        RET     C
        OR      A
        JP      NZ,EditorKeyRenderViewport
        JP      EditorKeyRenderCursorRowMarkers

;!      out       A,carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@EditorKeyRenderCursorColumnMove:
        CALL    EditorEnsureCursorVisibleColumn
        RET     C
        OR      A
        JP      NZ,EditorKeyRenderViewport
        XOR     A
        RET

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

; EditorEnsureCursorVisibleColumn -
; Keep the 31-column logical cursor inside the 20-column GLCD text viewport.
; Returns A=1 when the horizontal viewport changed, A=0 when it did not.
;!      out       A,carry,zero
;!      clobbers  A,BC,zero,sign,parity,halfCarry
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

EditorCursorVisibleCol:
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
