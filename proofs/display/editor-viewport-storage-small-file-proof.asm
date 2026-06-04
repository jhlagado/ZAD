; Storage-backed editor small-file proof.
;
; Proves page 1 is rejected when /src/main.asm is too small for its visible
; 256-byte record window.

        .org    0x4000

ProofPass       .equ     0x42
ProofFail       .equ     0xE0

;!      out       carry,zero
;!      clobbers  A,BC,DE,HL
@Start:
        LD      A,1
        LD      HL,EditorSourcePage
        CALL    TECM8_EDITOR_LOAD_MAIN_SOURCE_PAGE
        JR      NC,ProofFailed
        CP      EDITOR_LOAD_ERR_SIZE
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

        .include "../../src/editor-storage-loader.asm"
        .include "../../src/tecm8-bios.asm"

ResultMarker:
        .db     0

EditorSourcePage:
        .ds     512
