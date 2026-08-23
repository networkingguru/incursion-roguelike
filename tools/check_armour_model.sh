#!/bin/bash
# Regression check for the armour model: graded penetration of coverage, and
# subtractive damage. See bd inc-b0w2 for the design and every ruling in it.
#
# THE RULES BEING CHECKED
#
# Two bars are read off the same d20 attack roll. Clear the target's Defense
# Class and you hit. Clear Defense Class plus that armour's Coverage and you
# have found a seam, and every further point you rolled above that second bar
# turns one more point of that armour aside:
#
#   natIgnored  = max(0, hit + roll - (def + NATURAL_COVERAGE))
#   wornIgnored = max(0, hit + roll - (def + cov))
#   effective   = max(0, rating - ignored)          per source, separately
#   damage      = max(1, raw - effective)           subtractive, floor of 1
#
# Natural armour and a worn suit sit behind different Coverage, so they are
# penetrated independently and only then stacked.
#
# WHAT MAKES THIS A MEASUREMENT AND NOT A SMOKE TEST
#
# The oracle is logs/armour.log, written by ArmourProbeNote (src/Fight.cpp)
# under INCURSION_ARMOUR_PROBE. It names every term the model uses on every
# resolved attack, so this script recomputes the model from the inputs and
# compares against what the engine did. Numbers on both sides. A run that
# resolves no attacks fails rather than passes: see the counts near the end.
#
# On a build without the change, the damage assertion fails on the first hit
# that the old threshold-and-percentage tables absorbed to nothing -- which is
# most of them, and is exactly the complaint the change answers.
#
# WHAT THIS DOES NOT COVER, AND WHY
#
# 1. Penetrating weapons (WT_PENETRATING, +rating*2/5 ignored). Nothing in the
#    starting kit carries the flag and wizard mode cannot add it. The parser
#    below ACCEPTS the penetrating value wherever it appears and says how many
#    lines used it, so if a future scenario produces one it is checked, but
#    this scenario produces none and the script says so rather than implying
#    coverage it does not have.
# 2. The helmet, gauntlet and boot Coverage branch (inc-vifx). The only items
#    in the module carrying that Coverage are mundane -- "hard steel cap",
#    "cured leather boots" and their kin -- and src/Tables.cpp:320 gives the
#    wizard-mode acquisition browser no category that reaches T_HELMET,
#    T_BOOTS or T_GAUNTLETS, so no scripted session can put one on a
#    character. What IS checked here is the constant those items add up to.
#
# Usage: tools/check_armour_model.sh    (exits 0 on pass, 1 on fail)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=1
KEYS=tools/keys/armour-model.keys

[ -x ./incursion-headless ] || {
    echo "FAIL: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 1
}

# --- Part one: the constant against the data it claims to summarise ---------
#
# NATURAL_COVERAGE says natural armour covers as much of a body as a complete
# worn harness does. If the data ever gains a suit above 10, or a helmet above
# 2, that claim stops being true and the constant must move with it.
python3 - "$ROOT" <<'PYEOF' || exit 1
import re, sys, glob, os
root = sys.argv[1]

want = {'T_ARMOUR': 0, 'T_HELMET': 0, 'T_GAUNTLETS': 0, 'T_BOOTS': 0}
item = re.compile(r'^\s*Item\s+"[^"]*"\s*:\s*(T_\w+)')
cov  = re.compile(r'\b(?:Coverage|Cov)\s*:\s*(\d+)')

for path in glob.glob(os.path.join(root, 'lib', '*.irh')):
    cur = None
    for line in open(path, encoding='utf-8', errors='replace'):
        m = item.match(line)
        if m:
            cur = m.group(1)
            continue
        if cur in want:
            c = cov.search(line)
            if c:
                want[cur] = max(want[cur], int(c.group(1)))

total = sum(want.values())

src = open(os.path.join(root, 'inc', 'Defines.h'), encoding='utf-8',
           errors='replace').read()
m = re.search(r'#define\s+NATURAL_COVERAGE\s+(\d+)', src)
if not m:
    print("FAIL: NATURAL_COVERAGE is not defined in inc/Defines.h")
    sys.exit(1)
const = int(m.group(1))

if const != total:
    print("FAIL: NATURAL_COVERAGE is %d, but the heaviest complete harness in"
          " lib/ adds up to %d" % (const, total))
    print("      suit %d + helm %d + gauntlets %d + boots %d"
          % (want['T_ARMOUR'], want['T_HELMET'], want['T_GAUNTLETS'],
             want['T_BOOTS']))
    sys.exit(1)

print("data:  NATURAL_COVERAGE %d = suit %d + helm %d + gauntlets %d + boots %d"
      % (const, want['T_ARMOUR'], want['T_HELMET'], want['T_GAUNTLETS'],
         want['T_BOOTS']))
PYEOF

# --- Part two: the model, measured in a real session ------------------------
out="$(INCURSION_ARMOUR_PROBE=1 tools/headless.sh "$KEYS" "$SEED" 2>&1)"
run="$(echo "$out" | awk '/^run:/ {print $2}')"

# A session that measured nothing must never read as a pass: inc-loa.3.
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

log="$run/logs/armour.log"
if [ ! -s "$log" ]; then
    echo "FAIL: no $log. Either no attack resolved, or the probe is gone from"
    echo "      src/Fight.cpp and this check has nothing to read."
    exit 1
fi

python3 - "$log" "$ROOT" <<'PYEOF'
import re, sys

log, root = sys.argv[1], sys.argv[2]

src = open(root + '/inc/Defines.h', encoding='utf-8', errors='replace').read()
NATCOV = int(re.search(r'#define\s+NATURAL_COVERAGE\s+(\d+)', src).group(1))

LINE = re.compile(
    r'turn (\d+): <(.*)> DType (\d+) hit (-?\d+)\+(-?\d+) vs def (-?\d+) '
    r'cov (-?\d+); nat (-?\d+) natIgn (-?\d+); worn (-?\d+) wornIgn (-?\d+); '
    r'arm (-?\d+); raw (-?\d+) -> got (-?\d+)')

rows, bad, unparsed = [], [], 0
for n, line in enumerate(open(log, encoding='utf-8', errors='replace'), 1):
    line = line.rstrip('\n')
    if not line.strip():
        continue
    m = LINE.match(line)
    if not m:
        unparsed += 1
        continue
    (turn, who, dtype, hit, roll, dfn, cov,
     nat, natign, worn, wornign, arm, raw, got) = (
        [int(m.group(1)), m.group(2)] + [int(m.group(i)) for i in range(3, 15)])
    rows.append(dict(n=n, line=line, who=who, hit=hit, roll=roll, dfn=dfn,
                     cov=cov, nat=nat, natign=natign, worn=worn,
                     wornign=wornign, arm=arm, raw=raw, got=got))

def fail(r, why):
    bad.append("  line %d: %s\n      %s" % (r['n'], why, r['line']))

pen_lines = 0

for r in rows:
    total = r['hit'] + r['roll']
    rolled = not (r['hit'] == 0 and r['roll'] == 0 and r['dfn'] == 0)

    if not rolled:
        # No attack roll means nothing was penetrated. Damage still applies.
        if r['natign'] or r['wornign']:
            fail(r, "an attack with no roll turned armour aside")
    else:
        base_nat  = max(0, total - (r['dfn'] + NATCOV))
        base_worn = max(0, total - (r['dfn'] + r['cov']))
        pen_nat   = base_nat  + (r['nat']  * 2) // 5
        pen_worn  = base_worn + (r['worn'] * 2) // 5

        ok_nat  = r['natign']  in (base_nat,  pen_nat,  r['nat'])
        ok_worn = r['wornign'] in (base_worn, pen_worn, r['worn'])
        if not ok_nat:
            fail(r, "natIgn is %d; the roll allows %d (or %d penetrating)"
                    % (r['natign'], base_nat, pen_nat))
        if not ok_worn:
            fail(r, "wornIgn is %d; the roll allows %d (or %d penetrating)"
                    % (r['wornign'], base_worn, pen_worn))
        if ok_nat and ok_worn and (r['natign'] != base_nat
                                   or r['wornign'] != base_worn):
            pen_lines += 1

    # The damage model itself, on every line without exception.
    if r['got'] != max(1, r['raw'] - r['arm']):
        fail(r, "damage is %d; raw %d less armour %d, floored at 1, is %d"
                % (r['got'], r['raw'], r['arm'], max(1, r['raw'] - r['arm'])))
    if r['got'] < 1:
        fail(r, "a landed hit did no damage at all")

# Graded, not stepped: with everything else equal, a better roll must never
# leave MORE armour standing.
groups = {}
for r in rows:
    if r['hit'] == 0 and r['roll'] == 0:
        continue
    groups.setdefault((r['who'], r['dfn'], r['cov'], r['nat'], r['worn']),
                      []).append(r)
for key, g in groups.items():
    g.sort(key=lambda r: r['hit'] + r['roll'])
    for a, b in zip(g, g[1:]):
        if b['arm'] > a['arm']:
            bad.append("  lines %d and %d: a higher roll left MORE armour "
                       "standing (%d then %d)\n      %s\n      %s"
                       % (a['n'], b['n'], a['arm'], b['arm'],
                          a['line'], b['line']))

rolled_rows = [r for r in rows if not (r['hit'] == 0 and r['roll'] == 0
                                       and r['dfn'] == 0)]
nat_pen  = [r for r in rolled_rows if r['natign'] > 0 and r['nat'] > 0]
worn_pen = [r for r in rolled_rows if r['wornign'] > 0 and r['worn'] > 0]
floored  = [r for r in rows if r['arm'] > 0 and r['raw'] <= r['arm']]
zeroes   = [r for r in rows if r['got'] == 0]

print("read:  %d resolved attacks, %d of them with an attack roll"
      % (len(rows), len(rolled_rows)))
print("       %d penetrated natural armour, %d penetrated a worn suit"
      % (len(nat_pen), len(worn_pen)))
print("       %d met more armour than damage and still did 1, %d did 0"
      % (len(floored), len(zeroes)))
print("       %d used a penetrating weapon" % pen_lines)

# A scenario that stopped exercising a rule must fail, not quietly pass.
gaps = []
if unparsed:
    gaps.append("%d lines of the log did not parse; the probe's format and "
                "this script have drifted apart" % unparsed)
if len(rolled_rows) < 30:
    gaps.append("only %d attacks carried a roll; the scenario is no longer "
                "producing a fight" % len(rolled_rows))
if not nat_pen:
    gaps.append("nothing penetrated natural armour, so the graded ramp went "
                "unmeasured")
if not worn_pen:
    gaps.append("nothing penetrated a worn suit, so the second bar went "
                "unmeasured")
if not floored:
    gaps.append("no hit met more armour than it carried damage, so the floor "
                "of 1 went unmeasured")

if bad:
    print("\nFAIL: the engine and the model disagree.")
    for b in bad[:20]:
        print(b)
    if len(bad) > 20:
        print("  ... and %d more" % (len(bad) - 20))
    sys.exit(1)

if gaps:
    print("\nFAIL: the session did not measure what this check exists for.")
    for g in gaps:
        print("  " + g)
    sys.exit(1)

print("\nPASS: every resolved attack matches the model.")
PYEOF
