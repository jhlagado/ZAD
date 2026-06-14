; Editor viewport scroll proof.
;
; Opens /src/main.asm, moves the logical cursor through all 16 records of the
; first source page, verifies that the 10-row GLCD viewport scrolls to show
; rows 6-15 without changing dirty state, then proves plain Up/Down crosses the
; resident adjacent source page as one continuous document.

        .org    0x4000

        .include "../../src/tecm8-equates.asm"

PROOF_PASS       .equ     0x42
PROOF_FAIL       .equ     0xE0

;! out carry,zero
;! clobbers A,BC,DE,HL
@Start:
        LD      A,1
        LD      (CaseMarker),A
        CALL    DisplayInit
        JP      C,ProofFailed

        LD      A,2
        LD      (CaseMarker),A
        CALL    EditorOpenMain
        JP      C,ProofFailed

        LD      A,3
        LD      (CaseMarker),A
        LD      HL,MoveDownToBottom
        CALL    EditorRunKeys
        JP      C,ProofFailed

        LD      A,(EditorCursorRow)
        LD      (CursorRowAfterDown),A
        LD      A,(EditorCursorVisibleRow)
        LD      (VisibleRowAfterDown),A
        LD      A,(EditorNavViewportTopRow)
        LD      (TopRowAfterDown),A
        LD      A,(EditorNavDirty)
        LD      (DirtyAfterDown),A
        LD      HL,EditorRowText0
        LD      DE,BottomRowText0
        CALL    CopyRowText
        LD      HL,EditorRowText9
        LD      DE,BottomRowText9
        CALL    CopyRowText

        LD      A,4
        LD      (CaseMarker),A
        LD      HL,MoveDownAcrossPage
        CALL    EditorRunKeys
        JP      C,ProofFailed

        LD      A,(EditorNavCurrentPage)
        LD      (PageAfterCrossDown),A
        LD      A,(EditorCursorRow)
        LD      (CursorRowAfterCrossDown),A
        LD      A,(EditorCursorVisibleRow)
        LD      (VisibleRowAfterCrossDown),A
        LD      A,(EditorNavViewportTopRow)
        LD      (TopRowAfterCrossDown),A
        LD      A,(EditorNavNextPageValid)
        LD      (NextPageValidAfterCrossDown),A
        LD      A,(EditorNavNextPageSynthetic)
        LD      (NextPageSyntheticAfterCrossDown),A
        LD      HL,EditorRowText0
        LD      DE,CrossDownRowText0
        CALL    CopyRowText
        LD      HL,EditorRowText8
        LD      DE,CrossDownRowText8
        CALL    CopyRowText
        LD      HL,EditorRowText9
        LD      DE,CrossDownRowText9
        CALL    CopyRowText

        LD      A,5
        LD      (CaseMarker),A
        CALL    RunSyntheticControlArrowUp
        JP      C,ProofFailed
        LD      A,(EditorNavCurrentPage)
        LD      (PageAfterMixedCtrlUp),A
        LD      A,(EditorCursorRow)
        LD      (CursorRowAfterMixedCtrlUp),A
        LD      A,(EditorNavViewportTopRow)
        LD      (TopRowAfterMixedCtrlUp),A
        LD      HL,EditorRowText0
        LD      DE,MixedCtrlUpRowText0
        CALL    CopyRowText

        LD      A,6
        LD      (CaseMarker),A
        LD      HL,MoveDownToBottom
        CALL    EditorRunKeys
        JP      C,ProofFailed
        LD      HL,MoveDownAcrossPage
        CALL    EditorRunKeys
        JP      C,ProofFailed

        LD      A,7
        LD      (CaseMarker),A
        LD      A,1
        LD      (EditorNavNextPageValid),A
        XOR     A
        LD      (EditorNavNextPageSynthetic),A
        LD      A,(EditorNavDirtySectors)
        OR      2
        LD      (EditorNavDirtySectors),A
        CALL    EditorNavRefreshAggregateDirty
        LD      A,1
        LD      (EditorNavNextPageBuffer),A
        LD      A,"!"
        LD      (EditorNavNextPageBuffer + 1),A
        LD      HL,MoveUpAcrossPage
        CALL    EditorRunKeys
        JP      C,ProofFailed
        LD      A,(EditorNavCurrentPage)
        LD      (PageAfterDirtyNextCrossUp),A
        LD      A,(EditorCursorRow)
        LD      (CursorRowAfterDirtyNextCrossUp),A
        LD      A,(EditorNavDirtySectors)
        LD      (DirtySectorsAfterDirtyNextCrossUp),A
        LD      A,(EditorNavNextPageBuffer + 1)
        LD      (NextPageMarkerAfterDirtyNextCrossUp),A
        CALL    RunSyntheticControlArrowUp
        JP      C,ProofFailed
        LD      A,(EditorNavCurrentPage)
        LD      (PageAfterDirtyNextCtrlUp),A
        LD      A,(EditorCursorRow)
        LD      (CursorRowAfterDirtyNextCtrlUp),A
        LD      A,(EditorNavDirtySectors)
        LD      (DirtySectorsAfterDirtyNextCtrlUp),A
        LD      A,(EditorNavNextPageBuffer + 1)
        LD      (NextPageMarkerAfterDirtyNextCtrlUp),A
        LD      A,(EditorNavDirtySectors)
        AND     0xFD
        LD      (EditorNavDirtySectors),A
        CALL    EditorNavRefreshAggregateDirty
        XOR     A
        LD      (EditorNavNextPageValid),A
        LD      (EditorNavNextPageSynthetic),A

        LD      A,8
        LD      (CaseMarker),A
        LD      HL,MoveUpAcrossPage
        CALL    EditorRunKeys
        JP      C,ProofFailed

        LD      A,(EditorNavCurrentPage)
        LD      (PageAfterCrossUp),A
        LD      A,(EditorCursorRow)
        LD      (CursorRowAfterCrossUp),A
        LD      A,(EditorCursorVisibleRow)
        LD      (VisibleRowAfterCrossUp),A
        LD      A,(EditorNavViewportTopRow)
        LD      (TopRowAfterCrossUp),A
        LD      HL,EditorRowText0
        LD      DE,CrossUpRowText0
        CALL    CopyRowText
        LD      HL,EditorRowText9
        LD      DE,CrossUpRowText9
        CALL    CopyRowText

        LD      A,9
        LD      (CaseMarker),A
        LD      HL,MoveDownAcrossPage
        CALL    EditorRunKeys
        JP      C,ProofFailed

        LD      A,(EditorNavCurrentPage)
        LD      (PageAfterSecondCrossDown),A
        LD      A,(EditorCursorRow)
        LD      (CursorRowAfterSecondCrossDown),A
        LD      A,(EditorCursorVisibleRow)
        LD      (VisibleRowAfterSecondCrossDown),A
        LD      A,(EditorNavViewportTopRow)
        LD      (TopRowAfterSecondCrossDown),A
        LD      HL,EditorRowText0
        LD      DE,SecondCrossDownRowText0
        CALL    CopyRowText

        LD      A,10
        LD      (CaseMarker),A
        LD      HL,MoveUpAcrossPage
        CALL    EditorRunKeys
        JP      C,ProofFailed

        LD      A,11
        LD      (CaseMarker),A
        LD      HL,MoveUpToTop
        CALL    EditorRunKeys
        JP      C,ProofFailed

        LD      A,(EditorCursorRow)
        LD      (CursorRowAfterUp),A
        LD      A,(EditorCursorVisibleRow)
        LD      (VisibleRowAfterUp),A
        LD      A,(EditorNavViewportTopRow)
        LD      (TopRowAfterUp),A
        LD      A,(EditorNavDirty)
        LD      (DirtyAfterUp),A

        LD      A,12
        LD      (CaseMarker),A
        LD      HL,MoveDownToBottom
        CALL    EditorRunKeys
        JP      C,ProofFailed
        LD      HL,MoveDownAcrossPage
        CALL    EditorRunKeys
        JP      C,ProofFailed
        CALL    RunSyntheticControlArrowDown
        JP      C,ProofFailed
        LD      A,(EditorNavCurrentPage)
        LD      (PageAfterMixedCtrlDown),A
        LD      A,(EditorCursorRow)
        LD      (CursorRowAfterMixedCtrlDown),A
        LD      A,(EditorNavViewportTopRow)
        LD      (TopRowAfterMixedCtrlDown),A
        LD      HL,EditorRowText0
        LD      DE,MixedCtrlDownRowText0
        CALL    CopyRowText

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

;! in DE,HL
;! out A,DE,HL,carry,zero
;! clobbers A,BC
@CopyRowText:
        LD      B,32

CopyRowTextLoop:
        LD      A,(HL)
        LD      (DE),A
        INC     HL
        INC     DE
        OR      A
        RET     Z
        DJNZ    CopyRowTextLoop
        XOR     A
        RET

;! out A,carry
;! clobbers A,BC,DE,HL,zero,sign,parity,halfCarry
@RunSyntheticControlArrowUp:
        LD      A,TECM8_EDITOR_KEY_ARROW_UP
        LD      (BiosInputRawPrimary),A
        LD      A,0x01
        LD      (BiosInputRawSecondary),A
        LD      A,TECM8_EDITOR_KEY_ARROW_UP
        LD      B,TECM8_EDITOR_KEY_MOD_CTRL
        CALL    EditorRunModifiedKey
        JR      C,RunSyntheticControlArrowUpErr
        LD      A,0xFF
        LD      (BiosInputRawPrimary),A
        LD      (BiosInputRawSecondary),A
        XOR     A
        RET

RunSyntheticControlArrowUpErr:
        LD      C,A
        LD      A,0xFF
        LD      (BiosInputRawPrimary),A
        LD      (BiosInputRawSecondary),A
        LD      A,C
        SCF
        RET

;! out A,carry
;! clobbers A,BC,DE,HL,zero,sign,parity,halfCarry
@RunSyntheticControlArrowDown:
        LD      A,TECM8_EDITOR_KEY_ARROW_DOWN
        LD      (BiosInputRawPrimary),A
        LD      A,0x01
        LD      (BiosInputRawSecondary),A
        LD      A,TECM8_EDITOR_KEY_ARROW_DOWN
        LD      B,TECM8_EDITOR_KEY_MOD_CTRL
        CALL    EditorRunModifiedKey
        JR      C,RunSyntheticControlArrowDownErr
        LD      A,0xFF
        LD      (BiosInputRawPrimary),A
        LD      (BiosInputRawSecondary),A
        XOR     A
        RET

RunSyntheticControlArrowDownErr:
        LD      C,A
        LD      A,0xFF
        LD      (BiosInputRawPrimary),A
        LD      (BiosInputRawSecondary),A
        LD      A,C
        SCF
        RET

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
        .include "../../src/tecm8-bios.asm"

MoveDownToBottom:
        .db     TECM8_EDITOR_KEY_ARROW_DOWN,TECM8_EDITOR_KEY_ARROW_DOWN
        .db     TECM8_EDITOR_KEY_ARROW_DOWN,TECM8_EDITOR_KEY_ARROW_DOWN
        .db     TECM8_EDITOR_KEY_ARROW_DOWN,TECM8_EDITOR_KEY_ARROW_DOWN
        .db     TECM8_EDITOR_KEY_ARROW_DOWN,TECM8_EDITOR_KEY_ARROW_DOWN
        .db     TECM8_EDITOR_KEY_ARROW_DOWN,TECM8_EDITOR_KEY_ARROW_DOWN
        .db     TECM8_EDITOR_KEY_ARROW_DOWN,TECM8_EDITOR_KEY_ARROW_DOWN
        .db     TECM8_EDITOR_KEY_ARROW_DOWN,TECM8_EDITOR_KEY_ARROW_DOWN
        .db     TECM8_EDITOR_KEY_ARROW_DOWN,0

MoveUpToTop:
        .db     TECM8_EDITOR_KEY_ARROW_UP,TECM8_EDITOR_KEY_ARROW_UP
        .db     TECM8_EDITOR_KEY_ARROW_UP,TECM8_EDITOR_KEY_ARROW_UP
        .db     TECM8_EDITOR_KEY_ARROW_UP,TECM8_EDITOR_KEY_ARROW_UP
        .db     TECM8_EDITOR_KEY_ARROW_UP,TECM8_EDITOR_KEY_ARROW_UP
        .db     TECM8_EDITOR_KEY_ARROW_UP,TECM8_EDITOR_KEY_ARROW_UP
        .db     TECM8_EDITOR_KEY_ARROW_UP,TECM8_EDITOR_KEY_ARROW_UP
        .db     TECM8_EDITOR_KEY_ARROW_UP,TECM8_EDITOR_KEY_ARROW_UP
        .db     TECM8_EDITOR_KEY_ARROW_UP,0

MoveDownAcrossPage:
        .db     TECM8_EDITOR_KEY_ARROW_DOWN,0

MoveUpAcrossPage:
        .db     TECM8_EDITOR_KEY_ARROW_UP,0

ResultMarker:
        .db     0
CaseMarker:
        .db     0
ErrorMarker:
        .db     0
CursorRowAfterDown:
        .db     0
VisibleRowAfterDown:
        .db     0
TopRowAfterDown:
        .db     0
DirtyAfterDown:
        .db     0
BottomRowText0:
        .ds     32
BottomRowText9:
        .ds     32
PageAfterCrossDown:
        .db     0
CursorRowAfterCrossDown:
        .db     0
VisibleRowAfterCrossDown:
        .db     0
TopRowAfterCrossDown:
        .db     0
NextPageValidAfterCrossDown:
        .db     0
NextPageSyntheticAfterCrossDown:
        .db     0
CrossDownRowText0:
        .ds     32
CrossDownRowText8:
        .ds     32
CrossDownRowText9:
        .ds     32
PageAfterMixedCtrlUp:
        .db     0
CursorRowAfterMixedCtrlUp:
        .db     0
TopRowAfterMixedCtrlUp:
        .db     0
MixedCtrlUpRowText0:
        .ds     32
PageAfterDirtyNextCrossUp:
        .db     0
CursorRowAfterDirtyNextCrossUp:
        .db     0
DirtySectorsAfterDirtyNextCrossUp:
        .db     0
NextPageMarkerAfterDirtyNextCrossUp:
        .db     0
PageAfterDirtyNextCtrlUp:
        .db     0
CursorRowAfterDirtyNextCtrlUp:
        .db     0
DirtySectorsAfterDirtyNextCtrlUp:
        .db     0
NextPageMarkerAfterDirtyNextCtrlUp:
        .db     0
PageAfterCrossUp:
        .db     0
CursorRowAfterCrossUp:
        .db     0
VisibleRowAfterCrossUp:
        .db     0
TopRowAfterCrossUp:
        .db     0
CrossUpRowText0:
        .ds     32
CrossUpRowText9:
        .ds     32
PageAfterSecondCrossDown:
        .db     0
CursorRowAfterSecondCrossDown:
        .db     0
VisibleRowAfterSecondCrossDown:
        .db     0
TopRowAfterSecondCrossDown:
        .db     0
SecondCrossDownRowText0:
        .ds     32
CursorRowAfterUp:
        .db     0
VisibleRowAfterUp:
        .db     0
TopRowAfterUp:
        .db     0
DirtyAfterUp:
        .db     0
PageAfterMixedCtrlDown:
        .db     0
CursorRowAfterMixedCtrlDown:
        .db     0
TopRowAfterMixedCtrlDown:
        .db     0
MixedCtrlDownRowText0:
        .ds     32
