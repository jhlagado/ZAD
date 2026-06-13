; Structured display screen proof.
;
; Runs under Debug80's TEC-1G runtime with MON3 loaded. The proof renders a
; small editor-like screen model: ten source lines with gutter markers.

        .org    0x4000

        .include "../../src/tecm8-equates.asm"

PROOF_PASS       .equ     0x42
PROOF_FAIL       .equ     0xE0
MON3_VPORT      .equ     0x0E13
CursorAdjacentMarker .equ     0x13E4
CursorFarRightMarker .equ     0x13F0

;! out carry,zero
;! clobbers A,BC,DE,HL
@Start:
        CALL    DisplayInit
        JR      C,ProofFailed

        LD      HL,0x1000
        LD      (MON3_VPORT),HL

        LD      HL,StructuredScreenLong
        CALL    DisplayRenderScreen
        JR      C,ProofFailed

        XOR     A
        LD      C,TECM8_DISPLAY_MARKER_BREAKPOINT
        LD      HL,SourceLine0
        CALL    DisplayRenderLine
        JR      C,ProofFailed

        XOR     A
        LD      C,3
        CALL    DisplayRenderCursorCell
        JR      C,ProofFailed
        LD      A,0x5A
        LD      (CursorAdjacentMarker),A
        XOR     A
        LD      C,3
        CALL    DisplayEraseCursorCell
        JR      C,ProofFailed

        XOR     A
        LD      C,19
        CALL    DisplayRenderCursorCell
        JR      C,ProofFailed
        LD      A,0xF5
        LD      (CursorFarRightMarker),A
        XOR     A
        LD      C,19
        CALL    DisplayEraseCursorCell
        JR      C,ProofFailed

        CALL    GlcdTileFlushFull
        JR      C,ProofFailed

        LD      A,1
        LD      C,7
        CALL    DisplayRenderCursorCell
        JR      C,ProofFailed
        CALL    DrainDisplayWork
        JR      C,ProofFailed

        LD      A,PROOF_PASS
        LD      (ResultMarker),A

ProofDone:
        JP      ProofDone

ProofFailed:
        OR      PROOF_FAIL
        LD      (ResultMarker),A

ProofFailedDone:
        JP      ProofDone

; DrainDisplayWork -
; Structured proofs do not run the live idle loop, so drain queued GLCD bytes
; before host-side visible-pixel assertions.
;! out A,carry,zero
;! clobbers A,BC,DE,HL,zero,sign,parity,halfCarry
@DrainDisplayWork:
        CALL    GlcdTileStep
        RET     C
        OR      A
        JR      NZ,DrainDisplayWork
        XOR     A
        RET

        .include "../../src/glcd-tile.asm"
        .include "../../src/display-model.asm"
        .include "../../src/tecm8-bios.asm"

StructuredScreen:
        .db     TECM8_DISPLAY_MARKER_BREAKPOINT
        .dw     SourceLine0
        .db     TECM8_DISPLAY_MARKER_NONE
        .dw     SourceLine1
        .db     TECM8_DISPLAY_MARKER_SELECTED
        .dw     SourceLine2
        .db     TECM8_DISPLAY_MARKER_COPY_SOURCE
        .dw     SourceLine3
        .db     TECM8_DISPLAY_MARKER_MOVE_SOURCE
        .dw     SourceLine4
        .db     TECM8_DISPLAY_MARKER_BREAKPOINT
        .dw     SourceLine5
        .db     TECM8_DISPLAY_MARKER_NONE
        .dw     SourceLine6
        .db     TECM8_DISPLAY_MARKER_SELECTED
        .dw     SourceLine7
        .db     TECM8_DISPLAY_MARKER_NONE
        .dw     SourceLine8
        .db     TECM8_DISPLAY_MARKER_NONE
        .dw     SourceLine9

StructuredScreenLong:
        .db     TECM8_DISPLAY_MARKER_BREAKPOINT
        .dw     SourceLine0Long
        .db     TECM8_DISPLAY_MARKER_NONE
        .dw     SourceLine1
        .db     TECM8_DISPLAY_MARKER_SELECTED
        .dw     SourceLine2
        .db     TECM8_DISPLAY_MARKER_COPY_SOURCE
        .dw     SourceLine3
        .db     TECM8_DISPLAY_MARKER_MOVE_SOURCE
        .dw     SourceLine4
        .db     TECM8_DISPLAY_MARKER_BREAKPOINT
        .dw     SourceLine5
        .db     TECM8_DISPLAY_MARKER_NONE
        .dw     SourceLine6
        .db     TECM8_DISPLAY_MARKER_SELECTED
        .dw     SourceLine7
        .db     TECM8_DISPLAY_MARKER_NONE
        .dw     SourceLine8
        .db     TECM8_DISPLAY_MARKER_NONE
        .dw     SourceLine9

SourceLine0:
        .db     "ORG 4000H",0
SourceLine0Long:
        .db     "ABCDEFGHIJKLMNOPQRST",0
SourceLine1:
        .db     "CALL INIT",0
SourceLine2:
        .db     "LD HL,MSG",0
SourceLine3:
        .db     "CALL PRINT",0
SourceLine4:
        .db     "JP DONE",0
SourceLine5:
        .db     "MSG DB 'OK'",0
SourceLine6:
        .db     "DONE:",0
SourceLine7:
        .db     "RET",0
SourceLine8:
        .db     "NOP",0
SourceLine9:
        .db     "END",0

ResultMarker:
        .db     0
