; Proof for shared TECM8 string helpers.

        .org    0x4000

PROOF_PASS      .equ    0x42
PROOF_FAIL      .equ    0xE0

;! out carry,zero
;! clobbers sign,parity,halfCarry,A,BC,DE,HL
@Start:
        CALL    AssertCopyZeroCapacity
        JR      C,ProofFailed
        CALL    AssertCopyExactFit
        JR      C,ProofFailed
        CALL    AssertCopyOverflow
        JR      C,ProofFailed
        LD      A,PROOF_PASS
        LD      (ResultMarker),A
        HALT

ProofFailed:
        OR      PROOF_FAIL
        LD      (ResultMarker),A
        HALT

        .include "../../src/tecm8-string.asm"

;! out A,carry,zero
;! clobbers sign,parity,halfCarry,B,DE,HL
@AssertCopyZeroCapacity:
        LD      A,1
        LD      (CopyCaseMarker),A
        LD      HL,CopySourceShort
        LD      DE,CopyDest
        LD      B,0
        CALL    Tecm8StringCopyNulBounded
        JR      NC,CopyFail
        XOR     A
        RET

;! out A,carry,zero
;! clobbers sign,parity,halfCarry,B,C,DE,HL
@AssertCopyExactFit:
        LD      A,2
        LD      (CopyCaseMarker),A
        LD      HL,CopySourceShort
        LD      DE,CopyDest
        LD      B,3
        CALL    Tecm8StringCopyNulBounded
        JR      C,CopyFail
        LD      A,B
        CP      1
        JR      NZ,CopyFail
        LD      HL,CopyDest
        LD      DE,CopySourceShort
        LD      B,3
        CALL    Tecm8StringMatchBytes
        JR      C,CopyFail
        XOR     A
        RET

;! out A,carry,zero
;! clobbers sign,parity,halfCarry,B,DE,HL
@AssertCopyOverflow:
        LD      A,3
        LD      (CopyCaseMarker),A
        LD      HL,CopySourceShort
        LD      DE,CopyDest
        LD      B,2
        CALL    Tecm8StringCopyNulBounded
        JR      NC,CopyFail
        XOR     A
        RET

CopyFail:
        LD      A,(CopyCaseMarker)
        SCF
        RET

CopySourceShort:
        .db     "AB",0

CopyDest:
        .ds     4

ResultMarker:
        .db     0

CopyCaseMarker:
        .db     0
