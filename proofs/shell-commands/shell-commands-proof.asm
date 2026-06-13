; Shell command resolver proof.
;
; Runs in the plain Debug80 Z80 runtime. LoadProjectConfig is stubbed here so
; the proof exercises command parsing and path resolution without MON3 storage.

        .org    0x4000

        .include "../../src/tecm8-equates.asm"

PROOF_PASS       .equ     0x42
PROOF_FAIL       .equ     0xE0
PATH_OUT_LEN      .equ     64

;! out carry,zero
;! clobbers A,BC,DE,HL
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
        LD      HL,CmdInputEditCr
        LD      C,CMD_INPUT_EDIT_CR_LEN
        LD      DE,CmdEdit
        LD      A,SHELL_CMD_EDIT
        CALL    AssertShellInputOk
        JP      C,ProofFailed

        LD      A,35
        LD      (CaseMarker),A
        LD      HL,CmdInputAsmLf
        LD      C,CMD_INPUT_ASM_LF_LEN
        LD      DE,CmdAsmTest
        LD      A,SHELL_CMD_ASM
        CALL    AssertShellInputOk
        JP      C,ProofFailed

        LD      A,36
        LD      (CaseMarker),A
        LD      HL,CmdInputBadCr
        LD      C,CMD_INPUT_BAD_CR_LEN
        LD      A,SHELL_ERR_UNKNOWN
        CALL    AssertShellInputErr
        JP      C,ProofFailed

        LD      A,37
        LD      (CaseMarker),A
        LD      HL,CmdInputMaxRun
        LD      C,CMD_INPUT_MAX_RUN_LEN
        LD      DE,CmdInputMaxRun
        LD      A,SHELL_CMD_RUN
        CALL    AssertShellInputOk
        JP      C,ProofFailed

        LD      A,38
        LD      (CaseMarker),A
        LD      A,(ShellInputCommand + SHELL_INPUT_LEN - 1)
        OR      A
        JP      NZ,ProofFailed

        LD      A,39
        LD      (CaseMarker),A
        LD      HL,CmdInputLong
        LD      C,CMD_INPUT_LONG_LEN
        LD      A,SHELL_ERR_LONG
        CALL    AssertShellInputErr
        JP      C,ProofFailed

        LD      A,40
        LD      (CaseMarker),A
        LD      HL,CmdInputEditCr
        LD      C,CMD_INPUT_EDIT_CR_LEN
        LD      A,SHELL_CMD_EDIT
        CALL    AssertShellPromptOk
        JP      C,ProofFailed

        LD      A,41
        LD      (CaseMarker),A
        XOR     A
        LD      (ShellLastExecAction),A
        LD      HL,CmdInputBadCr
        LD      C,CMD_INPUT_BAD_CR_LEN
        LD      A,SHELL_ERR_UNKNOWN
        CALL    AssertShellPromptErr
        JP      C,ProofFailed

        LD      A,42
        LD      (CaseMarker),A
        XOR     A
        LD      (ShellLastExecAction),A
        LD      HL,CmdInputLong
        LD      C,CMD_INPUT_LONG_LEN
        LD      A,SHELL_ERR_LONG
        CALL    AssertShellPromptErr
        JP      C,ProofFailed

        LD      A,43
        LD      (CaseMarker),A
        LD      HL,KeyEditText
        LD      C,CMD_EDIT_TEXT_LEN
        LD      DE,CmdEditText
        LD      A,SHELL_CMD_EDIT
        CALL    AssertShellProgramEntryOk
        JP      C,ProofFailed

        LD      A,44
        LD      (CaseMarker),A
        LD      HL,KeyEditBackspace
        LD      C,CMD_EDIT_TEXT_LEN
        LD      DE,CmdEditText
        LD      A,SHELL_CMD_EDIT
        CALL    AssertShellProgramEntryOk
        JP      C,ProofFailed

        LD      A,45
        LD      (CaseMarker),A
        LD      HL,KeyInputMaxRun
        LD      C,CMD_INPUT_MAX_RUN_LEN
        LD      DE,CmdInputMaxRun
        LD      A,SHELL_CMD_RUN
        CALL    AssertShellProgramEntryOk
        JP      C,ProofFailed

        LD      A,46
        LD      (CaseMarker),A
        LD      A,SHELL_CMD_EDIT
        LD      (ShellLastExecAction),A
        LD      HL,KeyBadText
        LD      C,CMD_BAD_TEXT_LEN
        LD      DE,CmdBadText
        LD      A,SHELL_ERR_UNKNOWN
        CALL    AssertShellProgramEntryErr
        JP      C,ProofFailed

        LD      A,47
        LD      (CaseMarker),A
        CALL    AssertShellLineSeedClamped
        JP      C,ProofFailed

        LD      A,48
        LD      (CaseMarker),A
        CALL    AssertShellProgramEntryDefaultCr
        JP      C,ProofFailed

        LD      A,49
        LD      (CaseMarker),A
        LD      HL,CmdBad
        LD      DE,PathOut
        LD      B,PATH_OUT_LEN
        CALL    ResolveShellCommand
        JP      NC,ProofFailed
        CP      SHELL_ERR_UNKNOWN
        JP      NZ,ProofFailed

        LD      A,50
        LD      (CaseMarker),A
        LD      HL,CmdEasm
        LD      DE,PathOut
        LD      B,PATH_OUT_LEN
        CALL    ResolveShellCommand
        JP      NC,ProofFailed
        CP      SHELL_ERR_UNKNOWN
        JP      NZ,ProofFailed

        LD      A,51
        LD      (CaseMarker),A
        LD      HL,CmdArun
        LD      DE,PathOut
        LD      B,PATH_OUT_LEN
        CALL    ResolveShellCommand
        JP      NC,ProofFailed
        CP      SHELL_ERR_UNKNOWN
        JP      NZ,ProofFailed

        LD      A,52
        LD      (CaseMarker),A
        CALL    AssertProjectLoadAtStartup
        JP      C,ProofFailed

        LD      A,53
        LD      (CaseMarker),A
        CALL    AssertExplicitCommandSkipsProjectLoad
        JP      C,ProofFailed

        LD      A,54
        LD      (CaseMarker),A
        CALL    AssertDefaultCommandReloadsAfterFailure
        JP      C,ProofFailed

        LD      A,55
        LD      (CaseMarker),A
        CALL    AssertShellProgramCommandLoop
        JP      C,ProofFailed

        LD      A,56
        LD      (CaseMarker),A
        CALL    AssertShellProgramCyclesInitErr
        JP      C,ProofFailed

        LD      A,57
        LD      (CaseMarker),A
        CALL    AssertShellProgramCyclesPromptErr
        JP      C,ProofFailed

        LD      A,58
        LD      (CaseMarker),A
        CALL    AssertShellProgramCyclesZero
        JP      C,ProofFailed

        LD      A,59
        LD      (CaseMarker),A
        CALL    AssertShellExecLogSaturates
        JP      C,ProofFailed

        LD      A,PROOF_PASS
        LD      (ResultMarker),A
        HALT

ProofFailed:
        OR      PROOF_FAIL
        LD      (ResultMarker),A
        HALT

; AssertCommand —
; Resolve one command and compare action plus resolved path.
; Input: HL = command text, A = expected action, DE = expected path
;! in A,DE,HL
;! out DE,HL,A,carry,zero
;! clobbers BC
@AssertCommand:
        LD      (ExpectedAction),A
        LD      (ExpectedPathPtr),DE
        LD      DE,PathOut
        LD      B,PATH_OUT_LEN
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
;! in BC,DE,HL,IX
;! out DE,HL,A,carry,zero
;! clobbers BC,IX
@AssertAsmRequest:
        LD      (ExpectedPathPtr),DE
        LD      (ExpectedOutputPtr),BC
        LD      (ExpectedMapPtr),IX
        LD      DE,BuildRequest
        LD      B,PATH_OUT_LEN
        CALL    ResolveShellAsmRequest
        RET     C

        LD      HL,(ExpectedPathPtr)
        LD      DE,BuildRequest
        CALL    AssertString
        RET     C

        LD      HL,(ExpectedOutputPtr)
        LD      DE,BuildRequest + PATH_OUT_LEN
        CALL    AssertString
        RET     C

        LD      HL,(ExpectedMapPtr)
        LD      DE,BuildRequest + PATH_OUT_LEN + PATH_OUT_LEN
        CALL    AssertString
        RET

; AssertAsmRequestSyntaxErr —
; Resolve one non-asm command and require an immediate syntax error.
; Input: HL = command text
;! in HL
;! out A,H,carry,zero
;! clobbers BC,DE,L
@AssertAsmRequestSyntaxErr:
        LD      DE,BuildRequest
        LD      B,PATH_OUT_LEN
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
;! in A,DE,HL
;! out DE,HL,A,carry,zero
;! clobbers BC
@AssertRunRequest:
        LD      (ExpectedAction),A
        LD      (ExpectedPathPtr),DE
        LD      DE,RunRequest
        LD      B,PATH_OUT_LEN
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
;! in HL
;! out A,carry,zero
;! clobbers BC,DE,HL
@AssertRunRequestSyntaxErr:
        LD      DE,RunRequest
        LD      B,PATH_OUT_LEN
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
;! in A,DE,HL
;! out DE,HL,A,carry,zero
;! clobbers BC
@AssertEditRequest:
        LD      (ExpectedAction),A
        LD      (ExpectedPathPtr),DE
        LD      DE,EditRequest
        LD      B,PATH_OUT_LEN
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
;! in HL
;! out A,carry,zero
;! clobbers BC,DE,HL
@AssertEditRequestSyntaxErr:
        LD      DE,EditRequest
        LD      B,PATH_OUT_LEN
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
;! in A,B,DE,HL
;! out DE,HL,A,carry,zero
;! clobbers BC
@AssertDispatchModePath:
        LD      (ExpectedAction),A
        LD      A,B
        LD      (ExpectedMode),A
        LD      (ExpectedPathPtr),DE
        LD      DE,DispatchRequest
        LD      B,PATH_OUT_LEN
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
;! in BC,DE,HL,IX
;! out DE,HL,A,carry,zero
;! clobbers BC,IX
@AssertDispatchAsm:
        LD      (ExpectedPathPtr),DE
        LD      (ExpectedOutputPtr),BC
        LD      (ExpectedMapPtr),IX
        LD      DE,DispatchRequest
        LD      B,PATH_OUT_LEN
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
        LD      DE,DispatchRequest + 1 + PATH_OUT_LEN
        CALL    AssertString
        RET     C

        LD      HL,(ExpectedMapPtr)
        LD      DE,DispatchRequest + 1 + PATH_OUT_LEN + PATH_OUT_LEN
        CALL    AssertString
        RET

AssertDispatchAsmBad:
        SCF
        RET

; AssertDispatchUnknownErr —
; Dispatch one unknown command and require SHELL_ERR_UNKNOWN.
; Input: HL = command text
;! in HL
;! out A,carry,zero
;! clobbers BC,DE,HL
@AssertDispatchUnknownErr:
        LD      DE,DispatchRequest
        LD      B,PATH_OUT_LEN
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
;! in A,HL
;! out A,carry,zero
;! clobbers BC,DE,HL
@AssertExecuteDispatch:
        LD      (ExpectedAction),A
        LD      DE,DispatchRequest
        LD      B,PATH_OUT_LEN
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
;! out A,carry,zero
;! clobbers BC,DE,HL
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
;! in A,HL
;! out A,carry,zero
;! clobbers BC,DE,HL
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
;! in HL
;! out A,carry,zero
;! clobbers BC,DE,HL
@AssertShellStepUnknownErr:
        CALL    RunShellCommandLine
        JR      NC,AssertShellStepUnknownBad
        CP      SHELL_ERR_UNKNOWN
        RET     Z

AssertShellStepUnknownBad:
        SCF
        RET

; AssertShellInputOk —
; Normalize one entered line, run it, and verify the command buffer plus stub.
; Input: HL = entered bytes, C = byte count, DE = expected normalized text,
;        A = expected action
;! in A,C,DE,HL
;! out A,carry,zero
;! clobbers BC,DE,HL
@AssertShellInputOk:
        LD      (ExpectedAction),A
        LD      (ExpectedPathPtr),DE
        CALL    RunShellInputLine
        RET     C
        CP      SHELL_OK
        JR      NZ,AssertShellInputBad

        LD      A,(ShellLastExecAction)
        LD      B,A
        LD      A,(ExpectedAction)
        CP      B
        JR      NZ,AssertShellInputBad

        LD      HL,(ExpectedPathPtr)
        LD      DE,ShellInputCommand
        CALL    AssertString
        RET

; AssertShellInputErr —
; Normalize one entered line, run it, and require a specific shell error.
; Input: HL = entered bytes, C = byte count, A = expected error
;! in A,C,HL
;! out A,carry,zero
;! clobbers BC,DE,HL
@AssertShellInputErr:
        LD      (ExpectedAction),A
        CALL    RunShellInputLine
        JR      NC,AssertShellInputBad
        LD      B,A
        LD      A,(ExpectedAction)
        CP      B
        RET     Z

AssertShellInputBad:
        SCF
        RET

; AssertShellPromptOk —
; Run one prompt cycle and require OK status plus invoked stub action.
; Input: HL = entered bytes, C = byte count, A = expected action
;! in A,C,HL
;! out A,carry,zero
;! clobbers BC,DE,HL
@AssertShellPromptOk:
        LD      (ExpectedAction),A
        CALL    RunShellPromptCycle
        JR      C,AssertShellPromptBad
        CP      SHELL_PROMPT_OK
        JR      NZ,AssertShellPromptBad

        LD      A,(ShellPromptStatus)
        CP      SHELL_PROMPT_OK
        JR      NZ,AssertShellPromptBad

        LD      A,(ShellPromptError)
        OR      A
        JR      NZ,AssertShellPromptBad

        LD      A,(ShellLastExecAction)
        LD      B,A
        LD      A,(ExpectedAction)
        CP      B
        RET     Z

AssertShellPromptBad:
        SCF
        RET

; AssertShellPromptErr —
; Run one prompt cycle and require ERROR status plus stored shell error.
; Input: HL = entered bytes, C = byte count, A = expected error
;! in A,C,HL
;! out A,carry,zero
;! clobbers BC,DE,HL
@AssertShellPromptErr:
        LD      (ExpectedAction),A
        CALL    RunShellPromptCycle
        JR      C,AssertShellPromptBad
        CP      SHELL_PROMPT_ERROR
        JR      NZ,AssertShellPromptBad

        LD      A,(ShellPromptStatus)
        CP      SHELL_PROMPT_ERROR
        JR      NZ,AssertShellPromptBad

        LD      A,(ShellPromptError)
        LD      B,A
        LD      A,(ExpectedAction)
        CP      B
        JR      NZ,AssertShellPromptBad

        LD      A,(ShellLastExecAction)
        OR      A
        RET     Z

        JR      AssertShellPromptBad

; AssertShellProgramEntryOk —
; Seed the line-input provider, run entry, and require prompt-ready success.
; Input: HL = key stream, C = expected text length, DE = expected text,
;        A = expected action
;! in A,C,DE,HL
;! out A,carry,zero
;! clobbers BC,DE,HL
@AssertShellProgramEntryOk:
        LD      (ExpectedAction),A
        LD      (ExpectedPathPtr),DE
        LD      A,C
        LD      (ExpectedMode),A
        LD      (ShellKeySeedPtr),HL
        LD      A,0x7F
        LD      (ShellProgramState),A
        LD      (ShellPromptStatus),A
        LD      (ShellPromptError),A
        LD      HL,CmdBad
        LD      C,1
        CALL    RunShellProgramEntry
        JR      C,AssertShellProgramEntryBad
        CP      SHELL_PROGRAM_READY
        JR      NZ,AssertShellProgramEntryBad

        LD      A,(ShellProgramState)
        CP      SHELL_PROGRAM_READY
        JR      NZ,AssertShellProgramEntryBad

        LD      A,(ShellPromptStatus)
        CP      SHELL_PROMPT_OK
        JR      NZ,AssertShellProgramEntryBad

        LD      A,(ShellPromptError)
        OR      A
        JR      NZ,AssertShellProgramEntryBad

        LD      A,(ShellLineBuffer)
        LD      B,A
        LD      A,(ExpectedMode)
        CP      B
        JR      NZ,AssertShellProgramEntryBad

        LD      HL,(ExpectedPathPtr)
        LD      DE,ShellLineBuffer + 1
        LD      A,(ExpectedMode)
        LD      C,A
        CALL    AssertBytes
        JR      C,AssertShellProgramEntryBad

        LD      DE,ShellLineBuffer + 1
        LD      A,(ExpectedMode)
        LD      B,A
        CALL    AddBToDE
        LD      A,(DE)
        CP      0x0D
        JR      NZ,AssertShellProgramEntryBad

        LD      A,(ShellLastExecAction)
        LD      B,A
        LD      A,(ExpectedAction)
        CP      B
        RET     Z

AssertShellProgramEntryBad:
        SCF
        RET

; AssertShellProgramEntryErr —
; Seed the line-input provider, run entry, and require prompt-ready error state.
; Input: HL = key stream, C = expected text length, DE = expected text,
;        A = expected error
;! in A,C,DE,HL
;! out A,carry,zero
;! clobbers BC,DE,HL
@AssertShellProgramEntryErr:
        LD      (ExpectedAction),A
        LD      (ExpectedPathPtr),DE
        LD      A,C
        LD      (ExpectedMode),A
        LD      (ShellKeySeedPtr),HL
        LD      A,0x7F
        LD      (ShellProgramState),A
        LD      (ShellPromptStatus),A
        LD      (ShellPromptError),A
        LD      HL,CmdEdit
        LD      C,1
        CALL    RunShellProgramEntry
        JR      C,AssertShellProgramEntryBad
        CP      SHELL_PROGRAM_READY
        JR      NZ,AssertShellProgramEntryBad

        LD      A,(ShellProgramState)
        CP      SHELL_PROGRAM_READY
        JR      NZ,AssertShellProgramEntryBad

        LD      A,(ShellPromptStatus)
        CP      SHELL_PROMPT_ERROR
        JR      NZ,AssertShellProgramEntryBad

        LD      A,(ShellPromptError)
        LD      B,A
        LD      A,(ExpectedAction)
        CP      B
        JR      NZ,AssertShellProgramEntryBad

        LD      A,(ShellLineBuffer)
        LD      B,A
        LD      A,(ExpectedMode)
        CP      B
        JR      NZ,AssertShellProgramEntryBad

        LD      HL,(ExpectedPathPtr)
        LD      DE,ShellLineBuffer + 1
        LD      A,(ExpectedMode)
        LD      C,A
        CALL    AssertBytes
        JR      C,AssertShellProgramEntryBad

        LD      DE,ShellLineBuffer + 1
        LD      A,(ExpectedMode)
        LD      B,A
        CALL    AddBToDE
        LD      A,(DE)
        CP      0x0D
        JR      NZ,AssertShellProgramEntryBad

        LD      A,(ShellLastExecAction)
        OR      A
        RET     Z

        JR      AssertShellProgramEntryBad

; AssertShellProgramEntryDefaultCr —
; Unseeded input falls back to a default CR key event and returns ready.
;! out A,carry,zero
;! clobbers BC,DE,HL
@AssertShellProgramEntryDefaultCr:
        LD      HL,0
        LD      (ShellKeySeedPtr),HL
        CALL    RunShellProgramEntry
        JR      C,AssertShellProgramEntryDefaultBad
        CP      SHELL_PROGRAM_READY
        JR      NZ,AssertShellProgramEntryDefaultBad

        LD      A,(ShellProgramState)
        CP      SHELL_PROGRAM_READY
        JR      NZ,AssertShellProgramEntryDefaultBad

        LD      A,(ShellLineBuffer)
        OR      A
        JR      NZ,AssertShellProgramEntryDefaultBad

        LD      A,(ShellLineBuffer + 1)
        CP      0x0D
        JR      NZ,AssertShellProgramEntryDefaultBad

        LD      HL,(ShellKeySeedPtr)
        LD      A,H
        OR      L
        JR      NZ,AssertShellProgramEntryDefaultBad

        CALL    RunShellProgramEntry
        JR      C,AssertShellProgramEntryDefaultBad
        CP      SHELL_PROGRAM_READY
        JR      NZ,AssertShellProgramEntryDefaultBad

        LD      A,(ShellLineBuffer)
        OR      A
        JR      NZ,AssertShellProgramEntryDefaultBad

        LD      A,(ShellLineBuffer + 1)
        CP      0x0D
        RET     Z

AssertShellProgramEntryDefaultBad:
        SCF
        RET

; AssertShellLineSeedClamped —
; A too-long edited seed is clamped to the max text length before CR append.
;! out A,carry,zero
;! clobbers BC,DE,HL
@AssertShellLineSeedClamped:
        LD      HL,KeyInputLong
        LD      (ShellKeySeedPtr),HL
        CALL    FillShellLineBuffer

        LD      A,(ShellLineBuffer)
        CP      SHELL_LINE_TEXT_LEN
        JR      NZ,AssertShellLineSeedClampedBad

        LD      A,(ShellLineBuffer + 1 + SHELL_LINE_TEXT_LEN)
        CP      0x0D
        JR      NZ,AssertShellLineSeedClampedBad

        LD      HL,CmdInputLong
        LD      DE,ShellLineBuffer + 1
        LD      C,SHELL_LINE_TEXT_LEN
        CALL    AssertBytes
        JR      C,AssertShellLineSeedClampedBad

        LD      HL,(ShellKeySeedPtr)
        LD      DE,KeyInputLong + CMD_INPUT_LONG_LEN + 1
        OR      A
        SBC     HL,DE
        JR      NZ,AssertShellLineSeedClampedBad
        XOR     A
        RET

AssertShellLineSeedClampedBad:
        SCF
        RET

; AssertProjectLoadAtStartup —
; Program initialization loads /tecm8.prj once, and default resolution reuses
; the cached main path.
;! out A,carry,zero
;! clobbers BC,DE,HL
@AssertProjectLoadAtStartup:
        XOR     A
        LD      (ProjectLoadMode),A
        LD      (ProjectLoadCount),A
        LD      (ShellProjectStatus),A
        CALL    InitShellProgramState
        JR      C,AssertProjectLoadAtStartupBad

        LD      A,(ProjectLoadCount)
        CP      1
        JR      NZ,AssertProjectLoadAtStartupBad

        LD      A,(ShellProjectStatus)
        CP      SHELL_PROJECT_READY
        JR      NZ,AssertProjectLoadAtStartupBad

        LD      HL,ExpectedMain
        LD      DE,ShellMainPath
        CALL    AssertString
        JR      C,AssertProjectLoadAtStartupBad

        LD      HL,CmdEdit
        LD      A,SHELL_CMD_EDIT
        LD      DE,ExpectedMain
        CALL    AssertCommand
        JR      C,AssertProjectLoadAtStartupBad

        LD      A,(ProjectLoadCount)
        CP      1
        RET     Z

AssertProjectLoadAtStartupBad:
        SCF
        RET

; AssertExplicitCommandSkipsProjectLoad —
; Explicit edit/asm/run targets do not need project config state.
;! out A,carry,zero
;! clobbers BC,DE,HL
@AssertExplicitCommandSkipsProjectLoad:
        LD      A,1
        LD      (ProjectLoadMode),A
        XOR     A
        LD      (ProjectLoadCount),A
        LD      (ShellProjectStatus),A

        LD      HL,CmdEditDraw
        LD      A,SHELL_CMD_EDIT
        LD      DE,ExpectedDraw
        CALL    AssertCommand
        JR      C,AssertExplicitCommandSkipsProjectLoadBad

        LD      HL,CmdAsmTest
        LD      A,SHELL_CMD_ASM
        LD      DE,ExpectedTest
        CALL    AssertCommand
        JR      C,AssertExplicitCommandSkipsProjectLoadBad

        LD      HL,CmdRunTest
        LD      A,SHELL_CMD_RUN
        LD      DE,ExpectedRunTest
        CALL    AssertCommand
        JR      C,AssertExplicitCommandSkipsProjectLoadBad

        LD      A,(ProjectLoadCount)
        OR      A
        JR      NZ,AssertExplicitCommandSkipsProjectLoadBad
        XOR     A
        RET

AssertExplicitCommandSkipsProjectLoadBad:
        SCF
        RET

; AssertDefaultCommandReloadsAfterFailure —
; A default command fails when /tecm8.prj cannot be loaded, then retries and
; recovers after the project config becomes readable.
;! out A,carry,zero
;! clobbers BC,DE,HL
@AssertDefaultCommandReloadsAfterFailure:
        LD      A,1
        LD      (ProjectLoadMode),A
        XOR     A
        LD      (ProjectLoadCount),A
        LD      (ShellProjectStatus),A

        LD      HL,CmdEdit
        LD      DE,PathOut
        LD      B,PATH_OUT_LEN
        CALL    ResolveShellCommand
        JR      NC,AssertDefaultCommandReloadsAfterFailureBad
        CP      SHELL_ERR_PROJECT
        JR      NZ,AssertDefaultCommandReloadsAfterFailureBad

        LD      A,(ProjectLoadCount)
        CP      1
        JR      NZ,AssertDefaultCommandReloadsAfterFailureBad

        LD      A,(ShellProjectStatus)
        CP      SHELL_PROJECT_ERROR
        JR      NZ,AssertDefaultCommandReloadsAfterFailureBad

        XOR     A
        LD      (ProjectLoadMode),A
        LD      HL,CmdEdit
        LD      A,SHELL_CMD_EDIT
        LD      DE,ExpectedMain
        CALL    AssertCommand
        JR      C,AssertDefaultCommandReloadsAfterFailureBad

        LD      A,(ProjectLoadCount)
        CP      2
        JR      NZ,AssertDefaultCommandReloadsAfterFailureBad

        LD      A,(ShellProjectStatus)
        CP      SHELL_PROJECT_READY
        JR      NZ,AssertDefaultCommandReloadsAfterFailureBad

        RET

AssertDefaultCommandReloadsAfterFailureBad:
        SCF
        RET

; AssertShellProgramCommandLoop —
; Run edit, asm, and run through one initialized shell session.
;! out A,carry,zero
;! clobbers BC,DE,HL
@AssertShellProgramCommandLoop:
        XOR     A
        LD      (ProjectLoadMode),A
        LD      (ProjectLoadCount),A
        LD      HL,KeyEditAsmRun
        LD      (ShellKeySeedPtr),HL
        LD      B,3
        CALL    RunShellProgramCycles
        JR      C,AssertShellProgramCommandLoopBad
        CP      SHELL_PROGRAM_READY
        JR      NZ,AssertShellProgramCommandLoopBad

        LD      A,(ShellProgramState)
        CP      SHELL_PROGRAM_READY
        JR      NZ,AssertShellProgramCommandLoopBad

        LD      A,(ShellPromptStatus)
        CP      SHELL_PROMPT_OK
        JR      NZ,AssertShellProgramCommandLoopBad

        LD      A,(ShellPromptError)
        OR      A
        JR      NZ,AssertShellProgramCommandLoopBad

        LD      A,(ProjectLoadCount)
        CP      1
        JR      NZ,AssertShellProgramCommandLoopBad

        LD      A,(ShellExecCount)
        CP      3
        JR      NZ,AssertShellProgramCommandLoopBad

        LD      A,(ShellExecActionLog)
        CP      SHELL_CMD_EDIT
        JR      NZ,AssertShellProgramCommandLoopBad

        LD      A,(ShellExecActionLog + 1)
        CP      SHELL_CMD_ASM
        JR      NZ,AssertShellProgramCommandLoopBad

        LD      A,(ShellExecActionLog + 2)
        CP      SHELL_CMD_RUN
        JR      NZ,AssertShellProgramCommandLoopBad

        LD      A,(ShellLastExecAction)
        CP      SHELL_CMD_RUN
        JR      NZ,AssertShellProgramCommandLoopBad

        LD      HL,(ShellKeySeedPtr)
        LD      DE,KeyEditAsmRunEnd
        OR      A
        SBC     HL,DE
        JR      NZ,AssertShellProgramCommandLoopBad

        XOR     A
        RET

AssertShellProgramCommandLoopBad:
        SCF
        RET

; AssertShellProgramCyclesInitErr —
; A project-config failure at shell startup is visible to the bounded loop.
;! out A,carry,zero
;! clobbers BC,DE,HL
@AssertShellProgramCyclesInitErr:
        LD      A,1
        LD      (ProjectLoadMode),A
        XOR     A
        LD      (ProjectLoadCount),A
        LD      HL,KeyEditAsmRun
        LD      (ShellKeySeedPtr),HL
        LD      B,3
        CALL    RunShellProgramCycles
        JR      NC,AssertShellProgramCyclesInitBad
        CP      SHELL_ERR_PROJECT
        JR      NZ,AssertShellProgramCyclesInitBad
        LD      A,(ProjectLoadCount)
        CP      1
        JR      NZ,AssertShellProgramCyclesInitBad
        LD      A,(ShellProjectStatus)
        CP      SHELL_PROJECT_ERROR
        RET     Z

AssertShellProgramCyclesInitBad:
        SCF
        RET

; AssertShellProgramCyclesPromptErr —
; The bounded loop stops on a prompt-level command error.
;! out A,carry,zero
;! clobbers BC,DE,HL
@AssertShellProgramCyclesPromptErr:
        XOR     A
        LD      (ProjectLoadMode),A
        LD      (ProjectLoadCount),A
        LD      HL,KeyEditBadRun
        LD      (ShellKeySeedPtr),HL
        LD      B,3
        CALL    RunShellProgramCycles
        JR      NC,AssertShellProgramCyclesPromptBad
        CP      SHELL_ERR_UNKNOWN
        JR      NZ,AssertShellProgramCyclesPromptBad
        LD      A,(ShellProgramState)
        CP      SHELL_PROGRAM_READY
        JR      NZ,AssertShellProgramCyclesPromptBad
        LD      A,(ShellPromptStatus)
        CP      SHELL_PROMPT_ERROR
        JR      NZ,AssertShellProgramCyclesPromptBad
        LD      A,(ShellExecCount)
        CP      1
        JR      NZ,AssertShellProgramCyclesPromptBad
        LD      A,(ShellExecActionLog)
        CP      SHELL_CMD_EDIT
        JR      NZ,AssertShellProgramCyclesPromptBad
        LD      HL,(ShellKeySeedPtr)
        LD      DE,KeyEditBadRunAfterBad
        OR      A
        SBC     HL,DE
        JR      NZ,AssertShellProgramCyclesPromptBad
        XOR     A
        RET

AssertShellProgramCyclesPromptBad:
        SCF
        RET

; AssertShellProgramCyclesZero —
; Zero requested cycles initializes and returns ready without consuming input.
;! out A,carry,zero
;! clobbers BC,DE,HL
@AssertShellProgramCyclesZero:
        XOR     A
        LD      (ProjectLoadMode),A
        LD      (ProjectLoadCount),A
        LD      HL,KeyEditAsmRun
        LD      (ShellKeySeedPtr),HL
        LD      B,0
        CALL    RunShellProgramCycles
        JR      C,AssertShellProgramCyclesZeroBad
        CP      SHELL_PROGRAM_READY
        JR      NZ,AssertShellProgramCyclesZeroBad
        LD      A,(ProjectLoadCount)
        CP      1
        JR      NZ,AssertShellProgramCyclesZeroBad
        LD      A,(ShellExecCount)
        OR      A
        JR      NZ,AssertShellProgramCyclesZeroBad
        LD      HL,(ShellKeySeedPtr)
        LD      DE,KeyEditAsmRun
        OR      A
        SBC     HL,DE
        JR      NZ,AssertShellProgramCyclesZeroBad
        XOR     A
        RET

AssertShellProgramCyclesZeroBad:
        SCF
        RET

; AssertShellExecLogSaturates —
; More executor calls than the action log can hold do not grow the count past
; the bounded log capacity.
;! out A,carry,zero
;! clobbers BC,DE,HL
@AssertShellExecLogSaturates:
        XOR     A
        LD      (ShellExecCount),A
        LD      A,SHELL_EXEC_LOG_LEN + 2
        LD      (ExpectedMode),A

AssertShellExecLogSaturatesLoop:
        LD      A,SHELL_CMD_RUN
        CALL    ShellRecordExecAction
        LD      A,(ExpectedMode)
        DEC     A
        LD      (ExpectedMode),A
        JR      NZ,AssertShellExecLogSaturatesLoop

        LD      A,(ShellExecCount)
        CP      SHELL_EXEC_LOG_LEN
        JR      NZ,AssertShellExecLogSaturatesBad
        LD      A,(ShellExecActionLog)
        CP      SHELL_CMD_RUN
        JR      NZ,AssertShellExecLogSaturatesBad
        LD      A,(ShellExecActionLog + SHELL_EXEC_LOG_LEN - 1)
        CP      SHELL_CMD_RUN
        JR      NZ,AssertShellExecLogSaturatesBad
        XOR     A
        RET

AssertShellExecLogSaturatesBad:
        SCF
        RET

; AssertDerivedMap —
; Derive a map path from one source path and compare it.
; Input: HL = source path, DE = expected map path
;! in DE,HL
;! out DE,HL,A,carry,zero,B
;! clobbers C
@AssertDerivedMap:
        LD      (ExpectedPathPtr),DE
        LD      DE,PathOut
        LD      B,PATH_OUT_LEN
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
;! in DE,HL
;! out DE,HL,A,carry,zero
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

; AssertBytes —
; Compare C bytes from HL to DE.
; Input: HL = expected, DE = actual, C = byte count
;! in C,DE,HL
;! out A,C,DE,HL,carry,zero
@AssertBytes:
        LD      A,C
        OR      A
        RET     Z
        LD      A,(DE)
        CP      (HL)
        JR      NZ,AssertBytesBad
        INC     DE
        INC     HL
        DEC     C
        JR      AssertBytes

AssertBytesBad:
        SCF
        RET

; AddBToDE —
; Add unsigned B to DE for proof assertions.
;! in B,DE
;! out DE,A,carry,zero
;! clobbers HL
@AddBToDE:
        LD      H,0
        LD      L,B
        ADD     HL,DE
        JR      C,AddBToDEBad
        LD      D,H
        LD      E,L
        XOR     A
        RET

AddBToDEBad:
        SCF
        RET

; Stub LoadProjectConfig for command resolver proof.
;! in B,DE
;! out DE,HL,A,C,carry,zero
;! clobbers B
@LoadProjectConfig:
        LD      A,(ProjectLoadCount)
        INC     A
        LD      (ProjectLoadCount),A
        LD      A,(ProjectLoadMode)
        OR      A
        JR      Z,LoadProjectStubCopy
        LD      A,SHELL_ERR_PROJECT
        SCF
        RET

LoadProjectStubCopy:
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

        .include "../../src/tecm8-string.asm"
        .include "../../src/shell-commands.asm"

CmdEdit:
        .db     "edit",0

CmdAsm:
        .db     "asm",0

CmdRun:
        .db     "run",0

KeyEditText:
        .db     "edit",0x0D

KeyEditBackspace:
        .db     "edix",0x08,"t",0x0D

KeyEditAsmRun:
        .db     "edit",0x0D
        .db     "asm",0x0D
        .db     "run",0x0D
KeyEditAsmRunEnd:

KeyEditBadRun:
        .db     "edit",0x0D
        .db     "list",0x0D
KeyEditBadRunAfterBad:
        .db     "run",0x0D

CmdEditText:
        .db     "edit"
CMD_EDIT_TEXT_LEN .equ       4

KeyBadText:
        .db     "list",0x0D

CmdBadText:
        .db     "list"
CMD_BAD_TEXT_LEN .equ        4

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

CmdInputEditCr:
        .db     "edit",0x0D,"ignored",0
CMD_INPUT_EDIT_CR_LEN .equ     12

CmdInputAsmLf:
        .db     "asm test",0x0A,"ignored",0
CMD_INPUT_ASM_LF_LEN .equ      16

CmdInputBadCr:
        .db     "list",0x0D,0
CMD_INPUT_BAD_CR_LEN .equ      5

CmdInputMaxRun:
        .db     "run /build/abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGHIJKL.bin",0
CMD_INPUT_MAX_RUN_LEN .equ     63

KeyInputMaxRun:
        .db     "run /build/abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGHIJKL.bin",0x0D

CmdInputLong:
        .db     "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
        .db     "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
CMD_INPUT_LONG_LEN .equ       64

KeyInputLong:
        .db     "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
        .db     "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",0x0D

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

ProjectLoadMode:
        .db     0

ProjectLoadCount:
        .db     0

ResultMarker:
        .db     0

CaseMarker:
        .db     0

PathOut:
        .ds     PATH_OUT_LEN

BuildRequest:
        .ds     PATH_OUT_LEN * 3

RunRequest:
        .ds     PATH_OUT_LEN + 1

EditRequest:
        .ds     PATH_OUT_LEN + 1

DispatchRequest:
        .ds     1 + PATH_OUT_LEN * 3
