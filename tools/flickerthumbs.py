"""Downscale a directory of captures into shareable thumbnails.

Full-size screen captures run to gigabytes for a long session, which is far
too much to bundle. The thumbnails keep the visual record at a size that can
be attached to an issue. The originals stay where they are.

Usage: python3 tools/flickerthumbs.py <shots_dir> <thumbs_dir> [width]
"""
import os
import sys

from PIL import Image

WIDTH = 320


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    src, dst = sys.argv[1], sys.argv[2]
    width = int(sys.argv[3]) if len(sys.argv) > 3 else WIDTH
    os.makedirs(dst, exist_ok=True)

    n = 0
    for name in sorted(os.listdir(src)):
        if not name.lower().endswith(".png"):
            continue
        im = Image.open(os.path.join(src, name))
        height = max(1, int(im.height * width / im.width))
        out = os.path.join(dst, name.replace(".png", ".jpg"))
        im.convert("RGB").resize((width, height)).save(out, quality=70)
        # Carry the timing across, since the analysis keys off mtime.
        stamp = os.path.getmtime(os.path.join(src, name))
        os.utime(out, (stamp, stamp))
        n += 1
    print("thumbs %d" % n)


if __name__ == "__main__":
    main()
