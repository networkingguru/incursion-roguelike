"""Self-test for flickerscan.py's cropping and repaint-correlation logic.

Builds synthetic captures with known brightness, a known game-window rectangle
and known repaint times, then checks that flickerscan reaches the right
verdict. Run it after touching flickerscan.py:

    python3 tools/flickerscan_selftest.py

It needs no fixtures and no test framework. It prints OK or raises.
"""
import os
import subprocess
import sys
import tempfile

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
SCAN = os.path.join(HERE, "flickerscan.py")

ANCHOR_EPOCH = 1_700_000_000_000
PRESENTS_MS = [0, 3000, 6000, 9000, 12000]
DURATION_MS = 14000
INTERVAL_MS = 500

# A synthetic desktop in points, and the captures at 2x, as macOS delivers.
DISPLAY_W, DISPLAY_H = 400, 300
IMG_W, IMG_H = DISPLAY_W * 2, DISPLAY_H * 2
WIN = (50, 40, 200, 150)          # x, y, w, h in points -- a quarter of the area
SURROUND = 200                    # bright desktop around the game window


def write_palette_log(path, presents_ms, with_rect=True):
    with open(path, "w") as fh:
        fh.write("# game_ms 0 == epoch_ms %d\n" % ANCHOR_EPOCH)
        fh.write("ms\tevent\tdetail\n")
        fh.write("0\treset-enter\twindowed\n")
        if with_rect:
            fh.write("0\twinrect\twin %d,%d %dx%d drawable %dx%d display %dx%d\n"
                     % (WIN[0], WIN[1], WIN[2], WIN[3], WIN[2], WIN[3],
                        DISPLAY_W, DISPLAY_H))
        for t in presents_ms:
            fh.write("%d\tpresent\tUpdate\n" % t)


def write_captures(directory, luma_for_offset, framed=True):
    """One PNG per sample, mtime set to its epoch ms.

    framed=True draws a bright constant desktop with the game window inset,
    so a scan that fails to crop measures mostly desktop.
    """
    n = 0
    for offset in range(0, DURATION_MS, INTERVAL_MS):
        n += 1
        grey = luma_for_offset(offset)
        if framed:
            im = Image.new("L", (IMG_W, IMG_H), SURROUND)
            x, y, w, h = (v * 2 for v in WIN)
            im.paste(Image.new("L", (w, h), grey), (x, y))
        else:
            im = Image.new("L", (32, 32), grey)
        path = os.path.join(directory, "%05d.png" % n)
        im.save(path)
        stamp = (ANCHOR_EPOCH + offset) / 1000.0
        os.utime(path, (stamp, stamp))
    return n


def run_scan(shots_dir, palette_path, front_path=None):
    cmd = [sys.executable, SCAN, os.path.join(shots_dir, "*.png"), palette_path]
    if front_path:
        cmd.append(front_path)
    r = subprocess.run(cmd, capture_output=True, text=True)
    return r.stdout + r.stderr


def gap_since_present(offset):
    prev = max((p for p in PRESENTS_MS if p <= offset), default=None)
    return None if prev is None else (offset - prev) / 1000.0


def dims_when_quiet(offset):
    """Bright just after a repaint, dim once quiet. The cadence theory."""
    gap = gap_since_present(offset)
    return 60 if gap is not None and gap < 1.0 else 40


def no_correlation(offset):
    """Brightness swings hard, but never in step with repaints."""
    return 60 if (offset // INTERVAL_MS) % 2 == 0 else 40


def static(offset):
    return 50


def scan_case(luma_fn, with_rect=True, framed=True, front=None):
    with tempfile.TemporaryDirectory() as tmp:
        shots = os.path.join(tmp, "shots")
        os.mkdir(shots)
        palette = os.path.join(tmp, "palette.log")
        write_palette_log(palette, PRESENTS_MS, with_rect=with_rect)
        n = write_captures(shots, luma_fn, framed=framed)
        front_path = None
        if front is not None:
            front_path = os.path.join(tmp, "front.tsv")
            with open(front_path, "w") as fh:
                fh.write("shot\tfrontmost\n")
                for i in range(1, n + 1):
                    fh.write("%05d\t%s\n" % (i, front(i)))
        return run_scan(shots, palette, front_path)


def expect(name, out, must_contain, must_not_contain=()):
    for needle in must_contain:
        assert needle in out, (
            "%s: expected %r.\n--- output ---\n%s" % (name, needle, out))
    for needle in must_not_contain:
        assert needle not in out, (
            "%s: did NOT expect %r.\n--- output ---\n%s" % (name, needle, out))
    print("ok  %s" % name)


def check_crop_isolates_the_window():
    """The whole point: a bright desktop must not drown the game's swing.

    The window is a quarter of the frame, so uncropped the 20-point swing
    shrinks to 5 and sits on a mean near 160. Cropped, it is the full 20.
    """
    cropped = scan_case(dims_when_quiet, with_rect=True)
    uncropped = scan_case(dims_when_quiet, with_rect=False)
    expect("cropping recovers the game's full swing", cropped,
           must_contain=["span 20.000", "Repaint cadence is the cause",
                         "cropped to the game window"])
    expect("without a rect the same swing is diluted", uncropped,
           must_contain=["span 5.000", "no winrect lines"])


def check_front_filter():
    """Frames owned by another app must be dropped, not measured."""
    out = scan_case(dims_when_quiet,
                    front=lambda i: "ASN:0x0-0x1-\"Ghostty\":" if i <= 10
                    else "ASN:0x0-0x2-\"incursion-palettelog\":")
    expect("frames where the game was not in front are dropped", out,
           must_contain=["where the game was not in front"])


def check_black_frames_abort():
    out = scan_case(lambda offset: 0, framed=False)
    expect("black frames abort instead of reaching a verdict", out,
           must_contain=["ABORT"], must_not_contain=["VERDICT"])


def check_out_of_window_dropped():
    with tempfile.TemporaryDirectory() as tmp:
        shots = os.path.join(tmp, "shots")
        os.mkdir(shots)
        palette = os.path.join(tmp, "palette.log")
        write_palette_log(palette, PRESENTS_MS)
        n = write_captures(shots, dims_when_quiet)
        stray = os.path.join(shots, "%05d.png" % (n + 1))
        Image.new("L", (IMG_W, IMG_H), 255).save(stray)
        stamp = (ANCHOR_EPOCH + DURATION_MS + 60000) / 1000.0
        os.utime(stray, (stamp, stamp))
        out = run_scan(shots, palette)
    expect("captures outside the game's run are dropped", out,
           must_contain=["dropped ", "max 60.000"])


def check_precropped_captures_are_not_cropped_twice():
    """`screencapture -R` already gives just the window. Cropping it again
    would cut a window-sized hole out of a window-sized image."""
    with tempfile.TemporaryDirectory() as tmp:
        shots = os.path.join(tmp, "shots")
        os.mkdir(shots)
        palette = os.path.join(tmp, "palette.log")
        write_palette_log(palette, PRESENTS_MS, with_rect=True)
        for i, offset in enumerate(range(0, DURATION_MS, INTERVAL_MS), start=1):
            # Window-sized frames at 2x, exactly what -R produces.
            im = Image.new("L", (WIN[2] * 2, WIN[3] * 2), dims_when_quiet(offset))
            path = os.path.join(shots, "%05d.png" % i)
            im.save(path)
            stamp = (ANCHOR_EPOCH + offset) / 1000.0
            os.utime(path, (stamp, stamp))
        out = run_scan(shots, palette)
    expect("window-only captures are not cropped a second time", out,
           must_contain=["already window-only", "span 20.000",
                         "Repaint cadence is the cause"],
           must_not_contain=["cropped to the game window"])


def main():
    check_crop_isolates_the_window()
    check_precropped_captures_are_not_cropped_twice()
    expect("swings unrelated to repaints are not called cadence",
           scan_case(no_correlation),
           must_contain=["Repaint cadence does not explain the swing"],
           must_not_contain=["Repaint cadence is the cause"])
    expect("a static window reports no change",
           scan_case(static),
           must_contain=["did not change brightness"],
           must_not_contain=["Repaint cadence is the cause"])
    check_front_filter()
    check_black_frames_abort()
    check_out_of_window_dropped()
    print("\nOK")


if __name__ == "__main__":
    main()
