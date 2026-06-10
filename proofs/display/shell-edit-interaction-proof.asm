; Shell-launched editor interaction proof.
;
; Opens a project source file through the shell and consumes editor key input
; that exercises cursor bounds, pages down once, and mutates the loaded page.

        .org    0x4000

PROOF_PASS       .equ     0x42
PROOF_FAIL       .equ     0xE0

;!      out       carry,zero
;!      clobbers  A,BC,DE,HL
@Start:
        CALL    DisplayInit
        JR      C,ProofFailed

        LD      A,1
        LD      (CaseMarker),A
        LD      HL,CmdEdit
        LD      DE,NoKeys
        CALL    ShellRunEditorSession
        JR      C,ProofFailed

        LD      A,2
        LD      (CaseMarker),A
        LD      A,"W"
        LD      B,TECM8_EDITOR_KEY_MOD_ALT
        CALL    EditorRunModifiedKey
        JR      C,ProofFailed
        LD      A,(EditorNavDirty)
        LD      (UnknownModifiedDirty),A

        LD      A,3
        LD      (CaseMarker),A
        LD      A,TECM8_EDITOR_KEY_ARROW_DOWN
        LD      B,TECM8_EDITOR_KEY_MOD_ALT
        CALL    EditorRunModifiedKey
        JR      C,ProofFailed

        LD      A,4
        LD      (CaseMarker),A
        LD      HL,EditorKeys
        CALL    EditorRunKeys
        JR      C,ProofFailed

        LD      A,5
        LD      (CaseMarker),A
        LD      HL,EditorKeyLeft
        CALL    EditorRunKeys
        JR      C,ProofFailed

        LD      A,6
        LD      (CaseMarker),A
        LD      HL,EditorKeyRight
        CALL    EditorRunKeys
        JR      C,ProofFailed

        LD      A,PROOF_PASS
        LD      (ResultMarker),A

ProofDone:
        JP      ProofDone

ProofFailed:
        LD      (ErrorMarker),A
        LD      A,(CaseMarker)
        OR      PROOF_FAIL
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

        .include "../../src/glcd-tile.asm"
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

NoKeys:
        .db     0

EditorKeys:
        .db     TECM8_EDITOR_KEY_ARROW_LEFT,TECM8_EDITOR_KEY_ARROW_UP
        .db     TECM8_EDITOR_KEY_ARROW_RIGHT,TECM8_EDITOR_KEY_ARROW_RIGHT
        .db     TECM8_EDITOR_KEY_ARROW_RIGHT,TECM8_EDITOR_KEY_ARROW_RIGHT
        .db     TECM8_EDITOR_KEY_ARROW_RIGHT,TECM8_EDITOR_KEY_ARROW_RIGHT
        .db     TECM8_EDITOR_KEY_ARROW_RIGHT,TECM8_EDITOR_KEY_ARROW_RIGHT
        .db     TECM8_EDITOR_KEY_ARROW_RIGHT,TECM8_EDITOR_KEY_ARROW_RIGHT
        .db     TECM8_EDITOR_KEY_ARROW_RIGHT,TECM8_EDITOR_KEY_ARROW_RIGHT
        .db     TECM8_EDITOR_KEY_ARROW_RIGHT,TECM8_EDITOR_KEY_ARROW_RIGHT
        .db     TECM8_EDITOR_KEY_ARROW_RIGHT,TECM8_EDITOR_KEY_ARROW_RIGHT
        .db     TECM8_EDITOR_KEY_ARROW_RIGHT,TECM8_EDITOR_KEY_ARROW_RIGHT
        .db     TECM8_EDITOR_KEY_ARROW_RIGHT,TECM8_EDITOR_KEY_ARROW_RIGHT
        .db     TECM8_EDITOR_KEY_ARROW_RIGHT,TECM8_EDITOR_KEY_ARROW_RIGHT
        .db     TECM8_EDITOR_KEY_ARROW_RIGHT,TECM8_EDITOR_KEY_ARROW_RIGHT
        .db     TECM8_EDITOR_KEY_ARROW_RIGHT,TECM8_EDITOR_KEY_ARROW_RIGHT
        .db     TECM8_EDITOR_KEY_ARROW_RIGHT,TECM8_EDITOR_KEY_ARROW_RIGHT
        .db     TECM8_EDITOR_KEY_ARROW_RIGHT,TECM8_EDITOR_KEY_ARROW_RIGHT,TECM8_EDITOR_KEY_ARROW_RIGHT
        .db     TECM8_EDITOR_KEY_ARROW_DOWN,TECM8_EDITOR_KEY_ARROW_DOWN,TECM8_EDITOR_KEY_ARROW_DOWN
        .db     TECM8_EDITOR_KEY_ARROW_DOWN,TECM8_EDITOR_KEY_ARROW_DOWN,TECM8_EDITOR_KEY_ARROW_DOWN
        .db     TECM8_EDITOR_KEY_ARROW_DOWN,TECM8_EDITOR_KEY_ARROW_DOWN,TECM8_EDITOR_KEY_ARROW_DOWN
        .db     TECM8_EDITOR_KEY_ARROW_RIGHT,TECM8_EDITOR_KEY_ARROW_DOWN
        .db     TECM8_EDITOR_KEY_ARROW_LEFT,TECM8_EDITOR_KEY_ARROW_UP
        .db     TECM8_EDITOR_KEY_ARROW_RIGHT,TECM8_EDITOR_KEY_ARROW_DOWN
        .db     TECM8_EDITOR_KEY_ARROW_LEFT,TECM8_EDITOR_KEY_ARROW_UP
        .db     TECM8_EDITOR_KEY_ARROW_LEFT,TECM8_EDITOR_KEY_ARROW_LEFT
        .db     TECM8_EDITOR_KEY_ARROW_LEFT,TECM8_EDITOR_KEY_ARROW_LEFT
        .db     TECM8_EDITOR_KEY_ARROW_LEFT,TECM8_EDITOR_KEY_ARROW_LEFT
        .db     TECM8_EDITOR_KEY_ARROW_LEFT,TECM8_EDITOR_KEY_ARROW_LEFT
        .db     TECM8_EDITOR_KEY_ARROW_LEFT,TECM8_EDITOR_KEY_ARROW_LEFT,TECM8_EDITOR_KEY_ARROW_LEFT
        .db     TECM8_EDITOR_KEY_ARROW_UP
        .db     TECM8_EDITOR_KEY_ARROW_LEFT,TECM8_EDITOR_KEY_ARROW_LEFT
        .db     TECM8_EDITOR_KEY_ARROW_LEFT,TECM8_EDITOR_KEY_ARROW_LEFT
        .db     TECM8_EDITOR_KEY_ARROW_LEFT,TECM8_EDITOR_KEY_ARROW_LEFT
        .db     TECM8_EDITOR_KEY_ARROW_LEFT,TECM8_EDITOR_KEY_ARROW_LEFT
        .db     TECM8_EDITOR_KEY_ARROW_LEFT,TECM8_EDITOR_KEY_ARROW_LEFT
        .db     TECM8_EDITOR_KEY_ARROW_LEFT,TECM8_EDITOR_KEY_ARROW_LEFT
        .db     TECM8_EDITOR_KEY_ARROW_LEFT,TECM8_EDITOR_KEY_ARROW_LEFT
        .db     TECM8_EDITOR_KEY_ARROW_LEFT,TECM8_EDITOR_KEY_ARROW_LEFT
        .db     TECM8_EDITOR_KEY_ARROW_LEFT
        .db     9
        .db     "dl!"
        .db     8
        .db     "?",127,0

EditorKeyLeft:
        .db     TECM8_EDITOR_KEY_ARROW_LEFT,0

EditorKeyRight:
        .db     TECM8_EDITOR_KEY_ARROW_RIGHT,0

ExpectedMain:
        .db     "/projects/demo/app.asm",0

ResultMarker:
        .db     0

CaseMarker:
        .db     0

ErrorMarker:
        .db     0

UnknownModifiedDirty:
        .db     0
