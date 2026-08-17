#!/usr/bin/env python3
"""Craft deliberately corrupt .sav files from one genuine, freshly-generated
save, for tools/check_load_corrupt.sh (bd inc-l0t).

WHY A GENUINE SAVE IS THE STARTING POINT. A .sav is a memory image welded to
the exact struct layout of the binary that wrote it (see
docs/ENGINE-SERIALISATION.md) -- the same reason inc-loa.1 refused to write an
external save parser. This script does not parse the save contents either. It
only overwrites four fixed fields in the group header immediately after the
96-byte fileHeader (verified against the real struct layout in
src/Registry.cpp, offsets confirmed in the bd inc-l0t working notes) and, for
two cases, replaces the compressed data that follows it with a hand-built
stream in the RLE format the main save group actually uses
(Registry::LoadGame calls LoadGroup with use_lz=false).

Usage: craft_corrupt_saves.py <genuine.sav> <output-dir>
Writes one file per case into <output-dir> and prints "<name> <path>" for
each, one per line, so the caller doesn't have to hardcode filenames twice.
"""
import struct
import sys
import os

FH_SIZE = 96
GH_SIZE = 28
GH_OFF = FH_SIZE
GROUPSIZE_OFF = GH_OFF + 8
COMPSIZE_OFF = GH_OFF + 12
DATA_OFF = GH_OFF + GH_SIZE
SIGNATURE = 0x1234ABCD


def patch_i32(data: bytes, offset: int, value: int) -> bytes:
    return data[:offset] + struct.pack("<i", value) + data[offset + 4:]


def rle_run(marker: int, count_minus_1: int, symbol: int) -> bytes:
    """One RLE repeat token in the format src/rle.c::RLE_Uncompress decodes:
    marker, count(-hi|0x80, count-lo if >127), symbol. count_minus_1 must be
    <= 32767 (a run of up to 32768 bytes)."""
    assert 3 <= count_minus_1 <= 32767
    hi = (count_minus_1 >> 8) | 0x80
    lo = count_minus_1 & 0xff
    return bytes([marker, hi, lo, symbol])


def build_overflow_stream() -> bytes:
    """33 maximum-length (32768-byte) runs = 1,081,344 output bytes, aimed at
    a 1,048,576-byte (one CFILE_DELTA) allocation. Before inc-l0t this wrote
    32,768 bytes straight past the end of the heap block on run 33."""
    marker = 0x00
    out = bytes([marker])
    for _ in range(33):
        out += rle_run(marker, 32767, 0x41)
    return out


def build_short_stream() -> bytes:
    """51 bytes that legitimately decode to exactly 50 literal bytes -- a
    stream that is honest about its own compressed content but shorter than
    whatever uncompressed_size the header claims."""
    marker = 0x00
    payload = bytes((i % 250) + 1 for i in range(50))  # never 0 (the marker)
    return bytes([marker]) + payload


def main():
    if len(sys.argv) != 3:
        print("usage: craft_corrupt_saves.py <genuine.sav> <output-dir>", file=sys.stderr)
        return 2
    src_path, out_dir = sys.argv[1], sys.argv[2]
    os.makedirs(out_dir, exist_ok=True)

    base = open(src_path, "rb").read()

    sig, = struct.unpack_from("<I", base, 0)
    if sig != SIGNATURE:
        print("fileHeader.Sig mismatch: 0x%08X != 0x%08X -- struct layout drifted, "
              "recheck FH_SIZE/GH_SIZE/offsets" % (sig, SIGNATURE), file=sys.stderr)
        return 2
    num_groups, = struct.unpack_from("<h", base, 88)
    if num_groups != 1:
        print("expected exactly 1 group in a freshly-generated save, got %d" % num_groups,
              file=sys.stderr)
        return 2
    gh_sig, = struct.unpack_from("<I", base, GH_OFF)
    if gh_sig != SIGNATURE:
        print("groupHeader.Signature mismatch at offset %d -- struct layout drifted"
              % GH_OFF, file=sys.stderr)
        return 2
    orig_group_size, = struct.unpack_from("<i", base, GROUPSIZE_OFF)
    orig_comp_size, = struct.unpack_from("<i", base, COMPSIZE_OFF)
    if DATA_OFF + orig_comp_size != len(base):
        print("compSize (%d) + header (%d) != file size (%d) -- struct layout drifted"
              % (orig_comp_size, DATA_OFF, len(base)), file=sys.stderr)
        return 2

    # name -> (file contents, expected substring of the game's own error
    # report -- see src/Tables.cpp's FileErrors table). The caller (a bash
    # 3.2 script -- no associative arrays) reads this triple back per line,
    # '|'-separated, rather than keeping its own copy of the mapping.
    cases = {}

    CORRUPT = "File is Corrupt"      # ECORRUPT, src/Tables.cpp:2678
    READERR = "File Read Error"      # EREADERR, src/Tables.cpp:2676

    # --- corrupt header fields: zero, negative, absurdly large -------------
    cases["compsize_zero"] = (patch_i32(base, COMPSIZE_OFF, 0), CORRUPT)
    cases["compsize_negative"] = (patch_i32(base, COMPSIZE_OFF, -1), CORRUPT)
    cases["compsize_huge"] = (patch_i32(base, COMPSIZE_OFF, 600_000_000), CORRUPT)
    cases["groupsize_zero"] = (patch_i32(base, GROUPSIZE_OFF, 0), CORRUPT)
    cases["groupsize_negative"] = (patch_i32(base, GROUPSIZE_OFF, -1), CORRUPT)
    cases["groupsize_huge"] = (patch_i32(base, GROUPSIZE_OFF, 600_000_000), CORRUPT)

    # --- truncation ----------------------------------------------------------
    cases["truncated_in_header"] = (base[:50], READERR)  # cuts fileHeader itself
    cases["truncated_mid_data"] = (
        base[:DATA_OFF + orig_comp_size - 1000], CORRUPT)  # header intact, blob short

    # --- the core defect: a stream that lies about its own size -------------
    overflow_blob = build_overflow_stream()
    f = patch_i32(base, COMPSIZE_OFF, len(overflow_blob))
    f = patch_i32(f, GROUPSIZE_OFF, 100)  # tiny claimed size -> small allocation
    cases["overflow_attempt"] = (f[:DATA_OFF] + overflow_blob, CORRUPT)

    short_blob = build_short_stream()
    f = patch_i32(base, COMPSIZE_OFF, len(short_blob))
    f = patch_i32(f, GROUPSIZE_OFF, 100_000)  # claims far more than it delivers
    cases["decodes_short"] = (f[:DATA_OFF] + short_blob, CORRUPT)

    # NOT included here: a corrupted gh.objCount/gh.dataCount (both read
    # straight from the uncompressed file header, downstream of every check
    # above) DOES reach CFile::FRead's new past-end guard cleanly -- but by
    # the time it fires, Registry::LoadGroup has already reconstructed
    # theGame in place and the exception skips the pointer-fixup pass that
    # normally runs after it, which then crashes on process teardown
    # (delete theGame in Wposix.cpp main()). That crash is bd inc-8rk (filed
    # 2026-08-17, P4, already known to leave theGame deregistered after a
    # LoadGroup exception) reached through a new, worse-than-previously-
    # recorded path, not a new defect in the decompression/allocation trust
    # boundary this file is testing. See the inc-l0t and inc-8rk bd notes
    # dated 2026-08-16/17 for the repro and the reasoning for leaving it out
    # of this suite rather than asserting on a crash.

    for name, (contents, expected) in cases.items():
        path = os.path.join(out_dir, name + ".sav")
        with open(path, "wb") as fh:
            fh.write(contents)
        print("%s|%s|%s" % (name, path, expected))

    return 0


if __name__ == "__main__":
    sys.exit(main())
