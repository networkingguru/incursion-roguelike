#!/bin/bash
# One-terminal flicker capture. Launches the instrumented game, samples the
# screen as fast as the machine allows, records which app was frontmost at
# every sample, and keeps all of it in one dated directory.
#
# Nothing here is timed by hand. The game is started by this script, so its
# clock and the capture clock share a known anchor, and every frame carries
# its own mtime. Stop it by quitting the game, or by creating the STOP file
# that this script prints on startup.
#
# WHY NOT 0.1s: screencapture costs ~171ms per frame on this machine, measured.
# There is no sleep in the loop below -- this is already as fast as stills go.
# For a finer trace than that you need video, which trades exact per-frame
# timestamps for frame rate.
#
# Usage: tools/flickercapture.sh [max_seconds]      (default 900)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

BIN="${BIN:-incursion-palettelog}"
MAX="${1:-900}"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="$ROOT/logs/flicker-$STAMP"
SHOTS="$OUT/shots"
STOP="$OUT/STOP"
FRONT="$OUT/front.tsv"

mkdir -p "$SHOTS"

command -v python3 >/dev/null || { echo "needs python3"; exit 1; }
python3 -c "import PIL" 2>/dev/null || { echo "needs Pillow"; exit 1; }
[ -x "$ROOT/$BIN" ] || { echo "no $BIN -- build it first"; exit 1; }

echo "output dir : $OUT"
echo "stop with  : touch $STOP"
echo

# Start from no palette log at all, so the rectangle read below cannot come
# from a previous session in which the window sat somewhere else.
rm -f "$ROOT/logs/palette.log"

"$ROOT/$BIN" &
GAME=$!
echo "$GAME" > "$OUT/game.pid"
echo "launched $BIN as pid $GAME"

# Capturing only the window costs 82ms a frame against 171ms for the whole
# screen, measured -- twice the sample rate and a quarter of the disk. The
# game logs its own rectangle, so wait briefly for that line to appear.
RECTARG=""
for _ in 1 2 3 4 5 6 7 8 9 10; do
    grep -q winrect "$ROOT/logs/palette.log" 2>/dev/null && break
    sleep 0.5
done
RECT="$(python3 - "$ROOT/logs/palette.log" <<'PY'
import re, sys
try:
    for line in open(sys.argv[1]):
        if "\twinrect\t" in line:
            m = re.search(r"win (-?\d+),(-?\d+) (\d+)x(\d+)", line)
            if m:
                print("%s,%s,%s,%s" % m.groups())
                break
except OSError:
    pass
PY
)"
if [ -n "$RECT" ]; then
    RECTARG="-R $RECT"
    echo "capturing window only: $RECT  (~12 frames/sec)"
    echo "NOTE: do not move or resize the window -- the region is fixed here."
else
    echo "no window rect yet; capturing the whole screen (~6 frames/sec)"
fi
echo

printf 'shot\tfrontmost\n' > "$FRONT"

START=$(python3 -c 'import time; print(int(time.time()*1000))')
echo "capture_start_epoch_ms $START" > "$OUT/window.txt"

i=0
while kill -0 "$GAME" 2>/dev/null && [ ! -f "$STOP" ]; do
    i=$((i + 1))
    n=$(printf '%06d' "$i")
    screencapture -x $RECTARG "$SHOTS/$n.png" 2>/dev/null
    # Which app owned the screen for this frame. Cheap (~10ms) and it removes
    # every argument about what the capture was actually looking at.
    # `lsappinfo front` yields only an opaque ASN, so resolve it to a name --
    # an ASN cannot be looked up afterwards, once the process is gone.
    asn="$(lsappinfo front 2>/dev/null | tr -d '\n')"
    printf '%s\t%s\t%s\n' "$n" \
        "$(lsappinfo info -only name "$asn" 2>/dev/null | tr -d '\n')" \
        "$asn" >> "$FRONT"
    # A safety cap only. At ~171ms per frame this is roughly MAX seconds.
    [ "$i" -ge $((MAX * 6)) ] && break
done

END=$(python3 -c 'import time; print(int(time.time()*1000))')
echo "capture_end_epoch_ms $END" >> "$OUT/window.txt"
echo "frames $i" >> "$OUT/window.txt"

kill "$GAME" 2>/dev/null
wait "$GAME" 2>/dev/null

echo
echo "captured $i frames. packaging..."

cp -f "$ROOT/logs/palette.log" "$OUT/palette.log" 2>/dev/null

python3 tools/flickerscan.py "$SHOTS/*.png" "$OUT/palette.log" "$FRONT" \
    > "$OUT/report.txt" 2>&1
python3 tools/flickerthumbs.py "$SHOTS" "$OUT/thumbs" >> "$OUT/window.txt" 2>&1

# The tarball carries everything a reader needs except the full-size frames,
# which stay on disk in $SHOTS and are far too large to bundle.
tar -czf "$OUT.tar.gz" -C "$ROOT/logs" \
    "flicker-$STAMP/report.txt" \
    "flicker-$STAMP/front.tsv" \
    "flicker-$STAMP/palette.log" \
    "flicker-$STAMP/window.txt" \
    "flicker-$STAMP/thumbs" 2>/dev/null

echo
cat "$OUT/report.txt"
echo
echo "full frames : $SHOTS"
echo "bundle      : $OUT.tar.gz"
