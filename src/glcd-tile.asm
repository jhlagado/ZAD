; TECM8 GLCD tile-cell primitives.
;
; This layer writes 6x6 text cells directly into MON3's TGBUF bitmap. It may
; still use MON3 for full-screen flushes, but it does not call MON3's terminal
; glyph policy.

TECM8_GLCD_TILE_COLUMNS             .equ    20
TECM8_GLCD_TILE_ROWS                .equ    10
TECM8_GLCD_TILE_WIDTH               .equ    6
TECM8_GLCD_TILE_HEIGHT              .equ    6
TECM8_GLCD_TILE_TEXT_X              .equ    6
TECM8_GLCD_TILE_Y_ORIGIN            .equ    2
TECM8_GLCD_TILE_ROW_BYTES           .equ    16
TECM8_GLCD_TILE_ROW_STRIDE          .equ    TECM8_GLCD_TILE_HEIGHT * TECM8_GLCD_TILE_ROW_BYTES
TECM8_GLCD_TILE_TGBUF               .equ    0x13C0
TECM8_GLCD_TILE_VPORT               .equ    0x0E13
TECM8_GLCD_TILE_FONT_DATA           .equ    0xDD9B
TECM8_GLCD_TILE_PORT_CMD            .equ    0x07
TECM8_GLCD_TILE_PORT_DATA           .equ    0x87
TECM8_GLCD_TILE_SET_ADDR            .equ    0x80
TECM8_GLCD_TILE_LOWER_BANK          .equ    0x08
TECM8_GLCD_TILE_ROW_BANK            .equ    32
TECM8_GLCD_TILE_DELAY_COUNT         .equ    0x0010
TECM8_GLCD_TILE_ERR_RANGE           .equ    0x01

; GlcdTileClearCell -
; Clear one 6x6 text cell in the GLCD backing bitmap.
; Input: B = row (0-9), C = column (0-19)
;!      in        B,C
;!      out       carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@GlcdTileClearCell:
        CALL    GlcdTilePrepareCell
        RET     C
        LD      C,0
        LD      B,TECM8_GLCD_TILE_HEIGHT

GlcdTileClearRowLoop:
        PUSH    BC
        LD      HL,(GlcdTileRowPtr)
        LD      A,(GlcdTileStartBit)
        LD      D,A
        LD      B,TECM8_GLCD_TILE_WIDTH

GlcdTileClearPixelLoop:
        LD      A,D
        LD      (GlcdTileBitIndex),A
        PUSH    HL
        LD      HL,GlcdTileClearMaskTable
        LD      D,0
        LD      E,A
        ADD     HL,DE
        LD      A,(HL)
        POP     HL
        AND     (HL)
        LD      (HL),A
        LD      A,(GlcdTileBitIndex)
        INC     A
        LD      D,A
        CP      8
        JR      C,GlcdTileClearPixelNext
        LD      D,0
        INC     HL

GlcdTileClearPixelNext:
        DJNZ    GlcdTileClearPixelLoop
        LD      HL,(GlcdTileRowPtr)
        LD      DE,TECM8_GLCD_TILE_ROW_BYTES
        ADD     HL,DE
        LD      (GlcdTileRowPtr),HL
        POP     BC
        DJNZ    GlcdTileClearRowLoop
        XOR     A
        RET

; GlcdTileDrawCell -
; Overwrite one 6x6 text cell with a MON3 font glyph.
; Input: A = ASCII/codepoint, B = row (0-9), C = column (0-19)
;!      in        A,B,C
;!      out       carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@GlcdTileDrawCell:
        LD      (GlcdTileGlyphCode),A
        CALL    GlcdTileClearCell
        RET     C
        LD      C,0
        LD      A,(GlcdTileGlyphCode)
        OR      A
        RET     Z
        DEC     A
        LD      H,0
        LD      L,A
        ADD     HL,HL
        LD      D,H
        LD      E,L
        ADD     HL,HL
        ADD     HL,DE
        LD      DE,TECM8_GLCD_TILE_FONT_DATA
        ADD     HL,DE
        LD      (GlcdTileGlyphPtr),HL
        LD      HL,(GlcdTileCellPtr)
        LD      (GlcdTileRowPtr),HL
        LD      B,TECM8_GLCD_TILE_HEIGHT

GlcdTileDrawRowLoop:
        PUSH    BC
        LD      HL,(GlcdTileGlyphPtr)
        LD      A,(HL)
        INC     HL
        LD      (GlcdTileGlyphPtr),HL
        AND     0x3F
        ADD     A,A
        ADD     A,A
        LD      E,A
        LD      HL,(GlcdTileRowPtr)
        LD      A,(GlcdTileStartBit)
        LD      D,A
        LD      B,TECM8_GLCD_TILE_WIDTH

GlcdTileDrawPixelLoop:
        SLA     E
        JR      NC,GlcdTileDrawPixelSkip
        LD      A,D
        LD      (GlcdTileBitIndex),A
        PUSH    DE
        PUSH    HL
        LD      HL,GlcdTileSetMaskTable
        LD      D,0
        LD      E,A
        ADD     HL,DE
        LD      A,(HL)
        POP     HL
        POP     DE
        OR      (HL)
        LD      (HL),A

GlcdTileDrawPixelSkip:
        LD      A,D
        INC     A
        LD      D,A
        CP      8
        JR      C,GlcdTileDrawPixelNext
        LD      D,0
        INC     HL

GlcdTileDrawPixelNext:
        DJNZ    GlcdTileDrawPixelLoop
        LD      HL,(GlcdTileRowPtr)
        LD      DE,TECM8_GLCD_TILE_ROW_BYTES
        ADD     HL,DE
        LD      (GlcdTileRowPtr),HL
        POP     BC
        DJNZ    GlcdTileDrawRowLoop
        XOR     A
        RET

; GlcdTileDrawTextRun -
; Draw a NUL-terminated string starting at one cell. Stops at screen edge.
; Input: HL = text, B = row (0-9), C = start column (0-19)
;!      in        B,C,HL
;!      out       carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@GlcdTileDrawTextRun:
        LD      (GlcdTileTextPtr),HL
        LD      A,B
        LD      (GlcdTileTextRow),A
        LD      A,C
        LD      (GlcdTileTextColumn),A

GlcdTileTextRunLoop:
        LD      A,(GlcdTileTextColumn)
        CP      TECM8_GLCD_TILE_COLUMNS
        JR      NC,GlcdTileTextRunDone
        LD      HL,(GlcdTileTextPtr)
        LD      A,(HL)
        OR      A
        JR      Z,GlcdTileTextRunDone
        INC     HL
        LD      (GlcdTileTextPtr),HL
        LD      B,A
        LD      A,(GlcdTileTextRow)
        LD      D,A
        LD      A,(GlcdTileTextColumn)
        LD      C,A
        LD      A,B
        LD      B,D
        CALL    GlcdTileDrawCell
        RET     C
        LD      A,(GlcdTileTextColumn)
        INC     A
        LD      (GlcdTileTextColumn),A
        JR      GlcdTileTextRunLoop

GlcdTileTextRunDone:
        XOR     A
        RET

; GlcdTileClearTextRow -
; Clear all 20 text cells on one display row.
; Input: B = row (0-9)
;!      in        B
;!      out       carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@GlcdTileClearTextRow:
        LD      A,B
        CP      TECM8_GLCD_TILE_ROWS
        JP      NC,GlcdTileRangeError
        LD      (GlcdTileTextRow),A
        XOR     A
        LD      (GlcdTileTextColumn),A

GlcdTileClearTextRowLoop:
        LD      A,(GlcdTileTextColumn)
        CP      TECM8_GLCD_TILE_COLUMNS
        JR      NC,GlcdTileClearTextRowDone
        LD      C,A
        LD      A,(GlcdTileTextRow)
        LD      B,A
        CALL    GlcdTileClearCell
        RET     C
        LD      A,(GlcdTileTextColumn)
        INC     A
        LD      (GlcdTileTextColumn),A
        JR      GlcdTileClearTextRowLoop

GlcdTileClearTextRowDone:
        XOR     A
        RET

; GlcdTileFlushFull -
; Push the current GLCD backing bitmap through the active BIOS display backend.
;!      out       carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@GlcdTileFlushFull:
        LD      A,(GlcdTileFlushFullCount)
        INC     A
        LD      (GlcdTileFlushFullCount),A
        LD      HL,TECM8_GLCD_TILE_TGBUF
        LD      (TECM8_GLCD_TILE_VPORT),HL
        CALL    BiosDisplayUpdate
        RET

; GlcdTileFlushRow -
; Push one dirty 6-pixel text row directly to the ST7920 graphic buffer.
; Input: A = row (0-9)
;!      in        A
;!      out       carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@GlcdTileFlushRow:
        CP      TECM8_GLCD_TILE_ROWS
        JP      NC,GlcdTileRangeError
        LD      (GlcdTileFlushRowLast),A
        LD      A,(GlcdTileFlushRowCount)
        INC     A
        LD      (GlcdTileFlushRowCount),A

        CALL    BiosDisplaySetBitmapMode
        RET     C

        LD      HL,TECM8_GLCD_TILE_TGBUF + (TECM8_GLCD_TILE_Y_ORIGIN * TECM8_GLCD_TILE_ROW_BYTES)
        LD      A,(GlcdTileFlushRowLast)
        LD      DE,TECM8_GLCD_TILE_ROW_STRIDE
        OR      A
        JR      Z,GlcdTileFlushRowPtrReady

GlcdTileFlushRowPtrLoop:
        ADD     HL,DE
        DEC     A
        JR      NZ,GlcdTileFlushRowPtrLoop

GlcdTileFlushRowPtrReady:
        LD      (GlcdTileFlushRowPtr),HL
        LD      A,(GlcdTileFlushRowLast)
        LD      C,A
        ADD     A,A
        ADD     A,C
        ADD     A,A
        ADD     A,TECM8_GLCD_TILE_Y_ORIGIN
        LD      (GlcdTileFlushPhysicalY),A
        LD      A,TECM8_GLCD_TILE_HEIGHT
        LD      (GlcdTileFlushRowsRemaining),A

GlcdTileFlushPhysicalRowLoop:
        CALL    GlcdTileFlushPhysicalRow
        LD      A,(GlcdTileFlushPhysicalY)
        INC     A
        LD      (GlcdTileFlushPhysicalY),A
        LD      A,(GlcdTileFlushRowsRemaining)
        DEC     A
        LD      (GlcdTileFlushRowsRemaining),A
        JR      NZ,GlcdTileFlushPhysicalRowLoop
        XOR     A
        RET

; GlcdTilePrepareCell -
; Validate B/C and compute the first row byte address plus start bit.
;!      in        B,C
;!      out       carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@GlcdTilePrepareCell:
        LD      A,B
        CP      TECM8_GLCD_TILE_ROWS
        JP      NC,GlcdTileRangeError
        LD      (GlcdTileCellRow),A
        LD      A,C
        CP      TECM8_GLCD_TILE_COLUMNS
        JP      NC,GlcdTileRangeError
        LD      (GlcdTileCellColumn),A

        LD      HL,TECM8_GLCD_TILE_TGBUF + (TECM8_GLCD_TILE_Y_ORIGIN * TECM8_GLCD_TILE_ROW_BYTES)
        LD      A,(GlcdTileCellRow)
        LD      DE,TECM8_GLCD_TILE_ROW_STRIDE
        OR      A
        JR      Z,GlcdTileRowReady

GlcdTileRowLoop:
        ADD     HL,DE
        DEC     A
        JR      NZ,GlcdTileRowLoop

GlcdTileRowReady:
        LD      A,TECM8_GLCD_TILE_TEXT_X
        LD      D,A
        LD      A,(GlcdTileCellColumn)
        LD      B,A
        OR      A
        JR      Z,GlcdTilePixelXReady

GlcdTilePixelXLoop:
        LD      A,D
        ADD     A,TECM8_GLCD_TILE_WIDTH
        LD      D,A
        DJNZ    GlcdTilePixelXLoop

GlcdTilePixelXReady:
        LD      A,D
        LD      B,0

GlcdTileByteOffsetLoop:
        CP      8
        JR      C,GlcdTileByteOffsetReady
        SUB     8
        INC     B
        JR      GlcdTileByteOffsetLoop

GlcdTileByteOffsetReady:
        LD      (GlcdTileStartBit),A
        LD      A,B
        OR      A
        JR      Z,GlcdTileCellPtrReady

GlcdTileBytePtrLoop:
        INC     HL
        DJNZ    GlcdTileBytePtrLoop

GlcdTileCellPtrReady:
        LD      (GlcdTileCellPtr),HL
        LD      (GlcdTileRowPtr),HL
        XOR     A
        RET

; GlcdTileFlushPhysicalRow -
; Push the 16 backing bytes for the selected physical GLCD row.
;!      out       carry
;!      clobbers  A,B,DE,HL,zero,sign,parity,halfCarry
@GlcdTileFlushPhysicalRow:
        CALL    GlcdTileSetGraphicAddress
        LD      HL,(GlcdTileFlushRowPtr)
        LD      B,TECM8_GLCD_TILE_ROW_BYTES

GlcdTileFlushByteLoop:
        LD      A,(HL)
        OUT     (TECM8_GLCD_TILE_PORT_DATA),A
        CALL    GlcdTileFlushDelay
        INC     HL
        LD      A,(GlcdTileFlushRowByteCount)
        INC     A
        LD      (GlcdTileFlushRowByteCount),A
        DJNZ    GlcdTileFlushByteLoop
        LD      (GlcdTileFlushRowPtr),HL
        XOR     A
        RET

; GlcdTileSetGraphicAddress -
; Set ST7920 graphic row and banked horizontal address for one physical row.
;!      out       carry
;!      clobbers  A,B,DE,carry,zero,sign,parity,halfCarry
@GlcdTileSetGraphicAddress:
        LD      A,(GlcdTileFlushPhysicalY)
        CP      TECM8_GLCD_TILE_ROW_BANK
        JR      C,GlcdTileSetGraphicAddressUpper
        SUB     TECM8_GLCD_TILE_ROW_BANK
        LD      B,TECM8_GLCD_TILE_SET_ADDR | TECM8_GLCD_TILE_LOWER_BANK
        JR      GlcdTileSetGraphicAddressRowReady

GlcdTileSetGraphicAddressUpper:
        LD      B,TECM8_GLCD_TILE_SET_ADDR

GlcdTileSetGraphicAddressRowReady:
        OR      TECM8_GLCD_TILE_SET_ADDR
        OUT     (TECM8_GLCD_TILE_PORT_CMD),A
        CALL    GlcdTileFlushDelay
        LD      A,B
        OUT     (TECM8_GLCD_TILE_PORT_CMD),A
        CALL    GlcdTileFlushDelay
        XOR     A
        RET

; GlcdTileFlushDelay -
; Local copy of MON3's small GLCD write delay, kept near the direct port path.
;!      out       A,zero
;!      clobbers  A,DE,carry,zero,sign,parity,halfCarry
@GlcdTileFlushDelay:
        LD      DE,TECM8_GLCD_TILE_DELAY_COUNT

GlcdTileFlushDelayLoop:
        DEC     DE
        LD      A,D
        OR      E
        JR      NZ,GlcdTileFlushDelayLoop
        RET

GlcdTileRangeError:
        LD      A,TECM8_GLCD_TILE_ERR_RANGE
        SCF
        RET

GlcdTileSetMaskTable:
        .db     0x80,0x40,0x20,0x10,0x08,0x04,0x02,0x01
GlcdTileClearMaskTable:
        .db     0x7F,0xBF,0xDF,0xEF,0xF7,0xFB,0xFD,0xFE

GlcdTileCellRow:
        .db     0
GlcdTileCellColumn:
        .db     0
GlcdTileStartBit:
        .db     0
GlcdTileBitIndex:
        .db     0
GlcdTileGlyphCode:
        .db     0
GlcdTileTextRow:
        .db     0
GlcdTileTextColumn:
        .db     0
GlcdTileCellPtr:
        .dw     0
GlcdTileRowPtr:
        .dw     0
GlcdTileGlyphPtr:
        .dw     0
GlcdTileTextPtr:
        .dw     0
GlcdTileFlushFullCount:
        .db     0
GlcdTileFlushRowCount:
        .db     0
GlcdTileFlushRowLast:
        .db     0
GlcdTileFlushRowByteCount:
        .db     0
GlcdTileFlushPhysicalY:
        .db     0
GlcdTileFlushRowsRemaining:
        .db     0
GlcdTileFlushRowPtr:
        .dw     0
