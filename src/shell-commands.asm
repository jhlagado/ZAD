; TECM8 shell command resolver.
;
; Resolves the first project-centered shell commands into an action code and a
; concrete TM8 path. Tool execution is deliberately not launched here.

SHELL_CMD_EDIT      .equ     0x10
SHELL_CMD_ASM       .equ     0x11
SHELL_CMD_RUN       .equ     0x12

SHELL_OK            .equ     0
SHELL_ERR_UNKNOWN   .equ     0x40
SHELL_ERR_SYNTAX    .equ     0x41
SHELL_ERR_LONG      .equ     0x42
SHELL_ERR_PROJECT   .equ     0x43

SHELL_MAIN_PATH_LEN .equ     64

; ResolveShellCommand —
; Parse edit/asm/run and resolve the command target path.
; Input:
;   HL = NUL-terminated command line
;   DE = destination path buffer
;   B  = destination capacity, including final NUL
; Output:
;   carry clear, A=SHELL_CMD_*, destination path is NUL-terminated
;   carry set, A=SHELL_ERR_* or project loader error
;!      in        B,DE,HL
;!      out       A,carry,zero
;!      clobbers  A,BC,DE,HL
@ResolveShellCommand:
        LD      (ShellOutPath),DE
        LD      A,B
        LD      (ShellOutCap),A

        CALL    ShellSkipSpaces
        LD      (ShellCommandPtr),HL
        LD      DE,ShellEditText
        CALL    ShellMatchCommand
        JP      NC,ShellResolveEdit

        LD      HL,(ShellCommandPtr)
        LD      DE,ShellAsmText
        CALL    ShellMatchCommand
        JP      NC,ShellResolveAsm

        LD      HL,(ShellCommandPtr)
        LD      DE,ShellRunText
        CALL    ShellMatchCommand
        JP      NC,ShellResolveRun

        LD      A,SHELL_ERR_UNKNOWN
        SCF
        RET

ShellResolveEdit:
        LD      A,SHELL_CMD_EDIT
        JP      ShellResolveSourceCommand

ShellResolveAsm:
        LD      A,SHELL_CMD_ASM
        JP      ShellResolveSourceCommand

ShellResolveRun:
        LD      (ShellAction),A
        CALL    ShellSkipSpaces
        LD      (ShellArgPtr),HL
        CALL    ShellLoadProjectMain
        RET     C
        LD      HL,(ShellArgPtr)
        LD      A,(HL)
        OR      A
        JP      Z,ShellResolveProjectRun
        JP      ShellCopyExplicitPath

; ShellResolveSourceCommand —
; Resolve edit/asm to project main when no argument is present, otherwise to a
; source path under the default source prefix.
; Input: A = command action, HL = text after command
;!      in        A,HL
;!      out       A,carry,zero
;!      clobbers  A,BC,DE,HL
@ShellResolveSourceCommand:
        LD      (ShellAction),A
        CALL    ShellSkipSpaces
        LD      (ShellArgPtr),HL
        CALL    ShellLoadProjectMain
        RET     C
        LD      HL,(ShellArgPtr)
        LD      A,(HL)
        OR      A
        JP      Z,ShellCopyProjectMain
        JP      ShellCopySourceArgument

ShellCopyProjectMain:
        CALL    ShellLoadProjectMain
        RET     C
        LD      HL,ShellMainPath
        LD      DE,(ShellOutPath)
        LD      A,(ShellOutCap)
        LD      B,A
        CALL    ShellCopyString
        RET     C
        LD      A,(ShellAction)
        RET

ShellResolveProjectRun:
        CALL    ShellLoadProjectMain
        RET     C
        LD      HL,ShellMainPath
        LD      DE,(ShellOutPath)
        LD      A,(ShellOutCap)
        LD      B,A
        CALL    ShellDeriveBuildBin
        RET     C
        LD      A,SHELL_CMD_RUN
        RET

ShellCopySourceArgument:
        LD      (ShellArgPtr),HL
        CALL    ShellArgHasSlash
        JR      C,ShellCopyNamedSource

        LD      HL,ShellCurrentPrefix
        LD      DE,(ShellOutPath)
        LD      A,(ShellOutCap)
        LD      B,A
        CALL    ShellCopyString
        RET     C
        LD      A,(ShellRemainingCap)
        LD      B,A
        LD      HL,(ShellArgPtr)
        LD      DE,(ShellWritePtr)
        CALL    ShellCopyArgWithAsmDefault
        RET     C
        LD      A,(ShellAction)
        RET

ShellCopyNamedSource:
        LD      HL,(ShellArgPtr)
        LD      DE,(ShellOutPath)
        LD      A,(ShellOutCap)
        LD      B,A
        CALL    ShellCopyArgWithAsmDefault
        RET     C
        LD      A,(ShellAction)
        RET

ShellCopyExplicitPath:
        LD      DE,(ShellOutPath)
        LD      A,(ShellOutCap)
        LD      B,A
        CALL    ShellCopyArgument
        RET     C
        LD      A,SHELL_CMD_RUN
        RET

ShellLoadProjectMain:
        LD      DE,ShellMainPath
        LD      B,SHELL_MAIN_PATH_LEN
        CALL    LoadProjectConfig
        JR      C,ShellProjectErr
        XOR     A
        RET

ShellProjectErr:
        CP      SHELL_ERR_LONG
        RET     Z
        RET

; ShellMatchCommand —
; Match command literal at DE against HL. The next char must be space or NUL.
; Output: carry clear on match with HL after command; carry set on mismatch.
;!      in        DE,HL
;!      out       carry,zero
;!      clobbers  A,DE,HL
@ShellMatchCommand:
        LD      A,(DE)
        OR      A
        JR      Z,ShellMatchCommandEnd
        CP      (HL)
        JR      NZ,ShellMatchCommandBad
        INC     DE
        INC     HL
        JR      ShellMatchCommand

ShellMatchCommandEnd:
        LD      A,(HL)
        OR      A
        RET     Z
        CP      0x20
        RET     Z

ShellMatchCommandBad:
        SCF
        RET

; ShellSkipSpaces —
; Advance HL past ASCII spaces.
;!      in        HL
;!      out       HL
;!      clobbers  A
@ShellSkipSpaces:
        LD      A,(HL)
        CP      0x20
        RET     NZ
        INC     HL
        JR      ShellSkipSpaces

; ShellCopyString —
; Copy NUL-terminated string from HL to DE with capacity B.
; Stores ShellWritePtr and ShellRemainingCap on success.
;!      in        B,DE,HL
;!      out       carry,zero
;!      clobbers  A,B,DE,HL
@ShellCopyString:
        LD      A,B
        OR      A
        JP      Z,ShellLongErr

ShellCopyStringLoop:
        LD      A,(HL)
        LD      (DE),A
        INC     HL
        OR      A
        JR      Z,ShellCopyStringDone
        INC     DE
        DEC     B
        JP      Z,ShellLongErr
        JR      ShellCopyStringLoop

ShellCopyStringDone:
        LD      (ShellWritePtr),DE
        LD      A,B
        LD      (ShellRemainingCap),A
        XOR     A
        RET

; ShellCopyArgument —
; Copy one argument from HL to DE. Spaces after the argument are accepted only
; when followed by NUL.
;!      in        B,DE,HL
;!      out       carry,zero
;!      clobbers  A,B,DE,HL
@ShellCopyArgument:
        LD      A,B
        OR      A
        JP      Z,ShellLongErr
        LD      C,0

ShellCopyArgumentLoop:
        LD      A,(HL)
        OR      A
        JR      Z,ShellCopyArgumentEnd
        CP      0x20
        JR      Z,ShellCopyArgumentSpace
        LD      (DE),A
        INC     HL
        INC     DE
        INC     C
        DEC     B
        JP      Z,ShellLongErr
        JR      ShellCopyArgumentLoop

ShellCopyArgumentSpace:
        CALL    ShellSkipSpaces
        LD      A,(HL)
        OR      A
        JR      Z,ShellCopyArgumentEnd
        LD      A,SHELL_ERR_SYNTAX
        SCF
        RET

ShellCopyArgumentEnd:
        LD      A,C
        OR      A
        JP      Z,ShellSyntaxErr
        XOR     A
        LD      (DE),A
        RET

; ShellCopyArgWithAsmDefault —
; Copy one argument and append .asm when no dot appears before the terminator.
;!      in        B,DE,HL
;!      out       carry,zero
;!      clobbers  A,B,C,DE,HL
@ShellCopyArgWithAsmDefault:
        LD      A,B
        OR      A
        JP      Z,ShellLongErr
        LD      C,0
        LD      (ShellArgHadDot),A
        XOR     A
        LD      (ShellArgHadDot),A

ShellCopyAsmArgLoop:
        LD      A,(HL)
        OR      A
        JR      Z,ShellCopyAsmArgEnd
        CP      0x20
        JR      Z,ShellCopyAsmArgSpace
        CP      "."
        JR      NZ,ShellCopyAsmArgByte
        LD      A,1
        LD      (ShellArgHadDot),A
        LD      A,"."

ShellCopyAsmArgByte:
        LD      (DE),A
        INC     HL
        INC     DE
        INC     C
        DEC     B
        JP      Z,ShellLongErr
        JR      ShellCopyAsmArgLoop

ShellCopyAsmArgSpace:
        CALL    ShellSkipSpaces
        LD      A,(HL)
        OR      A
        JR      Z,ShellCopyAsmArgEnd
        LD      A,SHELL_ERR_SYNTAX
        SCF
        RET

ShellCopyAsmArgEnd:
        LD      A,C
        OR      A
        JP      Z,ShellSyntaxErr

        LD      A,(ShellArgHadDot)
        OR      A
        JR      NZ,ShellCopyAsmArgNul

        LD      HL,ShellAsmExt
        CALL    ShellAppendString
        RET     C

ShellCopyAsmArgNul:
        XOR     A
        LD      (DE),A
        RET

; ShellAppendString —
; Append NUL-terminated HL text before the final NUL. B is remaining capacity.
;!      in        B,DE,HL
;!      out       carry,zero
;!      clobbers  A,B,DE,HL
@ShellAppendString:
        LD      A,(HL)
        OR      A
        RET     Z
        LD      (DE),A
        INC     HL
        INC     DE
        DEC     B
        JP      Z,ShellLongErr
        JR      ShellAppendString

; ShellArgHasSlash —
; Return carry set when the argument contains '/' before space or NUL.
;!      in        HL
;!      out       carry,zero
;!      clobbers  A,HL
@ShellArgHasSlash:
        LD      A,(HL)
        OR      A
        JR      Z,ShellArgNoSlash
        CP      0x20
        JR      Z,ShellArgNoSlash
        CP      "/"
        JR      Z,ShellArgSlash
        INC     HL
        JR      ShellArgHasSlash

ShellArgSlash:
        SCF
        RET

ShellArgNoSlash:
        XOR     A
        RET

; ShellDeriveBuildBin —
; Derive /build/<local-stem>.bin from an absolute source path.
;!      in        B,DE,HL
;!      out       carry,zero
;!      clobbers  A,B,C,DE,HL
@ShellDeriveBuildBin:
        LD      (ShellArgPtr),HL
        LD      (ShellWritePtr),DE
        CALL    ShellFindLocalName
        LD      (ShellArgPtr),HL
        CALL    ShellFindStemEnd
        LD      (ShellStemEnd),HL

        LD      HL,ShellBuildPrefix
        LD      DE,(ShellWritePtr)
        CALL    ShellCopyString
        RET     C

        LD      A,(ShellRemainingCap)
        LD      B,A
        LD      DE,(ShellWritePtr)
        LD      HL,(ShellArgPtr)
        CALL    ShellCopyStem
        RET     C

        LD      HL,ShellBinExt
        CALL    ShellAppendString
        RET     C
        XOR     A
        LD      (DE),A
        RET

; ShellFindLocalName —
; Return HL pointing at the byte after the last slash.
;!      in        HL
;!      out       HL
;!      clobbers  A,DE,HL
@ShellFindLocalName:
        LD      D,H
        LD      E,L

ShellFindLocalLoop:
        LD      A,(HL)
        OR      A
        JR      Z,ShellFindLocalDone
        CP      "/"
        JR      NZ,ShellFindLocalNext
        INC     HL
        LD      D,H
        LD      E,L
        JR      ShellFindLocalLoop

ShellFindLocalNext:
        INC     HL
        JR      ShellFindLocalLoop

ShellFindLocalDone:
        LD      H,D
        LD      L,E
        RET

; ShellCopyStem —
; Copy a filename stem from HL to DE until dot or NUL.
;!      in        B,DE,HL
;!      out       carry,zero
;!      clobbers  A,B,C,DE,HL
@ShellCopyStem:
        LD      C,0

ShellCopyStemLoop:
        LD      (ShellWritePtr),DE
        PUSH    HL
        LD      DE,(ShellStemEnd)
        LD      A,H
        CP      D
        JR      NZ,ShellCopyStemNotEnd
        LD      A,L
        CP      E
        JR      Z,ShellCopyStemAtEnd

ShellCopyStemNotEnd:
        POP     HL
        LD      DE,(ShellWritePtr)
        LD      A,(HL)
        OR      A
        JR      Z,ShellCopyStemEnd
        LD      (DE),A
        INC     HL
        INC     DE
        INC     C
        DEC     B
        JP      Z,ShellLongErr
        JR      ShellCopyStemLoop

ShellCopyStemAtEnd:
        POP     HL
        LD      DE,(ShellWritePtr)

ShellCopyStemEnd:
        LD      A,C
        OR      A
        JP      Z,ShellSyntaxErr
        RET

; ShellFindStemEnd —
; Return HL pointing at the final dot in a local filename, or at NUL if none.
;!      in        HL
;!      out       HL
;!      clobbers  A,DE,HL
@ShellFindStemEnd:
        LD      D,0
        LD      E,0

ShellFindStemEndLoop:
        LD      A,(HL)
        OR      A
        JR      Z,ShellFindStemDone
        CP      "."
        JR      NZ,ShellFindStemNext
        LD      D,H
        LD      E,L

ShellFindStemNext:
        INC     HL
        JR      ShellFindStemEndLoop

ShellFindStemDone:
        LD      A,D
        OR      E
        RET     Z
        LD      H,D
        LD      L,E
        RET

ShellSyntaxErr:
        LD      A,SHELL_ERR_SYNTAX
        SCF
        RET

ShellLongErr:
        LD      A,SHELL_ERR_LONG
        SCF
        RET

ShellEditText:
        .db     "edit",0

ShellAsmText:
        .db     "asm",0

ShellRunText:
        .db     "run",0

ShellCurrentPrefix:
        .db     "/src/",0

ShellBuildPrefix:
        .db     "/build/",0

ShellAsmExt:
        .db     ".asm",0

ShellBinExt:
        .db     ".bin",0

ShellOutPath:
        .dw     0

ShellWritePtr:
        .dw     0

ShellArgPtr:
        .dw     0

ShellCommandPtr:
        .dw     0

ShellStemEnd:
        .dw     0

ShellOutCap:
        .db     0

ShellRemainingCap:
        .db     0

ShellAction:
        .db     0

ShellArgHadDot:
        .db     0

ShellMainPath:
        .ds     SHELL_MAIN_PATH_LEN
