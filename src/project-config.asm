; TECM8 project config parser.
;
; Parses the loaded /tecm8.prj text buffer. File I/O is deliberately separate:
; the shell storage layer should load the root file, then call this parser on
; the bytes it read. This first parser accepts the canonical v1 key order only:
; tm8project line first, main line second.

LF              .equ     0x0A
NUL             .equ     0x00

PROJECT_CFG_OK        .equ 0
PROJECT_CFG_ERR_HEADER .equ 1
PROJECT_CFG_ERR_MAIN   .equ 2
PROJECT_CFG_ERR_EMPTY  .equ 3
PROJECT_CFG_ERR_LONG   .equ 4
PROJECT_CFG_ERR_EXTRA  .equ 5

; ParseProjectConfig —
; Validate a /tecm8.prj buffer and copy the main path.
; Expected v1 file:
;   tm8project=1\n
;   main=/src/main.asm\n
; Input:
;   HL = zero-terminated project file text
;   DE = destination buffer for the main path
;   B  = destination byte capacity, including final NUL
; Output:
;   carry clear, A=PROJECT_CFG_OK, destination is NUL-terminated main path
;   carry set, A=ProjectCfgErr*
;!      in        B,DE,HL
;!      out       A,C,carry,zero
;!      clobbers  B,DE,HL
@ParseProjectConfig:
        PUSH    DE
        LD      DE,ProjectCfgMagicLine
        CALL    ProjectCfgMatchLine
        POP     DE
        JP      C,ProjectCfgHeaderErr

        PUSH    DE
        LD      DE,ProjectCfgMainKey
        CALL    ProjectCfgMatchText
        POP     DE
        JP      C,ProjectCfgMainErr

        LD      A,B
        OR      A
        JP      Z,ProjectCfgLongErr

        LD      C,B
        LD      B,0

ParseCfgPathLoop:
        LD      A,(HL)
        CP      LF
        JR      Z,ParseCfgPathEnd
        OR      A
        JR      Z,ParseCfgPathEnd

        LD      (DE),A
        INC     HL
        INC     DE
        DEC     C
        JP      Z,ProjectCfgLongErr
        INC     B
        JR      ParseCfgPathLoop

ParseCfgPathEnd:
        LD      A,B
        OR      A
        JP      Z,ProjectCfgEmptyErr

        LD      A,(HL)
        CP      LF
        JR      NZ,ParseCfgCheckFinalNul
        INC     HL

ParseCfgCheckFinalNul:
        LD      A,(HL)
        OR      A
        JP      NZ,ProjectCfgExtraErr

        XOR     A
        LD      (DE),A
        RET

ProjectCfgHeaderErr:
        LD      A,PROJECT_CFG_ERR_HEADER
        SCF
        RET

ProjectCfgMainErr:
        LD      A,PROJECT_CFG_ERR_MAIN
        SCF
        RET

ProjectCfgEmptyErr:
        LD      A,PROJECT_CFG_ERR_EMPTY
        SCF
        RET

ProjectCfgLongErr:
        LD      A,PROJECT_CFG_ERR_LONG
        SCF
        RET

ProjectCfgExtraErr:
        LD      A,PROJECT_CFG_ERR_EXTRA
        SCF
        RET

; ProjectCfgMatchLine —
; Match zero-terminated text at DE against HL, then require LF.
; Input: HL = source, DE = literal
; Output: carry clear on match, HL after LF; carry set on mismatch
;!      in        DE,HL
;!      out       HL,A,carry,zero
;!      clobbers  DE
@ProjectCfgMatchLine:
        CALL    ProjectCfgMatchText
        RET     C
        LD      A,(HL)
        CP      LF
        JR      Z,ProjectCfgLineOk
        SCF
        RET

ProjectCfgLineOk:
        INC     HL
        OR      A
        RET

; ProjectCfgMatchText —
; Match zero-terminated literal at DE against bytes at HL.
; Input: HL = source, DE = literal
; Output: carry clear on match, HL after literal; carry set on mismatch
;!      in        DE,HL
;!      out       DE,HL,A,carry,zero
@ProjectCfgMatchText:
        LD      A,(DE)
        OR      A
        RET     Z
        CP      (HL)
        JR      NZ,ProjectCfgTextBad
        INC     DE
        INC     HL
        JR      ProjectCfgMatchText

ProjectCfgTextBad:
        SCF
        RET

ProjectCfgMagicLine:
        .db     "tm8project=1",0

ProjectCfgMainKey:
        .db     "main=",0

ProjectCfgFileName:
        .db     "/tecm8.prj",0
