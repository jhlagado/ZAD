; Editor allocation-chain growth proof.
;
; Starts from a source file that exactly fills one 4K TM8 allocation block,
; saves source page 8 through the editor save path, and lets the host verify
; that /src/main.asm and its backup were extended into newly allocated blocks.

        .org    0x4000

        .include "../../src/tecm8-equates.asm"

PROOF_PASS       .equ     0x42
PROOF_FAIL       .equ     0xE0

;! out carry,zero
;! clobbers A,BC,DE,HL
@Start:
        LD      A,1
        LD      (CaseMarker),A
        CALL    DisplayInit
        JP      C,ProofFailed

        LD      A,2
        LD      (CaseMarker),A
        CALL    EditorOpenMain
        JP      C,ProofFailed

        LD      A,3
        LD      (CaseMarker),A
        LD      A,8
        LD      (EditorNavCurrentPage),A
        LD      A,1
        LD      (EditorNavDirtySectors),A
        LD      HL,EditorAllocGrowthPage
        LD      DE,EditorNavPageBuffer
        LD      BC,512
        LDIR
        CALL    EditorSaveCurrentPage
        JP      C,ProofFailed

        LD      A,4
        LD      (CaseMarker),A
        LD      A,8
        LD      DE,EditorLoadMainPath
        LD      HL,EditorVerifyPage
        CALL    EditorLoadSourcePage
        JP      C,ProofFailed

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

        .include "../../src/glcd-tile.asm"
        .include "../../src/display-model.asm"
        .include "../../src/editor-block-state.asm"
        .include "../../src/editor-viewport.asm"
        .include "../../src/tecm8-string.asm"
        .include "../../src/tecm8-storage.asm"
        .include "../../src/editor-storage-loader.asm"
        .include "../../src/editor-navigation.asm"
        .include "../../src/tecm8-bios.asm"

ResultMarker:
        .db     0

CaseMarker:
        .db     0

ErrorMarker:
        .db     0

EditorAllocGrowthPage:
        .db     10,"GROW P8 00"
        .ds     21
        .ds     480

EditorVerifyPage:
        .ds     512
