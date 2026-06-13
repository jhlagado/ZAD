; TECM8 Debug80 editor session entry.
;
; Runs under Debug80's TEC-1G runtime with MON3 loaded and an SD/FAT32 image
; containing VOLUME.TM8. The 4000h entry is the manual live editor path. The
; automated Debug80 proof runner enters ScriptStart for the saved edit/reopen
; verification flow.

        .org    0x4000

TECM8_MAIN_PASS        .equ     0x42
TECM8_MAIN_FAIL        .equ     0xE0

        .include "tecm8-equates.asm"

;! out carry,zero
;! clobbers sign,parity,halfCarry,A,BC,DE,HL
@Start:
        JP      LiveStart

;! out carry,zero
;! clobbers sign,parity,halfCarry,A,BC,DE,HL
@ScriptStart:
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
        CALL    EditorNavShowError
        LD      A,(MainCaseMarker)
        OR      TECM8_MAIN_FAIL
        LD      (MainResultMarker),A
        JP      MainDone

;! out carry,zero
;! clobbers sign,parity,halfCarry,A,BC,DE,HL
@LiveStart:
        CALL    DisplayInit
        JP      C,MainFailed
        LD      HL,MainEditCommand
        CALL    ShellRunEditorLine
        JP      C,MainFailed
        CALL    EditorCursorReset
        CALL    EditorRunLive
        JP      C,MainFailed
        LD      HL,MainShellReadyText
        CALL    EditorKeyShowStatus
        JP      C,MainFailed
        LD      A,TECM8_MAIN_PASS
        LD      (MainResultMarker),A
        JP      MainDone

        .include "project-config.asm"
        .include "project-config-loader.asm"
        .include "glcd-tile.asm"
        .include "display-model.asm"
        .include "editor-viewport.asm"
        .include "editor-storage-loader.asm"
        .include "editor-navigation.asm"
        .include "tecm8-record.asm"
        .include "editor-interaction.asm"
        .include "shell-commands.asm"
        .include "shell-editor-launch.asm"
        .include "tecm8-bios.asm"

MainEditCommand:
        .db     "edit",0

MainShellReadyText:
        .db     "Shell",0

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
