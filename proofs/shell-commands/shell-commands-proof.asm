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
        LD      HL,CmdAsm
        LD      DE,ExpectedMain
        LD      BC,ExpectedRunMain
        LD      IX,ExpectedMapMain
        CALL    AssertAsmRequest
        JP      C,ProofFailed

        LD      A,10
        LD      (CaseMarker),A
        LD      HL,CmdAsmTest
        LD      DE,ExpectedTest
        LD      BC,ExpectedRunTest
        LD      IX,ExpectedMapTest
        CALL    AssertAsmRequest
        JP      C,ProofFailed

        LD      A,11
        LD      (CaseMarker),A
        LD      HL,CmdEdit
        CALL    AssertAsmRequestSyntaxErr
        JP      C,ProofFailed

        LD      A,12
        LD      (CaseMarker),A
        LD      HL,CmdRun
        CALL    AssertAsmRequestSyntaxErr
        JP      C,ProofFailed

        LD      A,13
        LD      (CaseMarker),A
        LD      HL,CmdRun
        LD      A,SHELL_RUN_DEFAULT
        LD      DE,ExpectedRunMain
        CALL    AssertRunRequest
        JP      C,ProofFailed

        LD      A,14
        LD      (CaseMarker),A
        LD      HL,CmdRunTest
        LD      A,SHELL_RUN_EXPLICIT
        LD      DE,ExpectedRunTest
        CALL    AssertRunRequest
        JP      C,ProofFailed

        LD      A,15
        LD      (CaseMarker),A
        LD      HL,CmdEdit
        CALL    AssertRunRequestSyntaxErr
        JP      C,ProofFailed

        LD      A,16
        LD      (CaseMarker),A
        LD      HL,CmdAsm
        CALL    AssertRunRequestSyntaxErr
        JP      C,ProofFailed

        LD      A,17
        LD      (CaseMarker),A
        LD      HL,CmdEdit
        LD      A,SHELL_EDIT_DEFAULT
        LD      DE,ExpectedMain
        CALL    AssertEditRequest
        JP      C,ProofFailed

        LD      A,18
        LD      (CaseMarker),A
        LD      HL,CmdEditDraw
        LD      A,SHELL_EDIT_EXPLICIT
        LD      DE,ExpectedDraw
        CALL    AssertEditRequest
        JP      C,ProofFailed

        LD      A,19
        LD      (CaseMarker),A
        LD      HL,CmdEditDrawZ80
        LD      A,SHELL_EDIT_EXPLICIT
        LD      DE,ExpectedDrawZ80
        CALL    AssertEditRequest
        JP      C,ProofFailed

        LD      A,20
        LD      (CaseMarker),A
        LD      HL,CmdAsm
        CALL    AssertEditRequestSyntaxErr
        JP      C,ProofFailed

        LD      A,21
        LD      (CaseMarker),A
        LD      HL,CmdRun
        CALL    AssertEditRequestSyntaxErr
        JP      C,ProofFailed

        LD      A,22
        LD      (CaseMarker),A
        LD      HL,CmdEdit
        LD      A,SHELL_CMD_EDIT
        LD      B,SHELL_EDIT_DEFAULT
        LD      DE,ExpectedMain
        CALL    AssertDispatchModePath
        JP      C,ProofFailed

        LD      A,23
        LD      (CaseMarker),A
        LD      HL,CmdRunTest
        LD      A,SHELL_CMD_RUN
        LD      B,SHELL_RUN_EXPLICIT
        LD      DE,ExpectedRunTest
        CALL    AssertDispatchModePath
        JP      C,ProofFailed

        LD      A,24
        LD      (CaseMarker),A
        LD      HL,CmdAsmTest
        LD      DE,ExpectedTest
        LD      BC,ExpectedRunTest
        LD      IX,ExpectedMapTest
        CALL    AssertDispatchAsm
        JP      C,ProofFailed

        LD      A,25
        LD      (CaseMarker),A
        LD      HL,CmdBad
        CALL    AssertDispatchUnknownErr
        JP      C,ProofFailed

        LD      A,26
        LD      (CaseMarker),A
        LD      HL,CmdEdit
        LD      A,SHELL_CMD_EDIT
        CALL    AssertExecuteDispatch
        JP      C,ProofFailed

        LD      A,27
        LD      (CaseMarker),A
        LD      HL,CmdAsmTest
        LD      A,SHELL_CMD_ASM
        CALL    AssertExecuteDispatch
        JP      C,ProofFailed

        LD      A,28
        LD      (CaseMarker),A
        LD      HL,CmdRunTest
        LD      A,SHELL_CMD_RUN
        CALL    AssertExecuteDispatch
        JP      C,ProofFailed

        LD      A,29
        LD      (CaseMarker),A
        CALL    AssertExecuteDispatchUnknownErr
        JP      C,ProofFailed

        LD      A,30
        LD      (CaseMarker),A
        LD      HL,CmdEdit
        LD      A,SHELL_CMD_EDIT
        CALL    AssertShellStepOk
        JP      C,ProofFailed

        LD      A,31
        LD      (CaseMarker),A
        LD      HL,CmdAsmTest
        LD      A,SHELL_CMD_ASM
        CALL    AssertShellStepOk
        JP      C,ProofFailed

        LD      A,32
        LD      (CaseMarker),A
        LD      HL,CmdRunTest
        LD      A,SHELL_CMD_RUN
        CALL    AssertShellStepOk
        JP      C,ProofFailed

        LD      A,33
        LD      (CaseMarker),A
        LD      HL,CmdBad
        CALL    AssertShellStepUnknownErr
        JP      C,ProofFailed

        LD      A,34
        LD      (CaseMarker),A
        LD      HL,CmdBad
        LD      DE,PathOut
        LD      B,PathOutLen
        CALL    ResolveShellCommand
        JP      NC,ProofFailed
        CP      SHELL_ERR_UNKNOWN
        JP      NZ,ProofFailed

        LD      A,35
        LD      (CaseMarker),A
        LD      HL,CmdEasm
        LD      DE,PathOut
        LD      B,PathOutLen
        CALL    ResolveShellCommand
        JP      NC,ProofFailed
        CP      SHELL_ERR_UNKNOWN
        JP      NZ,ProofFailed

        LD      A,36
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

; AssertAsmRequest —
; Resolve one asm command and compare source, output, and map paths.
; Input: HL = command text, DE = expected source, BC = expected output,
;        IX = expected map
;!      in        BC,DE,HL,IX
;!      out       DE,HL,A,carry,zero
;!      clobbers  BC,IX
@AssertAsmRequest:
        LD      (ExpectedPathPtr),DE
        LD      (ExpectedOutputPtr),BC
        LD      (ExpectedMapPtr),IX
        LD      DE,BuildRequest
        LD      B,PathOutLen
        CALL    ResolveShellAsmRequest
        RET     C

        LD      HL,(ExpectedPathPtr)
        LD      DE,BuildRequest
        CALL    AssertString
        RET     C

        LD      HL,(ExpectedOutputPtr)
        LD      DE,BuildRequest + PathOutLen
        CALL    AssertString
        RET     C

        LD      HL,(ExpectedMapPtr)
        LD      DE,BuildRequest + PathOutLen + PathOutLen
        CALL    AssertString
        RET

; AssertAsmRequestSyntaxErr —
; Resolve one non-asm command and require an immediate syntax error.
; Input: HL = command text
;!      in        HL
;!      out       A,H,carry,zero
;!      clobbers  BC,DE,L
@AssertAsmRequestSyntaxErr:
        LD      DE,BuildRequest
        LD      B,PathOutLen
        CALL    ResolveShellAsmRequest
        JR      NC,AssertAsmRequestSyntaxBad
        CP      SHELL_ERR_SYNTAX
        RET     Z

AssertAsmRequestSyntaxBad:
        SCF
        RET

; AssertRunRequest —
; Resolve one run command and compare mode plus runnable path.
; Input: HL = command text, A = expected mode, DE = expected path
;!      in        A,DE,HL
;!      out       DE,HL,A,carry,zero
;!      clobbers  BC
@AssertRunRequest:
        LD      (ExpectedAction),A
        LD      (ExpectedPathPtr),DE
        LD      DE,RunRequest
        LD      B,PathOutLen
        CALL    ResolveShellRunRequest
        RET     C

        LD      B,A
        LD      A,(ExpectedAction)
        CP      B
        JR      NZ,AssertRunRequestBad

        LD      A,(RunRequest)
        LD      B,A
        LD      A,(ExpectedAction)
        CP      B
        JR      NZ,AssertRunRequestBad

        LD      HL,(ExpectedPathPtr)
        LD      DE,RunRequest + 1
        CALL    AssertString
        RET

AssertRunRequestBad:
        SCF
        RET

; AssertRunRequestSyntaxErr —
; Resolve one non-run command and require an immediate syntax error.
; Input: HL = command text
;!      in        HL
;!      out       A,carry,zero
;!      clobbers  BC,DE,HL
@AssertRunRequestSyntaxErr:
        LD      DE,RunRequest
        LD      B,PathOutLen
        CALL    ResolveShellRunRequest
        JR      NC,AssertRunRequestSyntaxBad
        CP      SHELL_ERR_SYNTAX
        RET     Z

AssertRunRequestSyntaxBad:
        SCF
        RET

; AssertEditRequest —
; Resolve one edit command and compare mode plus source path.
; Input: HL = command text, A = expected mode, DE = expected path
;!      in        A,DE,HL
;!      out       DE,HL,A,carry,zero
;!      clobbers  BC
@AssertEditRequest:
        LD      (ExpectedAction),A
        LD      (ExpectedPathPtr),DE
        LD      DE,EditRequest
        LD      B,PathOutLen
        CALL    ResolveShellEditRequest
        RET     C

        LD      B,A
        LD      A,(ExpectedAction)
        CP      B
        JR      NZ,AssertEditRequestBad

        LD      A,(EditRequest)
        LD      B,A
        LD      A,(ExpectedAction)
        CP      B
        JR      NZ,AssertEditRequestBad

        LD      HL,(ExpectedPathPtr)
        LD      DE,EditRequest + 1
        CALL    AssertString
        RET

AssertEditRequestBad:
        SCF
        RET

; AssertEditRequestSyntaxErr —
; Resolve one non-edit command and require an immediate syntax error.
; Input: HL = command text
;!      in        HL
;!      out       A,carry,zero
;!      clobbers  BC,DE,HL
@AssertEditRequestSyntaxErr:
        LD      DE,EditRequest
        LD      B,PathOutLen
        CALL    ResolveShellEditRequest
        JR      NC,AssertEditRequestSyntaxBad
        CP      SHELL_ERR_SYNTAX
        RET     Z

AssertEditRequestSyntaxBad:
        SCF
        RET

; AssertDispatchModePath —
; Dispatch edit/run and compare action, mode, and single path payload.
; Input: HL = command text, A = expected action, B = expected mode,
;        DE = expected path
;!      in        A,B,DE,HL
;!      out       DE,HL,A,carry,zero
;!      clobbers  BC
@AssertDispatchModePath:
        LD      (ExpectedAction),A
        LD      A,B
        LD      (ExpectedMode),A
        LD      (ExpectedPathPtr),DE
        LD      DE,DispatchRequest
        LD      B,PathOutLen
        CALL    DispatchShellCommand
        RET     C

        LD      B,A
        LD      A,(ExpectedAction)
        CP      B
        JR      NZ,AssertDispatchModePathBad

        LD      A,(DispatchRequest)
        LD      B,A
        LD      A,(ExpectedAction)
        CP      B
        JR      NZ,AssertDispatchModePathBad

        LD      A,(DispatchRequest + 1)
        LD      B,A
        LD      A,(ExpectedMode)
        CP      B
        JR      NZ,AssertDispatchModePathBad

        LD      HL,(ExpectedPathPtr)
        LD      DE,DispatchRequest + 2
        CALL    AssertString
        RET

AssertDispatchModePathBad:
        SCF
        RET

; AssertDispatchAsm —
; Dispatch asm and compare action, source, output, and map payload paths.
; Input: HL = command text, DE = expected source, BC = expected output,
;        IX = expected map
;!      in        BC,DE,HL,IX
;!      out       DE,HL,A,carry,zero
;!      clobbers  BC,IX
@AssertDispatchAsm:
        LD      (ExpectedPathPtr),DE
        LD      (ExpectedOutputPtr),BC
        LD      (ExpectedMapPtr),IX
        LD      DE,DispatchRequest
        LD      B,PathOutLen
        CALL    DispatchShellCommand
        RET     C

        CP      SHELL_CMD_ASM
        JR      NZ,AssertDispatchAsmBad

        LD      A,(DispatchRequest)
        CP      SHELL_CMD_ASM
        JR      NZ,AssertDispatchAsmBad

        LD      HL,(ExpectedPathPtr)
        LD      DE,DispatchRequest + 1
        CALL    AssertString
        RET     C

        LD      HL,(ExpectedOutputPtr)
        LD      DE,DispatchRequest + 1 + PathOutLen
        CALL    AssertString
        RET     C

        LD      HL,(ExpectedMapPtr)
        LD      DE,DispatchRequest + 1 + PathOutLen + PathOutLen
        CALL    AssertString
        RET

AssertDispatchAsmBad:
        SCF
        RET

; AssertDispatchUnknownErr —
; Dispatch one unknown command and require SHELL_ERR_UNKNOWN.
; Input: HL = command text
;!      in        HL
;!      out       A,carry,zero
;!      clobbers  BC,DE,HL
@AssertDispatchUnknownErr:
        LD      DE,DispatchRequest
        LD      B,PathOutLen
        CALL    DispatchShellCommand
        JR      NC,AssertDispatchUnknownBad
        CP      SHELL_ERR_UNKNOWN
        RET     Z

AssertDispatchUnknownBad:
        SCF
        RET

; AssertExecuteDispatch —
; Dispatch a command, execute the dispatch block, and verify the invoked stub.
; Input: HL = command text, A = expected action
;!      in        A,HL
;!      out       A,carry,zero
;!      clobbers  BC,DE,HL
@AssertExecuteDispatch:
        LD      (ExpectedAction),A
        LD      DE,DispatchRequest
        LD      B,PathOutLen
        CALL    DispatchShellCommand
        RET     C

        LD      HL,DispatchRequest
        CALL    ExecuteShellDispatch
        RET     C

        LD      B,A
        LD      A,(ExpectedAction)
        CP      B
        JR      NZ,AssertExecuteDispatchBad

        LD      A,(ShellLastExecAction)
        LD      B,A
        LD      A,(ExpectedAction)
        CP      B
        JR      NZ,AssertExecuteDispatchBad

        LD      HL,(ShellLastExecRequestPtr)
        LD      DE,DispatchRequest + 1
        OR      A
        SBC     HL,DE
        RET     Z

AssertExecuteDispatchBad:
        SCF
        RET

; AssertExecuteDispatchUnknownErr —
; Execute a dispatch block with an invalid action and require unknown-command.
;!      out       A,carry,zero
;!      clobbers  BC,DE,HL
@AssertExecuteDispatchUnknownErr:
        LD      A,SHELL_ERR_UNKNOWN
        LD      (DispatchRequest),A
        LD      HL,DispatchRequest
        CALL    ExecuteShellDispatch
        JR      NC,AssertExecuteDispatchUnknownBad
        CP      SHELL_ERR_UNKNOWN
        RET     Z

AssertExecuteDispatchUnknownBad:
        SCF
        RET

; AssertShellStepOk —
; Run one shell command line and verify status plus invoked stub.
; Input: HL = command text, A = expected action
;!      in        A,HL
;!      out       A,carry,zero
;!      clobbers  BC,DE,HL
@AssertShellStepOk:
        LD      (ExpectedAction),A
        CALL    RunShellCommandLine
        RET     C
        CP      SHELL_OK
        JR      NZ,AssertShellStepBad

        LD      A,(ShellLastExecAction)
        LD      B,A
        LD      A,(ExpectedAction)
        CP      B
        RET     Z

AssertShellStepBad:
        SCF
        RET

; AssertShellStepUnknownErr —
; Run one unknown shell command line and require SHELL_ERR_UNKNOWN.
; Input: HL = command text
;!      in        HL
;!      out       A,carry,zero
;!      clobbers  BC,DE,HL
@AssertShellStepUnknownErr:
        CALL    RunShellCommandLine
        JR      NC,AssertShellStepUnknownBad
        CP      SHELL_ERR_UNKNOWN
        RET     Z

AssertShellStepUnknownBad:
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

CmdEditDrawZ80:
        .db     "edit /src/draw.z80",0

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

ExpectedDrawZ80:
        .db     "/src/draw.z80",0

ExpectedTest:
        .db     "/src/test.asm",0

ExpectedRunTest:
        .db     "/build/test.bin",0

ExpectedMapTest:
        .db     "/build/test.map",0

ExpectedAction:
        .db     0

ExpectedMode:
        .db     0

ExpectedPathPtr:
        .dw     0

ExpectedOutputPtr:
        .dw     0

ExpectedMapPtr:
        .dw     0

ResultMarker:
        .db     0

CaseMarker:
        .db     0

PathOut:
        .ds     PathOutLen

BuildRequest:
        .ds     PathOutLen * 3

RunRequest:
        .ds     PathOutLen + 1

EditRequest:
        .ds     PathOutLen + 1

DispatchRequest:
        .ds     1 + PathOutLen * 3
