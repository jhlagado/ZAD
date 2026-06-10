; Editor file listing proof.
;
; Lists /src and proves ordinary listing output hides leading-dot backup files.

        .org    0x4000

PROOF_PASS       .equ     0x42
PROOF_FAIL       .equ     0xE0

;!      out       carry,zero
;!      clobbers  A,BC,DE,HL
@Start:
        LD      DE,ListPrefix
        LD      HL,ListOut
        LD      B,LIST_OUT_BYTES
        CALL    FillListBuffer
        LD      DE,ListPrefix
        LD      HL,ListOut
        LD      B,LIST_OUT_BYTES
        CALL    EditorListVisibleFiles
        JR      C,ProofFailed

        LD      DE,NestedListPrefix
        LD      HL,NestedListOut
        LD      B,LIST_OUT_BYTES
        CALL    FillListBuffer
        LD      DE,NestedListPrefix
        LD      HL,NestedListOut
        LD      B,LIST_OUT_BYTES
        CALL    EditorListVisibleFiles
        JR      C,ProofFailed

        LD      DE,RootListPrefix
        LD      HL,RootListOut
        LD      B,LIST_OUT_BYTES
        CALL    FillListBuffer
        LD      DE,RootListPrefix
        LD      HL,RootListOut
        LD      B,LIST_OUT_BYTES
        CALL    EditorListVisibleFiles
        JR      C,ProofFailed

        LD      A,PROOF_PASS
        LD      (ResultMarker),A

ProofDone:
        JP      ProofDone

ProofFailed:
        LD      (ErrorMarker),A
        LD      A,PROOF_FAIL
        LD      (ResultMarker),A

ProofFailedDone:
        JP      ProofDone

;!      in        B,HL
;!      out       carry,zero
;!      clobbers  A,B,HL
@FillListBuffer:
        LD      A,0xA5

FillListBufferLoop:
        LD      (HL),A
        INC     HL
        DJNZ    FillListBufferLoop
        XOR     A
        RET

        .include "../../src/editor-storage-loader.asm"
        .include "../../src/editor-file-list.asm"
        .include "../../src/tecm8-bios.asm"

ListPrefix:
        .db     "/src",0

NestedListPrefix:
        .db     "/projects/demo",0

RootListPrefix:
        .db     "/",0

LIST_OUT_BYTES   .equ    128

ListOut:
        .ds     LIST_OUT_BYTES

NestedListOut:
        .ds     LIST_OUT_BYTES

RootListOut:
        .ds     LIST_OUT_BYTES

ResultMarker:
        .db     0

ErrorMarker:
        .db     0
