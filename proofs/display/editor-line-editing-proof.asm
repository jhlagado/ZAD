; Editor line-editing proof.
;
; Exercises split-line/newline and join-line/backspace-at-start behavior inside
; the current 512-byte editor page buffer.

        .org    0x4000

PROOF_PASS       .equ     0x42
PROOF_FAIL       .equ     0xE0

;!      out       carry,zero
;!      clobbers  A,BC,DE,HL
@Start:
        CALL    DisplayInit
        JP      C,ProofFailed
        CALL    LineEditInitRecords

        LD      A,1
        LD      (CaseMarker),A
        XOR     A
        LD      (EditorCursorRow),A
        LD      A,2
        LD      (EditorCursorCol),A
        CALL    EditorSplitLine
        JP      C,ProofFailed
        LD      HL,LineEditCursorCase1
        CALL    LineEditSaveCursor

        LD      A,2
        LD      (CaseMarker),A
        LD      A,1
        LD      (EditorCursorRow),A
        XOR     A
        LD      (EditorCursorCol),A
        CALL    EditorBackspaceChar
        JP      C,ProofFailed
        LD      HL,LineEditCursorCase2
        CALL    LineEditSaveCursor

        LD      A,3
        LD      (CaseMarker),A
        LD      A,2
        LD      (EditorCursorRow),A
        LD      A,3
        LD      (EditorCursorCol),A
        CALL    EditorSplitLine
        JP      C,ProofFailed
        LD      HL,LineEditCursorCase3
        CALL    LineEditSaveCursor

        LD      A,4
        LD      (CaseMarker),A
        LD      A,4
        LD      (EditorCursorRow),A
        XOR     A
        LD      (EditorCursorCol),A
        CALL    EditorBackspaceChar
        JP      C,ProofFailed
        LD      HL,LineEditCursorCase4
        CALL    LineEditSaveCursor

        LD      A,5
        LD      (CaseMarker),A
        LD      A,7
        LD      (EditorCursorRow),A
        XOR     A
        LD      (EditorCursorCol),A
        CALL    EditorBackspaceChar
        JP      C,ProofFailed
        LD      HL,LineEditCursorCase5
        CALL    LineEditSaveCursor

        LD      A,7
        LD      (CaseMarker),A
        LD      A,1
        LD      (EditorCursorRow),A
        LD      A,2
        LD      (EditorCursorCol),A
        LD      HL,LineEditNewlineKey
        CALL    EditorRunKeys
        JP      C,ProofFailed
        LD      HL,LineEditCursorCase7
        CALL    LineEditSaveCursor

        LD      A,8
        LD      (CaseMarker),A
        LD      HL,LineEditRecordLast
        LD      DE,EditorNavPageBuffer + 480
        CALL    LineEditCopyRecord
        LD      A,1
        LD      (EditorCursorRow),A
        LD      (EditorCursorCol),A
        CALL    EditorSplitLine
        JP      C,ProofFailed
        LD      HL,LineEditCursorCase8
        CALL    LineEditSaveCursor

        LD      A,10
        LD      (CaseMarker),A
        LD      HL,LineEditRecordEmpty
        LD      DE,EditorNavPageBuffer + 480
        CALL    LineEditCopyRecord
        LD      A,15
        LD      (EditorCursorRow),A
        XOR     A
        LD      (EditorCursorCol),A
        CALL    EditorSplitLine
        JP      C,ProofFailed
        LD      (LineEditResultCase10),A
        LD      HL,LineEditCursorCase10
        CALL    LineEditSaveCursor

        LD      A,6
        LD      (CaseMarker),A
        LD      HL,LineEditRecordLast
        LD      DE,EditorNavPageBuffer + 480
        CALL    LineEditCopyRecord
        LD      A,15
        LD      (EditorCursorRow),A
        LD      A,2
        LD      (EditorCursorCol),A
        CALL    EditorSplitLine
        JP      C,ProofFailed
        LD      (LineEditResultCase6),A
        LD      HL,LineEditCursorCase6
        CALL    LineEditSaveCursor

        LD      A,9
        LD      (CaseMarker),A
        XOR     A
        LD      (EditorCursorRow),A
        LD      (EditorCursorCol),A
        CALL    EditorBackspaceChar
        JP      C,ProofFailed
        LD      (LineEditResultCase9),A
        LD      HL,LineEditCursorCase9
        CALL    LineEditSaveCursor

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
;!      clobbers  BC,DE,HL
@LineEditInitRecords:
        LD      HL,LineEditRecord0
        LD      DE,EditorNavPageBuffer
        CALL    LineEditCopyRecord
        LD      HL,LineEditRecord1
        LD      DE,EditorNavPageBuffer + 32
        CALL    LineEditCopyRecord
        LD      HL,LineEditRecord2
        LD      DE,EditorNavPageBuffer + 64
        CALL    LineEditCopyRecord
        LD      HL,LineEditRecord3
        LD      DE,EditorNavPageBuffer + 96
        CALL    LineEditCopyRecord
        LD      HL,LineEditRecord4
        LD      DE,EditorNavPageBuffer + 128
        CALL    LineEditCopyRecord
        LD      HL,LineEditRecord5
        LD      DE,EditorNavPageBuffer + 160
        CALL    LineEditCopyRecord
        LD      HL,LineEditRecord6
        LD      DE,EditorNavPageBuffer + 192
        CALL    LineEditCopyRecord
        LD      HL,LineEditRecord7
        LD      DE,EditorNavPageBuffer + 224
        CALL    LineEditCopyRecord
        LD      HL,LineEditRecord8
        LD      DE,EditorNavPageBuffer + 256
        CALL    LineEditCopyRecord
        LD      HL,LineEditRecordEmpty
        LD      DE,EditorNavPageBuffer + 288
        CALL    LineEditCopyRecord
        LD      HL,LineEditRecordEmpty
        LD      DE,EditorNavPageBuffer + 320
        CALL    LineEditCopyRecord
        LD      HL,LineEditRecordEmpty
        LD      DE,EditorNavPageBuffer + 352
        CALL    LineEditCopyRecord
        LD      HL,LineEditRecordEmpty
        LD      DE,EditorNavPageBuffer + 384
        CALL    LineEditCopyRecord
        LD      HL,LineEditRecordEmpty
        LD      DE,EditorNavPageBuffer + 416
        CALL    LineEditCopyRecord
        LD      HL,LineEditRecordEmpty
        LD      DE,EditorNavPageBuffer + 448
        CALL    LineEditCopyRecord
        LD      HL,LineEditRecordEmpty
        LD      DE,EditorNavPageBuffer + 480
        CALL    LineEditCopyRecord
        XOR     A
        RET

;!      in        DE,HL
;!      out       A,BC,DE,HL,carry,zero
@LineEditCopyRecord:
        LD      BC,32
        LDIR
        XOR     A
        RET

;!      in        HL
;!      out       A,HL,carry,zero
;!      clobbers  A
@LineEditSaveCursor:
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
        LD      HL,LineEditExpectedMain
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

LineEditNewlineKey:
        .db     13,0

LineEditExpectedMain:
        .db     "/src/main.asm",0

LineEditRecord0:
        .db     5,"HELLO"
        .ds     26
LineEditRecord1:
        .db     4,"NEXT"
        .ds     27
LineEditRecord2:
        .db     3,"END"
        .ds     28
LineEditRecord3:
        .db     4,"TAIL"
        .ds     27
LineEditRecord4:
        .db     0
        .ds     31
LineEditRecord5:
        .db     0
        .ds     31
LineEditRecord6:
        .db     31,"ABCDEFGHIJKLMNOPQRSTUVWXYZ12345"
LineEditRecord7:
        .db     1,"X"
        .ds     30
LineEditRecord8:
        .db     5,"AFTER"
        .ds     26
LineEditRecordEmpty:
        .db     0
        .ds     31
LineEditRecordLast:
        .db     4,"LAST"
        .ds     27

LineEditCursorCase1:
        .ds     2
LineEditCursorCase2:
        .ds     2
LineEditCursorCase3:
        .ds     2
LineEditCursorCase4:
        .ds     2
LineEditCursorCase5:
        .ds     2
LineEditCursorCase6:
        .ds     2
LineEditCursorCase7:
        .ds     2
LineEditCursorCase8:
        .ds     2
LineEditCursorCase9:
        .ds     2
LineEditCursorCase10:
        .ds     2

LineEditResultCase6:
        .db     0xFF
LineEditResultCase9:
        .db     0xFF
LineEditResultCase10:
        .db     0xFF

ResultMarker:
        .db     0

CaseMarker:
        .db     0

ErrorMarker:
        .db     0
