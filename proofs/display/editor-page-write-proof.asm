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
        JP      C,ProofFailed

        CALL    EditorOpenMain
        JP      C,ProofFailed
        LD      HL,InitialRow9Bytes
        CALL    CaptureStatusRowTextByte

        LD      A,9
        LD      (EditorCursorRow),A
        LD      (EditorCursorVisibleRow),A
        LD      (EditorNavCurrentRow),A
        CALL    EditorViewportSetCurrentRow
        JP      C,ProofFailed
        CALL    EditorRenderCursor
        JP      C,ProofFailed

        CALL    RunSyntheticControlArrowUp
        JP      C,ProofFailed
        LD      HL,PageUpBoundaryRow9Bytes
        CALL    CaptureStatusRowTextByte

        CALL    EditorRenderCursor
        JP      C,ProofFailed

        LD      A,127
        LD      (EditorNavCurrentPage),A
        LD      A,TECM8_EDITOR_KEY_ARROW_DOWN
        LD      B,TECM8_EDITOR_KEY_MOD_CTRL
        CALL    EditorRunModifiedKey
        JP      C,ProofFailed
        CALL    EditorHideCursor
        JP      C,ProofFailed
        LD      HL,PageDownBoundaryRow9Bytes
        CALL    CaptureStatusRowTextByte
        XOR     A
        LD      (EditorNavCurrentPage),A
        CALL    EditorRenderCurrent
        JP      C,ProofFailed
        CALL    EditorCursorReset
        JP      C,ProofFailed

        LD      A,8
        LD      (EditorCursorCol),A
        LD      HL,EditorNoopDeleteKeys
        CALL    EditorRunKeys
        JP      C,ProofFailed
        LD      A,(EditorNavDirty)
        LD      (DirtyAfterNoopDelete),A

        LD      A,15
        LD      (EditorCursorRow),A
        XOR     A
        LD      (EditorCursorCol),A
        INC     A
        LD      (EditorNavNextPageValid),A
        LD      (EditorNavNextPageBuffer + (15 * 32)),A
        LD      HL,EditorNoopSplitKeys
        CALL    EditorRunKeys
        JP      C,ProofFailed
        LD      A,(EditorNavDirty)
        LD      (DirtyAfterNoopSplit),A

        XOR     A
        LD      (EditorCursorRow),A
        LD      (EditorCursorCol),A
        CALL    EditorKeyCurrentRecord
        LD      (HL),31
        LD      HL,EditorNoopInsertKeys
        CALL    EditorRunKeys
        JP      C,ProofFailed
        LD      A,(EditorNavDirty)
        LD      (DirtyAfterNoopInsert),A

        XOR     A
        LD      (EditorNavCurrentPage),A
        LD      (EditorNavCacheValid),A
        LD      (EditorNavCachedPageDirty),A
        LD      (EditorNavDirtySectors),A
        CALL    EditorRenderCurrent
        JP      C,ProofFailed
        CALL    EditorCursorReset
        JP      C,ProofFailed

        LD      HL,EditorPageEditKeys
        CALL    EditorRunKeys
        JP      C,ProofFailed

        LD      A,(EditorNavDirty)
        LD      (DirtyAfterEdit),A

        LD      HL,EditorPageSaveKeys
        CALL    EditorRunKeys
        JP      C,ProofFailed

        LD      A,(EditorNavDirty)
        LD      (DirtyAfterSave),A

        LD      HL,EditorCleanQuitKeys
        CALL    EditorRunKeys
        JP      C,ProofFailed
        LD      A,(EditorQuitRequested)
        LD      (QuitAfterClean),A

        LD      HL,EditorPromptProofText
        CALL    EditorPromptAskYesNo
        JP      C,ProofFailed
        LD      HL,PromptOverlayRow9Bytes
        CALL    CaptureStatusRowTextByte
        LD      HL,EditorPromptIgnoreKeys
        CALL    EditorRunKeys
        JP      C,ProofFailed
        LD      A,(EditorPromptActive)
        LD      (PromptActiveAfterIgnore),A
        LD      A,(EditorPromptResult)
        LD      (PromptResultAfterIgnore),A

        LD      HL,EditorPromptYesKeys
        CALL    EditorRunKeys
        JP      C,ProofFailed
        LD      HL,PromptRestoredRow9Bytes
        CALL    CaptureStatusRowTextByte
        LD      A,(EditorPromptActive)
        LD      (PromptActiveAfterYes),A
        LD      A,(EditorPromptResult)
        LD      (PromptResultAfterYes),A

        LD      HL,EditorRestoreNoKeys
        CALL    EditorRunKeys
        JP      C,ProofFailed
        LD      A,(EditorNavDirty)
        LD      (DirtyAfterRestoreNo),A
        LD      HL,EditorNavPageBuffer
        LD      A,(HL)
        LD      (RestoreNoRecord0Length),A
        INC     HL
        LD      A,(HL)
        LD      (RestoreNoRecord0FirstChar),A

        LD      HL,EditorRestoreEscKeys
        CALL    EditorRunKeys
        JP      C,ProofFailed
        LD      A,(EditorNavDirty)
        LD      (DirtyAfterRestoreEsc),A
        LD      HL,EditorNavPageBuffer
        LD      A,(HL)
        LD      (RestoreEscRecord0Length),A
        INC     HL
        LD      A,(HL)
        LD      (RestoreEscRecord0FirstChar),A

        LD      HL,EditorRestoreYesKeys
        CALL    EditorRunKeys
        JP      C,ProofFailed
        LD      A,(EditorNavDirty)
        LD      (DirtyAfterRestore),A
        LD      HL,EditorNavPageBuffer
        LD      A,(HL)
        LD      (RestoreRecord0Length),A
        INC     HL
        LD      A,(HL)
        LD      (RestoreRecord0FirstChar),A

        LD      HL,EditorDirtyQuitNoKeys
        CALL    EditorRunKeys
        JP      C,ProofFailed
        LD      A,(EditorQuitRequested)
        LD      (QuitAfterDirtyNo),A
        LD      A,(EditorPromptResult)
        LD      (PromptResultAfterQuitNo),A

        LD      HL,EditorDirtyQuitYesKeys
        CALL    EditorRunKeys
        JP      C,ProofFailed
        LD      A,(EditorQuitRequested)
        LD      (QuitAfterDirtyYes),A
        LD      A,(EditorPromptResult)
        LD      (PromptResultAfterQuitYes),A

        LD      A,PROOF_PASS
        LD      (ResultMarker),A

ProofDone:
        JP      ProofDone

;!      out       A,carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@RunSyntheticControlArrowUp:
        LD      A,TECM8_EDITOR_KEY_ARROW_UP
        LD      (BiosInputRawPrimary),A
        LD      A,0x01
        LD      (BiosInputRawSecondary),A
        LD      A,TECM8_EDITOR_KEY_ARROW_UP
        LD      B,TECM8_EDITOR_KEY_MOD_CTRL
        CALL    EditorRunModifiedKey
        JR      C,RunSyntheticControlArrowUpErr
        LD      A,0xFF
        LD      (BiosInputRawPrimary),A
        LD      (BiosInputRawSecondary),A
        XOR     A
        RET

RunSyntheticControlArrowUpErr:
        LD      B,A
        LD      A,0xFF
        LD      (BiosInputRawPrimary),A
        LD      (BiosInputRawSecondary),A
        LD      A,B
        SCF
        RET

ProofFailed:
        OR      PROOF_FAIL
        LD      (ResultMarker),A

ProofFailedDone:
        JP      ProofDone

; Capture one text byte from each pixel row of the transient status row. This
; lets the host proof compare prompt-visible and source-restored row states.
; Input: HL = six-byte destination
;!      in        HL
;!      out       carry,zero
;!      clobbers  A,BC,DE,HL
@CaptureStatusRowTextByte:
        LD      DE,MON3_TGBUF + ((TECM8_DISPLAY_STATUS_ROW * TECM8_DISPLAY_ROW_HEIGHT + TECM8_DISPLAY_Y_ORIGIN) * TECM8_DISPLAY_ROW_BYTES) + 1
        CALL    CaptureStatusRowOneByte
        CALL    CaptureStatusRowOneByte
        CALL    CaptureStatusRowOneByte
        CALL    CaptureStatusRowOneByte
        CALL    CaptureStatusRowOneByte
        CALL    CaptureStatusRowOneByte
        XOR     A
        RET

;!      in        DE,HL
;!      out       DE,HL,carry,halfCarry
;!      clobbers  A,BC,carry,halfCarry
@CaptureStatusRowOneByte:
        LD      A,(DE)
        LD      (HL),A
        INC     HL
        EX      DE,HL
        LD      BC,TECM8_DISPLAY_ROW_BYTES
        ADD     HL,BC
        EX      DE,HL
        RET

        .include "../../src/glcd-tile.asm"
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

EditorCleanQuitKeys:
        .db     17,0

EditorNoopDeleteKeys:
        .db     127,0

EditorNoopSplitKeys:
        .db     13,0

EditorNoopInsertKeys:
        .db     9,"!",0

EditorPromptIgnoreKeys:
        .db     "x",0

EditorPromptYesKeys:
        .db     "Y",0

EditorRestoreYesKeys:
        .db     26,"Y",0

EditorRestoreNoKeys:
        .db     26,"N",0

EditorRestoreEscKeys:
        .db     26,27,0

EditorDirtyQuitNoKeys:
        .db     17,"N",0

EditorDirtyQuitYesKeys:
        .db     17,"Y",0

EditorPromptProofText:
        .db     "Confirm? Y/N",0

DirtyAfterNoopDelete:
        .db     0

PageUpBoundaryRow9Bytes:
        .ds     TECM8_DISPLAY_ROW_HEIGHT

InitialRow9Bytes:
        .ds     TECM8_DISPLAY_ROW_HEIGHT

PageDownBoundaryRow9Bytes:
        .ds     TECM8_DISPLAY_ROW_HEIGHT

DirtyAfterNoopSplit:
        .db     0

DirtyAfterNoopInsert:
        .db     0

DirtyAfterEdit:
        .db     0

DirtyAfterSave:
        .db     0

QuitAfterClean:
        .db     0

PromptActiveAfterIgnore:
        .db     0

PromptResultAfterIgnore:
        .db     0

PromptActiveAfterYes:
        .db     0

PromptResultAfterYes:
        .db     0

PromptOverlayRow9Bytes:
        .ds     6

PromptRestoredRow9Bytes:
        .ds     6

DirtyAfterRestore:
        .db     0

DirtyAfterRestoreNo:
        .db     0

DirtyAfterRestoreEsc:
        .db     0

RestoreNoRecord0Length:
        .db     0

RestoreNoRecord0FirstChar:
        .db     0

RestoreEscRecord0Length:
        .db     0

RestoreEscRecord0FirstChar:
        .db     0

RestoreRecord0Length:
        .db     0

RestoreRecord0FirstChar:
        .db     0

QuitAfterDirtyNo:
        .db     0

PromptResultAfterQuitNo:
        .db     0

QuitAfterDirtyYes:
        .db     0

PromptResultAfterQuitYes:
        .db     0

ResultMarker:
        .db     0
