; Editor block-delete proof.
;
; Verifies selected whole-line block deletion prompt behavior in a compact proof
; separate from the larger selection/paste proof.

        .org    0x4000

        .include "../../src/tecm8-equates.asm"

PROOF_PASS       .equ     0x42
PROOF_FAIL       .equ     0xE0
PROOF_MOD_SHIFT  .equ     0x01
PROOF_MOD_CTRL   .equ     0x02

;! out carry,zero
;! clobbers A,BC,DE,HL
@Start:
        CALL    DisplayInit
        JP      C,ProofFailed

        LD      A,1
        LD      (CaseMarker),A
        LD      HL,CmdEdit
        LD      DE,NoKeys
        CALL    ShellRunEditorSession
        JP      C,ProofFailed
        CALL    EditorCursorReset
        JP      C,ProofFailed
        CALL    SelectRowsZeroToOne
        JP      C,ProofFailed
        LD      A,TECM8_EDITOR_KEY_DELETE
        LD      B,0
        CALL    EditorRunModifiedKey
        JP      C,ProofFailed
        LD      A,"n"
        LD      B,0
        CALL    EditorRunModifiedKey
        JP      C,ProofFailed
        CALL    AssertDeleteBlockNoCancelled
        JP      C,ProofFailed

        LD      A,2
        LD      (CaseMarker),A
        CALL    EditorOpenMain
        JP      C,ProofFailed
        CALL    EditorCursorReset
        JP      C,ProofFailed
        CALL    SelectRowsZeroToOne
        JP      C,ProofFailed
        LD      A,TECM8_EDITOR_KEY_DELETE
        LD      B,0
        CALL    EditorRunModifiedKey
        JP      C,ProofFailed
        LD      A,"y"
        LD      B,0
        CALL    EditorRunModifiedKey
        JP      C,ProofFailed
        CALL    GlcdTileDrainPending
        JP      C,ProofFailed
        CALL    AssertDeleteBlockYesRows
        JP      C,ProofFailed

        LD      A,3
        LD      (CaseMarker),A
        CALL    EditorOpenMain
        JP      C,ProofFailed
        CALL    EditorCursorReset
        JP      C,ProofFailed
        LD      A,TECM8_EDITOR_KEY_ARROW_DOWN
        LD      B,0
        CALL    EditorRunModifiedKey
        JP      C,ProofFailed
        LD      A,TECM8_EDITOR_KEY_CTRL_Y
        LD      B,PROOF_MOD_CTRL
        CALL    EditorRunModifiedKey
        JP      C,ProofFailed
        CALL    GlcdTileDrainPending
        JP      C,ProofFailed
        CALL    AssertDeleteCurrentLineRows
        JP      C,ProofFailed

        LD      A,PROOF_PASS
        LD      (ResultMarker),A

ProofDone:
        JP      ProofDone

ProofFailed:
        LD      (ErrorMarker),A
        LD      A,(CaseMarker)
        OR      PROOF_FAIL
        LD      (ResultMarker),A

ProofFailedDone:
        JP      ProofDone

;! out A,carry,zero
;! clobbers A,BC,DE,HL,zero,sign,parity,halfCarry
@SelectRowsZeroToOne:
        LD      A,TECM8_EDITOR_KEY_ARROW_DOWN
        LD      B,PROOF_MOD_SHIFT
        JP      EditorRunModifiedKey

;! out A,carry,zero
;! clobbers A,BC,DE,HL
@AssertDeleteBlockNoCancelled:
        LD      A,(EditorBlockSelectionActive)
        CP      1
        JP      NZ,AssertFail
        LD      A,(EditorPendingBlockMode)
        OR      A
        JP      NZ,AssertFail
        LD      A,(EditorPromptActive)
        OR      A
        JP      NZ,AssertFail
        LD      A,(EditorPromptAction)
        OR      A
        JP      NZ,AssertFail
        LD      HL,ExpectedP0Line00
        LD      DE,EditorNavPageBuffer
        CALL    AssertRecordEquals
        JP      C,AssertFail
        LD      HL,ExpectedP0Line01
        LD      DE,EditorNavPageBuffer + 32
        CALL    AssertRecordEquals
        JP      C,AssertFail
        XOR     A
        RET

;! out A,carry,zero
;! clobbers A,BC,DE,HL
@AssertDeleteBlockYesRows:
        LD      A,(EditorBlockSelectionActive)
        OR      A
        JP      NZ,AssertFail
        LD      A,(EditorPendingBlockMode)
        OR      A
        JP      NZ,AssertFail
        LD      A,(EditorPromptActive)
        OR      A
        JP      NZ,AssertFail
        LD      A,(EditorPromptAction)
        OR      A
        JP      NZ,AssertFail
        LD      A,(EditorNavDirty)
        CP      1
        JP      NZ,AssertFail
        LD      A,(EditorCursorRow)
        OR      A
        JP      NZ,AssertFail
        LD      A,(EditorCursorCol)
        OR      A
        JP      NZ,AssertFail
        LD      HL,ExpectedP0Line01
        LD      DE,EditorNavPageBuffer
        CALL    AssertRecordEquals
        JP      C,AssertFail
        LD      HL,ExpectedP0Line02
        LD      DE,EditorNavPageBuffer + 32
        CALL    AssertRecordEquals
        JP      C,AssertFail
        LD      HL,ExpectedP0Line03
        LD      DE,EditorNavPageBuffer + (2 * 32)
        CALL    AssertRecordEquals
        JP      C,AssertFail
        LD      HL,ExpectedP0Line15
        LD      DE,EditorNavPageBuffer + (14 * 32)
        CALL    AssertRecordEquals
        JP      C,AssertFail
        LD      A,15
        CALL    EditorKeyRecordAtRow
        CALL    AssertRecordZeroed
        JP      C,AssertFail
        XOR     A
        RET

;! out A,carry,zero
;! clobbers A,BC,DE,HL
@AssertDeleteCurrentLineRows:
        LD      A,(EditorBlockSelectionActive)
        OR      A
        JP      NZ,AssertFail
        LD      A,(EditorPendingBlockMode)
        OR      A
        JP      NZ,AssertFail
        LD      A,(EditorPromptActive)
        OR      A
        JP      NZ,AssertFail
        LD      A,(EditorNavDirty)
        CP      1
        JP      NZ,AssertFail
        LD      A,(EditorCursorRow)
        CP      1
        JP      NZ,AssertFail
        LD      A,(EditorCursorCol)
        OR      A
        JP      NZ,AssertFail
        LD      HL,ExpectedP0Line00
        LD      DE,EditorNavPageBuffer
        CALL    AssertRecordEquals
        JP      C,AssertFail
        LD      HL,ExpectedP0Line02
        LD      DE,EditorNavPageBuffer + 32
        CALL    AssertRecordEquals
        JP      C,AssertFail
        LD      HL,ExpectedP0Line03
        LD      DE,EditorNavPageBuffer + (2 * 32)
        CALL    AssertRecordEquals
        JP      C,AssertFail
        LD      HL,ExpectedP0Line15
        LD      DE,EditorNavPageBuffer + (14 * 32)
        CALL    AssertRecordEquals
        JP      C,AssertFail
        LD      A,15
        CALL    EditorKeyRecordAtRow
        CALL    AssertRecordZeroed
        JP      C,AssertFail
        XOR     A
        RET

;! in DE,HL
;! out A,BC,DE,HL,carry,zero
;! clobbers A,BC,DE,HL
@AssertRecordEquals:
        LD      A,(HL)
        LD      B,A
        INC     B

AssertRecordEqualsLoop:
        LD      A,(DE)
        CP      (HL)
        JR      NZ,AssertFail
        INC     DE
        INC     HL
        DJNZ    AssertRecordEqualsLoop
        XOR     A
        RET

;! in HL
;! out A,B,HL,carry,zero
;! clobbers A,B,HL
@AssertRecordZeroed:
        LD      B,32

AssertRecordZeroedLoop:
        LD      A,(HL)
        OR      A
        JR      NZ,AssertFail
        INC     HL
        DJNZ    AssertRecordZeroedLoop
        XOR     A
        RET

AssertFail:
        SCF
        RET

; Stub LoadProjectConfig for shell-to-editor proof.
;! in B,DE
;! out DE,HL,A,C,carry,zero
;! clobbers B
@LoadProjectConfig:
        LD      HL,ExpectedMain
        LD      C,B

LoadProjectStubLoop:
        LD      A,(HL)
        LD      (DE),A
        INC     HL
        INC     DE
        OR      A
        JR      Z,LoadProjectStubOk
        DEC     C
        JR      NZ,LoadProjectStubLoop
        LD      A,SHELL_ERR_LONG
        SCF
        RET

LoadProjectStubOk:
        XOR     A
        RET

        .include "../../src/glcd-tile.asm"
        .include "../../src/display-model.asm"
        .include "../../src/editor-viewport.asm"
        .include "../../src/tecm8-string.asm"
        .include "../../src/tecm8-storage.asm"
        .include "../../src/editor-storage-loader.asm"
        .include "../../src/editor-navigation.asm"
        .include "../../src/tecm8-record.asm"
        .include "../../src/editor-interaction.asm"
        .include "../../src/shell-commands.asm"
        .include "../../src/shell-editor-launch.asm"
        .include "../../src/tecm8-bios.asm"

CmdEdit:
        .db     "edit",0

NoKeys:
        .db     0

ExpectedMain:
        .db     "/src/main.asm",0

CaseMarker:
        .db     0

ErrorMarker:
        .db     0

ResultMarker:
        .db     0

ExpectedP0Line00:
        .db     10,"P0 LINE 00"

ExpectedP0Line01:
        .db     10,"P0 LINE 01"

ExpectedP0Line02:
        .db     10,"P0 LINE 02"

ExpectedP0Line03:
        .db     10,"P0 LINE 03"

ExpectedP0Line04:
        .db     10,"P0 LINE 04"

ExpectedP0Line15:
        .db     10,"P0 LINE 15"
