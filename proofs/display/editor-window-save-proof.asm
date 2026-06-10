; Editor window save proof.
;
; Reproduces the dirty cache/next-window alias case: edit page 0, page down,
; page back up from cache, split row 14 so row 15 is pushed into the adjacent
; next buffer, then save. The host verifies both dirty resident sectors persist.

        .org    0x4000

PROOF_PASS       .equ     0x42
PROOF_FAIL       .equ     0xE0

;!      out       carry,zero
;!      clobbers  A,BC,DE,HL
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
        XOR     A
        LD      (EditorCursorRow),A
        LD      (EditorCursorCol),A
        LD      A,"Z"
        CALL    EditorInsertChar
        JP      C,ProofFailed
        CALL    EditorMarkDirty
        JP      C,ProofFailed

        LD      A,4
        LD      (CaseMarker),A
        CALL    EditorPageDown
        JP      C,ProofFailed
        LD      A,5
        LD      (CaseMarker),A
        CALL    EditorPageUp
        JP      C,ProofFailed

        LD      A,6
        LD      (CaseMarker),A
        LD      HL,WindowRow14
        LD      DE,EditorNavPageBuffer + (14 * 32)
        CALL    WindowCopyRecord
        LD      HL,WindowRow15
        LD      DE,EditorNavPageBuffer + (15 * 32)
        CALL    WindowCopyRecord
        LD      A,3
        LD      (EditorNavDirtySectors),A
        LD      A,1
        LD      (EditorNavDirty),A

        LD      A,14
        LD      (EditorCursorRow),A
        LD      A,2
        LD      (EditorCursorCol),A
        CALL    EditorSplitLine
        JP      C,ProofFailed
        OR      A
        JP      Z,ProofFailed
        LD      A,7
        LD      (CaseMarker),A
        CALL    EditorMarkDirty
        JP      C,ProofFailed

        LD      A,8
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

;!      in        DE,HL
;!      out       A,BC,DE,HL,carry,zero
@WindowCopyRecord:
        LD      BC,32
        LDIR
        XOR     A
        RET

        .include "../../src/glcd-tile.asm"
        .include "../../src/display-model.asm"
        .include "../../src/editor-viewport.asm"
        .include "../../src/editor-storage-loader.asm"
        .include "../../src/editor-navigation.asm"
        .include "../../src/editor-interaction.asm"
        .include "../../src/tecm8-bios.asm"

WindowRow14:
        .db     4,"LEFT"
        .ds     27

WindowRow15:
        .db     4,"PUSH"
        .ds     27

ResultMarker:
        .db     0

CaseMarker:
        .db     0

ErrorMarker:
        .db     0
