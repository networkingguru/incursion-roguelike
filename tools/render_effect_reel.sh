#!/bin/bash
# inc-jw0hw: render the effect reel. The probe (INCURSION_EFFECT_REEL,
# src/EffectReelProbe.cpp) casts every blast, globe, aura field and breath type
# in one lit room, one recorder clip each. This script runs the SDL build twice
# through tools/headless.sh, once with INCURSION_EFFECT_LIGHT_OFF=1, joins each
# clip's two frame sets into one side-by-side mp4 (tools/frames_to_video.sh
# --pair), and writes logs/effect-reel/<date>/index.html with a video per clip.
#   tools/render_effect_reel.sh [--only <name>[,<name>...]] [--keep-frames]
#   tools/render_effect_reel.sh --selftest   (no build: fabricated BMP frames prove the map-area identical-frames check)
# A clip whose light-on frames have an identical map area (sidebar, messages, status line ignored) fails the run, unless its row in
# tools/fixtures/effect-light-table.tsv (matched by the REEL_KEY line the probe logs: the declared name
# with its ;tag) says shows_nothing = yes. The run still writes the index, then exits 1.
# Each run's frames/ tree is 1-4 GB (--only) to ~55 GB (full reel). The script copies each run's errors.log to
# $OUT/errors-{off,on}.log, then deletes both run dirs (also on an early error exit). --keep-frames skips the deletion.
# Needs ./incursion (./build_macos.sh), ./incursion-headless
# (BACKEND=posix ./build_macos.sh) and ffmpeg. Launches the SDL build: the main
# session runs it, never an implementer.
# fact: the effect list and each clip's key -- the probe logs REEL_KEY <n> <declared name> per clip; the table is tools/fixtures/effect-light-table.tsv
# fact: the frames -- recorded by the SDL build, not the seeded game; the identical-frames test hashes only the map-area pixels of each BMP
# fact: the map area -- the probe logs REEL_MAPRECT <x> <y> <w> <h> (pixels, from TermCellPixel); no line or a rectangle outside the frame exits 2
# Exit 0 done, 1 a clip has frames in one run only, a run lacks REEL_DONE, or a clip shows nothing (all light-on
# map areas identical) and its table row does not say shows_nothing = yes, 2 no build or fixture or bad usage, or the frames cannot be cropped to the map area.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=1
OPTIONS=tools/fixtures/options-2026-08-22.dat
FIXTURE=xsummon-priest-seed5-opt0822
ONLY=""
SELFTEST=0
KEEP_FRAMES=0
TABLE="${INCURSION_LIGHT_TABLE:-tools/fixtures/effect-light-table.tsv}"
while [ $# -gt 0 ]; do
    case "$1" in
        --only) ONLY="${2:-}"; shift 2 ;;
        --selftest) SELFTEST=1; shift ;;
        --keep-frames) KEEP_FRAMES=1; shift ;;
        *) echo "usage: tools/render_effect_reel.sh [--only <name>[,<name>...]] [--keep-frames] | --selftest" >&2; exit 2 ;;
    esac
done

# identical_clips <frames dir> <errors.log> <table>: prints one line per clip whose MAP AREA is the same in every
# frame (f*.bmp, the recorder's format) and whose table row does not say shows_nothing = yes; exits 1 when it printed
# any. The map area is the pixel rectangle of the REEL_MAPRECT <x> <y> <w> <h> line the probe logs (from
# TermCellPixel: the map window's cells times the font cell size). The sidebar, message lines and status line are not
# hashed. Exits 2, printing why, when REEL_MAPRECT is missing or differs between lines, or a frame is not an
# uncompressed 24- or 32-bit BMP, or the rectangle does not lie inside it: a frame set it cannot crop never passes.
identical_clips() {
    python3 -I - "$@" <<'PY'
import hashlib, os, re, struct, sys
frames, log, table = sys.argv[1:4]
def die(msg):
    print("ERROR: " + msg)
    sys.exit(2)
keys = {}
rects = set()
for ln in open(log, encoding="latin-1"):
    m = re.search(r'  REEL_KEY (\d+) (.*?)\s*$', ln)
    if m:
        keys[int(m.group(1))] = m.group(2)
    m = re.search(r'  REEL_MAPRECT (.*?)\s*$', ln)
    if m:
        rects.add(m.group(1))
if len(rects) != 1:
    die("%s has %d distinct REEL_MAPRECT values (need exactly 1): %s" % (log, len(rects), sorted(rects)))
mm = re.fullmatch(r"(\d+) (\d+) (\d+) (\d+)", next(iter(rects)))
if not mm:
    die("REEL_MAPRECT is not '<x> <y> <w> <h>': %s" % next(iter(rects)))
rx, ry, rw, rh = map(int, mm.groups())
if rw <= 0 or rh <= 0:
    die("REEL_MAPRECT is empty: %s" % next(iter(rects)))
def map_pixels(path):
    d = open(path, "rb").read()
    if d[:2] != b"BM" or len(d) < 54:
        die("%s is not a BMP" % path)
    off = struct.unpack_from("<I", d, 10)[0]
    w, h, planes, bpp, comp = struct.unpack_from("<iiHHI", d, 18)
    if bpp not in (24, 32) or comp not in (0, 3) or w <= 0 or h == 0:
        die("%s: cannot decode (bpp %d, compression %d)" % (path, bpp, comp))
    top_down = h < 0
    h = abs(h)
    if rx + rw > w or ry + rh > h:
        die("%s: map rectangle %d,%d %dx%d lies outside the %dx%d frame" % (path, rx, ry, rw, rh, w, h))
    bp = bpp // 8
    stride = (w * bp + 3) // 4 * 4
    if off + stride * h > len(d):
        die("%s is truncated" % path)
    hh = hashlib.sha1()
    for y in range(ry, ry + rh):
        row = y if top_down else h - 1 - y
        o = off + row * stride + rx * bp
        hh.update(d[o:o + rw * bp])
    return hh.hexdigest()
shows = {}
for ln in open(table, encoding="utf-8"):
    if not ln.strip() or ln.startswith("#") or ln.startswith("effect\t"):
        continue
    f = ln.rstrip("\n").split("\t")
    if len(f) >= 4:
        shows[f[0]] = f[3].strip() == "yes"
bad = 0
for c in sorted(os.listdir(frames)):
    d = os.path.join(frames, c)
    fr = sorted(x for x in os.listdir(d) if re.fullmatch(r"f.*\.(bmp|png)", x))
    if not fr:
        continue
    hashes = set(map_pixels(os.path.join(d, x)) for x in fr)
    if len(hashes) > 1:
        continue
    key = keys.get(int(c.split("-")[0], 10))
    if key is not None and shows.get(key, False):
        continue
    print("FAIL: clip %s (%s) shows nothing: the map area is identical in all %d light-on frames and its table row does not say shows_nothing = yes."
          % (c, key if key is not None else "no REEL_KEY line", len(fr)))
    bad = 1
sys.exit(bad)
PY
}

# cleanup_runs <dir>...: deletes run dirs that exist, unless --keep-frames. Uses safe-trash (below a project's logs/);
# falls back to rm -rf only for a path matching */logs/runs/*-effect-reel-*.
cleanup_runs() {
    [ "$KEEP_FRAMES" -eq 0 ] || return 0
    local d
    for d in "$@"; do
        [ -n "$d" ] && [ -d "$d" ] || continue
        "$HOME/.claude/bin/safe-trash" "$d" >/dev/null 2>&1 && continue
        case "$d" in
            */logs/runs/*-effect-reel-*) rm -rf "$d" ;;
            *) echo "WARN: not deleting $d (safe-trash refused and the path does not match logs/runs/*-effect-reel-*)." >&2 ;;
        esac
    done
}

if [ "$SELFTEST" -eq 1 ]; then
    T="$(mktemp -d "${TMPDIR:-/tmp}/reel-selftest.XXXXXX")" || exit 2
    mkdir -p "$T/frames/001-flat" "$T/frames/002-moving" "$T/frames/003-sidebar"
    # 8x6 BMPs, 24 bit, bottom-up; the map rect is x=2 y=1 w=4 h=3. mkbmp <out> <pixel-x> <pixel-y> <value>: all
    # pixels 0 except one set to <value>.
    mkbmp() { python3 -I - "$@" <<'PYB'
import struct, sys
out, px, py, val = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4])
w, h = 8, 6
stride = (w * 3 + 3) // 4 * 4
rows = []
for y in range(h):
    r = bytearray(stride)
    if y == py: r[px * 3:px * 3 + 3] = bytes([val] * 3)
    rows.append(bytes(r))
body = b"".join(reversed(rows))
hdr = b"BM" + struct.pack("<IHHI", 54 + len(body), 0, 0, 54) + struct.pack("<IiiHHIIiiII", 40, w, h, 1, 24, 0, len(body), 0, 0, 0, 0)
open(out, "wb").write(hdr + body)
PYB
    }
    for i in 0 1 2; do mkbmp "$T/frames/001-flat/f0000$i.bmp" 0 0 0; done
    mkbmp "$T/frames/002-moving/f00000.bmp" 3 2 0; mkbmp "$T/frames/002-moving/f00001.bmp" 3 2 200
    # 003: only a pixel outside the map rect (sidebar column 7, message row 5) changes
    mkbmp "$T/frames/003-sidebar/f00000.bmp" 7 2 10; mkbmp "$T/frames/003-sidebar/f00001.bmp" 1 5 90
    printf '%s\n' "  REEL_KEY 1 Flat Spell" "  REEL_KEY 2 Moving Spell" "  REEL_KEY 3 Sidebar Spell" "  REEL_MAPRECT 2 1 4 3" > "$T/errors.log"
    printf 'effect\tglow\tcolor\tshows_nothing\tbasis\nFlat Spell\tUNLIT\t-\tno\tx\nMoving Spell\tLIT\tfire\tno\tx\nSidebar Spell\tUNLIT\t-\tno\tx\n' > "$T/no.tsv"
    printf 'effect\tglow\tcolor\tshows_nothing\tbasis\nFlat Spell\tUNLIT\t-\tyes\tx\nMoving Spell\tLIT\tfire\tno\tx\nSidebar Spell\tUNLIT\t-\tyes\tx\n' > "$T/yes.tsv"
    ok=1
    out="$(identical_clips "$T/frames" "$T/errors.log" "$T/no.tsv")"; rc=$?
    if [ "$rc" -eq 1 ] && grep -q "001-flat" <<< "$out" && grep -q "003-sidebar" <<< "$out" && ! grep -q "002-moving" <<< "$out"; then
        echo "ok: a clip whose map area never changes goes red, also when only the sidebar/message pixels change; a clip that changes inside the map passes"
    else echo "FAIL: expected red naming 001-flat and 003-sidebar but not 002-moving, got rc=$rc: $out"; ok=0; fi
    out="$(identical_clips "$T/frames" "$T/errors.log" "$T/yes.tsv")"; rc=$?
    if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
        echo "ok: the same clips with shows_nothing = yes are green"
    else echo "FAIL: expected green, got rc=$rc: $out"; ok=0; fi
    grep -v REEL_MAPRECT "$T/errors.log" > "$T/norect.log"
    out="$(identical_clips "$T/frames" "$T/norect.log" "$T/yes.tsv")"; rc=$?
    if [ "$rc" -eq 2 ]; then echo "ok: no REEL_MAPRECT line exits 2"
    else echo "FAIL: expected exit 2 without REEL_MAPRECT, got rc=$rc: $out"; ok=0; fi
    sed 's/REEL_MAPRECT .*/REEL_MAPRECT 6 1 4 3/' "$T/errors.log" > "$T/outside.log"
    out="$(identical_clips "$T/frames" "$T/outside.log" "$T/yes.tsv")"; rc=$?
    if [ "$rc" -eq 2 ]; then echo "ok: a rectangle outside the frame exits 2"
    else echo "FAIL: expected exit 2 for an outside rectangle, got rc=$rc: $out"; ok=0; fi
    printf 'not a bmp' > "$T/frames/002-moving/f00002.bmp"
    out="$(identical_clips "$T/frames" "$T/errors.log" "$T/yes.tsv")"; rc=$?
    if [ "$rc" -eq 2 ]; then echo "ok: an undecodable frame exits 2"
    else echo "FAIL: expected exit 2 for a bad frame, got rc=$rc: $out"; ok=0; fi
    mkdir -p "$T/logs/runs/s-1-effect-reel-off/frames" "$T/logs/runs/s-1-effect-reel-on/frames"
    KEEP_FRAMES=1; cleanup_runs "$T/logs/runs/s-1-effect-reel-off" "$T/logs/runs/s-1-effect-reel-on"
    if [ -d "$T/logs/runs/s-1-effect-reel-off" ] && [ -d "$T/logs/runs/s-1-effect-reel-on" ]; then
        echo "ok: --keep-frames keeps the run dirs"
    else echo "FAIL: --keep-frames deleted a run dir"; ok=0; fi
    KEEP_FRAMES=0; cleanup_runs "$T/logs/runs/s-1-effect-reel-off" "$T/logs/runs/s-1-effect-reel-on" "$T/logs/runs/missing"
    if [ ! -e "$T/logs/runs/s-1-effect-reel-off" ] && [ ! -e "$T/logs/runs/s-1-effect-reel-on" ]; then
        echo "ok: cleanup deletes both run dirs"
    else echo "FAIL: cleanup left a run dir"; ok=0; fi
    rm -rf "$T"
    [ "$ok" -eq 1 ] && { echo "selftest PASS"; exit 0; }
    echo "selftest FAIL"; exit 1
fi

[ -x ./incursion ] || { echo "ERROR: ./incursion (the SDL build) is missing. Run: ./build_macos.sh"; exit 2; }
[ -x ./incursion-headless ] || { echo "ERROR: ./incursion-headless is missing. Run: BACKEND=posix ./build_macos.sh"; exit 2; }
LOAD="$(tools/fixture_cache.sh "$FIXTURE")" || { echo "ERROR: tools/fixture_cache.sh could not build $FIXTURE."; exit 2; }

START=$(date +%s)
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="$ROOT/logs/effect-reel/$STAMP"
mkdir -p "$OUT"
OFF_RUN=""; ON_RUN=""
trap 'cleanup_runs "$OFF_RUN" "$ON_RUN"' EXIT

# ESC keys end a prompt the probe did not foresee instead of stopping the run on an empty script.
KEYS="$OUT/reel.keys"
for _ in $(seq 1 80); do echo "ESC"; done > "$KEYS"
echo "@quit" >> "$KEYS"

run_pass() {   # <off|on>
    local mode="$1" rd="$ROOT/logs/runs/$STAMP-$$-effect-reel-$1"
    mkdir -p "$rd"
    local off=""
    [ "$mode" = off ] && off=INCURSION_EFFECT_LIGHT_OFF=1
    env INCURSION_BIN="${INCURSION_REEL_BIN:-./incursion}" INCURSIONFONTPATH="$ROOT/fonts" \
        INCURSION_FRAMES="$rd/frames" INCURSION_RUN_DIR="$rd" \
        INCURSION_OPTIONS="$OPTIONS" INCURSION_LOAD="$LOAD" \
        INCURSION_EFFECT_REEL=1 INCURSION_EFFECT_REEL_ONLY="$ONLY" INCURSION_LIGHT_TABLE="$(cd "$(dirname "$TABLE")" && pwd)/$(basename "$TABLE")" \
        $off \
        tools/headless.sh "$KEYS" "$SEED" > "$rd/run.out" 2>&1
    echo "$rd"
}

# run_pass creates its dir before the run, so set the trap's variables first.
OFF_RUN="$ROOT/logs/runs/$STAMP-$$-effect-reel-off"; run_pass off >/dev/null
ON_RUN="$ROOT/logs/runs/$STAMP-$$-effect-reel-on"; run_pass on >/dev/null
for m in off on; do
    r="$ROOT/logs/runs/$STAMP-$$-effect-reel-$m"
    cp -f "$r/logs/errors.log" "$OUT/errors-$m.log" 2>/dev/null || true
done
for rd in "$OFF_RUN" "$ON_RUN"; do
    if ! grep -aq ' REEL_DONE ' "$rd/logs/errors.log" 2>/dev/null; then
        echo "FAIL: no REEL_DONE in $rd/logs/errors.log (the probe did not finish)."
        exit 1
    fi
done

# Clip names are <nnn>-<name>; the number comes from the REEL line.
declare -a CLIPS=()
while IFS= read -r d; do CLIPS+=("$d"); done < <(
    { ls "$OFF_RUN/frames" 2>/dev/null; ls "$ON_RUN/frames" 2>/dev/null; } | sort -u)
[ ${#CLIPS[@]} -gt 0 ] || { echo "FAIL: no clip frames in $OFF_RUN/frames or $ON_RUN/frames."; exit 1; }

BAD=0
for c in "${CLIPS[@]}"; do
    a=$(ls "$OFF_RUN/frames/$c"/f*.bmp 2>/dev/null | wc -l)
    b=$(ls "$ON_RUN/frames/$c"/f*.bmp 2>/dev/null | wc -l)
    if [ "$a" -eq 0 ] || [ "$b" -eq 0 ]; then
        echo "FAIL: clip $c has $a frames with light off and $b with light on."
        BAD=1
    fi
done
REELS=$(grep -ac ' REEL [0-9]' "$ON_RUN/logs/errors.log")
if [ "$REELS" -ne ${#CLIPS[@]} ]; then
    echo "FAIL: the probe logged $REELS REEL lines but ${#CLIPS[@]} clips have frames."
    BAD=1
fi
[ "$BAD" -eq 0 ] || exit 1

ROWS="$OUT/clips.tsv"
: > "$ROWS"
for c in "${CLIPS[@]}"; do
    tools/frames_to_video.sh --pair "$OFF_RUN/frames/$c" "$ON_RUN/frames/$c" "$OUT/$c.mp4" 2>/dev/null || {
        echo "FAIL: frames_to_video.sh failed for $c."
        exit 1
    }
    n=$((10#${c%%-*}))
    line="$(grep -a "  REEL $n " "$ON_RUN/logs/errors.log" | head -n 1 | sed "s/.*  REEL $n //")"
    kind="${line##* }"
    name="${line% *}"
    printf '%s\t%s\t%s\t%s\n' "$c" "$n" "$name" "$kind" >> "$ROWS"
done

IDENT_OUT="$(identical_clips "$ON_RUN/frames" "$ON_RUN/logs/errors.log" "$TABLE")"; IDENT_RC=$?
SKIPS="$(grep -ac 'REEL_SKIP' "$ON_RUN/logs/errors.log")"
python3 -I - "$OUT" "$ROWS" <<'PY'
import html, sys, os
out, rows = sys.argv[1], sys.argv[2]
parts = ["""<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Effect reel</title>
<style>
body { background: #101114; color: #e6e6ea; font: 15px/1.4 system-ui, sans-serif; margin: 0; padding: 16px; }
h1 { margin: 0 0 4px; font-size: 22px; }
p.legend { margin: 0 0 20px; color: #a8a8b4; }
section { margin: 0 0 28px; }
h2 { font-size: 16px; margin: 0 0 6px; }
h2 span { color: #8a8a99; font-weight: normal; margin-left: 8px; }
video { display: block; max-width: 100%; background: #000; }
</style></head><body>
<h1>Effect reel</h1>
<p class="legend">left: light off -- right: light on</p>
"""]
for ln in open(rows, encoding="utf-8", errors="replace"):
    clip, n, name, kind = ln.rstrip("\n").split("\t")
    parts.append('<section><h2>%s %s<span>%s</span></h2>\n<video controls loop muted preload="none" src="%s.mp4"></video></section>\n'
                 % (html.escape(n), html.escape(name), html.escape(kind), html.escape(clip, quote=True)))
parts.append("</body></html>\n")
open(os.path.join(out, "index.html"), "w", encoding="utf-8").write("".join(parts))
PY
rm -f "$ROWS" "$KEYS"
grep -a "REEL_SKIP" "$ON_RUN/logs/errors.log" | sed "s/^[0-9-]* [0-9:]*  //"
echo "clips: ${#CLIPS[@]}  skips: $SKIPS  wall time: $(( $(date +%s) - START )) s"
echo "index: $OUT/index.html"
if [ "$IDENT_RC" -ne 0 ]; then
    printf '%s\n' "$IDENT_OUT"
    [ "$IDENT_RC" -eq 2 ] && exit 2
    exit 1
fi
