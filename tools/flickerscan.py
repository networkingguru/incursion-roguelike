"""Mean luminance of the GAME WINDOW over time, against the game's repaints.

Two things this does that a naive screen scan cannot:

  * It crops every capture to the game window. The window covers about half
    the screen, so averaging the whole desktop halves any real signal and
    lets unrelated windows swamp it entirely. The game logs its own rectangle
    (the "winrect" lines), so the crop needs no window-manager access.

  * It labels every sample with how long it had been since the game last
    repainted, and reports what share of the brightness swing that explains.
    Without that, screen content changes look exactly like the bug.

Usage: python3 tools/flickerscan.py '<glob of pngs>' [palette.log] [front.tsv]
"""
import sys
import glob
import os

try:
    from PIL import Image
except ImportError:
    sys.exit("needs Pillow: python3 -m pip install --user Pillow")

# A sample this long after the last repaint counts as "quiet". A sample within
# FRESH_S counts as "just repainted". The gap between the two bands is
# deliberate -- samples in between are ambiguous and are left out of the test.
FRESH_S = 1.0
QUIET_S = 2.0
# The fresh-vs-quiet difference must account for at least this much of the
# total swing before repaint cadence gets the blame for it.
SHARE_TO_BLAME_CADENCE = 0.5


def parse_palette(path):
    """Presents (epoch ms) and window rectangles (epoch ms + points) from a log."""
    anchor_game_ms = anchor_epoch_ms = None
    presents, rects = [], []
    with open(path) as fh:
        for line in fh:
            line = line.rstrip("\n")
            if line.startswith("# game_ms "):
                parts = line.split()
                anchor_game_ms, anchor_epoch_ms = int(parts[2]), int(parts[5])
                continue
            if not line or line.startswith(("#", "ms\t")):
                continue
            cols = line.split("\t")
            if len(cols) < 2:
                continue
            if cols[1] == "present":
                presents.append(int(cols[0]))
            elif cols[1] == "winrect" and len(cols) > 2:
                # "win 219,169 1272x768 drawable 1272x768 display 1710x1107"
                f = cols[2].split()
                x, y = (int(v) for v in f[1].split(","))
                w, h = (int(v) for v in f[2].split("x"))
                dw, dh = (int(v) for v in f[6].split("x"))
                rects.append((int(cols[0]), x, y, w, h, dw, dh))
    if anchor_epoch_ms is None:
        sys.exit("%s has no '# game_ms N == epoch_ms M' anchor line.\n"
                 "It came from an older probe build. Rebuild with "
                 "EXTRA_CXXFLAGS=-DPALETTE_LOG and run again." % path)
    off = anchor_epoch_ms - anchor_game_ms
    return {
        "presents": sorted(p + off for p in presents),
        "rects": sorted((r[0] + off,) + r[1:] for r in rects),
    }


def newest_at_or_before(items, t, key=lambda v: v):
    found = None
    for item in items:
        if key(item) <= t:
            found = item
        else:
            break
    return found


def crop_box(im, rect):
    """Window rect in points -> pixel box in this capture, clipped to it.

    Returns None when the capture is already just the window. The capture
    script uses `screencapture -R` on the window rectangle when it can, which
    is twice as fast as a full screen grab -- cropping such a frame a second
    time would cut a window-sized hole out of a window-sized image.
    """
    _, x, y, w, h, dw, dh = rect
    if not dw or not dh:
        return None
    for factor in (1, 2):
        if abs(im.width - w * factor) <= max(4, 0.02 * w * factor):
            return None
    scale = im.width / float(dw)
    box = (int(x * scale), int(y * scale),
           int((x + w) * scale), int((y + h) * scale))
    box = (max(0, box[0]), max(0, box[1]),
           min(im.width, box[2]), min(im.height, box[3]))
    if box[2] - box[0] < 8 or box[3] - box[1] < 8:
        return None
    return box


def mean_luma(path, rect):
    im = Image.open(path)
    box = crop_box(im, rect) if rect else None
    if box:
        im = im.crop(box)
    im = im.convert("L")
    # Downsample hard. A global brightness shift survives it, and this makes
    # the scan fast enough to run on a few thousand captures.
    im = im.resize((max(1, im.width // 8), max(1, im.height // 8)))
    data = im.tobytes()
    return sum(data) / len(data)


def load_front(path):
    """shot basename -> frontmost app string."""
    front = {}
    with open(path) as fh:
        for line in fh:
            cols = line.rstrip("\n").split("\t")
            if len(cols) >= 2 and cols[0] != "shot":
                front[cols[0]] = cols[1]
    return front


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    paths = sorted(glob.glob(sys.argv[1]))
    if not paths:
        sys.exit("no captures matched " + sys.argv[1])

    pal = parse_palette(sys.argv[2]) if len(sys.argv) > 2 else {"presents": [],
                                                                "rects": []}
    presents, rects = pal["presents"], pal["rects"]
    front = load_front(sys.argv[3]) if len(sys.argv) > 3 else {}

    if not rects:
        print("NOTE: no winrect lines in the palette log -- measuring the")
        print("      whole screen. Any real change will be diluted by however")
        print("      much of the screen is not the game.")
        print()

    rows = []
    for p in paths:
        t = int(os.path.getmtime(p) * 1000)
        rect = newest_at_or_before(rects, t, key=lambda r: r[0]) or (
            rects[0] if rects else None)
        rows.append((os.path.splitext(os.path.basename(p))[0], t,
                     mean_luma(p, rect)))

    hi = max(v for _, _, v in rows)
    # macOS does not fail a denied screen capture. It writes a fully black
    # frame instead. Without this check the run reads span 0.000 and reports
    # "the screen did not change brightness" -- a verdict from no data at all.
    if hi < 1.0:
        sys.exit(
            "ABORT: every capture is black (max luminance %.3f).\n"
            "The captures were blocked, not measured, so there is no verdict.\n"
            "Grant Screen Recording to the terminal you ran this from:\n"
            "  System Settings > Privacy & Security > Screen & System Audio "
            "Recording\n"
            "Then quit and reopen that terminal and run this again." % hi
        )

    # Samples from before the game drew anything, or after it stopped, measure
    # something else. Drop them rather than let them fake a swing.
    dropped_window = 0
    if presents:
        first, last = presents[0], presents[-1]
        kept = [r for r in rows if first <= r[1] <= last]
        dropped_window = len(rows) - len(kept)
        if not kept:
            sys.exit("ABORT: no capture falls inside the game's run.\n"
                     "The scan and the game did not overlap.")
        rows = kept

    # Frames where another app was in front are not measuring the game, even
    # cropped to the game's rectangle -- the other window is sitting on top.
    dropped_front = 0
    if front:
        kept = [r for r in rows if "ncursion" in front.get(r[0], "")]
        dropped_front = len(rows) - len(kept)
        if not kept:
            sys.exit("ABORT: the game was never the frontmost app in any\n"
                     "capture. Nothing here measures the game window.")
        rows = kept

    lo = min(v for _, _, v in rows)
    hi = max(v for _, _, v in rows)
    span = hi - lo

    print(f"{'shot':<9}{'epoch_ms':>15}{'since_paint':>13}{'mean_luma':>11}"
          f"{'vs min':>9}")
    fresh, quiet = [], []
    for name, t, v in rows:
        prev = newest_at_or_before(presents, t) if presents else None
        if prev is None:
            gap_s = "     -"
        else:
            gap = (t - prev) / 1000.0
            gap_s = f"{gap:>6.2f}s"
            if gap < FRESH_S:
                fresh.append(v)
            elif gap >= QUIET_S:
                quiet.append(v)
        bar = "#" * int(min(50, (v - lo) * 4))
        print(f"{name:<9}{t:>15}{gap_s:>13}{v:>11.3f}{v - lo:>+9.3f}  {bar}")

    print()
    if dropped_window:
        print(f"dropped {dropped_window} capture(s) outside the game's run")
    if dropped_front:
        print(f"dropped {dropped_front} capture(s) where the game was not in front")
    print(f"kept {len(rows)} capture(s)")
    print(f"min {lo:.3f}   max {hi:.3f}   span {span:.3f}")
    if rects:
        probe = Image.open(paths[0])
        if crop_box(probe, rects[0]):
            print(f"cropped to the game window "
                  f"({rects[-1][3]}x{rects[-1][4]} points)")
        else:
            print(f"captures are already window-only "
                  f"({rects[-1][3]}x{rects[-1][4]} points); no crop needed")

    if span < 0.5:
        print("VERDICT: the game window did not change brightness.")
        print("         Whatever you saw happens below the framebuffer --")
        print("         the window server, the colour pipeline, or the panel.")
        return
    print("VERDICT: the game window DID change brightness.")

    if len(fresh) >= 3 and len(quiet) >= 3:
        mf = sum(fresh) / len(fresh)
        mq = sum(quiet) / len(quiet)
        diff = mf - mq
        # Judge the difference against the swing it is meant to explain, not
        # against a fixed number. A 1-point gap inside a 20-point swing is
        # noise; the same gap inside a 2-point swing is the whole story.
        share = abs(diff) / span if span else 0.0
        print()
        print(f"  within {FRESH_S:.0f}s of a repaint: mean {mf:.3f}  (n={len(fresh)})")
        print(f"  quiet {QUIET_S:.0f}s or longer:     mean {mq:.3f}  (n={len(quiet)})")
        print(f"  difference: {diff:+.3f}  "
              f"({share * 100:.0f}% of the {span:.3f} swing)")
        if share < SHARE_TO_BLAME_CADENCE:
            print("  => Repaint cadence does not explain the swing. Something")
            print("     else moves the brightness. Find it before changing")
            print("     any drawing code.")
        elif diff > 0:
            print("  => The window is brighter right after we repaint, and")
            print("     dimmer when we go quiet. Repaint cadence is the cause.")
        else:
            print("  => Brighter when QUIET. That is the opposite of the")
            print("     cadence theory and needs explaining before any fix.")
    else:
        print()
        print(f"  Not enough samples to test cadence "
              f"(fresh={len(fresh)}, quiet={len(quiet)}, need 3 of each).")


if __name__ == "__main__":
    main()
