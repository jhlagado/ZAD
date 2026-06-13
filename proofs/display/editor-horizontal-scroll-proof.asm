; Editor horizontal scroll proof.
;
; Opens /src/main.asm, fills one source record to its 31-character limit, and
; verifies that the 20-column GLCD text viewport pans to show columns 11-30.

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
        CALL    EditorKeyCurrentRecord
        CALL    EditorKeyClearRecord
        CALL    EditorRenderPageBuffer
        JP      C,ProofFailed

        LD      A,4
        LD      (CaseMarker),A
        LD      HL,LongLineKeys
        CALL    EditorRunKeys
        JP      C,ProofFailed

        LD      A,(EditorCursorCol)
        LD      (CursorColAfterInsert),A
        LD      A,(EditorCursorVisibleCol)
        LD      (VisibleColAfterInsert),A
        LD      A,(EditorViewportColOffset)
        LD      (ColOffsetAfterInsert),A
        LD      A,(EditorNavDirty)
        LD      (DirtyAfterInsert),A
        LD      HL,EditorRowText0
        LD      DE,VisibleRowText0
        CALL    CopyRowText

        LD      A,5
        LD      (CaseMarker),A
        CALL    EditorKeyCurrentRecord
        CALL    EditorKeyClearRecord
        CALL    EditorCursorReset
        JP      C,ProofFailed
        LD      HL,ShortLinePanKeys
        CALL    EditorRunKeys
        JP      C,ProofFailed

        LD      A,(EditorCursorCol)
        LD      (ShortCursorColBeforeBackspace),A
        LD      A,(EditorCursorVisibleCol)
        LD      (ShortVisibleColBeforeBackspace),A
        LD      A,(EditorViewportColOffset)
        LD      (ShortColOffsetBeforeBackspace),A
        LD      HL,BackspaceKey
        CALL    EditorRunKeys
        JP      C,ProofFailed

        LD      A,(EditorCursorCol)
        LD      (ShortCursorColAfterBackspace),A
        LD      A,(EditorCursorVisibleCol)
        LD      (ShortVisibleColAfterBackspace),A
        LD      A,(EditorViewportColOffset)
        LD      (ShortColOffsetAfterBackspace),A

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
        .include "../../src/editor-storage-loader.asm"
        .include "../../src/editor-navigation.asm"
        .include "../../src/tecm8-record.asm"
        .include "../../src/editor-interaction.asm"
        .include "../../src/tecm8-bios.asm"

LongLineKeys:
        .db     "ABCDEFGHIJKLMNOPQRSTUVWXYZ12345",0
ShortLinePanKeys:
        .db     "ABCDE"
        .db     TECM8_EDITOR_KEY_ARROW_RIGHT,TECM8_EDITOR_KEY_ARROW_RIGHT
        .db     TECM8_EDITOR_KEY_ARROW_RIGHT,TECM8_EDITOR_KEY_ARROW_RIGHT
        .db     TECM8_EDITOR_KEY_ARROW_RIGHT,TECM8_EDITOR_KEY_ARROW_RIGHT
        .db     TECM8_EDITOR_KEY_ARROW_RIGHT,TECM8_EDITOR_KEY_ARROW_RIGHT
        .db     TECM8_EDITOR_KEY_ARROW_RIGHT,TECM8_EDITOR_KEY_ARROW_RIGHT
        .db     TECM8_EDITOR_KEY_ARROW_RIGHT,TECM8_EDITOR_KEY_ARROW_RIGHT
        .db     TECM8_EDITOR_KEY_ARROW_RIGHT,TECM8_EDITOR_KEY_ARROW_RIGHT
        .db     TECM8_EDITOR_KEY_ARROW_RIGHT,TECM8_EDITOR_KEY_ARROW_RIGHT
        .db     TECM8_EDITOR_KEY_ARROW_RIGHT,TECM8_EDITOR_KEY_ARROW_RIGHT
        .db     TECM8_EDITOR_KEY_ARROW_RIGHT,TECM8_EDITOR_KEY_ARROW_RIGHT
        .db     TECM8_EDITOR_KEY_ARROW_RIGHT,TECM8_EDITOR_KEY_ARROW_RIGHT
        .db     TECM8_EDITOR_KEY_ARROW_RIGHT,TECM8_EDITOR_KEY_ARROW_RIGHT
        .db     TECM8_EDITOR_KEY_ARROW_RIGHT,0
BackspaceKey:
        .db     TECM8_EDITOR_KEY_BACKSPACE,0

ResultMarker:
        .db     0
CaseMarker:
        .db     0
ErrorMarker:
        .db     0
CursorColAfterInsert:
        .db     0
VisibleColAfterInsert:
        .db     0
ColOffsetAfterInsert:
        .db     0
DirtyAfterInsert:
        .db     0
ShortCursorColBeforeBackspace:
        .db     0
ShortVisibleColBeforeBackspace:
        .db     0
ShortColOffsetBeforeBackspace:
        .db     0
ShortCursorColAfterBackspace:
        .db     0
ShortVisibleColAfterBackspace:
        .db     0
ShortColOffsetAfterBackspace:
        .db     0
VisibleRowText0:
        .ds     32
