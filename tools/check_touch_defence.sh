#!/bin/bash
# gate: live
#
# Regression check for the phase-1 touch defence (inc-30ps): Creature::TouchDef
# (src/Values.cpp, computed beside A_CDEF in both branches of
# Creature::CalcValues) must equal A_DEF less BONUS_ARMOUR (24) and
# BONUS_SHIELD (30), each floored at 0 before subtracting. BONUS_NATURAL is
# NOT subtracted: at A_DEF it holds the flat base 10 every playable race
# carries (Def: 10, lib/races.irh, stacked in at src/Values.cpp:490), not
# natural armour, and a touch attack should not bypass that base.
#
# THE ORACLE is logs/touchdef.log, written by TouchDefProbeNote (src/Values.cpp)
# under INCURSION_TOUCHDEF_PROBE, one line per recalculation of the player's
# values: "def %d touchdef %d nat %d arm %d shield %d" (nat is printed for
# visibility only; the formula below does not use it). This script recomputes
# the formula from arm/shield and compares against what the engine did.
#
# A NOTE ON "wearing none of the three". Worn body armour (T_ARMOUR) does not
# reach A_DEF in this engine's armour model -- it adds only to Coverage,
# Speed, Hit and Reflex saves (src/Values.cpp:938-950) -- so BONUS_ARMOUR at
# A_DEF picks up only an ADJUST_ARM stati (a mage-armour style spell). A
# character with no shield worn and no ADJUST_ARM stati therefore has BOTH
# subtracted terms at 0, and TouchDef MUST equal A_DEF exactly. This check
# asserts that equality on the bare row, then asserts the general arithmetic
# on every row -- see tools/keys/touch-defence.keys for how the geared row
# still exercises a real, non-zero shield contribution.
#
# Usage: tools/check_touch_defence.sh    (exits 0 on pass, 1 on fail)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=1
KEYS=tools/keys/touch-defence.keys

[ -x ./incursion-headless ] || {
    echo "FAIL: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 1
}

out="$(INCURSION_TOUCHDEF_PROBE=1 INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat tools/headless.sh "$KEYS" "$SEED" 2>&1)"
run="$(echo "$out" | awk '/^run:/ {print $2}')"

if echo "$out" | grep -q "NO GAMEPLAY"; then
    echo "FAIL: the run never entered a map, so it measured nothing."
    echo "$out"
    exit 1
fi
if echo "$out" | grep -q "the key script looked for something"; then
    echo "FAIL: the key script did not find a screen it expected; read"
    echo "      $run/logs/screens for the one it was looking at."
    exit 1
fi

log="$run/logs/touchdef.log"
if [ ! -s "$log" ]; then
    echo "FAIL: no $log. Either CalcValues never ran for the player, or the"
    echo "      probe is gone from src/Values.cpp and this check has nothing"
    echo "      to read."
    exit 1
fi

python3 - "$log" <<'PYEOF'
import re, sys

log = sys.argv[1]
LINE = re.compile(
    r'^def (-?\d+) touchdef (-?\d+) nat (-?\d+) arm (-?\d+) shield (-?\d+)$')

rows = []
unparsed = 0
for line in open(log, encoding='utf-8', errors='replace'):
    line = line.rstrip('\n')
    if not line.strip():
        continue
    m = LINE.match(line)
    if not m:
        unparsed += 1
        continue
    d, t, nat, arm, shield = (int(x) for x in m.groups())
    rows.append(dict(d=d, t=t, nat=nat, arm=arm, shield=shield, line=line))

if unparsed:
    print("FAIL: %d lines of %s did not parse; the probe's format and this "
          "script have drifted apart" % (unparsed, log))
    sys.exit(1)
if not rows:
    print("FAIL: %s parsed but held no rows" % log)
    sys.exit(1)

bad = []
for r in rows:
    want = r['d'] - (max(0, r['arm']) + max(0, r['shield']))
    if r['t'] != want:
        bad.append("  %s\n      touchdef is %d; def %d less arm %d, "
                    "shield %d is %d"
                   % (r['line'], r['t'], r['d'], r['arm'],
                      r['shield'], want))

bare = rows[0]
geared = rows[-1]

print("read:  %d recalculations" % len(rows))
print("bare:  %s" % bare['line'])
print("geared:%s" % geared['line'])

gaps = []
if bare['arm'] != 0 or bare['shield'] != 0:
    gaps.append("the FIRST row already carries armour or shield -- "
                "tools/keys/touch-defence.keys is not starting bare")
# A worn suit (T_ARMOUR) does NOT add to A_DEF in this engine's armour model
# -- it adds only to Coverage, Speed, Hit and the like (src/Values.cpp:965-982).
# Only a shield's DefVal and BONUS_NATURAL reach A_DEF. geared['arm'] == 0 is
# therefore the CORRECT reading, not a gap; the formula still subtracts it
# (at 0) and is proven correct arithmetically below regardless.
if geared['arm'] != 0:
    gaps.append("the LAST row carries a non-zero armour contribution to "
                "A_DEF, which this engine's armour model does not produce -- "
                "check that tools/keys/touch-defence.keys still equips a "
                "plain worn suit and nothing else changed")
if geared['shield'] <= 0:
    gaps.append("the LAST row carries no shield contribution -- the shield "
                "was never worn")

# A creature with no shield and no ADJUST_ARM stati (the bare row) has both
# subtracted terms at 0, so TouchDef MUST equal A_DEF exactly -- restoring
# the equality the earlier (BONUS_NATURAL-subtracting) formula could not
# satisfy.
if bare['arm'] == 0 and bare['shield'] == 0:
    if bare['t'] != bare['d']:
        bad.append("  bare row: TouchDef %d != A_DEF %d, though no shield "
                    "or ADJUST_ARM armour term is present"
                    % (bare['t'], bare['d']))
else:
    gaps.append("the bare row already carries an armour or shield term, so "
                "the bare-equals-A_DEF equality was never exercised")

# The brief's own check, on the geared row: touch defence lower than A_DEF by
# exactly the two contributions.
drop = geared['d'] - geared['t']
expect_drop = max(0, geared['arm']) + max(0, geared['shield'])
if drop != expect_drop:
    bad.append("  geared row: A_DEF exceeds touch defence by %d; armour+"
                "shield is %d" % (drop, expect_drop))

if bad:
    print("\nFAIL: the engine and the formula disagree.")
    for b in bad[:20]:
        print(b)
    sys.exit(1)

if gaps:
    print("\nFAIL: the session did not measure what this check exists for.")
    for g in gaps:
        print("  " + g)
    sys.exit(1)

print("\nPASS: touch defence matches A_DEF less armour and shield, bare "
      "(where it equals A_DEF exactly) and geared.")
PYEOF
