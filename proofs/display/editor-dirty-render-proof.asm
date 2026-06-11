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
        LD      A,2
        LD      (CaseMarker),A
        LD      HL,MovementKeys
        CALL    EditorRunKeys
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

        CALL    ResetRenderCounters
        LD      A,3
        LD      (CaseMarker),A
        LD      HL,InsertKeys
        CALL    EditorRunKeys
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
