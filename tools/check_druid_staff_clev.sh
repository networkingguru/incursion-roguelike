#!/bin/bash
# gate: live
# Does a pure Druid pass the Staff of Healing's caster-level prerequisite? Bead inc-7y8u.
#
# fact: character -- fixture druid-shoulder-metal-seed7-opt0822 (built from its .char, served by tools/fixture_cache.sh)
# fact: the wizard mode and the long sword on the L. Shoulder -- tools/keys/setup-druid-shoulder-metal-seed7-opt0822.keys (the old .sav held them; V7-1 moved them into the checks)
# fact: settings -- tools/fixtures/options-2026-08-22.dat
# fact: the staff and its stati -- wizard Item Acquisition of a Staff of Healing, no dice
# THE DEFECT (Traced). Creature::ItemPrereq's CLEV_VAL branch loops over
# {SP_ARCANE, SP_DIVINE, SP_BARDIC, SP_SORCERY, SP_PRIMAL, 0} and stops at the
# first 0. SP_SORCERY is 0x0000, so the loop ends before SP_PRIMAL and a
# Druid's level (Stati[SPELL_ACCESS,SP_PRIMAL]) never counts. The staff's
# EV_MAGIC_HIT handler (lib/m_items.irh, "Healing;staff") calls
# ItemPrereq(CLEV_VAL + SP_DIVINE + SP_PRIMAL,1,10) and returns DONE on failure,
# which swallows the event before the STAFF_SPELLS grant is made.
#
# THE ORACLE is wizard mode's "Examine Player Data": a wielder whose staff
# passed the prerequisite holds a "STAFF SPELLS from SS ITEM" stati. The
# key script tools/keys/druid-staff-clev.keys wishes a Staff of Healing, wields
# it in the weapon hand and dumps the whole stati list.
#
# Verdict, from the stati dumps only:
#   0  the stati is present: the wielder passed the prerequisite
#   1  the stati is absent, AND the wielder's "SPELL ACCESS from SS CLAS" stati
#      and the Staff of Healing in the weapon hand are both on screen, so the
#      absence is the prerequisite and not an unread list or an unwielded staff
#   2  anything else (build missing, key script lost, list not read)
#
# Usage: tools/check_druid_staff_clev.sh            the Druid fixture (red today)
#        tools/check_druid_staff_clev.sh --priest   positive control: a Priest
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

FIX=druid-shoulder-metal-seed7-opt0822
KEYS=tools/keys/druid-staff-clev-druid.keys
SEED=7
if [ "${1:-}" = "--priest" ]; then
    FIX=tools/fixtures/chars/orc-priest-seed4-gate.char
    KEYS=tools/keys/druid-staff-clev.keys
    SEED=4
fi

[ -x ./incursion-headless ] || {
    echo "INCONCLUSIVE: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 2
}
[ -f "$FIX" ] || [ -f "tools/fixtures/chars/$FIX.char" ] || { echo "INCONCLUSIVE: no fixture $FIX"; exit 2; }

out="$(INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat INCURSION_LOAD="$FIX" \
    tools/headless.sh "$KEYS" "$SEED" 2>&1)"
run="$(echo "$out" | awk '/^run:/ {print $2}')"
[ -n "$run" ] || { echo "INCONCLUSIVE: no run directory."; exit 2; }
if grep -q "the key script looked for something" <<< "$out"; then
    echo "INCONCLUSIVE: the key script could not find something on screen. Run: $run"
    exit 2
fi

scr="$run/logs/screens"
wield="$scr/0001-staff-wielded.txt"
[ -f "$wield" ] || { echo "INCONCLUSIVE: no wield screen. Run: $run"; exit 2; }

if ! grep -q "^>>b)Weapon Hand  :Staff of Healing" "$wield"; then
    echo "INCONCLUSIVE: the Staff of Healing is not in the weapon hand. Run: $run"
    exit 2
fi
# The stati list must have been read to its end: header says N, five dumps.
n=0
for f in "$scr"/000[2-6]-stati-*.txt; do
    [ -f "$f" ] && n=$((n + 1))
done
[ "$n" -eq 5 ] || { echo "INCONCLUSIVE: $n of 5 stati dumps. Run: $run"; exit 2; }

staff="$(grep -h "STAFF SPELLS from SS ITEM" "$scr"/000[2-6]-stati-*.txt | head -1)"
if [ -n "$staff" ]; then
    echo "PASS: STAFF SPELLS stati present; the wielder passed the prerequisite. Run: $run"
    exit 0
fi
access="$(grep -h "SPELL ACCESS from SS CLAS" "$scr"/000[2-6]-stati-*.txt | head -1)"
if [ -n "$access" ]; then
    echo "FAIL: caster has SPELL ACCESS but no STAFF SPELLS stati (inc-7y8u). Run: $run"
    exit 1
fi
echo "INCONCLUSIVE: no SPELL ACCESS stati read, so the list is suspect. Run: $run"
exit 2
