; TECM8 editor status-line prompt handling.

; EditorPromptAskYesNo -
; Activate a status-line yes/no prompt using the NUL-terminated text at HL.
;! in HL
;! out A,carry
;! clobbers zero,sign,parity,halfCarry,BC,DE,HL
@EditorPromptAskYesNo:
        LD      (EditorPromptTextPtr),HL
        CALL    EditorHideCursor
        RET     C
        XOR     A
        LD      (EditorPromptResult),A
        LD      A,1
        LD      (EditorPromptActive),A
        JP      EditorViewportRenderStatusOverlay

;! in A
;! out A,carry
;! clobbers zero,sign,parity,halfCarry,BC,DE,HL
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

;! out A,carry,zero
;! clobbers sign,parity,halfCarry,BC,DE,HL
@EditorPromptDispatch:
        LD      A,(EditorPromptActive)
        OR      A
        RET     NZ
        LD      A,(EditorPromptAction)
        CP      TECM8_EDITOR_PROMPT_ACTION_RESTORE
        JR      Z,EditorPromptDispatchRestore
        CP      TECM8_EDITOR_PROMPT_ACTION_QUIT
        JR      Z,EditorPromptDispatchQuit
        CP      TECM8_EDITOR_PROMPT_ACTION_DELETE_BLOCK
        JR      Z,EditorPromptDispatchDeleteBlock
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

EditorPromptDispatchDeleteBlock:
        XOR     A
        LD      (EditorPromptAction),A
        LD      A,(EditorPromptResult)
        CP      TECM8_EDITOR_PROMPT_RESULT_YES
        JR      Z,EditorDeleteBlockConfirmed
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

EditorDeleteBlockConfirmed:
        CALL    EditorDeleteSelectedBlock
        RET     C
        OR      A
        RET     Z
        CALL    EditorKeyRenderDirty
        RET     C
        XOR     A
        RET
