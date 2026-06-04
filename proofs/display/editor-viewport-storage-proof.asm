; Storage-backed editor viewport proof.
;
; Opens FAT32 VOLUME.TM8 through MON3, loads two /src/main.asm source-record
; pages, and renders them through the editor viewport/display model.

        .org    0x4000

ProofPass       .equ     0x42
ProofFail       .equ     0xE0

;!      out       carry,zero
;!      clobbers  A,BC,DE,HL
@Start:
        CALL    TECM8_DISPLAY_INIT
        JR      C,ProofFailed

        XOR     A
        LD      HL,EditorSourcePage0
        CALL    TECM8_EDITOR_LOAD_MAIN_SOURCE_PAGE
        JR      C,ProofFailed

        LD      HL,EditorSourcePage0
        CALL    TECM8_EDITOR_VIEWPORT_RENDER
        JR      C,ProofFailed

        LD      A,1
        LD      HL,EditorSourcePage1
        CALL    TECM8_EDITOR_LOAD_MAIN_SOURCE_PAGE
        JR      C,ProofFailed

        LD      HL,EditorSourcePage1
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
        .include "../../src/editor-storage-loader.asm"
        .include "../../src/tecm8-bios.asm"

ResultMarker:
        .db     0

EditorSourcePage0:
        .ds     512

EditorSourcePage1:
        .ds     512
