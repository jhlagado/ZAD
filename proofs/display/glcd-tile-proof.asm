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
        JP      C,ProofFailed
        CALL    BiosDisplayClear
        JP      C,ProofFailed

        LD      A,'A'
        LD      B,1
        LD      C,0
        CALL    GlcdTileDrawCell
        JP      C,ProofFailed

        LD      A,'B'
        LD      B,1
        LD      C,0
        CALL    GlcdTileDrawCell
        JP      C,ProofFailed

        LD      A,'B'
        LD      B,1
        LD      C,1
        CALL    GlcdTileDrawCell
        JP      C,ProofFailed

        LD      B,1
        LD      C,0
        CALL    GlcdTileClearCell
        JP      C,ProofFailed

        LD      HL,TileText
        LD      B,2
        LD      C,0
        CALL    GlcdTileDrawTextRun
        JP      C,ProofFailed

        CALL    GlcdTileFlushFull
        JP      C,ProofFailed
        LD      A,(GlcdTileFlushFullCount)
        CP      1
        JP      NZ,ProofFailed

        XOR     A
        LD      (GlcdTileFlushFullCount),A
        LD      (GlcdTileFlushRowByteCount),A
        LD      (GlcdTileStepCount),A

        LD      A,'C'
        LD      B,1
        LD      C,1
        CALL    GlcdTileDrawCell
        JP      C,ProofFailed

        LD      A,1
        CALL    GlcdTileFlushRow
        JP      C,ProofFailed
        LD      A,(GlcdTileFlushFullCount)
        OR      A
        JP      NZ,ProofFailed
        LD      A,(GlcdTileFlushRowByteCount)
        CP      96
        JP      NZ,ProofFailed

        XOR     A
        LD      (GlcdTileFlushRowByteCount),A
        LD      (GlcdTileStepCount),A

        LD      A,'D'
        LD      B,1
        LD      C,1
        CALL    GlcdTileDrawCell
        JP      C,ProofFailed

        LD      A,1
        CALL    GlcdTileQueueRow
        JP      C,ProofFailed
        CALL    GlcdTileStep
        JP      C,ProofFailed
        OR      A
        JP      Z,ProofFailed
        LD      A,(GlcdTileFlushRowByteCount)
        CP      16
        JP      NZ,ProofFailed
        LD      A,(GlcdTileStepCount)
        CP      1
        JP      NZ,ProofFailed

        CALL    GlcdTileStep
        JP      C,ProofFailed
        OR      A
        JP      Z,ProofFailed
        CALL    GlcdTileStep
        JP      C,ProofFailed
        OR      A
        JP      Z,ProofFailed
        CALL    GlcdTileStep
        JP      C,ProofFailed
        OR      A
        JP      Z,ProofFailed
        CALL    GlcdTileStep
        JP      C,ProofFailed
        OR      A
        JP      Z,ProofFailed
        CALL    GlcdTileStep
        JP      C,ProofFailed
        OR      A
        JP      NZ,ProofFailed
        LD      A,(GlcdTileFlushRowByteCount)
        CP      96
        JP      NZ,ProofFailed
        LD      A,(GlcdTileStepCount)
        CP      6
        JP      NZ,ProofFailed
        CALL    GlcdTileStep
        JP      C,ProofFailed
        OR      A
        JP      NZ,ProofFailed
        LD      A,(GlcdTileStepCount)
        CP      6
        JP      NZ,ProofFailed

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
