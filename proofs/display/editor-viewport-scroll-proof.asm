; Editor viewport scroll proof.
;
; Opens /src/main.asm, moves the logical cursor through all 16 records of the
; first source page, and verifies that the 10-row GLCD viewport scrolls to show
; rows 6-15 without changing dirty state.

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

        .include "../../src/glcd-tile.asm"
        .include "../../src/display-model.asm"
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
CursorRowAfterUp:
        .db     0
VisibleRowAfterUp:
        .db     0
TopRowAfterUp:
        .db     0
DirtyAfterUp:
        .db     0
