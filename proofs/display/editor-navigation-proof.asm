; Storage-backed editor navigation proof.
;
; Opens /src/main.asm, pages down into the second TM8 allocation block,
; pages back up once, and leaves rendered row text/state for host checks.

        .org    0x4000

ProofPass       .equ     0x42
ProofFail       .equ     0xE0

;!      out       carry,zero
;!      clobbers  A,BC,DE,HL
@Start:
        CALL    TECM8_DISPLAY_INIT
        JR      C,ProofFailed

        CALL    TECM8_EDITOR_OPEN_MAIN
        JR      C,ProofFailed

        LD      BC,8 * 256

ProofPageDownLoop:
        PUSH    BC
        CALL    TECM8_EDITOR_PAGE_DOWN
        POP     BC
        JR      C,ProofFailed
        DJNZ    ProofPageDownLoop

        CALL    TECM8_EDITOR_PAGE_UP
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
        .include "../../src/editor-storage-loader.asm"
        .include "../../src/editor-navigation.asm"
        .include "../../src/tecm8-bios.asm"

ResultMarker:
        .db     0
