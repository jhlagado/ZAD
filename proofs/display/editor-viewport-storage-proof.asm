; Storage-backed editor viewport proof.
;
; Opens FAT32 VOLUME.TM8 through MON3, loads /src/main.asm source records,
; and renders them through the editor viewport/display model.

        .org    0x4000

ProofPass       .equ     0x42
ProofFail       .equ     0xE0

;!      out       carry,zero
;!      clobbers  A,BC,DE,HL
@Start:
        CALL    TECM8_DISPLAY_INIT
        JR      C,ProofFailed

        LD      HL,EditorSourceSector
        CALL    TECM8_EDITOR_LOAD_MAIN_SOURCE_SECTOR
        JR      C,ProofFailed

        LD      HL,EditorSourceSector
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

EditorSourceSector:
        .ds     512
