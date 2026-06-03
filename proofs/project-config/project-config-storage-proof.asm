; Project config storage proof.
;
; Runs under Debug80's TEC-1G runtime with MON3 loaded. The proof opens the
; FAT32 VOLUME.TM8 file, reads /tecm8.prj through the TM8 catalog layout, and
; verifies the parsed main path.

        .org    0x4000

ProofPass       .equ     0x42
ProofFail       .equ     0xE0
MainPathOutLen  .equ     64

;!      out       carry,zero
;!      clobbers  A,BC,DE,HL
@Start:
        LD      DE,MainPathOut
        LD      B,MainPathOutLen
        CALL    LoadProjectConfig
        JR      C,ProofFailed

        LD      HL,ExpectedMainPath
        LD      DE,MainPathOut
        CALL    AssertString
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

; AssertString —
; Compare two NUL-terminated strings.
; Input: HL = expected, DE = actual
; Output: carry clear on match, carry set on mismatch
;!      in        DE,HL
;!      out       carry,zero
;!      clobbers  A,DE,HL
@AssertString:
        LD      A,(DE)
        CP      (HL)
        JR      NZ,AssertStringBad
        OR      A
        RET     Z
        INC     DE
        INC     HL
        JR      AssertString

AssertStringBad:
        SCF
        RET

        .include "../../src/project-config.asm"
        .include "../../src/project-config-loader.asm"

ExpectedMainPath:
        .db     "/src/main.asm",0

ResultMarker:
        .db     0

MainPathOut:
        .ds     MainPathOutLen
