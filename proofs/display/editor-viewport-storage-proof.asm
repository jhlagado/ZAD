; Storage-backed editor viewport proof.
;
; Opens FAT32 VOLUME.TM8 through MON3, loads source-record pages from the
; first and second allocated TM8 blocks, and renders them through the editor
; viewport/display model.

        .org    0x4000

        .include "../../src/tecm8-equates.asm"

PROOF_PASS       .equ     0x42
PROOF_FAIL       .equ     0xE0

;! out carry,zero
;! clobbers A,BC,DE,HL
@Start:
        CALL    DisplayInit
        JR      C,ProofFailed

        XOR     A
        LD      HL,EditorSourcePage0
        CALL    EditorLoadMainPage
        JR      C,ProofFailed

        LD      HL,EditorSourcePage0
        CALL    EditorViewportRender
        JR      C,ProofFailed

        LD      A,1
        LD      HL,EditorSourcePage1
        CALL    EditorLoadMainPage
        JR      C,ProofFailed

        LD      HL,EditorSourcePage1
        CALL    EditorViewportRender
        JR      C,ProofFailed

        LD      A,8
        LD      HL,EditorSourcePage8
        CALL    EditorLoadMainPage
        JR      C,ProofFailed

        LD      HL,EditorSourcePage8
        CALL    EditorViewportRender
        JR      C,ProofFailed

        CALL    GlcdTileFlushFull
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
        .include "../../src/tecm8-string.asm"
        .include "../../src/editor-storage-loader.asm"
        .include "../../src/tecm8-bios.asm"

ResultMarker:
        .db     0

EditorSourcePage0:
        .ds     512

EditorSourcePage1:
        .ds     512

EditorSourcePage8:
        .ds     512
