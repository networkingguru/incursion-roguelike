#!/bin/bash
# gate: live
# Taking 20 speeds an unthreatened check along; it must not become a free
# pass regardless of the DC. (bd inc-e68f)
#
# THE DEFECT. Creature::SkillCheck (src/Skills.cpp) let an ACCIDENTAL natural
# 20 stand in for SRD 3.5's "taking 20": `roll == 20 && !isThreatened() &&
# (sk == SK_ESCAPE_ART || ...)` granted an automatic success no matter how
# far the total fell short of the DC. The `!isThreatened()` clause is
# take-20's own "no threats or distractions" requirement, bolted onto the
# wrong trigger -- a lucky die instead of a deliberate choice to spend the
# time.
#
# THE RULING (bd inc-e68f, 2026-09-17): implement taking 20 except its
# deliberate-action and time-cost parts. When a creature is not threatened
# and the skill is Escape Artist, Climb, Handle Device, Search or Balance,
# the roll simply IS 20 -- no die is consulted -- and the total is compared
# to the DC like any other check. There is no more automatic success.
#
# THE ORACLE is the engine's own printed skill line, which now reads
# "<Skill> Check: took 20 <mods> = <total> vs DC <n> [success|failure]."
# instead of fabricating dice nobody rolled. The fixture is the
# entangle-strength paladin (bd inc-jwm0): full plate and a kite shield in
# an empty room, so he is never threatened, stuck in tanglefoot strands
# (Escape Artist DC 22) he has no ranks in and cannot buy any in. His
# Escape Artist total after taking 20 is below that DC on every attempt.
#
# TWO PROPERTIES, read off every "took 20" line the harvest finds:
#
#   1. THE REGRESSION THIS FIX CREATES: a total below the DC must read
#      [failure]. This is the mutation below: restoring the old OR'd
#      auto-success clause while leaving the take-20 substitution in place
#      makes it fire on every one of these lines, deterministically --
#      the clause's own condition (`!isThreatened()` and one of the five
#      skills) is exactly the condition that already forced `roll` to 20 --
#      so no lucky natural 20 needs to be waited for.
#   2. Repeating the same check at the same DC gives the same verdict,
#      because no die is consulted once a creature is unthreatened.
#
# Usage: tools/check_take_twenty.sh [--prove-red]   (0 pass, 1 fail, 2 inconclusive)
. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/gates/Options.Dat

SEED=4
KEYS=tools/keys/entangle-strength-escape.keys

# The mutation this check defends: restore the auto-success clause SkillCheck
# used to OR into the verdict. Declared before do_check runs so --prove-red
# intercepts here, before the (build-needing) check below runs once in this
# process at all.
check_mutation src/Skills.cpp \
'	bool succ = (sr + roll + mod1 + mod2 + armPen) >= DC;' \
'	bool succ = (sr + roll + mod1 + mod2 + armPen) >= DC ||
		(roll == 20 && !isThreatened() && (sk == SK_ESCAPE_ART ||
			sk == SK_CLIMB || sk == SK_HANDLE_DEV || sk == SK_SEARCH ||
			sk == SK_BALANCE));'

HARVEST="$(mktemp -t take_twenty_harvest)" || _check_die 2 "no temp file"
trap 'rm -f "$HARVEST"' EXIT

check_run "$KEYS" "$SEED"
check_screens '*'

grep -h "Check: took 20" "${CHECK_SCREENS[@]}" 2>/dev/null |
    sed -E 's/^[[:space:]]*\|[[:space:]]*//; s/[[:space:]]*\|[^|]*$//' \
    > "$HARVEST"

LINES="$(wc -l < "$HARVEST" | tr -d ' ')"
UNIQUE="$(sort -u "$HARVEST" | wc -l | tr -d ' ')"

echo
echo "took-20 lines harvested: ${LINES:-0}"
echo "distinct verdicts seen:  ${UNIQUE:-0}"

if [ -z "$LINES" ] || [ "$LINES" -eq 0 ]; then
    _check_die 2 \
        "no \"Check: took 20\" line was ever printed; the fixture, the" \
        "take-20 skill list or the message wording has drifted, and this" \
        "run measured nothing."
fi

# --- property 2: repetition with no die consulted must not vary the verdict.
if [ "$UNIQUE" -gt 1 ]; then
    echo
    echo "FAIL: the same unthreatened check produced more than one verdict,"
    echo "      though taking 20 should consult no die:"
    sort -u "$HARVEST" | sed 's/^/      /'
    exit 1
fi

# --- property 1: a total below the DC must read [failure], never [success].
python3 - "$HARVEST" <<'PY'
import re
import sys

path = sys.argv[1]
pat = re.compile(r"took 20.*?(-?\d+) vs DC (\d+) \[(success|failure)\]")

bad = []
seen = 0
for line in open(path, encoding="utf-8"):
    line = line.rstrip("\n")
    if not line.strip():
        continue
    m = pat.search(line)
    if not m:
        print(f"the oracle pattern did not match a harvested line: {line}")
        sys.exit(2)
    seen += 1
    total, dc, verdict = int(m.group(1)), int(m.group(2)), m.group(3)
    if total < dc and verdict == "success":
        bad.append(line)

if seen == 0:
    print("no line survived parsing; nothing was measured.")
    sys.exit(2)

if bad:
    print("FAIL: a total below the DC read [success] after taking 20:")
    for b in bad:
        print("      " + b)
    sys.exit(1)

print(f"PASS: {seen} took-20 line(s) below their DC all read [failure], and")
print("      the verdict never varied across repeats.")
PY
rc=$?

echo
sort -u "$HARVEST" | sed 's/^/      /'
exit $rc
