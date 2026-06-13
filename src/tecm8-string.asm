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

; Tecm8StringFindLocalName -
; Return HL pointing at the byte after the last slash in a NUL-terminated path.
; If no slash is present, HL returns to the original input pointer.
;! in HL
;! out HL,A,carry,zero
;! clobbers sign,parity,halfCarry,DE
@Tecm8StringFindLocalName:
        LD      D,H
        LD      E,L

Tecm8StringFindLocalNameLoop:
        LD      A,(HL)
        OR      A
        JR      Z,Tecm8StringFindLocalNameDone
        CP      "/"
        JR      NZ,Tecm8StringFindLocalNameNext
        INC     HL
        LD      D,H
        LD      E,L
        JR      Tecm8StringFindLocalNameLoop

Tecm8StringFindLocalNameNext:
        INC     HL
        JR      Tecm8StringFindLocalNameLoop

Tecm8StringFindLocalNameDone:
        LD      H,D
        LD      L,E
        RET
