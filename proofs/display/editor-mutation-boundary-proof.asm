; Editor mutation boundary proof.
;
; Exercises fixed-record insert, backspace, delete, and insert-mode reserved
; command-letter input directly against the loaded editor page buffer.

        .org    0x4000

        .include "../../src/tecm8-equates.asm"

PROOF_PASS       .equ     0x42
PROOF_FAIL       .equ     0xE0

;! out carry,zero
;! clobbers A,BC,DE,HL
@Start:
        CALL    DisplayInit
        JP      C,ProofFailed
        CALL    BoundaryInitRecords

        LD      A,1
        LD      (CaseMarker),A
        XOR     A
        LD      (EditorCursorRow),A
        LD      (EditorCursorCol),A
        CALL    EditorBackspaceChar
        JP      C,ProofFailed
        LD      HL,BoundaryCursorCase1
        CALL    BoundarySaveCursor

        LD      A,2
        LD      (CaseMarker),A
        XOR     A
        LD      (EditorCursorRow),A
        LD      (EditorCursorCol),A
        CALL    EditorDeleteChar
        JP      C,ProofFailed
        LD      HL,BoundaryCursorCase2
        CALL    BoundarySaveCursor

        LD      A,3
        LD      (CaseMarker),A
        XOR     A
        LD      (EditorCursorRow),A
        LD      (EditorCursorCol),A
        LD      A,"Z"
        CALL    EditorInsertChar
        JP      C,ProofFailed
        LD      HL,BoundaryCursorCase3
        CALL    BoundarySaveCursor

        LD      A,4
        LD      (CaseMarker),A
        LD      A,1
        LD      (EditorCursorRow),A
        XOR     A
        LD      (EditorCursorCol),A
        LD      A,"Q"
        CALL    EditorInsertChar
        JP      C,ProofFailed
        LD      HL,BoundaryCursorCase4
        CALL    BoundarySaveCursor

        LD      A,5
        LD      (CaseMarker),A
        LD      A,2
        LD      (EditorCursorRow),A
        XOR     A
        LD      (EditorCursorCol),A
        CALL    EditorBackspaceChar
        JP      C,ProofFailed
        LD      HL,BoundaryCursorCase5
        CALL    BoundarySaveCursor

        LD      A,6
        LD      (CaseMarker),A
        LD      A,2
        LD      (EditorCursorRow),A
        LD      A,5
        LD      (EditorCursorCol),A
        CALL    EditorDeleteChar
        JP      C,ProofFailed
        LD      HL,BoundaryCursorCase6
        CALL    BoundarySaveCursor

        LD      A,7
        LD      (CaseMarker),A
        LD      A,3
        LD      (EditorCursorRow),A
        LD      A,2
        LD      (EditorCursorCol),A
        CALL    EditorDeleteChar
        JP      C,ProofFailed
        LD      HL,BoundaryCursorCase7
        CALL    BoundarySaveCursor

        LD      A,8
        LD      (CaseMarker),A
        LD      A,4
        LD      (EditorCursorRow),A
        LD      A,3
        LD      (EditorCursorCol),A
        LD      A,"!"
        CALL    EditorInsertChar
        JP      C,ProofFailed
        LD      HL,BoundaryCursorCase8
        CALL    BoundarySaveCursor

        LD      A,9
        LD      (CaseMarker),A
        LD      A,5
        LD      (EditorCursorRow),A
        XOR     A
        LD      (EditorCursorCol),A
        LD      HL,BoundaryReservedKeys
        CALL    EditorRunKeys
        JP      C,ProofFailed
        LD      HL,BoundaryCursorCase9
        CALL    BoundarySaveCursor

        LD      A,10
        LD      (CaseMarker),A
        CALL    EditorNavClearNextPageBuffer
        JP      C,ProofFailed
        LD      A,1
        LD      (EditorNavNextPageValid),A
        LD      HL,BoundaryRecord8
        LD      DE,EditorNavPageBuffer + (14 * 32)
        CALL    BoundaryCopyRecord
        LD      HL,BoundaryRecord9
        LD      DE,EditorNavPageBuffer + (15 * 32)
        CALL    BoundaryCopyRecord
        LD      A,14
        LD      (EditorCursorRow),A
        LD      A,2
        LD      (EditorCursorCol),A
        CALL    EditorSplitLine
        JP      C,ProofFailed
        OR      A
        JP      Z,ProofFailed
        CALL    EditorMarkDirty
        JP      C,ProofFailed
        LD      HL,BoundaryCursorCase10
        CALL    BoundarySaveCursor

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

;! out A,carry,zero
;! clobbers BC,DE,HL
@BoundaryInitRecords:
        LD      HL,BoundaryRecord0
        LD      DE,EditorNavPageBuffer
        CALL    BoundaryCopyRecord
        LD      HL,BoundaryRecord1
        LD      DE,EditorNavPageBuffer + 32
        CALL    BoundaryCopyRecord
        LD      HL,BoundaryRecord2
        LD      DE,EditorNavPageBuffer + 64
        CALL    BoundaryCopyRecord
        LD      HL,BoundaryRecord3
        LD      DE,EditorNavPageBuffer + 96
        CALL    BoundaryCopyRecord
        LD      HL,BoundaryRecord4
        LD      DE,EditorNavPageBuffer + 128
        CALL    BoundaryCopyRecord
        LD      HL,BoundaryRecord5
        LD      DE,EditorNavPageBuffer + 160
        CALL    BoundaryCopyRecord
        LD      HL,BoundaryRecord6
        LD      DE,EditorNavPageBuffer + 192
        CALL    BoundaryCopyRecord
        LD      HL,BoundaryRecord7
        LD      DE,EditorNavPageBuffer + 224
        CALL    BoundaryCopyRecord
        XOR     A
        RET

;! in DE,HL
;! out A,BC,DE,HL,carry,zero
@BoundaryCopyRecord:
        LD      BC,32
        LDIR
        XOR     A
        RET

;! in HL
;! out A,HL,carry,zero
;! clobbers A
@BoundarySaveCursor:
        LD      A,(EditorCursorRow)
        LD      (HL),A
        INC     HL
        LD      A,(EditorCursorCol)
        LD      (HL),A
        XOR     A
        RET

; Stub LoadProjectConfig for included shell command code.
;! in B,DE
;! out DE,HL,A,C,carry,zero
;! clobbers B
@LoadProjectConfig:
        LD      HL,BoundaryExpectedMain
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
        .include "../../src/tecm8-string.asm"
        .include "../../src/tecm8-storage.asm"
        .include "../../src/editor-storage-loader.asm"
        .include "../../src/editor-navigation.asm"
        .include "../../src/tecm8-record.asm"
        .include "../../src/editor-interaction.asm"
        .include "../../src/editor-record.asm"
        .include "../../src/editor-line-edit.asm"
        .include "../../src/editor-keymap.asm"
        .include "../../src/editor-cursor.asm"
        .include "../../src/editor-prompt.asm"
        .include "../../src/editor-render.asm"
        .include "../../src/shell-commands.asm"
        .include "../../src/shell-editor-launch.asm"
        .include "../../src/tecm8-bios.asm"

BoundaryReservedKeys:
        .db     9,"dl",0

BoundaryExpectedMain:
        .db     "/src/main.asm",0

BoundaryRecord0:
        .db     0
        .ds     31
BoundaryRecord1:
        .db     0x7F,"ABCDEFGHIJKLMNOPQRSTUVWXYZ12345"
BoundaryRecord2:
        .db     0xE5,"ABCDE"
        .ds     26
BoundaryRecord3:
        .db     0xA5,"ABCDE"
        .ds     26
BoundaryRecord4:
        .db     0x63,"XYZ"
        .ds     28
BoundaryRecord5:
        .db     0x80
        .ds     31
BoundaryRecord6:
        .db     0
        .ds     31
BoundaryRecord7:
        .db     0
        .ds     31
BoundaryRecord8:
        .db     4,"LEFT"
        .ds     27
BoundaryRecord9:
        .db     4,"PUSH"
        .ds     27

BoundaryCursorCase1:
        .ds     2
BoundaryCursorCase2:
        .ds     2
BoundaryCursorCase3:
        .ds     2
BoundaryCursorCase4:
        .ds     2
BoundaryCursorCase5:
        .ds     2
BoundaryCursorCase6:
        .ds     2
BoundaryCursorCase7:
        .ds     2
BoundaryCursorCase8:
        .ds     2
BoundaryCursorCase9:
        .ds     2
BoundaryCursorCase10:
        .ds     2

ResultMarker:
        .db     0

CaseMarker:
        .db     0

ErrorMarker:
        .db     0
