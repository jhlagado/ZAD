; Storage-backed editor invalid-page proof.
;
; Proves page index 128 is rejected before storage reads are attempted.

        .org    0x4000

        .include "../../src/tecm8-equates.asm"

PROOF_PASS       .equ     0x42
PROOF_FAIL       .equ     0xE0

;! out carry,zero
;! clobbers A,BC,DE,HL
@Start:
        LD      A,128
        LD      HL,EditorSourcePage
        CALL    EditorLoadMainPage
        JR      NC,ProofFailed
        CP      EDITOR_LOAD_ERR_PAGE
        JR      NZ,ProofFailed

        LD      A,PROOF_PASS
        LD      (ResultMarker),A

ProofDone:
        JP      ProofDone

ProofFailed:
        OR      PROOF_FAIL
        LD      (ResultMarker),A

ProofFailedDone:
        JP      ProofDone

        .include "../../src/tecm8-string.asm"
        .include "../../src/editor-storage-loader.asm"
        .include "../../src/tecm8-bios.asm"

ResultMarker:
        .db     0

EditorSourcePage:
        .ds     512
