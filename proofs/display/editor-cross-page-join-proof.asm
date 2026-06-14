; Editor cross-page join proof.
;
; Proves Backspace at row 0 column 0 joins into cached previous-page row 15,
; makes the previous page active, and keeps the shifted old current page as the
; adjacent next sector.

        .org    0x4000

        .include "../../src/tecm8-equates.asm"

PROOF_PASS       .equ     0x42
PROOF_FAIL       .equ     0xE0

;! out carry,zero
;! clobbers A,BC,DE,HL
@Start:
        CALL    DisplayInit
        JR      C,ProofFailed

        LD      HL,EditorNavPageBuffer
        CALL    ProofClearPage
        LD      HL,EditorNavCachePageBuffer
        CALL    ProofClearPage
        CALL    EditorNavClearNextPageBuffer
        JR      C,ProofFailed

        LD      HL,ProofPreviousLastRecord
        LD      DE,EditorNavCachePageBuffer + (15 * 32)
        CALL    ProofCopyRecord
        LD      HL,ProofCurrentFirstRecord
        LD      DE,EditorNavPageBuffer
        CALL    ProofCopyRecord
        LD      HL,ProofCurrentSecondRecord
        LD      DE,EditorNavPageBuffer + 32
        CALL    ProofCopyRecord

        LD      A,1
        LD      (EditorNavCurrentPage),A
        LD      (EditorNavCacheValid),A
        XOR     A
        LD      (EditorNavCachedPage),A
        LD      (EditorCursorRow),A
        LD      (EditorCursorCol),A
        LD      (EditorNavCurrentRow),A
        LD      A,7
        LD      (EditorNavViewportTopRow),A
        LD      A,TECM8_EDITOR_CURSOR_VISIBLE_ROWS - 1
        LD      (EditorCursorVisibleRow),A
        XOR     A
        LD      (EditorNavDirty),A
        LD      (EditorNavDirtySectors),A
        LD      (EditorNavCachedPageDirty),A

        CALL    EditorBackspaceChar
        JR      C,ProofFailed
        OR      A
        JR      Z,ProofFailed

        LD      A,(EditorNavViewportTopRow)
        LD      (ViewportTopAfterJoin),A
        LD      A,(EditorNavCurrentRow)
        LD      (NavCurrentRowAfterJoin),A
        LD      A,(EditorCursorVisibleRow)
        LD      (VisibleRowAfterJoin),A

        LD      A,PROOF_PASS
        LD      (ResultMarker),A

ProofDone:
        JP      ProofDone

ProofFailed:
        OR      PROOF_FAIL
        LD      (ResultMarker),A

ProofFailedDone:
        JP      ProofDone

;! in HL
;! out A,BC,DE,HL,carry,zero
@ProofClearPage:
        LD      BC,512
        XOR     A

ProofClearPageLoop:
        LD      (HL),A
        INC     HL
        DEC     BC
        LD      A,B
        OR      C
        JR      NZ,ProofClearPageLoop
        XOR     A
        RET

;! in DE,HL
;! out A,BC,DE,HL,carry,zero
@ProofCopyRecord:
        LD      BC,32
        LDIR
        XOR     A
        RET

        .include "../../src/glcd-tile.asm"
        .include "../../src/display-model.asm"
        .include "../../src/editor-block-state.asm"
        .include "../../src/editor-viewport.asm"
        .include "../../src/tecm8-string.asm"
        .include "../../src/tecm8-storage.asm"
        .include "../../src/editor-storage-loader.asm"
        .include "../../src/editor-navigation.asm"
        .include "../../src/tecm8-record.asm"
        .include "../../src/editor-interaction.asm"
        .include "../../src/editor-record.asm"
        .include "../../src/editor-line-edit.asm"
        .include "../../src/editor-block.asm"
        .include "../../src/editor-keymap.asm"
        .include "../../src/editor-cursor.asm"
        .include "../../src/editor-prompt.asm"
        .include "../../src/editor-render.asm"
        .include "../../src/tecm8-bios.asm"

ProofPreviousLastRecord:
        .db     4,"PREV"
        .ds     27

ProofCurrentFirstRecord:
        .db     3,"CUR"
        .ds     28

ProofCurrentSecondRecord:
        .db     4,"NEXT"
        .ds     27

ResultMarker:
        .db     0
ViewportTopAfterJoin:
        .db     0
NavCurrentRowAfterJoin:
        .db     0
VisibleRowAfterJoin:
        .db     0
