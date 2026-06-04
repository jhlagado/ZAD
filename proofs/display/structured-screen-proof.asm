; Structured display screen proof.
;
; Runs under Debug80's TEC-1G runtime with MON3 loaded. The proof renders a
; small editor-like screen model: top chrome, eight editable lines with gutter
; markers, and a bottom status/command row.

        .org    0x4000

ProofPass       .equ     0x42
ProofFail       .equ     0xE0

;!      out       carry,zero
;!      clobbers  A,BC,DE,HL
@Start:
        CALL    TECM8_DISPLAY_INIT
        JR      C,ProofFailed

        LD      HL,StructuredScreen
        CALL    TECM8_DISPLAY_RENDER_SCREEN
        JR      C,ProofFailed

        CALL    TECM8_BIOS_DISPLAY_UPDATE
        JR      C,ProofFailed

        LD      A,ProofPass
        LD      (ResultMarker),A

ProofDone:
        JP      ProofDone

ProofFailed:
        OR      ProofFail
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
