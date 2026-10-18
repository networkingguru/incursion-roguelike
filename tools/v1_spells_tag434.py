#!/usr/bin/env python3
"""Independent reader for the pre-inc-vqla spell-flag array in a v1 save.

    tools/v1_spells_tag434.py <save>

A v1 save is a fileHeader followed by one zlib stream. This script finds the
stream (the first 0x78 0x9c bytes), decompresses it with zlib.decompressobj,
and locates the retired tag-434 array the old build wrote:

    b2 01            tag 434 as u16 little-endian
    0b               kind K_ARRAY (11), one byte
    count 2049       u32 little-endian
    element size 2   u32 little-endian
    then 4098 bytes  uint16 little-endian element values

The array must occur exactly once. For each non-zero element it prints

    <idx> <raw>

with raw as 0x%08X, one line per non-zero element.

Exit codes: 0 on success (including "found zero non-zero elements"),
2 when the pattern is not found exactly once or the file cannot be read.
"""

import sys
import zlib


def main(argv):
    if len(argv) != 2:
        sys.stderr.write("usage: v1_spells_tag434.py <save>\n")
        return 2
    path = argv[1]
    try:
        data = open(path, "rb").read()
    except OSError as exc:
        sys.stderr.write("v1_spells_tag434.py: cannot read %s: %s\n" % (path, exc))
        return 2

    off = data.find(b"\x78\x9c")
    if off < 0:
        sys.stderr.write("v1_spells_tag434.py: no zlib stream in %s\n" % path)
        return 2
    try:
        raw = zlib.decompressobj().decompress(data[off:])
    except zlib.error as exc:
        sys.stderr.write("v1_spells_tag434.py: decompression failed: %s\n" % exc)
        return 2

    pat = b"\xb2\x01" + bytes([11]) + (2049).to_bytes(4, "little") \
        + (2).to_bytes(4, "little")
    if raw.count(pat) != 1:
        sys.stderr.write(
            "v1_spells_tag434.py: tag-434 array header occurs %d times, "
            "expected exactly 1\n" % raw.count(pat))
        return 2
    body = raw.index(pat) + len(pat)

    for i in range(2049):
        v = int.from_bytes(raw[body + 2 * i: body + 2 * i + 2], "little")
        if v:
            print("%d 0x%08X" % (i, v))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
