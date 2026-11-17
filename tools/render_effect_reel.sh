#!/bin/bash
# inc-jw0hw: render the effect reel. The probe (INCURSION_EFFECT_REEL,
# src/EffectReelProbe.cpp) casts every blast, globe, aura field and breath type
# in one dark room, one recorder clip each. This script runs the SDL build twice
# through tools/headless.sh, once with INCURSION_EFFECT_LIGHT_OFF=1, joins each
# clip's two frame sets into one side-by-side mp4 (tools/frames_to_video.sh
# --pair), and writes logs/effect-reel/<date>/index.html with a video per clip.
#   tools/render_effect_reel.sh [--only <name>[,<name>...]]
# Needs ./incursion (./build_macos.sh), ./incursion-headless
# (BACKEND=posix ./build_macos.sh) and ffmpeg. Launches the SDL build: the main
# session runs it, never an implementer.
# Exit 0 done, 1 a clip has frames in one run only or a run lacks REEL_DONE, 2 no build or fixture.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=1
OPTIONS=tools/fixtures/options-2026-08-22.dat
FIXTURE=xsummon-priest-seed5-opt0822
ONLY=""
while [ $# -gt 0 ]; do
    case "$1" in
        --only) ONLY="${2:-}"; shift 2 ;;
        *) echo "usage: tools/render_effect_reel.sh [--only <name>[,<name>...]]" >&2; exit 2 ;;
    esac
done

[ -x ./incursion ] || { echo "ERROR: ./incursion (the SDL build) is missing. Run: ./build_macos.sh"; exit 2; }
[ -x ./incursion-headless ] || { echo "ERROR: ./incursion-headless is missing. Run: BACKEND=posix ./build_macos.sh"; exit 2; }
LOAD="$(tools/fixture_cache.sh "$FIXTURE")" || { echo "ERROR: tools/fixture_cache.sh could not build $FIXTURE."; exit 2; }

START=$(date +%s)
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="$ROOT/logs/effect-reel/$STAMP"
mkdir -p "$OUT"

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
        INCURSION_EFFECT_REEL=1 INCURSION_EFFECT_REEL_ONLY="$ONLY" \
        $off \
        tools/headless.sh "$KEYS" "$SEED" > "$rd/run.out" 2>&1
    echo "$rd"
}

OFF_RUN="$(run_pass off)"
ON_RUN="$(run_pass on)"
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
