; Shell-launched editor interaction proof.
;
; Opens a project source file through the shell and consumes editor key input
; that pages down once.

        .org    0x4000

ProofPass       .equ     0x42
ProofFail       .equ     0xE0

;!      out       carry,zero
;!      clobbers  A,BC,DE,HL
@Start:
        CALL    TECM8_DISPLAY_INIT
        JR      C,ProofFailed

        LD      A,1
        LD      (CaseMarker),A
        LD      HL,CmdEdit
        LD      DE,EditorKeys
        CALL    TECM8_SHELL_RUN_EDITOR_SESSION
        JR      C,ProofFailed

        LD      A,ProofPass
        LD      (ResultMarker),A

ProofDone:
        JP      ProofDone

ProofFailed:
        LD      (ErrorMarker),A
        LD      A,(CaseMarker)
        OR      ProofFail
        LD      (ResultMarker),A

ProofFailedDone:
        JP      ProofDone

; Stub LoadProjectConfig for shell-to-editor interaction proof.
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

        .include "../../src/display-model.asm"
        .include "../../src/editor-viewport.asm"
        .include "../../src/editor-storage-loader.asm"
        .include "../../src/editor-navigation.asm"
        .include "../../src/editor-interaction.asm"
        .include "../../src/shell-commands.asm"
        .include "../../src/shell-editor-launch.asm"
        .include "../../src/tecm8-bios.asm"

CmdEdit:
        .db     "edit",0

EditorKeys:
        .db     "hkulljjd",0

ExpectedMain:
        .db     "/projects/demo/app.asm",0

ResultMarker:
        .db     0

CaseMarker:
        .db     0

ErrorMarker:
        .db     0
