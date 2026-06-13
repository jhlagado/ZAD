; TECM8 fixed source-record helpers.
;
; Source records are 32-byte Pascal-style records: byte 0 stores a 5-bit text
; length and 3 metadata bits, followed by up to 31 text bytes.

; Tecm8RecordReadLength -
; Read the effective text length from a source record.
;! in HL
;! out A
;! clobbers F
@Tecm8RecordReadLength:
        LD      A,(HL)
        AND     TECM8_SOURCE_RECORD_LENGTH_MASK
        RET

; Tecm8RecordWriteLength -
; Write the effective text length while preserving metadata bits.
;! in A,HL
;! out A,carry,zero
;! clobbers sign,parity,halfCarry,B
@Tecm8RecordWriteLength:
        AND     TECM8_SOURCE_RECORD_LENGTH_MASK
        LD      B,A
        LD      A,(HL)
        AND     TECM8_SOURCE_RECORD_METADATA_MASK
        OR      B
        LD      (HL),A
        XOR     A
        RET

; Tecm8RecordZeroPadding -
; Zero text bytes after a record's effective text length.
; Input: A = effective text length, HL = record base
;! in A,HL
;! out A,carry,zero
;! clobbers sign,parity,halfCarry,BC,DE,HL
@Tecm8RecordZeroPadding:
        LD      C,A
        LD      A,TECM8_SOURCE_RECORD_TEXT_MAX
        SUB     C
        JR      Z,Tecm8RecordZeroPaddingDone
        LD      B,A
        INC     HL
        LD      D,0
        LD      E,C
        ADD     HL,DE
        XOR     A

Tecm8RecordZeroPaddingLoop:
        LD      (HL),A
        INC     HL
        DJNZ    Tecm8RecordZeroPaddingLoop

Tecm8RecordZeroPaddingDone:
        XOR     A
        RET

; Tecm8RecordClear -
; Clear a full 32-byte source record.
;! in HL
;! out A,carry,zero
;! clobbers sign,parity,halfCarry,B,HL
@Tecm8RecordClear:
        LD      B,TECM8_SOURCE_RECORD_BYTES
        XOR     A

Tecm8RecordClearLoop:
        LD      (HL),A
        INC     HL
        DJNZ    Tecm8RecordClearLoop
        XOR     A
        RET
