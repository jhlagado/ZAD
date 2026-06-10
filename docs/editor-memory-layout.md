# Editor Memory Layout

This document records the current Debug80/TEC-1G editor RAM layout. The goal is
to keep editor buffers away from MON3 and GLCD volatile RAM while the program
itself is still launched by MON3 at `4000h`.

## Assumptions

- MON3 has initialized the machine before TECM8 starts.
- TECM8 is launched at `4000h`.
- MON3 storage uses `DISK_BUFF` at `0600h`.
- MON3 GLCD code uses low RAM around the graphics and terminal buffers,
  including the active `TGBUF` area at `13C0h`.
- The area below `3000h` is treated as MON3/display/storage-owned for now.
- `3000h-3FFFh` is the current editor workspace candidate below the `4000h`
  launch address.

## Current Fixed Workspace

The editor now reserves `3000h-37FFh` for source-sector buffers:

```text
3000h-31FFh  EditorNavCachePageBuffer   previous-page cache
3200h-33FFh  EditorNavPageBuffer        active source sector
3400h-35FFh  EditorNavNextPageBuffer    adjacent next-sector window
3600h-37FFh  EditorNavBackupPageBuffer  backup/save scratch sector
3800h-3FFFh  reserved for future editor workspace
4000h-....h  TECM8 code and ordinary assembled state
```

This gives the current editor a 2K fixed source-sector workspace: three
resident edit/navigation sectors plus one scratch sector for backup creation and
restore. It is still smaller than the preferred future 2K or 4K navigation
window, but it removes accidental dependence on assembled data placement.

## Policy

The editor should not allocate source-page buffers in the program image unless
there is a deliberate reason. Buffers used by storage, navigation, backup, and
future display diffing should have named addresses or a named allocator.

The `3000h-3FFFh` range is the first editor workspace. It should remain
independent of MON3's low volatile storage and GLCD buffers. New low-RAM use
must be documented here before it is relied on by code.

If later work needs more resident source text, prefer expanding toward a 4K
window inside this workspace before adding more SD reads to ordinary page
movement. If display buffers or hardware tests show that part of this range is
unsafe, the workspace must be moved as a unit rather than leaving mixed fixed
and assembled buffers.
