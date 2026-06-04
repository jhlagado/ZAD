; TECM8 editor viewport proof module.
;
; Converts fixed 32-byte Pascal-string source records into the structured
; display descriptor consumed by TECM8_DISPLAY_RENDER_SCREEN.

TECM8_EDITOR_RECORD_BYTES          .equ    32
TECM8_EDITOR_VISIBLE_ROWS          .equ    8
TECM8_EDITOR_MAX_RECORD_TEXT       .equ    31
TECM8_EDITOR_ROW_TEXT_BYTES        .equ    32
TECM8_EDITOR_ERR_RECORD_LENGTH     .equ    0x01

; TECM8_EDITOR_VIEWPORT_RENDER -
; Render the first eight 32-byte source records in the sector/window at HL.
; Input: HL = source record window
;!      in        HL
;!      out       A,carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@TECM8_EDITOR_VIEWPORT_RENDER:
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
        CALL    TECM8_DISPLAY_RENDER_SCREEN
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
        .dw     EditorTopChrome
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
        .dw     EditorBottomChrome

EditorTopChrome:
        .db     "TECM8 EDIT MAIN.ASM",0
EditorBottomChrome:
        .db     "Ln 2 Col 1",0

EditorRecordPtr:
        .dw     0
EditorTextPtr:
        .dw     0
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
