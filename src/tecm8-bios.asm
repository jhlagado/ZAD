; TECM8 BIOS compatibility wrappers.
;
; These entry points keep TECM8 code calling stable TECM8_BIOS_* names while
; MON3 remains the active storage implementation.

MON3_OPEN_FILE      .equ     0xF5A1
MON3_READ_SECTOR    .equ     0xF5D5
MON3_WRITE_SECTOR   .equ     0xF66D

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
