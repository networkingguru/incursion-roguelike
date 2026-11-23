#!/usr/bin/env python3
"""Read pixels from an uncompressed 24- or 32-bit BMP. Stdlib only.

Usage: tools/bmp_pixel.py <file.bmp> <x> <y> [<x> <y> ...]
Prints one "x y r g b" line per point. Exit 2 on a bad file or a point off the image.
Module use: read_bmp(path) -> (width, height, getpixel(x, y) -> (r, g, b))
"""
import struct
import sys


def read_bmp(path):
    with open(path, "rb") as fh:
        data = fh.read()
    if len(data) < 54 or data[:2] != b"BM":
        raise ValueError("not a BMP: %s" % path)
    off = struct.unpack_from("<I", data, 10)[0]
    hdr = struct.unpack_from("<I", data, 14)[0]
    if hdr < 40:
        raise ValueError("unsupported BMP header size %d" % hdr)
    w, h, planes, bpp, comp = struct.unpack_from("<iiHHI", data, 18)
    if comp not in (0, 3) or bpp not in (24, 32):
        raise ValueError("unsupported BMP: bpp=%d compression=%d" % (bpp, comp))
    top_down = h < 0
    h = abs(h)
    step = bpp // 8
    stride = (w * step + 3) // 4 * 4
    masks = None
    if comp == 3 and bpp == 32:
        masks = struct.unpack_from("<III", data, 54)

    def shift(mask):
        s = 0
        while mask and not mask & 1:
            mask >>= 1
            s += 1
        return s, mask

    def getpixel(x, y):
        if not (0 <= x < w and 0 <= y < h):
            raise IndexError("point %d,%d is outside %dx%d" % (x, y, w, h))
        row = y if top_down else h - 1 - y
        p = off + row * stride + x * step
        if masks:
            v = struct.unpack_from("<I", data, p)[0]
            out = []
            for m in masks:
                s, mm = shift(m)
                out.append(((v & m) >> s) * 255 // mm if mm else 0)
            return tuple(out)
        return (data[p + 2], data[p + 1], data[p])

    return w, h, getpixel


def block_mean(px, x, y, w, h):
    """Mean (r, g, b) of the w x h block whose top-left pixel is (x, y)."""
    tot = [0, 0, 0]
    for yy in range(y, y + h):
        for xx in range(x, x + w):
            for i, v in enumerate(px(xx, yy)):
                tot[i] += v
    n = w * h
    return tuple(t / n for t in tot)


def main(argv):
    if len(argv) == 7 and argv[1] == "--mean":
        # --mean <file.bmp> <x> <y> <w> <h>: prints the block's mean r g b
        try:
            _, _, px = read_bmp(argv[2])
            print("%.2f %.2f %.2f" % block_mean(px, *[int(a) for a in argv[3:7]]))
        except (ValueError, IndexError, OSError) as e:
            print("bmp_pixel: %s" % e, file=sys.stderr)
            return 2
        return 0
    if len(argv) < 4 or len(argv) % 2 != 0:
        print(__doc__)
        return 2
    try:
        _, _, px = read_bmp(argv[1])
        for i in range(2, len(argv), 2):
            x, y = int(argv[i]), int(argv[i + 1])
            print("%d %d %d %d %d" % ((x, y) + px(x, y)))
    except (ValueError, IndexError, OSError) as e:
        print("bmp_pixel: %s" % e, file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
