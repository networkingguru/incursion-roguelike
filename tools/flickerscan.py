"""Mean luminance of a sequence of screen captures, in time order.

Why this and not the in-game FLICKER_PROBE: that probe runs inside libtcod's
actual_rendering(), so it can only sample when the game presents a frame. The
game presents about twice a second, with gaps measured up to 3.4s. Anything
that changes brightness *between* presents is invisible to it -- which fits
both the flat 8.99 reading it produced and the multi-second ramp the flicker
is reported to have.

This samples the composited screen on a fixed clock instead, so it sees what
the display is actually showing regardless of when the game drew it.

Usage: python3 tools/flickerscan.py '<glob of pngs>'
"""
import sys
import glob
import os

try:
    from PIL import Image
except ImportError:
    sys.exit("needs Pillow: python3 -m pip install --user Pillow")


def mean_luma(path):
    im = Image.open(path).convert("L")
    # Downsample hard. A global brightness shift survives it, and this makes
    # the scan fast enough to run on a few hundred full-screen captures.
    im = im.resize((max(1, im.width // 8), max(1, im.height // 8)))
    data = im.tobytes()
    return sum(data) / len(data)


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    paths = sorted(glob.glob(sys.argv[1]))
    if not paths:
        sys.exit("no captures matched " + sys.argv[1])

    values = [(os.path.basename(p), mean_luma(p)) for p in paths]
    lo = min(v for _, v in values)
    hi = max(v for _, v in values)
    span = hi - lo

    print(f"{'capture':<22}{'mean_luma':>10}{'vs min':>9}")
    for name, v in values:
        # One bar per 0.25 of luminance, so a small real shift is still visible.
        bar = "#" * int(min(50, (v - lo) * 4))
        print(f"{name:<22}{v:>10.3f}{v - lo:>+9.3f}  {bar}")

    print()
    print(f"min {lo:.3f}   max {hi:.3f}   span {span:.3f}")
    # The threshold is a judgement call, not a measurement: captures of a
    # static screen in this game sit within a few hundredths of each other,
    # because only the cursor block and a highlight move.
    if span < 0.5:
        print("VERDICT: the composited screen did not change brightness.")
        print("         Whatever you saw happens below the framebuffer --")
        print("         the window server, the colour pipeline, or the panel.")
    else:
        print("VERDICT: the composited screen DID change brightness.")
        print("         The change is in what is being drawn or presented,")
        print("         so it is ours to fix. Look for the jump above.")


if __name__ == "__main__":
    main()
