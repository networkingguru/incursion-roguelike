#!/bin/bash
# gate: live
# Regression check for breath dice and dragon age scaling, inc-19ay.
#
# THE RULE. A breath weapon's die COUNT is the statblock's dice plus twice the
# breather's Power, floored at one; its die SIDES are the statblock's and
# nothing else. Creature::SAttack (src/Fight.cpp) computed that sum and then
# assigned max(1,e.Dmg.Number) over it. e.Dmg is zero at that point for every
# caller, so every breath weapon in the game delivered exactly one die.
#
# THE TWO SESSIONS, and why it takes two.
#
#   drake    A HELL HOUND, despite the file name. It declares 2d6 and carries
#            no template, so Power is 0 and the declared dice are the whole
#            answer. This is the half a Power-only fix would fail. The flame
#            drake the scenario was named for cannot be summoned at all -- see
#            the header of tools/keys/breath-dice-drake.keys.
#   dragon   A RED DRAGON, which declares 0d12 and takes every die it throws
#            from its age template's Power. This is the half a declared-only
#            fix would fail: it would hand the dragon one die at every age and
#            erase age scaling altogether.
#
# Each half alone can be passed by a wrong fix, so both must run.
#
# Build with INCURSION_BREATH_UNFIXED to restore only the faulty assignment for
# the before/after measurement. Measured 2026-09-11, seed 1, the two binaries
# differing in nothing but that one line:
#
#   before   hell hound 2d6 declared -> 1d6 delivered;
#            red dragon 0d12 declared at Power 5 -> 1d12 delivered
#   after    hell hound 2d6 declared -> 2d6 delivered;
#            red dragon 0d12 declared at Power 5 -> 10d12 delivered
#
# A session that never reaches the scenario is INCONCLUSIVE, not FAIL.
# Usage: tools/check_breath_dice.sh    (0 pass, 1 fail, 2 inconclusive)
#
# INCURSION_BIN picks a different binary, the way tools/headless.sh documents:
#   INCURSION_BIN=./incursion-breath-unfixed tools/check_breath_dice.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
SEED=1
BIN="${INCURSION_BIN:-./incursion-headless}"

[ -x "$BIN" ] || {
    echo "INCONCLUSIVE: $BIN not built. Run: BACKEND=posix ./build_macos.sh"
    exit 2
}
echo "binary: $BIN"

# Run both sessions even if the first one did not reach its monster.
logs=()
inconclusive=0
for scenario in drake dragon; do
    out="$(INCURSION_BIN="$BIN" INCURSION_BREATH_PROBE=1 INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat tools/headless.sh "tools/keys/breath-dice-$scenario.keys" "$SEED" 2>&1)"
    # "run:" is followed by padding spaces, so take the field, not the rest of
    # the line: sub(/^run: /,"") left them on the front of the path, and every
    # later [ -f "$log" ] then looked for a file whose name began with spaces
    # and reported INCONCLUSIVE however good the evidence was.
    run="$(echo "$out" | awk '/^run:/ {print $2; exit}')"
    log="$run/logs/breath.log"
    echo "$scenario run: ${run:-unreported}"
    if grep -q "NO GAMEPLAY" <<< "$out"; then
        echo "INCONCLUSIVE: the $scenario run never entered a map, so it measured nothing."
        echo "              Run dir: ${run:-unreported}"
        inconclusive=1
    elif [ -z "$run" ] || [ ! -f "$log" ] || ! grep -q '^breath:' "$log"; then
        echo "INCONCLUSIVE: the $scenario monster never breathed; no breath lines."
        echo "              Run dir: ${run:-unreported}"
        inconclusive=1
    fi
    logs+=("$log")
done
[ "$inconclusive" -eq 0 ] || exit 2

# Split the quoted actor separately: monster names contain spaces. Numeric
# fields have fixed labels; reject malformed evidence instead of coercing it
# into zeros and announcing a pass.
awk '
/^breath:/ {
    if ($0 !~ /^breath: actor="[^"]+" atype=[0-9]+ declared=-?[0-9]+d[0-9]+ power=-?[0-9]+ delivered=-?[0-9]+d[0-9]+$/) {
        print "INCONCLUSIVE: malformed breath evidence in " FILENAME ": " $0
        malformed=1
        next
    }
    split($0, quoted, "\"")
    actor=quoted[2]
    rest=quoted[3]
    sub(/^ /, "", rest)
    split(rest, field, " ")
    sub(/^declared=/, "", field[2]); split(field[2], declared, "d")
    sub(/^power=/, "", field[3]); power=field[3]+0
    sub(/^delivered=/, "", field[4]); split(field[4], delivered, "d")
    expected=declared[1]+power*2
    if (expected < 1) expected=1
    if (delivered[1]+0 != expected) {
        print "FAIL: breath count must equal max(1, declared + 2*power); inc-19ay back again."
        print "      " FILENAME ": " $0
        count_bad=1
    }
    if (delivered[2]+0 != declared[2]+0) {
        print "FAIL: delivered die sides differ from the statblock."
        print "      " FILENAME ": " $0
        sides_bad=1
    }
    if (FILENAME == ARGV[1] && actor == "hell hound") {
        hounds++
        if (declared[1]+0 != 2 || delivered[1]+0 != 2) hound_bad=1
    }
    # The dragon half. Every die comes from Power, so a breath that declares
    # dice of its own is not the evidence this scenario is about and is not
    # counted -- an age template that started declaring dice would make the
    # scenario silently stop testing what it says it tests.
    if (FILENAME == ARGV[2] && actor == "red dragon") {
        dragons++
        if (declared[1]+0 != 0 || power < 1) {
            dragon_wrong_shape=1
            next
        }
        aged++
        if (delivered[1]+0 != power*2) dragon_bad=1
        if (!(power in seen)) powers++
        seen[power]=delivered[1]+0
    }
}
END {
    if (!count_bad && !malformed)
        print "PASS: every breath preserves declared dice plus twice Power, floored at one."
    if (!sides_bad && !malformed)
        print "PASS: every breath preserves its declared die sides."

    if (!hounds) {
        print "INCONCLUSIVE: the hell hound never breathed. Read " ARGV[1]
        missing=1
    } else if (hound_bad) {
        print "FAIL: the hell hound must declare and deliver two dice; statblock dice were lost."
    } else {
        print "PASS: the hell hound declares and delivers two dice at Power 0."
    }

    if (!dragons) {
        print "INCONCLUSIVE: the red dragon never breathed. Read " ARGV[2]
        missing=1
    } else if (!aged) {
        print "INCONCLUSIVE: the red dragon breathed, but never with a declared 0dN"
        print "              and a Power above zero, so nothing measured age scaling."
        print "              Read " ARGV[2]
        missing=1
    } else if (dragon_bad) {
        print "FAIL: a red dragon that declares no dice must deliver twice its Power;"
        print "      its age contributed nothing. Read " ARGV[2]
    } else {
        for (p in seen)
            line = line sprintf(" Power %d -> %d dice.", p, seen[p])
        print "PASS: every die the red dragon breathes comes from its age." line
    }

    # Two ages in one log is a stronger claim, and the session is not built to
    # guarantee it (a summoned dragon takes the age the game gives it). Check
    # it when the evidence is there; never demand it.
    if (powers >= 2) {
        for (low in seen)
            for (high in seen)
                if (high+0 > low+0 && seen[high] <= seen[low]) age_bad=1
        if (age_bad)
            print "FAIL: higher-Power red dragon must deliver strictly more dice; age scaling was lost."
        else
            print "PASS: higher-Power red dragon delivers strictly more dice than the younger one."
    }

    if (dragon_wrong_shape) {
        print "NOTE: some red dragon breaths declared dice of their own or had Power 0;"
        print "      those lines are still held to the general rule above, but they are"
        print "      not what the age half measures."
    }

    if (count_bad || sides_bad || hound_bad || dragon_bad || age_bad) exit 1
    if (missing || malformed) exit 2
    exit 0
}' "${logs[0]}" "${logs[1]}"
