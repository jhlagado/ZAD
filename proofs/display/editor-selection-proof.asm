; Editor line-selection proof.
;
; Opens the default source through the shell, then verifies Shift+Up/Down
; create an ordinary inclusive line-selection range and ordinary movement/editing
; clears it.

        .org    0x4000

PROOF_PASS       .equ     0x42
PROOF_FAIL       .equ     0xE0
PROOF_MOD_SHIFT  .equ     0x01
PROOF_MOD_ALT    .equ     0x08

;!      out       carry,zero
;!      clobbers  A,BC,DE,HL
@Start:
        CALL    DisplayInit
        JP      C,ProofFailed

        LD      A,1
        LD      (CaseMarker),A
        LD      HL,CmdEdit
        LD      DE,NoKeys
        CALL    ShellRunEditorSession
        JP      C,ProofFailed

        LD      A,2
        LD      (CaseMarker),A
        LD      A,TECM8_EDITOR_KEY_ARROW_DOWN
        LD      B,PROOF_MOD_SHIFT
        CALL    EditorRunModifiedKey
        JP      C,ProofFailed
        CALL    GlcdTileDrainPending
        JP      C,ProofFailed
        CALL    AssertSelectionRowsZeroToOne
        JP      C,ProofFailed

        LD      A,3
        LD      (CaseMarker),A
        LD      A,TECM8_EDITOR_KEY_ARROW_DOWN
        LD      B,PROOF_MOD_SHIFT
        CALL    EditorRunModifiedKey
        JP      C,ProofFailed
        CALL    GlcdTileDrainPending
        JP      C,ProofFailed
        CALL    AssertSelectionRowsZeroToTwo
        JP      C,ProofFailed

        LD      A,4
        LD      (CaseMarker),A
        LD      A,TECM8_EDITOR_KEY_ARROW_UP
        LD      B,PROOF_MOD_SHIFT
        CALL    EditorRunModifiedKey
        JP      C,ProofFailed
        CALL    GlcdTileDrainPending
        JP      C,ProofFailed
        CALL    AssertSelectionRowsZeroToOne
        JP      C,ProofFailed

        LD      A,5
        LD      (CaseMarker),A
        LD      A,TECM8_EDITOR_KEY_ARROW_DOWN
        LD      B,0
        CALL    EditorRunModifiedKey
        JP      C,ProofFailed
        CALL    AssertGutterRowsZeroOneQueued
        JP      C,ProofFailed
        CALL    GlcdTileDrainPending
        JP      C,ProofFailed
        CALL    AssertSelectionClear
        JP      C,ProofFailed

        LD      A,6
        LD      (CaseMarker),A
        CALL    EditorOpenMain
        JP      C,ProofFailed
        CALL    EditorCursorReset
        JP      C,ProofFailed
        CALL    GlcdTileDrainPending
        JP      C,ProofFailed
        LD      A,TECM8_EDITOR_KEY_ARROW_DOWN
        LD      B,PROOF_MOD_SHIFT | PROOF_MOD_ALT
        CALL    EditorRunModifiedKey
        JP      C,ProofFailed
        CALL    GlcdTileDrainPending
        JP      C,ProofFailed
        CALL    AssertPageSelectionDown
        JP      C,ProofFailed

        LD      A,7
        LD      (CaseMarker),A
        LD      A,TECM8_EDITOR_KEY_ARROW_UP
        LD      B,PROOF_MOD_SHIFT | PROOF_MOD_ALT
        CALL    EditorRunModifiedKey
        JP      C,ProofFailed
        CALL    GlcdTileDrainPending
        JP      C,ProofFailed
        CALL    AssertPageSelectionUp
        JP      C,ProofFailed

        LD      A,8
        LD      (CaseMarker),A
        CALL    EditorOpenMain
        JP      C,ProofFailed
        CALL    EditorCursorReset
        JP      C,ProofFailed
        LD      A,10
        LD      (ShiftDownCount),A
        CALL    RunShiftDownCount
        JP      C,ProofFailed
        CALL    GlcdTileDrainPending
        JP      C,ProofFailed
        CALL    AssertViewportSelectionScroll
        JP      C,ProofFailed

        LD      A,9
        LD      (CaseMarker),A
        LD      A,TECM8_EDITOR_KEY_ARROW_UP
        LD      B,PROOF_MOD_SHIFT
        CALL    EditorRunModifiedKey
        JP      C,ProofFailed
        CALL    GlcdTileDrainPending
        JP      C,ProofFailed
        LD      A,"Z"
        LD      B,0
        CALL    EditorRunModifiedKey
        JP      C,ProofFailed
        CALL    GlcdTileDrainPending
        JP      C,ProofFailed
        CALL    AssertSelectionClear
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

;!      out       A,carry,zero
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@RunShiftDownCount:
        LD      A,(ShiftDownCount)
        OR      A
        RET     Z
        LD      A,TECM8_EDITOR_KEY_ARROW_DOWN
        LD      B,PROOF_MOD_SHIFT
        CALL    EditorRunModifiedKey
        RET     C
        LD      A,(ShiftDownCount)
        DEC     A
        LD      (ShiftDownCount),A
        JR      RunShiftDownCount

;!      out       A,carry,zero
;!      clobbers  A,HL
@AssertSelectionRowsZeroToOne:
        LD      A,(EditorBlockSelectionActive)
        CP      1
        JP      NZ,AssertFail
        LD      A,(EditorBlockSelectionAnchorLo)
        OR      A
        JP      NZ,AssertFail
        LD      A,(EditorBlockSelectionAnchorHi)
        OR      A
        JP      NZ,AssertFail
        LD      A,(EditorBlockSelectionActiveLo)
        CP      1
        JP      NZ,AssertFail
        LD      A,(EditorBlockSelectionActiveHi)
        OR      A
        JP      NZ,AssertFail
        LD      HL,EditorScreenDescriptor
        LD      A,(HL)
        CP      TECM8_DISPLAY_MARKER_SELECTED
        JP      NZ,AssertFail
        LD      DE,3
        ADD     HL,DE
        LD      A,(HL)
        CP      TECM8_DISPLAY_MARKER_CURRENT | TECM8_DISPLAY_MARKER_SELECTED
        JP      NZ,AssertFail
        XOR     A
        RET

;!      out       A,carry,zero
;!      clobbers  A,HL
@AssertSelectionRowsZeroToTwo:
        LD      A,(EditorBlockSelectionActive)
        CP      1
        JP      NZ,AssertFail
        LD      A,(EditorBlockSelectionAnchorLo)
        OR      A
        JP      NZ,AssertFail
        LD      A,(EditorBlockSelectionAnchorHi)
        OR      A
        JP      NZ,AssertFail
        LD      A,(EditorBlockSelectionActiveLo)
        CP      2
        JP      NZ,AssertFail
        LD      A,(EditorBlockSelectionActiveHi)
        OR      A
        JP      NZ,AssertFail
        LD      HL,EditorScreenDescriptor
        LD      A,(HL)
        CP      TECM8_DISPLAY_MARKER_SELECTED
        JP      NZ,AssertFail
        LD      DE,3
        ADD     HL,DE
        LD      A,(HL)
        CP      TECM8_DISPLAY_MARKER_SELECTED
        JP      NZ,AssertFail
        LD      HL,EditorScreenDescriptor + 6
        LD      A,(HL)
        CP      TECM8_DISPLAY_MARKER_CURRENT | TECM8_DISPLAY_MARKER_SELECTED
        JP      NZ,AssertFail
        XOR     A
        RET

;!      out       A,carry,zero
;!      clobbers  A
@AssertSelectionClear:
        LD      A,(EditorBlockSelectionActive)
        OR      A
        JP      NZ,AssertFail
        XOR     A
        RET

;!      out       A,carry,zero
;!      clobbers  A,HL
@AssertGutterRowsZeroOneQueued:
        LD      A,(GlcdTileDirtyCellRowsLo)
        AND     0x03
        CP      0x03
        JP      NZ,AssertFail
        LD      HL,GlcdTileDirtyCellMin
        LD      A,(HL)
        OR      A
        JP      NZ,AssertFail
        INC     HL
        LD      A,(HL)
        OR      A
        JP      NZ,AssertFail
        LD      HL,GlcdTileDirtyCellMax
        LD      A,(HL)
        CP      1
        JP      NZ,AssertFail
        INC     HL
        LD      A,(HL)
        CP      1
        JP      NZ,AssertFail
        XOR     A
        RET

;!      out       A,carry,zero
;!      clobbers  A,HL
@AssertPageSelectionDown:
        LD      A,(EditorNavCurrentPage)
        CP      1
        JP      NZ,AssertFail
        LD      A,(EditorBlockSelectionActive)
        CP      1
        JP      NZ,AssertFail
        LD      A,(EditorBlockSelectionAnchorLo)
        OR      A
        JP      NZ,AssertFail
        LD      A,(EditorBlockSelectionAnchorHi)
        OR      A
        JP      NZ,AssertFail
        LD      A,(EditorBlockSelectionActiveLo)
        CP      16
        JP      NZ,AssertFail
        LD      A,(EditorBlockSelectionActiveHi)
        OR      A
        JP      NZ,AssertFail
        LD      HL,EditorScreenDescriptor
        LD      A,(HL)
        CP      TECM8_DISPLAY_MARKER_CURRENT | TECM8_DISPLAY_MARKER_SELECTED
        JP      NZ,AssertFail
        XOR     A
        RET

;!      out       A,carry,zero
;!      clobbers  A,HL
@AssertPageSelectionUp:
        LD      A,(EditorNavCurrentPage)
        OR      A
        JP      NZ,AssertFail
        LD      A,(EditorBlockSelectionActive)
        CP      1
        JP      NZ,AssertFail
        LD      A,(EditorBlockSelectionAnchorLo)
        OR      A
        JP      NZ,AssertFail
        LD      A,(EditorBlockSelectionActiveLo)
        OR      A
        JP      NZ,AssertFail
        LD      HL,EditorScreenDescriptor
        LD      A,(HL)
        CP      TECM8_DISPLAY_MARKER_CURRENT | TECM8_DISPLAY_MARKER_SELECTED
        JP      NZ,AssertFail
        XOR     A
        RET

;!      out       A,carry,zero
;!      clobbers  A,HL
@AssertViewportSelectionScroll:
        LD      A,(EditorNavViewportTopRow)
        CP      1
        JP      NZ,AssertFail
        LD      A,(EditorCursorRow)
        CP      10
        JP      NZ,AssertFail
        LD      A,(EditorBlockSelectionActiveLo)
        CP      10
        JP      NZ,AssertFail
        LD      HL,EditorScreenDescriptor
        LD      A,(HL)
        CP      TECM8_DISPLAY_MARKER_SELECTED
        JP      NZ,AssertFail
        LD      HL,EditorScreenDescriptor + 27
        LD      A,(HL)
        CP      TECM8_DISPLAY_MARKER_CURRENT | TECM8_DISPLAY_MARKER_SELECTED
        JP      NZ,AssertFail
        XOR     A
        RET

AssertFail:
        SCF
        RET

; Stub LoadProjectConfig for shell-to-editor proof.
;!      in        B,DE
;!      out       DE,HL,A,C,carry,zero
;!      clobbers  B
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
        .include "../../src/editor-storage-loader.asm"
        .include "../../src/editor-navigation.asm"
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

ShiftDownCount:
        .db     0
