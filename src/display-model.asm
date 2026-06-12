; TECM8 structured display model.
;
; This layer renders editor-style screens through TECM8-owned GLCD tile writes.
; It is a display proof surface, not an editor.

TECM8_DISPLAY_GLCD_COLUMNS          .equ    20
TECM8_DISPLAY_GLCD_ROWS             .equ    10
TECM8_DISPLAY_EDIT_ROWS             .equ    10
TECM8_DISPLAY_GUTTER_PIXELS         .equ    4
TECM8_DISPLAY_TEXT_X                .equ    6
TECM8_DISPLAY_Y_ORIGIN              .equ    2
TECM8_DISPLAY_STATUS_ROW            .equ    9
TECM8_DISPLAY_ROW_HEIGHT            .equ    6
TECM8_DISPLAY_ROW_BYTES             .equ    16
TECM8_DISPLAY_Y_ORIGIN_BYTES        .equ    TECM8_DISPLAY_Y_ORIGIN * TECM8_DISPLAY_ROW_BYTES
TECM8_DISPLAY_ROW_STRIDE            .equ    TECM8_DISPLAY_ROW_HEIGHT * TECM8_DISPLAY_ROW_BYTES
TECM8_DISPLAY_GUTTER_ROWS           .equ    TECM8_DISPLAY_ROW_HEIGHT
TECM8_DISPLAY_MAX_TEXT_CHARS        .equ    20
TECM8_DISPLAY_MARKER_NONE           .equ    0
TECM8_DISPLAY_MARKER_BREAKPOINT     .equ    1
TECM8_DISPLAY_MARKER_CURRENT        .equ    2
TECM8_DISPLAY_MARKER_SELECTED       .equ    4
TECM8_DISPLAY_CURSOR_SAVED_BYTES    .equ    TECM8_DISPLAY_ROW_HEIGHT * 2

MON3_TGBUF                          .equ    0x13C0

; DisplayInit -
; Initialize and clear the current display.
;!      out       carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@DisplayInit:
        CALL    BiosDisplayInit
        RET     C
        CALL    BiosDisplayClear
        RET

; DisplayRenderScreen -
; Render a fixed structured screen descriptor.
; Input: HL = descriptor:
;        ten records of db marker, dw source text
;!      in        HL
;!      out       carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@DisplayRenderScreen:
        LD      A,(DisplayRenderScreenCount)
        INC     A
        LD      (DisplayRenderScreenCount),A
        LD      (DisplayCursor),HL

        LD      A,TECM8_DISPLAY_EDIT_ROWS
        LD      (DisplayRemaining),A
        XOR     A
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
        CALL    DisplayRenderLine
        RET     C
        LD      A,(DisplayRow)
        INC     A
        LD      (DisplayRow),A
        LD      A,(DisplayRemaining)
        DEC     A
        LD      (DisplayRemaining),A
        JR      NZ,DisplayScreenLoop
        RET

; DisplayRenderLine -
; Render one screen row with gutter marker and text.
; Input: A = display row, C = marker flags, HL = NUL-terminated text
;!      in        A,C,HL
;!      out       carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@DisplayRenderLine:
        LD      (DisplayText),HL
        LD      (DisplayRow),A
        CALL    DisplayRenderGutter
        RET     C
        LD      A,(DisplayRow)
        LD      B,A
        CALL    GlcdTileClearTextRow
        RET     C
        LD      HL,(DisplayText)
        LD      A,(DisplayRow)
        LD      B,A
        LD      C,0
        CALL    GlcdTileDrawTextRun
        RET

; DisplayRenderGutter -
; Draw a 4-pixel marker in the left gutter for one display row.
; Input: A = display row, C = marker flags
;!      in        A,C
;!      out       carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@DisplayRenderGutter:
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
        LD      DE,TECM8_DISPLAY_Y_ORIGIN_BYTES
        ADD     HL,DE
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

; DisplayRenderCursorCell -
; Overlay an inverse 6x6 cursor cell for one visible edit-pane cell.
; Input: A = edit row (0-9), C = text column (0-19)
;!      in        A,C
;!      out       carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@DisplayRenderCursorCell:
        CP      TECM8_DISPLAY_EDIT_ROWS
        JP      NC,DisplayCursorNoop
        LD      (DisplayCursorCellRow),A
        LD      A,C
        CP      TECM8_DISPLAY_MAX_TEXT_CHARS
        JP      NC,DisplayCursorNoop
        LD      (DisplayCursorCellCol),A

        LD      A,(DisplayCursorCellRow)
        LD      HL,MON3_TGBUF
        LD      DE,TECM8_DISPLAY_Y_ORIGIN_BYTES
        ADD     HL,DE
        LD      DE,TECM8_DISPLAY_ROW_STRIDE
        OR      A
        JR      Z,DisplayCursorRowReady

DisplayCursorRowOffsetLoop:
        ADD     HL,DE
        DEC     A
        JR      NZ,DisplayCursorRowOffsetLoop

DisplayCursorRowReady:
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
        LD      (DisplayCursorCellPtr),HL
        LD      A,(DisplayCursorBitIndex)
        LD      E,A
        LD      D,0
        LD      HL,DisplayCursorFirstMaskTable
        ADD     HL,DE
        LD      A,(HL)
        LD      (DisplayCursorFirstMask),A
        LD      A,(DisplayCursorBitIndex)
        LD      E,A
        LD      D,0
        LD      HL,DisplayCursorSecondMaskTable
        ADD     HL,DE
        LD      A,(HL)
        LD      (DisplayCursorSecondMask),A
        LD      B,TECM8_DISPLAY_ROW_HEIGHT
        LD      DE,TECM8_DISPLAY_ROW_BYTES
        LD      HL,DisplayCursorSavedBytes
        LD      (DisplayCursorSavePtr),HL
        LD      HL,(DisplayCursorCellPtr)

DisplayCursorWriteLoop:
        LD      A,(HL)
        LD      (DisplayCursorOriginalByte),A
        LD      (DisplayCursorCellPtr),HL
        LD      HL,(DisplayCursorSavePtr)
        LD      A,(DisplayCursorOriginalByte)
        LD      (HL),A
        INC     HL
        LD      (DisplayCursorSavePtr),HL
        LD      HL,(DisplayCursorCellPtr)
        LD      A,(DisplayCursorOriginalByte)
        LD      C,A
        LD      A,(DisplayCursorFirstMask)
        XOR     C
        LD      (HL),A
        LD      A,(DisplayCursorSecondMask)
        OR      A
        JR      Z,DisplayCursorSkipSecondWrite
        INC     HL
        LD      A,(HL)
        LD      (DisplayCursorOriginalByte),A
        LD      (DisplayCursorCellPtr),HL
        LD      HL,(DisplayCursorSavePtr)
        LD      A,(DisplayCursorOriginalByte)
        LD      (HL),A
        INC     HL
        LD      (DisplayCursorSavePtr),HL
        LD      HL,(DisplayCursorCellPtr)
        LD      A,(DisplayCursorOriginalByte)
        LD      C,A
        LD      A,(DisplayCursorSecondMask)
        XOR     C
        LD      (HL),A
        DEC     HL
        JR      DisplayCursorNextRow

DisplayCursorSkipSecondWrite:
        LD      HL,(DisplayCursorSavePtr)
        LD      (HL),0
        INC     HL
        LD      (DisplayCursorSavePtr),HL
        LD      HL,(DisplayCursorCellPtr)

DisplayCursorNextRow:
        ADD     HL,DE
        DJNZ    DisplayCursorWriteLoop
        LD      A,(DisplayCursorCellRow)
        CALL    GlcdTileMarkRowDirty
        RET

DisplayCursorNoop:
        XOR     A
        RET

; DisplayEraseCursorCell -
; Restore the bytes saved before an inverse cursor cell was overlaid.
; Input: A = edit row (0-9), C = text column (0-19)
;!      in        A,C
;!      out       carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@DisplayEraseCursorCell:
        CP      TECM8_DISPLAY_EDIT_ROWS
        JP      NC,DisplayCursorEraseNoop
        LD      (DisplayCursorCellRow),A
        LD      A,C
        CP      TECM8_DISPLAY_MAX_TEXT_CHARS
        JP      NC,DisplayCursorEraseNoop
        LD      (DisplayCursorCellCol),A

        LD      A,(DisplayCursorCellRow)
        LD      HL,MON3_TGBUF
        LD      DE,TECM8_DISPLAY_Y_ORIGIN_BYTES
        ADD     HL,DE
        LD      DE,TECM8_DISPLAY_ROW_STRIDE
        OR      A
        JR      Z,DisplayCursorEraseRowReady

DisplayCursorEraseRowOffsetLoop:
        ADD     HL,DE
        DEC     A
        JR      NZ,DisplayCursorEraseRowOffsetLoop

DisplayCursorEraseRowReady:
        LD      A,TECM8_DISPLAY_TEXT_X
        LD      (DisplayCursorPixelX),A
        LD      A,(DisplayCursorCellCol)
        LD      B,A
        OR      A
        JR      Z,DisplayCursorErasePixelReady

DisplayCursorErasePixelLoop:
        LD      A,(DisplayCursorPixelX)
        ADD     A,TECM8_DISPLAY_ROW_HEIGHT
        LD      (DisplayCursorPixelX),A
        DJNZ    DisplayCursorErasePixelLoop

DisplayCursorErasePixelReady:
        LD      A,(DisplayCursorPixelX)
        LD      B,0

DisplayCursorEraseByteLoop:
        CP      8
        JR      C,DisplayCursorEraseByteReady
        SUB     8
        INC     B
        JR      DisplayCursorEraseByteLoop

DisplayCursorEraseByteReady:
        LD      (DisplayCursorBitIndex),A
        LD      A,B
        OR      A
        JR      Z,DisplayCursorEraseByteOffsetReady

DisplayCursorEraseByteOffsetLoop:
        INC     HL
        DJNZ    DisplayCursorEraseByteOffsetLoop

DisplayCursorEraseByteOffsetReady:
        LD      (DisplayCursorCellPtr),HL
        LD      A,(DisplayCursorBitIndex)
        LD      E,A
        LD      D,0
        LD      HL,DisplayCursorSecondMaskTable
        ADD     HL,DE
        LD      A,(HL)
        LD      (DisplayCursorSecondMask),A
        LD      B,TECM8_DISPLAY_ROW_HEIGHT
        LD      DE,TECM8_DISPLAY_ROW_BYTES
        LD      HL,DisplayCursorSavedBytes
        LD      (DisplayCursorSavePtr),HL
        LD      HL,(DisplayCursorCellPtr)

DisplayCursorEraseWriteLoop:
        LD      (DisplayCursorCellPtr),HL
        LD      HL,(DisplayCursorSavePtr)
        LD      A,(HL)
        INC     HL
        LD      (DisplayCursorSavePtr),HL
        LD      HL,(DisplayCursorCellPtr)
        LD      (HL),A
        LD      A,(DisplayCursorSecondMask)
        OR      A
        JR      Z,DisplayCursorEraseSkipSecond
        INC     HL
        LD      (DisplayCursorCellPtr),HL
        LD      HL,(DisplayCursorSavePtr)
        LD      A,(HL)
        INC     HL
        LD      (DisplayCursorSavePtr),HL
        LD      HL,(DisplayCursorCellPtr)
        LD      (HL),A
        DEC     HL
        JR      DisplayCursorEraseNextRow

DisplayCursorEraseSkipSecond:
        LD      HL,(DisplayCursorSavePtr)
        INC     HL
        LD      (DisplayCursorSavePtr),HL
        LD      HL,(DisplayCursorCellPtr)

DisplayCursorEraseNextRow:
        ADD     HL,DE
        DJNZ    DisplayCursorEraseWriteLoop
        LD      A,(DisplayCursorCellRow)
        CALL    GlcdTileMarkRowDirty
        RET

DisplayCursorEraseNoop:
        XOR     A
        RET

; DisplayRowToPixel -
; Convert a 0-9 display row to a Y pixel coordinate.
; Input: A = row
; Output: C = row * 6 + TECM8_DISPLAY_Y_ORIGIN
;!      in        A
;!      out       C,zero
;!      clobbers  A
@DisplayRowToPixel:
        LD      C,A
        ADD     A,A
        ADD     A,C
        ADD     A,A
        ADD     A,TECM8_DISPLAY_Y_ORIGIN
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
DisplayCursorCellPtr:
        .dw     0
DisplayCursorSavePtr:
        .dw     0
DisplayCursorOriginalByte:
        .db     0
DisplayCursorFirstMask:
        .db     0
DisplayCursorSecondMask:
        .db     0
DisplayCursorSavedBytes:
        .ds     TECM8_DISPLAY_CURSOR_SAVED_BYTES

DisplayCursorFirstMaskTable:
        .db     0xFC,0x7E,0x3F,0x1F,0x0F,0x07,0x03,0x01
DisplayCursorSecondMaskTable:
        .db     0x00,0x00,0x00,0x80,0xC0,0xE0,0xF0,0xF8
DisplayRenderScreenCount:
        .db     0
