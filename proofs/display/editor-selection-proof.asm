; Editor line-selection proof.
;
; Opens the default source through the shell, then verifies Shift+Up/Down
; create an ordinary exclusive-endpoint line-selection range and ordinary
; movement/editing clears it.

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
        LD      B,PROOF_MOD_SHIFT | PROOF_MOD_CTRL
        CALL    EditorRunModifiedKey
        JP      C,ProofFailed
        CALL    GlcdTileDrainPending
        JP      C,ProofFailed
        CALL    AssertPageSelectionDown
        JP      C,ProofFailed

        LD      A,7
        LD      (CaseMarker),A
        CALL    RunSyntheticShiftControlArrowUp
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

        LD      A,16
        LD      (CaseMarker),A
        CALL    EditorOpenMain
        JP      C,ProofFailed
        CALL    EditorCursorReset
        JP      C,ProofFailed
        LD      A,16
        LD      (ShiftDownCount),A
        CALL    RunShiftDownCount
        JP      C,ProofFailed
        CALL    GlcdTileDrainPending
        JP      C,ProofFailed
        CALL    AssertSelectionRowsZeroToFifteen
        JP      C,ProofFailed

        LD      A,10
        LD      (CaseMarker),A
        CALL    EditorOpenMain
        JP      C,ProofFailed
        CALL    EditorCursorReset
        JP      C,ProofFailed
        CALL    SelectRowsZeroToTwo
        JP      C,ProofFailed
        LD      A,"c"
        LD      B,PROOF_MOD_CTRL
        CALL    EditorRunModifiedKey
        JP      C,ProofFailed
        CALL    GlcdTileDrainPending
        JP      C,ProofFailed
        CALL    AssertPendingCopyRowsZeroToTwo
        JP      C,ProofFailed
        CALL    AssertCursorRenderedAtRowTwo
        JP      C,ProofFailed

        LD      A,21
        LD      (CaseMarker),A
        CALL    EditorOpenMain
        JP      C,ProofFailed
        CALL    EditorCursorReset
        JP      C,ProofFailed
        CALL    SelectRowsZeroToTwo
        JP      C,ProofFailed
        LD      A,0xFF
        LD      (BiosInputRawPrimary),A
        LD      (BiosInputRawSecondary),A
        LD      A,TECM8_EDITOR_KEY_CTRL_C
        LD      B,PROOF_MOD_CTRL
        CALL    EditorRunModifiedKey
        JP      C,ProofFailed
        CALL    GlcdTileDrainPending
        JP      C,ProofFailed
        CALL    AssertPendingCopyRowsZeroToTwo
        JP      C,ProofFailed

        LD      A,20
        LD      (CaseMarker),A
        LD      A,TECM8_EDITOR_KEY_ESCAPE
        LD      B,0
        CALL    EditorRunModifiedKey
        JP      C,ProofFailed
        CALL    GlcdTileDrainPending
        JP      C,ProofFailed
        CALL    AssertBlockStateClear
        JP      C,ProofFailed

        LD      A,11
        LD      (CaseMarker),A
        CALL    EditorOpenMain
        JP      C,ProofFailed
        CALL    EditorCursorReset
        JP      C,ProofFailed
        CALL    SelectRowsZeroToTwo
        JP      C,ProofFailed
        LD      A,"c"
        LD      B,PROOF_MOD_CTRL
        CALL    EditorRunModifiedKey
        JP      C,ProofFailed
        LD      A,TECM8_EDITOR_KEY_ARROW_DOWN
        LD      B,0
        CALL    EditorRunModifiedKey
        JP      C,ProofFailed
        LD      A,TECM8_EDITOR_KEY_ARROW_DOWN
        LD      B,PROOF_MOD_SHIFT
        CALL    EditorRunModifiedKey
        JP      C,ProofFailed
        CALL    AssertPendingCopyWithDestination
        JP      C,ProofFailed

        LD      A,12
        LD      (CaseMarker),A
        CALL    EditorOpenMain
        JP      C,ProofFailed
        CALL    EditorCursorReset
        JP      C,ProofFailed
        CALL    SelectRowsZeroToTwo
        JP      C,ProofFailed
        LD      A,TECM8_EDITOR_KEY_CTRL_X
        LD      B,PROOF_MOD_CTRL
        CALL    EditorRunModifiedKey
        JP      C,ProofFailed
        CALL    GlcdTileDrainPending
        JP      C,ProofFailed
        CALL    AssertPendingMoveRowsZeroToTwo
        JP      C,ProofFailed
        CALL    AssertCursorRenderedAtRowTwo
        JP      C,ProofFailed

        LD      A,13
        LD      (CaseMarker),A
        CALL    EditorOpenMain
        JP      C,ProofFailed
        CALL    EditorCursorReset
        JP      C,ProofFailed
        CALL    ClearPasteTailRows
        JP      C,ProofFailed
        CALL    SelectRowsZeroToOne
        JP      C,ProofFailed
        LD      A,"c"
        LD      B,PROOF_MOD_CTRL
        CALL    EditorRunModifiedKey
        JP      C,ProofFailed
        LD      A,3
        LD      (PlainDownCount),A
        CALL    RunPlainDownCount
        JP      C,ProofFailed
        LD      A,"v"
        LD      B,PROOF_MOD_CTRL
        CALL    EditorRunModifiedKey
        JP      C,ProofFailed
        CALL    GlcdTileDrainPending
        JP      C,ProofFailed
        CALL    AssertCopyPasteInsertRows
        JP      C,ProofFailed

        LD      A,14
        LD      (CaseMarker),A
        CALL    EditorOpenMain
        JP      C,ProofFailed
        CALL    EditorCursorReset
        JP      C,ProofFailed
        CALL    ClearPasteTailRows
        JP      C,ProofFailed
        CALL    SelectRowsZeroToOne
        JP      C,ProofFailed
        LD      A,"x"
        LD      B,PROOF_MOD_CTRL
        CALL    EditorRunModifiedKey
        JP      C,ProofFailed
        LD      A,3
        LD      (PlainDownCount),A
        CALL    RunPlainDownCount
        JP      C,ProofFailed
        LD      A,TECM8_EDITOR_KEY_CTRL_V
        LD      B,PROOF_MOD_CTRL
        CALL    EditorRunModifiedKey
        JP      C,ProofFailed
        CALL    GlcdTileDrainPending
        JP      C,ProofFailed
        CALL    AssertMovePasteInsertRows
        JP      C,ProofFailed

        LD      A,15
        LD      (CaseMarker),A
        CALL    EditorOpenMain
        JP      C,ProofFailed
        CALL    EditorCursorReset
        JP      C,ProofFailed
        CALL    ClearPasteTailRows
        JP      C,ProofFailed
        CALL    SelectRowsZeroToOne
        JP      C,ProofFailed
        LD      A,"c"
        LD      B,PROOF_MOD_CTRL
        CALL    EditorRunModifiedKey
        JP      C,ProofFailed
        LD      A,"v"
        LD      B,PROOF_MOD_CTRL
        CALL    EditorRunModifiedKey
        JP      C,ProofFailed
        CALL    AssertPasteNoopPendingCopyRowsZeroToOne
        JP      C,ProofFailed

        LD      A,18
        LD      (CaseMarker),A
        CALL    EditorOpenMain
        JP      C,ProofFailed
        CALL    EditorCursorReset
        JP      C,ProofFailed
        CALL    SelectRowsZeroToOne
        JP      C,ProofFailed
        LD      A,"c"
        LD      B,PROOF_MOD_CTRL
        CALL    EditorRunModifiedKey
        JP      C,ProofFailed
        LD      A,2
        LD      (PlainDownCount),A
        CALL    RunPlainDownCount
        JP      C,ProofFailed
        CALL    SelectRowsZeroToOne
        JP      C,ProofFailed
        LD      A,"v"
        LD      B,PROOF_MOD_CTRL
        CALL    EditorRunModifiedKey
        JP      C,ProofFailed
        CALL    GlcdTileDrainPending
        JP      C,ProofFailed
        CALL    AssertCopyPasteReplaceRows
        JP      C,ProofFailed

        LD      A,19
        LD      (CaseMarker),A
        CALL    EditorOpenMain
        JP      C,ProofFailed
        CALL    EditorCursorReset
        JP      C,ProofFailed
        CALL    SelectRowsZeroToOne
        JP      C,ProofFailed
        LD      A,"x"
        LD      B,PROOF_MOD_CTRL
        CALL    EditorRunModifiedKey
        JP      C,ProofFailed
        LD      A,2
        LD      (PlainDownCount),A
        CALL    RunPlainDownCount
        JP      C,ProofFailed
        CALL    SelectRowsZeroToOne
        JP      C,ProofFailed
        LD      A,"v"
        LD      B,PROOF_MOD_CTRL
        CALL    EditorRunModifiedKey
        JP      C,ProofFailed
        CALL    GlcdTileDrainPending
        JP      C,ProofFailed
        CALL    AssertMovePasteReplaceRows
        JP      C,ProofFailed

        LD      A,PROOF_PASS
        LD      (ResultMarker),A

ProofDone:
        JP      ProofDone

;! out A,carry
;! clobbers A,BC,DE,HL,zero,sign,parity,halfCarry
@RunSyntheticShiftControlArrowUp:
        LD      A,TECM8_EDITOR_KEY_ARROW_UP
        LD      (BiosInputRawPrimary),A
        LD      A,0x01
        LD      (BiosInputRawSecondary),A
        LD      A,TECM8_EDITOR_KEY_ARROW_UP
        LD      B,PROOF_MOD_SHIFT | PROOF_MOD_CTRL
        CALL    EditorRunModifiedKey
        JR      C,RunSyntheticShiftControlArrowUpErr
        LD      A,0xFF
        LD      (BiosInputRawPrimary),A
        LD      (BiosInputRawSecondary),A
        XOR     A
        RET

RunSyntheticShiftControlArrowUpErr:
        LD      B,A
        LD      A,0xFF
        LD      (BiosInputRawPrimary),A
        LD      (BiosInputRawSecondary),A
        LD      A,B
        SCF
        RET

ProofFailed:
        LD      (ErrorMarker),A
        LD      A,(CaseMarker)
        OR      PROOF_FAIL
        LD      (ResultMarker),A

ProofFailedDone:
        JP      ProofDone

;! out A,carry,zero
;! clobbers A,BC,DE,HL,zero,sign,parity,halfCarry
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

;! out A,carry,zero
;! clobbers A,BC,DE,HL,zero,sign,parity,halfCarry
@RunPlainDownCount:
        LD      A,(PlainDownCount)
        OR      A
        RET     Z
        LD      A,TECM8_EDITOR_KEY_ARROW_DOWN
        LD      B,0
        CALL    EditorRunModifiedKey
        RET     C
        LD      A,(PlainDownCount)
        DEC     A
        LD      (PlainDownCount),A
        JR      RunPlainDownCount

;! out A,carry,zero
;! clobbers A,BC,DE,HL,zero,sign,parity,halfCarry
@SelectRowsZeroToOne:
        LD      A,TECM8_EDITOR_KEY_ARROW_DOWN
        LD      B,PROOF_MOD_SHIFT
        CALL    EditorRunModifiedKey
        RET     C
        LD      A,TECM8_EDITOR_KEY_ARROW_DOWN
        LD      B,PROOF_MOD_SHIFT
        JP      EditorRunModifiedKey

;! out A,carry,zero
;! clobbers A,BC,DE,HL,zero,sign,parity,halfCarry
@SelectRowsZeroToTwo:
        LD      A,TECM8_EDITOR_KEY_ARROW_DOWN
        LD      B,PROOF_MOD_SHIFT
        CALL    EditorRunModifiedKey
        RET     C
        LD      A,TECM8_EDITOR_KEY_ARROW_DOWN
        LD      B,PROOF_MOD_SHIFT
        CALL    EditorRunModifiedKey
        RET     C
        LD      A,TECM8_EDITOR_KEY_ARROW_DOWN
        LD      B,PROOF_MOD_SHIFT
        JP      EditorRunModifiedKey

;! out A,carry,zero
;! clobbers A,B,HL
@ClearPasteTailRows:
        LD      A,14
        CALL    EditorKeyRecordAtRow
        CALL    EditorKeyClearRecord
        LD      A,15
        CALL    EditorKeyRecordAtRow
        JP      EditorKeyClearRecord

;! out A,carry,zero
;! clobbers A,HL
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
        CP      TECM8_DISPLAY_MARKER_NONE
        JP      NZ,AssertFail
        XOR     A
        RET

;! out A,carry,zero
;! clobbers A,HL
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
        CP      TECM8_DISPLAY_MARKER_NONE
        JP      NZ,AssertFail
        XOR     A
        RET

;! out A,carry,zero
;! clobbers A
@AssertSelectionClear:
        LD      A,(EditorBlockSelectionActive)
        OR      A
        JP      NZ,AssertFail
        XOR     A
        RET

;! out A,carry,zero
;! clobbers A,HL
@AssertBlockStateClear:
        LD      A,(EditorBlockSelectionActive)
        OR      A
        JP      NZ,AssertFail
        LD      A,(EditorPendingBlockMode)
        OR      A
        JP      NZ,AssertFail
        LD      HL,EditorScreenDescriptor
        LD      A,(HL)
        AND     TECM8_DISPLAY_MARKER_SELECTED | TECM8_DISPLAY_MARKER_COPY_SOURCE | TECM8_DISPLAY_MARKER_MOVE_SOURCE
        JP      NZ,AssertFail
        LD      HL,EditorScreenDescriptor + 3
        LD      A,(HL)
        AND     TECM8_DISPLAY_MARKER_SELECTED | TECM8_DISPLAY_MARKER_COPY_SOURCE | TECM8_DISPLAY_MARKER_MOVE_SOURCE
        JP      NZ,AssertFail
        LD      HL,EditorScreenDescriptor + 6
        LD      A,(HL)
        AND     TECM8_DISPLAY_MARKER_SELECTED | TECM8_DISPLAY_MARKER_COPY_SOURCE | TECM8_DISPLAY_MARKER_MOVE_SOURCE
        JP      NZ,AssertFail
        XOR     A
        RET

;! out A,carry,zero
;! clobbers A,HL
@AssertSelectionRowsZeroToFifteen:
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
        LD      A,(EditorCursorRow)
        CP      TECM8_EDITOR_CURSOR_MAX_ROW
        JP      NZ,AssertFail
        LD      HL,EditorScreenDescriptor + 27
        LD      A,(HL)
        CP      TECM8_DISPLAY_MARKER_SELECTED
        JP      NZ,AssertFail
        XOR     A
        RET

;! out A,carry,zero
;! clobbers A,HL
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

;! out A,carry,zero
;! clobbers A,HL
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
        CP      TECM8_DISPLAY_MARKER_NONE
        JP      NZ,AssertFail
        XOR     A
        RET

;! out A,carry,zero
;! clobbers A,HL
@AssertPageSelectionUp:
        LD      A,(EditorNavCurrentPage)
        OR      A
        JP      NZ,AssertFail
        LD      A,(EditorBlockSelectionActive)
        OR      A
        JP      NZ,AssertFail
        LD      HL,EditorScreenDescriptor
        LD      A,(HL)
        CP      TECM8_DISPLAY_MARKER_NONE
        JP      NZ,AssertFail
        XOR     A
        RET

;! out A,carry,zero
;! clobbers A,HL
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
        CP      TECM8_DISPLAY_MARKER_NONE
        JP      NZ,AssertFail
        XOR     A
        RET

;! out A,carry,zero
;! clobbers A,HL
@AssertPendingCopyRowsZeroToTwo:
        LD      A,(EditorPendingBlockMode)
        CP      1
        JP      NZ,AssertFail
        CALL    AssertPendingSourceRowsZeroToTwo
        JP      C,AssertFail
        LD      A,(EditorBlockSelectionActive)
        OR      A
        JP      NZ,AssertFail
        LD      HL,EditorScreenDescriptor
        LD      A,(HL)
        CP      TECM8_DISPLAY_MARKER_COPY_SOURCE
        JP      NZ,AssertFail
        LD      HL,EditorScreenDescriptor + 3
        LD      A,(HL)
        CP      TECM8_DISPLAY_MARKER_COPY_SOURCE
        JP      NZ,AssertFail
        LD      HL,EditorScreenDescriptor + 6
        LD      A,(HL)
        CP      TECM8_DISPLAY_MARKER_COPY_SOURCE
        JP      NZ,AssertFail
        XOR     A
        RET

;! out A,carry,zero
;! clobbers A,HL
@AssertPendingCopyWithDestination:
        LD      A,(EditorPendingBlockMode)
        CP      1
        JP      NZ,AssertFail
        LD      A,(EditorBlockSelectionActive)
        CP      1
        JP      NZ,AssertFail
        LD      HL,EditorScreenDescriptor
        LD      A,(HL)
        CP      TECM8_DISPLAY_MARKER_COPY_SOURCE
        JP      NZ,AssertFail
        LD      HL,EditorScreenDescriptor + 3
        LD      A,(HL)
        CP      TECM8_DISPLAY_MARKER_COPY_SOURCE
        JP      NZ,AssertFail
        LD      HL,EditorScreenDescriptor + 6
        LD      A,(HL)
        CP      TECM8_DISPLAY_MARKER_COPY_SOURCE
        JP      NZ,AssertFail
        LD      HL,EditorScreenDescriptor + 9
        LD      A,(HL)
        CP      TECM8_DISPLAY_MARKER_NONE
        JP      NZ,AssertFail
        LD      HL,EditorScreenDescriptor + 12
        LD      A,(HL)
        CP      TECM8_DISPLAY_MARKER_SELECTED
        JP      NZ,AssertFail
        LD      HL,EditorScreenDescriptor + 15
        LD      A,(HL)
        CP      TECM8_DISPLAY_MARKER_NONE
        JP      NZ,AssertFail
        XOR     A
        RET

;! out A,carry,zero
;! clobbers A,HL
@AssertPendingMoveRowsZeroToTwo:
        LD      A,(EditorPendingBlockMode)
        CP      2
        JP      NZ,AssertFail
        CALL    AssertPendingSourceRowsZeroToTwo
        JP      C,AssertFail
        LD      HL,EditorScreenDescriptor
        LD      A,(HL)
        CP      TECM8_DISPLAY_MARKER_MOVE_SOURCE
        JP      NZ,AssertFail
        LD      HL,EditorScreenDescriptor + 3
        LD      A,(HL)
        CP      TECM8_DISPLAY_MARKER_MOVE_SOURCE
        JP      NZ,AssertFail
        LD      HL,EditorScreenDescriptor + 6
        LD      A,(HL)
        CP      TECM8_DISPLAY_MARKER_MOVE_SOURCE
        JP      NZ,AssertFail
        XOR     A
        RET

;! out A,carry,zero
;! clobbers A
@AssertCursorRenderedAtRowTwo:
        LD      A,(EditorCursorRendered)
        CP      1
        JP      NZ,AssertFail
        LD      A,(EditorCursorRenderedRow)
        CP      3
        JP      NZ,AssertFail
        LD      A,(EditorCursorRenderedCol)
        OR      A
        JP      NZ,AssertFail
        XOR     A
        RET

;! out A,carry,zero
;! clobbers A
@AssertPendingSourceRowsZeroToTwo:
        LD      A,(EditorPendingBlockStartLo)
        OR      A
        JP      NZ,AssertFail
        LD      A,(EditorPendingBlockStartHi)
        OR      A
        JP      NZ,AssertFail
        LD      A,(EditorPendingBlockEndLo)
        CP      2
        JP      NZ,AssertFail
        LD      A,(EditorPendingBlockEndHi)
        OR      A
        JP      NZ,AssertFail
        XOR     A
        RET

;! out A,carry,zero
;! clobbers A,BC,DE,HL
@AssertCopyPasteInsertRows:
        LD      A,(EditorPendingBlockMode)
        OR      A
        JP      NZ,AssertFail
        LD      A,(EditorBlockSelectionActive)
        CP      1
        JP      NZ,AssertFail
        LD      A,(EditorBlockSelectionAnchorLo)
        CP      5
        JP      NZ,AssertFail
        LD      A,(EditorBlockSelectionActiveLo)
        CP      7
        JP      NZ,AssertFail
        LD      A,(EditorCursorRow)
        CP      7
        JP      NZ,AssertFail
        XOR     A
        RET

;! out A,carry,zero
;! clobbers A,BC,DE,HL
@AssertPasteNoopPendingCopyRowsZeroToOne:
        LD      A,(EditorPendingBlockMode)
        CP      1
        JP      NZ,AssertFail
        LD      A,(EditorPendingBlockStartLo)
        OR      A
        JP      NZ,AssertFail
        LD      A,(EditorPendingBlockEndLo)
        CP      1
        JP      NZ,AssertFail
        LD      A,(EditorBlockSelectionActive)
        OR      A
        JP      NZ,AssertFail
        XOR     A
        RET

;! out A,carry,zero
;! clobbers A,BC,DE,HL
@AssertMovePasteInsertRows:
        LD      A,(EditorPendingBlockMode)
        OR      A
        JP      NZ,AssertFail
        LD      A,(EditorBlockSelectionActive)
        CP      1
        JP      NZ,AssertFail
        LD      A,(EditorBlockSelectionAnchorLo)
        CP      3
        JP      NZ,AssertFail
        LD      A,(EditorBlockSelectionActiveLo)
        CP      5
        JP      NZ,AssertFail
        LD      A,(EditorCursorRow)
        CP      5
        JP      NZ,AssertFail
        XOR     A
        RET

;! out A,carry,zero
;! clobbers A,BC,DE,HL
@AssertCopyPasteReplaceRows:
        LD      A,(EditorPendingBlockMode)
        OR      A
        JP      NZ,AssertFail
        LD      A,(EditorBlockSelectionActive)
        CP      1
        JP      NZ,AssertFail
        LD      A,(EditorBlockSelectionAnchorLo)
        CP      4
        JP      NZ,AssertFail
        LD      A,(EditorBlockSelectionActiveLo)
        CP      6
        JP      NZ,AssertFail
        LD      A,(EditorCursorRow)
        CP      6
        JP      NZ,AssertFail
        XOR     A
        RET

;! out A,carry,zero
;! clobbers A,BC,DE,HL
@AssertMovePasteReplaceRows:
        LD      A,(EditorPendingBlockMode)
        OR      A
        JP      NZ,AssertFail
        LD      A,(EditorBlockSelectionActive)
        CP      1
        JP      NZ,AssertFail
        LD      A,(EditorBlockSelectionAnchorLo)
        CP      2
        JP      NZ,AssertFail
        LD      A,(EditorBlockSelectionActiveLo)
        CP      4
        JP      NZ,AssertFail
        LD      A,(EditorCursorRow)
        CP      4
        JP      NZ,AssertFail
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

PlainDownCount:
        .db     0

        .include "../../src/glcd-tile.asm"
        .include "../../src/display-model.asm"
        .include "../../src/editor-block-state.asm"
        .include "../../src/editor-viewport.asm"
        .include "../../src/tecm8-string.asm"
        .include "../../src/tecm8-storage.asm"
        .include "../../src/editor-storage-loader.asm"
        .include "../../src/editor-navigation.asm"
        .include "../../src/tecm8-record.asm"
        .include "../../src/editor-interaction.asm"
        .include "../../src/editor-record.asm"
        .include "../../src/editor-line-edit.asm"
        .include "../../src/editor-block.asm"
        .include "../../src/editor-keymap.asm"
        .include "../../src/editor-cursor.asm"
        .include "../../src/editor-prompt.asm"
        .include "../../src/editor-render.asm"
        .include "../../src/shell-commands.asm"
        .include "../../src/shell-editor-launch.asm"
        .include "../../src/tecm8-bios.asm"
