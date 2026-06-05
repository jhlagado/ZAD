; TECM8 editor navigation state.
;
; Minimal storage-backed page navigation for a TM8 source path.

TECM8_EDITOR_NAV_ERR_PAGE       .equ    0x50
TECM8_EDITOR_NAV_ERR_PATH       .equ    0x51
TECM8_EDITOR_NAV_PATH_LEN       .equ    64

; EditorOpenMain -
; Reset navigation to page 0 and render /src/main.asm.
;!      out       A,carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@EditorOpenMain:
        LD      HL,EditorNavMainPath
        JP      EditorOpenPath

; EditorOpenPath -
; Reset navigation to page 0 and render the source file at HL.
;!      in        HL
;!      out       A,carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@EditorOpenPath:
        LD      DE,EditorNavPathBuffer
        LD      B,TECM8_EDITOR_NAV_PATH_LEN
        CALL    EditorNavCopyPath
        RET     C
        LD      HL,EditorNavPathBuffer
        LD      (EditorNavPathPtr),HL
        XOR     A
        LD      (EditorNavCurrentPage),A
        JP      EditorRenderCurrent

; EditorRenderCurrent -
; Load and render the current page.
;!      out       A,carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@EditorRenderCurrent:
        LD      A,(EditorNavCurrentPage)
        JP      EditorNavRenderPage

; EditorRenderPageBuffer -
; Render the already-loaded page buffer without reloading it from storage.
;!      out       A,carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@EditorRenderPageBuffer:
        LD      HL,EditorNavPageBuffer
        CALL    EditorViewportRender
        RET     C
        CALL    BiosDisplayUpdate
        RET

; EditorSaveCurrentPage -
; Save the already-loaded page buffer back to the current source page.
;!      out       A,carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@EditorSaveCurrentPage:
        LD      A,(EditorNavCurrentPage)
        LD      DE,(EditorNavPathPtr)
        LD      HL,EditorNavPageBuffer
        JP      EditorSaveSourcePage

; EditorPageDown -
; Advance one page, render it, and commit the page only if rendering succeeds.
;!      out       A,carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@EditorPageDown:
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

; EditorPageUp -
; Move back one page, render it, and commit the page only if rendering succeeds.
;!      out       A,carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@EditorPageUp:
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
        CALL    EditorLoadSourcePage
        RET     C
        JP      EditorRenderPageBuffer

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
