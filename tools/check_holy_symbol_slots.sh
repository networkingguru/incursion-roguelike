#!/bin/bash
# gate: live
# Does a god-marked item worn in a slot OTHER than the old four work as a holy
# symbol? Bead inc-tf6l.
#
# THE DEFECT. Two sites decide "does this caster hold a holy symbol?" and both
# searched a hardcoded four-slot list and nothing else:
#
#   Creature::Turn                 src/Skills.cpp:4502-4512
#   the divine component check      src/Magic.cpp:3407-3419
#
#   int okSlots[] = { SL_READY, SL_WEAPON, SL_AMULET, SL_ARMOUR, 0 };
#
# so a god-marked item worn in the helmet, a ring, a cloak or a pair of boots
# did nothing. A third site, Creature::skillKitMod (src/Skills.cpp:775-780),
# walked every slot correctly but demanded isType(T_SYMBOL), so a god-marked
# shield or bow got no Knowledge: Theology bonus.
#
# THE ORACLE is the game's own line, printed after the component search in
# Creature::Turn:
#
#   helm worn   "You channel the sacred energies of Aiswin. Nothing happens."
#   helm packed "You need an appropriate Holy Symbol to affect undead."
#
# The worn helm is the RED/GREEN reading: before the fix the game refuses it
# with the Holy Symbol line because the helmet slot is not in the list; after
# the fix the same helm qualifies. The packed helm is the CONTROL: the pack is
# not a worn slot on either build, so it must stay refused, and it is also the
# positive assertion that the session reached the state where the refusal can
# appear at all.
#
# WHY A SCRATCH MODULE. No shipped item can be god-marked AND worn in a new
# slot: the only god-marked gear in lib/ is the player's starting `holy symbol`
# (T_SYMBOL, lib/races.irh:113-122) and the shield a priest template stamps
# (T_SHIELD, lib/mon2.irh:4826-4830), and both are active only in the four old
# slots. tools/fixtures/holy-symbol-slot-helm.irh adds a HELMET effect named
# "Aiswin Test Helm", which the code's own prefix test reads as a mark of the
# god Aiswin. The check copies lib/ to logs/, appends that fixture to the END
# of the COPY's main.irc -- never a mid-file insert, because a v1 save records
# each resource array's length and each entry's name in POSITION order -- and
# compiles it with INCURSIONPATH, the same shape tools/check_skc6_blast_text.sh
# and tools/check_heal_maladies.sh use. No tracked lib/ file is ever touched.
#
# The scratch module and the god-augmented lib survive being handed to
# tools/headless.sh: that script's `ln -sfn "$ROOT/mod" "$RUN/mod"` cannot
# clobber a REAL pre-existing directory at that path on macOS, so it places the
# symlink INSIDE it instead.
#
# The era's BEFORE reading: the pre-fix build refuses the worn helm, so this
# check exits 1 on it and 0 on the rebuilt fixed binary. Confirmed by reverting
# the helper call at the Turn site by hand and rebuilding.
#
# Usage: tools/check_holy_symbol_slots.sh   (0 pass, 1 fail, 2 inconclusive)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

OPTIONS="${INCURSION_OPTIONS:-tools/fixtures/options-2026-08-22.dat}"
KEYS=tools/keys/holy-symbol-slot.keys
GOD_FIXTURE=tools/fixtures/holy-symbol-slot-helm.irh

[ -x ./incursion-headless ] || {
    echo "INCONCLUSIVE: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 2
}
[ -f "$OPTIONS" ] || { echo "INCONCLUSIVE: settings file $OPTIONS is not there"; exit 2; }
[ -f "$KEYS" ] || { echo "INCONCLUSIVE: key script $KEYS is not there"; exit 2; }
[ -f "$GOD_FIXTURE" ] || { echo "INCONCLUSIVE: fixture $GOD_FIXTURE is not there"; exit 2; }

TOKEN="${INCURSION_CHECK_TOKEN:-$$-$(date +%s)}"
SCRATCH="$ROOT/logs/runs/check-holysym-$TOKEN"
rm -rf "$SCRATCH"
mkdir -p "$SCRATCH/mod" "$SCRATCH/save" "$SCRATCH/logs"
cp -Rf "$ROOT/lib" "$SCRATCH/lib" || { echo "INCONCLUSIVE: could not copy lib/"; exit 2; }
ln -sfn "$ROOT/inc" "$SCRATCH/inc"
cat "$GOD_FIXTURE" >> "$SCRATCH/lib/main.irc"

INCURSIONPATH="$SCRATCH/" ./incursion-headless -compile main.irc \
    < /dev/null > "$SCRATCH/compile.log" 2>&1
if [ ! -f "$SCRATCH/mod/Incursion.Mod" ]; then
    echo "--- compile output ---"
    tail -30 "$SCRATCH/compile.log"
    echo "INCONCLUSIVE: the scratch module (with the test helm appended) did not compile"
    exit 2
fi

out="$(INCURSION_OPTIONS="$OPTIONS" INCURSION_RUN_DIR="$SCRATCH" \
        tools/headless.sh "$KEYS" 1 2>&1)"
status=$?
echo "$out" | sed 's/^/  | /'
echo

if grep -q "the key script looked for something" <<< "$out"; then
    echo "INCONCLUSIVE: the key script could not find the fixture helm on"
    echo "              screen. Run dir: $SCRATCH"
    exit 2
fi
if [ "$status" -ne 0 ]; then
    echo "INCONCLUSIVE: the session ended $status (see above); it measured nothing."
    echo "              Run dir: $SCRATCH"
    exit 2
fi

screen() {
    local f="$SCRATCH/logs/screens/$1"
    [ -f "$f" ] || { echo "INCONCLUSIVE: no screen dumped at $f" >&2; exit 2; }
    echo "$f"
}

worn="$(screen 0002-helm-worn.txt)"
packed="$(screen 0004-helm-stowed.txt)"
turnworn="$(screen 0003-turn-worn.txt)"
turnpack="$(screen 0005-turn-pack.txt)"

# Did the god-marked helm really reach the helmet slot, and was the old amulet
# slot really vacated first? Without both, no reading below means anything.
grep -q "q)Helmet       :Helm of Aiswin Test Helm" "$worn" || {
    echo "INCONCLUSIVE: the fixture helm never reached the helmet slot, so the"
    echo "              session measured nothing. Screen: $worn"
    exit 2
}
grep -q "o)Neck         :Empty" "$worn" || {
    echo "INCONCLUSIVE: the starting holy symbol was still worn in the Neck slot,"
    echo "              so turning would work through an OLD slot whatever the"
    echo "              fix does. Screen: $worn"
    exit 2
}
grep -q "q)Helmet       :Empty" "$packed" || {
    echo "INCONCLUSIVE: the helm never left the helmet slot, so the pack control"
    echo "              is not a control. Screen: $packed"
    exit 2
}

rc=0

# The control first: a god-marked helm in the PACK is refused on both builds.
if ! grep -q "You need an appropriate Holy Symbol to affect undead" "$turnpack"; then
    echo "FAIL: with the god-marked helm in the pack, turning was NOT refused --"
    echo "      the pack is not a worn slot and must never qualify."
    echo "      Screen: $turnpack"
    rc=1
fi

# The red/green reading: the same helm WORN in the helmet slot qualifies.
if grep -q "You need an appropriate Holy Symbol to affect undead" "$turnworn"; then
    echo "FAIL: a god-marked helm WORN in the helmet slot was refused -- the"
    echo "      holy-symbol search still only looks at the old four slots."
    echo "      Screen: $turnworn"
    rc=1
elif ! grep -q "You channel the sacred energies of Aiswin" "$turnworn"; then
    echo "INCONCLUSIVE: the worn-helm turn printed neither the refusal nor the"
    echo "              channel line, so this run cannot tell qualify from crash."
    echo "              Screen: $turnworn"
    exit 2
fi

if [ "$rc" = 0 ]; then
    echo "  ok: a god-marked helm WORN in the helmet slot turns undead, and the"
    echo "      same helm in the pack is still refused."
fi
exit $rc
