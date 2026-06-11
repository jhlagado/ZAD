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

## Deferred Serial Archive Transfer

TECM8 will eventually need a simple way to move projects between machines over
serial links. The useful distinction is between the archive format and the wire
encoding:

```text
project files
-> archive stream
-> text-safe transfer encoding
-> serial
```

Existing standards are useful references. `uuencode`/`uudecode` and `shar`
represent the old Unix mail/news era: binary or multi-file content was converted
into line-oriented ASCII so it could survive simple transports. MIME multipart
with Base64 became the later email attachment standard. Intel HEX and Motorola
S-record are also line-oriented and checksummed, but they are address-oriented
rather than file-tree-oriented.

For TECM8, a literal Unix tarball is probably too broad as the native TEC-side
format because it brings POSIX permissions, uid/gid fields, timestamps, links,
padding rules, and dialect questions. A tar-like sequential archive is still the
right idea: it preserves paths and streams naturally over serial.

Preferred direction:

```text
TECM8-native archive stream
Base64, Intel HEX, or another line-checksummed ASCII transport
optional host-side import/export to tar or MIME for interoperability
```

A possible human-readable archive envelope:

```text
begin tecm8-archive v1
file /tecm8.prj 42 crc
base64...
end
file /src/main.asm 1234 crc
base64...
end
end tecm8-archive crc
```

This deliberately borrows the good parts of MIME and uuencode: line-oriented
ASCII, file names, lengths, and checksums. It avoids making the Z80 parse full
MIME or full POSIX tar unless a host tool is doing that work. Host tools should
be able to pack/unpack this format, and later may bridge it to `.tar`, MIME
attachments, or whole `VOLUME.TM8` images when that is useful.

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

Version 1 stores defined superblock fields in the first 512 bytes and leaves
the rest of the 4K superblock block zero-filled:

```text
offset  size  field
0       8     magic, ASCII "TECM8VOL"
8       2     format version, uint16le, currently 1
10      2     sector bytes, uint16le
12      2     block bytes, uint16le
14      2     total blocks, uint16le
16      4     volume bytes, uint32le
20      2     allocation table start block, uint16le
22      2     allocation table block count, uint16le
24      2     prefix table start block, uint16le
26      2     prefix table block count, uint16le
28      2     prefix entry size, uint16le
30      2     prefix entry count, uint16le
32      2     catalog start block, uint16le
34      2     catalog block count, uint16le
36      2     catalog entry size, uint16le
38      2     catalog entry count, uint16le
40      2     first data block, uint16le
42      2     free block count, uint16le
44      28    reserved, zero-filled
72      4     superblock checksum, uint32le
76      436   reserved, zero-filled
```

The checksum is the unsigned 32-bit sum of bytes 0-511 with the checksum field
at offset 72 treated as zero.

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

Leading-dot local filenames follow the Unix hidden-file convention. They are
ordinary catalog entries on disk, but ordinary TEC-side `ls`, project export,
and project `pack`/`unpack` workflows hide or omit them by default. Explicit
raw host operations such as `fs cat`, `fs export`, `fs import`, and `fs copy`
can still name hidden files directly.

Hidden files are not only backups. They are reserved for internal or auxiliary
project state as well, so backup files should carry a role suffix instead of
using the hidden source name directly. The editor backup convention is:

```text
/src/main.asm    -> /src/.main.asm.b
/src/driver.inc  -> /src/.driver.inc.b
/tecm8.prj       -> /.tecm8.prj.b
```

The derived backup name is `.` + original local filename + `.b`. The leading dot
makes the backup hidden; the trailing `.b` identifies it as a backup while
preserving the original filename and extension. If the derived local filename
does not fit the catalog name limit, v1 should fail the save with a clear error
rather than truncating or inventing an ambiguous short name.

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
fs import-text VOLUME.TM8 ./main.asm /projects/demo/main.asm
fs export-text VOLUME.TM8 /projects/demo/main.asm ./main.asm
fs copy LIBS.TM8:/lib/glcd/terminal.asm VOLUME.TM8:/lib/glcd/terminal.asm
fs unpack VOLUME.TM8 ./workspace
fs pack ./workspace VOLUME.TM8
fs project-init VOLUME.TM8 /src/main.asm
fs project-info VOLUME.TM8
```

`fs import`, `fs export`, and `fs copy` are implemented as raw byte operations.
`fs unpack` and `fs pack` are project-preservation operations and omit
leading-dot local filenames by default, so editor backups such as
`/src/.main.asm.b` do not clutter an exported workspace or get packed back into
a clean project volume. Explicit raw operations can still name hidden files
directly when recovery or diagnosis needs them. `fs import-text` and
`fs export-text` are implemented as source conversion commands for 32-byte
editor records.

`fs project-init` creates root file `/tecm8.prj`, a line-oriented ASCII config
file for the project main file. TEC-side code can read it without a JSON parser.
Build output and map paths are derived from the main filename by convention. See
[TEC-Side Shell Command Contract](shell-command-contract.md) for the shell-side
command resolution rules.
