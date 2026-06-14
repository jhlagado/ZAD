; Editor rolling source-window miss proof.
;
; Proves Phase 3A Slice 3 page-level rolling behavior:
; - a clean move from page 1 to page 2 rotates one sector and loads one high
;   source page into the slot-3/backup buffer;
; - a dirty cached low victim blocks the same move instead of autosaving.

        .org    0x4000

        .include "../../src/tecm8-equates.asm"

PROOF_PASS       .equ     0x42
PROOF_FAIL       .equ     0xE0

;! out carry,zero
;! clobbers A,BC,DE,HL,IX,IY
@Start:
        CALL    DisplayInit
        JP      C,ProofFailed

        CALL    RunCleanMissCase
        JP      C,ProofFailed

        CALL    EditorOpenMain
        JP      C,ProofFailed

        CALL    RunStaleBackupCase
        JP      C,ProofFailed

        CALL    EditorOpenMain
        JP      C,ProofFailed

        CALL    RunDirtyAdjacentReturnCase
        JP      C,ProofFailed

        CALL    EditorOpenMain
        JP      C,ProofFailed

        CALL    RunDirtyEvictionCase
        JP      C,ProofFailed

        LD      A,PROOF_PASS
        LD      (ResultMarker),A

ProofDone:
        JP      ProofDone

ProofFailed:
        OR      PROOF_FAIL
        LD      (ResultMarker),A

ProofFailedDone:
        JP      ProofDone

;! out A,carry,zero
;! clobbers sign,parity,halfCarry,BC,DE,HL,IX,IY
@RunCleanMissCase:
        CALL    EditorOpenMain
        RET     C
        LD      A,(EditorNavWindowMissLoadCount)
        LD      (CleanMissCountBefore),A
        CALL    EditorPageDown
        RET     C
        LD      A,(EditorNavCurrentPage)
        LD      (CleanPageAfterFirstDown),A
        CALL    EditorPageDown
        RET     C
        LD      A,(EditorNavCurrentPage)
        LD      (CleanPageAfterSecondDown),A
        LD      A,(EditorNavWindowMissLoadCount)
        LD      (CleanMissCountAfter),A
        LD      HL,EditorNavPageBuffer
        LD      DE,CleanCurrentRecord0
        CALL    CopyRecordText
        LD      HL,EditorNavNextPageBuffer
        LD      DE,CleanNextRecord0
        CALL    CopyRecordText
        LD      HL,EditorNavCachePageBuffer
        LD      DE,CleanCacheRecord0
        CALL    CopyRecordText
        LD      HL,EditorNavBackupPageBuffer
        LD      DE,CleanBackupRecord0
        CALL    CopyRecordText
        XOR     A
        RET

;! out A,carry,zero
;! clobbers sign,parity,halfCarry,BC,DE,HL,IX,IY
@RunStaleBackupCase:
        CALL    EditorPageDown
        RET     C
        CALL    EditorPageUp
        RET     C
        CALL    EditorPageDown
        RET     C
        LD      A,(EditorNavCurrentPage)
        LD      (StalePageAfterReturnDown),A
        LD      HL,EditorNavNextPageBuffer
        LD      DE,StaleNextRecordAfterReturnDown
        CALL    CopyRecordText
        CALL    EditorPageDown
        RET     C
        LD      A,(EditorNavCurrentPage)
        LD      (StalePageAfterSecondDown),A
        LD      HL,EditorNavPageBuffer
        LD      DE,StaleCurrentRecordAfterSecondDown
        CALL    CopyRecordText
        LD      HL,EditorNavNextPageBuffer
        LD      DE,StaleNextRecordAfterSecondDown
        CALL    CopyRecordText
        XOR     A
        RET

;! out A,carry,zero
;! clobbers sign,parity,halfCarry,BC,DE,HL,IX,IY
@RunDirtyAdjacentReturnCase:
        CALL    EditorPageDown
        RET     C
        CALL    EditorPageDown
        RET     C
        CALL    EditorMarkCurrentSectorDirty
        RET     C
        CALL    EditorPageUp
        RET     C
        LD      A,(EditorNavCurrentPage)
        LD      (DirtyAdjacentPageAfterUp),A
        LD      A,(EditorNavCachedPageDirty)
        LD      (DirtyAdjacentCacheDirtyAfterUp),A
        CALL    EditorPageDown
        RET     C
        LD      A,(EditorNavCurrentPage)
        LD      (DirtyAdjacentPageAfterReturnDown),A
        LD      A,(EditorNavDirtySectors)
        LD      (DirtyAdjacentDirtySectorsAfterReturnDown),A
        LD      HL,EditorNavPageBuffer
        LD      DE,DirtyAdjacentRecordAfterReturnDown
        CALL    CopyRecordText
        CALL    EditorPageDown
        RET     C
        LD      A,(EditorNavCurrentPage)
        LD      (DirtyAdjacentPageAfterContinueDown),A
        LD      HL,EditorNavPageBuffer
        LD      DE,DirtyAdjacentRecordAfterContinueDown
        CALL    CopyRecordText
        XOR     A
        RET

;! out A,carry,zero
;! clobbers sign,parity,halfCarry,BC,DE,HL,IX,IY
@RunDirtyEvictionCase:
        CALL    EditorMarkCurrentSectorDirty
        RET     C
        CALL    EditorPageDown
        RET     C
        LD      A,(EditorNavCurrentPage)
        LD      (DirtyPageAfterFirstDown),A
        LD      A,(EditorNavCachedPageDirty)
        LD      (DirtyCachedPageDirtyAfterFirstDown),A
        CALL    EditorPageDown
        JR      NC,DirtyEvictionUnexpectedSuccess
        LD      (DirtyEvictionError),A
        LD      A,(EditorNavCurrentPage)
        LD      (DirtyPageAfterBlockedDown),A
        XOR     A
        RET

DirtyEvictionUnexpectedSuccess:
        LD      A,0x7F
        SCF
        RET

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
CleanMissCountBefore:
        .db     0
CleanMissCountAfter:
        .db     0
CleanPageAfterFirstDown:
        .db     0
CleanPageAfterSecondDown:
        .db     0
DirtyPageAfterFirstDown:
        .db     0
DirtyPageAfterBlockedDown:
        .db     0
DirtyCachedPageDirtyAfterFirstDown:
        .db     0
DirtyEvictionError:
        .db     0
StalePageAfterReturnDown:
        .db     0
StalePageAfterSecondDown:
        .db     0
DirtyAdjacentPageAfterUp:
        .db     0
DirtyAdjacentCacheDirtyAfterUp:
        .db     0
DirtyAdjacentPageAfterReturnDown:
        .db     0
DirtyAdjacentDirtySectorsAfterReturnDown:
        .db     0
DirtyAdjacentPageAfterContinueDown:
        .db     0
CleanCurrentRecord0:
        .ds     32
CleanNextRecord0:
        .ds     32
CleanCacheRecord0:
        .ds     32
CleanBackupRecord0:
        .ds     32
StaleNextRecordAfterReturnDown:
        .ds     32
StaleCurrentRecordAfterSecondDown:
        .ds     32
StaleNextRecordAfterSecondDown:
        .ds     32
DirtyAdjacentRecordAfterReturnDown:
        .ds     32
DirtyAdjacentRecordAfterContinueDown:
        .ds     32
