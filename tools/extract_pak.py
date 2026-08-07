#!/usr/bin/env python3
"""Extractor for 10tons' PAK V11 archives (Crimsonland 2014).

Format (little-endian):
    0x00  8 bytes   magic: "PAK\\0V11\\0"
    0x08  u32       directory offset (from start of file)
    0x0C  u32       total file size
    ...   raw file data, concatenated
    dir   u16       entry count
          per entry: NUL-terminated path (forward slashes),
                     u32 data offset, u32 data size, 8 bytes extra
                     (observed constant ff26e25020000000 - likely hash+flags)

Usage: extract_pak.py <file.pak> <output_dir>
"""
import os
import struct
import sys


def extract(pak_path: str, out_dir: str) -> None:
    with open(pak_path, "rb") as f:
        data = f.read()

    if data[:8] != b"PAK\x00V11\x00":
        sys.exit(f"{pak_path}: not a PAK V11 archive")

    dir_start = struct.unpack_from("<I", data, 8)[0]
    count = struct.unpack_from("<H", data, dir_start)[0]
    pos = dir_start + 2

    extracted = 0
    for _ in range(count):
        end = data.index(b"\0", pos)
        name = data[pos:end].decode("utf-8", "replace")
        pos = end + 1
        offset, size = struct.unpack_from("<II", data, pos)
        pos += 16  # offset, size, 8-byte extra (hash/flags)

        if not name:
            continue
        dest = os.path.join(out_dir, name)
        if size == 0:  # directory entry
            os.makedirs(dest, exist_ok=True)
            continue
        os.makedirs(os.path.dirname(dest) or ".", exist_ok=True)
        with open(dest, "wb") as f:
            f.write(data[offset : offset + size])
        extracted += 1

    print(f"{pak_path}: extracted {extracted} files ({count} entries)")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    extract(sys.argv[1], sys.argv[2])
