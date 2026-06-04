# MON3 GLCD Split Report

Generated from Debug80 MON3 bundle source and `mon3.d8.json`.

This is a label-range measurement of `glcd_library.z80`. Code ranges are
taken from Debug80 map labels. Data ranges use the following package label
as the end boundary where the GLCD source hands off to the next included package.

Measured GLCD package span: 3995 bytes (`0F9B`).

## ROM Category Split

| Category | ID | Bytes | Hex | Disposition | Ranges | Notes |
| --- | --- | ---: | --- | --- | --- | --- |
| Hardware init, clear, and mode setup | `hardware-init-clear-mode` | 130 | `0082` | `keep-reference` | `initLCD`-`drawBox` (130 bytes) | ST7920 setup, graphics/text mode switching, and full-screen clear routines. This is useful low-level hardware reference material. |
| Drawing primitives | `drawing-primitives` | 526 | `020E` | `rewrite` | `drawBox`-`plotToLCD` (526 bytes) | Box, line, circle, fill, pixel, and GBUF addressing routines. TECM8 should preserve bitmap capability, but can split these from the editor text path. |
| Plot and native text-mode helpers | `plot-text-mode` | 114 | `0072` | `keep-reference` | `plotToLCD`-`delayUS` (114 bytes) | GBUF-to-LCD transfer plus direct ST7920 text-mode string helpers. |
| Timing and buffer policy | `timing-buffer-policy` | 22 | `0016` | `rewrite` | `delayUS`-`initTerminal` (22 bytes) | LCD delay and clear/no-clear policy. TECM8 should keep timing knowledge but make buffer policy display-layer owned. |
| Terminal text core | `terminal-core` | 279 | `0117` | `rewrite` | `initTerminal`-`setCursor` (242 bytes)<br>`displayCursor`-`drawGraphic` (37 bytes) | Terminal initialization, character/control handling, ASCII hex output, cursor visibility, inverse, underline, auto-LF, and plot policy. |
| Cursor and scrollback viewport | `cursor-scroll` | 187 | `00BB` | `rewrite` | `setCursor`-`displayCursor` (187 bytes) | Cursor movement, six-pixel character cells, scroll-buffer shifting, and viewport movement. This is the part least aligned with a sector/page editor. |
| Glyph and cursor renderer | `glyph-renderer` | 169 | `00A9` | `rewrite` | `drawGraphic`-`ROWS` (169 bytes) | 6x6 font/sprite rendering, inverse, underline, cursor XOR, and blanking primitives. |
| Font and text constants | `font-data` | 1544 | `0608` | `keep-reference` | `ROWS`-`GLCD_BANNER` (1544 bytes) | ST7920 text row table, init table, and 256-character 6-byte font data. |
| MON3 GLCD banner bitmap | `banner-data` | 1024 | `0400` | `relocate` | `GLCD_BANNER`-`disStart` (1024 bytes) | A 1024-byte startup bitmap. Useful as a demo asset, but not resident BIOS functionality. |

## RAM Workspace

Practical GLCD RAM workspace: 3584 bytes (`0E00`) from `0A00` through `17FF`.

| Buffer | ID | Address Range | Bytes | Hex | Notes |
| --- | --- | --- | ---: | --- | --- |
| Graphics framebuffer (GBUF) | `gbuf` | `0A00`-`0DFF` | 1024 | `0400` | Primary 128x64 one-bit graphics framebuffer, 16 bytes by 64 rows. |
| Drawing scratch and terminal state | `scratch-state` | `0E00`-`0E19` | 26 | `001A` | Line/circle scratch values, clear-buffer flag, cursor state, viewport pointer, and terminal flags. |
| Unassigned gap before scroll buffer | `unassigned-gap` | `0E1A`-`0FFF` | 486 | `01E6` | Not named by the current GLCD constants, but inside the practical GLCD workspace. |
| Terminal scroll history (SBUF) | `sbuf` | `1000`-`13BF` | 960 | `03C0` | 960-byte scroll history: 16 bytes by 60 pixel rows, enough for ten 6-pixel terminal rows. |
| Terminal viewport framebuffer (TGBUF) | `tgbuf` | `13C0`-`17BF` | 1024 | `0400` | 1024-byte terminal graphics viewport used as the displayed text buffer. |
| Tail headroom | `tail-headroom` | `17C0`-`17FF` | 64 | `0040` | Small remaining tail in the documented 0A00h-17FFh practical GLCD area. |

## TECM8 Replacement Reading

The ROM split supports the current design direction: keep the low-level ST7920
hardware knowledge and the 6x6 font as reference material, but replace the
terminal-centric scrollback model with TECM8-owned display modes.

For the editor, the source sector/window should be the truth and the GLCD
framebuffer should be a rendering target. A single 1024-byte framebuffer is
non-negotiable for full bitmap output. The extra SBUF/TGBUF terminal buffers
are useful for MON3 terminal history, but should become optional mode-specific
RAM rather than a global requirement for every TECM8 text/editor view.

The 1024-byte MON3 banner is the clearest ROM relocation candidate. The
drawing primitives are useful, but should be decomposed so editor text,
status rows, gutter markers, inverse text, and bitmap drawing do not all
force the same terminal scrollback implementation.

Key GLCD labels:

| Label | Address | Source |
| --- | --- | --- |
| `initLCD` | `D800` | `glcd_library.z80:58` |
| `clearGBUF` | `D81D` | `glcd_library.z80:76` |
| `clearGrLCD` | `D82D` | `glcd_library.z80:87` |
| `setGrMode` | `D86D` | `glcd_library.z80:127` |
| `setTxtMode` | `D87B` | `glcd_library.z80:136` |
| `drawPixel` | `DA3D` | `glcd_library.z80:516` |
| `clearPixel` | `DA4E` | `glcd_library.z80:536` |
| `flipPixel` | `DA60` | `glcd_library.z80:557` |
| `plotToLCD` | `DA90` | `glcd_library.z80:608` |
| `initTerminal` | `DB18` | `glcd_library.z80:724` |
| `sendCharToLCD` | `DB45` | `glcd_library.z80:755` |
| `sendStringToLCD` | `DBB7` | `glcd_library.z80:825` |
| `setCursor` | `DC0A` | `glcd_library.z80:890` |
| `SHIFT_BUFFER` | `DC45` | `glcd_library.z80:939` |
| `MOVE_VPORT` | `DC7B` | `glcd_library.z80:971` |
| `drawGraphic` | `DCEA` | `glcd_library.z80:1076` |
| `FONT_DATA` | `DD9B` | `glcd_library.z80:1211` |
