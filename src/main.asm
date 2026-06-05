; TECM8 Debug80 editor session entry.
;
; Runs under Debug80's TEC-1G runtime with MON3 loaded and an SD/FAT32 image
; containing VOLUME.TM8. This is the first user-testable TECM8 entry: it opens
; the project main source file through the shell editor path, performs a small
; edit, saves, quits, then reopens the saved file so the GLCD shows the result.

        .org    0x4000

TECM8_MAIN_PASS        .equ     0x42
TECM8_MAIN_FAIL        .equ     0xE0

;!      out       carry,zero
;!      clobbers  A,BC,DE,HL
@Start:
        CALL    DisplayInit
        JP      C,MainFailed

        LD      A,1
        LD      (MainCaseMarker),A
        LD      HL,MainEditCommand
        LD      DE,MainEditSaveQuitKeys
        CALL    ShellRunEditorSession
        JP      C,MainFailed

        LD      A,2
        LD      (MainCaseMarker),A
        LD      HL,MainEditCommand
        LD      DE,MainReopenQuitKeys
        CALL    ShellRunEditorSession
        JP      C,MainFailed

        LD      A,TECM8_MAIN_PASS
        LD      (MainResultMarker),A

MainDone:
        JP      MainDone

MainFailed:
        LD      (MainErrorMarker),A
        LD      A,(MainCaseMarker)
        OR      TECM8_MAIN_FAIL
        LD      (MainResultMarker),A
        JP      MainDone

        .include "project-config.asm"
        .include "project-config-loader.asm"
        .include "display-model.asm"
        .include "editor-viewport.asm"
        .include "editor-storage-loader.asm"
        .include "editor-navigation.asm"
        .include "editor-interaction.asm"
        .include "shell-commands.asm"
        .include "shell-editor-launch.asm"
        .include "tecm8-bios.asm"

MainEditCommand:
        .db     "edit",0

MainEditSaveQuitKeys:
        .db     "AB",19,17,0

MainReopenQuitKeys:
        .db     17,0

MainResultMarker:
        .db     0

MainCaseMarker:
        .db     0

MainErrorMarker:
        .db     0
