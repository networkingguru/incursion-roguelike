#!/bin/bash
# gate: live
# inc-2ok4: every A_DEQU attack gives the striker a Reflex save. 9 of the 13
# list no DC; DequSaveDC (src/Fight.cpp) now gives those 11 + CR/3 (CR floored
# at 0). The 4 that list a DC keep it. Needs the posix build:
#   BACKEND=posix ./build_macos.sh
# Oracle: logs/chance_probe.log (INCURSION_CHANCE_PROBE, src/Skills.cpp), one
# line per Creature::SavingThrow: "save <type 0/1/2> <DC> <predicted%> <0/1>".
# Type 1 is Reflex. A DC of 0 writes a line with result 0 and rolls no die, so
# the DC column is the oracle that a save was rolled.
# PART A  a level-1 orc warrior (DEX 13) strikes acid blobs (CR 0, no DC),
#         armed and then unarmed, 80 summon-and-strike cycles each. Needs >= 40
#         saves per mode, every DC 11, predicted chance 45-60%, and an observed
#         pass rate within 3 standard deviations of the prediction. The check
#         does not demand a literal 45-60% observed band: that would fail on a
#         lucky stream when any change moves the RNG (about 1 run in 8 at n=75).
#         The pooled observed rate is printed.
# PART B  12 of the 13 A_DEQU monsters (the caustic fungus, CR 7, DC 13, spawns
#         where the script cannot strike it: its blindsight disguise hides it), one session each: every save line carries the
#         expected DC (11 + CR/3 for the 9 that list none; the listed DC for
#         the 4 that do) and at least one save was rolled.
# Exit 0 pass, 1 fail ("measured nothing" counts as fail).
#
# fact: character (orc warrior, DEX 13) -- fixture dequ-save-dc-seed5-opt0822, INCURSION_LOAD
# fact: Cheat Death and Freeze Monsters on -- wizard Wizard Mode Switches (tools/keys/dequ-save-dc-setup-loaded.keys)
# fact: the monsters -- wizard Monster Summoning
# fact: where a multi-square monster (remorhaz, magma creeper) lands against him -- the roster tries all eight directions
# fact: each blow hits (A_DEQU answers only a hit) -- INCURSION_LOF_FORCE_ROLL=18
# fact: each save's DC and predicted% -- read from chance_probe.log, the engine's own record
# fact: each save's die -- Part A asserts the observed rate within 3 sd of the predicted, never an exact count
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[ -x ./incursion-headless ] || { echo 'FAIL: measured nothing; build with BACKEND=posix ./build_macos.sh'; exit 1; }
OPTS=tools/fixtures/options-2026-08-22.dat
# The character is loaded: no attribute row decides him (headless.sh copies the
# save into each run's own sandbox).
export INCURSION_LOAD=tools/fixtures/chars/dequ-save-dc-seed5-opt0822.sav
# A_DEQU answers only a blow that HITS (src/Fight.cpp, `at->AType == A_DEQU && !e.isHit`),
# so a miss rolls no save. Force the player's melee d20 to 18: an ordinary hit
# (below the long sword's threat range of 19) that the roster's defences do not
# turn away. Without it a roster run could see every blow miss. The save is
# a different die and stays free, which is what Part A measures.
export INCURSION_LOF_FORCE_ROLL=18
SEED=5
SCRATCH="$ROOT/logs/dequ-save-dc-keys.$$"
mkdir -p "$SCRATCH"
trap 'rm -rf "$SCRATCH"' EXIT

run_probe() { # run_probe <keys> -> prints the probe log path; fails when nothing ran
    local out run
    out="$(INCURSION_CHANCE_PROBE=1 INCURSION_BIN=./incursion-headless INCURSION_OPTIONS="$OPTS" \
           tools/headless.sh "$1" "$SEED" 2>&1 < /dev/null)"
    run="$(echo "$out" | awk '/^run:/ {print $2}')"
    if grep -q 'NO GAMEPLAY\|gave up after\|looked for something' <<< "$out"; then
        echo "FAIL: $1 measured nothing (script did not complete)" >&2
        return 1
    fi
    echo "$run/logs/chance_probe.log"
}

status=0
pooled_n=0; pooled_s=0
for mode in armed unarmed; do
    log="$(run_probe tools/keys/dequ-save-dc-$mode.keys)" || { status=1; continue; }
    [ -f "$log" ] || { echo "FAIL: $mode: no save was rolled (no chance_probe.log)"; status=1; continue; }
    res="$(python3 - "$log" "$mode" <<'PY'
import sys, math
log, mode = sys.argv[1:]
rows = [l.split() for l in open(log) if l.startswith('save ')]
n = len(rows)
s = sum(int(r[4]) for r in rows)
dcs = sorted({int(r[2]) for r in rows})
types = sorted({r[1] for r in rows})
preds = sorted({int(r[3]) for r in rows})
ok = n >= 40 and dcs == [11] and types == ['1'] and len(preds) == 1 and 45 <= preds[0] <= 60
if ok:
    p = preds[0] / 100.0
    sd = math.sqrt(p * (1 - p) / n) * 100
    ok = abs(100.0 * s / n - preds[0]) <= 3 * sd
print(f"{'ok' if ok else 'BAD'} {n} {s}")
print(f"A {mode}: saves={n} passed={s} observed={100.0*s/max(n,1):.1f}% predicted={preds} DCs={dcs} types={types}")
PY
)"
    echo "$res" | tail -1
    read -r verdict n s <<< "$(echo "$res" | head -1)"
    [ "$verdict" = ok ] || { echo "FAIL: $mode: need >=40 Reflex saves, all DC 11, predicted 45-60%, observed within 3 sd"; status=1; }
    pooled_n=$((pooled_n + ${n:-0})); pooled_s=$((pooled_s + ${s:-0}))
done
[ "$pooled_n" -gt 0 ] && echo "A pooled: $pooled_s/$pooled_n = $((100 * pooled_s / pooled_n))%"

# name|menu category|expected DC|keys that strike it
# A multi-square monster (the remorhaz, the magma creeper) is placed by the
# summon on a random free spot two squares off the player, never on the square
# the cursor names, and its body touches him on a different side each seed. So
# the script tries all eight directions for those two: a direction with nothing
# in it just moves the player a step, and the next summon places a fresh
# monster beside wherever he stands. Seeds 303 (remorhaz, due north) and 404
# (magma creeper) found no monster on the one or four directions tried before.
ROSTER='shattering ur-dragon|Dragons|>=11
firebat|Bats|11
small mud elemental|Elementals|11
vaporighu|Hominids|14
caryatid column|Constructs|12
acid blob|Jellies|11
brown pudding|Jellies|14
magma creeper|Jellies|14|ALL8
babau|Demons|24
grey ooze|Jellies|19
remorhaz|Beasts|20|ALL8
rust monster|Beasts|25'
i=0
while IFS='|' read -r name cat want dirs; do
    [ -n "$dirs" ] || dirs=RIGHT
    [ "$dirs" = ALL8 ] && dirs="RIGHT LEFT UP DOWN HOME PGUP END PGDN"
    i=$((i + 1))
    k="$SCRATCH/roster-$i.keys"
    {
        echo "@include $ROOT/tools/keys/dequ-save-dc-setup-loaded.keys"
        for c in 1 2 3 4 5 6 7 8; do
            printf '@until "Wizard Mode Options" w\n@choose "Monster Summoning"\n@choose "%s"\n@choose "%s"\nRIGHT ENTER\n' "$cat" "$name"
            for d in $dirs; do
                printf '%s\n@while "Attack the" y\n@while "Confirm attack" y\n@while "Abort, Flee" a\n@while "Die?" n\n' "$d"
            done
        done
        echo '@quit'
    } > "$k"
    log="$(run_probe "$k")" || { echo "FAIL: B $name"; status=1; continue; }
    if [ ! -f "$log" ]; then echo "FAIL: B $name: no save rolled"; status=1; continue; fi
    got="$(awk '$1=="save" && $2==1 {print $3}' "$log" | sort -n | uniq -c | tr -s ' ' | tr '\n' ';')"
    only="$(awk '$1=="save" && $2==1 {print $3}' "$log" | sort -u | tr '\n' ' ')"
    # A dragon is summoned with an age template, which raises its CR: ">=11".
    if [ "$want" = ">=11" ]; then
        low="$(awk '$1=="save" && $2==1 {print $3}' "$log" | sort -n | head -1)"
        if [ -n "$low" ] && [ "$low" -ge 11 ]; then ok=1; else ok=0; fi
    elif [ "$only" = "$want " ]; then ok=1; else ok=0; fi
    if [ "$ok" = 1 ]; then echo "B ok   $name: DC $want ($got)"
    else echo "FAIL: B $name: expected only DC $want, got [$got]"; status=1; fi
done <<< "$ROSTER"

[ "$status" = 0 ] && echo "PASS: every A_DEQU attack rolls a Reflex save at the expected DC" || echo "FAIL"
exit "$status"
