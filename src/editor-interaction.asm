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
TECM8_EDITOR_KEY_SAVE                   .equ    19
TECM8_EDITOR_KEY_RESTORE                .equ    26
TECM8_EDITOR_KEY_ESCAPE                 .equ    27
TECM8_EDITOR_KEY_DELETE                 .equ    127
TECM8_EDITOR_KEY_PRINTABLE_MIN          .equ    32
TECM8_EDITOR_KEY_PRINTABLE_MAX          .equ    126
TECM8_EDITOR_KEY_MOD_CTRL               .equ    0x02
TECM8_EDITOR_KEY_MOD_SHIFT              .equ    0x01
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
TECM8_EDITOR_PENDING_BLOCK_NONE         .equ    0
TECM8_EDITOR_PENDING_BLOCK_COPY         .equ    1
TECM8_EDITOR_PENDING_BLOCK_MOVE         .equ    2
TECM8_EDITOR_LIVE_IDLE_SPINS            .equ    0x10
TECM8_EDITOR_CURSOR_BLINK_IDLE_TICKS    .equ    0x0600

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
        LD      (EditorCursorBlinkCounter),A
        LD      (EditorCursorBlinkCounterHi),A
        CALL    EditorBlockSelectionClearState
        RET

; EditorCursorResetStateKeepSelection -
; Reset cursor state after a page render while preserving block selection.
;!      out       A,zero,sign,parity,halfCarry
;!      clobbers  A
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

; EditorCursorBlinkReset -
; Restart the idle blink countdown after a key event or explicit cursor render.
;!      out       A,zero,sign,parity,halfCarry
;!      clobbers  A,HL
@EditorCursorBlinkReset:
        LD      HL,TECM8_EDITOR_CURSOR_BLINK_IDLE_TICKS
        LD      (EditorCursorBlinkCounter),HL
        XOR     A
        RET

; EditorCursorBlinkStep -
; Advance the cooperative cursor blink state once from the live idle path.
;!      out       A,carry,zero
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
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
        CP      TECM8_EDITOR_KEY_RESTORE
        JP      Z,EditorKeyRestorePrompt
        CP      "C"
        JP      Z,EditorKeyCopyBlock
        CP      "X"
        JP      Z,EditorKeyMoveBlock
        CP      "V"
        JP      Z,EditorKeyPasteBlock
        JP      EditorKeyLoop

EditorKeySave:
        LD      A,(EditorNavDirty)
        OR      A
        JP      Z,EditorKeyCleanSave
        CALL    EditorHideCursor
        JP      C,EditorKeyShowErrorAndLoop
        CALL    EditorSaveCurrentPage
        JP      C,EditorKeyShowErrorAndLoop
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
        LD      A,(EditorPendingModifier)
        AND     TECM8_EDITOR_KEY_MOD_SHIFT
        JP      NZ,EditorKeySelectPageDown
        CALL    EditorPageDown
        JR      C,EditorKeyPageDownErr
        CALL    EditorCursorResetState
        CALL    EditorInvalidateCursorOverlay
        JP      EditorKeyLoop

EditorKeyPageUp:
        LD      A,(EditorPendingModifier)
        AND     TECM8_EDITOR_KEY_MOD_SHIFT
        JP      NZ,EditorKeySelectPageUp
        CALL    EditorPageUp
        JR      C,EditorKeyPageUpErr
        CALL    EditorCursorResetState
        CALL    EditorInvalidateCursorOverlay
        JP      EditorKeyLoop

EditorKeyPageDownErr:
        CP      TECM8_EDITOR_NAV_ERR_PAGE
        JR      Z,EditorKeyPageDownEnd
        CP      EDITOR_LOAD_ERR_SIZE
        JR      Z,EditorKeyPageDownEnd
        JR      EditorKeyNavigationErr

EditorKeyPageDownEnd:
        CALL    EditorHideCursor
        RET     C
        CALL    EditorViewportRestoreStatusRow
        RET     C
        JP      EditorKeyLoop

EditorKeyPageUpErr:
        CP      TECM8_EDITOR_NAV_ERR_PAGE
        JR      Z,EditorKeyPageUpTop
        JR      EditorKeyNavigationErr

EditorKeyPageUpTop:
        LD      HL,EditorStatusTopText
        CALL    EditorKeyShowStatus
        RET     C
        JP      EditorKeyLoop

EditorKeySelectPageDown:
        CALL    EditorBlockSelectionCapturePageAnchor
        RET     C
        CALL    EditorPageDown
        JR      C,EditorKeyPageDownErr
        CALL    EditorCursorResetStateKeepSelection
        CALL    EditorBlockSelectionRestorePageAnchor
        RET     C
        CALL    EditorBlockSelectionUpdateActive
        RET     C
        CALL    EditorBlockSelectionRenderMarkers
        RET     C
        CALL    EditorInvalidateCursorOverlay
        JP      EditorKeyLoop

EditorKeySelectPageUp:
        CALL    EditorBlockSelectionCapturePageAnchor
        RET     C
        CALL    EditorPageUp
        JR      C,EditorKeyPageUpErr
        CALL    EditorCursorResetStateKeepSelection
        CALL    EditorBlockSelectionRestorePageAnchor
        RET     C
        CALL    EditorBlockSelectionUpdateActive
        RET     C
        CALL    EditorBlockSelectionRenderMarkers
        RET     C
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
        JR      EditorKeyShowErrorAndLoop

EditorKeyShowErrorAndLoop:
        CALL    EditorNavShowError
        RET     C
        JP      EditorKeyLoop

EditorKeyCursorLeft:
        CALL    EditorBlockSelectionClearIfActive
        RET     C
        LD      A,(EditorCursorCol)
        OR      A
        JP      Z,EditorKeyLoop
        DEC     A
        LD      (EditorCursorCol),A
        CALL    EditorKeyRenderCursorColumnMove
        RET     C
        JP      EditorKeyLoop

EditorKeyCursorDown:
        LD      A,(EditorPendingModifier)
        AND     TECM8_EDITOR_KEY_MOD_SHIFT
        JP      NZ,EditorKeySelectDown
        CALL    EditorBlockSelectionClearIfActive
        RET     C
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
        LD      A,(EditorPendingModifier)
        AND     TECM8_EDITOR_KEY_MOD_SHIFT
        JP      NZ,EditorKeySelectUp
        CALL    EditorBlockSelectionClearIfActive
        RET     C
        LD      A,(EditorCursorRow)
        OR      A
        JP      Z,EditorKeyLoop
        LD      (EditorCursorPreviousRow),A
        DEC     A
        LD      (EditorCursorRow),A
        CALL    EditorKeyRenderCursorMove
        RET     C
        JP      EditorKeyLoop

EditorKeySelectDown:
        LD      A,(EditorCursorRow)
        CP      TECM8_EDITOR_CURSOR_MAX_ROW
        JP      Z,EditorKeyLoop
        CALL    EditorBlockSelectionBeginIfNeeded
        RET     C
        LD      A,(EditorCursorRow)
        LD      (EditorCursorPreviousRow),A
        INC     A
        LD      (EditorCursorRow),A
        CALL    EditorBlockSelectionUpdateActive
        RET     C
        CALL    EditorKeyRenderCursorMove
        RET     C
        CALL    EditorBlockSelectionRenderMarkers
        RET     C
        JP      EditorKeyLoop

EditorKeySelectUp:
        LD      A,(EditorCursorRow)
        OR      A
        JP      Z,EditorKeyLoop
        CALL    EditorBlockSelectionBeginIfNeeded
        RET     C
        LD      A,(EditorCursorRow)
        LD      (EditorCursorPreviousRow),A
        DEC     A
        LD      (EditorCursorRow),A
        CALL    EditorBlockSelectionUpdateActive
        RET     C
        CALL    EditorKeyRenderCursorMove
        RET     C
        CALL    EditorBlockSelectionRenderMarkers
        RET     C
        JP      EditorKeyLoop

EditorKeyCursorRight:
        CALL    EditorBlockSelectionClearIfActive
        RET     C
        LD      A,(EditorCursorCol)
        CP      TECM8_EDITOR_CURSOR_MAX_COL
        JP      Z,EditorKeyLoop
        INC     A
        LD      (EditorCursorCol),A
        CALL    EditorKeyRenderCursorColumnMove
        RET     C
        JP      EditorKeyLoop

EditorKeyInsertPrintable:
        CALL    EditorBlockStateClearForEdit
        RET     C
        LD      A,(EditorPendingChar)
        CALL    EditorInsertChar
        RET     C
        OR      A
        JP      Z,EditorKeyLoop
        CALL    EditorKeyRenderCurrentLineCellsDirty
        RET     C
        JP      EditorKeyLoop

EditorKeySplitLine:
        CALL    EditorBlockStateClearForEdit
        RET     C
        CALL    EditorSplitLine
        RET     C
        OR      A
        JP      Z,EditorKeyLoop
        CALL    EditorKeyRenderDirty
        RET     C
        JP      EditorKeyLoop

EditorKeyBackspace:
        CALL    EditorBlockStateClearForEdit
        RET     C
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
        CALL    EditorKeyRenderCurrentLineCellsDirty
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
        CALL    EditorBlockStateClearForEdit
        RET     C
        CALL    EditorDeleteChar
        RET     C
        OR      A
        JP      Z,EditorKeyLoop
        CALL    EditorKeyRenderCurrentLineCellsDirty
        RET     C
        JP      EditorKeyLoop

EditorKeyCopyBlock:
        LD      A,TECM8_EDITOR_PENDING_BLOCK_COPY
        CALL    EditorPendingBlockArm
        RET     C
        CALL    EditorBlockSelectionRenderMarkers
        RET     C
        JP      EditorKeyLoop

EditorKeyMoveBlock:
        LD      A,TECM8_EDITOR_PENDING_BLOCK_MOVE
        CALL    EditorPendingBlockArm
        RET     C
        CALL    EditorBlockSelectionRenderMarkers
        RET     C
        JP      EditorKeyLoop

EditorKeyPasteBlock:
        CALL    EditorPendingBlockPasteInsert
        RET     C
        OR      A
        JP      Z,EditorKeyLoop
        CALL    EditorKeyRenderDirty
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
        CALL    EditorCursorBlinkReset
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
        CALL    EditorCursorBlinkReset
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
        CALL    GlcdTileStep
        RET     C
        OR      A
        JR      NZ,EditorLiveIdleDelay
        CALL    EditorCursorBlinkStep
        RET     C
EditorLiveIdleDelay:
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
; Alt-S/Alt-Q/Alt-Z usable for macOS Debug80 testing and also catches Ctrl-letter
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

EditorModifiedCommandNone:
        XOR     A
        RET

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

; EditorBlockSelectionBeginIfNeeded -
; Start an inclusive whole-line block selection at the current absolute line if
; no ordinary selection is already active.
;!      out       A,carry
;!      clobbers  A,HL,zero,sign,parity,halfCarry
@EditorBlockSelectionBeginIfNeeded:
        LD      A,(EditorBlockSelectionActive)
        OR      A
        RET     NZ
        CALL    EditorBlockSelectionCurrentLine
        LD      A,L
        LD      (EditorBlockSelectionAnchorLo),A
        LD      (EditorBlockSelectionActiveLo),A
        LD      A,H
        LD      (EditorBlockSelectionAnchorHi),A
        LD      (EditorBlockSelectionActiveHi),A
        LD      A,1
        LD      (EditorBlockSelectionActive),A
        XOR     A
        RET

; EditorBlockSelectionCapturePageAnchor -
; Save the current absolute line and active state before a page-selection move.
;!      out       A,carry
;!      clobbers  A,HL,zero,sign,parity,halfCarry
@EditorBlockSelectionCapturePageAnchor:
        LD      A,(EditorBlockSelectionActive)
        LD      (EditorBlockSelectionPageWasActive),A
        CALL    EditorBlockSelectionCurrentLine
        LD      A,L
        LD      (EditorBlockSelectionPageAnchorLo),A
        LD      A,H
        LD      (EditorBlockSelectionPageAnchorHi),A
        XOR     A
        RET

; EditorBlockSelectionRestorePageAnchor -
; Ensure a successful page-selection move has an anchor. Existing selections
; keep their original anchor; fresh page selections anchor at the old line.
;!      out       A,carry
;!      clobbers  A,zero,sign,parity,halfCarry
@EditorBlockSelectionRestorePageAnchor:
        LD      A,(EditorBlockSelectionPageWasActive)
        OR      A
        JR      NZ,EditorBlockSelectionRestoreExisting
        LD      A,(EditorBlockSelectionPageAnchorLo)
        LD      (EditorBlockSelectionAnchorLo),A
        LD      A,(EditorBlockSelectionPageAnchorHi)
        LD      (EditorBlockSelectionAnchorHi),A

EditorBlockSelectionRestoreExisting:
        LD      A,1
        LD      (EditorBlockSelectionActive),A
        XOR     A
        RET

; EditorBlockSelectionUpdateActive -
; Move the active end of the ordinary selection to the current absolute line.
;!      out       A,carry
;!      clobbers  A,HL,zero,sign,parity,halfCarry
@EditorBlockSelectionUpdateActive:
        CALL    EditorBlockSelectionCurrentLine
        LD      A,L
        LD      (EditorBlockSelectionActiveLo),A
        LD      A,H
        LD      (EditorBlockSelectionActiveHi),A
        XOR     A
        RET

; EditorBlockSelectionClearState -
; Clear ordinary selection state without repainting. Used before full page
; renders and cursor resets.
;!      out       A,zero,sign,parity,halfCarry
;!      clobbers  A
@EditorBlockSelectionClearState:
        XOR     A
        LD      (EditorBlockSelectionActive),A
        RET

; EditorPendingBlockClearState -
; Clear the pending copy/move source without repainting.
;!      out       A,zero,sign,parity,halfCarry
;!      clobbers  A
@EditorPendingBlockClearState:
        XOR     A
        LD      (EditorPendingBlockMode),A
        RET

; EditorPendingBlockArm -
; Convert the ordinary selected range into a pending copy/move source.
; Input: A = TECM8_EDITOR_PENDING_BLOCK_COPY or *_MOVE.
;!      in        A
;!      out       A,carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@EditorPendingBlockArm:
        LD      (EditorPendingBlockRequestedMode),A
        LD      A,(EditorBlockSelectionActive)
        OR      A
        JR      Z,EditorPendingBlockArmNoSelection
        CALL    EditorBlockSelectionNormalize
        LD      A,(EditorBlockSelectionStartLo)
        LD      (EditorPendingBlockStartLo),A
        LD      A,(EditorBlockSelectionStartHi)
        LD      (EditorPendingBlockStartHi),A
        LD      A,(EditorBlockSelectionEndLo)
        LD      (EditorPendingBlockEndLo),A
        LD      A,(EditorBlockSelectionEndHi)
        LD      (EditorPendingBlockEndHi),A
        LD      A,(EditorPendingBlockRequestedMode)
        LD      (EditorPendingBlockMode),A
        CALL    EditorBlockSelectionClearState
        XOR     A
        RET

EditorPendingBlockArmNoSelection:
        CALL    EditorPendingBlockClearState
        XOR     A
        RET

; EditorPendingBlockPasteInsert -
; Insert pending source rows before the cursor when no destination selection is
; active. The first version is conservative: source and destination must be in
; the current resident page, overlap/self cases are left for B6, and empty tail
; rows must exist so no records are discarded.
;!      out       A,carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@EditorPendingBlockPasteInsert:
        LD      A,(EditorPendingBlockMode)
        OR      A
        JP      Z,EditorPendingBlockPasteNoop
        LD      (EditorPendingBlockPasteMode),A
        LD      A,(EditorBlockSelectionActive)
        OR      A
        JP      NZ,EditorPendingBlockPasteReplace
        CALL    EditorPendingBlockRowsForCurrentPage
        JP      C,EditorPendingBlockPasteNoop
        CALL    EditorPendingBlockRejectInsertOverlap
        JP      C,EditorPendingBlockPasteNoop
        CALL    EditorPendingBlockTailAvailable
        JP      Z,EditorPendingBlockPasteNoop
        CALL    EditorPendingBlockCopySourceToScratch
        RET     C
        CALL    EditorPendingBlockShiftRowsDown
        RET     C
        CALL    EditorPendingBlockCopyScratchToDest
        RET     C
        LD      A,(EditorPendingBlockPasteMode)
        CP      TECM8_EDITOR_PENDING_BLOCK_MOVE
        JR      NZ,EditorPendingBlockPasteSelectInserted
        CALL    EditorPendingBlockDeleteMovedSource
        RET     C

EditorPendingBlockPasteSelectInserted:
        CALL    EditorPendingBlockSelectInsertedRows
        CALL    EditorPendingBlockClearState
        CALL    EditorMarkDirty
        LD      A,1
        RET

EditorPendingBlockPasteNoop:
        XOR     A
        RET

; EditorPendingBlockPasteReplace -
; Replace an ordinary destination selection with a pending copy or move source.
; This first B6 slice is intentionally narrow: current page only, equal-sized
; ranges only, and no overlap.
;!      out       A,carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@EditorPendingBlockPasteReplace:
        CALL    EditorPendingBlockRowsForCurrentPage
        JP      C,EditorPendingBlockPasteNoop
        CALL    EditorPendingBlockDestinationRowsForCurrentPage
        JP      C,EditorPendingBlockPasteNoop
        CALL    EditorPendingBlockRejectReplaceOverlap
        JP      C,EditorPendingBlockPasteNoop
        CALL    EditorPendingBlockReplaceSameSize
        JP      NZ,EditorPendingBlockPasteNoop
        LD      A,(EditorPendingBlockDestStartRow)
        LD      (EditorPendingBlockDestRow),A
        CALL    EditorPendingBlockCopySourceToScratch
        RET     C
        CALL    EditorPendingBlockCopyScratchToDest
        RET     C
        LD      A,(EditorPendingBlockPasteMode)
        CP      TECM8_EDITOR_PENDING_BLOCK_MOVE
        JR      NZ,EditorPendingBlockPasteReplaceSelect
        CALL    EditorPendingBlockDeleteOriginalSource
        RET     C

EditorPendingBlockPasteReplaceSelect:
        CALL    EditorPendingBlockSelectInsertedRows
        CALL    EditorPendingBlockClearState
        CALL    EditorMarkDirty
        LD      A,1
        RET

;!      out       A,carry
;!      clobbers  A,BC,HL,zero,sign,parity,halfCarry
@EditorPendingBlockRowsForCurrentPage:
        LD      A,(EditorNavCurrentPage)
        LD      H,0
        LD      L,A
        ADD     HL,HL
        ADD     HL,HL
        ADD     HL,HL
        ADD     HL,HL
        LD      A,L
        LD      (EditorPendingBlockPageBaseLo),A
        LD      A,H
        LD      (EditorPendingBlockPageBaseHi),A
        LD      A,(EditorPendingBlockStartHi)
        CP      H
        JR      NZ,EditorPendingBlockRowsErr
        LD      A,(EditorPendingBlockEndHi)
        CP      H
        JR      NZ,EditorPendingBlockRowsErr
        LD      A,(EditorPendingBlockStartLo)
        LD      B,A
        LD      A,(EditorPendingBlockPageBaseLo)
        LD      C,A
        LD      A,B
        SUB     C
        CP      16
        JR      NC,EditorPendingBlockRowsErr
        LD      (EditorPendingBlockSourceStartRow),A
        LD      B,A
        LD      A,(EditorPendingBlockEndLo)
        SUB     C
        CP      16
        JR      NC,EditorPendingBlockRowsErr
        LD      (EditorPendingBlockSourceEndRow),A
        SUB     B
        JR      C,EditorPendingBlockRowsErr
        INC     A
        LD      (EditorPendingBlockRowCount),A
        XOR     A
        RET

EditorPendingBlockRowsErr:
        SCF
        RET

;!      out       A,carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@EditorPendingBlockDestinationRowsForCurrentPage:
        CALL    EditorBlockSelectionNormalize
        LD      A,(EditorBlockSelectionStartHi)
        LD      B,A
        LD      A,(EditorPendingBlockPageBaseHi)
        CP      B
        JR      NZ,EditorPendingBlockDestinationRowsErr
        LD      A,(EditorBlockSelectionEndHi)
        LD      B,A
        LD      A,(EditorPendingBlockPageBaseHi)
        CP      B
        JR      NZ,EditorPendingBlockDestinationRowsErr
        LD      A,(EditorBlockSelectionStartLo)
        LD      B,A
        LD      A,(EditorPendingBlockPageBaseLo)
        LD      C,A
        LD      A,B
        SUB     C
        CP      16
        JR      NC,EditorPendingBlockDestinationRowsErr
        LD      (EditorPendingBlockDestStartRow),A
        LD      B,A
        LD      A,(EditorBlockSelectionEndLo)
        SUB     C
        CP      16
        JR      NC,EditorPendingBlockDestinationRowsErr
        LD      (EditorPendingBlockDestEndRow),A
        SUB     B
        JR      C,EditorPendingBlockDestinationRowsErr
        INC     A
        LD      (EditorPendingBlockDestRowCount),A
        XOR     A
        RET

EditorPendingBlockDestinationRowsErr:
        SCF
        RET

;!      out       A,carry
;!      clobbers  A,B,zero,sign,parity,halfCarry
@EditorPendingBlockRejectInsertOverlap:
        LD      A,(EditorCursorRow)
        LD      (EditorPendingBlockDestRow),A
        LD      B,A
        LD      A,(EditorPendingBlockSourceStartRow)
        CP      B
        JR      Z,EditorPendingBlockRejectOverlap
        JR      NC,EditorPendingBlockRejectNoOverlap
        LD      A,(EditorPendingBlockSourceEndRow)
        INC     A
        CP      B
        JR      NC,EditorPendingBlockRejectOverlap

EditorPendingBlockRejectNoOverlap:
        XOR     A
        RET

EditorPendingBlockRejectOverlap:
        SCF
        RET

;!      out       A,carry
;!      clobbers  A,B,zero,sign,parity,halfCarry
@EditorPendingBlockRejectReplaceOverlap:
        LD      A,(EditorPendingBlockDestEndRow)
        LD      B,A
        LD      A,(EditorPendingBlockSourceStartRow)
        CP      B
        JR      Z,EditorPendingBlockReplaceOverlap
        JR      NC,EditorPendingBlockReplaceNoOverlap
        LD      A,(EditorPendingBlockSourceEndRow)
        LD      B,A
        LD      A,(EditorPendingBlockDestStartRow)
        CP      B
        JR      Z,EditorPendingBlockReplaceOverlap
        JR      C,EditorPendingBlockReplaceOverlap

EditorPendingBlockReplaceNoOverlap:
        XOR     A
        RET

EditorPendingBlockReplaceOverlap:
        SCF
        RET

;!      out       A,zero
;!      clobbers  A,B,zero,sign,parity,halfCarry
@EditorPendingBlockReplaceSameSize:
        LD      A,(EditorPendingBlockDestRowCount)
        LD      B,A
        LD      A,(EditorPendingBlockRowCount)
        CP      B
        RET

;!      out       A,zero,carry
;!      clobbers  A,BC,HL,zero,sign,parity,halfCarry
@EditorPendingBlockTailAvailable:
        LD      A,16
        LD      B,A
        LD      A,(EditorPendingBlockRowCount)
        CP      B
        JR      NC,EditorPendingBlockTailNo
        LD      A,B
        LD      B,A
        LD      A,(EditorPendingBlockRowCount)
        LD      C,A
        LD      A,B
        SUB     C
        LD      (EditorPendingBlockTailCheckRow),A

EditorPendingBlockTailCheckLoop:
        LD      A,(EditorPendingBlockTailCheckRow)
        CP      16
        JR      Z,EditorPendingBlockTailYes
        CALL    EditorKeyRecordAtRow
        CALL    EditorKeyReadRecordLength
        OR      A
        JR      NZ,EditorPendingBlockTailNo
        LD      A,(EditorPendingBlockTailCheckRow)
        INC     A
        LD      (EditorPendingBlockTailCheckRow),A
        JR      EditorPendingBlockTailCheckLoop

EditorPendingBlockTailYes:
        LD      A,1
        OR      A
        RET

EditorPendingBlockTailNo:
        XOR     A
        RET

;!      out       A,carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@EditorPendingBlockCopySourceToScratch:
        LD      A,(EditorPendingBlockSourceStartRow)
        CALL    EditorKeyRecordAtRow
        LD      DE,EditorNavBackupPageBuffer
        LD      A,(EditorPendingBlockRowCount)
        LD      B,A

EditorPendingBlockScratchLoop:
        LD      A,B
        OR      A
        JR      Z,EditorPendingBlockScratchDone
        PUSH    BC
        LD      BC,TECM8_EDITOR_EDIT_RECORD_BYTES
        LDIR
        POP     BC
        DJNZ    EditorPendingBlockScratchLoop

EditorPendingBlockScratchDone:
        XOR     A
        RET

;!      out       A,carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@EditorPendingBlockShiftRowsDown:
        LD      A,16
        LD      B,A
        LD      A,(EditorPendingBlockRowCount)
        LD      C,A
        LD      A,B
        SUB     C
        LD      (EditorPendingBlockShiftRow),A
        LD      A,(EditorPendingBlockDestRow)
        LD      B,A
        LD      A,(EditorPendingBlockShiftRow)
        CP      B
        JR      C,EditorPendingBlockShiftDone

EditorPendingBlockShiftLoop:
        LD      A,(EditorPendingBlockShiftRow)
        CALL    EditorKeyRecordAtRow
        LD      (EditorLineSrc),HL
        LD      A,(EditorPendingBlockShiftRow)
        LD      B,A
        LD      A,(EditorPendingBlockRowCount)
        ADD     A,B
        CALL    EditorKeyRecordAtRow
        LD      D,H
        LD      E,L
        LD      HL,(EditorLineSrc)
        LD      BC,TECM8_EDITOR_EDIT_RECORD_BYTES
        LDIR
        LD      A,(EditorPendingBlockShiftRow)
        LD      B,A
        LD      A,(EditorPendingBlockDestRow)
        CP      B
        JR      Z,EditorPendingBlockShiftDone
        LD      A,(EditorPendingBlockShiftRow)
        DEC     A
        LD      (EditorPendingBlockShiftRow),A
        JR      EditorPendingBlockShiftLoop

EditorPendingBlockShiftDone:
        XOR     A
        RET

;!      out       A,carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@EditorPendingBlockCopyScratchToDest:
        LD      A,(EditorPendingBlockDestRow)
        CALL    EditorKeyRecordAtRow
        LD      D,H
        LD      E,L
        LD      HL,EditorNavBackupPageBuffer
        LD      A,(EditorPendingBlockRowCount)
        LD      B,A

EditorPendingBlockCopyDestLoop:
        LD      A,B
        OR      A
        JR      Z,EditorPendingBlockCopyDestDone
        PUSH    BC
        LD      BC,TECM8_EDITOR_EDIT_RECORD_BYTES
        LDIR
        POP     BC
        DJNZ    EditorPendingBlockCopyDestLoop

EditorPendingBlockCopyDestDone:
        XOR     A
        RET

;!      out       A,carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@EditorPendingBlockDeleteMovedSource:
        LD      A,(EditorPendingBlockSourceStartRow)
        LD      B,A
        LD      A,(EditorPendingBlockDestRow)
        CP      B
        JR      C,EditorPendingBlockDeleteSourceAfterDest
        LD      A,(EditorPendingBlockSourceStartRow)
        JR      EditorPendingBlockDeleteStartReady

EditorPendingBlockDeleteSourceAfterDest:
        LD      A,(EditorPendingBlockSourceStartRow)
        LD      B,A
        LD      A,(EditorPendingBlockRowCount)
        ADD     A,B

EditorPendingBlockDeleteStartReady:
        LD      (EditorPendingBlockDeleteStartRow),A
        LD      A,(EditorPendingBlockDeleteStartRow)
        LD      B,A
        LD      A,(EditorPendingBlockRowCount)
        ADD     A,B
        LD      (EditorPendingBlockShiftRow),A

EditorPendingBlockDeleteLoop:
        LD      A,(EditorPendingBlockShiftRow)
        CP      16
        JR      Z,EditorPendingBlockDeleteClearTail
        CALL    EditorKeyRecordAtRow
        LD      (EditorLineSrc),HL
        LD      A,(EditorPendingBlockShiftRow)
        LD      B,A
        LD      A,(EditorPendingBlockRowCount)
        LD      C,A
        LD      A,B
        SUB     C
        CALL    EditorKeyRecordAtRow
        LD      D,H
        LD      E,L
        LD      HL,(EditorLineSrc)
        LD      BC,TECM8_EDITOR_EDIT_RECORD_BYTES
        LDIR
        LD      A,(EditorPendingBlockShiftRow)
        INC     A
        LD      (EditorPendingBlockShiftRow),A
        JR      EditorPendingBlockDeleteLoop

EditorPendingBlockDeleteClearTail:
        LD      A,16
        LD      B,A
        LD      A,(EditorPendingBlockRowCount)
        LD      C,A
        LD      A,B
        SUB     C
        LD      (EditorPendingBlockTailCheckRow),A

EditorPendingBlockDeleteClearLoop:
        LD      A,(EditorPendingBlockTailCheckRow)
        CP      16
        JR      Z,EditorPendingBlockDeleteDone
        CALL    EditorKeyRecordAtRow
        CALL    EditorKeyClearRecord
        LD      A,(EditorPendingBlockTailCheckRow)
        INC     A
        LD      (EditorPendingBlockTailCheckRow),A
        JR      EditorPendingBlockDeleteClearLoop

EditorPendingBlockDeleteDone:
        XOR     A
        RET

;!      out       A,carry
;!      clobbers  A,BC,DE,HL
@EditorPendingBlockDeleteOriginalSource:
        LD      A,(EditorPendingBlockSourceStartRow)
        JP      EditorPendingBlockDeleteStartReady

;!      out       A,carry
;!      clobbers  A,BC,HL,zero,sign,parity,halfCarry
@EditorPendingBlockSelectInsertedRows:
        LD      A,(EditorPendingBlockDestRow)
        LD      B,A
        LD      A,(EditorPendingBlockPasteMode)
        CP      TECM8_EDITOR_PENDING_BLOCK_MOVE
        JR      NZ,EditorPendingBlockSelectStartReady
        LD      A,(EditorPendingBlockSourceStartRow)
        LD      C,A
        LD      A,(EditorPendingBlockDestRow)
        CP      C
        JR      C,EditorPendingBlockSelectStartReady
        LD      A,(EditorPendingBlockDestRow)
        LD      C,A
        LD      A,(EditorPendingBlockRowCount)
        LD      B,A
        LD      A,C
        SUB     B
        LD      B,A

EditorPendingBlockSelectStartReady:
        LD      A,(EditorPendingBlockPageBaseLo)
        ADD     A,B
        LD      (EditorBlockSelectionAnchorLo),A
        LD      (EditorBlockSelectionActiveLo),A
        LD      A,(EditorPendingBlockPageBaseHi)
        LD      (EditorBlockSelectionAnchorHi),A
        LD      (EditorBlockSelectionActiveHi),A
        LD      A,(EditorPendingBlockRowCount)
        DEC     A
        ADD     A,B
        LD      B,A
        LD      A,(EditorPendingBlockPageBaseLo)
        ADD     A,B
        LD      (EditorBlockSelectionActiveLo),A
        LD      A,(EditorPendingBlockPageBaseHi)
        LD      (EditorBlockSelectionActiveHi),A
        LD      A,1
        LD      (EditorBlockSelectionActive),A
        LD      A,B
        LD      (EditorCursorRow),A
        XOR     A
        LD      (EditorCursorCol),A
        RET

; EditorBlockSelectionClearIfActive -
; Clear ordinary selection state and repaint visible gutter markers when needed.
;!      out       A,carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@EditorBlockSelectionClearIfActive:
        LD      A,(EditorBlockSelectionActive)
        OR      A
        RET     Z
        CALL    EditorHideCursor
        RET     C
        CALL    EditorBlockSelectionClearState
        JP      EditorBlockSelectionRenderMarkers

; EditorBlockStateClearForEdit -
; Clear ordinary selection and pending source before mutating source records.
;!      out       A,carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@EditorBlockStateClearForEdit:
        LD      A,(EditorBlockSelectionActive)
        LD      B,A
        LD      A,(EditorPendingBlockMode)
        OR      B
        RET     Z
        CALL    EditorHideCursor
        RET     C
        CALL    EditorBlockSelectionClearState
        CALL    EditorPendingBlockClearState
        JP      EditorBlockSelectionRenderMarkers

; EditorBlockSelectionRenderMarkers -
; Repaint all visible gutter markers after a selection range change.
;!      out       A,carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@EditorBlockSelectionRenderMarkers:
        XOR     A
        LD      (EditorBlockSelectionMarkerRow),A

EditorBlockSelectionRenderMarkerLoop:
        LD      A,(EditorBlockSelectionMarkerRow)
        CALL    EditorViewportRenderRowMarker
        RET     C
        LD      A,(EditorBlockSelectionMarkerRow)
        CALL    GlcdTileMarkGutterDirty
        RET     C
        LD      A,(EditorBlockSelectionMarkerRow)
        INC     A
        LD      (EditorBlockSelectionMarkerRow),A
        CP      TECM8_EDITOR_CURSOR_VISIBLE_ROWS
        JR      NZ,EditorBlockSelectionRenderMarkerLoop
        XOR     A
        RET

; EditorBlockSelectionCurrentLine -
; Compute the current absolute source line as page * 16 + current row.
;!      out       HL,A,carry
;!      clobbers  A,zero,sign,parity,halfCarry
@EditorBlockSelectionCurrentLine:
        LD      A,(EditorNavCurrentPage)
        LD      H,0
        LD      L,A
        ADD     HL,HL
        ADD     HL,HL
        ADD     HL,HL
        ADD     HL,HL
        LD      A,(EditorCursorRow)
        ADD     A,L
        LD      L,A
        JR      NC,EditorBlockSelectionCurrentLineDone
        INC     H

EditorBlockSelectionCurrentLineDone:
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
        LD      (EditorLineDirtyStartCol),A
        LD      A,(EditorLineLength)
        LD      (EditorLineDirtyEndCol),A
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
        LD      (EditorLineDirtyStartCol),A
        LD      A,B
        DEC     A
        LD      (EditorLineDirtyEndCol),A
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
        LD      A,(EditorCursorVisibleRow)
        CALL    GlcdTileMarkRowDirty
        RET     C
        XOR     A
        RET

;!      out       A,carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@EditorKeyRenderCurrentLineCellsDirty:
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
        LD      A,(EditorLineDirtyEndCol)
        LD      B,A
        LD      A,(EditorViewportColOffset)
        LD      C,A
        LD      A,B
        CP      C
        JR      C,EditorKeyRenderCurrentLineCellsDone
        LD      A,(EditorViewportColOffset)
        ADD     A,TECM8_EDITOR_CURSOR_VISIBLE_COLS
        LD      C,A
        LD      A,(EditorLineDirtyStartCol)
        CP      C
        JR      NC,EditorKeyRenderCurrentLineCellsDone
        LD      A,(EditorLineDirtyStartCol)
        LD      B,A
        LD      A,(EditorViewportColOffset)
        LD      C,A
        LD      A,B
        CP      C
        JR      C,EditorKeyRenderCurrentLineCellsStartZero
        SUB     C
        JR      EditorKeyRenderCurrentLineCellsStartReady

EditorKeyRenderCurrentLineCellsStartZero:
        XOR     A

EditorKeyRenderCurrentLineCellsStartReady:
        LD      (EditorLineDirtyVisibleStart),A
        LD      A,(EditorViewportColOffset)
        ADD     A,TECM8_EDITOR_CURSOR_VISIBLE_COLS
        LD      C,A
        LD      A,(EditorLineDirtyEndCol)
        CP      C
        JR      NC,EditorKeyRenderCurrentLineCellsEndMax
        LD      B,A
        LD      A,(EditorViewportColOffset)
        LD      C,A
        LD      A,B
        SUB     C
        JR      EditorKeyRenderCurrentLineCellsEndReady

EditorKeyRenderCurrentLineCellsEndMax:
        LD      A,TECM8_EDITOR_CURSOR_VISIBLE_COLS - 1

EditorKeyRenderCurrentLineCellsEndReady:
        LD      (EditorLineDirtyVisibleEnd),A
        LD      A,(EditorCursorVisibleRow)
        LD      B,A
        LD      A,(EditorLineDirtyVisibleStart)
        LD      C,A
        CALL    GlcdTileMarkCellDirty
        RET     C
        LD      A,(EditorLineDirtyVisibleEnd)
        LD      C,A
        LD      A,(EditorLineDirtyVisibleStart)
        CP      C
        JR      Z,EditorKeyRenderCurrentLineCellsDone
        LD      A,(EditorCursorVisibleRow)
        LD      B,A
        LD      A,(EditorLineDirtyVisibleEnd)
        LD      C,A
        CALL    GlcdTileMarkCellDirty
        RET     C

EditorKeyRenderCurrentLineCellsDone:
        XOR     A
        RET

;!      out       A,carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@EditorKeyRenderCursorRowMarkers:
        CALL    EditorHideCursor
        RET     C
        CALL    EditorEnsureCursorVisible
        RET     C
        LD      A,0xFF
        LD      (EditorCursorPreviousVisibleRow),A
        LD      A,(EditorCursorVisibleRow)
        CALL    EditorViewportSetCurrentRow
        RET     C
        LD      A,(EditorCursorPreviousRow)
        CALL    EditorLogicalRowVisible
        JR      C,EditorKeyRenderCursorNewOnly
        LD      (EditorCursorPreviousVisibleRow),A
        LD      A,(EditorCursorPreviousVisibleRow)
        CALL    EditorViewportRenderRowMarker
        RET     C
EditorKeyRenderCursorNewOnly:
        LD      A,(EditorCursorVisibleRow)
        CALL    EditorViewportRenderRowMarker
        RET     C
        LD      A,(EditorCursorPreviousVisibleRow)
        CP      0xFF
        JR      Z,EditorKeyRenderCursorFlushCurrent
        CALL    GlcdTileMarkGutterDirty
        RET     C
EditorKeyRenderCursorFlushCurrent:
        LD      A,(EditorCursorVisibleRow)
        CALL    GlcdTileMarkGutterDirty
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
        CALL    EditorLoadCurrentBackupWindow
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

EditorLineDirtyStartCol:
        .db     0

EditorLineDirtyEndCol:
        .db     0

EditorLineDirtyVisibleStart:
        .db     0

EditorLineDirtyVisibleEnd:
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

EditorCursorBlinkCounter:
        .db     0

EditorCursorBlinkCounterHi:
        .db     0

EditorCursorBlinkToggleCount:
        .db     0

EditorCursorPreviousRow:
        .db     0

EditorCursorPreviousVisibleRow:
        .db     0

EditorBlockSelectionPageWasActive:
        .db     0

EditorBlockSelectionPageAnchorLo:
        .db     0

EditorBlockSelectionPageAnchorHi:
        .db     0

EditorPendingBlockRequestedMode:
        .db     0

EditorPendingBlockPasteMode:
        .db     0

EditorPendingBlockPageBaseLo:
        .db     0

EditorPendingBlockPageBaseHi:
        .db     0

EditorPendingBlockSourceStartRow:
        .db     0

EditorPendingBlockSourceEndRow:
        .db     0

EditorPendingBlockRowCount:
        .db     0

EditorPendingBlockDestRow:
        .db     0

EditorPendingBlockTailCheckRow:
        .db     0

EditorPendingBlockShiftRow:
        .db     0

EditorPendingBlockDeleteStartRow:
        .db     0

EditorPendingBlockDestStartRow:
        .db     0

EditorPendingBlockDestEndRow:
        .db     0

EditorPendingBlockDestRowCount:
        .db     0

EditorRestorePromptText:
        .db     "Restore backup? Y/N",0

EditorQuitPromptText:
        .db     "Discard changes? Y/N",0
