; TECM8 shell/editor launcher.
;
; Bridges the shell command resolver to the storage-backed editor. The command
; resolver remains responsible for parsing and path selection; this layer starts
; the editor only when the resolved shell action is edit.

TECM8_SHELL_LAUNCH_ERR_UNSUPPORTED     .equ    0x58
TECM8_SHELL_LAUNCH_ERR_TARGET          .equ    0x59

; ShellRunEditorLine -
; Run one shell command line and launch the editor when it resolves to edit.
; Input:
;   HL = NUL-terminated shell command line
; Output:
;   carry clear, A=SHELL_OK after the editor opens
;   carry set, A=SHELL_ERR_* or TECM8_SHELL_LAUNCH_ERR_*
;!      in        HL
;!      out       A,carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@ShellRunEditorLine:
        CALL    RunShellCommandLine
        RET     C

        LD      A,(ShellLastExecAction)
        CP      SHELL_CMD_EDIT
        JR      NZ,ShellEditorLaunchUnsupported

        LD      HL,(ShellLastExecRequestPtr)
        LD      A,(HL)
        CP      SHELL_EDIT_DEFAULT
        JR      Z,ShellEditorLaunchOpenPath
        CP      SHELL_EDIT_EXPLICIT
        JR      Z,ShellEditorLaunchOpenPath
        JR      ShellEditorLaunchTargetErr

ShellEditorLaunchOpenPath:
        INC     HL
        CALL    EditorOpenPath
        RET     C
        XOR     A
        RET

; ShellRunEditorSession -
; Run one shell edit command line, then consume editor key input.
; Input:
;   HL = NUL-terminated shell command line
;   DE = NUL-terminated editor key stream
;!      in        DE,HL
;!      out       A,carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@ShellRunEditorSession:
        LD      (ShellEditorSessionKeys),DE
        CALL    ShellRunEditorLine
        RET     C
        CALL    EditorCursorReset
        LD      HL,(ShellEditorSessionKeys)
        CALL    EditorRunKeys
        RET

ShellEditorLaunchUnsupported:
        LD      A,TECM8_SHELL_LAUNCH_ERR_UNSUPPORTED
        SCF
        RET

ShellEditorLaunchTargetErr:
        LD      A,TECM8_SHELL_LAUNCH_ERR_TARGET
        SCF
        RET

ShellEditorSessionKeys:
        .dw     0
