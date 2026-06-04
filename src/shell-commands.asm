; TECM8 shell command resolver.
;
; Resolves the first project-centered shell commands into an action code and a
; concrete TM8 path. Tool execution is deliberately not launched here.

SHELL_CMD_EDIT      .equ     0x10
SHELL_CMD_ASM       .equ     0x11
SHELL_CMD_RUN       .equ     0x12

SHELL_EDIT_DEFAULT  .equ     0x18
SHELL_EDIT_EXPLICIT .equ     0x19

SHELL_RUN_DEFAULT   .equ     0x20
SHELL_RUN_EXPLICIT  .equ     0x21

SHELL_OK            .equ     0
SHELL_ERR_UNKNOWN   .equ     0x40
SHELL_ERR_SYNTAX    .equ     0x41
SHELL_ERR_LONG      .equ     0x42
SHELL_ERR_PROJECT   .equ     0x43

SHELL_MAIN_PATH_LEN .equ     64
SHELL_INPUT_LEN     .equ     64
SHELL_LINE_TEXT_LEN .equ     SHELL_INPUT_LEN - 1
SHELL_LINE_BUF_LEN  .equ     SHELL_LINE_TEXT_LEN + 2

SHELL_PROMPT_OK     .equ     0
SHELL_PROMPT_ERROR  .equ     1

SHELL_PROGRAM_READY .equ     0
SHELL_PROGRAM_INPUT .equ     1

; RunShellProgramEntry —
; Minimal shell program skeleton. It initializes prompt-visible state, obtains
; one line from the current input provider, runs one prompt cycle, then returns
; to the prompt-ready state.
; Output:
;   carry clear, A=SHELL_PROGRAM_READY
;!      out       A,carry,zero
;!      clobbers  BC,DE,HL
@RunShellProgramEntry:
        CALL    InitShellProgramState

ShellProgramInput:
        LD      A,SHELL_PROGRAM_INPUT
        LD      (ShellProgramState),A
        CALL    ReadShellInputLine
        CALL    RunShellPromptCycle

ShellProgramPromptReady:
        LD      A,SHELL_PROGRAM_READY
        LD      (ShellProgramState),A
        OR      A
        RET

; InitShellProgramState —
; Clear prompt-visible shell state before entering the input cycle.
;!      out       A,carry,zero
@InitShellProgramState:
        XOR     A
        LD      (ShellProgramState),A
        LD      (ShellPromptStatus),A
        LD      (ShellPromptError),A
        LD      (ShellLastExecAction),A
        LD      (ShellLastExecRequestPtr),A
        LD      (ShellLastExecRequestPtr + 1),A
        RET

; ReadShellInputLine —
; Stubbed input provider. Real TEC input will replace this with keyboard/editor
; input. Buffer layout:
;   +0       edited text length, excluding terminator
;   +1       edited text bytes
;   +1+len   CR terminator
; Output:
;   HL = entered line bytes
;   C  = entered byte count, including the CR terminator
;!      out       C,HL
;!      clobbers  A,B,DE
@ReadShellInputLine:
        CALL    FillShellLineBuffer
        LD      HL,ShellLineBuffer + 1
        LD      A,(ShellLineBuffer)
        INC     A
        LD      C,A
        RET

; FillShellLineBuffer —
; Proof stub for the future TEC editor/input routine. It copies the seeded
; edited text into ShellLineBuffer and appends the CR terminator.
;!      out       A,B,DE,HL
@FillShellLineBuffer:
        LD      HL,(ShellLineSeedPtr)
        LD      DE,ShellLineBuffer + 1
        LD      A,(ShellLineSeedLen)
        CP      SHELL_LINE_TEXT_LEN + 1
        JR      C,ShellLineSeedLenOk
        LD      A,SHELL_LINE_TEXT_LEN

ShellLineSeedLenOk:
        LD      (ShellLineBuffer),A
        LD      B,A
        OR      A
        JR      Z,ShellLineFillTerminator

ShellLineFillLoop:
        LD      A,(HL)
        LD      (DE),A
        INC     HL
        INC     DE
        DEC     B
        JR      NZ,ShellLineFillLoop

ShellLineFillTerminator:
        LD      A,0x0D
        LD      (DE),A
        RET

; RunShellPromptCycle —
; Handle one shell prompt cycle from an already-entered input line.
; The shell returns to the prompt after both success and shell errors; callers
; inspect ShellPromptStatus and ShellPromptError to decide what to display.
; Input:
;   HL = entered line bytes
;   C  = entered byte count
; Output:
;   carry clear, A=SHELL_PROMPT_OK or SHELL_PROMPT_ERROR
;!      in        C,HL
;!      out       A,carry,zero
;!      clobbers  BC,DE,HL
@RunShellPromptCycle:
        CALL    RunShellInputLine
        JR      C,ShellPromptCycleError

        XOR     A
        LD      (ShellPromptError),A
        LD      (ShellPromptStatus),A
        RET

ShellPromptCycleError:
        LD      (ShellPromptError),A
        LD      A,SHELL_PROMPT_ERROR
        LD      (ShellPromptStatus),A
        OR      A
        RET

; RunShellInputLine —
; Normalize entered shell input into a NUL-terminated command line, then run it.
; CR, LF, and NUL terminate the entered line before the supplied byte count.
; Input:
;   HL = entered line bytes
;   C  = entered byte count
; Output:
;   carry clear, A=SHELL_OK after a stub handles the command
;   carry set, A=SHELL_ERR_* if normalization, dispatch, or execution fails
;!      in        C,HL
;!      out       A,carry,zero
;!      clobbers  BC,DE,HL
@RunShellInputLine:
        LD      DE,ShellInputCommand
        LD      B,SHELL_INPUT_LEN
        CALL    NormalizeShellInputLine
        RET     C
        LD      HL,ShellInputCommand
        JP      RunShellCommandLine

; NormalizeShellInputLine —
; Copy an entered input line into a bounded NUL-terminated command buffer.
; Input:
;   HL = entered line bytes
;   C  = entered byte count
;   DE = output command buffer
;   B  = output capacity, including final NUL
; Output:
;   carry clear, A=SHELL_OK, output buffer is NUL-terminated
;   carry set, A=SHELL_ERR_LONG when no byte remains for the final NUL
;!      in        B,C,DE,HL
;!      out       A,carry,zero
;!      clobbers  BC,DE,HL
@NormalizeShellInputLine:
        LD      A,B
        OR      A
        JP      Z,ShellLongErr

ShellNormalizeLoop:
        LD      A,C
        OR      A
        JR      Z,ShellNormalizeEnd
        LD      A,(HL)
        OR      A
        JR      Z,ShellNormalizeEnd
        CP      0x0D
        JR      Z,ShellNormalizeEnd
        CP      0x0A
        JR      Z,ShellNormalizeEnd

        DEC     B
        JP      Z,ShellLongErr
        LD      (DE),A
        INC     HL
        INC     DE
        DEC     C
        JR      ShellNormalizeLoop

ShellNormalizeEnd:
        XOR     A
        LD      (DE),A
        RET

; RunShellCommandLine —
; Execute one already-entered shell command line through the current stubs.
; Input:
;   HL = NUL-terminated command line
; Output:
;   carry clear, A=SHELL_OK after a stub handles the command
;   carry set, A=SHELL_ERR_* if dispatch or execution fails
;!      in        HL
;!      out       A,carry,zero
;!      clobbers  BC,DE,HL
@RunShellCommandLine:
        LD      DE,ShellStepDispatch
        LD      B,SHELL_MAIN_PATH_LEN
        CALL    DispatchShellCommand
        RET     C

        LD      HL,ShellStepDispatch
        CALL    ExecuteShellDispatch
        RET     C
        XOR     A
        RET

; ExecuteShellDispatch —
; Route a populated dispatch block to the current executor entry stub.
; Input:
;   HL = dispatch block from DispatchShellCommand
; Output:
;   carry clear, A=SHELL_CMD_* invoked
;   carry set, A=SHELL_ERR_UNKNOWN for an unsupported dispatch action
;!      in        HL
;!      out       A,carry,zero
;!      clobbers  DE,HL
@ExecuteShellDispatch:
        LD      A,(HL)
        INC     HL
        CP      SHELL_CMD_EDIT
        JR      Z,ShellExecuteEdit
        CP      SHELL_CMD_ASM
        JR      Z,ShellExecuteAsm
        CP      SHELL_CMD_RUN
        JR      Z,ShellExecuteRun
        LD      A,SHELL_ERR_UNKNOWN
        SCF
        RET

ShellExecuteEdit:
        JP      ShellExecEditor

ShellExecuteAsm:
        JP      ShellExecAssembler

ShellExecuteRun:
        JP      ShellExecRunner

; ShellExecEditor —
; Stub editor entry point. HL points at edit payload: mode byte, then path.
;!      in        HL
;!      out       A,carry,zero
@ShellExecEditor:
        LD      (ShellLastExecRequestPtr),HL
        LD      A,SHELL_CMD_EDIT
        LD      (ShellLastExecAction),A
        OR      A
        RET

; ShellExecAssembler —
; Stub assembler entry point. HL points at asm payload: source, output, map.
;!      in        HL
;!      out       A,carry,zero
@ShellExecAssembler:
        LD      (ShellLastExecRequestPtr),HL
        LD      A,SHELL_CMD_ASM
        LD      (ShellLastExecAction),A
        OR      A
        RET

; ShellExecRunner —
; Stub runner entry point. HL points at run payload: mode byte, then path.
;!      in        HL
;!      out       A,carry,zero
@ShellExecRunner:
        LD      (ShellLastExecRequestPtr),HL
        LD      A,SHELL_CMD_RUN
        LD      (ShellLastExecAction),A
        OR      A
        RET

; DispatchShellCommand —
; Resolve a shell command into the executor-facing dispatch block:
;   +0       action, SHELL_CMD_EDIT/SHELL_CMD_ASM/SHELL_CMD_RUN
;   +1       action-specific request payload
;            edit/run: mode byte followed by one path slot
;            asm:      source, output, and map path slots
; Input:
;   HL = NUL-terminated command line
;   DE = dispatch block
;   B  = per-path capacity, including final NUL
; Output:
;   carry clear, A=SHELL_CMD_*, dispatch block is populated
;   carry set, A=SHELL_ERR_* or project loader error
;!      in        B,DE,HL
;!      out       A,carry,zero
;!      clobbers  BC,DE,HL
@DispatchShellCommand:
        LD      (ShellDispatchPtr),DE
        LD      (ShellDispatchCommandPtr),HL
        LD      A,B
        LD      (ShellOutCap),A

        INC     DE
        CALL    ResolveShellCommand
        RET     C

        CP      SHELL_CMD_EDIT
        JR      Z,ShellDispatchEdit
        CP      SHELL_CMD_ASM
        JR      Z,ShellDispatchAsm
        CP      SHELL_CMD_RUN
        JR      Z,ShellDispatchRun
        LD      A,SHELL_ERR_UNKNOWN
        SCF
        RET

ShellDispatchEdit:
        LD      DE,(ShellDispatchPtr)
        INC     DE
        LD      HL,(ShellDispatchCommandPtr)
        LD      A,(ShellOutCap)
        LD      B,A
        CALL    ResolveShellEditRequest
        RET     C
        LD      A,SHELL_CMD_EDIT
        JR      ShellDispatchOk

ShellDispatchAsm:
        LD      DE,(ShellDispatchPtr)
        INC     DE
        LD      HL,(ShellDispatchCommandPtr)
        LD      A,(ShellOutCap)
        LD      B,A
        CALL    ResolveShellAsmRequest
        RET     C
        LD      A,SHELL_CMD_ASM
        JR      ShellDispatchOk

ShellDispatchRun:
        LD      DE,(ShellDispatchPtr)
        INC     DE
        LD      HL,(ShellDispatchCommandPtr)
        LD      A,(ShellOutCap)
        LD      B,A
        CALL    ResolveShellRunRequest
        RET     C
        LD      A,SHELL_CMD_RUN

ShellDispatchOk:
        LD      HL,(ShellDispatchPtr)
        LD      (HL),A
        RET

; ResolveShellEditRequest —
; Resolve an edit command into an editor request block:
;   +0       edit mode, SHELL_EDIT_DEFAULT or SHELL_EDIT_EXPLICIT
;   +1       source path
; Input:
;   HL = NUL-terminated edit command line
;   DE = request block with one mode byte followed by one path slot
;   B  = path capacity, including final NUL
; Output:
;   carry clear, A=edit mode, request path is NUL-terminated
;   carry set, A=SHELL_ERR_* or project loader error
;!      in        B,DE,HL
;!      out       carry,A,zero
;!      clobbers  BC,DE,HL
@ResolveShellEditRequest:
        LD      (ShellRequestPtr),DE
        LD      A,B
        LD      (ShellOutCap),A
        CALL    ShellSkipSpaces
        LD      (ShellRequestCommandPtr),HL
        LD      DE,ShellEditText
        CALL    ShellMatchCommand
        JR      NC,ShellEditRequestCommandOk
        LD      A,SHELL_ERR_SYNTAX
        SCF
        RET

ShellEditRequestCommandOk:
        CALL    ShellSkipSpaces
        LD      A,(HL)
        OR      A
        JR      Z,ShellEditRequestDefault
        LD      A,SHELL_EDIT_EXPLICIT
        JR      ShellEditRequestResolve

ShellEditRequestDefault:
        LD      A,SHELL_EDIT_DEFAULT

ShellEditRequestResolve:
        LD      (ShellEditMode),A
        LD      DE,(ShellRequestPtr)
        INC     DE
        LD      HL,(ShellRequestCommandPtr)
        LD      A,(ShellOutCap)
        LD      B,A
        CALL    ResolveShellCommand
        RET     C
        CP      SHELL_CMD_EDIT
        JR      Z,ShellEditRequestOk
        LD      A,SHELL_ERR_SYNTAX
        SCF
        RET

ShellEditRequestOk:
        LD      HL,(ShellRequestPtr)
        LD      A,(ShellEditMode)
        LD      (HL),A
        RET

; ResolveShellRunRequest —
; Resolve a run command into a launch request block:
;   +0       run mode, SHELL_RUN_DEFAULT or SHELL_RUN_EXPLICIT
;   +1       runnable path
; Input:
;   HL = NUL-terminated run command line
;   DE = request block with one mode byte followed by one path slot
;   B  = path capacity, including final NUL
; Output:
;   carry clear, A=run mode, request path is NUL-terminated
;   carry set, A=SHELL_ERR_* or project loader error
;!      in        B,DE,HL
;!      out       carry,A,zero
;!      clobbers  BC,DE,HL
@ResolveShellRunRequest:
        LD      (ShellRequestPtr),DE
        LD      A,B
        LD      (ShellOutCap),A
        CALL    ShellSkipSpaces
        LD      (ShellRequestCommandPtr),HL
        LD      DE,ShellRunText
        CALL    ShellMatchCommand
        JR      NC,ShellRunRequestCommandOk
        LD      A,SHELL_ERR_SYNTAX
        SCF
        RET

ShellRunRequestCommandOk:
        CALL    ShellSkipSpaces
        LD      A,(HL)
        OR      A
        JR      Z,ShellRunRequestDefault
        LD      A,SHELL_RUN_EXPLICIT
        JR      ShellRunRequestResolve

ShellRunRequestDefault:
        LD      A,SHELL_RUN_DEFAULT

ShellRunRequestResolve:
        LD      (ShellRunMode),A
        LD      DE,(ShellRequestPtr)
        INC     DE
        LD      HL,(ShellRequestCommandPtr)
        LD      A,(ShellOutCap)
        LD      B,A
        CALL    ResolveShellCommand
        RET     C
        CP      SHELL_CMD_RUN
        JR      Z,ShellRunRequestOk
        LD      A,SHELL_ERR_SYNTAX
        SCF
        RET

ShellRunRequestOk:
        LD      HL,(ShellRequestPtr)
        LD      A,(ShellRunMode)
        LD      (HL),A
        RET

; ResolveShellAsmRequest —
; Resolve an asm command into a build request block:
;   +0       source path
;   +B       derived /build/<stem>.bin
;   +B+B     derived /build/<stem>.map
; Input:
;   HL = NUL-terminated asm command line
;   DE = request block with three path slots
;   B  = per-path capacity, including final NUL
; Output:
;   carry clear, A=SHELL_CMD_ASM, request block paths are NUL-terminated
;   carry set, A=SHELL_ERR_* or project loader error
;!      in        B,DE,HL
;!      out       A,H,zero,carry
;!      clobbers  BC,DE,L
@ResolveShellAsmRequest:
        LD      (ShellRequestPtr),DE
        LD      A,B
        LD      (ShellOutCap),A
        CALL    ShellSkipSpaces
        LD      (ShellRequestCommandPtr),HL
        LD      DE,ShellAsmText
        CALL    ShellMatchCommand
        JR      NC,ShellAsmRequestCommandOk
        LD      A,SHELL_ERR_SYNTAX
        SCF
        RET

ShellAsmRequestCommandOk:
        LD      HL,(ShellRequestCommandPtr)
        LD      DE,(ShellRequestPtr)
        LD      A,(ShellOutCap)
        LD      B,A
        CALL    ResolveShellCommand
        RET     C

        LD      DE,(ShellRequestPtr)
        LD      A,(ShellOutCap)
        LD      B,A
        CALL    ShellAddBToDE
        RET     C
        LD      HL,(ShellRequestPtr)
        CALL    ShellDeriveBuildBin
        RET     C

        LD      DE,(ShellRequestPtr)
        LD      A,(ShellOutCap)
        LD      B,A
        CALL    ShellAddBToDE
        RET     C
        CALL    ShellAddBToDE
        RET     C
        LD      HL,(ShellRequestPtr)
        CALL    ShellDeriveBuildMap
        RET     C
        LD      A,SHELL_CMD_ASM
        RET

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
;!      clobbers  BC,DE,HL
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
;!      out       A,B,zero,carry
;!      clobbers  C,DE,HL
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
        LD      HL,ShellMainPath
        LD      DE,(ShellOutPath)
        LD      A,(ShellOutCap)
        LD      B,A
        CALL    ShellCopyString
        RET     C
        LD      A,(ShellAction)
        RET

ShellResolveProjectRun:
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

; ShellLoadProjectMain —
; Load and validate /tecm8.prj, then cache the project main path.
;!      out       DE,HL,A,C,carry,zero
;!      clobbers  B
@ShellLoadProjectMain:
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
;!      out       DE,A,carry,zero
;!      clobbers  HL
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
;!      out       HL,A,carry
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
;!      out       HL,A,carry,zero
;!      clobbers  B,DE
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
;!      out       B,carry,zero
;!      clobbers  A,DE,HL
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
;!      out       HL,B,carry,zero
;!      clobbers  A,C,DE
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
;!      out       DE,HL,A,B,carry,zero
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
;!      out       HL,A,carry,zero
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

; ShellAddBToDE —
; Add unsigned B to DE. Carry set if the 16-bit pointer wraps.
;!      in        B,DE
;!      out       DE,A,carry,zero
;!      clobbers  HL
@ShellAddBToDE:
        LD      H,0
        LD      L,B
        ADD     HL,DE
        JR      C,ShellAddBToDEOverflow
        LD      D,H
        LD      E,L
        XOR     A
        RET

ShellAddBToDEOverflow:
        LD      A,SHELL_ERR_LONG
        SCF
        RET

; ShellDeriveBuildBin —
; Derive /build/<local-stem>.bin from an absolute source path.
;!      in        B,DE,HL
;!      out       HL,carry,B,zero
;!      clobbers  A,C,DE
@ShellDeriveBuildBin:
        LD      (ShellArgPtr),HL
        LD      HL,ShellBinExt
        LD      (ShellBuildExtPtr),HL
        LD      HL,(ShellArgPtr)
        JP      ShellDeriveBuildPath

; ShellDeriveBuildMap —
; Derive /build/<local-stem>.map from an absolute source path.
;!      in        B,DE,HL
;!      out       HL,carry,B,zero
;!      clobbers  A,C,DE
@ShellDeriveBuildMap:
        LD      (ShellArgPtr),HL
        LD      HL,ShellMapExt
        LD      (ShellBuildExtPtr),HL
        LD      HL,(ShellArgPtr)
        JP      ShellDeriveBuildPath

; ShellDeriveBuildPath —
; Derive /build/<local-stem><extension> from an absolute source path.
;!      in        B,DE,HL
;!      out       HL,B,carry,zero
;!      clobbers  A,C,DE
@ShellDeriveBuildPath:
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

        LD      HL,(ShellBuildExtPtr)
        CALL    ShellAppendString
        RET     C
        XOR     A
        LD      (DE),A
        RET

; ShellFindLocalName —
; Return HL pointing at the byte after the last slash.
;!      in        HL
;!      out       HL,A,carry
;!      clobbers  DE
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
;!      out       DE,HL,A,B,carry,zero
;!      clobbers  C
@ShellCopyStem:
        LD      C,0

ShellCopyStemLoop:
        LD      (ShellWritePtr),DE
        LD      DE,(ShellStemEnd)
        LD      A,H
        CP      D
        JR      NZ,ShellCopyStemNotEnd
        LD      A,L
        CP      E
        JR      Z,ShellCopyStemAtEnd

ShellCopyStemNotEnd:
        LD      DE,(ShellWritePtr)
        LD      A,(HL)
        OR      A
        JR      Z,ShellCopyStemEnd
        LD      (DE),A
        INC     HL
        INC     DE
        INC     C
        DEC     B
        JR      Z,ShellCopyStemLongErr
        JR      ShellCopyStemLoop

ShellCopyStemAtEnd:
        LD      DE,(ShellWritePtr)

ShellCopyStemEnd:
        LD      A,C
        OR      A
        JR      Z,ShellCopyStemSyntaxErr
        RET

ShellCopyStemSyntaxErr:
        LD      A,SHELL_ERR_SYNTAX
        SCF
        RET

ShellCopyStemLongErr:
        LD      A,SHELL_ERR_LONG
        SCF
        RET

; ShellFindStemEnd —
; Return HL pointing at the final dot in a local filename, or at NUL if none.
;!      in        HL
;!      out       A,DE,HL
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

; ShellSyntaxErr —
; Return a shell syntax error.
;!      out       A,carry
@ShellSyntaxErr:
        LD      A,SHELL_ERR_SYNTAX
        SCF
        RET

; ShellLongErr —
; Return a shell buffer-too-long error.
;!      out       A,carry
@ShellLongErr:
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

ShellMapExt:
        .db     ".map",0

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

ShellBuildExtPtr:
        .dw     0

ShellRequestPtr:
        .dw     0

ShellRequestCommandPtr:
        .dw     0

ShellOutCap:
        .db     0

ShellRemainingCap:
        .db     0

ShellAction:
        .db     0

ShellDispatchPtr:
        .dw     0

ShellDispatchCommandPtr:
        .dw     0

ShellLastExecRequestPtr:
        .dw     0

ShellLastExecAction:
        .db     0

ShellStepDispatch:
        .ds     1 + SHELL_MAIN_PATH_LEN * 3

ShellInputCommand:
        .ds     SHELL_INPUT_LEN

ShellPromptStatus:
        .db     0

ShellPromptError:
        .db     0

ShellProgramState:
        .db     0

ShellLineBuffer:
        .ds     SHELL_LINE_BUF_LEN

ShellLineSeedPtr:
        .dw     0

ShellLineSeedLen:
        .db     0

ShellEditMode:
        .db     0

ShellRunMode:
        .db     0

ShellArgHadDot:
        .db     0

ShellMainPath:
        .ds     SHELL_MAIN_PATH_LEN
