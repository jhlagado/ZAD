; TECM8 editor whole-line block selection and pending block mutation.

; EditorBlockSelectionBeginIfNeeded -
; Start an exclusive-endpoint whole-line block selection at the current
; absolute line if no ordinary selection is already active.
;! out A,carry,zero
;! clobbers sign,parity,halfCarry,HL
@EditorBlockSelectionBeginIfNeeded:
        LD      A,(EditorBlockSelectionActive)
        OR      A
        RET     NZ
        CALL    EditorBlockSelectionCurrentLine
        LD      A,L
        LD      (EditorBlockSelectionAnchorLo),A
        LD      (EditorBlockSelectionActiveLo),A
        LD      A,H
        LD      (EditorBlockSelectionAnchorHi),A
        LD      (EditorBlockSelectionActiveHi),A
        LD      A,1
        LD      (EditorBlockSelectionActive),A
        XOR     A
        RET

; EditorBlockSelectionCapturePageAnchor -
; Save the current absolute line and active state before a page-selection move.
;! out A,carry,zero
;! clobbers sign,parity,halfCarry,HL
@EditorBlockSelectionCapturePageAnchor:
        LD      A,(EditorBlockSelectionActive)
        LD      (EditorBlockSelectionPageWasActive),A
        ; expects out HL
        CALL    EditorBlockSelectionCurrentLine
        LD      A,L
        LD      (EditorBlockSelectionPageAnchorLo),A
        LD      A,H
        LD      (EditorBlockSelectionPageAnchorHi),A
        XOR     A
        RET

; EditorBlockSelectionRestorePageAnchor -
; Ensure a successful page-selection move has an anchor. Existing selections
; keep their original anchor; fresh page selections anchor at the old line.
;! out A,carry,zero
;! clobbers sign,parity,halfCarry
@EditorBlockSelectionRestorePageAnchor:
        LD      A,(EditorBlockSelectionPageWasActive)
        OR      A
        JR      NZ,EditorBlockSelectionRestoreExisting
        LD      A,(EditorBlockSelectionPageAnchorLo)
        LD      (EditorBlockSelectionAnchorLo),A
        LD      A,(EditorBlockSelectionPageAnchorHi)
        LD      (EditorBlockSelectionAnchorHi),A

EditorBlockSelectionRestoreExisting:
        LD      A,1
        LD      (EditorBlockSelectionActive),A
        XOR     A
        RET

; EditorBlockSelectionUpdateActive -
; Move the active end of the ordinary selection to the current absolute line.
;! out A,carry,zero
;! clobbers sign,parity,halfCarry,HL
@EditorBlockSelectionUpdateActive:
        ; expects out HL
        CALL    EditorBlockSelectionCurrentLine
        LD      A,L
        LD      (EditorBlockSelectionActiveLo),A
        LD      A,H
        LD      (EditorBlockSelectionActiveHi),A
        LD      A,(EditorBlockSelectionAnchorHi)
        CP      H
        JR      NZ,EditorBlockSelectionUpdateStillActive
        LD      A,(EditorBlockSelectionAnchorLo)
        CP      L
        JR      NZ,EditorBlockSelectionUpdateStillActive
        XOR     A
        LD      (EditorBlockSelectionActive),A
        RET

EditorBlockSelectionUpdateStillActive:
        LD      A,1
        LD      (EditorBlockSelectionActive),A
        XOR     A
        RET

; EditorBlockSelectionClearState -
; Clear ordinary selection state without repainting. Used before full page
; renders and cursor resets.
;! out carry,zero,A,sign,parity,halfCarry
@EditorBlockSelectionClearState:
        XOR     A
        LD      (EditorBlockSelectionActive),A
        RET

; EditorPendingBlockClearState -
; Clear the pending copy/move source without repainting.
;! out carry,zero,A,sign,parity,halfCarry
@EditorPendingBlockClearState:
        XOR     A
        LD      (EditorPendingBlockMode),A
        RET

; EditorPendingBlockArm -
; Convert the ordinary selected range into a pending copy/move source.
; Input: A = TECM8_EDITOR_PENDING_BLOCK_COPY or *_MOVE.
;! in A
;! out BC,DE,A,carry,zero
;! clobbers sign,parity,halfCarry,HL
@EditorPendingBlockArm:
        LD      (EditorPendingBlockRequestedMode),A
        LD      A,(EditorBlockSelectionActive)
        OR      A
        JR      Z,EditorPendingBlockArmNoSelection
        LD      A,(EditorBlockSelectionAnchorHi)
        LD      H,A
        LD      A,(EditorBlockSelectionAnchorLo)
        LD      L,A
        LD      A,(EditorBlockSelectionActiveHi)
        LD      D,A
        LD      A,(EditorBlockSelectionActiveLo)
        LD      E,A
        CALL    EditorBlockSelectionCompareHlDe
        JR      Z,EditorPendingBlockArmNoSelection
        CALL    EditorBlockSelectionNormalize
        LD      A,(EditorBlockSelectionStartLo)
        LD      (EditorPendingBlockStartLo),A
        LD      A,(EditorBlockSelectionStartHi)
        LD      (EditorPendingBlockStartHi),A
        LD      A,(EditorBlockSelectionEndLo)
        LD      (EditorPendingBlockEndLo),A
        LD      A,(EditorBlockSelectionEndHi)
        LD      (EditorPendingBlockEndHi),A
        LD      A,(EditorPendingBlockRequestedMode)
        LD      (EditorPendingBlockMode),A
        CALL    EditorBlockSelectionClearState
        XOR     A
        RET

EditorPendingBlockArmNoSelection:
        CALL    EditorPendingBlockClearState
        XOR     A
        RET

; EditorPendingBlockPasteInsert -
; Insert pending source rows before the cursor when no destination selection is
; active. The first version is conservative: source and destination must be in
; the current resident page, unsafe overlap/self cases are rejected, and empty
; tail rows must exist so no records are discarded.
;! out A,carry,zero
;! clobbers sign,parity,halfCarry,BC,DE,HL
@EditorPendingBlockPasteInsert:
        LD      A,(EditorPendingBlockMode)
        OR      A
        JP      Z,EditorPendingBlockPasteNoop
        LD      (EditorPendingBlockPasteMode),A
        LD      A,(EditorBlockSelectionActive)
        OR      A
        JP      NZ,EditorPendingBlockPasteReplace
        CALL    EditorPendingBlockRowsForCurrentPage
        JP      C,EditorPendingBlockPasteNoop
        CALL    EditorPendingBlockRejectInsertOverlap
        JP      C,EditorPendingBlockPasteNoop
        CALL    EditorPendingBlockTailAvailable
        JP      Z,EditorPendingBlockPasteNoop
        CALL    EditorPendingBlockCopySourceToScratch
        RET     C
        CALL    EditorPendingBlockShiftRowsDown
        RET     C
        CALL    EditorPendingBlockCopyScratchToDest
        RET     C
        LD      A,(EditorPendingBlockPasteMode)
        CP      TECM8_EDITOR_PENDING_BLOCK_MOVE
        JR      NZ,EditorPendingBlockPasteSelectInserted
        CALL    EditorPendingBlockDeleteMovedSource
        RET     C

EditorPendingBlockPasteSelectInserted:
        CALL    EditorPendingBlockSelectInsertedRows
        CALL    EditorPendingBlockClearState
        CALL    EditorMarkDirty
        LD      A,1
        RET

EditorPendingBlockPasteNoop:
        XOR     A
        RET

; EditorPendingBlockPasteReplace -
; Replace an ordinary destination selection with a pending copy or move source.
; This first B6 slice is intentionally narrow: current page only, equal-sized
; ranges only, and no overlap.
;! out A,carry
;! clobbers zero,sign,parity,halfCarry,BC,DE,HL
@EditorPendingBlockPasteReplace:
        CALL    EditorPendingBlockRowsForCurrentPage
        JP      C,EditorPendingBlockPasteNoop
        CALL    EditorPendingBlockDestinationRowsForCurrentPage
        JP      C,EditorPendingBlockPasteNoop
        CALL    EditorPendingBlockRejectReplaceOverlap
        JP      C,EditorPendingBlockPasteNoop
        CALL    EditorPendingBlockReplaceSameSize
        JP      NZ,EditorPendingBlockPasteNoop
        LD      A,(EditorPendingBlockDestStartRow)
        LD      (EditorPendingBlockDestRow),A
        CALL    EditorPendingBlockCopySourceToScratch
        RET     C
        CALL    EditorPendingBlockCopyScratchToDest
        RET     C
        LD      A,(EditorPendingBlockPasteMode)
        CP      TECM8_EDITOR_PENDING_BLOCK_MOVE
        JR      NZ,EditorPendingBlockPasteReplaceSelect
        CALL    EditorPendingBlockDeleteOriginalSource
        RET     C

EditorPendingBlockPasteReplaceSelect:
        CALL    EditorPendingBlockSelectInsertedRows
        CALL    EditorPendingBlockClearState
        CALL    EditorMarkDirty
        LD      A,1
        RET

;! out A,L,carry,zero
;! clobbers sign,parity,halfCarry,BC,H
@EditorPendingBlockRowsForCurrentPage:
        CALL    EditorPendingBlockPageBaseForCurrentPage
        LD      A,(EditorPendingBlockStartHi)
        LD      H,A
        LD      A,(EditorPendingBlockPageBaseHi)
        CP      H
        JR      NZ,EditorPendingBlockRowsErr
        LD      A,(EditorPendingBlockEndHi)
        LD      H,A
        LD      A,(EditorPendingBlockPageBaseHi)
        CP      H
        JR      NZ,EditorPendingBlockRowsErr
        LD      A,(EditorPendingBlockStartLo)
        LD      B,A
        LD      A,(EditorPendingBlockPageBaseLo)
        LD      C,A
        LD      A,B
        SUB     C
        CP      16
        JR      NC,EditorPendingBlockRowsErr
        LD      (EditorPendingBlockSourceStartRow),A
        LD      B,A
        LD      A,(EditorPendingBlockEndLo)
        SUB     C
        CP      16
        JR      NC,EditorPendingBlockRowsErr
        LD      (EditorPendingBlockSourceEndRow),A
        SUB     B
        JR      C,EditorPendingBlockRowsErr
        INC     A
        LD      (EditorPendingBlockRowCount),A
        XOR     A
        RET

;! out A,carry,zero,HL
;! clobbers sign,parity,halfCarry
@EditorPendingBlockPageBaseForCurrentPage:
        LD      A,(EditorNavCurrentPage)
        LD      H,0
        LD      L,A
        ADD     HL,HL
        ADD     HL,HL
        ADD     HL,HL
        ADD     HL,HL
        LD      A,L
        LD      (EditorPendingBlockPageBaseLo),A
        LD      A,H
        LD      (EditorPendingBlockPageBaseHi),A
        XOR     A
        RET

EditorPendingBlockRowsErr:
        SCF
        RET

;! out DE,A,carry,zero
;! clobbers sign,parity,halfCarry,BC,HL
@EditorPendingBlockDestinationRowsForCurrentPage:
        CALL    EditorBlockSelectionNormalize
        LD      A,(EditorBlockSelectionStartHi)
        LD      B,A
        LD      A,(EditorPendingBlockPageBaseHi)
        CP      B
        JR      NZ,EditorPendingBlockDestinationRowsErr
        LD      A,(EditorBlockSelectionEndHi)
        LD      B,A
        LD      A,(EditorPendingBlockPageBaseHi)
        CP      B
        JR      NZ,EditorPendingBlockDestinationRowsErr
        LD      A,(EditorBlockSelectionStartLo)
        LD      B,A
        LD      A,(EditorPendingBlockPageBaseLo)
        LD      C,A
        LD      A,B
        SUB     C
        CP      16
        JR      NC,EditorPendingBlockDestinationRowsErr
        LD      (EditorPendingBlockDestStartRow),A
        LD      B,A
        LD      A,(EditorBlockSelectionEndLo)
        SUB     C
        CP      16
        JR      NC,EditorPendingBlockDestinationRowsErr
        LD      (EditorPendingBlockDestEndRow),A
        SUB     B
        JR      C,EditorPendingBlockDestinationRowsErr
        INC     A
        LD      (EditorPendingBlockDestRowCount),A
        XOR     A
        RET

EditorPendingBlockDestinationRowsErr:
        SCF
        RET

;! out A,carry,zero
;! clobbers sign,parity,halfCarry,B
@EditorPendingBlockRejectInsertOverlap:
        LD      A,(EditorCursorRow)
        LD      (EditorPendingBlockDestRow),A
        LD      B,A
        LD      A,(EditorPendingBlockSourceStartRow)
        CP      B
        JR      Z,EditorPendingBlockRejectOverlap
        JR      NC,EditorPendingBlockRejectNoOverlap
        LD      A,(EditorPendingBlockSourceEndRow)
        INC     A
        CP      B
        JR      NC,EditorPendingBlockRejectOverlap

EditorPendingBlockRejectNoOverlap:
        XOR     A
        RET

EditorPendingBlockRejectOverlap:
        SCF
        RET

;! out A,carry,zero
;! clobbers sign,parity,halfCarry,B
@EditorPendingBlockRejectReplaceOverlap:
        LD      A,(EditorPendingBlockDestEndRow)
        LD      B,A
        LD      A,(EditorPendingBlockSourceStartRow)
        CP      B
        JR      Z,EditorPendingBlockReplaceOverlap
        JR      NC,EditorPendingBlockReplaceNoOverlap
        LD      A,(EditorPendingBlockSourceEndRow)
        LD      B,A
        LD      A,(EditorPendingBlockDestStartRow)
        CP      B
        JR      Z,EditorPendingBlockReplaceOverlap
        JR      C,EditorPendingBlockReplaceOverlap

EditorPendingBlockReplaceNoOverlap:
        XOR     A
        RET

EditorPendingBlockReplaceOverlap:
        SCF
        RET

;! out A,carry,zero
;! clobbers sign,parity,halfCarry,B
@EditorPendingBlockReplaceSameSize:
        LD      A,(EditorPendingBlockDestRowCount)
        LD      B,A
        LD      A,(EditorPendingBlockRowCount)
        CP      B
        RET

;! out A,carry,zero
;! clobbers sign,parity,halfCarry,BC,HL
@EditorPendingBlockTailAvailable:
        LD      A,16
        LD      B,A
        LD      A,(EditorPendingBlockRowCount)
        CP      B
        JR      NC,EditorPendingBlockTailNo
        LD      A,B
        LD      B,A
        LD      A,(EditorPendingBlockRowCount)
        LD      C,A
        LD      A,B
        SUB     C
        LD      (EditorPendingBlockTailCheckRow),A

EditorPendingBlockTailCheckLoop:
        LD      A,(EditorPendingBlockTailCheckRow)
        CP      16
        JR      Z,EditorPendingBlockTailYes
        CALL    EditorKeyRecordAtRow
        CALL    EditorKeyReadRecordLength
        OR      A
        JR      NZ,EditorPendingBlockTailNo
        LD      A,(EditorPendingBlockTailCheckRow)
        INC     A
        LD      (EditorPendingBlockTailCheckRow),A
        JR      EditorPendingBlockTailCheckLoop

EditorPendingBlockTailYes:
        LD      A,1
        OR      A
        RET

EditorPendingBlockTailNo:
        XOR     A
        RET

;! out A,carry,zero
;! clobbers sign,parity,halfCarry,BC,DE,HL
@EditorPendingBlockCopySourceToScratch:
        CALL    EditorNavInvalidateWindowSlot3
        LD      A,(EditorPendingBlockSourceStartRow)
        CALL    EditorKeyRecordAtRow
        LD      DE,EditorNavBackupPageBuffer
        LD      A,(EditorPendingBlockRowCount)
        CALL    Tecm8RecordShiftRecordsUp
        RET

;! out A,carry,zero
;! clobbers sign,parity,halfCarry,BC,DE,HL
@EditorPendingBlockShiftRowsDown:
        LD      A,16
        LD      B,A
        LD      A,(EditorPendingBlockRowCount)
        LD      C,A
        LD      A,B
        SUB     C
        LD      (EditorPendingBlockShiftRow),A
        LD      A,(EditorPendingBlockDestRow)
        LD      B,A
        LD      A,(EditorPendingBlockShiftRow)
        CP      B
        JR      C,EditorPendingBlockShiftDone
        LD      A,(EditorPendingBlockShiftRow)
        LD      B,A
        LD      A,(EditorPendingBlockDestRow)
        LD      C,A
        LD      A,B
        SUB     C
        INC     A
        LD      (EditorLineRowsLeft),A
        LD      A,(EditorPendingBlockShiftRow)
        CALL    EditorKeyRecordAtRow
        LD      (EditorLineSrc),HL
        LD      A,(EditorPendingBlockShiftRow)
        LD      B,A
        LD      A,(EditorPendingBlockRowCount)
        ADD     A,B
        CALL    EditorKeyRecordAtRow
        LD      D,H
        LD      E,L
        LD      HL,(EditorLineSrc)
        LD      A,(EditorLineRowsLeft)
        CALL    Tecm8RecordShiftRecordsDown

EditorPendingBlockShiftDone:
        XOR     A
        RET

;! out A,carry,zero
;! clobbers sign,parity,halfCarry,BC,DE,HL
@EditorPendingBlockCopyScratchToDest:
        CALL    EditorNavInvalidateWindowSlot3
        LD      A,(EditorPendingBlockDestRow)
        ; expects out HL
        CALL    EditorKeyRecordAtRow
        LD      D,H
        LD      E,L
        LD      HL,EditorNavBackupPageBuffer
        LD      A,(EditorPendingBlockRowCount)
        CALL    Tecm8RecordShiftRecordsUp
        RET

;! out A,carry,zero
;! clobbers sign,parity,halfCarry,BC,DE,HL
@EditorPendingBlockDeleteMovedSource:
        LD      A,(EditorPendingBlockSourceStartRow)
        LD      B,A
        LD      A,(EditorPendingBlockDestRow)
        CP      B
        JR      C,EditorPendingBlockDeleteSourceAfterDest
        LD      A,(EditorPendingBlockSourceStartRow)
        JR      EditorPendingBlockDeleteStartReady

EditorPendingBlockDeleteSourceAfterDest:
        LD      A,(EditorPendingBlockSourceStartRow)
        LD      B,A
        LD      A,(EditorPendingBlockRowCount)
        ADD     A,B

EditorPendingBlockDeleteStartReady:
        LD      (EditorPendingBlockDeleteStartRow),A
        LD      A,(EditorPendingBlockDeleteStartRow)
        LD      B,A
        LD      A,(EditorPendingBlockRowCount)
        ADD     A,B
        LD      (EditorPendingBlockShiftRow),A
        LD      A,(EditorPendingBlockShiftRow)
        CP      16
        JR      Z,EditorPendingBlockDeleteClearTail
        LD      B,A
        LD      A,16
        SUB     B
        LD      (EditorLineRowsLeft),A
        LD      A,(EditorPendingBlockShiftRow)
        CALL    EditorKeyRecordAtRow
        LD      (EditorLineSrc),HL
        LD      A,(EditorPendingBlockShiftRow)
        LD      B,A
        LD      A,(EditorPendingBlockRowCount)
        LD      C,A
        LD      A,B
        SUB     C
        CALL    EditorKeyRecordAtRow
        LD      D,H
        LD      E,L
        LD      HL,(EditorLineSrc)
        LD      A,(EditorLineRowsLeft)
        CALL    Tecm8RecordShiftRecordsUp

EditorPendingBlockDeleteClearTail:
        LD      A,16
        LD      B,A
        LD      A,(EditorPendingBlockRowCount)
        LD      C,A
        LD      A,B
        SUB     C
        LD      (EditorPendingBlockTailCheckRow),A

EditorPendingBlockDeleteClearLoop:
        LD      A,(EditorPendingBlockTailCheckRow)
        CP      16
        JR      Z,EditorPendingBlockDeleteDone
        ; expects out HL
        CALL    EditorKeyRecordAtRow
        CALL    EditorKeyClearRecord
        LD      A,(EditorPendingBlockTailCheckRow)
        INC     A
        LD      (EditorPendingBlockTailCheckRow),A
        JR      EditorPendingBlockDeleteClearLoop

EditorPendingBlockDeleteDone:
        XOR     A
        RET

;! out A,carry
;! clobbers zero,sign,parity,halfCarry,BC,DE,HL
@EditorPendingBlockDeleteOriginalSource:
        LD      A,(EditorPendingBlockSourceStartRow)
        JP      EditorPendingBlockDeleteStartReady

;! out carry,zero,A
;! clobbers sign,parity,halfCarry,BC,HL
@EditorPendingBlockSelectInsertedRows:
        LD      A,(EditorPendingBlockDestRow)
        LD      B,A
        LD      A,(EditorPendingBlockPasteMode)
        CP      TECM8_EDITOR_PENDING_BLOCK_MOVE
        JR      NZ,EditorPendingBlockSelectStartReady
        LD      A,(EditorPendingBlockSourceStartRow)
        LD      C,A
        LD      A,(EditorPendingBlockDestRow)
        CP      C
        JR      C,EditorPendingBlockSelectStartReady
        LD      A,(EditorPendingBlockDestRow)
        LD      C,A
        LD      A,(EditorPendingBlockRowCount)
        LD      B,A
        LD      A,C
        SUB     B
        LD      B,A

EditorPendingBlockSelectStartReady:
        LD      A,(EditorPendingBlockPageBaseLo)
        ADD     A,B
        LD      (EditorBlockSelectionAnchorLo),A
        LD      (EditorBlockSelectionActiveLo),A
        LD      A,(EditorPendingBlockPageBaseHi)
        LD      (EditorBlockSelectionAnchorHi),A
        LD      (EditorBlockSelectionActiveHi),A
        LD      A,(EditorPendingBlockRowCount)
        ADD     A,B
        LD      B,A
        LD      A,(EditorPendingBlockPageBaseLo)
        ADD     A,B
        LD      (EditorBlockSelectionActiveLo),A
        LD      C,A
        LD      A,(EditorPendingBlockPageBaseHi)
        ADC     A,0
        LD      (EditorBlockSelectionActiveHi),A
        LD      A,1
        LD      (EditorBlockSelectionActive),A
        LD      A,C
        CP      16
        JR      C,EditorPendingBlockCursorRowReady
        LD      A,15

EditorPendingBlockCursorRowReady:
        LD      (EditorCursorRow),A
        XOR     A
        LD      (EditorCursorCol),A
        RET

; EditorBlockSelectionClearIfActive -
; Clear ordinary selection state and repaint visible gutter markers when needed.
;! out A,carry
;! clobbers zero,sign,parity,halfCarry,BC,DE,HL
@EditorBlockSelectionClearIfActive:
        LD      A,(EditorBlockSelectionActive)
        OR      A
        RET     Z
        CALL    EditorHideCursor
        RET     C
        CALL    EditorBlockSelectionClearState
        JP      EditorBlockSelectionRenderMarkers

; EditorBlockStateClearForEdit -
; Clear ordinary selection and pending source before mutating source records.
;! out A,carry
;! clobbers zero,sign,parity,halfCarry,BC,DE,HL
@EditorBlockStateClearForEdit:
        LD      A,(EditorBlockSelectionActive)
        LD      B,A
        LD      A,(EditorPendingBlockMode)
        OR      B
        RET     Z
        CALL    EditorHideCursor
        RET     C
        CALL    EditorBlockSelectionClearState
        CALL    EditorPendingBlockClearState
        JP      EditorBlockSelectionRenderMarkers

; EditorBlockSelectionRenderMarkers -
; Repaint all visible gutter markers after a selection range change.
;! out A,carry,zero
;! clobbers sign,parity,halfCarry,BC,DE,HL
@EditorBlockSelectionRenderMarkers:
        XOR     A
        LD      (EditorBlockSelectionMarkerRow),A

EditorBlockSelectionRenderMarkerLoop:
        LD      A,(EditorBlockSelectionMarkerRow)
        CALL    EditorViewportRenderRowMarker
        RET     C
        LD      A,(EditorBlockSelectionMarkerRow)
        CALL    GlcdTileMarkGutterDirty
        RET     C
        LD      A,(EditorBlockSelectionMarkerRow)
        INC     A
        LD      (EditorBlockSelectionMarkerRow),A
        CP      TECM8_EDITOR_CURSOR_VISIBLE_ROWS
        JR      NZ,EditorBlockSelectionRenderMarkerLoop
        XOR     A
        RET

; EditorBlockSelectionCurrentLine -
; Compute the current absolute source line as page * 16 + current row.
;! out HL,A,carry,zero
;! clobbers sign,parity,halfCarry
@EditorBlockSelectionCurrentLine:
        LD      A,(EditorNavCurrentPage)
        LD      H,0
        LD      L,A
        ADD     HL,HL
        ADD     HL,HL
        ADD     HL,HL
        ADD     HL,HL
        LD      A,(EditorCursorRow)
        ADD     A,L
        LD      L,A
        JR      NC,EditorBlockSelectionCurrentLineDone
        INC     H

EditorBlockSelectionCurrentLineDone:
        XOR     A
        RET

;! out A,carry,zero
;! clobbers sign,parity,halfCarry,BC,DE,HL
@EditorDeleteSelectedBlock:
        LD      A,(EditorBlockSelectionActive)
        OR      A
        JP      Z,EditorDeleteSelectedBlockNoop
        CALL    EditorPendingBlockPageBaseForCurrentPage
        CALL    EditorPendingBlockDestinationRowsForCurrentPage
        JP      C,EditorDeleteSelectedBlockNoop
        LD      A,(EditorPendingBlockDestStartRow)
        LD      (EditorPendingBlockSourceStartRow),A
        LD      A,(EditorPendingBlockDestRowCount)
        LD      (EditorPendingBlockRowCount),A
        CALL    EditorPendingBlockDeleteOriginalSource
        RET     C
        CALL    EditorBlockSelectionClearState
        CALL    EditorPendingBlockClearState
        LD      A,(EditorPendingBlockDestStartRow)
        LD      (EditorCursorRow),A
        XOR     A
        LD      (EditorCursorCol),A
        CALL    EditorMarkDirty
        LD      A,1
        RET

EditorDeleteSelectedBlockNoop:
        XOR     A
        RET

EditorBlockSelectionPageWasActive:
        .db     0

EditorBlockSelectionPageAnchorLo:
        .db     0

EditorBlockSelectionPageAnchorHi:
        .db     0

EditorPendingBlockRequestedMode:
        .db     0

EditorPendingBlockPasteMode:
        .db     0

EditorPendingBlockPageBaseLo:
        .db     0

EditorPendingBlockPageBaseHi:
        .db     0

EditorPendingBlockSourceStartRow:
        .db     0

EditorPendingBlockSourceEndRow:
        .db     0

EditorPendingBlockRowCount:
        .db     0

EditorPendingBlockDestRow:
        .db     0

EditorPendingBlockTailCheckRow:
        .db     0

EditorPendingBlockShiftRow:
        .db     0

EditorPendingBlockDeleteStartRow:
        .db     0

EditorPendingBlockDestStartRow:
        .db     0

EditorPendingBlockDestEndRow:
        .db     0

EditorPendingBlockDestRowCount:
        .db     0
