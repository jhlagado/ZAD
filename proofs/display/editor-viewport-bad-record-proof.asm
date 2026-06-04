; Editor viewport malformed-record proof.
;
; Verifies that a source record length >= 32 is rejected before display update.

        .org    0x4000

ProofPass       .equ     0x42
ProofFail       .equ     0xE0

;!      out       carry,zero
;!      clobbers  A,BC,DE,HL
@Start:
        CALL    TECM8_DISPLAY_INIT
        JR      C,ProofFailed

        LD      HL,BadEditorSourceRecords
        CALL    TECM8_EDITOR_VIEWPORT_RENDER
        JR      NC,ProofFailed
        CP      TECM8_EDITOR_ERR_RECORD_LENGTH
        JR      NZ,ProofFailed

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

BadEditorSourceRecords:
        .db     32
        .ds     31

ResultMarker:
        .db     0
