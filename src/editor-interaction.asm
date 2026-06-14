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
TECM8_EDITOR_KEY_CTRL_C                 .equ    0x03
TECM8_EDITOR_KEY_CTRL_V                 .equ    0x16
TECM8_EDITOR_KEY_CTRL_X                 .equ    0x18
TECM8_EDITOR_KEY_CTRL_Y                 .equ    0x19
TECM8_EDITOR_KEY_ESCAPE                 .equ    27
TECM8_EDITOR_KEY_DELETE                 .equ    127
TECM8_EDITOR_KEY_PRINTABLE_MIN          .equ    32
TECM8_EDITOR_KEY_PRINTABLE_MAX          .equ    126
TECM8_EDITOR_KEY_MOD_CTRL               .equ    TECM8_KEY_MOD_CTRL
TECM8_EDITOR_KEY_MOD_SHIFT              .equ    TECM8_KEY_MOD_SHIFT
TECM8_EDITOR_CURSOR_MAX_ROW             .equ    TECM8_SOURCE_RECORDS_PER_PAGE - 1
TECM8_EDITOR_CURSOR_MAX_COL             .equ    TECM8_SOURCE_RECORD_TEXT_MAX - 1
TECM8_EDITOR_CURSOR_VISIBLE_ROWS        .equ    TECM8_GLCD_ROWS
TECM8_EDITOR_CURSOR_VISIBLE_COLS        .equ    TECM8_GLCD_COLUMNS
TECM8_EDITOR_EDIT_RECORD_LENGTH_MASK    .equ    TECM8_SOURCE_RECORD_LENGTH_MASK
TECM8_EDITOR_EDIT_RECORD_METADATA_MASK  .equ    TECM8_SOURCE_RECORD_METADATA_MASK
TECM8_EDITOR_INTERACTION_ERR_EOF        .equ    0x34
TECM8_EDITOR_EDIT_RECORD_BYTES          .equ    TECM8_SOURCE_RECORD_BYTES
TECM8_EDITOR_EDIT_RECORD_TEXT_MAX       .equ    TECM8_SOURCE_RECORD_TEXT_MAX
TECM8_EDITOR_PROMPT_RESULT_NONE         .equ    0
TECM8_EDITOR_PROMPT_RESULT_YES          .equ    1
TECM8_EDITOR_PROMPT_RESULT_NO           .equ    2
TECM8_EDITOR_PROMPT_ACTION_NONE         .equ    0
TECM8_EDITOR_PROMPT_ACTION_RESTORE      .equ    1
TECM8_EDITOR_PROMPT_ACTION_QUIT         .equ    2
TECM8_EDITOR_PROMPT_ACTION_DELETE_BLOCK .equ    3
TECM8_EDITOR_PENDING_BLOCK_NONE         .equ    0
TECM8_EDITOR_PENDING_BLOCK_COPY         .equ    1
TECM8_EDITOR_PENDING_BLOCK_MOVE         .equ    2
TECM8_EDITOR_LIVE_IDLE_SPINS            .equ    0x10
TECM8_EDITOR_CURSOR_BLINK_IDLE_TICKS    .equ    0x0600

; EditorRunKeys -
; Consume a NUL-terminated translated-key stream used by proof fixtures.
; Movement and paging are physical arrow-key actions only. TAB enters insert
; mode, printable ASCII inserts, backspace deletes before the cursor, delete
; removes the character at the cursor, newline splits the current record, and
; unknown keys are ignored.
; Input:
;   HL = NUL-terminated key stream
;! in HL
;! out A,carry
;! clobbers zero,sign,parity,halfCarry,BC,DE,HL
@EditorRunKeys:
        LD      (EditorKeyStreamPtr),HL
        XOR     A
        LD      (EditorKeyStreamModifier),A
        LD      (EditorInsertMode),A
        LD      (EditorQuitRequested),A
        JP      EditorKeyLoop

; EditorRunModifiedKey -
; Consume one translated key event with modifier flags.
; Input:
;   A = translated key
;   B = modifier flags
;! in A,B
;! out A,carry
;! clobbers zero,sign,parity,halfCarry,BC,DE,HL
@EditorRunModifiedKey:
        LD      C,A
        LD      A,(BiosInputRawSecondary)
        CP      0xFF
        JR      NZ,EditorRunModifiedKeyRawPrimaryReady
        LD      A,B
        AND     TECM8_EDITOR_KEY_MOD_CTRL
        JR      Z,EditorRunModifiedKeyMaybeSyntheticArrow
        LD      A,C
        CP      TECM8_EDITOR_KEY_CTRL_C
        JR      Z,EditorRunModifiedKeyClearRawPrimary

EditorRunModifiedKeyMaybeSyntheticArrow:
        LD      A,C
        CP      TECM8_EDITOR_KEY_ARROW_UP
        JR      C,EditorRunModifiedKeyClearRawPrimary
        CP      TECM8_EDITOR_KEY_ARROW_RIGHT + 1
        JR      NC,EditorRunModifiedKeyClearRawPrimary
        LD      (BiosInputRawPrimary),A
        JR      EditorRunModifiedKeyRawPrimaryReady

EditorRunModifiedKeyClearRawPrimary:
        LD      A,0xFF
        LD      (BiosInputRawPrimary),A

EditorRunModifiedKeyRawPrimaryReady:
        LD      A,C
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
        CP      TECM8_EDITOR_KEY_ESCAPE
        JP      Z,EditorKeyEscape
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
        CP      "Y"
        JP      Z,EditorKeyDeleteCurrentLine
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
        CALL    EditorHideCursor
        RET     C
        CALL    EditorViewportRestoreStatusRow
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
        JP      Z,EditorKeyCursorDownAtPageBottom
        LD      (EditorCursorPreviousRow),A
        INC     A
        LD      (EditorCursorRow),A
        CALL    EditorKeyRenderCursorMove
        RET     C
        JP      EditorKeyLoop

EditorKeyCursorDownAtPageBottom:
        LD      A,(EditorCursorCol)
        LD      (EditorCursorSavedCol),A
        CALL    EditorPageDownResidentNoPreload
        JR      C,EditorKeyCursorDownAtPageBottomErr
        CALL    EditorCursorResetState
        LD      A,(EditorCursorSavedCol)
        LD      (EditorCursorCol),A
        CALL    EditorKeyRenderCursorMove
        RET     C
        JP      EditorKeyLoop

EditorKeyCursorDownAtPageBottomErr:
        CP      TECM8_EDITOR_NAV_ERR_PAGE
        JP      Z,EditorKeyLoop
        CP      EDITOR_LOAD_ERR_SIZE
        JP      Z,EditorKeyLoop
        JP      EditorKeyNavigationErr

EditorKeyCursorUp:
        LD      A,(EditorPendingModifier)
        AND     TECM8_EDITOR_KEY_MOD_SHIFT
        JP      NZ,EditorKeySelectUp
        CALL    EditorBlockSelectionClearIfActive
        RET     C
        LD      A,(EditorCursorRow)
        OR      A
        JP      Z,EditorKeyCursorUpAtPageTop
        LD      (EditorCursorPreviousRow),A
        DEC     A
        LD      (EditorCursorRow),A
        CALL    EditorKeyRenderCursorMove
        RET     C
        JP      EditorKeyLoop

EditorKeyCursorUpAtPageTop:
        LD      A,(EditorCursorCol)
        LD      (EditorCursorSavedCol),A
        CALL    EditorPageUpResidentNoPreload
        JR      C,EditorKeyCursorUpAtPageTopErr
        CALL    EditorCursorResetState
        LD      A,TECM8_EDITOR_CURSOR_MAX_ROW
        LD      (EditorCursorRow),A
        LD      A,(EditorCursorSavedCol)
        LD      (EditorCursorCol),A
        CALL    EditorKeyRenderCursorMove
        RET     C
        JP      EditorKeyLoop

EditorKeyCursorUpAtPageTopErr:
        CP      TECM8_EDITOR_NAV_ERR_PAGE
        JP      Z,EditorKeyLoop
        JP      EditorKeyNavigationErr

EditorKeySelectDown:
        LD      A,(EditorCursorRow)
        CP      TECM8_EDITOR_CURSOR_MAX_ROW
        JP      Z,EditorKeySelectDownAtBottom
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

EditorKeySelectDownAtBottom:
        CALL    EditorBlockSelectionBeginIfNeeded
        RET     C
        LD      A,(EditorCursorRow)
        LD      (EditorCursorPreviousRow),A
        ; expects out HL
        CALL    EditorBlockSelectionCurrentLine
        INC     HL
        LD      A,L
        LD      (EditorBlockSelectionActiveLo),A
        LD      A,H
        LD      (EditorBlockSelectionActiveHi),A
        LD      A,1
        LD      (EditorBlockSelectionActive),A
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
        LD      A,(EditorBlockSelectionActive)
        OR      A
        JP      NZ,EditorKeyDeleteBlockPrompt
        CALL    EditorBlockStateClearForEdit
        RET     C
        CALL    EditorDeleteChar
        RET     C
        OR      A
        JP      Z,EditorKeyLoop
        CALL    EditorKeyRenderCurrentLineCellsDirty
        RET     C
        JP      EditorKeyLoop

EditorKeyDeleteCurrentLine:
        CALL    EditorBlockStateClearForEdit
        RET     C
        LD      A,(EditorCursorRow)
        LD      (EditorPendingBlockSourceStartRow),A
        LD      A,1
        LD      (EditorPendingBlockRowCount),A
        CALL    EditorPendingBlockDeleteOriginalSource
        RET     C
        XOR     A
        LD      (EditorCursorCol),A
        CALL    EditorMarkDirty
        CALL    EditorKeyRenderDirty
        RET     C
        JP      EditorKeyLoop

EditorKeyDeleteBlockPrompt:
        LD      A,TECM8_EDITOR_PROMPT_ACTION_DELETE_BLOCK
        LD      (EditorPromptAction),A
        LD      HL,EditorDeleteBlockPromptText
        CALL    EditorPromptAskYesNo
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
        XOR     A
        JP      EditorKeyLoop

EditorKeyEscape:
        CALL    EditorBlockStateClearForEdit
        RET     C
        JP      EditorKeyLoop

;! in HL
;! out carry,zero,A
;! clobbers sign,parity,halfCarry,BC,DE,HL
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
;! out A,carry
;! clobbers zero,sign,parity,halfCarry,BC,DE,HL
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

EditorCursorSavedCol:
        .db     0

EditorInsertMode:
        .db     0

EditorPromptAction:
        .db     0

EditorQuitRequested:
        .db     0

EditorStatusTextPtr:
        .dw     0

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

EditorRestorePromptText:
        .db     "Restore backup? Y/N",0

EditorQuitPromptText:
        .db     "Discard changes? Y/N",0

EditorDeleteBlockPromptText:
        .db     "Delete block? Y/N",0
