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

; EditorBlockSelectionBeginIfNeeded -
; Start an exclusive-endpoint whole-line block selection at the current
; absolute line if no ordinary selection is already active.
;! out A,carry,zero
;! clobbers sign,parity,halfCarry,HL
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
;! out A,carry,zero
;! clobbers sign,parity,halfCarry,HL
@EditorBlockSelectionCapturePageAnchor:
        LD      A,(EditorBlockSelectionActive)
        LD      (EditorBlockSelectionPageWasActive),A
        ; expects out HL
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
;! out A,carry,zero
;! clobbers sign,parity,halfCarry
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
;! out A,carry,zero
;! clobbers sign,parity,halfCarry,HL
@EditorBlockSelectionUpdateActive:
        ; expects out HL
        CALL    EditorBlockSelectionCurrentLine
        LD      A,L
        LD      (EditorBlockSelectionActiveLo),A
        LD      A,H
        LD      (EditorBlockSelectionActiveHi),A
        LD      A,(EditorBlockSelectionAnchorHi)
        CP      H
        JR      NZ,EditorBlockSelectionUpdateStillActive
        LD      A,(EditorBlockSelectionAnchorLo)
        CP      L
        JR      NZ,EditorBlockSelectionUpdateStillActive
        XOR     A
        LD      (EditorBlockSelectionActive),A
        RET

EditorBlockSelectionUpdateStillActive:
        LD      A,1
        LD      (EditorBlockSelectionActive),A
        XOR     A
        RET

; EditorBlockSelectionClearState -
; Clear ordinary selection state without repainting. Used before full page
; renders and cursor resets.
;! out carry,zero,A,sign,parity,halfCarry
@EditorBlockSelectionClearState:
        XOR     A
        LD      (EditorBlockSelectionActive),A
        RET

; EditorPendingBlockClearState -
; Clear the pending copy/move source without repainting.
;! out carry,zero,A,sign,parity,halfCarry
@EditorPendingBlockClearState:
        XOR     A
        LD      (EditorPendingBlockMode),A
        RET

; EditorPendingBlockArm -
; Convert the ordinary selected range into a pending copy/move source.
; Input: A = TECM8_EDITOR_PENDING_BLOCK_COPY or *_MOVE.
;! in A
;! out BC,DE,A,carry,zero
;! clobbers sign,parity,halfCarry,HL
@EditorPendingBlockArm:
        LD      (EditorPendingBlockRequestedMode),A
        LD      A,(EditorBlockSelectionActive)
        OR      A
        JR      Z,EditorPendingBlockArmNoSelection
        LD      A,(EditorBlockSelectionAnchorHi)
        LD      H,A
        LD      A,(EditorBlockSelectionAnchorLo)
        LD      L,A
        LD      A,(EditorBlockSelectionActiveHi)
        LD      D,A
        LD      A,(EditorBlockSelectionActiveLo)
        LD      E,A
        CALL    EditorBlockSelectionCompareHlDe
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
; the current resident page, unsafe overlap/self cases are rejected, and empty
; tail rows must exist so no records are discarded.
;! out A,carry,zero
;! clobbers sign,parity,halfCarry,BC,DE,HL
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
;! out A,carry
;! clobbers zero,sign,parity,halfCarry,BC,DE,HL
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

;! out A,L,carry,zero
;! clobbers sign,parity,halfCarry,BC,H
@EditorPendingBlockRowsForCurrentPage:
        CALL    EditorPendingBlockPageBaseForCurrentPage
        LD      A,(EditorPendingBlockStartHi)
        LD      H,A
        LD      A,(EditorPendingBlockPageBaseHi)
        CP      H
        JR      NZ,EditorPendingBlockRowsErr
        LD      A,(EditorPendingBlockEndHi)
        LD      H,A
        LD      A,(EditorPendingBlockPageBaseHi)
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

;! out A,carry,zero,HL
;! clobbers sign,parity,halfCarry
@EditorPendingBlockPageBaseForCurrentPage:
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
        XOR     A
        RET

EditorPendingBlockRowsErr:
        SCF
        RET

;! out DE,A,carry,zero
;! clobbers sign,parity,halfCarry,BC,HL
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

;! out A,carry,zero
;! clobbers sign,parity,halfCarry,B
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

;! out A,carry,zero
;! clobbers sign,parity,halfCarry,B
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

;! out A,carry,zero
;! clobbers sign,parity,halfCarry,B
@EditorPendingBlockReplaceSameSize:
        LD      A,(EditorPendingBlockDestRowCount)
        LD      B,A
        LD      A,(EditorPendingBlockRowCount)
        CP      B
        RET

;! out A,carry,zero
;! clobbers sign,parity,halfCarry,BC,HL
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

;! out A,carry,zero
;! clobbers sign,parity,halfCarry,BC,DE,HL
@EditorPendingBlockCopySourceToScratch:
        LD      A,(EditorPendingBlockSourceStartRow)
        CALL    EditorKeyRecordAtRow
        LD      DE,EditorNavBackupPageBuffer
        LD      A,(EditorPendingBlockRowCount)
        CALL    Tecm8RecordShiftRecordsUp
        RET

;! out A,carry,zero
;! clobbers sign,parity,halfCarry,BC,DE,HL
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
        LD      A,(EditorPendingBlockShiftRow)
        LD      B,A
        LD      A,(EditorPendingBlockDestRow)
        LD      C,A
        LD      A,B
        SUB     C
        INC     A
        LD      (EditorLineRowsLeft),A
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
        LD      A,(EditorLineRowsLeft)
        CALL    Tecm8RecordShiftRecordsDown

EditorPendingBlockShiftDone:
        XOR     A
        RET

;! out A,carry,zero
;! clobbers sign,parity,halfCarry,BC,DE,HL
@EditorPendingBlockCopyScratchToDest:
        LD      A,(EditorPendingBlockDestRow)
        ; expects out HL
        CALL    EditorKeyRecordAtRow
        LD      D,H
        LD      E,L
        LD      HL,EditorNavBackupPageBuffer
        LD      A,(EditorPendingBlockRowCount)
        CALL    Tecm8RecordShiftRecordsUp
        RET

;! out A,carry,zero
;! clobbers sign,parity,halfCarry,BC,DE,HL
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
        LD      A,(EditorPendingBlockShiftRow)
        CP      16
        JR      Z,EditorPendingBlockDeleteClearTail
        LD      B,A
        LD      A,16
        SUB     B
        LD      (EditorLineRowsLeft),A
        LD      A,(EditorPendingBlockShiftRow)
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
        LD      A,(EditorLineRowsLeft)
        CALL    Tecm8RecordShiftRecordsUp

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
        ; expects out HL
        CALL    EditorKeyRecordAtRow
        CALL    EditorKeyClearRecord
        LD      A,(EditorPendingBlockTailCheckRow)
        INC     A
        LD      (EditorPendingBlockTailCheckRow),A
        JR      EditorPendingBlockDeleteClearLoop

EditorPendingBlockDeleteDone:
        XOR     A
        RET

;! out A,carry
;! clobbers zero,sign,parity,halfCarry,BC,DE,HL
@EditorPendingBlockDeleteOriginalSource:
        LD      A,(EditorPendingBlockSourceStartRow)
        JP      EditorPendingBlockDeleteStartReady

;! out carry,zero,A
;! clobbers sign,parity,halfCarry,BC,HL
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
        ADD     A,B
        LD      B,A
        LD      A,(EditorPendingBlockPageBaseLo)
        ADD     A,B
        LD      (EditorBlockSelectionActiveLo),A
        LD      C,A
        LD      A,(EditorPendingBlockPageBaseHi)
        ADC     A,0
        LD      (EditorBlockSelectionActiveHi),A
        LD      A,1
        LD      (EditorBlockSelectionActive),A
        LD      A,C
        CP      16
        JR      C,EditorPendingBlockCursorRowReady
        LD      A,15

EditorPendingBlockCursorRowReady:
        LD      (EditorCursorRow),A
        XOR     A
        LD      (EditorCursorCol),A
        RET

; EditorBlockSelectionClearIfActive -
; Clear ordinary selection state and repaint visible gutter markers when needed.
;! out A,carry
;! clobbers zero,sign,parity,halfCarry,BC,DE,HL
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
;! out A,carry
;! clobbers zero,sign,parity,halfCarry,BC,DE,HL
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
;! out A,carry,zero
;! clobbers sign,parity,halfCarry,BC,DE,HL
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
;! out HL,A,carry,zero
;! clobbers sign,parity,halfCarry
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

;! out A,carry,zero
;! clobbers sign,parity,halfCarry,BC,DE,HL
@EditorDeleteSelectedBlock:
        LD      A,(EditorBlockSelectionActive)
        OR      A
        JP      Z,EditorDeleteSelectedBlockNoop
        CALL    EditorPendingBlockPageBaseForCurrentPage
        CALL    EditorPendingBlockDestinationRowsForCurrentPage
        JP      C,EditorDeleteSelectedBlockNoop
        LD      A,(EditorPendingBlockDestStartRow)
        LD      (EditorPendingBlockSourceStartRow),A
        LD      A,(EditorPendingBlockDestRowCount)
        LD      (EditorPendingBlockRowCount),A
        CALL    EditorPendingBlockDeleteOriginalSource
        RET     C
        CALL    EditorBlockSelectionClearState
        CALL    EditorPendingBlockClearState
        LD      A,(EditorPendingBlockDestStartRow)
        LD      (EditorCursorRow),A
        XOR     A
        LD      (EditorCursorCol),A
        CALL    EditorMarkDirty
        LD      A,1
        RET

EditorDeleteSelectedBlockNoop:
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

EditorDeleteBlockPromptText:
        .db     "Delete block? Y/N",0
