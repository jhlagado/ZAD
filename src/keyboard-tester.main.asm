; TECM8 keyboard tester.
;
; Standalone diagnostic target for Debug80/TEC-1G matrix keyboard testing.
; Load at 4000h and GO from MON3. It displays each accepted key event as
; raw secondary/primary bytes followed by the interpreted token.

        .org    0x4000

        .include "tecm8-equates.asm"

KbdTestHistoryFirstRow              .equ    2
KbdTestHistoryLastRow               .equ    TECM8_GLCD_TILE_ROWS - 1
KbdTestKeyArrowUp                   .equ    0x03
KbdTestKeyArrowDown                 .equ    0x04
KbdTestKeyArrowLeft                 .equ    0x05
KbdTestKeyArrowRight                .equ    0x06
KbdTestKeyBackspace                 .equ    0x08
KbdTestKeyTab                       .equ    0x09
KbdTestKeyEnter                     .equ    0x0D
KbdTestKeyEscape                    .equ    0x1B
KbdTestKeyDelete                    .equ    0x7F

@Start:
        CALL    BiosDisplayInit
        JP      C,KbdTestFatal
        CALL    BiosDisplaySetBitmapMode
        JP      C,KbdTestFatal
        CALL    KbdTestClearScreen
        JP      C,KbdTestFatal
        CALL    KbdTestRenderHeader
        JP      C,KbdTestFatal

KbdTestLoop:
        CALL    BiosInputPollKey
        JR      NC,KbdTestIdle
        CALL    KbdTestAppendKey
        JP      C,KbdTestFatal

KbdTestIdle:
        CALL    GlcdTileStep
        JP      C,KbdTestFatal
        JP      KbdTestLoop

;! out carry
;! clobbers A,BC,DE,HL,zero,sign,parity,halfCarry
@KbdTestClearScreen:
        XOR     A
        LD      (KbdTestRow),A

KbdTestClearScreenLoop:
        LD      A,(KbdTestRow)
        CP      TECM8_GLCD_TILE_ROWS
        JR      NC,KbdTestClearScreenDone
        LD      B,A
        CALL    GlcdTileClearTextRow
        RET     C
        LD      A,(KbdTestRow)
        INC     A
        LD      (KbdTestRow),A
        JR      KbdTestClearScreenLoop

KbdTestClearScreenDone:
        CALL    GlcdTileFlushFull
        RET     C
        LD      A,KbdTestHistoryFirstRow
        LD      (KbdTestRow),A
        XOR     A
        LD      (KbdTestColumn),A
        RET

;! out carry
;! clobbers A,BC,DE,HL,zero,sign,parity,halfCarry
@KbdTestRenderHeader:
        LD      HL,KbdTestTitle
        LD      B,0
        LD      C,0
        CALL    GlcdTileDrawTextRun
        RET     C
        LD      HL,KbdTestLegend
        LD      B,1
        LD      C,0
        CALL    GlcdTileDrawTextRun
        RET     C
        CALL    GlcdTileFlushFull
        RET

; Append one translated key event to the rolling display log.
; Input: A = translated key/code, B = modifier flags, D/E = raw scan
;! in A,B,D,E
;! out carry
;! clobbers A,BC,DE,HL,zero,sign,parity,halfCarry
@KbdTestAppendKey:
        LD      (KbdTestKeyCode),A
        LD      A,B
        LD      (KbdTestKeyMods),A
        LD      A,D
        LD      (KbdTestRawSecondary),A
        LD      A,E
        LD      (KbdTestRawPrimary),A

        LD      A,(KbdTestRawSecondary)
        CALL    KbdTestAppendHexByte
        RET     C
        LD      A,(KbdTestRawPrimary)
        CALL    KbdTestAppendHexByte
        RET     C

        LD      A,(KbdTestKeyMods)
        AND     TECM8_BIOS_KEY_MOD_CTRL
        JR      NZ,KbdTestAppendCtrl
        LD      A,(KbdTestKeyMods)
        AND     TECM8_BIOS_KEY_MOD_ALT
        JR      NZ,KbdTestAppendAlt

        LD      A,(KbdTestKeyCode)
        CALL    KbdTestAppendKeyName
        JR      KbdTestAppendTokenDone

KbdTestAppendCtrl:
        LD      A,"^"
        CALL    KbdTestAppendChar
        RET     C
        LD      A,(KbdTestKeyCode)
        CALL    KbdTestAppendCtrlName
        JR      KbdTestAppendTokenDone

KbdTestAppendAlt:
        LD      A,0x5C
        CALL    KbdTestAppendChar
        RET     C
        LD      A,(KbdTestKeyCode)
        CALL    KbdTestAppendChordName

KbdTestAppendTokenDone:
        RET     C
        LD      A," "
        CALL    KbdTestAppendChar
        RET     C
        CALL    GlcdTileFlushFull
        RET

;! in A
;! out carry
;! clobbers A,BC,DE,HL,zero,sign,parity,halfCarry
@KbdTestAppendCtrlName:
        LD      (KbdTestSpecialCandidate),A
        CP      KbdTestKeyArrowUp
        JR      C,KbdTestAppendCtrlLetter
        CP      KbdTestKeyArrowRight + 1
        JR      NC,KbdTestAppendCtrlLetter
        LD      B,A
        LD      A,(KbdTestRawPrimary)
        CP      B
        JR      NZ,KbdTestAppendCtrlLetter
        LD      A,B
        JP      KbdTestAppendSpecialName

KbdTestAppendCtrlLetter:
        LD      A,(KbdTestSpecialCandidate)
        CP      1
        JR      C,KbdTestAppendChordName
        CP      27
        JR      NC,KbdTestAppendChordName
        ADD     A,0x40
        JP      KbdTestAppendChar

;! in A
;! out carry
;! clobbers A,BC,DE,HL,zero,sign,parity,halfCarry
@KbdTestAppendChordName:
        CALL    KbdTestUppercaseAscii
        CP      " "
        JR      C,KbdTestAppendSpecialName
        CP      0x7F
        JR      NC,KbdTestAppendSpecialName
        JP      KbdTestAppendChar

;! in A
;! out carry
;! clobbers A,BC,DE,HL,zero,sign,parity,halfCarry
@KbdTestAppendKeyName:
        CP      " "
        JR      C,KbdTestAppendSpecialName
        CP      0x7F
        JR      NC,KbdTestAppendSpecialName
        JP      KbdTestAppendChar

; Compact names for non-printable/special keys.
; ^/>/</_ = arrows, B = backspace, T = tab, N = enter, E = escape, X = delete.
;! in A
;! out carry
;! clobbers A,BC,DE,HL,zero,sign,parity,halfCarry
@KbdTestAppendSpecialName:
        CP      KbdTestKeyArrowUp
        JR      Z,KbdTestAppendSpecialUp
        CP      KbdTestKeyArrowDown
        JR      Z,KbdTestAppendSpecialDown
        CP      KbdTestKeyArrowLeft
        JR      Z,KbdTestAppendSpecialLeft
        CP      KbdTestKeyArrowRight
        JR      Z,KbdTestAppendSpecialRight
        CP      KbdTestKeyBackspace
        JR      Z,KbdTestAppendSpecialBackspace
        CP      KbdTestKeyTab
        JR      Z,KbdTestAppendSpecialTab
        CP      KbdTestKeyEnter
        JR      Z,KbdTestAppendSpecialEnter
        CP      KbdTestKeyEscape
        JR      Z,KbdTestAppendSpecialEscape
        CP      KbdTestKeyDelete
        JR      Z,KbdTestAppendSpecialDelete
        LD      A,"?"
        JP      KbdTestAppendChar

KbdTestAppendSpecialUp:
        LD      A,"^"
        JP      KbdTestAppendChar

KbdTestAppendSpecialDown:
        LD      A,"_"
        JP      KbdTestAppendChar

KbdTestAppendSpecialLeft:
        LD      A,"<"
        JP      KbdTestAppendChar

KbdTestAppendSpecialRight:
        LD      A,">"
        JP      KbdTestAppendChar

KbdTestAppendSpecialBackspace:
        LD      A,"B"
        JP      KbdTestAppendChar

KbdTestAppendSpecialTab:
        LD      A,"T"
        JP      KbdTestAppendChar

KbdTestAppendSpecialEnter:
        LD      A,"N"
        JP      KbdTestAppendChar

KbdTestAppendSpecialEscape:
        LD      A,"E"
        JP      KbdTestAppendChar

KbdTestAppendSpecialDelete:
        LD      A,"X"
        JP      KbdTestAppendChar

;! in A
;! out A
;! clobbers A,zero,sign,parity,halfCarry
@KbdTestUppercaseAscii:
        CP      "a"
        RET     C
        CP      "z" + 1
        RET     NC
        SUB     0x20
        RET

;! in A
;! out carry
;! clobbers A,BC,DE,HL,zero,sign,parity,halfCarry
@KbdTestAppendChar:
        LD      (KbdTestPendingChar),A
        LD      A,(KbdTestColumn)
        CP      TECM8_GLCD_TILE_COLUMNS
        JR      C,KbdTestAppendCharReady
        CALL    KbdTestAdvanceLine
        RET     C

KbdTestAppendCharReady:
        LD      A,(KbdTestRow)
        LD      B,A
        LD      A,(KbdTestColumn)
        LD      C,A
        LD      A,(KbdTestPendingChar)
        CALL    GlcdTileDrawCell
        RET     C
        LD      A,(KbdTestColumn)
        INC     A
        LD      (KbdTestColumn),A
        XOR     A
        RET

;! out carry
;! clobbers A,BC,DE,HL,zero,sign,parity,halfCarry
@KbdTestAdvanceLine:
        XOR     A
        LD      (KbdTestColumn),A
        LD      A,(KbdTestRow)
        INC     A
        CP      KbdTestHistoryLastRow + 1
        JR      C,KbdTestAdvanceLineStore
        CALL    KbdTestClearHistory
        RET     C
        LD      A,KbdTestHistoryFirstRow

KbdTestAdvanceLineStore:
        LD      (KbdTestRow),A
        XOR     A
        RET

;! out carry
;! clobbers A,BC,DE,HL,zero,sign,parity,halfCarry
@KbdTestClearHistory:
        LD      A,KbdTestHistoryFirstRow
        LD      (KbdTestClearRow),A

KbdTestClearHistoryLoop:
        LD      A,(KbdTestClearRow)
        CP      KbdTestHistoryLastRow + 1
        JR      NC,KbdTestClearHistoryDone
        LD      B,A
        CALL    GlcdTileClearTextRow
        RET     C
        LD      A,(KbdTestClearRow)
        INC     A
        LD      (KbdTestClearRow),A
        JR      KbdTestClearHistoryLoop

KbdTestClearHistoryDone:
        CALL    GlcdTileFlushFull
        RET

;! in A,HL
;! out HL
;! clobbers A,BC,HL,zero,sign,parity,halfCarry
@KbdTestWriteHexByte:
        LD      B,A
        AND     0xF0
        RRCA
        RRCA
        RRCA
        RRCA
        CALL    KbdTestHexNibble
        LD      (HL),A
        INC     HL
        LD      A,B
        AND     0x0F
        CALL    KbdTestHexNibble
        LD      (HL),A
        RET

;! in A
;! out carry
;! clobbers A,BC,DE,HL,zero,sign,parity,halfCarry
@KbdTestAppendHexByte:
        LD      HL,KbdTestHexBuffer
        CALL    KbdTestWriteHexByte
        LD      A,(KbdTestHexBuffer)
        CALL    KbdTestAppendChar
        RET     C
        LD      A,(KbdTestHexBuffer + 1)
        CALL    KbdTestAppendChar
        RET

;! in A
;! out A
;! clobbers A,zero,sign,parity,halfCarry
@KbdTestHexNibble:
        CP      10
        JR      C,KbdTestHexDigit
        ADD     A,"A" - 10
        RET

KbdTestHexDigit:
        ADD     A,"0"
        RET

KbdTestFatal:
        JP      KbdTestFatal

KbdTestTitle:
        .db     "KEYBOARD TEST",0

KbdTestLegend:
        .db     "RAW+TOKEN STREAM",0

KbdTestRow:
        .db     0

KbdTestColumn:
        .db     0

KbdTestClearRow:
        .db     0

KbdTestPendingChar:
        .db     0

KbdTestSpecialCandidate:
        .db     0

KbdTestKeyCode:
        .db     0

KbdTestKeyMods:
        .db     0

KbdTestRawPrimary:
        .db     0

KbdTestRawSecondary:
        .db     0

KbdTestHexBuffer:
        .db     0,0

        .include "glcd-tile.asm"
        .include "tecm8-bios.asm"
