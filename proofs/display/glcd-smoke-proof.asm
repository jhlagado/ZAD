; GLCD display smoke proof.
;
; Runs under Debug80's TEC-1G runtime with MON3 loaded. The proof initializes
; the MON3-backed TECM8 display wrappers and writes a short visible string.

        .org    0x4000

ProofPass       .equ     0x42
ProofFail       .equ     0xE0
Mon3Tgbuf       .equ     0x13C0

;!      out       carry,zero
;!      clobbers  A,BC,DE,HL
@Start:
        CALL    TECM8_BIOS_DISPLAY_INIT
        JR      C,ProofFailed

        CALL    TECM8_BIOS_DISPLAY_CLEAR
        JR      C,ProofFailed

        LD      B,0
        LD      C,0
        CALL    TECM8_BIOS_DISPLAY_SET_CURSOR
        JR      C,ProofFailed

        LD      A,'>'
        CALL    TECM8_BIOS_DISPLAY_PUT_CHAR
        JR      C,ProofFailed

        LD      HL,SmokeText
        CALL    TECM8_BIOS_DISPLAY_PUT_STRING
        JR      C,ProofFailed

        CALL    TECM8_BIOS_DISPLAY_SET_BITMAP_MODE
        JR      C,ProofFailed

        LD      A,0xFF
        LD      (Mon3Tgbuf),A

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

        .include "../../src/tecm8-bios.asm"

SmokeText:
        .db     "TECM8",0

ResultMarker:
        .db     0
