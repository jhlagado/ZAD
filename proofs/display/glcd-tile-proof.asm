; GLCD tile-cell proof.
;
; Exercises TECM8-owned 6x6 cell writes into MON3 TGBUF without using MON3's
; terminal glyph drawing routine.

        .org    0x4000

PROOF_PASS       .equ     0x42
PROOF_FAIL       .equ     0xE0

;!      out       carry,zero
;!      clobbers  A,BC,DE,HL
@Start:
        CALL    BiosDisplayInit
        JR      C,ProofFailed
        CALL    BiosDisplayClear
        JR      C,ProofFailed

        LD      A,'A'
        LD      B,1
        LD      C,0
        CALL    GlcdTileDrawCell
        JR      C,ProofFailed

        LD      A,'B'
        LD      B,1
        LD      C,0
        CALL    GlcdTileDrawCell
        JR      C,ProofFailed

        LD      A,'B'
        LD      B,1
        LD      C,1
        CALL    GlcdTileDrawCell
        JR      C,ProofFailed

        LD      B,1
        LD      C,0
        CALL    GlcdTileClearCell
        JR      C,ProofFailed

        LD      HL,TileText
        LD      B,2
        LD      C,0
        CALL    GlcdTileDrawTextRun
        JR      C,ProofFailed

        CALL    GlcdTileFlushFull
        JR      C,ProofFailed
        LD      A,(GlcdTileFlushFullCount)
        CP      1
        JR      NZ,ProofFailed

        XOR     A
        LD      (GlcdTileFlushFullCount),A
        LD      (GlcdTileFlushRowByteCount),A

        LD      A,'C'
        LD      B,1
        LD      C,1
        CALL    GlcdTileDrawCell
        JR      C,ProofFailed

        LD      A,1
        CALL    GlcdTileFlushRow
        JR      C,ProofFailed
        LD      A,(GlcdTileFlushFullCount)
        OR      A
        JR      NZ,ProofFailed
        LD      A,(GlcdTileFlushRowByteCount)
        CP      96
        JR      NZ,ProofFailed

        LD      A,PROOF_PASS
        LD      (ResultMarker),A

ProofDone:
        JP      ProofDone

ProofFailed:
        OR      PROOF_FAIL
        LD      (ResultMarker),A

ProofFailedDone:
        JP      ProofDone

        .include "../../src/glcd-tile.asm"
        .include "../../src/tecm8-bios.asm"

TileText:
        .db     "OK",0

ResultMarker:
        .db     0
