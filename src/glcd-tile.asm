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
        CALL    GlcdTileQueueRow
        RET     C

GlcdTileFlushRowDrainLoop:
        CALL    GlcdTileStep
        RET     C
        OR      A
        JR      NZ,GlcdTileFlushRowDrainLoop
        XOR     A
        RET

; GlcdTileQueueRow -
; Queue one dirty 6-pixel text row for bounded GLCD transfer steps.
; Input: A = row (0-9)
;!      in        A
;!      out       carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@GlcdTileQueueRow:
        CP      TECM8_GLCD_TILE_ROWS
        JP      NC,GlcdTileRangeError
        LD      (GlcdTileFlushRowLast),A
        LD      (GlcdTileRequestedRow),A
        LD      A,(GlcdTileFlushRowCount)
        INC     A
        LD      (GlcdTileFlushRowCount),A
        CALL    GlcdTileDrainPending
        RET     C
        LD      A,(GlcdTileRequestedRow)
        LD      (GlcdTileFlushRowLast),A
        JP      GlcdTileStartQueuedRow

; GlcdTileMarkRowDirty -
; Mark one text row for later cooperative transfer by GlcdTileStep.
; Input: A = row (0-9)
;!      in        A
;!      out       carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@GlcdTileMarkRowDirty:
        CP      TECM8_GLCD_TILE_ROWS
        JP      NC,GlcdTileRangeError
        LD      (GlcdTileDirtyRowTemp),A
        LD      A,(GlcdTileFlushRowCount)
        INC     A
        LD      (GlcdTileFlushRowCount),A
        LD      A,(GlcdTileDirtyRowTemp)
        CP      8
        JR      NC,GlcdTileMarkHighRow
        LD      HL,GlcdTileDirtyRowsLo
        JR      GlcdTileMarkMaskReady

GlcdTileMarkHighRow:
        SUB     8
        LD      (GlcdTileDirtyRowTemp),A
        LD      HL,GlcdTileDirtyRowsHi

GlcdTileMarkMaskReady:
        LD      D,0
        LD      E,A
        PUSH    HL
        LD      HL,GlcdTileDirtySetMaskTable
        ADD     HL,DE
        LD      A,(HL)
        POP     HL
        OR      (HL)
        LD      (HL),A
        XOR     A
        RET

; GlcdTileMarkCellDirty -
; Mark one text cell for later cooperative byte-range transfer.
; Input: B = row (0-9), C = column (0-19)
;!      in        B,C
;!      out       carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@GlcdTileMarkCellDirty:
        CALL    GlcdTilePrepareCell
        RET     C
        LD      A,(GlcdTileCellRow)
        LD      (GlcdTileDirtyCellRowTemp),A
        LD      A,(GlcdTileFlushCellCount)
        INC     A
        LD      (GlcdTileFlushCellCount),A
        LD      A,(GlcdTileByteX)
        LD      (GlcdTileDirtyCellMinTemp),A
        LD      B,A
        LD      A,(GlcdTileStartBit)
        CP      3
        JR      C,GlcdTileDirtyCellMaxReady
        LD      A,B
        INC     A
        JR      GlcdTileDirtyCellMaxStore

GlcdTileDirtyCellMaxReady:
        LD      A,B

GlcdTileDirtyCellMaxStore:
        OR      1
        LD      (GlcdTileDirtyCellMaxTemp),A
        LD      A,(GlcdTileDirtyCellMinTemp)
        AND     0xFE
        LD      (GlcdTileDirtyCellMinTemp),A
        LD      A,(GlcdTileDirtyCellRowTemp)
        CP      8
        JR      NC,GlcdTileMarkCellHighRow
        LD      HL,GlcdTileDirtyCellRowsLo
        JR      GlcdTileMarkCellMaskReady

GlcdTileMarkCellHighRow:
        SUB     8
        LD      HL,GlcdTileDirtyCellRowsHi

GlcdTileMarkCellMaskReady:
        LD      D,0
        LD      E,A
        PUSH    HL
        LD      HL,GlcdTileDirtySetMaskTable
        ADD     HL,DE
        LD      A,(HL)
        POP     HL
        OR      (HL)
        LD      (HL),A

        LD      A,(GlcdTileDirtyCellRowTemp)
        LD      E,A
        LD      D,0
        LD      HL,GlcdTileDirtyCellMin
        ADD     HL,DE
        LD      A,(HL)
        CP      0xFF
        JR      Z,GlcdTileDirtyCellWriteMin
        LD      B,A
        LD      A,(GlcdTileDirtyCellMinTemp)
        CP      B
        JR      NC,GlcdTileDirtyCellMinDone

GlcdTileDirtyCellWriteMin:
        LD      A,(GlcdTileDirtyCellMinTemp)
        LD      (HL),A

GlcdTileDirtyCellMinDone:
        LD      A,(GlcdTileDirtyCellRowTemp)
        LD      E,A
        LD      D,0
        LD      HL,GlcdTileDirtyCellMax
        ADD     HL,DE
        LD      A,(HL)
        LD      B,A
        LD      A,(GlcdTileDirtyCellMaxTemp)
        CP      B
        JR      C,GlcdTileDirtyCellMaxDone
        LD      (HL),A

GlcdTileDirtyCellMaxDone:
        XOR     A
        RET

; GlcdTileStartQueuedRow -
; Start transfer state for GlcdTileFlushRowLast without changing queue counts.
;!      out       carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@GlcdTileStartQueuedRow:
        XOR     A
        LD      (GlcdTileFlushByteX),A
        LD      (GlcdTileFlushMode),A
        LD      (GlcdTileFlushRowAdvance),A
        LD      A,TECM8_GLCD_TILE_ROW_BYTES
        LD      (GlcdTileFlushBytesPerRow),A
        JP      GlcdTileStartQueuedTransfer

; GlcdTileStartQueuedTransfer -
; Start row-transfer state for GlcdTileFlushRowLast and current byte range.
;!      out       carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@GlcdTileStartQueuedTransfer:
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
        LD      A,(GlcdTileFlushByteX)
        LD      E,A
        LD      D,0
        ADD     HL,DE
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
        LD      A,1
        LD      (GlcdTileFlushPending),A
        XOR     A
        RET

; GlcdTileStep -
; Transfer at most one physical GLCD row from the queued row flush.
; Output: A = 1 when more queued work remains, 0 when idle/done.
;!      out       A,carry,zero
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@GlcdTileStep:
        LD      A,(GlcdTileFlushPending)
        OR      A
        JR      NZ,GlcdTileStepPending
        CALL    GlcdTileStartDirtyCellRow
        RET     C
        OR      A
        JR      NZ,GlcdTileStepPending
        CALL    GlcdTileStartDirtyRow
        RET     C
        OR      A
        JR      NZ,GlcdTileStepPending
        XOR     A
        RET

GlcdTileStepPending:
        CALL    GlcdTileFlushPhysicalRow
        RET     C
        LD      A,(GlcdTileStepCount)
        INC     A
        LD      (GlcdTileStepCount),A
        LD      A,(GlcdTileFlushPhysicalY)
        INC     A
        LD      (GlcdTileFlushPhysicalY),A
        LD      A,(GlcdTileFlushRowsRemaining)
        DEC     A
        LD      (GlcdTileFlushRowsRemaining),A
        JR      Z,GlcdTileStepDone
        LD      A,1
        OR      A
        RET

GlcdTileStepDone:
        XOR     A
        LD      (GlcdTileFlushPending),A
        LD      A,(GlcdTileDirtyCellRowsLo)
        OR      A
        JR      NZ,GlcdTileStepMoreDirty
        LD      A,(GlcdTileDirtyCellRowsHi)
        OR      A
        JR      NZ,GlcdTileStepMoreDirty
        LD      A,(GlcdTileDirtyRowsLo)
        OR      A
        JR      NZ,GlcdTileStepMoreDirty
        LD      A,(GlcdTileDirtyRowsHi)
        OR      A
        JR      NZ,GlcdTileStepMoreDirty
        XOR     A
        RET

GlcdTileStepMoreDirty:
        LD      A,1
        OR      A
        RET

; GlcdTileDrainPending -
; Drain any already pending or marked row work before a synchronous row starts.
;!      out       carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@GlcdTileDrainPending:
        CALL    GlcdTileStep
        RET     C
        OR      A
        JR      NZ,GlcdTileDrainPending
        XOR     A
        RET

; GlcdTileStartDirtyRow -
; Start the lowest marked dirty row without transferring it yet.
; Output: A = 1 when a row was started, 0 when no dirty rows are queued.
;!      out       A,carry,zero
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@GlcdTileStartDirtyRow:
        LD      A,(GlcdTileDirtyRowsLo)
        OR      A
        JR      NZ,GlcdTileStartDirtyLow
        LD      A,(GlcdTileDirtyRowsHi)
        OR      A
        JR      NZ,GlcdTileStartDirtyHigh
        XOR     A
        RET

GlcdTileStartDirtyLow:
        LD      B,A
        LD      C,0
        LD      HL,GlcdTileDirtyRowsLo
        JR      GlcdTileStartDirtyFindRow

GlcdTileStartDirtyHigh:
        LD      B,A
        LD      C,8
        LD      HL,GlcdTileDirtyRowsHi

GlcdTileStartDirtyFindRow:
        LD      A,B
        AND     1
        JR      NZ,GlcdTileStartDirtyFound
        SRL     B
        INC     C
        JR      GlcdTileStartDirtyFindRow

GlcdTileStartDirtyFound:
        LD      A,C
        LD      (GlcdTileFlushRowLast),A
        CP      8
        JR      C,GlcdTileStartDirtyMaskIndexReady
        SUB     8

GlcdTileStartDirtyMaskIndexReady:
        LD      D,0
        LD      E,A
        PUSH    HL
        LD      HL,GlcdTileDirtyClearMaskTable
        ADD     HL,DE
        LD      A,(HL)
        POP     HL
        AND     (HL)
        LD      (HL),A
        CALL    GlcdTileStartQueuedRow
        RET     C
        LD      A,1
        OR      A
        RET

; GlcdTileStartDirtyCellRow -
; Start the lowest marked dirty cell byte range without transferring it yet.
; Output: A = 1 when a range was started, 0 when no cell ranges are queued.
;!      out       A,carry,zero
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@GlcdTileStartDirtyCellRow:
        LD      A,(GlcdTileDirtyCellRowsLo)
        OR      A
        JR      NZ,GlcdTileStartDirtyCellLow
        LD      A,(GlcdTileDirtyCellRowsHi)
        OR      A
        JR      NZ,GlcdTileStartDirtyCellHigh
        XOR     A
        RET

GlcdTileStartDirtyCellLow:
        LD      B,A
        LD      C,0
        LD      HL,GlcdTileDirtyCellRowsLo
        JR      GlcdTileStartDirtyCellFindRow

GlcdTileStartDirtyCellHigh:
        LD      B,A
        LD      C,8
        LD      HL,GlcdTileDirtyCellRowsHi

GlcdTileStartDirtyCellFindRow:
        LD      A,B
        AND     1
        JR      NZ,GlcdTileStartDirtyCellFound
        SRL     B
        INC     C
        JR      GlcdTileStartDirtyCellFindRow

GlcdTileStartDirtyCellFound:
        LD      A,C
        LD      (GlcdTileFlushRowLast),A
        LD      (GlcdTileDirtyCellRowTemp),A
        CP      8
        JR      C,GlcdTileStartDirtyCellMaskIndexReady
        SUB     8

GlcdTileStartDirtyCellMaskIndexReady:
        LD      D,0
        LD      E,A
        PUSH    HL
        LD      HL,GlcdTileDirtyClearMaskTable
        ADD     HL,DE
        LD      A,(HL)
        POP     HL
        AND     (HL)
        LD      (HL),A

        LD      A,(GlcdTileDirtyCellRowTemp)
        LD      E,A
        LD      D,0
        LD      HL,GlcdTileDirtyCellMin
        ADD     HL,DE
        LD      A,(HL)
        LD      (GlcdTileFlushByteX),A
        LD      (HL),0xFF
        LD      A,(GlcdTileDirtyCellRowTemp)
        LD      E,A
        LD      D,0
        LD      HL,GlcdTileDirtyCellMax
        ADD     HL,DE
        LD      A,(HL)
        LD      B,A
        XOR     A
        LD      (HL),A
        LD      A,B
        LD      (GlcdTileDirtyCellMaxTemp),A
        LD      A,(GlcdTileFlushByteX)
        LD      C,A
        LD      A,(GlcdTileDirtyCellMaxTemp)
        SUB     C
        INC     A
        LD      (GlcdTileFlushBytesPerRow),A
        LD      B,A
        LD      A,TECM8_GLCD_TILE_ROW_BYTES
        SUB     B
        LD      (GlcdTileFlushRowAdvance),A
        LD      A,1
        LD      (GlcdTileFlushMode),A
        CALL    GlcdTileStartQueuedTransfer
        RET     C
        LD      A,1
        OR      A
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
        LD      (GlcdTileByteX),A
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
; Push the selected backing-byte range for the selected physical GLCD row.
;!      out       carry
;!      clobbers  A,B,DE,HL,zero,sign,parity,halfCarry
@GlcdTileFlushPhysicalRow:
        CALL    GlcdTileSetGraphicAddress
        LD      HL,(GlcdTileFlushRowPtr)
        LD      A,(GlcdTileFlushBytesPerRow)
        LD      B,A

GlcdTileFlushByteLoop:
        LD      A,(HL)
        OUT     (TECM8_GLCD_TILE_PORT_DATA),A
        CALL    GlcdTileFlushDelay
        INC     HL
        LD      A,(GlcdTileFlushRowByteCount)
        INC     A
        LD      (GlcdTileFlushRowByteCount),A
        LD      A,(GlcdTileFlushMode)
        OR      A
        JR      Z,GlcdTileFlushByteNext
        LD      A,(GlcdTileFlushCellByteCount)
        INC     A
        LD      (GlcdTileFlushCellByteCount),A

GlcdTileFlushByteNext:
        DJNZ    GlcdTileFlushByteLoop
        LD      A,(GlcdTileFlushRowAdvance)
        LD      E,A
        LD      D,0
        ADD     HL,DE
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
        LD      A,(GlcdTileFlushByteX)
        SRL     A
        OR      B
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
GlcdTileDirtySetMaskTable:
        .db     0x01,0x02,0x04,0x08,0x10,0x20,0x40,0x80
GlcdTileDirtyClearMaskTable:
        .db     0xFE,0xFD,0xFB,0xF7,0xEF,0xDF,0xBF,0x7F

GlcdTileCellRow:
        .db     0
GlcdTileCellColumn:
        .db     0
GlcdTileStartBit:
        .db     0
GlcdTileByteX:
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
GlcdTileFlushCellCount:
        .db     0
GlcdTileFlushCellByteCount:
        .db     0
GlcdTileStepCount:
        .db     0
GlcdTileFlushPending:
        .db     0
GlcdTileFlushMode:
        .db     0
GlcdTileDirtyRowsLo:
        .db     0
GlcdTileDirtyRowsHi:
        .db     0
GlcdTileDirtyCellRowsLo:
        .db     0
GlcdTileDirtyCellRowsHi:
        .db     0
GlcdTileDirtyRowTemp:
        .db     0
GlcdTileDirtyCellRowTemp:
        .db     0
GlcdTileDirtyCellMinTemp:
        .db     0
GlcdTileDirtyCellMaxTemp:
        .db     0
GlcdTileDirtyCellMin:
        .db     0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF
GlcdTileDirtyCellMax:
        .db     0,0,0,0,0,0,0,0,0,0
GlcdTileRequestedRow:
        .db     0
GlcdTileFlushPhysicalY:
        .db     0
GlcdTileFlushRowsRemaining:
        .db     0
GlcdTileFlushByteX:
        .db     0
GlcdTileFlushBytesPerRow:
        .db     TECM8_GLCD_TILE_ROW_BYTES
GlcdTileFlushRowAdvance:
        .db     0
GlcdTileFlushRowPtr:
        .dw     0
