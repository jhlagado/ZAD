; Editor rolling source-window proof.
;
; Proves the Phase 3A Slice 2 initial shape: opening /src/main.asm fills four
; resident source slots with pages 0-3 and records window-local metadata.

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

        LD      A,(EditorNavWindowBasePage)
        LD      (WindowBasePageOut),A
        LD      A,(EditorNavWindowValidMask)
        LD      (WindowValidMaskOut),A
        LD      A,(EditorNavWindowDirtyMask)
        LD      (WindowDirtyMaskOut),A
        LD      A,(EditorNavWindowSyntheticMask)
        LD      (WindowSyntheticMaskOut),A

        LD      HL,EditorNavWindowSlotPages
        LD      DE,WindowSlotPagesOut
        LD      BC,4
        LDIR

        LD      HL,EditorNavWindowSlot0
        LD      DE,Slot0Record0
        CALL    CopyRecordText
        LD      HL,EditorNavWindowSlot1
        LD      DE,Slot1Record0
        CALL    CopyRecordText
        LD      HL,EditorNavWindowSlot2
        LD      DE,Slot2Record0
        CALL    CopyRecordText
        LD      HL,EditorNavWindowSlot3
        LD      DE,Slot3Record0
        CALL    CopyRecordText

        LD      A,1
        LD      (EditorNavCurrentPage),A
        CALL    EditorNavLoadNextWindowPage
        JP      C,ProofFailed
        LD      A,(EditorNavNextPageSynthetic)
        LD      (NextPageSyntheticAfterCacheOut),A

        CALL    EditorNavInvalidateWindowSlot3
        JP      C,ProofFailed
        LD      A,(EditorNavWindowValidMask)
        LD      (WindowValidMaskAfterInvalidateOut),A

        LD      A,PROOF_PASS
        LD      (ResultMarker),A

ProofDone:
        JP      ProofDone

ProofFailed:
        OR      PROOF_FAIL
        LD      (ResultMarker),A

ProofFailedDone:
        JP      ProofDone

;! in DE,HL
;! out A,DE,HL,carry,zero
;! clobbers A,BC
@CopyRecordText:
        INC     HL
        LD      B,32

CopyRecordTextLoop:
        LD      A,(HL)
        LD      (DE),A
        INC     HL
        INC     DE
        OR      A
        RET     Z
        DJNZ    CopyRecordTextLoop
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

ResultMarker:
        .db     0
WindowBasePageOut:
        .db     0
WindowValidMaskOut:
        .db     0
WindowDirtyMaskOut:
        .db     0
WindowSyntheticMaskOut:
        .db     0
NextPageSyntheticAfterCacheOut:
        .db     0
WindowValidMaskAfterInvalidateOut:
        .db     0
WindowSlotPagesOut:
        .ds     4
Slot0Record0:
        .ds     32
Slot1Record0:
        .ds     32
Slot2Record0:
        .ds     32
Slot3Record0:
        .ds     32
