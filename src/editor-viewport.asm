; TECM8 editor viewport proof module.
;
; Converts fixed 32-byte Pascal-string source records into the structured
; display descriptor consumed by DisplayRenderScreen.

TECM8_EDITOR_RECORD_BYTES          .equ    32
TECM8_EDITOR_VISIBLE_ROWS          .equ    10
TECM8_EDITOR_MAX_RECORD_TEXT       .equ    31
TECM8_EDITOR_ROW_TEXT_BYTES        .equ    32
TECM8_EDITOR_ERR_RECORD_LENGTH     .equ    0x01
TECM8_EDITOR_ERR_ROW               .equ    0x02

; EditorViewportRender -
; Render the first ten 32-byte source records in the sector/window at HL.
; Input: HL = source record window
;!      in        HL
;!      out       A,carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@EditorViewportRender:
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
        JR      NC,EditorViewportRowError
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

;!      in        A
;!      out       C,carry
;!      clobbers  A,C,zero,sign,parity,halfCarry
@EditorViewportMarkerForRow:
        CP      0
        JR      Z,EditorViewportMarkerBreakpoint
        CP      1
        JR      Z,EditorViewportMarkerCurrent
        CP      3
        JR      Z,EditorViewportMarkerSelected
        LD      C,TECM8_DISPLAY_MARKER_NONE
        XOR     A
        RET

EditorViewportMarkerBreakpoint:
        LD      C,TECM8_DISPLAY_MARKER_BREAKPOINT
        XOR     A
        RET

EditorViewportMarkerCurrent:
        LD      C,TECM8_DISPLAY_MARKER_CURRENT
        XOR     A
        RET

EditorViewportMarkerSelected:
        LD      C,TECM8_DISPLAY_MARKER_SELECTED
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
        LD      HL,EditorRowText9
        LD      A,TECM8_DISPLAY_STATUS_ROW
        LD      C,TECM8_DISPLAY_MARKER_NONE
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
        CP      TECM8_EDITOR_MAX_RECORD_TEXT + 1
        JR      NC,EditorViewportRecordLengthError
        LD      B,A
        INC     HL
        LD      (EditorRecordPtr),HL
        LD      DE,(EditorTextPtr)
        LD      A,B
        OR      A
        JR      Z,EditorViewportTerminateRow

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

EditorViewportRecordLengthError:
        LD      A,TECM8_EDITOR_ERR_RECORD_LENGTH
        SCF
        RET

EditorScreenDescriptor:
        .db     TECM8_DISPLAY_MARKER_BREAKPOINT
        .dw     EditorRowText0
        .db     TECM8_DISPLAY_MARKER_CURRENT
        .dw     EditorRowText1
        .db     TECM8_DISPLAY_MARKER_NONE
        .dw     EditorRowText2
        .db     TECM8_DISPLAY_MARKER_SELECTED
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
EditorRowIndex:
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
