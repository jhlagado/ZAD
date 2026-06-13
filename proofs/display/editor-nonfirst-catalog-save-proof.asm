; Editor non-first catalog save proof.
;
; Opens /src/main.asm when another /src file appears earlier in the TM8
; catalog, edits the first record, and saves. This proves catalog scan state
; preserves the sector offset while walking entries inside a sector.

        .org    0x4000

        .include "../../src/tecm8-equates.asm"

PROOF_PASS       .equ     0x42
PROOF_FAIL       .equ     0xE0

;! out carry,zero
;! clobbers A,BC,DE,HL
@Start:
        CALL    DisplayInit
        JP      C,ProofFailed

        CALL    EditorOpenMain
        JP      C,ProofFailed

        LD      HL,(EditorLoadCatalogSectorOffset)
        LD      (CatalogSectorAfterOpen),HL
        LD      HL,(EditorLoadCatalogEntryOffset)
        LD      (CatalogEntryAfterOpen),HL

        LD      HL,EditorNonFirstEditKeys
        CALL    EditorRunKeys
        JP      C,ProofFailed

        LD      A,(EditorNavDirty)
        LD      (DirtyAfterSave),A

        LD      A,PROOF_PASS
        LD      (ResultMarker),A

ProofDone:
        JP      ProofDone

ProofFailed:
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
        .include "../../src/editor-record.asm"
        .include "../../src/editor-keymap.asm"
        .include "../../src/editor-cursor.asm"
        .include "../../src/editor-prompt.asm"
        .include "../../src/editor-render.asm"
        .include "../../src/tecm8-bios.asm"

EditorNonFirstEditKeys:
        .db     "Z",19,0

DirtyAfterSave:
        .db     0

CatalogSectorAfterOpen:
        .dw     0

CatalogEntryAfterOpen:
        .dw     0

ResultMarker:
        .db     0
