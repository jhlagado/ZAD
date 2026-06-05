; Editor page write-back proof.
;
; Opens /src/main.asm, mutates the loaded 512-byte page buffer, saves it back to
; VOLUME.TM8, then reloads the page so the host runner can verify persisted TM8
; source records from the FAT32 image.

        .org    0x4000

PROOF_PASS       .equ     0x42
PROOF_FAIL       .equ     0xE0

;!      out       carry,zero
;!      clobbers  A,BC,DE,HL
@Start:
        CALL    DisplayInit
        JR      C,ProofFailed

        CALL    EditorOpenMain
        JR      C,ProofFailed

        LD      A,8
        LD      (EditorCursorCol),A
        LD      HL,EditorNoopDeleteKeys
        CALL    EditorRunKeys
        JR      C,ProofFailed
        LD      A,(EditorNavDirty)
        LD      (DirtyAfterNoopDelete),A

        LD      A,15
        LD      (EditorCursorRow),A
        XOR     A
        LD      (EditorCursorCol),A
        LD      HL,EditorNoopSplitKeys
        CALL    EditorRunKeys
        JR      C,ProofFailed
        LD      A,(EditorNavDirty)
        LD      (DirtyAfterNoopSplit),A

        XOR     A
        LD      (EditorCursorRow),A
        LD      (EditorCursorCol),A
        CALL    EditorKeyCurrentRecord
        LD      (HL),31
        LD      HL,EditorNoopInsertKeys
        CALL    EditorRunKeys
        JR      C,ProofFailed
        LD      A,(EditorNavDirty)
        LD      (DirtyAfterNoopInsert),A

        CALL    EditorRenderCurrent
        JR      C,ProofFailed
        CALL    EditorCursorReset
        JR      C,ProofFailed

        LD      HL,EditorPageEditKeys
        CALL    EditorRunKeys
        JR      C,ProofFailed

        LD      A,(EditorNavDirty)
        LD      (DirtyAfterEdit),A

        LD      HL,EditorPageSaveKeys
        CALL    EditorRunKeys
        JR      C,ProofFailed

        LD      A,(EditorNavDirty)
        LD      (DirtyAfterSave),A

        CALL    EditorRenderCurrent
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

        .include "../../src/display-model.asm"
        .include "../../src/editor-viewport.asm"
        .include "../../src/editor-storage-loader.asm"
        .include "../../src/editor-navigation.asm"
        .include "../../src/editor-interaction.asm"
        .include "../../src/tecm8-bios.asm"

EditorPageEditKeys:
        .db     9,"OK",0

EditorPageSaveKeys:
        .db     19,0

EditorNoopDeleteKeys:
        .db     127,0

EditorNoopSplitKeys:
        .db     13,0

EditorNoopInsertKeys:
        .db     9,"!",0

DirtyAfterNoopDelete:
        .db     0

DirtyAfterNoopSplit:
        .db     0

DirtyAfterNoopInsert:
        .db     0

DirtyAfterEdit:
        .db     0

DirtyAfterSave:
        .db     0

ResultMarker:
        .db     0
