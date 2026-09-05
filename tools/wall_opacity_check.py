#!/usr/bin/env python3
"""Regression analyser for inc-qhux -- walls that pass light.

The bug: level generation restored a cell's .Solid from terrain when it removed
a door but never its .Opaque (src/MakeLev.cpp), so a wall reconstituted from a
removed door stayed solid but see-through. In a saved map that shows as a wall
TERRAIN most of whose cells are opaque but a few are not -- Brian's real save
had exactly 3 such cells on each of its two levels (Terrain 4: 1573 opaque, 3
transparent). A by-design transparent wall (ice, fence, portcullis) is uniformly
non-opaque, and a feature cell (pillar on a floor terrain) makes an otherwise
non-wall terrain briefly solid; neither is this bug, so the invariant is stated
over WALL terrains that are in the majority opaque.

  analyse <save.sav>   exit 0 clean, 1 if a majority-opaque wall terrain has any
                       transparent cell (the bug), 2 on a parse problem.
  inject  <in> <out>   clear .Opaque on 3 opaque solid-wall cells, to give the
                       --selftest a known-bad save and prove this analyser bites.

Save wire format: docs/SAVE-SCHEMA-SPEC.md, src/SaveV1.cpp. Record envelope is
u8 type, u32 handle, u32 length (fields+terminator), then u16 tag / u8 kind /
payload fields to a tag-0 terminator. Map record is type 4; its grid is the
tag-672 K_EMBED whose inner tag-4 blob is 8 bytes per tile, tile byte 2 bit 0 =
Opaque, byte 2 bit 4 = Solid, byte 3 bit 4 (flag bit 12) = isWall.
"""
import sys, zlib, struct

FIXED = {1: 1, 2: 1, 3: 2, 4: 2, 5: 4, 6: 4, 9: 4, 10: 4}


def zbody(path):
    raw = open(path, "rb").read()
    i = raw.find(b"\x78\x9c")
    if i < 0:
        sys.exit("no zlib stream in %s" % path)
    return raw[:i], zlib.decompress(raw[i:])


def field_end(b, p):
    kind = b[p]; q = p + 1
    if kind in FIXED:
        n = FIXED[kind]; return q + n, kind, q, n
    if kind in (7, 8, 12):
        n = struct.unpack_from("<I", b, q)[0]; return q + 4 + n, kind, q + 4, n
    if kind == 11:
        c = struct.unpack_from("<I", b, q)[0]; e = struct.unpack_from("<I", b, q + 4)[0]
        return q + 8 + c * e, kind, q + 8, c * e
    raise ValueError("bad kind %d at %d" % (kind, p))


def walk(b, p, end):
    while p < end:
        tag = struct.unpack_from("<H", b, p)[0]
        if tag == 0:
            return
        nxt, kind, poff, plen = field_end(b, p + 2)
        yield tag, kind, poff, plen
        p = nxt


def grids(body):
    """Yield (sizeX, sizeY, packed_offset) for every Map record."""
    p = 0
    while p + 9 <= len(body):
        typ = body[p]; length = struct.unpack_from("<I", body, p + 5)[0]
        fs = p + 9; fe = fs + length
        if typ == 4:
            sx = sy = packed = None
            for tag, kind, poff, plen in walk(body, fs, fe):
                if tag == 673:
                    sx = struct.unpack_from("<h", body, poff)[0]
                elif tag == 674:
                    sy = struct.unpack_from("<h", body, poff)[0]
                elif tag == 672:
                    for it, ik, ipoff, iplen in walk(body, poff, poff + plen):
                        if it == 4:
                            packed = ipoff
            if sx and packed is not None:
                yield sx, sy, packed
        p = fe


def analyse(path):
    _, body = zbody(path)
    bad = []
    nmaps = 0
    for sx, sy, packed in grids(body):
        nmaps += 1
        # per terrain index: opaque-wall count, transparent-wall count, samples
        stat = {}
        for idx in range(sx * sy):
            d = packed + idx * 8
            ter = body[d + 1]
            flags = body[d + 2] | (body[d + 3] << 8)
            if not (flags & 0x1000):        # isWall only
                continue
            opaque = flags & 1
            s = stat.setdefault(ter, [0, 0, []])
            if opaque:
                s[0] += 1
            else:
                s[1] += 1
                if len(s[2]) < 8:
                    s[2].append((idx % sx, idx // sx))
        for ter, (op, tr, samp) in stat.items():
            if op > tr and tr > 0:          # majority-opaque wall, some see-through
                bad.append((nmaps, ter, op, tr, samp))
    if nmaps == 0:
        print("no map grid parsed", file=sys.stderr)
        return 2
    if bad:
        for m, ter, op, tr, samp in bad:
            print("FAIL map#%d Terrain=%d opaque=%d transparent=%d cells=%s"
                  % (m, ter, op, tr, samp))
        return 1
    print("OK: %d map(s), no majority-opaque wall passes light" % nmaps)
    return 0


def inject(src, dst):
    head, body = zbody(src)
    body = bytearray(body)
    sx, sy, packed = next(grids(body))
    done = []
    for idx in range(sx * sy):
        d = packed + idx * 8
        flags = body[d + 2] | (body[d + 3] << 8)
        if (flags & 1) and (flags & 0x10) and (flags & 0x1000):
            body[d + 2] &= ~1
            done.append((idx % sx, idx // sx))
            if len(done) == 3:
                break
    comp = zlib.compress(bytes(body), 6)
    head = bytearray(head)
    struct.pack_into("<i", head, 108, len(comp))   # groupHeader.compSize
    open(dst, "wb").write(bytes(head) + comp)
    print("injected bug at %s" % done)
    return 0 if len(done) == 3 else 2


if __name__ == "__main__":
    if len(sys.argv) >= 3 and sys.argv[1] == "analyse":
        sys.exit(analyse(sys.argv[2]))
    if len(sys.argv) >= 4 and sys.argv[1] == "inject":
        sys.exit(inject(sys.argv[2], sys.argv[3]))
    sys.exit("usage: wall_opacity_check.py analyse <save> | inject <in> <out>")
