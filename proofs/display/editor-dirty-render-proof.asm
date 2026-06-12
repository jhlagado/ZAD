; Editor dirty-render proof.
;
; Opens the default source through the shell, then verifies ordinary cursor
; movement and a simple printable insertion avoid the full viewport render path.

        .org    0x4000

PROOF_PASS       .equ     0x42
PROOF_FAIL       .equ     0xE0

;!      out       carry,zero
;!      clobbers  A,BC,DE,HL
@Start:
        CALL    DisplayInit
        JP      C,ProofFailed

        LD      A,1
        LD      (CaseMarker),A
        LD      HL,CmdEdit
        LD      DE,NoKeys
        CALL    ShellRunEditorSession
        JP      C,ProofFailed

        CALL    ResetRenderCounters
        LD      A,3
        LD      (CaseMarker),A
        LD      HL,InsertKeys
        CALL    EditorRunKeys
        JP      C,ProofFailed
        CALL    GlcdTileDrainPending
        JP      C,ProofFailed
        LD      A,(DisplayRenderScreenCount)
        LD      (InsertScreenCount),A
        LD      A,(EditorRenderPageBufferCount)
        LD      (InsertPageCount),A
        LD      A,(EditorViewportRenderRecordRowCount)
        LD      (InsertRowCount),A
        LD      A,(EditorViewportRenderRowMarkerCount)
        LD      (InsertMarkerCount),A
        LD      A,(GlcdTileFlushFullCount)
        LD      (InsertFullFlushCount),A
        LD      A,(GlcdTileFlushRowCount)
        LD      (InsertRowFlushCount),A
        LD      A,(GlcdTileFlushCellCount)
        LD      (InsertCellFlushCount),A
        LD      A,(GlcdTileFlushCellByteCount)
        LD      (InsertCellFlushByteCount),A

        CALL    ResetRenderCounters
        LD      A,6
        LD      (CaseMarker),A
        LD      HL,DeleteKeys
        CALL    EditorRunKeys
        JP      C,ProofFailed
        CALL    GlcdTileDrainPending
        JP      C,ProofFailed
        LD      A,(DisplayRenderScreenCount)
        LD      (DeleteScreenCount),A
        LD      A,(EditorRenderPageBufferCount)
        LD      (DeletePageCount),A
        LD      A,(EditorViewportRenderRecordRowCount)
        LD      (DeleteRowCount),A
        LD      A,(EditorViewportRenderRowMarkerCount)
        LD      (DeleteMarkerCount),A
        LD      A,(GlcdTileFlushFullCount)
        LD      (DeleteFullFlushCount),A
        LD      A,(GlcdTileFlushRowCount)
        LD      (DeleteRowFlushCount),A
        LD      A,(GlcdTileFlushCellCount)
        LD      (DeleteCellFlushCount),A
        LD      A,(GlcdTileFlushCellByteCount)
        LD      (DeleteCellFlushByteCount),A

        CALL    ResetRenderCounters
        LD      A,7
        LD      (CaseMarker),A
        LD      HL,BackspaceKeys
        CALL    EditorRunKeys
        JP      C,ProofFailed
        CALL    GlcdTileDrainPending
        JP      C,ProofFailed
        LD      A,(DisplayRenderScreenCount)
        LD      (BackspaceScreenCount),A
        LD      A,(EditorRenderPageBufferCount)
        LD      (BackspacePageCount),A
        LD      A,(EditorViewportRenderRecordRowCount)
        LD      (BackspaceRowCount),A
        LD      A,(EditorViewportRenderRowMarkerCount)
        LD      (BackspaceMarkerCount),A
        LD      A,(GlcdTileFlushFullCount)
        LD      (BackspaceFullFlushCount),A
        LD      A,(GlcdTileFlushRowCount)
        LD      (BackspaceRowFlushCount),A
        LD      A,(GlcdTileFlushCellCount)
        LD      (BackspaceCellFlushCount),A
        LD      A,(GlcdTileFlushCellByteCount)
        LD      (BackspaceCellFlushByteCount),A

        CALL    ResetRenderCounters
        LD      A,2
        LD      (CaseMarker),A
        LD      HL,MovementKeys
        CALL    EditorRunKeys
        JP      C,ProofFailed
        CALL    GlcdTileDrainPending
        JP      C,ProofFailed
        LD      A,(DisplayRenderScreenCount)
        LD      (MoveScreenCount),A
        LD      A,(EditorRenderPageBufferCount)
        LD      (MovePageCount),A
        LD      A,(EditorViewportRenderRecordRowCount)
        LD      (MoveRowCount),A
        LD      A,(EditorViewportRenderRowMarkerCount)
        LD      (MoveMarkerCount),A
        LD      A,(GlcdTileFlushFullCount)
        LD      (MoveFullFlushCount),A
        LD      A,(GlcdTileFlushRowCount)
        LD      (MoveRowFlushCount),A
        LD      A,(GlcdTileFlushCellCount)
        LD      (MoveCellFlushCount),A
        LD      A,(GlcdTileFlushCellByteCount)
        LD      (MoveCellFlushByteCount),A

        CALL    ResetRenderCounters
        LD      A,4
        LD      (CaseMarker),A
        LD      A,1
        LD      (EditorCursorBlinkCounter),A
        CALL    EditorCursorBlinkStep
        JP      C,ProofFailed
        CALL    GlcdTileDrainPending
        JP      C,ProofFailed
        LD      A,(DisplayRenderScreenCount)
        LD      (BlinkHideScreenCount),A
        LD      A,(EditorRenderPageBufferCount)
        LD      (BlinkHidePageCount),A
        LD      A,(GlcdTileFlushRowCount)
        LD      (BlinkHideRowFlushCount),A
        LD      A,(GlcdTileFlushCellCount)
        LD      (BlinkHideCellFlushCount),A
        LD      A,(GlcdTileFlushCellByteCount)
        LD      (BlinkHideCellFlushByteCount),A
        LD      A,(EditorCursorRendered)
        LD      (BlinkHideRendered),A
        LD      A,(EditorCursorBlinkToggleCount)
        LD      (BlinkHideToggleCount),A

        CALL    ResetRenderCounters
        LD      A,5
        LD      (CaseMarker),A
        LD      A,1
        LD      (EditorCursorBlinkCounter),A
        CALL    EditorCursorBlinkStep
        JP      C,ProofFailed
        CALL    GlcdTileDrainPending
        JP      C,ProofFailed
        LD      A,(DisplayRenderScreenCount)
        LD      (BlinkShowScreenCount),A
        LD      A,(EditorRenderPageBufferCount)
        LD      (BlinkShowPageCount),A
        LD      A,(GlcdTileFlushRowCount)
        LD      (BlinkShowRowFlushCount),A
        LD      A,(GlcdTileFlushCellCount)
        LD      (BlinkShowCellFlushCount),A
        LD      A,(GlcdTileFlushCellByteCount)
        LD      (BlinkShowCellFlushByteCount),A
        LD      A,(EditorCursorRendered)
        LD      (BlinkShowRendered),A
        LD      A,(EditorCursorBlinkToggleCount)
        LD      (BlinkShowToggleCount),A

        LD      A,PROOF_PASS
        LD      (ResultMarker),A

ProofDone:
        JP      ProofDone

ProofFailed:
        LD      (ErrorMarker),A
        LD      A,(CaseMarker)
        OR      PROOF_FAIL
        LD      (ResultMarker),A

ProofFailedDone:
        JP      ProofDone

;!      out       A,carry,zero
;!      clobbers  A
@ResetRenderCounters:
        XOR     A
        LD      (DisplayRenderScreenCount),A
        LD      (EditorRenderPageBufferCount),A
        LD      (EditorViewportRenderRecordRowCount),A
        LD      (EditorViewportRenderRowMarkerCount),A
        LD      (GlcdTileFlushFullCount),A
        LD      (GlcdTileFlushRowCount),A
        LD      (GlcdTileFlushCellCount),A
        LD      (GlcdTileFlushCellByteCount),A
        RET

; Stub LoadProjectConfig for shell-to-editor proof.
;!      in        B,DE
;!      out       DE,HL,A,C,carry,zero
;!      clobbers  B
@LoadProjectConfig:
        LD      HL,ExpectedMain
        LD      C,B

LoadProjectStubLoop:
        LD      A,(HL)
        LD      (DE),A
        INC     HL
        INC     DE
        OR      A
        JR      Z,LoadProjectStubOk
        DEC     C
        JR      NZ,LoadProjectStubLoop
        LD      A,SHELL_ERR_LONG
        SCF
        RET

LoadProjectStubOk:
        XOR     A
        RET

        .include "../../src/glcd-tile.asm"
        .include "../../src/display-model.asm"
        .include "../../src/editor-viewport.asm"
        .include "../../src/editor-storage-loader.asm"
        .include "../../src/editor-navigation.asm"
        .include "../../src/editor-interaction.asm"
        .include "../../src/shell-commands.asm"
        .include "../../src/shell-editor-launch.asm"
        .include "../../src/tecm8-bios.asm"

CmdEdit:
        .db     "edit",0

NoKeys:
        .db     0

MovementKeys:
        .db     TECM8_EDITOR_KEY_ARROW_RIGHT,TECM8_EDITOR_KEY_ARROW_RIGHT
        .db     TECM8_EDITOR_KEY_ARROW_DOWN,TECM8_EDITOR_KEY_ARROW_LEFT
        .db     TECM8_EDITOR_KEY_ARROW_UP,0

InsertKeys:
        .db     "Z",0

DeleteKeys:
        .db     TECM8_EDITOR_KEY_DELETE,0

BackspaceKeys:
        .db     TECM8_EDITOR_KEY_BACKSPACE,0

ExpectedMain:
        .db     "/src/main.asm",0

ResultMarker:
        .db     0
CaseMarker:
        .db     0
ErrorMarker:
        .db     0
MoveScreenCount:
        .db     0
MovePageCount:
        .db     0
MoveRowCount:
        .db     0
MoveMarkerCount:
        .db     0
MoveFullFlushCount:
        .db     0
MoveRowFlushCount:
        .db     0
MoveCellFlushCount:
        .db     0
MoveCellFlushByteCount:
        .db     0
InsertScreenCount:
        .db     0
InsertPageCount:
        .db     0
InsertRowCount:
        .db     0
InsertMarkerCount:
        .db     0
InsertFullFlushCount:
        .db     0
InsertRowFlushCount:
        .db     0
InsertCellFlushCount:
        .db     0
InsertCellFlushByteCount:
        .db     0
DeleteScreenCount:
        .db     0
DeletePageCount:
        .db     0
DeleteRowCount:
        .db     0
DeleteMarkerCount:
        .db     0
DeleteFullFlushCount:
        .db     0
DeleteRowFlushCount:
        .db     0
DeleteCellFlushCount:
        .db     0
DeleteCellFlushByteCount:
        .db     0
BackspaceScreenCount:
        .db     0
BackspacePageCount:
        .db     0
BackspaceRowCount:
        .db     0
BackspaceMarkerCount:
        .db     0
BackspaceFullFlushCount:
        .db     0
BackspaceRowFlushCount:
        .db     0
BackspaceCellFlushCount:
        .db     0
BackspaceCellFlushByteCount:
        .db     0
BlinkHideScreenCount:
        .db     0
BlinkHidePageCount:
        .db     0
BlinkHideRowFlushCount:
        .db     0
BlinkHideCellFlushCount:
        .db     0
BlinkHideCellFlushByteCount:
        .db     0
BlinkHideRendered:
        .db     0
BlinkHideToggleCount:
        .db     0
BlinkShowScreenCount:
        .db     0
BlinkShowPageCount:
        .db     0
BlinkShowRowFlushCount:
        .db     0
BlinkShowCellFlushCount:
        .db     0
BlinkShowCellFlushByteCount:
        .db     0
BlinkShowRendered:
        .db     0
BlinkShowToggleCount:
        .db     0
