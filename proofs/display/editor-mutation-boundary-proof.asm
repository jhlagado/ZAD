; Editor mutation boundary proof.
;
; Exercises fixed-record insert, backspace, delete, and insert-mode reserved
; command-letter input directly against the loaded editor page buffer.

        .org    0x4000

ProofPass       .equ     0x42
ProofFail       .equ     0xE0

;!      out       carry,zero
;!      clobbers  A,BC,DE,HL
@Start:
        CALL    TECM8_DISPLAY_INIT
        JP      C,ProofFailed
        CALL    BoundaryInitRecords

        LD      A,1
        LD      (CaseMarker),A
        XOR     A
        LD      (EditorCursorRow),A
        LD      (EditorCursorCol),A
        CALL    TECM8_EDITOR_BACKSPACE_CHAR
        JP      C,ProofFailed
        LD      HL,BoundaryCursorCase1
        CALL    BoundarySaveCursor

        LD      A,2
        LD      (CaseMarker),A
        XOR     A
        LD      (EditorCursorRow),A
        LD      (EditorCursorCol),A
        CALL    TECM8_EDITOR_DELETE_CHAR
        JP      C,ProofFailed
        LD      HL,BoundaryCursorCase2
        CALL    BoundarySaveCursor

        LD      A,3
        LD      (CaseMarker),A
        XOR     A
        LD      (EditorCursorRow),A
        LD      (EditorCursorCol),A
        LD      A,"Z"
        CALL    TECM8_EDITOR_INSERT_CHAR
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
        CALL    TECM8_EDITOR_INSERT_CHAR
        JP      C,ProofFailed
        LD      HL,BoundaryCursorCase4
        CALL    BoundarySaveCursor

        LD      A,5
        LD      (CaseMarker),A
        LD      A,2
        LD      (EditorCursorRow),A
        XOR     A
        LD      (EditorCursorCol),A
        CALL    TECM8_EDITOR_BACKSPACE_CHAR
        JP      C,ProofFailed
        LD      HL,BoundaryCursorCase5
        CALL    BoundarySaveCursor

        LD      A,6
        LD      (CaseMarker),A
        LD      A,2
        LD      (EditorCursorRow),A
        LD      A,5
        LD      (EditorCursorCol),A
        CALL    TECM8_EDITOR_DELETE_CHAR
        JP      C,ProofFailed
        LD      HL,BoundaryCursorCase6
        CALL    BoundarySaveCursor

        LD      A,7
        LD      (CaseMarker),A
        LD      A,3
        LD      (EditorCursorRow),A
        LD      A,2
        LD      (EditorCursorCol),A
        CALL    TECM8_EDITOR_DELETE_CHAR
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
        CALL    TECM8_EDITOR_INSERT_CHAR
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
        CALL    TECM8_EDITOR_RUN_KEYS
        JP      C,ProofFailed
        LD      HL,BoundaryCursorCase9
        CALL    BoundarySaveCursor

        LD      A,ProofPass
        LD      (ResultMarker),A

ProofDone:
        JP      ProofDone

ProofFailed:
        LD      (ErrorMarker),A
        LD      A,(CaseMarker)
        OR      ProofFail
        LD      (ResultMarker),A

ProofFailedDone:
        JP      ProofDone

;!      out       A,carry,zero
;!      clobbers  BC,DE,HL
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

;!      in        DE,HL
;!      out       A,BC,DE,HL,carry,zero
@BoundaryCopyRecord:
        LD      BC,32
        LDIR
        XOR     A
        RET

;!      in        HL
;!      out       A,HL,carry,zero
;!      clobbers  A
@BoundarySaveCursor:
        LD      A,(EditorCursorRow)
        LD      (HL),A
        INC     HL
        LD      A,(EditorCursorCol)
        LD      (HL),A
        XOR     A
        RET

; Stub LoadProjectConfig for included shell command code.
;!      in        B,DE
;!      out       DE,HL,A,C,carry,zero
;!      clobbers  B
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

        .include "../../src/display-model.asm"
        .include "../../src/editor-viewport.asm"
        .include "../../src/editor-storage-loader.asm"
        .include "../../src/editor-navigation.asm"
        .include "../../src/editor-interaction.asm"
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
        .db     31,"ABCDEFGHIJKLMNOPQRSTUVWXYZ12345"
BoundaryRecord2:
        .db     5,"ABCDE"
        .ds     26
BoundaryRecord3:
        .db     5,"ABCDE"
        .ds     26
BoundaryRecord4:
        .db     3,"XYZ"
        .ds     28
BoundaryRecord5:
        .db     0
        .ds     31
BoundaryRecord6:
        .db     0
        .ds     31
BoundaryRecord7:
        .db     0
        .ds     31

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

ResultMarker:
        .db     0

CaseMarker:
        .db     0

ErrorMarker:
        .db     0
