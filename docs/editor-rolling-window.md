# Editor Rolling Source Window

This document defines the next source-navigation design for the TECM8 editor.
The current editor treats each 512-byte source sector as a page and uses
explicit page movement to switch between sectors. That was useful while proving
storage, save, restore, and cross-sector edits, but it is not the right user
model. A source file should feel like one continuous document.

The next implementation should allocate a 2K source window:

```text
4 sectors x 512 bytes = 2048 bytes
16 source records per sector = 64 source lines
```

This 2K window is a rolling sector cache. The editor still reads and writes
TM8 source files at sector granularity, but the user moves by document lines.

## Goals

- Plain Up/Down should cross source-sector boundaries when the target line is
  resident in the 2K window.
- `Ctrl-Up` and `Ctrl-Down` remain faster movement commands, but they operate
  on the same continuous document model rather than switching between apparent
  documents.
- Moving inside the resident 64-line window should not perform SD reads.
- Moving outside the window should load or evict one 512-byte sector, not throw
  away and reload all 2K.
- Edits remain explicit-save by default. Navigation must not silently commit
  dirty source sectors to disk.
- Backup/restore should work at source-sector granularity.

## Source Coordinates

The editor should track cursor position as an absolute document line and
logical column.

```text
absoluteLine = 0..N
absolutePage = absoluteLine / 16
lineInPage   = absoluteLine % 16
recordOffset = lineInPage * 32
```

The display viewport then maps absolute lines to visible rows. The physical
GLCD screen is not the source model; it is only a renderer over the source
window.

V1 may keep the existing one-byte source page API limit while it is being
rewired:

```text
page number range = 0..127
maximum source span = 128 sectors = 64K = 2048 source lines
```

That is a practical limit for the current editor, but it should be named rather
than hidden. Use one byte for `slotPage` and backed-page entries in V1. Keep the
absolute line as a 16-bit value so later storage code can lift the page limit
without changing the editor's public coordinate model.

## Window Slots

The 2K source window is four independent 512-byte slots:

```text
slot 0  512 bytes
slot 1  512 bytes
slot 2  512 bytes
slot 3  512 bytes
```

Each slot needs small metadata:

```text
slotPage      source sector/page number in this slot
valid         slot contains meaningful data
dirty         slot has edits not yet written to source file
synthetic     slot represents blank content beyond current EOF
```

For the four loaded slots, bit masks are appropriate:

```text
validMask      4 bits
dirtyMask      4 bits
syntheticMask  4 bits
```

These masks are window-local. They do not limit file size because each slot also
stores its absolute source page number. V1 is still limited by the current
one-byte page-indexed storage API, not by these masks.

## Rolling Policy

The window should represent four contiguous source pages:

```text
windowBasePage = N
slot 0 = page N
slot 1 = page N+1
slot 2 = page N+2
slot 3 = page N+3
```

The slot layout can be implemented as a physical ring buffer, but the logical
invariant remains contiguous. Do not let the cache become four arbitrary recent
pages; that would make line movement and redraw policy harder to reason about.

When the cursor needs a source page, the editor first checks whether that page
is inside `windowBasePage..windowBasePage+3` and whether the matching logical
slot is valid.

If the page is resident:

```text
use the matching slot
no storage operation
```

If the page is not resident:

```text
scrolling down past windowBasePage+3:
  the natural victim is windowBasePage
  if clean, evict it, increment windowBasePage, and load the new high page
  if dirty, block movement and request an explicit save

scrolling up before windowBasePage:
  the natural victim is windowBasePage+3
  if clean, evict it, decrement windowBasePage, and load the new low page
  if dirty, block movement and request an explicit save
```

Do not evict a different clean slot just because the natural rolling victim is
dirty. That would break the contiguous 64-line window invariant.

The first implementation should not autosave dirty sectors on eviction. A
dirty-eviction write would change the editor from explicit-save semantics to a
partial autosave model. That needs a separate product decision.

Recommended first policy:

```text
clean eviction: allowed
dirty eviction: blocked with SAVE/DIRTY status
Ctrl-S: writes dirty resident sectors, then movement can be retried
```

This keeps the mental model simple:

```text
Nothing reaches the source file until the user explicitly saves.
```

## Initial Fill

On open, the editor should fill the window around the beginning of the file:

```text
slots contain source pages 0, 1, 2, 3 where available
short/missing pages are synthetic blank sectors
cursor starts at absolute line 0
viewport starts at absolute line 0
```

This startup still performs several slow storage operations. A later
optimization should cache file metadata so page loads do not repeat the whole
TM8 prefix/catalog/superblock lookup. The first rolling-window milestone can
still use existing loader calls if that keeps the behavioral change contained.

## EOF And Synthetic Pages

Synthetic pages are a growth mechanism, not ordinary navigable document
content. A synthetic blank page beyond EOF may be resident so Enter/split/growth
logic can use it, but plain Down must not move into that page merely because it
is cached.

V1 should track the current source byte size or effective last source line well
enough to answer:

```text
is absoluteLine inside the existing file?
is absoluteLine the first legal growth line created by an edit?
```

Navigation rule:

```text
plain Up/Down may cross between existing resident source lines
plain Down at EOF stops unless an edit has created/grown the next line
Ctrl-Down should not jump into clean synthetic blank territory
```

Once an edit creates content in a synthetic page, that page becomes dirty source
state and is no longer just a blank EOF placeholder.

## Backup Policy

Backup is sector-based.

Before the first save of a dirty source sector in an editor session, the editor
must preserve the old on-disk sector in the hidden backup file. Then it may
write the dirty RAM sector to the source file.

Repeated saves of the same source sector in the same session should not replace
the original backup with a later edited version. The backup represents the
pre-session source content for that sector.

The backup file should use the same page numbers as the source file:

```text
source page N backs up to backup page N
```

For newly created pages beyond old EOF, restore can treat missing old content as
blank. The simpler implementation is to grow the backup file enough that page N
can always be read, writing blank sectors for pages that had no previous source
content.

## Backed-Page Tracking

Avoid a global file-size bitset. A global bitset creates an artificial maximum
file length:

```text
8-bit mask   = 8 sectors  = 4K  = 128 lines
16-bit mask  = 16 sectors = 8K  = 256 lines
32-bit mask  = 32 sectors = 16K = 512 lines
```

Instead, use a small session table of pages already backed up:

```text
BackedPageCount
BackedPageTable[16 or 32]
```

This limits the number of distinct sectors that can be edited and saved in one
session, not the total file size.

For example, a 32-entry table allows 32 distinct backed sectors:

```text
32 sectors = 16K source = 512 lines touched in one session
```

A much larger file can still be opened if the session only edits a small number
of sectors.

If the table fills, the editor should refuse further saves with a compact error
such as:

```text
BACK FULL
```

That failure is explicit and safer than silently losing restore information.

## Ctrl-Z Restore

`Ctrl-Z` should restore backed-up sectors for the currently resident window in
the first implementation. That gives the user a practical escape hatch for the
area they are editing.

The backed-page table is authoritative. Restore should only touch a resident
slot when that slot's `slotPage` appears in `BackedPageTable`. Resident sectors
that have not been backed up in this session must be skipped. Clean synthetic
pages with no backed-page entry should remain blank; dirty synthetic pages that
were created during the session need an explicit policy before broader restore
is implemented, so V1 should avoid treating them as restorable unless their page
has been entered in `BackedPageTable`.

Later, restore can grow into a broader session restore that walks the backed
page table and restores every backed page, but that is not required for the
first rolling-window milestone.

## Storage Optimization Follow-Up

The rolling window reduces the number of source-sector loads during navigation,
but each miss may still be expensive because the current loader rediscovers the
TM8 file each time. A follow-up storage optimization should cache:

```text
source path
prefix id
catalog entry location
file byte size
first allocation block
recent allocation-chain position
```

Then loading page N can become closer to a direct source-sector read instead of
open, superblock validation, prefix scan, catalog scan, block-chain walk, and
data read every time.

## Milestone

The first milestone is **Rolling Source Window V1**.

Manual Debug80 acceptance:

- Open the editor on the standard `/src/main.asm` fixture.
- Use plain Down to move from `R0 LINE 14` or `R0 LINE 15` into `R1 LINE 00`
  without pressing `Ctrl-Down`.
- Use plain Up to move back from `R1 LINE 00` into the previous `R0` line.
- Confirm `Ctrl-Up` and `Ctrl-Down` still move faster but do not feel like
  switching between separate documents.
- Edit lines in more than one resident sector, save, reset, and confirm the
  saved content survives.
- Attempt to move far enough that a dirty sector would be evicted; V1 should
  block with a save/dirty status instead of silently writing to disk.

Automated acceptance:

- A Debug80 proof covers plain Down crossing from source page 0 to source page
  1 when both are resident.
- A proof covers plain Up crossing from page 1 back to page 0.
- A proof covers dirty eviction being blocked before explicit save.
- Existing save, restore, row-15 growth, allocation growth, block editing, and
  live-smoke checks remain green.
