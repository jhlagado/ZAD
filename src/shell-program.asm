; TECM8 shell program loop.
;
; Provides the interactive prompt/input layer. Command resolution and execution
; live in shell-resolver.asm, which must be included before this module.

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
;! out carry,zero,A
;! clobbers sign,parity,halfCarry,BC,DE,HL
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
;! out DE,HL,A,C,zero,carry
;! clobbers sign,parity,halfCarry
@InitShellProgramState:
        XOR     A
        LD      (ShellProgramState),A
        LD      (ShellPromptStatus),A
        LD      (ShellPromptError),A
        LD      (ShellLastExecAction),A
        LD      (ShellExecCount),A
        LD      (ShellLastExecRequestPtr),A
        LD      (ShellLastExecRequestPtr + 1),A
        LD      (ShellProjectStatus),A
        LD      (ShellProjectError),A
        CALL    ShellReloadProjectConfig
        RET     NC
        RET

; RunShellProgramCycles —
; Run a bounded number of prompt cycles after one program initialization. This
; is the current shell-loop primitive for proofs and the future live shell.
; Input:
;   B = number of command lines to read and run
; Output:
;   carry clear, A=SHELL_PROGRAM_READY
;   carry set, A=shell error from the failing prompt cycle
;! in B
;! out A,carry,zero
;! clobbers sign,parity,halfCarry,BC,DE,HL
@RunShellProgramCycles:
        LD      A,B
        LD      (ShellProgramCyclesLeft),A
        CALL    InitShellProgramState
        RET     C
        LD      A,(ShellProgramCyclesLeft)
        OR      A
        JR      Z,ShellProgramPromptReady

ShellProgramCycleLoop:
        LD      A,SHELL_PROGRAM_INPUT
        LD      (ShellProgramState),A
        CALL    ReadShellInputLine
        CALL    RunShellPromptCycle
        JR      C,ShellProgramCycleErr
        CP      SHELL_PROMPT_ERROR
        JR      Z,ShellProgramPromptStatusErr

        LD      A,(ShellProgramCyclesLeft)
        DEC     A
        LD      (ShellProgramCyclesLeft),A
        JR      NZ,ShellProgramCycleLoop
        JR      ShellProgramPromptReady

ShellProgramPromptStatusErr:
        LD      A,(ShellPromptError)

ShellProgramCycleErr:
        LD      B,A
        LD      A,SHELL_PROGRAM_READY
        LD      (ShellProgramState),A
        LD      A,B
        SCF
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
;! out BC,DE,HL,carry
;! clobbers zero,sign,parity,halfCarry,A
@ReadShellInputLine:
        CALL    FillShellLineBuffer
        LD      HL,ShellLineBuffer + 1
        LD      A,(ShellLineBuffer)
        INC     A
        LD      C,A
        RET

; FillShellLineBuffer —
; Minimal editable line routine. It reads key events from the current key
; source, appends printable characters, handles backspace, stops on CR, and
; appends the CR terminator.
;! out carry,A,B,DE,HL
;! clobbers zero,sign,parity,halfCarry,C
@FillShellLineBuffer:
        LD      DE,ShellLineBuffer + 1
        LD      B,0

ShellLineEditLoop:
        ; expects out A
        CALL    ReadShellKey
        CP      0x0D
        JR      Z,ShellLineFillTerminator
        CP      0x08
        JR      Z,ShellLineBackspace
        CP      0x7F
        JR      Z,ShellLineBackspace
        CP      0x20
        JR      C,ShellLineEditLoop
        CP      0x7F
        JR      NC,ShellLineEditLoop
        LD      C,A
        LD      A,B
        CP      SHELL_LINE_TEXT_LEN
        JR      NC,ShellLineEditLoop
        LD      A,C
        LD      (DE),A
        INC     DE
        INC     B
        JR      ShellLineEditLoop

ShellLineBackspace:
        LD      A,B
        OR      A
        JR      Z,ShellLineEditLoop
        DEC     B
        DEC     DE
        JR      ShellLineEditLoop

ShellLineFillTerminator:
        LD      A,B
        LD      (ShellLineBuffer),A
        LD      A,0x0D
        LD      (DE),A
        RET

; ReadShellKey —
; Stubbed key source. Real monitor input will replace this provider; proofs seed
; ShellKeySeedPtr with a byte stream ending in CR.
;! out A
;! clobbers HL,F
@ReadShellKey:
        LD      HL,(ShellKeySeedPtr)
        LD      A,H
        OR      L
        JR      NZ,ShellKeySeedReady
        LD      A,0x0D
        RET

ShellKeySeedReady:
        LD      A,(HL)
        INC     HL
        LD      (ShellKeySeedPtr),HL
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
;! in C,HL
;! out carry,zero,A
;! clobbers sign,parity,halfCarry,BC,DE,HL
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
;! in C,HL
;! out A,carry,zero
;! clobbers sign,parity,halfCarry,BC,DE,HL
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
;! in BC,DE,HL
;! out BC,HL,carry,zero,A
;! clobbers sign,parity,halfCarry,DE
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

ShellInputCommand:
        .ds     SHELL_INPUT_LEN

ShellPromptStatus:
        .db     0

ShellPromptError:
        .db     0

ShellProgramState:
        .db     0

ShellProgramCyclesLeft:
        .db     0

ShellLineBuffer:
        .ds     SHELL_LINE_BUF_LEN

ShellKeySeedPtr:
        .dw     0
