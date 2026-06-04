; TECM8 shell/editor launcher.
;
; Bridges the shell command resolver to the storage-backed editor. The command
; resolver remains responsible for parsing and path selection; this layer starts
; the editor only when the resolved shell action is edit.

TECM8_SHELL_LAUNCH_ERR_UNSUPPORTED     .equ    0x58
TECM8_SHELL_LAUNCH_ERR_TARGET          .equ    0x59

; TECM8_SHELL_RUN_EDITOR_LINE -
; Run one shell command line and launch the editor when it resolves to edit.
; Input:
;   HL = NUL-terminated shell command line
; Output:
;   carry clear, A=SHELL_OK after the editor opens
;   carry set, A=SHELL_ERR_* or TECM8_SHELL_LAUNCH_ERR_*
;!      in        HL
;!      out       A,carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@TECM8_SHELL_RUN_EDITOR_LINE:
        CALL    RunShellCommandLine
        RET     C

        LD      A,(ShellLastExecAction)
        CP      SHELL_CMD_EDIT
        JR      NZ,ShellEditorLaunchUnsupported

        LD      HL,(ShellLastExecRequestPtr)
        LD      A,(HL)
        CP      SHELL_EDIT_DEFAULT
        JR      Z,ShellEditorLaunchCheckTarget
        CP      SHELL_EDIT_EXPLICIT
        JR      Z,ShellEditorLaunchCheckTarget
        JR      ShellEditorLaunchTargetErr

ShellEditorLaunchCheckTarget:
        INC     HL
        LD      DE,ShellEditorLaunchMainPath
        CALL    ShellEditorLaunchStringEquals
        JR      C,ShellEditorLaunchTargetErr

ShellEditorLaunchOpenMain:
        CALL    TECM8_EDITOR_OPEN_MAIN
        RET     C
        XOR     A
        RET

ShellEditorLaunchUnsupported:
        LD      A,TECM8_SHELL_LAUNCH_ERR_UNSUPPORTED
        SCF
        RET

ShellEditorLaunchTargetErr:
        LD      A,TECM8_SHELL_LAUNCH_ERR_TARGET
        SCF
        RET

; ShellEditorLaunchStringEquals -
; Compare NUL-terminated strings at HL and DE.
;!      in        DE,HL
;!      out       A,carry,zero
;!      clobbers  DE,HL
@ShellEditorLaunchStringEquals:
        LD      A,(DE)
        CP      (HL)
        JR      NZ,ShellEditorLaunchStringBad
        OR      A
        RET     Z
        INC     DE
        INC     HL
        JR      ShellEditorLaunchStringEquals

ShellEditorLaunchStringBad:
        SCF
        RET

ShellEditorLaunchMainPath:
        .db     "/src/main.asm",0
