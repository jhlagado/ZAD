; TECM8 editor viewport proof module.
;
; Converts fixed 32-byte Pascal-string source records into the structured
; display descriptor consumed by DisplayRenderScreen.

TECM8_EDITOR_RECORD_BYTES          .equ    32
TECM8_EDITOR_VISIBLE_ROWS          .equ    10
TECM8_EDITOR_VISIBLE_COLS          .equ    20
TECM8_EDITOR_MAX_RECORD_TEXT       .equ    31
TECM8_EDITOR_RECORD_LENGTH_MASK    .equ    0x1F
TECM8_EDITOR_ROW_TEXT_BYTES        .equ    32
TECM8_EDITOR_ERR_ROW               .equ    0x02

; EditorViewportRender -
; Render ten 32-byte source records in the sector/window at HL, starting at
; EditorViewportTopRow.
; Input: HL = source record window
;!      in        HL
;!      out       A,carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@EditorViewportRender:
        LD      (EditorRecordBasePtr),HL
        CALL    EditorViewportTopRecordPtr
        LD      (EditorRecordPtr),HL
        LD      HL,EditorRowText0
        LD      (EditorTextPtr),HL
        XOR     A
        LD      (EditorRowIndex),A

EditorViewportBuildLoop:
        CALL    EditorViewportCopyRecord
        RET     C
        LD      A,(EditorRowIndex)
        INC     A
        LD      (EditorRowIndex),A
        CP      TECM8_EDITOR_VISIBLE_ROWS
        JR      NZ,EditorViewportBuildLoop

        CALL    EditorViewportRefreshMarkers
        LD      HL,EditorScreenDescriptor
        CALL    DisplayRenderScreen
        RET

; EditorViewportRenderRecordRow -
; Copy one source record into its row text buffer and redraw that display row.
; Input: A = visible row (0-9), HL = source record
;!      in        A,HL
;!      out       A,carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@EditorViewportRenderRecordRow:
        LD      (EditorViewportRenderRecordRowInput),A
        LD      A,(EditorViewportRenderRecordRowCount)
        INC     A
        LD      (EditorViewportRenderRecordRowCount),A
        LD      A,(EditorViewportRenderRecordRowInput)
        CP      TECM8_EDITOR_VISIBLE_ROWS
        JP      NC,EditorViewportRowError
        LD      (EditorRowIndex),A
        LD      (EditorRecordPtr),HL
        CALL    EditorViewportRowTextPtr
        LD      (EditorTextPtr),HL
        CALL    EditorViewportCopyRecord
        RET     C
        LD      A,(EditorRowIndex)
        CALL    EditorViewportMarkerForRow
        LD      A,(EditorRowIndex)
        LD      HL,(EditorTextPtr)
        LD      DE,0 - TECM8_EDITOR_ROW_TEXT_BYTES
        ADD     HL,DE
        CALL    DisplayRenderLine
        RET

; EditorViewportSetTopRow -
; Select the first logical source row rendered at visible row 0.
; Input: A = logical row 0-6
;!      in        A
;!      out       A,carry
;!      clobbers  A,zero,sign,parity,halfCarry
@EditorViewportSetTopRow:
        CP      7
        JR      NC,EditorViewportRowError
        LD      (EditorViewportTopRow),A
        XOR     A
        RET

; EditorViewportSetColOffset -
; Select the first logical source column rendered at visible column 0.
; Input: A = logical column 0-11
;!      in        A
;!      out       A,carry
;!      clobbers  A,zero,sign,parity,halfCarry
@EditorViewportSetColOffset:
        CP      12
        JR      NC,EditorViewportRowError
        LD      (EditorViewportColOffset),A
        XOR     A
        RET

;!      out       HL,A,carry,zero
;!      clobbers  A,B,DE,zero,sign,parity,halfCarry
@EditorViewportTopRecordPtr:
        LD      HL,(EditorRecordBasePtr)
        LD      A,(EditorViewportTopRow)
        OR      A
        RET     Z
        LD      B,A
        LD      DE,TECM8_EDITOR_RECORD_BYTES

EditorViewportTopRecordPtrLoop:
        ADD     HL,DE
        DJNZ    EditorViewportTopRecordPtrLoop
        XOR     A
        RET

;!      in        A
;!      out       HL,carry
;!      clobbers  A,B,DE,zero,sign,parity,halfCarry
@EditorViewportRowTextPtr:
        LD      HL,EditorRowText0
        OR      A
        RET     Z
        LD      B,A
        LD      DE,TECM8_EDITOR_ROW_TEXT_BYTES

EditorViewportRowTextPtrLoop:
        ADD     HL,DE
        DJNZ    EditorViewportRowTextPtrLoop
        XOR     A
        RET

; EditorViewportSetCurrentRow -
; Select the visible source row that should receive the current-line gutter mark.
; Input: A = visible row (0-9)
;!      in        A
;!      out       A,carry
;!      clobbers  A,zero,sign,parity,halfCarry
@EditorViewportSetCurrentRow:
        CP      TECM8_EDITOR_VISIBLE_ROWS
        JR      NC,EditorViewportRowError
        LD      (EditorViewportCurrentRow),A
        XOR     A
        RET

;!      in        A
;!      out       C,carry
;!      clobbers  A,C,HL,zero,sign,parity,halfCarry
@EditorViewportMarkerForRow:
        LD      HL,EditorViewportCurrentRow
        CP      (HL)
        JR      Z,EditorViewportMarkerCurrent
        LD      C,TECM8_DISPLAY_MARKER_NONE
        XOR     A
        RET

EditorViewportMarkerCurrent:
        LD      C,TECM8_DISPLAY_MARKER_CURRENT
        XOR     A
        RET

; EditorViewportRefreshMarkers -
; Rebuild descriptor gutter markers from the current viewport state.
;!      out       A,carry
;!      clobbers  A,BC,HL,zero,sign,parity,halfCarry
@EditorViewportRefreshMarkers:
        LD      HL,EditorScreenDescriptor
        XOR     A
        LD      (EditorRowIndex),A

EditorViewportRefreshMarkersLoop:
        LD      A,(EditorRowIndex)
        PUSH    HL
        CALL    EditorViewportMarkerForRow
        POP     HL
        LD      (HL),C
        INC     HL
        INC     HL
        INC     HL
        LD      A,(EditorRowIndex)
        INC     A
        LD      (EditorRowIndex),A
        CP      TECM8_EDITOR_VISIBLE_ROWS
        JR      NZ,EditorViewportRefreshMarkersLoop
        XOR     A
        RET

EditorViewportRowError:
        LD      A,TECM8_EDITOR_ERR_ROW
        SCF
        RET

; EditorViewportRenderStatusOverlay -
; Temporarily render the active prompt over the last visible source row.
;!      out       A,carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@EditorViewportRenderStatusOverlay:
        LD      HL,(EditorPromptTextPtr)
        LD      A,TECM8_DISPLAY_STATUS_ROW
        LD      C,TECM8_DISPLAY_MARKER_NONE
        CALL    DisplayRenderLine
        RET     C
        CALL    GlcdTileFlushFull
        RET

; EditorViewportRestoreStatusRow -
; Redraw the source row hidden by a transient prompt/status overlay.
;!      out       A,carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@EditorViewportRestoreStatusRow:
        LD      A,TECM8_DISPLAY_STATUS_ROW
        CALL    EditorViewportMarkerForRow
        LD      HL,EditorRowText9
        LD      A,TECM8_DISPLAY_STATUS_ROW
        CALL    DisplayRenderLine
        RET     C
        CALL    GlcdTileFlushFull
        RET

; EditorViewportCopyRecord -
; Copy one Pascal-string record to the next NUL-terminated row text buffer.
;!      out       A,carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@EditorViewportCopyRecord:
        LD      HL,(EditorRecordPtr)
        LD      A,(HL)
        AND     TECM8_EDITOR_RECORD_LENGTH_MASK
        LD      B,A
        INC     HL
        LD      (EditorRecordPtr),HL
        LD      DE,(EditorTextPtr)
        LD      A,B
        OR      A
        JR      Z,EditorViewportTerminateRow
        LD      A,(EditorViewportColOffset)
        LD      C,A
        LD      A,B
        CP      C
        JR      C,EditorViewportTerminateRow
        JR      Z,EditorViewportTerminateRow
        SUB     C
        LD      B,A
        LD      A,C
        OR      A
        JR      Z,EditorViewportCopyCap
        PUSH    DE
        LD      D,0
        LD      E,A
        ADD     HL,DE
        POP     DE

EditorViewportCopyCap:
        LD      A,B
        CP      TECM8_EDITOR_VISIBLE_COLS + 1
        JR      C,EditorViewportCopyLoop
        LD      B,TECM8_EDITOR_VISIBLE_COLS

EditorViewportCopyLoop:
        LD      A,(HL)
        LD      (DE),A
        INC     HL
        INC     DE
        DJNZ    EditorViewportCopyLoop

EditorViewportTerminateRow:
        XOR     A
        LD      (DE),A
        LD      HL,(EditorRecordPtr)
        LD      DE,TECM8_EDITOR_RECORD_BYTES - 1
        ADD     HL,DE
        LD      (EditorRecordPtr),HL
        LD      HL,(EditorTextPtr)
        LD      DE,TECM8_EDITOR_ROW_TEXT_BYTES
        ADD     HL,DE
        LD      (EditorTextPtr),HL
        XOR     A
        RET

EditorScreenDescriptor:
        .db     TECM8_DISPLAY_MARKER_NONE
        .dw     EditorRowText0
        .db     TECM8_DISPLAY_MARKER_NONE
        .dw     EditorRowText1
        .db     TECM8_DISPLAY_MARKER_NONE
        .dw     EditorRowText2
        .db     TECM8_DISPLAY_MARKER_NONE
        .dw     EditorRowText3
        .db     TECM8_DISPLAY_MARKER_NONE
        .dw     EditorRowText4
        .db     TECM8_DISPLAY_MARKER_NONE
        .dw     EditorRowText5
        .db     TECM8_DISPLAY_MARKER_NONE
        .dw     EditorRowText6
        .db     TECM8_DISPLAY_MARKER_NONE
        .dw     EditorRowText7
        .db     TECM8_DISPLAY_MARKER_NONE
        .dw     EditorRowText8
        .db     TECM8_DISPLAY_MARKER_NONE
        .dw     EditorRowText9

EditorPromptActive:
        .db     0

EditorPromptResult:
        .db     0

EditorPromptTextPtr:
        .dw     EditorPromptDefaultText

EditorPromptDefaultText:
        .db     "Confirm? Y/N",0

EditorRecordPtr:
        .dw     0
EditorTextPtr:
        .dw     0
EditorViewportRenderRecordRowInput:
        .db     0
EditorViewportRenderRecordRowCount:
        .db     0
EditorRecordBasePtr:
        .dw     0
EditorRowIndex:
        .db     0

EditorViewportTopRow:
        .db     0

EditorViewportColOffset:
        .db     0

EditorViewportCurrentRow:
        .db     0

EditorRowText0:
        .ds     TECM8_EDITOR_ROW_TEXT_BYTES
EditorRowText1:
        .ds     TECM8_EDITOR_ROW_TEXT_BYTES
EditorRowText2:
        .ds     TECM8_EDITOR_ROW_TEXT_BYTES
EditorRowText3:
        .ds     TECM8_EDITOR_ROW_TEXT_BYTES
EditorRowText4:
        .ds     TECM8_EDITOR_ROW_TEXT_BYTES
EditorRowText5:
        .ds     TECM8_EDITOR_ROW_TEXT_BYTES
EditorRowText6:
        .ds     TECM8_EDITOR_ROW_TEXT_BYTES
EditorRowText7:
        .ds     TECM8_EDITOR_ROW_TEXT_BYTES
EditorRowText8:
        .ds     TECM8_EDITOR_ROW_TEXT_BYTES
EditorRowText9:
        .ds     TECM8_EDITOR_ROW_TEXT_BYTES
