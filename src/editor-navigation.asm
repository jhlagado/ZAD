; TECM8 editor navigation state.
;
; Minimal storage-backed page navigation for a TM8 source path.

TECM8_EDITOR_NAV_ERR_PAGE       .equ    0x50
TECM8_EDITOR_NAV_ERR_PATH       .equ    0x51
TECM8_EDITOR_NAV_PATH_LEN       .equ    64

; TECM8_EDITOR_OPEN_MAIN -
; Reset navigation to page 0 and render /src/main.asm.
;!      out       A,carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@TECM8_EDITOR_OPEN_MAIN:
        LD      HL,EditorNavMainPath
        JP      TECM8_EDITOR_OPEN_PATH

; TECM8_EDITOR_OPEN_PATH -
; Reset navigation to page 0 and render the source file at HL.
;!      in        HL
;!      out       A,carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@TECM8_EDITOR_OPEN_PATH:
        LD      DE,EditorNavPathBuffer
        LD      B,TECM8_EDITOR_NAV_PATH_LEN
        CALL    EditorNavCopyPath
        RET     C
        LD      HL,EditorNavPathBuffer
        LD      (EditorNavPathPtr),HL
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

; TECM8_EDITOR_RENDER_PAGE_BUFFER -
; Render the already-loaded page buffer without reloading it from storage.
;!      out       A,carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@TECM8_EDITOR_RENDER_PAGE_BUFFER:
        LD      HL,EditorNavPageBuffer
        CALL    TECM8_EDITOR_VIEWPORT_RENDER
        RET     C
        CALL    TECM8_BIOS_DISPLAY_UPDATE
        RET

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
        LD      DE,(EditorNavPathPtr)
        LD      HL,EditorNavPageBuffer
        CALL    TECM8_EDITOR_LOAD_SOURCE_PAGE
        RET     C
        JP      TECM8_EDITOR_RENDER_PAGE_BUFFER

EditorNavPageErr:
        LD      A,TECM8_EDITOR_NAV_ERR_PAGE
        SCF
        RET

;!      in        B,DE,HL
;!      out       A,carry,zero
;!      clobbers  B,DE,HL
@EditorNavCopyPath:
        LD      A,B
        OR      A
        JR      Z,EditorNavPathErr

EditorNavCopyPathLoop:
        LD      A,(HL)
        LD      (DE),A
        INC     HL
        INC     DE
        OR      A
        RET     Z
        DEC     B
        JR      NZ,EditorNavCopyPathLoop

EditorNavPathErr:
        LD      A,TECM8_EDITOR_NAV_ERR_PATH
        SCF
        RET

EditorNavCurrentPage:
        .db     0

EditorNavPendingPage:
        .db     0

EditorNavPathPtr:
        .dw     0

EditorNavMainPath:
        .db     "/src/main.asm",0

EditorNavPathBuffer:
        .ds     TECM8_EDITOR_NAV_PATH_LEN

EditorNavPageBuffer:
        .ds     512
