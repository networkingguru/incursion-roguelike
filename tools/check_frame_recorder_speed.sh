#!/bin/bash
# gate: live
# inc-i63lc: the recorder's virtual clock must follow the animation option. Records the reel probe's Fireball, Lightning Bolt
# and Magic Missile clips (fixed StopWatch sequences, the bolts with waits under 33 ms) once at Normal and once at Fast
# (INCURSION_EFFECT_REEL_ANIM 0 and 1) and measures each clip's animation span (first to last changed frame). Every clip must have
# frames at Fast and a span no longer than at Normal. A recorder that passes the undivided wait under Fast
# records a Fast clip longer than the Normal one and goes red.
# Needs the SDL build (./incursion). The main session runs it; it launches SDL.
# fact: character -- fixture xsummon-priest-seed5-opt0822
# fact: settings -- options-2026-08-22.dat, named in INCURSION_OPTIONS
# fact: effect and scene -- EffectReelProbe builds its own cleared room and fixed kobolds; INCURSION_EFFECT_REEL_ONLY=Fireball,Lightning Bolt,Magic Missile
# fact: short waits -- the bolt clips step cells with StopWatch(5) (src/Display.cpp), under the 33 ms the Fast floor was sized for
# fact: animation option -- INCURSION_EFFECT_REEL_ANIM, set to 0 then 1 by this script
# fact: refresh period -- the Fast floor reads the display's refresh rate (60 Hz when SDL reports none); the check compares counts, never an absolute length
# fact: saving throws -- INCURSION_FORCE_SAVE_ROLL=1
# Exit 0 PASS, 1 FAIL, 2 INCONCLUSIVE.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[ -x ./incursion ] || { echo "INCONCLUSIVE: ./incursion (the SDL build) is missing. Run: ./build_macos.sh"; exit 2; }
LOAD="$(INCURSION_BIN=./incursion-headless tools/fixture_cache.sh xsummon-priest-seed5-opt0822)" || {
    echo "INCONCLUSIVE: tools/fixture_cache.sh could not build the fixture."; exit 2; }
STAMP="$(date +%Y%m%d-%H%M%S)-$$"
KEYS="$ROOT/logs/runs/$STAMP-frame-speed.keys"
mkdir -p "$ROOT/logs/runs"
{ for _ in $(seq 1 80); do echo "ESC"; done; echo "@quit"; } > "$KEYS"
run_for() {   # <anim 0|1>: records the clips; prints the run dir
    local rd="$ROOT/logs/runs/$STAMP-frame-speed-$1"
    mkdir -p "$rd"
    env INCURSION_BIN=./incursion INCURSIONFONTPATH="$ROOT/fonts" INCURSION_FRAMES="$rd/frames" INCURSION_RUN_DIR="$rd" \
        INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat INCURSION_LOAD="$LOAD" \
        INCURSION_LIGHT_TABLE="$ROOT/tools/fixtures/effect-light-table.tsv" INCURSION_FORCE_SAVE_ROLL=1 \
        INCURSION_EFFECT_REEL=1 INCURSION_EFFECT_REEL_ONLY="Fireball,Lightning Bolt,Magic Missile" INCURSION_EFFECT_REEL_ANIM="$1" \
        tools/headless.sh "$KEYS" 1 > "$rd/run.out" 2>&1
    echo "$rd"
}
nrun="$(run_for 0)"; frun="$(run_for 1)"
echo "Specimens: $nrun $frun"
# span <clipdir>: frames from the first to the last frame that differs from its predecessor (the animation itself, not the
# fixed holds around it, which do not scale with the option). Prints "<frames> <span>"; span 0 when nothing changed.
span() {
    python3 -I - "$1" <<'PY'
import hashlib, os, sys
d = sys.argv[1]
fs = sorted(f for f in os.listdir(d) if f.startswith("f") and f.endswith(".bmp"))
h = [hashlib.md5(open(os.path.join(d, f), "rb").read()).hexdigest() for f in fs]
ch = [i for i in range(1, len(h)) if h[i] != h[i - 1]]
print(len(h), (ch[-1] - ch[0] + 1) if ch else 0)
PY
}
nclips=0; bad=0
for d in "$nrun"/frames/*/; do
    c="$(basename "$d")"
    read -r n ns <<< "$(span "$d")"
    read -r f fs <<< "$(span "$frun/frames/$c" 2>/dev/null || echo "0 0")"
    echo "clip $c: Normal $n frames (animation span $ns), Fast $f frames (animation span $fs)"
    nclips=$((nclips + 1))
    if [ "$n" -le 0 ] || [ "$ns" -le 0 ]; then echo "INCONCLUSIVE: $c shows no animation at Normal."; exit 2; fi
    if [ "$f" -le 0 ]; then echo "FAIL: $c recorded no frames at Fast."; bad=1; fi
    if [ "$fs" -gt "$ns" ]; then echo "FAIL: $c animation is longer at Fast ($fs frames) than at Normal ($ns)."; bad=1; fi
done
[ "$nclips" -ge 3 ] || { echo "INCONCLUSIVE: only $nclips clips recorded (need 3)."; exit 2; }
[ "$bad" -eq 0 ] || exit 1
echo "PASS: no clip's animation is longer at Fast than at Normal."
