; Project config parser proof.
;
; Assembled by tools/run-project-config-proof.ts, then run in the Debug80 Z80
; runtime. The proof succeeds when ResultMarker is PROOF_PASS and MainPathOut is
; "/src/main.asm".

        .org    0x4000

        .include "../../src/tecm8-equates.asm"

PROOF_PASS       .equ     0x42
PROOF_FAIL       .equ     0xE0
MAIN_PATH_OUT_LEN  .equ     64

;!      out       carry,zero
;!      clobbers  A,BC,DE,HL
@Start:
        LD      HL,GoodProjectConfig
        LD      DE,MainPathOut
        LD      B,MAIN_PATH_OUT_LEN
        CALL    ParseProjectConfig
        JR      C,ProofFailed

        LD      HL,ExpectedMainPath
        LD      DE,MainPathOut
        CALL    AssertString
        JR      C,ProofFailed

        LD      A,PROOF_PASS
        LD      (ResultMarker),A
        HALT

ProofFailed:
        OR      PROOF_FAIL
        LD      (ResultMarker),A
        HALT

; AssertString —
; Compare two NUL-terminated strings.
; Input: HL = expected, DE = actual
; Output: carry clear on match, carry set on mismatch
;!      in        DE,HL
;!      out       DE,HL,A,carry,zero
@AssertString:
        LD      A,(DE)
        CP      (HL)
        JR      NZ,AssertStringBad
        OR      A
        RET     Z
        INC     DE
        INC     HL
        JR      AssertString

AssertStringBad:
        SCF
        RET

        .include "../../src/project-config.asm"

GoodProjectConfig:
        .db     "tm8project=1",0x0A
        .db     "main=/src/main.asm",0x0A
        .db     0

ExpectedMainPath:
        .db     "/src/main.asm",0

ResultMarker:
        .db     0

MainPathOut:
        .ds     MAIN_PATH_OUT_LEN
