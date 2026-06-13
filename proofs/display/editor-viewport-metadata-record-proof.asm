; Editor viewport metadata-record proof.
;
; Verifies that source record length byte bits 5-7 are treated as metadata and
; the visible text length is read from bits 0-4.

        .org    0x4000

        .include "../../src/tecm8-equates.asm"

PROOF_PASS       .equ     0x42
PROOF_FAIL       .equ     0xE0

;! out carry,zero
;! clobbers A,BC,DE,HL
@Start:
        CALL    DisplayInit
        JR      C,ProofFailed

        LD      HL,MetadataEditorSourceRecords
        CALL    EditorViewportRender
        JR      C,ProofFailed

        CALL    GlcdTileFlushFull
        JR      C,ProofFailed

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
        .include "../../src/tecm8-bios.asm"

MetadataEditorSourceRecords:
        .db     0xA8,"META ROW"
        .ds     23
        .db     0x40
        .ds     31
        .db     0xFF,"ABCDEFGHIJKLMNOPQRSTUVWXYZ12345"
        .ds     32 * 7

ResultMarker:
        .db     0
