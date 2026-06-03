# Virtual Filesystem

## Rationale

MON3's FAT32 layer can mount a card, list root files, open an existing file, read
sectors, and write a sector that has already been read. It does not appear to
provide a complete DOS-style API for creating files, extending files, deleting
files, writing long filenames, or managing subdirectories.

TECM8 therefore uses FAT32 as a transport layer and stores its own filesystem
inside a single pre-existing FAT32 file.

Host-visible file:

```text
VOLUME.TM8
```

TECM8 treats that file as a private project volume. A FAT32 card can contain
multiple TM8 volumes, but the TEC-1G normally works inside one active volume
at a time.

Default v1 volume sizing:

```text
volume size:      4MB
block size:       4K
file entries:     256
prefix entries:   128
catalog size:     32K
```

## Outer Layer

The outer FAT32 layer only needs these operations:

- Open `VOLUME.TM8`.
- Read sector at byte offset.
- Write sector at byte offset.

This avoids implementing FAT32 long filenames, directory creation, cluster
allocation, truncation, and deletion on the Z80.

## Internal Layout

Version 1 layout:

```text
block 0      superblock
block 1      allocation table
blocks 2-5   prefix table
blocks 6-9   file catalog
block 10..n  file data blocks
```

Initial constants:

```text
sector size:           512 bytes
allocation block size: 4096 bytes
sectors per block:     8
default volume size:   4MB
file entries:          256
prefix entries:        128
```

The 4K block size maps well to editor source pages:

```text
32-byte line record
512-byte sector = 16 lines
4K block        = 128 lines
```

## Superblock

The superblock identifies the disk and describes the layout:

```text
magic/version
total blocks
block size
allocation table start block
allocation table block count
catalog start block
catalog block count
free block count
reserved fields
checksum
```

The format is kept simple enough for both Z80 code and host tools to parse.
See [Workspace Disk Format](workspace-disk-format.md) for exact byte offsets.

## Allocation Table

The allocation table records file block chains.

Simple representation:

```text
0x0000 = free block
0xffff = end of file
other  = next block number
```

Example:

```text
file first block = 20

block 20 -> 21
block 21 -> 35
block 35 -> END
```

Blocks do not need to be adjacent. Fragmentation is accepted initially.

## Prefix Table And File Catalog

The catalog is flat. There are no real directories. To avoid repeating long
path prefixes in every file entry, TECM8 stores prefixes separately from local
file names.

Example logical paths:

```text
/projects/tecm8/editor.asm
/projects/tecm8/storage.asm
/lib/glcd/terminal.asm
```

These are represented internally as:

```text
prefix id 3 = projects/tecm8
  editor.asm
  storage.asm

prefix id 9 = lib/glcd
  terminal.asm
```

The leading slash and the slash between prefix and file name are implied, not
stored. Prefix strings also do not store a trailing slash.

When displaying a full path:

```text
full path = "/" + prefix + "/" + local filename
```

For a file at the project root, the prefix can be the empty prefix.

## Prefix Table

Version 1 prefix table entries store:

```text
status/type
prefix id
prefix length
prefix string
reserved metadata
```

Working limits:

```text
prefix entries:      128
prefix id:           1 byte
prefix entry size:   128 bytes
max prefix length:   about 120 bytes
```

Prefix strings are lowercase ASCII and omit leading/trailing slashes:

```text
projects/tecm8/src/editor
lib/glcd
build
```

The future TEC-side shell location is a current prefix string. `cd` may move to
a syntactically valid prefix that is not yet present in the prefix table. The
prefix entry is only needed when the first file is created there.

If a user creates a file under a prefix that is not in the prefix table and all
128 prefix entries are already used, file creation fails with a prefix-table
full error.

## File Catalog

Version 1 file catalog entries store:

```text
status/type
file id
prefix id
name length
local filename
first block
file size in bytes
file format/type
reserved metadata
```

Working limits:

```text
file entries:      256
file id:           1 byte
file entry size:   64 bytes
max local name:    about 40 bytes
```

The prefix table and file catalog together occupy 32K:

```text
128 prefixes * 128 bytes = 16K
256 files    * 64 bytes  = 16K
total                    = 32K
```

Local filenames are lowercase ASCII and do not contain slashes:

```text
editor.asm
glcd-terminal.asm
main.map
```

User input can be accepted case-insensitively and normalized before lookup.

Allowed v1 path characters:

```text
a-z 0-9 _ - . /
```

## Virtual Directories

There are no directory objects. The system has a current prefix, not a current
directory.

`cd` changes the current prefix and always succeeds if the path is syntactically
valid:

```text
cd /projects/newthing
```

No `mkdir` command is required. A virtual folder becomes visible when at least
one file exists under its prefix.

Listing `/projects/` scans prefix and file entries and groups entries by the
next path component. Prefixes are still flat records, not linked parent/child
directory objects.

## File Creation

To create a file:

1. Normalize the path.
2. Check that no exact path already exists.
3. Split the normalized path into prefix and local filename.
4. Find or create the prefix entry.
5. Find a free file catalog entry.
6. Allocate one or more 4K blocks.
7. Link the blocks in the allocation table.
8. Write the file catalog entry.
9. Initialize file data.

The host-side `fs new` implementation creates a zero-length file and
allocates one initialized 4K block immediately. `fs import` reuses the same
catalog and allocation model for raw host bytes, allocating enough 4K blocks
for the imported content.

## Deletion

Deletion can reclaim blocks immediately:

1. Mark the catalog entry free/deleted.
2. Walk the file's block chain.
3. Mark each block free in the allocation table.
4. If no remaining file references the file's prefix, mark that prefix entry
   free as well.

Future work can add `fsck`, compaction, and defragmentation, but they are not
required for the first editor.

## Rename And Move

Use Unix command names.

`mv` rewrites a path in the catalog:

```text
mv /projects/tecm8/editor.asm /projects/tecm8/edit.asm
```

No file data moves. If the destination path uses a different prefix, `mv` may
create the destination prefix entry, update the file entry's prefix id and local
name, then reclaim the old prefix if it is no longer used.

A virtual folder move is a prefix rewrite over matching prefix entries and file
entries. That can be added later.

## Project Volumes And Imports

A TM8 volume represents a project workspace. It is not intended to be a
general-purpose whole-card filesystem.

The intended workflow is static copying:

```text
fs copy LIBS.TM8:/lib/glcd/terminal.asm VOLUME.TM8:/lib/glcd/terminal.asm
```

This copies a file from another TM8 volume into the active project. After the
copy, there is no live dependency relationship. This is deliberately closer to
copying a source file into an 8-bit project than to modern package management or
dynamic linking.

Opening two volumes at once may be useful for copy operations, but the system
does not need to keep multiple volumes live during normal editing or building.

## Host Preservation Tools

Because `VOLUME.TM8` is opaque to a laptop, host tools are required for long-term
preservation.

Host commands:

```text
fs import VOLUME.TM8 ./main.asm /projects/demo/main.asm
fs export VOLUME.TM8 /projects/demo/main.asm ./main.asm
fs copy LIBS.TM8:/lib/glcd/terminal.asm VOLUME.TM8:/lib/glcd/terminal.asm
fs unpack VOLUME.TM8 ./workspace
fs pack ./workspace VOLUME.TM8
```

`fs import` is implemented as raw byte import. `export`, cross-volume `copy`,
`unpack`, and `pack` are still Phase 2 work.
