; TECM8 BIOS compatibility wrappers.
;
; These entry points keep TECM8 code calling stable PascalCase BIOS names while
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
MON3_MATRIX_SCAN             .equ     0xCC40
MON3_MATRIX_SCAN_ASCII       .equ     0xD0CB
MON3_PARSE_MATRIX_SCAN       .equ     0xD142
MON3_GET_CAPS                .equ     0xCFCA
MON3_TOGGLE_CAPS             .equ     0xD02B
MON3_GLCD_VPORT              .equ     0x0E13
MON3_GLCD_TGBUF              .equ     0x13C0
TECM8_BIOS_DISPLAY_ERR_RANGE .equ     0x01
TECM8_BIOS_KEY_MOD_SHIFT     .equ     0x01
TECM8_BIOS_KEY_MOD_CTRL      .equ     0x02
TECM8_BIOS_KEY_MOD_FN        .equ     0x04
TECM8_BIOS_KEY_MOD_ALT       .equ     0x08
TECM8_BIOS_KEY_MOD_CAPS      .equ     0x10

; BiosFileOpen -
; Open a MON3/FAT32 file by NUL-terminated name.
;!      in        HL
;!      out       carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@BiosFileOpen:
        CALL    MON3_OPEN_FILE
        RET

; BiosFileReadSector -
; Read a 512-byte sector from the current MON3 file into DISK_BUFF.
;!      in        DE,HL
;!      out       carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@BiosFileReadSector:
        CALL    MON3_READ_SECTOR
        RET

; BiosFileWriteSector -
; Write a 512-byte sector from DISK_BUFF to the current MON3 file.
;!      in        DE,HL
;!      out       carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@BiosFileWriteSector:
        CALL    MON3_WRITE_SECTOR
        RET

; BiosDisplayInit -
; Initialize the MON3 GLCD terminal path for TECM8 display output.
;!      out       carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@BiosDisplayInit:
        CALL    MON3_GLCD_INIT_TERMINAL
        CALL    MON3_GLCD_CLEAR_GBUF
        CALL    MON3_GLCD_PLOT_TO_LCD
        XOR     A
        RET

; BiosDisplayClear -
; Clear the active MON3 GLCD graphics buffer without reinitializing the terminal
; cursor policy.
;!      out       carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@BiosDisplayClear:
        CALL    MON3_GLCD_CLEAR_GBUF
        CALL    MON3_GLCD_PLOT_TO_LCD
        XOR     A
        RET

; BiosDisplaySetCursor -
; Move the GLCD graphics cursor. B = X pixel, C = Y pixel.
;!      in        B,C
;!      out       carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@BiosDisplaySetCursor:
        CALL    MON3_GLCD_SET_CURSOR
        XOR     A
        RET

; BiosDisplayPutChar -
; Write one ASCII character through the MON3 GLCD terminal.
;!      in        A
;!      out       carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@BiosDisplayPutChar:
        LD      C,A
        CALL    MON3_GLCD_SEND_CHAR_TO_LCD
        XOR     A
        RET

; BiosDisplayPutString -
; Write a NUL-terminated ASCII string through the MON3 GLCD terminal.
;!      in        HL
;!      out       carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@BiosDisplayPutString:
        LD      D,H
        LD      E,L
        LD      C,0
        CALL    MON3_GLCD_SEND_STRING_TO_LCD
        XOR     A
        RET

; BiosDisplayDrawCharAt -
; Draw one 6x6 font character at B,C pixel coordinates without terminal scroll.
;!      in        A,B,C
;!      out       A,carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@BiosDisplayDrawCharAt:
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

; BiosDisplayUpdate -
; Push the current MON3 GLCD viewport to the physical/displayed GLCD state.
;!      out       carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@BiosDisplayUpdate:
        CALL    MON3_GLCD_PLOT_TO_LCD
        XOR     A
        RET

; BiosDisplaySetBitmapMode -
; Select the MON3 GLCD graphics mode for bitmap operations.
;!      out       carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@BiosDisplaySetBitmapMode:
        CALL    MON3_GLCD_SET_GR_MODE
        XOR     A
        RET

; BiosInputPollAscii -
; Poll MON3's matrix keyboard scanner once.
; Output:
;   carry set: A = debounced ASCII key from MON3 parseMatrixScan
;   carry clear: no ASCII key is ready
;!      out       A,carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@BiosInputPollAscii:
        CALL    MON3_MATRIX_SCAN
        CALL    MON3_PARSE_MATRIX_SCAN
        RET

; BiosInputPollKey -
; Poll MON3's raw matrix scanner once and return a TECM8 key event.
; Output:
;   carry set:   A = translated key/code, B = modifier flags, D/E = raw scan
;   carry clear: no new key event; D/E contain the latest raw scan result or FFh
; Normal callers should use A/B. D/E are exposed for diagnostics and unmapped
; key handling.
;!      out       A,B,D,E,carry
;!      clobbers  A,BC,DE,HL,zero,sign,parity,halfCarry
@BiosInputPollKey:
        CALL    MON3_MATRIX_SCAN
        JR      Z,BiosInputPollKeyRaw
        LD      A,E
        CP      0x40
        JR      NC,BiosInputPollKeyNoRaw
        LD      A,D
        CP      3
        JR      NZ,BiosInputPollKeyNoRaw

BiosInputPollKeyRaw:
        LD      A,D
        LD      (BiosInputRawSecondary),A
        LD      A,E
        LD      (BiosInputRawPrimary),A
        LD      A,(BiosInputLastPrimary)
        CP      E
        JR      NZ,BiosInputPollKeyNew
        LD      A,(BiosInputLastSecondary)
        CP      D
        JR      NZ,BiosInputPollKeyNew
        OR      A
        RET

BiosInputPollKeyNew:
        LD      A,E
        LD      (BiosInputLastPrimary),A
        LD      A,D
        LD      (BiosInputLastSecondary),A
        LD      A,E
        CP      0x07
        JR      Z,BiosInputPollKeyToggleCaps
        CALL    BiosInputIgnoreStandaloneModifier
        RET     NC
        LD      A,D
        CALL    BiosInputModifierFlags
        LD      (BiosInputModifierBits),A
        LD      A,(BiosInputRawSecondary)
        LD      (BiosInputLastChordModifier),A
        LD      D,A
        LD      A,(BiosInputRawPrimary)
        LD      E,A
        CALL    MON3_MATRIX_SCAN_ASCII
        LD      (BiosInputTranslatedKey),A
        CALL    MON3_GET_CAPS
        OR      A
        JR      Z,BiosInputPollKeyNoCaps
        LD      A,(BiosInputModifierBits)
        OR      TECM8_BIOS_KEY_MOD_CAPS
        LD      (BiosInputModifierBits),A

BiosInputPollKeyNoCaps:
        LD      A,(BiosInputTranslatedKey)
        CALL    BiosInputNormalizeControlKey
        LD      (BiosInputTranslatedKey),A
        LD      A,(BiosInputRawSecondary)
        LD      D,A
        LD      A,(BiosInputRawPrimary)
        LD      E,A
        LD      A,(BiosInputModifierBits)
        LD      B,A
        LD      A,(BiosInputTranslatedKey)
        SCF
        RET

BiosInputPollKeyToggleCaps:
        CALL    MON3_TOGGLE_CAPS

        LD      A,(BiosInputRawSecondary)
        LD      D,A
        LD      A,(BiosInputRawPrimary)
        LD      E,A
        XOR     A
        RET

BiosInputPollKeyNoRaw:
        LD      A,0xFF
        LD      (BiosInputLastPrimary),A
        LD      (BiosInputLastSecondary),A
        LD      (BiosInputLastChordModifier),A
        LD      D,0xFF
        LD      E,0xFF
        XOR     A
        RET

; BiosInputIgnoreStandaloneModifier -
; Modifier keys pressed alone are state, not editor actions. Alt shares raw
; primary 03h with ArrowUp in the current matrix path, so Alt is suppressed
; only when it is the modifier left held after a real chord.
;!      out       A,carry
;!      clobbers  A,zero,sign,parity,halfCarry
@BiosInputIgnoreStandaloneModifier:
        LD      A,(BiosInputRawSecondary)
        CALL    BiosInputModifierFlags
        OR      A
        JR      NZ,BiosInputIgnoreStandaloneModifierRealKey
        LD      A,(BiosInputRawPrimary)
        CP      3
        JR      C,BiosInputIgnoreStandaloneModifierUnambiguous
        JR      NZ,BiosInputIgnoreStandaloneModifierRealKey
        LD      A,(BiosInputLastChordModifier)
        CP      3
        JR      NZ,BiosInputIgnoreStandaloneModifierRealKey

BiosInputIgnoreStandaloneModifierUnambiguous:
        CALL    BiosInputModifierFlags
        OR      A
        JR      Z,BiosInputIgnoreStandaloneModifierRealKey
        LD      A,0xFF
        LD      (BiosInputLastChordModifier),A
        XOR     A
        RET

BiosInputIgnoreStandaloneModifierRealKey:
        SCF
        RET

;!      in        A
;!      out       A,carry
;!      clobbers  A,zero,sign,parity,halfCarry
@BiosInputModifierFlags:
        CP      0
        JR      Z,BiosInputModifierShift
        CP      1
        JR      Z,BiosInputModifierCtrl
        CP      2
        JR      Z,BiosInputModifierFn
        CP      3
        JR      Z,BiosInputModifierAlt
        XOR     A
        RET

BiosInputModifierShift:
        LD      A,TECM8_BIOS_KEY_MOD_SHIFT
        RET

BiosInputModifierCtrl:
        LD      A,TECM8_BIOS_KEY_MOD_CTRL
        RET

BiosInputModifierFn:
        LD      A,TECM8_BIOS_KEY_MOD_FN
        RET

BiosInputModifierAlt:
        LD      A,TECM8_BIOS_KEY_MOD_ALT
        RET

; BiosInputNormalizeControlKey -
; Convert Ctrl+A..Z and Ctrl+a..z into ASCII control codes 01h..1Ah.
; Input: A = translated ASCII/key code
;!      in        A
;!      out       A
;!      clobbers  A,C,zero,sign,parity,halfCarry
@BiosInputNormalizeControlKey:
        LD      C,A
        LD      A,(BiosInputModifierBits)
        AND     TECM8_BIOS_KEY_MOD_CTRL
        JR      Z,BiosInputNormalizeNoCtrl
        LD      A,C
        CP      "A"
        JR      C,BiosInputNormalizeLower
        CP      "Z" + 1
        JR      NC,BiosInputNormalizeLower
        AND     0x1F
        RET

BiosInputNormalizeLower:
        LD      A,C
        CP      "a"
        JR      C,BiosInputNormalizeNoCtrl
        CP      "z" + 1
        JR      NC,BiosInputNormalizeNoCtrl
        AND     0x1F
        RET

BiosInputNormalizeNoCtrl:
        LD      A,C
        RET

BiosDisplayChar:
        .db     0

BiosInputLastPrimary:
        .db     0xFF

BiosInputLastSecondary:
        .db     0xFF

BiosInputLastChordModifier:
        .db     0xFF

BiosInputRawPrimary:
        .db     0xFF

BiosInputRawSecondary:
        .db     0xFF

BiosInputTranslatedKey:
        .db     0

BiosInputModifierBits:
        .db     0
