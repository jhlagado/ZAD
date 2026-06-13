; Editor error handling proof.
;
; Proves compact editor/storage error codes map to visible status-row strings
; and remain available as diagnostic state.

        .org    0x4000

        .include "../../src/tecm8-equates.asm"

PROOF_PASS       .equ     0x42
PROOF_FAIL       .equ     0xE0

;! out carry,zero
;! clobbers A,BC,DE,HL
@Start:
        CALL    DisplayInit
        JR      C,ProofFailed

        LD      A,EDITOR_LOAD_ERR_OPEN
        CALL    EditorNavShowError
        JR      C,ProofFailed
        LD      HL,(EditorLastErrorTextPtr)
        LD      (OpenErrPtr),HL

        LD      A,EDITOR_LOAD_ERR_READ
        CALL    EditorNavShowError
        JR      C,ProofFailed
        LD      HL,(EditorLastErrorTextPtr)
        LD      (ReadErrPtr),HL

        LD      A,EDITOR_LOAD_ERR_WRITE
        CALL    EditorNavShowError
        JR      C,ProofFailed
        LD      HL,(EditorLastErrorTextPtr)
        LD      (WriteErrPtr),HL

        LD      A,EDITOR_LOAD_ERR_CREATE
        CALL    EditorNavShowError
        JR      C,ProofFailed
        LD      HL,(EditorLastErrorTextPtr)
        LD      (FullErrPtr),HL

        LD      A,EDITOR_LOAD_ERR_SIZE
        CALL    EditorNavShowError
        JR      C,ProofFailed
        LD      HL,(EditorLastErrorTextPtr)
        LD      (SizeErrPtr),HL

        LD      A,TECM8_EDITOR_NAV_ERR_BACKUP
        CALL    EditorNavShowError
        JR      C,ProofFailed
        LD      HL,(EditorLastErrorTextPtr)
        LD      (BackupErrPtr),HL

        LD      A,128
        LD      HL,EditorSourcePage
        CALL    EditorLoadMainPage
        JR      NC,ProofFailed
        CALL    EditorNavShowError
        JR      C,ProofFailed
        LD      HL,(EditorLastErrorTextPtr)
        LD      (PageErrPtr),HL
        LD      A,(EditorLastErrorCode)
        LD      (LastErrCodeAfterPage),A

        LD      A,PROOF_PASS
        LD      (ResultMarker),A

ProofDone:
        JP      ProofDone

ProofFailed:
        OR      PROOF_FAIL
        LD      (ResultMarker),A

ProofFailedDone:
        JP      ProofDone

        .include "../../src/glcd-tile.asm"
        .include "../../src/display-model.asm"
        .include "../../src/editor-viewport.asm"
        .include "../../src/tecm8-string.asm"
        .include "../../src/tecm8-storage.asm"
        .include "../../src/editor-storage-loader.asm"
        .include "../../src/editor-navigation.asm"
        .include "../../src/tecm8-bios.asm"

ResultMarker:
        .db     0

OpenErrPtr:
        .dw     0

ReadErrPtr:
        .dw     0

WriteErrPtr:
        .dw     0

FullErrPtr:
        .dw     0

SizeErrPtr:
        .dw     0

BackupErrPtr:
        .dw     0

PageErrPtr:
        .dw     0

LastErrCodeAfterPage:
        .db     0

EditorSourcePage:
        .ds     512
