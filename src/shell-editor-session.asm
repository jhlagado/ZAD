; TECM8 shell/editor scripted session helper.
;
; Proof targets use this to run one shell edit command line and then feed a
; NUL-terminated translated-key stream into the editor. The live editor image
; should include shell-editor-launch.asm without this module.

; ShellRunEditorSession -
; Run one shell edit command line, then consume editor key input.
; Input:
;   HL = NUL-terminated shell command line
;   DE = NUL-terminated editor key stream
;! in DE,HL
;! out A,carry
;! clobbers zero,sign,parity,halfCarry,BC,DE,HL
@ShellRunEditorSession:
        LD      (ShellEditorSessionKeys),DE
        CALL    ShellRunEditorLine
        RET     C
        CALL    EditorCursorReset
        LD      HL,(ShellEditorSessionKeys)
        CALL    EditorRunKeys
        RET

ShellEditorSessionKeys:
        .dw     0
