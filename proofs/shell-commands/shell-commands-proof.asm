; Shell command resolver proof.
;
; Runs in the plain Debug80 Z80 runtime. LoadProjectConfig is stubbed here so
; the proof exercises command parsing and path resolution without MON3 storage.

        .org    0x4000

ProofPass       .equ     0x42
ProofFail       .equ     0xE0
PathOutLen      .equ     64

;!      out       carry,zero
;!      clobbers  A,BC,DE,HL
@Start:
        LD      A,1
        LD      (CaseMarker),A
        LD      HL,CmdEdit
        LD      A,SHELL_CMD_EDIT
        LD      DE,ExpectedMain
        CALL    AssertCommand
        JP      C,ProofFailed

        LD      A,2
        LD      (CaseMarker),A
        LD      HL,CmdAsm
        LD      A,SHELL_CMD_ASM
        LD      DE,ExpectedMain
        CALL    AssertCommand
        JP      C,ProofFailed

        LD      A,3
        LD      (CaseMarker),A
        LD      HL,CmdRun
        LD      A,SHELL_CMD_RUN
        LD      DE,ExpectedRunMain
        CALL    AssertCommand
        JP      C,ProofFailed

        LD      A,4
        LD      (CaseMarker),A
        LD      HL,CmdEditDraw
        LD      A,SHELL_CMD_EDIT
        LD      DE,ExpectedDraw
        CALL    AssertCommand
        JP      C,ProofFailed

        LD      A,5
        LD      (CaseMarker),A
        LD      HL,CmdAsmTest
        LD      A,SHELL_CMD_ASM
        LD      DE,ExpectedTest
        CALL    AssertCommand
        JP      C,ProofFailed

        LD      A,6
        LD      (CaseMarker),A
        LD      HL,CmdRunTest
        LD      A,SHELL_CMD_RUN
        LD      DE,ExpectedRunTest
        CALL    AssertCommand
        JP      C,ProofFailed

        LD      A,7
        LD      (CaseMarker),A
        LD      HL,ExpectedMain
        LD      DE,ExpectedMapMain
        CALL    AssertDerivedMap
        JP      C,ProofFailed

        LD      A,8
        LD      (CaseMarker),A
        LD      HL,ExpectedTest
        LD      DE,ExpectedMapTest
        CALL    AssertDerivedMap
        JP      C,ProofFailed

        LD      A,9
        LD      (CaseMarker),A
        LD      HL,CmdBad
        LD      DE,PathOut
        LD      B,PathOutLen
        CALL    ResolveShellCommand
        JP      NC,ProofFailed
        CP      SHELL_ERR_UNKNOWN
        JP      NZ,ProofFailed

        LD      A,10
        LD      (CaseMarker),A
        LD      HL,CmdEasm
        LD      DE,PathOut
        LD      B,PathOutLen
        CALL    ResolveShellCommand
        JP      NC,ProofFailed
        CP      SHELL_ERR_UNKNOWN
        JP      NZ,ProofFailed

        LD      A,11
        LD      (CaseMarker),A
        LD      HL,CmdArun
        LD      DE,PathOut
        LD      B,PathOutLen
        CALL    ResolveShellCommand
        JP      NC,ProofFailed
        CP      SHELL_ERR_UNKNOWN
        JP      NZ,ProofFailed

        LD      A,ProofPass
        LD      (ResultMarker),A
        HALT

ProofFailed:
        OR      ProofFail
        LD      (ResultMarker),A
        HALT

; AssertCommand —
; Resolve one command and compare action plus resolved path.
; Input: HL = command text, A = expected action, DE = expected path
;!      in        A,DE,HL
;!      out       DE,HL,A,carry,zero
;!      clobbers  BC
@AssertCommand:
        LD      (ExpectedAction),A
        LD      (ExpectedPathPtr),DE
        LD      DE,PathOut
        LD      B,PathOutLen
        CALL    ResolveShellCommand
        RET     C

        LD      B,A
        LD      A,(ExpectedAction)
        CP      B
        JR      NZ,AssertCommandBad

        LD      HL,(ExpectedPathPtr)
        LD      DE,PathOut
        CALL    AssertString
        RET

AssertCommandBad:
        SCF
        RET

; AssertDerivedMap —
; Derive a map path from one source path and compare it.
; Input: HL = source path, DE = expected map path
;!      in        DE,HL
;!      out       DE,HL,A,carry,zero,B
;!      clobbers  C
@AssertDerivedMap:
        LD      (ExpectedPathPtr),DE
        LD      DE,PathOut
        LD      B,PathOutLen
        CALL    ShellDeriveBuildMap
        RET     C

        LD      HL,(ExpectedPathPtr)
        LD      DE,PathOut
        CALL    AssertString
        RET

; AssertString —
; Compare two NUL-terminated strings.
; Input: HL = expected, DE = actual
; Output: carry clear on match, carry set on mismatch
;!      in        DE,HL
;!      out       DE,HL,A,carry,zero
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

; Stub LoadProjectConfig for command resolver proof.
;!      in        B,DE
;!      out       DE,HL,A,C,carry,zero
;!      clobbers  B
@LoadProjectConfig:
        LD      HL,ExpectedMain
        LD      C,B

LoadProjectStubLoop:
        LD      A,(HL)
        LD      (DE),A
        INC     HL
        INC     DE
        OR      A
        JR      Z,LoadProjectStubOk
        DEC     C
        JR      NZ,LoadProjectStubLoop
        LD      A,SHELL_ERR_LONG
        SCF
        RET

LoadProjectStubOk:
        XOR     A
        RET

        .include "../../src/shell-commands.asm"

CmdEdit:
        .db     "edit",0

CmdAsm:
        .db     "asm",0

CmdRun:
        .db     "run",0

CmdEditDraw:
        .db     "edit draw",0

CmdAsmTest:
        .db     "asm test",0

CmdRunTest:
        .db     "run /build/test.bin",0

CmdBad:
        .db     "list",0

CmdEasm:
        .db     "easm",0

CmdArun:
        .db     "arun",0

ExpectedMain:
        .db     "/src/test.v1.asm",0

ExpectedRunMain:
        .db     "/build/test.v1.bin",0

ExpectedMapMain:
        .db     "/build/test.v1.map",0

ExpectedDraw:
        .db     "/src/draw.asm",0

ExpectedTest:
        .db     "/src/test.asm",0

ExpectedRunTest:
        .db     "/build/test.bin",0

ExpectedMapTest:
        .db     "/build/test.map",0

ExpectedAction:
        .db     0

ExpectedPathPtr:
        .dw     0

ResultMarker:
        .db     0

CaseMarker:
        .db     0

PathOut:
        .ds     PathOutLen
