; Editor page write-back proof.
;
; Opens /src/main.asm, mutates the loaded 512-byte page buffer, saves it back to
; VOLUME.TM8, then reloads the page so the host runner can verify persisted TM8
; source records from the FAT32 image.

        .org    0x4000

PROOF_PASS       .equ     0x42
PROOF_FAIL       .equ     0xE0

;!      out       carry,zero
;!      clobbers  A,BC,DE,HL
@Start:
        CALL    DisplayInit
        JR      C,ProofFailed

        CALL    EditorOpenMain
        JR      C,ProofFailed

        LD      HL,EditorPageWriteKeys
        CALL    EditorRunKeys
        JR      C,ProofFailed

        CALL    EditorSaveCurrentPage
        JR      C,ProofFailed

        CALL    EditorRenderCurrent
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

        .include "../../src/display-model.asm"
        .include "../../src/editor-viewport.asm"
        .include "../../src/editor-storage-loader.asm"
        .include "../../src/editor-navigation.asm"
        .include "../../src/editor-interaction.asm"
        .include "../../src/tecm8-bios.asm"

EditorPageWriteKeys:
        .db     9,"OK",0

ResultMarker:
        .db     0
