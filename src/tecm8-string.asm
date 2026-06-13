; Shared byte/string helpers for TECM8 storage and shell code.

; Tecm8StringMatchBytes -
; Compare B bytes from DE against HL.
; Output: carry clear on match, carry set on mismatch.
;! in B,DE,HL
;! out A,carry,zero
;! clobbers sign,parity,halfCarry,B,DE,HL
@Tecm8StringMatchBytes:
        LD      A,(DE)
        CP      (HL)
        JR      NZ,Tecm8StringMatchBytesBad
        INC     DE
        INC     HL
        DJNZ    Tecm8StringMatchBytes
        XOR     A
        RET

Tecm8StringMatchBytesBad:
        SCF
        RET
