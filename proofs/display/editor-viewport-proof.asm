; Editor viewport display proof.
;
; Converts ten fixed 32-byte source records into a structured GLCD screen.

        .org    0x4000

PROOF_PASS       .equ     0x42
PROOF_FAIL       .equ     0xE0

;!      out       carry,zero
;!      clobbers  A,BC,DE,HL
@Start:
        CALL    DisplayInit
        JR      C,ProofFailed

        LD      HL,EditorSourceRecords
        CALL    EditorViewportRender
        JR      C,ProofFailed

        CALL    GlcdTileFlushFull
        JR      C,ProofFailed

        LD      A,TECM8_DISPLAY_STATUS_ROW
        CALL    EditorViewportSetCurrentRow
        JR      C,ProofFailed

        LD      HL,EditorSourceRecords
        CALL    EditorViewportRender
        JR      C,ProofFailed

        LD      HL,ProofStatusText
        LD      (EditorPromptTextPtr),HL
        CALL    EditorViewportRenderStatusOverlay
        JR      C,ProofFailed

        CALL    EditorViewportRestoreStatusRow
        JR      C,ProofFailed

        LD      A,PROOF_PASS
        LD      (ResultMarker),A

ProofDone:
        JP      ProofDone

ProofFailed:
        OR      PROOF_FAIL
        LD      (ResultMarker),A

ProofFailedDone:
        JP      ProofDone

        .include "../../src/glcd-tile.asm"
        .include "../../src/display-model.asm"
        .include "../../src/editor-viewport.asm"
        .include "../../src/tecm8-bios.asm"

EditorSourceRecords:
        .db     9,"ORG 4000H"
        .ds     22
        .db     9,"CALL INIT"
        .ds     22
        .db     9,"LD HL,MSG"
        .ds     22
        .db     10,"CALL PRINT"
        .ds     21
        .db     7,"JP DONE"
        .ds     24
        .db     11,"MSG DB 'OK'"
        .ds     20
        .db     5,"DONE:"
        .ds     26
        .db     3,"RET"
        .ds     28
        .db     3,"NOP"
        .ds     28
        .db     3,"END"
        .ds     28

ResultMarker:
        .db     0

ProofStatusText:
        .db     "Saving...",0
