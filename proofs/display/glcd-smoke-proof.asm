; GLCD display smoke proof.
;
; Runs under Debug80's TEC-1G runtime with MON3 loaded. The proof initializes
; the MON3-backed TECM8 display wrappers and writes a short visible string.

        .org    0x4000

PROOF_PASS       .equ     0x42
PROOF_FAIL       .equ     0xE0
MON3_TGBUF       .equ     0x13C0

;!      out       carry,zero
;!      clobbers  A,BC,DE,HL
@Start:
        CALL    BiosDisplayInit
        JR      C,ProofFailed

        CALL    BiosDisplayClear
        JR      C,ProofFailed

        LD      B,0
        LD      C,0
        CALL    BiosDisplaySetCursor
        JR      C,ProofFailed

        LD      A,'>'
        CALL    BiosDisplayPutChar
        JR      C,ProofFailed

        LD      HL,SmokeText
        CALL    BiosDisplayPutString
        JR      C,ProofFailed

        CALL    BiosDisplaySetBitmapMode
        JR      C,ProofFailed

        LD      A,0xFF
        LD      (MON3_TGBUF),A

        CALL    BiosDisplayUpdate
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

        .include "../../src/tecm8-bios.asm"

SmokeText:
        .db     "TECM8",0

ResultMarker:
        .db     0
