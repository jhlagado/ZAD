; TECM8 shared assembly equates.
;
; This file emits no bytes. Include it once from each top-level program or
; proof before including TECM8 source modules.

TECM8_SOURCE_RECORD_BYTES          .equ    32
TECM8_SOURCE_RECORD_TEXT_MAX       .equ    TECM8_SOURCE_RECORD_BYTES - 1
TECM8_SOURCE_RECORD_LENGTH_MASK    .equ    0x1F
TECM8_SOURCE_RECORD_METADATA_MASK  .equ    0xE0
TECM8_SOURCE_RECORDS_PER_PAGE      .equ    16
TECM8_SECTOR_BYTES                 .equ    512

TECM8_GLCD_COLUMNS                 .equ    20
TECM8_GLCD_ROWS                    .equ    10
TECM8_GLCD_CELL_WIDTH              .equ    6
TECM8_GLCD_CELL_HEIGHT             .equ    6
TECM8_GLCD_TEXT_X                  .equ    6
TECM8_GLCD_Y_ORIGIN                .equ    2
TECM8_GLCD_BITMAP_ROW_BYTES        .equ    16
TECM8_GLCD_CELL_ROW_STRIDE         .equ    TECM8_GLCD_CELL_HEIGHT * TECM8_GLCD_BITMAP_ROW_BYTES
TECM8_MON3_GLCD_VPORT             .equ    0x0E13
TECM8_MON3_GLCD_TGBUF             .equ    0x13C0

TECM8_KEY_MOD_SHIFT                .equ    0x01
TECM8_KEY_MOD_CTRL                 .equ    0x02
TECM8_KEY_MOD_FN                   .equ    0x04
TECM8_KEY_MOD_ALT                  .equ    0x08
TECM8_KEY_MOD_CAPS                 .equ    0x10
