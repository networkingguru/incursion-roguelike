#!/bin/bash
# Does a Wand of Animal Summoning summon an animal?
# Finding PA-08-F13 of bd inc-tek.8.8.
#
# THE DEFECT. Every generic-summons wand in lib/m_items.irh names the kind of
# creature it calls in its xval field: MA_BEAST for the Beast wand, MA_UNDEAD
# for the Undead one, MA_VERMIN for the Vermin one. The Animal Summoning wand
# carried "xval: MA_DRAGON; rval: $"generic summons";" -- the line above it,
# copied whole off the Dragon Summoning wand, which is the entry immediately
# before it in the same file. Magic::Summon copies xval into xe.enConstraint
# before throwing EV_ENGEN (src/Effects.cpp:1451), and enConstraint is the
# monster-type filter the encounter generator selects on, so the wand drew
# from the dragon list.
#
# THE ORACLE is the name of the creature that lands. Magic::Summon prints one
# "An <Obj> appears!" line per summoned creature (src/Effects.cpp:1493), and
# this script matches that name against the 474 monsters declared in
# lib/mon*.irh to recover its MTypes. An animal has MA_ANIMAL; a dragon has
# MA_DRAGON. Nothing is judged by the wand's own description, which was
# already correct and is not what the game reads.
#
# MEASURED on 2026-08-24, six seeds x eight shots = 48 shots a side, the
# module the only thing between the two builds:
#
#   before the fix   12 creatures arrived over 48 shots, 0 animals, 12 dragons
#                    -- 5 shattering ur-dragons, 4 plant ur-dragons, 2
#                    brilliant ur-dragons, 1 copper dragon
#   after  the fix   32 creatures arrived over 48 shots, 32 animals, 0 others
#                    -- 14 elephants, 8 giant crocodiles, 2 smilodons, and one
#                    each of warpony, giant constrictor snake, pygmy war rhino,
#                    cave lion, wolverine, rhinoceros, wild boar and
#                    arsinoitherium
#
# The arrival rate moves as well as the species, and that is expected: the
# animal list at CR 10 is far denser than the dragon list, so the generator
# fails to fill far less often. Do not read the 12 -> 32 as the finding; the
# finding is 0 animals -> 32 animals.
#
# Red was measured first, on the pre-fix build, and confirmed a second time
# afterwards by reverting the one constant and rebuilding, which reproduced
# the 12 / 0 / 12 figures exactly.
#
# Usage: tools/check_wand_animal.sh     (0 pass, 1 fail, 2 inconclusive)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEEDS="1 2 3 4 5 6"
PLUS=5          # what tools/keys/wand-animal-summon.keys types at "Enter Item Level:"

# ---- static: every generic-summons wand names its own kind ---------------
# The live pass below fires ONE of the wands. The other four could each be
# given the wrong xval and the run would still be green, so read them here.
fail=0
for pair in "Dragon:MA_DRAGON" "Animal:MA_ANIMAL" "Beast:MA_BEAST" \
            "Undead:MA_UNDEAD" "Vermin:MA_VERMIN"; do
    what="${pair%%:*}"
    want="${pair##*:}"
    got=$(awk -v w="AI_WAND Effect \"$what Summoning\" : EA_SUMMON" '
        $0 == w { inwand = 1; next }
        inwand && /xval:/ { sub(/.*xval:[ \t]*/, ""); sub(/;.*/, ""); print; exit }
        inwand && /Desc:/ { exit }
    ' lib/m_items.irh)
    if [ "$got" = "$want" ]; then
        echo "  ok: the $what Summoning wand passes $want"
    else
        echo "FAIL: the $what Summoning wand passes '${got:-nothing}', not $want"
        fail=1
    fi
done

[ -x ./incursion-headless ] || {
    echo "INCONCLUSIVE: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 2
}

# ---- live: fire the wand and name what arrives ---------------------------
screens=""
for seed in $SEEDS; do
    out="$(tools/headless.sh tools/keys/wand-animal-summon.keys "$seed" 2>&1)"
    run="$(echo "$out" | awk '/^run:/ {print $2}')"
    if echo "$out" | grep -q "the key script looked for something"; then
        echo "INCONCLUSIVE: seed $seed could not find something on screen. Run: $run"
        exit 2
    fi
    held="$run/logs/screens/0001-wand-in-hand.txt"
    [ -f "$held" ] || { echo "INCONCLUSIVE: seed $seed dumped no $held"; exit 2; }
    # The acquisition list is walked by cursor, not by menu letter, so read the
    # item's name back before believing anything else about the run.
    grep -q "Wand +$PLUS of Animal Summoning" "$held" || {
        echo "INCONCLUSIVE: seed $seed never held a Wand +$PLUS of Animal Summoning."
        echo "              Screen: $held"
        exit 2
    }
    for f in "$run"/logs/screens/*-fired?.txt; do
        [ -f "$f" ] && screens="$screens $f"
    done
done

python3 - $screens <<'PY'
import re, sys, glob, collections

# Every monster the module declares, with its MTypes. One declaration per line
# in all four files -- checked: 474 of 474 match this shape.
mons = {}
for path in sorted(glob.glob("lib/mon*.irh")):
    for line in open(path, encoding="latin-1"):
        m = re.match(r'^Monster\s+"([^"]+)"\s*:\s*(.+?)\s*$', line)
        if m:
            mons[m.group(1)] = [t.strip() for t in m.group(2).split(",")]

# A summoned creature can wear an age or a template ("juvenile brilliant
# ur-dragon", "dire wolf"), which prefixes the base name. So look for the
# LONGEST declared name that sits directly in front of " appears!".
names = sorted(mons, key=len, reverse=True)

found = []
for path in sys.argv[1:]:
    lines = open(path, encoding="latin-1").read().splitlines()
    # The message region is the top of the screen, left of the status column,
    # and it ends at the first blank line. A long message wraps, so the lines
    # have to be joined before the creature's name can be matched.
    msg = []
    for line in lines[1:]:
        left = line[:64].rstrip()
        if not left:
            break
        msg.append(left)
    text = re.sub(r"\s+", " ", " ".join(msg))
    for name in names:
        if name + " appears!" in text:
            found.append(name)
            break

if not found:
    print("INCONCLUSIVE: not one shot in %d summoned anything the module names."
          % len(sys.argv[1:]))
    print("              Either every Use Magic check failed, or the summon")
    print("              message moved. Nothing was measured.")
    sys.exit(2)

animals = [n for n in found if "MA_ANIMAL" in mons[n]]
others  = [n for n in found if "MA_ANIMAL" not in mons[n]]

print("  %d creatures arrived over %d shots: %d animals, %d not animals"
      % (len(found), len(sys.argv[1:]), len(animals), len(others)))
for name, n in collections.Counter(found).most_common():
    mark = "animal" if "MA_ANIMAL" in mons[name] else "NOT an animal"
    print("    %2dx %-32s %-14s %s" % (n, name, mark, ", ".join(mons[name])))

if others:
    print("FAIL: a Wand of Animal Summoning summoned %d creature(s) that are not"
          % len(others))
    print("      animals. Check that xval on the Animal Summoning wand in")
    print("      lib/m_items.irh reads MA_ANIMAL, and that the module was rebuilt.")
    sys.exit(1)
print("  ok: every creature the wand summoned is an animal")
sys.exit(0)
PY
rc=$?

[ "$rc" = 2 ] && exit 2
[ "$rc" != 0 ] && fail=1
if [ "$fail" = 0 ]; then
    echo "PASS: the Wand of Animal Summoning summons animals"
    exit 0
fi
exit 1
