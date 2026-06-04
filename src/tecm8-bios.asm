; TECM8 BIOS compatibility wrappers.
;
; These entry points keep TECM8 code calling stable TECM8_BIOS_* names while
; MON3 remains the active storage implementation.

MON3_OPEN_FILE      .equ     0xF5A1
MON3_READ_SECTOR    .equ     0xF5D5
MON3_WRITE_SECTOR   .equ     0xF66D
MON3_GLCD_CLEAR_GBUF         .equ     0xD81D
MON3_GLCD_SET_GR_MODE        .equ     0xD86D
MON3_GLCD_PLOT_TO_LCD        .equ     0xDA90
MON3_GLCD_INIT_TERMINAL      .equ     0xDB18
MON3_GLCD_SEND_CHAR_TO_LCD   .equ     0xDB45
MON3_GLCD_SEND_STRING_TO_LCD .equ     0xDBB7
MON3_GLCD_SET_CURSOR         .equ     0xDC0A
MON3_GLCD_DRAW_GRAPHIC       .equ     0xDCEA
MON3_GLCD_VPORT              .equ     0x0E13
MON3_GLCD_TGBUF              .equ     0x13C0
TECM8_BIOS_DISPLAY_ERR_RANGE .equ     0x01

; TECM8_BIOS_FILE_OPEN -
; Open a MON3/FAT32 file by NUL-terminated name.
;!      in        HL
;!      out       carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@TECM8_BIOS_FILE_OPEN:
        CALL    MON3_OPEN_FILE
        RET

; TECM8_BIOS_FILE_READ_SECTOR -
; Read a 512-byte sector from the current MON3 file into DISK_BUFF.
;!      in        DE,HL
;!      out       carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@TECM8_BIOS_FILE_READ_SECTOR:
        CALL    MON3_READ_SECTOR
        RET

; TECM8_BIOS_FILE_WRITE_SECTOR -
; Write a 512-byte sector from DISK_BUFF to the current MON3 file.
;!      in        DE,HL
;!      out       carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@TECM8_BIOS_FILE_WRITE_SECTOR:
        CALL    MON3_WRITE_SECTOR
        RET

; TECM8_BIOS_DISPLAY_INIT -
; Initialize the MON3 GLCD terminal path for TECM8 display output.
;!      out       carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@TECM8_BIOS_DISPLAY_INIT:
        CALL    MON3_GLCD_INIT_TERMINAL
        XOR     A
        RET

; TECM8_BIOS_DISPLAY_CLEAR -
; Clear the active MON3 GLCD terminal buffer.
;!      out       carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@TECM8_BIOS_DISPLAY_CLEAR:
        CALL    MON3_GLCD_INIT_TERMINAL
        XOR     A
        RET

; TECM8_BIOS_DISPLAY_SET_CURSOR -
; Move the GLCD graphics cursor. B = X pixel, C = Y pixel.
;!      in        B,C
;!      out       carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@TECM8_BIOS_DISPLAY_SET_CURSOR:
        CALL    MON3_GLCD_SET_CURSOR
        XOR     A
        RET

; TECM8_BIOS_DISPLAY_PUT_CHAR -
; Write one ASCII character through the MON3 GLCD terminal.
;!      in        A
;!      out       carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@TECM8_BIOS_DISPLAY_PUT_CHAR:
        LD      C,A
        CALL    MON3_GLCD_SEND_CHAR_TO_LCD
        XOR     A
        RET

; TECM8_BIOS_DISPLAY_PUT_STRING -
; Write a NUL-terminated ASCII string through the MON3 GLCD terminal.
;!      in        HL
;!      out       carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@TECM8_BIOS_DISPLAY_PUT_STRING:
        LD      D,H
        LD      E,L
        LD      C,0
        CALL    MON3_GLCD_SEND_STRING_TO_LCD
        XOR     A
        RET

; TECM8_BIOS_DISPLAY_DRAW_CHAR_AT -
; Draw one 6x6 font character at B,C pixel coordinates without terminal scroll.
;!      in        A,B,C
;!      out       A,carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@TECM8_BIOS_DISPLAY_DRAW_CHAR_AT:
        LD      (BiosDisplayChar),A
        LD      A,C
        CP      0x40
        JR      NC,BiosDisplayDrawCharRange
        LD      A,B
        CP      0x80
        JR      NC,BiosDisplayDrawCharRange
        LD      HL,MON3_GLCD_TGBUF
        LD      (MON3_GLCD_VPORT),HL
        CALL    MON3_GLCD_SET_CURSOR
        LD      A,(BiosDisplayChar)
        LD      D,A
        CALL    MON3_GLCD_DRAW_GRAPHIC
        XOR     A
        RET

BiosDisplayDrawCharRange:
        LD      A,TECM8_BIOS_DISPLAY_ERR_RANGE
        SCF
        RET

; TECM8_BIOS_DISPLAY_UPDATE -
; Push the current MON3 GLCD viewport to the physical/displayed GLCD state.
;!      out       carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@TECM8_BIOS_DISPLAY_UPDATE:
        CALL    MON3_GLCD_PLOT_TO_LCD
        XOR     A
        RET

; TECM8_BIOS_DISPLAY_SET_BITMAP_MODE -
; Select the MON3 GLCD graphics mode for bitmap operations.
;!      out       carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@TECM8_BIOS_DISPLAY_SET_BITMAP_MODE:
        CALL    MON3_GLCD_SET_GR_MODE
        XOR     A
        RET

BiosDisplayChar:
        .db     0
