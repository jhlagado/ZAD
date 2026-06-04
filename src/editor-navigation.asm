; TECM8 editor navigation state.
;
; Minimal storage-backed page navigation for /src/main.asm.

TECM8_EDITOR_NAV_ERR_PAGE       .equ    0x50

; TECM8_EDITOR_OPEN_MAIN -
; Reset navigation to page 0 and render /src/main.asm.
;!      out       A,carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@TECM8_EDITOR_OPEN_MAIN:
        XOR     A
        LD      (EditorNavCurrentPage),A
        JP      TECM8_EDITOR_RENDER_CURRENT

; TECM8_EDITOR_RENDER_CURRENT -
; Load and render the current page.
;!      out       A,carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@TECM8_EDITOR_RENDER_CURRENT:
        LD      A,(EditorNavCurrentPage)
        JP      EditorNavRenderPage

; TECM8_EDITOR_PAGE_DOWN -
; Advance one page, render it, and commit the page only if rendering succeeds.
;!      out       A,carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@TECM8_EDITOR_PAGE_DOWN:
        LD      A,(EditorNavCurrentPage)
        CP      127
        JR      Z,EditorNavPageErr
        INC     A
        LD      (EditorNavPendingPage),A
        CALL    EditorNavRenderPage
        RET     C
        LD      A,(EditorNavPendingPage)
        LD      (EditorNavCurrentPage),A
        XOR     A
        RET

; TECM8_EDITOR_PAGE_UP -
; Move back one page, render it, and commit the page only if rendering succeeds.
;!      out       A,carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@TECM8_EDITOR_PAGE_UP:
        LD      A,(EditorNavCurrentPage)
        OR      A
        JR      Z,EditorNavPageErr
        DEC     A
        LD      (EditorNavPendingPage),A
        CALL    EditorNavRenderPage
        RET     C
        LD      A,(EditorNavPendingPage)
        LD      (EditorNavCurrentPage),A
        XOR     A
        RET

;!      in        A
;!      out       A,carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@EditorNavRenderPage:
        LD      HL,EditorNavPageBuffer
        CALL    TECM8_EDITOR_LOAD_MAIN_SOURCE_PAGE
        RET     C
        LD      HL,EditorNavPageBuffer
        CALL    TECM8_EDITOR_VIEWPORT_RENDER
        RET     C
        CALL    TECM8_BIOS_DISPLAY_UPDATE
        RET

EditorNavPageErr:
        LD      A,TECM8_EDITOR_NAV_ERR_PAGE
        SCF
        RET

EditorNavCurrentPage:
        .db     0

EditorNavPendingPage:
        .db     0

EditorNavPageBuffer:
        .ds     512
