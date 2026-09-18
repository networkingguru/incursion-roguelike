#!/bin/bash
# gate: live
# A natural 20 on a saving throw must always succeed, and a natural 1 must
# always fail (SRD 3.5), regardless of Bonus + roll vs DC. (bd inc-e68f)
#
# THE DEFECT. Creature::SavingThrow (src/Creature.cpp) rolled 1d20 and then
# decided success with the bare comparison Bonus + roll >= DC, at four
# separate sites that all have to agree: the message colour, the message
# word, the Exercise training gate and the return value. Patching only the
# return leaves a natural 20 printing "[failure]" while the engine treats it
# as a success -- worse than the original bug, because the player's own
# screen would then disagree with what happened.
#
# THE ORACLE. The engine already prints every save the player can perceive,
# "<name>'s <type> Save: 1d20 (roll) ... vs DC <n> [success|failure].", and
# OPT_STORE_ROLLS (on in tools/gates/Options.Dat) keeps every one of them in
# the scrolling message log -- no probe, no instrumentation, just reading
# what an ordinary session already tells the player. This check drives
# tools/keys/natural-save-tangle.keys across many seeds for VOLUME (DC 15,
# safe, no damage) and tools/keys/natural-save-runes.keys once, pinned to
# seed 4, for an EDGE CASE a modest DC can never supply: DC 27 is far enough
# above a level 1 paladin's +3 base that a natural 20 there only reads
# "success" because of the special rule, not because Bonus + 20 happens to
# clear the DC anyway. Every harvested line is checked against both halves
# of the rule.
#
# A run that never rolls a natural 20 (or never rolls a natural 1) has
# measured nothing -- a d20 is 5% per roll; volume is what makes seeing both
# a near-certainty across the seeds below -- and this check exits 2, not 0,
# when that happens.
#
# PROVED RED on 2026-09-17 (docs/VERIFICATION.md step 2). The mutation below
# reverts the fix to the original bare comparison. The guardian-runes
# session then prints "Will Save: 1d20 (20) +3 base = 23 vs DC 27
# [failure]." -- a natural 20 the SRD says must succeed -- and this check
# reports that line as a violation and exits 1.
#
# Usage: tools/check_natural_save.sh [--prove-red]   (0 pass, 1 fail, 2 inconclusive)
. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/gates/Options.Dat

# Seeds tools/keys/natural-save-tangle.keys has been verified clean on: a
# clear run of floor at least 5 squares east of chargen-paladin.keys'
# opening position, on tools/gates/Options.Dat. Seed 12 is left out on
# purpose -- chargen-paladin.keys' own prompts land differently on it
# ("Wizard Mode Switches" never appears there), which is a fixture question,
# not a saving-throw one. A frozen list, not "however many seeds happen to
# work today", so a bad seed cannot silently make this check measure less
# than the reader expects.
TANGLE_SEEDS="1 2 3 4 5 6 7 8 9 10 11 13 14 15"
RUNES_SEED=4

# The mutation this check defends: the special-cased natural 20/1 verdict,
# reverted to upstream's bare comparison. Declared before do_check runs so
# that --prove-red intercepts here, before the (expensive, many-seed) check
# below ever runs once in this process -- the recursive re-runs inside
# _check_prove_red do that work instead, once clean and once mutated.
check_mutation src/Creature.cpp \
'  bool succ = (roll == 20) ? true
            : (roll == 1)  ? false
            : (Bonus + roll >= DC);' \
'  bool succ = (Bonus + roll >= DC);'

HARVEST="$(mktemp -t natural_save_harvest)" || _check_die 2 "no temp file"
RESULT="$(mktemp -t natural_save_result)" || _check_die 2 "no temp file"
trap 'rm -f "$HARVEST" "$RESULT"' EXIT

# Dedupe the CURRENT run's chosen screens before adding them: the tangle
# script pages the message log top to bottom with deliberately overlapping
# windows (so nothing between the pages is missed), and that overlap prints
# the same real roll on more than one page. Two different seeds are never
# deduped against each other -- an identical line from two different
# sessions is two different real rolls that happen to read alike.
harvest_run() {
    grep -h "Save: 1d20 (" "${CHECK_SCREENS[@]}" 2>/dev/null |
        sed -E 's/^[[:space:]]*\|[[:space:]]*//; s/[[:space:]]*\|[^|]*$//' |
        sort -u >> "$HARVEST"
}

do_check() {
    local seed
    : > "$HARVEST"
    for seed in $TANGLE_SEEDS; do
        check_run tools/keys/natural-save-tangle.keys "$seed"
        check_screens '*messages*'
        harvest_run
    done

    echo "--- the edge case: DC 27 guardian runes, seed $RUNES_SEED ---"
    check_run tools/keys/natural-save-runes.keys "$RUNES_SEED"
    check_screens '*messages*'
    harvest_run

    python3 - "$HARVEST" > "$RESULT" <<'PY'
import re
import sys

path = sys.argv[1]
lines = [l for l in open(path, encoding="utf-8").read().splitlines() if l.strip()]

pat = re.compile(r"Save: 1d20 \((\d+)\)[^=]*=\s*-?\d+ vs DC \d+ \[(success|failure)\]")

examined = 0
nat20 = nat1 = 0
violations = []
for line in lines:
    m = pat.search(line)
    if not m:
        continue
    examined += 1
    roll, verdict = int(m.group(1)), m.group(2)
    if roll == 20:
        nat20 += 1
        if verdict == "failure":
            violations.append(line)
    if roll == 1:
        nat1 += 1
        if verdict == "success":
            violations.append(line)

print(f"EXAMINED {examined}")
print(f"NAT20 {nat20}")
print(f"NAT1 {nat1}")
for v in violations:
    print("VIOLATION " + v)
PY
}

do_check

EXAMINED="$(sed -n 's/^EXAMINED //p' "$RESULT")"
NAT20="$(sed -n 's/^NAT20 //p' "$RESULT")"
NAT1="$(sed -n 's/^NAT1 //p' "$RESULT")"
VIOLATIONS="$(sed -n 's/^VIOLATION //p' "$RESULT")"

echo
echo "save lines examined: ${EXAMINED:-0}"
echo "natural 20s seen:    ${NAT20:-0}"
echo "natural 1s seen:     ${NAT1:-0}"

if [ -z "$EXAMINED" ] || [ "$EXAMINED" -eq 0 ]; then
    _check_die 2 "no save line matched the oracle pattern at all; the harness or the pattern drifted."
fi
if [ "${NAT20:-0}" -eq 0 ]; then
    _check_die 2 "no natural 20 was rolled across the $(echo $TANGLE_SEEDS | wc -w | tr -d ' ') tangle seeds plus the runes seed; this run measured nothing about the rule it exists to check."
fi
if [ "${NAT1:-0}" -eq 0 ]; then
    _check_die 2 "no natural 1 was rolled across the $(echo $TANGLE_SEEDS | wc -w | tr -d ' ') tangle seeds plus the runes seed; this run measured nothing about the rule it exists to check."
fi

if [ -n "$VIOLATIONS" ]; then
    echo
    echo "FAIL: a natural 20 or a natural 1 disagreed with SRD 3.5:"
    echo "$VIOLATIONS" | sed 's/^/      /'
    exit 1
fi

echo
echo "PASS: no natural 20 ended in [failure] and no natural 1 ended in [success]"
echo "      across $EXAMINED save lines (${NAT20} natural 20s, ${NAT1} natural 1s)."
exit 0
