; Editor viewport display proof.
;
; Converts eight fixed 32-byte source records into a structured GLCD screen.

        .org    0x4000

ProofPass       .equ     0x42
ProofFail       .equ     0xE0

;!      out       carry,zero
;!      clobbers  A,BC,DE,HL
@Start:
        CALL    TECM8_DISPLAY_INIT
        JR      C,ProofFailed

        LD      HL,EditorSourceRecords
        CALL    TECM8_EDITOR_VIEWPORT_RENDER
        JR      C,ProofFailed

        CALL    TECM8_BIOS_DISPLAY_UPDATE
        JR      C,ProofFailed

        LD      A,ProofPass
        LD      (ResultMarker),A

ProofDone:
        JP      ProofDone

ProofFailed:
        OR      ProofFail
        LD      (ResultMarker),A

ProofFailedDone:
        JP      ProofDone

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

ResultMarker:
        .db     0
