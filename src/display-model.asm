; TECM8 structured display model.
;
; This first layer renders editor-style screens through the MON3-backed
; TECM8_BIOS_DISPLAY_* wrappers. It is a display proof surface, not an editor.

TECM8_DISPLAY_GLCD_COLUMNS          .equ    20
TECM8_DISPLAY_GLCD_ROWS             .equ    10
TECM8_DISPLAY_EDIT_ROWS             .equ    8
TECM8_DISPLAY_GUTTER_PIXELS         .equ    4
TECM8_DISPLAY_TEXT_X                .equ    6
TECM8_DISPLAY_TOP_ROW               .equ    0
TECM8_DISPLAY_FIRST_EDIT_ROW        .equ    1
TECM8_DISPLAY_BOTTOM_ROW            .equ    9
TECM8_DISPLAY_ROW_HEIGHT            .equ    6
TECM8_DISPLAY_ROW_BYTES             .equ    16
TECM8_DISPLAY_ROW_STRIDE            .equ    TECM8_DISPLAY_ROW_HEIGHT * TECM8_DISPLAY_ROW_BYTES
TECM8_DISPLAY_GUTTER_ROWS           .equ    TECM8_DISPLAY_ROW_HEIGHT
TECM8_DISPLAY_MAX_TEXT_CHARS        .equ    20
TECM8_DISPLAY_MARKER_NONE           .equ    0
TECM8_DISPLAY_MARKER_BREAKPOINT     .equ    1
TECM8_DISPLAY_MARKER_CURRENT        .equ    2
TECM8_DISPLAY_MARKER_SELECTED       .equ    4
TECM8_DISPLAY_CURSOR_PATTERN        .equ    0x80

MON3_TGBUF                          .equ    0x13C0

; TECM8_DISPLAY_INIT -
; Initialize and clear the current display.
;!      out       carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@TECM8_DISPLAY_INIT:
        CALL    TECM8_BIOS_DISPLAY_INIT
        RET     C
        CALL    TECM8_BIOS_DISPLAY_CLEAR
        RET

; TECM8_DISPLAY_RENDER_SCREEN -
; Render a fixed structured screen descriptor.
; Input: HL = descriptor:
;        dw top text
;        eight records of db marker, dw source text
;        dw bottom text
;!      in        HL
;!      out       carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@TECM8_DISPLAY_RENDER_SCREEN:
        LD      (DisplayCursor),HL
        CALL    TECM8_BIOS_DISPLAY_CLEAR
        RET     C
        LD      HL,(DisplayCursor)
        LD      E,(HL)
        INC     HL
        LD      D,(HL)
        INC     HL
        LD      (DisplayCursor),HL
        LD      H,D
        LD      L,E
        LD      A,TECM8_DISPLAY_TOP_ROW
        LD      C,TECM8_DISPLAY_MARKER_NONE
        CALL    TECM8_DISPLAY_RENDER_LINE
        RET     C

        LD      A,TECM8_DISPLAY_EDIT_ROWS
        LD      (DisplayRemaining),A
        LD      A,TECM8_DISPLAY_FIRST_EDIT_ROW
        LD      (DisplayRow),A

DisplayScreenLoop:
        LD      HL,(DisplayCursor)
        LD      C,(HL)
        INC     HL
        LD      E,(HL)
        INC     HL
        LD      D,(HL)
        INC     HL
        LD      (DisplayCursor),HL
        LD      H,D
        LD      L,E
        LD      A,(DisplayRow)
        CALL    TECM8_DISPLAY_RENDER_LINE
        RET     C
        LD      A,(DisplayRow)
        INC     A
        LD      (DisplayRow),A
        LD      A,(DisplayRemaining)
        DEC     A
        LD      (DisplayRemaining),A
        JR      NZ,DisplayScreenLoop

        LD      HL,(DisplayCursor)
        LD      E,(HL)
        INC     HL
        LD      D,(HL)
        LD      H,D
        LD      L,E
        LD      A,TECM8_DISPLAY_BOTTOM_ROW
        LD      C,TECM8_DISPLAY_MARKER_NONE
        CALL    TECM8_DISPLAY_RENDER_LINE
        RET

; TECM8_DISPLAY_RENDER_LINE -
; Render one screen row with gutter marker and text.
; Input: A = display row, C = marker flags, HL = NUL-terminated text
;!      in        A,C,HL
;!      out       carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@TECM8_DISPLAY_RENDER_LINE:
        LD      (DisplayText),HL
        LD      (DisplayRow),A
        CALL    TECM8_DISPLAY_RENDER_GUTTER
        RET     C
        LD      A,(DisplayRow)
        CALL    DisplayRowToPixel
        LD      A,C
        LD      (DisplayTextY),A
        LD      A,TECM8_DISPLAY_TEXT_X
        LD      (DisplayTextX),A
        LD      A,TECM8_DISPLAY_MAX_TEXT_CHARS
        LD      (DisplayTextRemaining),A

DisplayTextLoop:
        LD      HL,(DisplayText)
        LD      A,(HL)
        OR      A
        RET     Z
        INC     HL
        LD      (DisplayText),HL
        LD      D,A
        LD      A,(DisplayTextY)
        LD      C,A
        LD      A,(DisplayTextX)
        LD      B,A
        LD      A,D
        CALL    TECM8_BIOS_DISPLAY_DRAW_CHAR_AT
        RET     C
        LD      A,(DisplayTextX)
        ADD     A,TECM8_DISPLAY_ROW_HEIGHT
        LD      (DisplayTextX),A
        LD      A,(DisplayTextRemaining)
        DEC     A
        LD      (DisplayTextRemaining),A
        JR      NZ,DisplayTextLoop
        XOR     A
        RET

; TECM8_DISPLAY_RENDER_GUTTER -
; Draw a 4-pixel marker in the left gutter for one display row.
; Input: A = display row, C = marker flags
;!      in        A,C
;!      out       carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@TECM8_DISPLAY_RENDER_GUTTER:
        LD      (DisplayRow),A
        LD      A,C
        OR      A
        JR      NZ,DisplayGutterHasMarker
        XOR     A
        JR      DisplayGutterPatternReady

DisplayGutterHasMarker:
        BIT     0,C
        JR      Z,DisplayGutterCheckCurrent
        LD      A,0xF0
        JR      DisplayGutterPatternReady

DisplayGutterCheckCurrent:
        BIT     1,C
        JR      Z,DisplayGutterCheckSelected
        LD      A,0x80
        JR      DisplayGutterPatternReady

DisplayGutterCheckSelected:
        LD      A,0xC0

DisplayGutterPatternReady:
        LD      (DisplayPattern),A
        LD      A,(DisplayRow)
        LD      HL,MON3_TGBUF
        LD      DE,TECM8_DISPLAY_ROW_STRIDE
        OR      A
        JR      Z,DisplayGutterWriteRows

DisplayGutterOffsetLoop:
        ADD     HL,DE
        DEC     A
        JR      NZ,DisplayGutterOffsetLoop

DisplayGutterWriteRows:
        LD      B,TECM8_DISPLAY_GUTTER_ROWS
        LD      DE,TECM8_DISPLAY_ROW_BYTES

DisplayGutterWriteLoop:
        LD      A,(HL)
        AND     0x0F
        LD      C,A
        LD      A,(DisplayPattern)
        OR      C
        LD      (HL),A
        ADD     HL,DE
        DJNZ    DisplayGutterWriteLoop
        XOR     A
        RET

; TECM8_DISPLAY_RENDER_CURSOR_CELL -
; Overlay a vertical cursor bit for one visible edit-pane cell.
; Input: A = edit row (0-7), C = text column (0-19)
;!      in        A,C
;!      out       carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@TECM8_DISPLAY_RENDER_CURSOR_CELL:
        CP      TECM8_DISPLAY_EDIT_ROWS
        JR      NC,DisplayCursorNoop
        LD      (DisplayCursorCellRow),A
        LD      A,C
        CP      TECM8_DISPLAY_MAX_TEXT_CHARS
        JR      NC,DisplayCursorNoop
        LD      (DisplayCursorCellCol),A

        LD      A,(DisplayCursorCellRow)
        ADD     A,TECM8_DISPLAY_FIRST_EDIT_ROW
        LD      HL,MON3_TGBUF
        LD      DE,TECM8_DISPLAY_ROW_STRIDE

DisplayCursorRowOffsetLoop:
        ADD     HL,DE
        DEC     A
        JR      NZ,DisplayCursorRowOffsetLoop

        LD      A,TECM8_DISPLAY_TEXT_X
        LD      (DisplayCursorPixelX),A
        LD      A,(DisplayCursorCellCol)
        LD      B,A
        OR      A
        JR      Z,DisplayCursorPixelReady

DisplayCursorPixelLoop:
        LD      A,(DisplayCursorPixelX)
        ADD     A,TECM8_DISPLAY_ROW_HEIGHT
        LD      (DisplayCursorPixelX),A
        DJNZ    DisplayCursorPixelLoop

DisplayCursorPixelReady:
        LD      A,(DisplayCursorPixelX)
        LD      B,0

DisplayCursorByteLoop:
        CP      8
        JR      C,DisplayCursorByteReady
        SUB     8
        INC     B
        JR      DisplayCursorByteLoop

DisplayCursorByteReady:
        LD      (DisplayCursorBitIndex),A
        LD      A,B
        OR      A
        JR      Z,DisplayCursorByteOffsetReady

DisplayCursorByteOffsetLoop:
        INC     HL
        DJNZ    DisplayCursorByteOffsetLoop

DisplayCursorByteOffsetReady:
        LD      A,(DisplayCursorBitIndex)
        LD      B,A
        LD      A,TECM8_DISPLAY_CURSOR_PATTERN
        LD      C,A
        LD      A,B
        OR      A
        JR      Z,DisplayCursorMaskReady
        LD      A,C

DisplayCursorMaskLoop:
        SRL     A
        DJNZ    DisplayCursorMaskLoop
        LD      C,A

DisplayCursorMaskReady:
        LD      B,TECM8_DISPLAY_ROW_HEIGHT
        LD      DE,TECM8_DISPLAY_ROW_BYTES

DisplayCursorWriteLoop:
        LD      A,(HL)
        OR      C
        LD      (HL),A
        ADD     HL,DE
        DJNZ    DisplayCursorWriteLoop
        CALL    TECM8_BIOS_DISPLAY_UPDATE
        RET

DisplayCursorNoop:
        XOR     A
        RET

; DisplayRowToPixel -
; Convert a 0-9 display row to a Y pixel coordinate.
; Input: A = row
; Output: C = row * 6
;!      in        A
;!      out       C,zero
;!      clobbers  A
@DisplayRowToPixel:
        LD      C,A
        ADD     A,A
        ADD     A,C
        ADD     A,A
        LD      C,A
        RET

DisplayCursor:
        .dw     0
DisplayText:
        .dw     0
DisplayRow:
        .db     0
DisplayRemaining:
        .db     0
DisplayPattern:
        .db     0
DisplayTextX:
        .db     0
DisplayTextY:
        .db     0
DisplayTextRemaining:
        .db     0
DisplayCursorCellRow:
        .db     0
DisplayCursorCellCol:
        .db     0
DisplayCursorPixelX:
        .db     0
DisplayCursorBitIndex:
        .db     0
