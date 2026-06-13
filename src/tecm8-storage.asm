; TECM8 shared TM8 storage helpers.
;
; These routines hold format-level helpers that are shared by the project
; loader, editor storage loader, and future shell/filesystem paths.

; Tecm8StorageBlockToOffset —
; Convert a 4K TM8 block number in HL to MON3 HLDE byte offset.
;! in HL
;! out DE,HL
;! clobbers A,F
@Tecm8StorageBlockToOffset:
        LD      A,L
        AND     0x0F
        RLCA
        RLCA
        RLCA
        RLCA
        LD      D,A
        LD      E,0

        LD      A,H
        RRCA
        RRCA
        RRCA
        RRCA
        AND     0xF0
        LD      H,A
        LD      A,L
        RRCA
        RRCA
        RRCA
        RRCA
        AND     0x0F
        OR      H
        LD      L,A
        LD      H,0
        RET
