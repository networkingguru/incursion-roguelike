#!/bin/bash
# inc-jw0hw: render the effect reel. The probe (INCURSION_EFFECT_REEL,
# src/EffectReelProbe.cpp) casts every blast, globe, aura field and breath type
# in one dark room, one recorder clip each. This script runs the SDL build twice
# through tools/headless.sh, once with INCURSION_EFFECT_LIGHT_OFF=1, joins each
# clip's two frame sets into one side-by-side mp4 (tools/frames_to_video.sh
# --pair), and writes logs/effect-reel/<date>/index.html with a video per clip.
#   tools/render_effect_reel.sh [--only <name>[,<name>...]] [--keep-frames]
#   tools/render_effect_reel.sh --selftest   (no build: fabricated frames prove the identical-frames check)
# A clip whose light-on frames are all byte-identical fails the run, unless its row in
# tools/fixtures/effect-light-table.tsv (matched by the REEL_KEY line the probe logs: the declared name
# with its ;tag) says shows_nothing = yes. The run still writes the index, then exits 1.
# Each run's frames/ tree is 1-4 GB (--only) to ~55 GB (full reel). The script copies each run's errors.log to
# $OUT/errors-{off,on}.log, then deletes both run dirs (also on an early error exit). --keep-frames skips the deletion.
# Needs ./incursion (./build_macos.sh), ./incursion-headless
# (BACKEND=posix ./build_macos.sh) and ffmpeg. Launches the SDL build: the main
# session runs it, never an implementer.
# fact: the effect list and each clip's key -- the probe logs REEL_KEY <n> <declared name> per clip; the table is tools/fixtures/effect-light-table.tsv
# fact: the frames -- recorded by the SDL build, not the seeded game; the identical-frames test hashes the files
# Exit 0 done, 1 a clip has frames in one run only, a run lacks REEL_DONE, or a clip shows nothing (all light-on
# frames identical) and its table row does not say shows_nothing = yes, 2 no build or fixture or bad usage.
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

# identical_clips <frames dir> <errors.log> <table>: prints one line per clip whose frames (f*.bmp or f*.png) are
# all byte-identical and whose table row does not say shows_nothing = yes; exits 1 when it printed any.
identical_clips() {
    python3 -I - "$@" <<'PY'
import hashlib, os, re, sys
frames, log, table = sys.argv[1:4]
keys = {}
for ln in open(log, encoding="latin-1"):
    m = re.search(r'  REEL_KEY (\d+) (.*?)\s*$', ln)
    if m:
        keys[int(m.group(1))] = m.group(2)
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
    hashes = set(hashlib.sha1(open(os.path.join(d, x), "rb").read()).hexdigest() for x in fr)
    if len(hashes) > 1:
        continue
    key = keys.get(int(c.split("-")[0], 10))
    if key is not None and shows.get(key, False):
        continue
    print("FAIL: clip %s (%s) shows nothing: all %d light-on frames are identical and its table row does not say shows_nothing = yes."
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
    mkdir -p "$T/frames/001-flat" "$T/frames/002-moving"
    for i in 0 1 2; do printf 'same' > "$T/frames/001-flat/f0000$i.png"; done
    printf 'a' > "$T/frames/002-moving/f00000.png"; printf 'b' > "$T/frames/002-moving/f00001.png"
    printf '%s\n' "  REEL_KEY 1 Flat Spell" "  REEL_KEY 2 Moving Spell" > "$T/errors.log"
    printf 'effect\tglow\tcolor\tshows_nothing\tbasis\nFlat Spell\tUNLIT\t-\tno\tx\nMoving Spell\tLIT\tfire\tno\tx\n' > "$T/no.tsv"
    printf 'effect\tglow\tcolor\tshows_nothing\tbasis\nFlat Spell\tUNLIT\t-\tyes\tx\nMoving Spell\tLIT\tfire\tno\tx\n' > "$T/yes.tsv"
    ok=1
    out="$(identical_clips "$T/frames" "$T/errors.log" "$T/no.tsv")"; rc=$?
    if [ "$rc" -eq 1 ] && grep -q "001-flat" <<< "$out" && ! grep -q "002-moving" <<< "$out"; then
        echo "ok: an all-identical clip with shows_nothing = no goes red and is named"
    else echo "FAIL: expected red naming 001-flat, got rc=$rc: $out"; ok=0; fi
    out="$(identical_clips "$T/frames" "$T/errors.log" "$T/yes.tsv")"; rc=$?
    if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
        echo "ok: the same clip with shows_nothing = yes is green"
    else echo "FAIL: expected green, got rc=$rc: $out"; ok=0; fi
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
        INCURSION_EFFECT_REEL=1 INCURSION_EFFECT_REEL_ONLY="$ONLY" \
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
    exit 1
fi
