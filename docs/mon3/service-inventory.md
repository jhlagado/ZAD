# MON3 Service Inventory

Generated from Debug80 MON3 bundle source and `mon3.d8.json`.

Classification is an initial planning aid, not a compatibility promise.
The current strategy is to keep classic MON3 identity first, then reclaim
space from GLCD replacement, PATA removal while preserving SD access, RTC
UI relocation, and optional text/extensions.

## RST 18h API

Selector register: `A`. Table symbol: `APITable2`.

| Table | Selector | Service | Address | Module | Source | Classification | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| RST 18h | `00h` | `initLCD` | `D800` | `glcd_library` | `glcd_library.z80:58` | `extension-rewrite` | Keep GLCD hardware knowledge; replace terminal/editor layer. |
| RST 18h | `01h` | `clearGBUF` | `D81D` | `glcd_library` | `glcd_library.z80:76` | `extension-rewrite` | GLCD buffer primitive for future TECM8 display renderer. |
| RST 18h | `02h` | `clearGrLCD` | `D82D` | `glcd_library` | `glcd_library.z80:87` | `extension-rewrite` | GLCD clear primitive for future TECM8 display renderer. |
| RST 18h | `03h` | `clearTxtLCD` | `D857` | `glcd_library` | `glcd_library.z80:113` | `extension-rewrite` | GLCD text clear primitive; terminal ownership should move to TECM8. |
| RST 18h | `04h` | `setGrMode` | `D86D` | `glcd_library` | `glcd_library.z80:127` | `extension-rewrite` | GLCD mode primitive. |
| RST 18h | `05h` | `setTxtMode` | `D87B` | `glcd_library` | `glcd_library.z80:136` | `extension-rewrite` | GLCD mode primitive. |
| RST 18h | `06h` | `drawBox` | `D882` | `glcd_library` | `glcd_library.z80:145` | `extension-rewrite` | GLCD drawing primitive. |
| RST 18h | `07h` | `drawLine` | `D8BD` | `glcd_library` | `glcd_library.z80:222` | `extension-rewrite` | GLCD drawing primitive. |
| RST 18h | `08h` | `drawCircle` | `D968` | `glcd_library` | `glcd_library.z80:370` | `extension-rewrite` | GLCD drawing primitive. |
| RST 18h | `09h` | `drawPixel` | `DA3D` | `glcd_library` | `glcd_library.z80:516` | `extension-rewrite` | GLCD drawing primitive. |
| RST 18h | `0Ah` | `fillBox` | `D8AD` | `glcd_library` | `glcd_library.z80:190` | `extension-rewrite` | GLCD drawing primitive. |
| RST 18h | `0Bh` | `fillCircle` | `DA2F` | `glcd_library` | `glcd_library.z80:500` | `extension-rewrite` | GLCD drawing primitive. |
| RST 18h | `0Ch` | `plotToLCD` | `DA90` | `glcd_library` | `glcd_library.z80:608` | `extension-rewrite` | GLCD plot/update primitive. |
| RST 18h | `0Dh` | `printString` | `DAC3` | `glcd_library` | `glcd_library.z80:646` | `extension-rewrite` | Text renderer primitive; likely replaced or wrapped. |
| RST 18h | `0Eh` | `printChars` | `DAE4` | `glcd_library` | `glcd_library.z80:677` | `extension-rewrite` | Text renderer primitive; likely replaced or wrapped. |
| RST 18h | `0Fh` | `delayUS` | `DB02` | `glcd_library` | `glcd_library.z80:699` | `bios-keep` | Timing service used by GLCD and other hardware paths. |
| RST 18h | `10h` | `delayMS` | `DB05` | `glcd_library` | `glcd_library.z80:701` | `bios-keep` | Timing service used by GLCD and other hardware paths. |
| RST 18h | `11h` | `setBufClear` | `DB0B` | `glcd_library` | `glcd_library.z80:710` | `extension-rewrite` | MON3 GLCD buffer policy; TECM8 should own display policy. |
| RST 18h | `12h` | `setBufNoClear` | `DB13` | `glcd_library` | `glcd_library.z80:715` | `extension-rewrite` | MON3 GLCD buffer policy; TECM8 should own display policy. |
| RST 18h | `13h` | `clearPixel` | `DA4E` | `glcd_library` | `glcd_library.z80:536` | `extension-rewrite` | GLCD drawing primitive. |
| RST 18h | `14h` | `flipPixel` | `DA60` | `glcd_library` | `glcd_library.z80:557` | `extension-rewrite` | GLCD drawing primitive. |
| RST 18h | `15h` | `drawGraphic` | `DCEA` | `glcd_library` | `glcd_library.z80:1076` | `extension-rewrite` | GLCD glyph/sprite primitive. |
| RST 18h | `16h` | `invGraphic` | `DCD0` | `glcd_library` | `glcd_library.z80:1036` | `extension-rewrite` | GLCD glyph/sprite primitive. |
| RST 18h | `17h` | `initTerminal` | `DB18` | `glcd_library` | `glcd_library.z80:724` | `extension-rewrite` | MON3 terminal layer is a replacement candidate. |
| RST 18h | `18h` | `sendCharToLCD` | `DB45` | `glcd_library` | `glcd_library.z80:755` | `extension-rewrite` | MON3 terminal layer is a replacement candidate. |
| RST 18h | `19h` | `sendStringToLCD` | `DBB7` | `glcd_library` | `glcd_library.z80:825` | `extension-rewrite` | MON3 terminal layer is a replacement candidate. |
| RST 18h | `1Ah` | `sendRegToLCD` | `DBDF` | `glcd_library` | `glcd_library.z80:852` | `extension-rewrite` | MON3 terminal/debug display helper. |
| RST 18h | `1Bh` | `sendHLToLCD` | `DBFE` | `glcd_library` | `glcd_library.z80:877` | `extension-rewrite` | MON3 terminal/debug display helper. |
| RST 18h | `1Ch` | `setCursor` | `DC0A` | `glcd_library` | `glcd_library.z80:890` | `extension-rewrite` | Display cursor primitive. |
| RST 18h | `1Dh` | `getCursor` | `DCC0` | `glcd_library` | `glcd_library.z80:1019` | `extension-rewrite` | Display cursor primitive. |
| RST 18h | `1Eh` | `displayCursor` | `DCC5` | `glcd_library` | `glcd_library.z80:1026` | `extension-rewrite` | Display cursor primitive. |
| RST 18h | `1Fh` | `autoLF` | `DCE0` | `glcd_library` | `glcd_library.z80:1054` | `extension-rewrite` | MON3 terminal policy. |
| RST 18h | `20h` | `underline` | `DCD8` | `glcd_library` | `glcd_library.z80:1045` | `extension-rewrite` | MON3 terminal policy. |
| RST 18h | `21h` | `plotAlways` | `DCE5` | `glcd_library` | `glcd_library.z80:1063` | `extension-rewrite` | MON3 terminal policy. |

## RST 10h API

Selector register: `C`. Table symbol: `APITable`.

| Table | Selector | Service | Address | Module | Source | Classification | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| RST 10h | `00h` | `softwareID` | `C68C` | `mon3` | `mon3.z80:1240` | `classic-core` | Stable monitor identity call. |
| RST 10h | `01h` | `versionID` | `C690` | `mon3` | `mon3.z80:1250` | `classic-core` | Stable monitor identity call. |
| RST 10h | `02h` | `preInit` | `C100` | `mon3` | `mon3.z80:301` | `classic-core` | Boot/reset helper used by MON3 itself. |
| RST 10h | `03h` | `beepAlways` | `C511` | `mon3` | `mon3.z80:905` | `bios-keep` | Small audio feedback service. |
| RST 10h | `04h` | `convAToSeg` | `C532` | `mon3` | `mon3.z80:936` | `bios-keep` | Seven-segment conversion utility. |
| RST 10h | `05h` | `regAToASCII` | `C8E2` | `mon3` | `mon3.z80:1733` | `bios-keep` | Hex formatting utility used by monitor and BIOS services. |
| RST 10h | `06h` | `ASCIItoSegment` | `C679` | `mon3` | `mon3.z80:1219` | `bios-keep` | LCD/seven-segment display utility. |
| RST 10h | `07h` | `stringCompare` | `C897` | `mon3` | `mon3.z80:1635` | `bios-keep` | Small utility routine. |
| RST 10h | `08h` | `HLToString` | `C8C9` | `mon3` | `mon3.z80:1701` | `bios-keep` | Word-to-ASCII utility. |
| RST 10h | `09h` | `AToString` | `C8CE` | `mon3` | `mon3.z80:1711` | `bios-keep` | Byte-to-ASCII utility. |
| RST 10h | `0Ah` | `scanSegments` | `C56B` | `mon3` | `mon3.z80:986` | `bios-keep` | Seven-segment hardware service. |
| RST 10h | `0Bh` | `displayError` | `CC2E` | `mon3` | `mon3.z80:2174` | `classic-core` | Classic monitor status display. |
| RST 10h | `0Ch` | `LCDBusy` | `C5C9` | `mon3` | `mon3.z80:1083` | `bios-keep` | Character LCD hardware service. |
| RST 10h | `0Dh` | `stringToLCD` | `C583` | `mon3` | `mon3.z80:1007` | `bios-keep` | Character LCD output service. |
| RST 10h | `0Eh` | `charToLCD` | `C598` | `mon3` | `mon3.z80:1032` | `bios-keep` | Character LCD output service. |
| RST 10h | `0Fh` | `commandToLCD` | `C59C` | `mon3` | `mon3.z80:1040` | `bios-keep` | Character LCD command service. |
| RST 10h | `10h` | `scanKeys` | `C5D1` | `mon3` | `mon3.z80:1097` | `bios-keep` | Hex keypad service. |
| RST 10h | `11h` | `scanKeysWait` | `C656` | `mon3` | `mon3.z80:1191` | `bios-keep` | Hex keypad wait service. |
| RST 10h | `12h` | `matrixScan` | `CC40` | `mon3` | `mon3.z80:2191` | `bios-keep` | Matrix keyboard raw scan service. |
| RST 10h | `13h` | `joystickScan` | `CC6F` | `mon3` | `mon3.z80:2242` | `bios-keep` | Hardware input service. |
| RST 10h | `14h` | `serialEnable` | `CE23` | `mon3` | `mon3.z80:2544` | `bios-keep` | Bit-bang serial setup service. |
| RST 10h | `15h` | `serialDisable` | `CE2C` | `mon3` | `mon3.z80:2554` | `bios-keep` | Bit-bang serial setup service. |
| RST 10h | `16h` | `txByte` | `C6A8` | `mon3` | `mon3.z80:1273` | `bios-keep` | Bit-bang serial transmit service. |
| RST 10h | `17h` | `rxByte` | `C6D9` | `mon3` | `mon3.z80:1311` | `bios-keep` | Bit-bang serial receive service. |
| RST 10h | `18h` | `intelHexLoad` | `C710` | `mon3` | `mon3.z80:1365` | `candidate-remove` | Legacy transfer workflow; SD and project flows should replace normal use. |
| RST 10h | `19h` | `sendToSerialAPI` | `C78C` | `mon3` | `mon3.z80:1465` | `bios-keep` | Serial byte/range export service; monitor UI may be shaved later. |
| RST 10h | `1Ah` | `receiveFromSerialAPI` | `C79E` | `mon3` | `mon3.z80:1482` | `bios-keep` | Serial receive service; monitor UI may be shaved later. |
| RST 10h | `1Bh` | `sendAssemblyAPI` | `C821` | `mon3` | `mon3.z80:1543` | `candidate-remove` | Monitor export workflow rather than core BIOS service. |
| RST 10h | `1Ch` | `sendHexAPI` | `C86F` | `mon3` | `mon3.z80:1598` | `candidate-remove` | Monitor export workflow rather than core BIOS service. |
| RST 10h | `1Dh` | `genDataDump` | `C8F6` | `mon3` | `mon3.z80:1758` | `classic-core` | Classic memory inspection formatter. |
| RST 10h | `1Eh` | `checkStartEnd` | `C90D` | `mon3` | `mon3.z80:1784` | `bios-keep` | Small range utility shared by monitor tools. |
| RST 10h | `1Fh` | `menuDriver` | `CFB0` | `mon3` | `mon3.z80:2849` | `optional-relocate` | Useful MON3 UI framework, but bulky for fixed BIOS. |
| RST 10h | `20h` | `paramDriver` | `CFBD` | `mon3` | `mon3.z80:2874` | `optional-relocate` | Useful MON3 UI framework, but bulky for fixed BIOS. |
| RST 10h | `21h` | `timeDelay` | `C703` | `mon3` | `mon3.z80:1344` | `bios-keep` | Timing utility. |
| RST 10h | `22h` | `playNote` | `EFA7` | `sound` | `sound.z80:85` | `bios-keep` | Sound service. |
| RST 10h | `23h` | `playTune` | `EF75` | `sound` | `sound.z80:45` | `bios-keep` | Sound service. |
| RST 10h | `24h` | `playTuneMenu` | `EF6B` | `sound` | `sound.z80:41` | `optional-relocate` | Interactive sound menu is optional. |
| RST 10h | `25h` | `getCaps` | `CFCA` | `mon3` | `mon3.z80:2884` | `bios-keep` | System state service. |
| RST 10h | `26h` | `getShadow` | `CFD2` | `mon3` | `mon3.z80:2898` | `bios-keep` | System state service. |
| RST 10h | `27h` | `getProtect` | `CFDA` | `mon3` | `mon3.z80:2907` | `bios-keep` | System state service. |
| RST 10h | `28h` | `getExpand` | `CFDE` | `mon3` | `mon3.z80:2914` | `bios-keep` | System state service. |
| RST 10h | `29h` | `setCaps` | `CFE4` | `mon3` | `mon3.z80:2922` | `bios-keep` | System state service. |
| RST 10h | `2Ah` | `setShadow` | `D003` | `mon3` | `mon3.z80:2949` | `bios-keep` | System state service. |
| RST 10h | `2Bh` | `setProtect` | `D00F` | `mon3` | `mon3.z80:2961` | `bios-keep` | System state service. |
| RST 10h | `2Ch` | `setExpand` | `D01D` | `mon3` | `mon3.z80:2973` | `bios-keep` | System state service. |
| RST 10h | `2Dh` | `stringToSerial` | `C58C` | `mon3` | `mon3.z80:1019` | `bios-keep` | Serial string output service. |
| RST 10h | `2Eh` | `RTCAPI` | `FA78` | `rtc` | `rtc.z80:15` | `optional-relocate` | Keep compact RTC services; consider moving interactive RTC setup/viewer. |
| RST 10h | `2Fh` | `menuPop` | `CF06` | `mon3` | `mon3.z80:2716` | `optional-relocate` | Menu framework helper. |
| RST 10h | `30h` | `toggleCaps` | `D02B` | `mon3` | `mon3.z80:2985` | `bios-keep` | System state service. |
| RST 10h | `31h` | `random` | `D0A5` | `mon3` | `mon3.z80:3085` | `bios-keep` | Small utility service. |
| RST 10h | `32h` | `setDisStart` | `D0B7` | `mon3` | `mon3.z80:3102` | `classic-core` | Disassembler is classic MON3 core for now. |
| RST 10h | `33h` | `getDisNext` | `D0BB` | `mon3` | `mon3.z80:3110` | `classic-core` | Disassembler is classic MON3 core for now. |
| RST 10h | `34h` | `getDisassembly` | `D0BF` | `mon3` | `mon3.z80:3118` | `classic-core` | Disassembler is classic MON3 core for now. |
| RST 10h | `35h` | `matrixScanASCII` | `D0CB` | `mon3` | `mon3.z80:3132` | `bios-keep` | Matrix keyboard ASCII service. |
| RST 10h | `36h` | `parseMatrixScan` | `D142` | `mon3` | `mon3.z80:3216` | `bios-keep` | Matrix keyboard parsing service. |
| RST 10h | `37h` | `LCDConfirm` | `CE32` | `mon3` | `mon3.z80:2563` | `optional-relocate` | Interactive LCD confirmation helper. |
| RST 10h | `38h` | `getGLCDTerm` | `CFCE` | `mon3` | `mon3.z80:2891` | `extension-rewrite` | GLCD terminal state should be replaced by TECM8 display policy. |
| RST 10h | `39h` | `setGLCDTerm` | `CFF8` | `mon3` | `mon3.z80:2939` | `extension-rewrite` | GLCD terminal state should be replaced by TECM8 display policy. |
| RST 10h | `3Ah` | `loadFromDisk` | `F022` | `pata_fat32` | `pata_fat32.z80:79` | `candidate-remove` | Storage user workflow; keep lower SD/file sector services. |
| RST 10h | `3Bh` | `openFile` | `F5A1` | `pata_fat32` | `pata_fat32.z80:1001` | `bios-keep` | SD-backed FAT32 file open service for TECM8 storage wrappers. |
| RST 10h | `3Ch` | `readSector` | `F5D5` | `pata_fat32` | `pata_fat32.z80:1055` | `bios-keep` | SD-backed FAT32 sector read service for TECM8 storage wrappers. |
| RST 10h | `3Dh` | `writeSector` | `F66D` | `pata_fat32` | `pata_fat32.z80:1163` | `bios-keep` | SD-backed FAT32 sector write service for TECM8 storage wrappers. |
| RST 10h | `3Eh` | `RGBScan` | `D2D0` | `mon3` | `mon3.z80:3399` | `bios-keep` | RGB LED matrix hardware service. |

## Classification Keys

- `classic-core`: keep as part of recognisable MON3 behaviour.
- `bios-keep`: keep as a compact resident hardware or utility service.
- `extension-rewrite`: preserve the capability, but expect TECM8 to replace or wrap the MON3 implementation.
- `optional-relocate`: useful, but a candidate for banked ROM, disk, or optional tools.
- `candidate-remove`: likely removable from a TECM8-focused profile after compatibility review.
- `unknown`: not yet classified.

