#!/bin/bash
# gate: live
# Does the target cursor reach a creature drawn on the map window's first row?
# (bd inc-3k0nv.)
#
# THE DEFECT. TextTerm::EffectPrompt (src/Term.cpp:2676) accepts a candidate
# only when `XOff < th->x && YOff < th->y`. Both tests are strict, so a creature
# on the window's first row (y == YOff) or first column (x == XOff) is never a
# candidate. TextTerm::PutGlyph (src/Term.cpp:1282) draws that row and column
# (it returns only for x<XOff or y<YOff), and "Things in View" lists the
# creature. The player sees it, [l]/[t] then an arrow skips it. Light plays no
# part: the first report blamed a lit square, and the cause is the window edge.
#
# WHAT THIS RUNS. tools/keys/edge-target.keys loads a frozen paladin whose map
# window starts nine rows north of him, lights the first row with a wall torch,
# and puts two flesh golems in view: the EDGE golem on the window's first row,
# nine rows north and two columns east of the player, and the CONTROL golem two
# rows below it, seven rows north and three columns east. It presses UP on three
# cursors: [t], [l] and [l][t]. INCURSION_TARGET_PROBE=1 writes each cursor's
# candidate list to logs/targetprobe.log. The invariant: every creature the
# player sees on the map is an "aim" candidate. The CONTROL golem MUST be one,
# or the run measured nothing (INCONCLUSIVE). The EDGE golem MUST be one, or the
# check FAILs, and it FAILS on a build that still has the strict test.
#
# PROOF THAT THE EDGE GOLEM IS ON THE FIRST ROW. The scene dump. The map window
# starts at screen row 4 (src/TextTerm.cpp:108, SizeWin(WIN_MAP,0,4,...)), so
# a glyph on dump screen row 4 is on y == YOff. The check requires a golem glyph
# on that row, and two golems under "Things in View". No scratch probe of XOff
# was needed.
#
# facts read, and the control that fixes each:
# fact: character, his map and where he stands -- fixture tools/fixtures/chars/human-paladin-seed4-opt0822.sav via INCURSION_LOAD
# fact: which map row is the window's first row -- AdjustMap runs at load from the saved player square alone (src/Registry.cpp:1476), so the fixture fixes it
# fact: settings, including OPT_CENTER_MAP -- tools/fixtures/options-2026-08-22.dat via INCURSION_OPTIONS
# fact: the first row is lit enough to see the golem -- wizard "Change terrain type", Wall Torch (the call tools/check_hide_dynamic_light.sh makes)
# fact: two creatures on chosen squares -- wizard "Monster Summoning", Golems, first entry; offsets typed in the key script, the player's square read from the probe
# fact: random rolls -- none read; wizard menus and cursors pass no turns, and INCURSION_SEED is pinned to 1
# fact: creature name text -- not asserted; the word "corpse" only separates an item from a creature
#
# Usage: tools/check_edge_target.sh                 (0 pass, 1 fail, 2 inconclusive)
#        tools/check_edge_target.sh --judge <targetprobe.log> <scene-dump>
#        tools/check_edge_target.sh --selftest
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

judge() { # judge <probe log> <scene dump>
python3 -I - "$@" <<'PY'
import re, sys

log, scene = sys.argv[1], sys.argv[2]
text = open(log, 'rb').read().decode('latin-1')
try:
    dump = open(scene, errors='replace').read().split('\n')
except OSError:
    dump = []

presses = []
for block in text.split('arrow ')[1:]:
    head = block.split('\n', 1)[0]
    pl = re.search(r'player=\((\d+),(\d+)\)', head)
    presses.append({
        'entering': 'entering the ring' in head,
        'player': (int(pl.group(1)), int(pl.group(2))) if pl else None,
        'aims': [(int(x), int(y), name) for x, y, name in
                 re.findall(r'aim\s+\(\s*(\d+),\s*(\d+)\) dist=\d+\s+(.*)', block)],
    })
entering = [q for q in presses if q['entering']]

dead = []
if len(entering) < 3:
    dead.append("only %d of the 3 expected presses entered the ring, so the\n"
                "              cursors never opened or never took the arrow." % len(entering))
# dump line 0 is the header; screen row r is dump line r+1. The map window
# starts at screen row 4, and its columns end before the side panel at 64.
first_row = dump[5][:64] if len(dump) > 5 else ''
if 'G' not in first_row:
    dead.append("no golem glyph on screen row 4, the map window's first row, so\n"
                "              the edge golem is not where the check needs it.")
if sum('golem' in l for l in dump) < 2:
    dead.append("the scene lists fewer than two golems, so a summon failed.")

fails = []
if not dead:
    px, py = entering[0]['player']
    edge, control = (px + 2, py - 9), (px + 3, py - 7)
    def has(q, want):
        return any((a[0], a[1]) == want and 'corpse' not in a[2] for a in q['aims'])
    for name, q in zip(('[t] UP', '[l] UP', '[l][t] UP'), entering[:3]):
        if not has(q, control):
            dead.append("%s: the control golem at %s, 7 rows north, is not a\n"
                        "              candidate either, so the cursor measured nothing." % (name, control))
        elif not has(q, edge):
            fails.append("%s: the golem at %s, on the window's first row and in view,\n"
                         "      is not an aim candidate. Candidates: %s"
                         % (name, edge, [(a[0], a[1]) for a in q['aims']]))

if fails and not dead:
    for f in fails:
        print("FAIL: " + f)
    sys.exit(1)
if dead:
    for d in dead:
        print("INCONCLUSIVE: " + d)
    sys.exit(2)
print("PASS: the golem on the window's first row is a candidate of [t] UP,")
print("      [l] UP and [l][t] UP, like the golem two rows below it.")
PY
}

selftest() {
    local d rc=0 s i
    d="$(mktemp -d "${TMPDIR:-$ROOT/logs}/edge-target-selftest.XXXXXX")" || return 2
    {
        echo "=== screen"
        for i in 0 1 2 3; do echo "row$i"; done
        echo "              G                                                   |panel"
        for i in 5 6; do echo "row$i"; done
        echo " |G flesh golem"; echo " |G flesh golem"
    } > "$d/scene"
    one() { printf 'arrow clockwise cursor=(5,20) player=(5,20) -- entering the ring\n  aim  ( 8,13) dist=7   a flesh golem\n%s' "$1"; }
    edge='  aim  ( 7,11) dist=9   a flesh golem\n'
    { one "$(printf "$edge")"; one "$(printf "$edge")"; one "$(printf "$edge")"; } > "$d/good"
    { one ""; one ""; one ""; } > "$d/red"
    { one ""; } > "$d/short"
    judge "$d/good" "$d/scene" >/dev/null; s=$?
    [ "$s" -eq 0 ] || { echo "selftest: FAIL good gave $s, wanted 0"; rc=1; }
    judge "$d/red" "$d/scene" >/dev/null; s=$?
    [ "$s" -eq 1 ] || { echo "selftest: FAIL red gave $s, wanted 1"; rc=1; }
    judge "$d/short" "$d/scene" >/dev/null; s=$?
    [ "$s" -eq 2 ] || { echo "selftest: FAIL short gave $s, wanted 2"; rc=1; }
    [ "$rc" -eq 0 ] && echo "selftest: PASS good=0 red=1 short=2"
    rm -f "$d/scene" "$d/good" "$d/red" "$d/short"; rmdir "$d"
    return "$rc"
}

case "${1:-}" in
    --selftest) selftest; exit $? ;;
    --judge) shift; judge "$@"; exit $? ;;
esac

[ -x ./incursion-headless ] || {
    echo "INCONCLUSIVE: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 2
}

out="$(INCURSION_TARGET_PROBE=1 INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat \
       INCURSION_LOAD=tools/fixtures/chars/human-paladin-seed4-opt0822.sav \
       tools/headless.sh tools/keys/edge-target.keys 1 2>&1)"
run="$(printf '%s\n' "$out" | awk '/^run:/ {print $2}')"
log="$run/logs/targetprobe.log"
scene="$(ls "$run"/logs/screens/*-scene.txt 2>/dev/null | head -1)"

[ -n "$run" ] && [ -f "$log" ] && [ -n "$scene" ] || {
    echo "INCONCLUSIVE: the session wrote no probe log or scene dump."
    echo "              Run dir: ${run:-none}"
    exit 2
}

judge "$log" "$scene"
status=$?
echo "Run dir: $run"
exit $status
