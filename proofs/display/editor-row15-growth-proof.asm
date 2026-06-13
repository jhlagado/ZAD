; Editor row-15 growth proof.
;
; Starts from a one-sector source file, splits row 15, saves, and lets the host
; verify that /src/main.asm grew to include the new second source sector.

        .org    0x4000

        .include "../../src/tecm8-equates.asm"

PROOF_PASS       .equ     0x42
PROOF_FAIL       .equ     0xE0

;! out carry,zero
;! clobbers A,BC,DE,HL
@Start:
        LD      A,1
        LD      (CaseMarker),A
        CALL    DisplayInit
        JP      C,ProofFailed

        LD      A,2
        LD      (CaseMarker),A
        CALL    EditorOpenMain
        JP      C,ProofFailed

        LD      A,3
        LD      (CaseMarker),A
        LD      A,15
        LD      (EditorCursorRow),A
        LD      A,2
        LD      (EditorCursorCol),A
        CALL    EditorSplitLine
        JP      C,ProofFailed
        OR      A
        JP      Z,ProofFailed
        CALL    EditorMarkDirty
        JP      C,ProofFailed

        LD      A,4
        LD      (CaseMarker),A
        CALL    EditorSaveCurrentPage
        JP      C,ProofFailed

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

        .include "../../src/glcd-tile.asm"
        .include "../../src/display-model.asm"
        .include "../../src/editor-viewport.asm"
        .include "../../src/tecm8-string.asm"
        .include "../../src/tecm8-storage.asm"
        .include "../../src/editor-storage-loader.asm"
        .include "../../src/editor-navigation.asm"
        .include "../../src/tecm8-record.asm"
        .include "../../src/editor-interaction.asm"
        .include "../../src/editor-keymap.asm"
        .include "../../src/editor-cursor.asm"
        .include "../../src/editor-prompt.asm"
        .include "../../src/tecm8-bios.asm"

ResultMarker:
        .db     0

CaseMarker:
        .db     0

ErrorMarker:
        .db     0
