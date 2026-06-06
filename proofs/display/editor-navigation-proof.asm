; Storage-backed editor navigation proof.
;
; Opens /src/main.asm, pages down into the second TM8 allocation block,
; pages back up once, proves dirty key-stream paging does not discard the
; current page buffer, and leaves rendered row text/state for host checks.

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

        LD      BC,8 * 256

ProofPageDownLoop:
        PUSH    BC
        CALL    EditorPageDown
        POP     BC
        JR      C,ProofFailed
        DJNZ    ProofPageDownLoop

        CALL    EditorPageUp
        JR      C,ProofFailed

        LD      A,1
        LD      (EditorNavDirty),A
        LD      A,TECM8_EDITOR_KEY_ARROW_DOWN
        LD      B,TECM8_EDITOR_KEY_MOD_CTRL
        CALL    EditorRunModifiedKey
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
        .include "../../src/editor-storage-loader.asm"
        .include "../../src/editor-navigation.asm"
        .include "../../src/editor-interaction.asm"
        .include "../../src/tecm8-bios.asm"

ResultMarker:
        .db     0
