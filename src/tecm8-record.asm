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

; Tecm8RecordShiftTextRight -
; Shift B text bytes right by one byte inside a source record.
; Input: HL = record base, C = zero-based text column, B = bytes to shift
;! in B,C,HL
;! out A,carry,zero
;! clobbers sign,parity,halfCarry,BC,DE,HL
@Tecm8RecordShiftTextRight:
        LD      A,B
        OR      A
        JR      Z,Tecm8RecordShiftTextRightDone
        LD      D,0
        LD      E,C
        ADD     HL,DE
        LD      D,0
        LD      E,B
        ADD     HL,DE
        LD      D,H
        LD      E,L
        INC     DE

Tecm8RecordShiftTextRightLoop:
        LD      A,(HL)
        LD      (DE),A
        DEC     HL
        DEC     DE
        DJNZ    Tecm8RecordShiftTextRightLoop

Tecm8RecordShiftTextRightDone:
        XOR     A
        RET

; Tecm8RecordShiftTextLeft -
; Shift B text bytes left by one byte inside a source record.
; Input: HL = record base, C = zero-based text column, B = bytes to shift
;! in B,C,HL
;! out A,carry,zero
;! clobbers sign,parity,halfCarry,BC,DE,HL
@Tecm8RecordShiftTextLeft:
        LD      A,B
        OR      A
        JR      Z,Tecm8RecordShiftTextLeftDone
        INC     HL
        LD      D,0
        LD      E,C
        ADD     HL,DE
        LD      D,H
        LD      E,L
        INC     HL

Tecm8RecordShiftTextLeftLoop:
        LD      A,(HL)
        LD      (DE),A
        INC     HL
        INC     DE
        DJNZ    Tecm8RecordShiftTextLeftLoop

Tecm8RecordShiftTextLeftDone:
        XOR     A
        RET

; Tecm8RecordShiftRecordsDown -
; Copy A records from high source to high destination, moving backward.
; Input: A = record count, HL = highest source record, DE = highest destination
;! in A,DE,HL
;! out A,carry,zero
;! clobbers sign,parity,halfCarry,BC,DE,HL
@Tecm8RecordShiftRecordsDown:
        OR      A
        JR      Z,Tecm8RecordShiftRecordsDownDone

Tecm8RecordShiftRecordsDownLoop:
        PUSH    AF
        LD      BC,TECM8_SOURCE_RECORD_BYTES
        LDIR
        LD      BC,0 - (TECM8_SOURCE_RECORD_BYTES * 2)
        ADD     HL,BC
        EX      DE,HL
        ADD     HL,BC
        EX      DE,HL
        POP     AF
        DEC     A
        JR      NZ,Tecm8RecordShiftRecordsDownLoop

Tecm8RecordShiftRecordsDownDone:
        XOR     A
        RET

; Tecm8RecordShiftRecordsUp -
; Copy A records from low source to low destination, moving forward.
; Input: A = record count, HL = lowest source record, DE = lowest destination
;! in A,DE,HL
;! out A,carry,zero
;! clobbers sign,parity,halfCarry,BC,DE,HL
@Tecm8RecordShiftRecordsUp:
        OR      A
        JR      Z,Tecm8RecordShiftRecordsUpDone

Tecm8RecordShiftRecordsUpLoop:
        PUSH    AF
        LD      BC,TECM8_SOURCE_RECORD_BYTES
        LDIR
        POP     AF
        DEC     A
        JR      NZ,Tecm8RecordShiftRecordsUpLoop

Tecm8RecordShiftRecordsUpDone:
        XOR     A
        RET
