# Workspace Disk Format

`VOLUME.TM8` is a fixed-size TECM8 project volume stored inside a host-visible
FAT32 file. Version 1 is deliberately small and byte-stable so the same image
can be produced and checked by host tools before Z80 filesystem code exists.

## Version 1 Defaults

```text
volume size:       4 MiB
sector size:       512 bytes
block size:        4096 bytes
total blocks:      1024
file entries:      256
prefix entries:    128
```

## Block Layout

```text
block 0      superblock
block 1      allocation table
blocks 2-5   prefix table
blocks 6-9   file catalog
blocks 10-n  file data
```

The allocation table has one 16-bit little-endian entry per 4K block:

```text
0x0000 = free block
0xffff = reserved block or end-of-file marker
other  = next block number in a file chain
```

After formatting, blocks 0-9 are marked `0xffff`; blocks 10-1023 are `0x0000`.
The remaining 2048 bytes in the 4K allocation table block are reserved and
zero-filled.

## Superblock

The superblock occupies block 0. Version 1 stores the defined fields in the
first 512 bytes and leaves the rest of the 4K block zero-filled.

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

## Prefix Table

The prefix table occupies blocks 2-5. It contains 128 entries of 128 bytes.
Formatted entries are zero-filled and therefore inactive. These are the version
1 entry fields.

```text
offset  size  field
0       1     status/type, 0 means free
1       1     prefix id
2       1     prefix string length
3       121   lowercase ASCII prefix string without leading/trailing slash
124     4     reserved
```

Valid version 1 prefix status values:

```text
0x00 = free/inactive entry; all remaining entry bytes must be zero
0x01 = active prefix entry
```

Prefix id `0` is reserved for the implicit root prefix and is not stored as an
active prefix-table entry. Active prefix strings must be unique.

## File Catalog

The file catalog occupies blocks 6-9. It contains 256 entries of 64 bytes.
Formatted entries are zero-filled and therefore inactive. These are the version
1 entry fields.

```text
offset  size  field
0       1     status/type, 0 means free
1       1     file id
2       1     prefix id
3       1     local filename length
4       40    lowercase ASCII local filename
44      2     first block, uint16le
46      4     file size in bytes, uint32le
50      1     file format/type
51      13    reserved
```

Valid version 1 file status values:

```text
0x00 = free/inactive entry; all remaining entry bytes must be zero
0x01 = active file entry
```

File entries with prefix id `0` are in the root prefix. Other prefix ids must
refer to active prefix-table entries. File ids are byte-sized values and may use
the full `0x00`-`0xff` range because entry activity is controlled by the status
byte.

For active file entries, `first block` must refer to a data block whose
allocation-table entry is not free. Block chains must end with `0xffff`, must
not cycle, must not share blocks with another active file, and must provide
enough block capacity for the stored file size.

## Host Commands

The first host-verifiable commands are:

```text
node --experimental-strip-types tools/tm8fs.ts format VOLUME.TM8
node --experimental-strip-types tools/tm8fs.ts info VOLUME.TM8
node --experimental-strip-types tools/tm8fs.ts import VOLUME.TM8 hostfile /path/file
node --experimental-strip-types tools/tm8fs.ts new VOLUME.TM8 /path/file
node --experimental-strip-types tools/tm8fs.ts rm VOLUME.TM8 /path/file
node --experimental-strip-types tools/tm8fs.ts mv VOLUME.TM8 /old/path /new/path
node --experimental-strip-types tools/tm8fs.ts ls VOLUME.TM8 /
node --experimental-strip-types tools/tm8fs.ts cat VOLUME.TM8 /path/file
```

`format` refuses to overwrite an existing file. `info` verifies the superblock,
checksum, allocation table, prefix table entries, file catalog entries, and
active file block chains, then reports the volume layout as JSON. `new` creates
the needed prefix entry if it
does not exist, allocates one 4K data block, initializes that block to zero,
stores a zero-length file catalog entry, and updates the allocation table and
free-block count. `import` reads exact bytes from a host file, creates the
destination TM8 file, allocates enough 4K data blocks with at least one block
even for a zero-length file, stores the exact byte count, zero-fills final-block
padding, and updates the allocation table, free-block count, and checksum. `rm`
resolves an existing file path, frees every block in its validated allocation
chain, zeroes the file catalog entry, updates the free-block count and checksum,
and removes the prefix entry when no remaining file references it. `mv` resolves
an existing source file, rejects destination collisions, rewrites the catalog
entry's prefix and local filename, creates or reuses the destination prefix,
reclaims the source prefix when emptied, and preserves the file's data block
chain and metadata. `ls` parses the prefix table and file catalog and prints
matching local filenames, one per line. A freshly formatted volume lists `/`
successfully with no output. `cat` resolves a file path, walks the validated
allocation block chain, and writes exactly the file's stored byte count to
stdout.

The host `tm8fs` command set is stateless. It does not implement `cd` or `pwd`;
host commands use absolute TM8 paths so tests and preservation tools do not
depend on ambient shell state. `cd` and `pwd` belong to the interactive GLCD
shell, where a current prefix can live in shell state without changing the
version 1 disk format.
