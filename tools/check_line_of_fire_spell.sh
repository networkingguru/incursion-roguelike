#!/bin/bash
# gate: live
#
# Regression check for the saving-throw cover-and-band rule for a spell
# bolt (inc-30ps rework): the same -4-per-square rule an arrow gets now
# applies to an EF_ATTACK bolt, ray or projected touch spell, rolling
# against the touch defence; a miss in band range is resolved by a Reflex
# save inside the named square, exactly as for a weapon; an effect with no
# EF_ATTACK (Magic Missile) rolls nothing and passes every body in the line
# to reach its chosen target; a beam still strikes everyone; and a bolt
# aimed at an EMPTY square (no chosen creature) obeys "A shot with no
# chosen creature" -- one candidate is the target with no penalty, more
# than one compares a single roll at a flat -4 in turn. See "The rule" in
# docs/specs/2026-09-21-line-of-fire-spec.md.
#
# THE ORACLE is logs/errors.log, written by LOFSpellProbe (src/Magic.cpp)
# under INCURSION_LOF_SPELL_PROBE. The probe places a five-rat line, the
# same shape LineOfFireProbe (src/Fight.cpp) uses -- "near" (distance 2)
# and "far" (distance 3) each alone, "cover"/"target"/"extra" sharing the
# square at distance 4 in that contents-chain order -- pins the target's
# touch defence relative to a calibrated vHit (read back through
# LOFGetLastVHit, since a bolt is cast through Magic::ABallBeamBolt's
# DoHits, whose per-target EventInfo copy never propagates back to the
# caller), and casts "Eldritch Bolt" (EF_ATTACK) once per case under a
# forced d20 roll (LOFSetForcedRoll) and, where a save matters, a forced
# save outcome (LOFSetForcedSave), reading back which rat lost hit points
# (or MULTIPLE, if more than one did).
#
# Cases: both boundaries of each of the three bands, a natural 20, a roll
# below the bare touch defence; the save walk reaching the second and
# third creature of a square and a whole-square save (miss); the save DC
# logged at two different bands; a displaced target producing a clean miss
# whether the roll is in band range, at the would-auto-hit boundary, or
# (pre-existing, not a defect) bypassed by a literal natural 20; two
# Flawless Dodge cases -- ruled 2026-09-22, a natural 20 always hits and
# Flawless Dodge cannot stop one, so flawless-dodge-nat20 asserts the
# TARGET is hit even under heavy cover, while flawless-dodge-ordinary-hit
# asserts an arithmetic (non-20) hit is still a clean miss that leaves the
# whole line alone, the original point of job 2 (see both cases' comments
# in LOFSpellProbe); the unerring Magic Missile case (inc-c4l4) and the
# beam case; and a bolt aimed at an empty square, both the lone-creature
# boundary (no penalty) and the multi-creature flat -4 walk. Each case
# writes one "LOF_SPELL_PROBE: case=... PASS|FAIL" line, and a final
# "LOF_SPELL_PROBE: RESULT pass=N fail=N" line.
#
# Amendment 1 item 5 (inc-55jl): loc-lone-hit, loc-multi-first and loc-
# multi-second all cast under MM_MAXIMIZE (fixed, non-random damage dice)
# and force Eldritch Bolt's own EF_PARTIAL Fortitude save to fail
# (LOFSetForcedSaveThrowRoll(1), wired into Creature::SavingThrow, src/
# Creature.cpp:3407 -- forcing a natural 1, which that function's own SRD
# rule always fails, so it can never accidentally read as the natural-20-
# always-succeeds rule instead). Each then asserts the struck creature's HP
# dropped by EXACTLY the maximized dice total, read back from
# Magic::ABallBeamBolt's own se.Dmg (LOFGetLastDmgNumber/Sides/Bonus)
# before any strike, hit/miss or save can touch it. A double application
# (the pre-fix defect) cannot land on that one number: an earlier version
# of this check tolerated "== full OR half" instead of forcing the save,
# and a double application where both halves succeeded could sum to a
# full-looking total and pass wrongly.
#
# Amendment 1 item 6 (inc-55jl phase 3): "A bolt fired in a direction
# strikes the first creature in its path". Fixed in Magic::ABallBeamBolt's
# own "shot with no chosen creature" walk (the item-5 kludge branch), not
# in MagicEvent's upstream fallback (:774, shared by every effect
# archetype, left untouched): a direction cast with EDir != CENTER arrives
# with EVictim set to the caster by that fallback, not a chosen creature,
# so the walk's guard now also fires for exactly that case.
# dir-hit-first/dir-miss-first cast Eldritch Bolt via EV_EFFECT with ONLY
# the fields EffectPrompt's key path itself sets (Clear(), EActor, eID,
# isDir, EDir -- no EXVal/EYVal/vRange), reusing the same line (dx,dy) as
# every case above so "near" is still the first body crossed;
# dir-beam-hits-all confirms a beam fired by direction is unaffected
# (isMulti, out of scope for item 6); dir-center-hits-self confirms
# EDir==CENTER (a self-cast by direction) is untouched -- the self-hit
# shortcut earlier in ABallBeamBolt sends it to DoneProject before it can
# ever reach the walk this fix changed.
#
# Amendment 1 item 7 (inc-55jl phase 3, data): "An unerring bolt is cast
# only at a chosen target". qval-* cases read the compiled qval bitmask
# (TEFF(id)->Vals(0)->qval) off Magic Missile, Force Missiles, Acid;wand
# and Major Drain directly -- no map or creature needed -- and assert
# neither Q_DIR nor Q_LOC survives on any of the four.
#
# Usage: tools/check_line_of_fire_spell.sh    (exits 0 on pass, 1 on fail)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=1
KEYS=tools/keys/line-of-fire.keys

[ -x ./incursion-headless ] || {
    echo "FAIL: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 1
}

out="$(INCURSION_LOF_SPELL_PROBE=1 INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat tools/headless.sh "$KEYS" "$SEED" 2>&1)"
run="$(echo "$out" | awk '/^run:/ {print $2}')"

log="$run/logs/errors.log"
if [ ! -s "$log" ]; then
    echo "FAIL: no $log. The probe never wrote anything -- is"
    echo "      LOFSpellProbe still called from Game::Play()?"
    exit 1
fi

# errors.log timestamps every line and prints a one-time call stack after a
# message's first occurrence (tools/headless.sh convention), so match the
# marker as a substring, not an anchor.
lines="$(grep 'LOF_SPELL_PROBE:' "$log")"
if [ -z "$lines" ]; then
    echo "FAIL: $log has no LOF_SPELL_PROBE lines."
    exit 1
fi

if grep -q 'INCONCLUSIVE' <<< "$lines"; then
    echo "FAIL: the probe could not run its scenario:"
    echo "$lines" | grep 'INCONCLUSIVE'
    exit 1
fi

result="$(echo "$lines" | grep 'LOF_SPELL_PROBE: RESULT ')"
if [ -z "$result" ]; then
    echo "FAIL: no LOF_SPELL_PROBE: RESULT line -- the probe did not finish."
    echo "$lines"
    exit 1
fi

echo "$lines"
echo

pass="$(echo "$result" | sed -n 's/.*pass=\([0-9]*\).*/\1/p')"
fail="$(echo "$result" | sed -n 's/.*fail=\([0-9]*\).*/\1/p')"

if [ -z "$pass" ] || [ -z "$fail" ]; then
    echo "FAIL: could not parse '$result'"
    exit 1
fi

if [ "$fail" != "0" ] || [ "$pass" -lt 36 ]; then
    echo "FAIL: $result (want fail=0 and pass>=36)"
    exit 1
fi

echo "PASS: $result"
