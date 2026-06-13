; Named shell edit to storage-backed editor proof.
;
; Launches the editor through `edit notes`, proving the shell resolves a
; bare source name to /src/notes.asm before opening the editor.

        .org    0x4000

        .include "../../src/tecm8-equates.asm"

PROOF_PASS       .equ     0x42
PROOF_FAIL       .equ     0xE0

;!      out       carry,zero
;!      clobbers  A,BC,DE,HL
@Start:
        CALL    DisplayInit
        JR      C,ProofFailed

        LD      HL,CmdEditNamed
        CALL    ShellRunEditorLine
        JR      C,ProofFailed

        LD      A,PROOF_PASS
        LD      (ResultMarker),A

ProofDone:
        JP      ProofDone

ProofFailed:
        OR      PROOF_FAIL
        LD      (ResultMarker),A

ProofFailedDone:
        JP      ProofDone

; Stub LoadProjectConfig for link completeness. Named edit must not depend on
; the project-main cache because the command supplies an explicit source name.
;!      in        B,DE
;!      out       DE,HL,A,C,carry,zero
;!      clobbers  B
@LoadProjectConfig:
        LD      A,SHELL_ERR_PROJECT
        SCF
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

CmdEditNamed:
        .db     "edit notes",0

ResultMarker:
        .db     0
