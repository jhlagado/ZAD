; Structured display screen proof.
;
; Runs under Debug80's TEC-1G runtime with MON3 loaded. The proof renders a
; small editor-like screen model: top chrome, eight editable lines with gutter
; markers, and a bottom status/command row.

        .org    0x4000

PROOF_PASS       .equ     0x42
PROOF_FAIL       .equ     0xE0
MON3_VPORT      .equ     0x0E13

;!      out       carry,zero
;!      clobbers  A,BC,DE,HL
@Start:
        CALL    DisplayInit
        JR      C,ProofFailed

        LD      HL,0x1000
        LD      (MON3_VPORT),HL

        LD      HL,StructuredScreen
        CALL    DisplayRenderScreen
        JR      C,ProofFailed

        CALL    BiosDisplayUpdate
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

        .include "../../src/display-model.asm"
        .include "../../src/tecm8-bios.asm"

StructuredScreen:
        .dw     TopChrome
        .db     TECM8_DISPLAY_MARKER_BREAKPOINT
        .dw     SourceLine0
        .db     TECM8_DISPLAY_MARKER_CURRENT
        .dw     SourceLine1
        .db     TECM8_DISPLAY_MARKER_SELECTED
        .dw     SourceLine2
        .db     TECM8_DISPLAY_MARKER_NONE
        .dw     SourceLine3
        .db     TECM8_DISPLAY_MARKER_NONE
        .dw     SourceLine4
        .db     TECM8_DISPLAY_MARKER_BREAKPOINT | TECM8_DISPLAY_MARKER_CURRENT
        .dw     SourceLine5
        .db     TECM8_DISPLAY_MARKER_NONE
        .dw     SourceLine6
        .db     TECM8_DISPLAY_MARKER_SELECTED
        .dw     SourceLine7
        .dw     BottomChrome

TopChrome:
        .db     "TECM8 MAIN.ASM",0
SourceLine0:
        .db     "ORG 4000H",0
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
BottomChrome:
        .db     "Ln 2 Col 5 INS",0

ResultMarker:
        .db     0
