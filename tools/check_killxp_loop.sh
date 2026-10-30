#!/bin/bash
# gate: live
# inc-946vn: Creature::KillXP must not recurse without end when a leader link
# and a DIPLOMACY_TAG form a loop (B's leader is A; A holds a tag from B).
# fact: character -- fixture xsummon-priest-seed5-opt0822 (INCURSION_LOAD)
# fact: settings -- options-2026-08-22.dat (INCURSION_OPTIONS)
# fact: monsters A, B, victims -- built by the probe from fixed names (kobold, goblin), no dice
# fact: links -- built by the probe: B leads to A, A has a tag from the player, loop scene adds a tag from B
# fact: XP formula and difficulty -- not read; the expected gain comes from the direct scene in the same run
# Build: BACKEND=posix ./build_macos.sh
# Run: tools/check_killxp_loop.sh
# Expected values, and why:
#   direct  gain G > 0: the player is credited at 100 percent; it is the base.
#   control gain == G*75/100 (integer divide): A is reached through B's leader
#           link, then the player through A's tag at 75 percent. Each of A and
#           B gets exactly 1 call.
#   loop    same gain and same counts as control: the extra B->A edge must add
#           no share and no second visit.
# Exit 0 pass; 1 defect (wrong numbers, or the loop recursed); 2 UNMEASURED.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
mkdir -p logs/runs
RUN_DIR="$(mktemp -d "$ROOT/logs/runs/killxp-loop.XXXXXX")"
echo "Specimens: $RUN_DIR"
status=0
INCURSION_BIN="$ROOT/incursion-headless" \
INCURSION_KILLXP_PROBE=1 INCURSION_RUN_DIR="$RUN_DIR" \
INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat \
INCURSION_LOAD=tools/fixtures/chars/xsummon-priest-seed5-opt0822.sav \
    tools/headless.sh tools/keys/template-alignment.keys 1 \
    > "$RUN_DIR/harness.txt" 2>&1 || status=$?
log="$RUN_DIR/logs/killxp-loop.log"
if [ ! -s "$log" ]; then
    echo "UNMEASURED: missing probe log (harness exit $status)."
    exit 2
fi
cat "$log"
if grep -q '^RECURSION' "$log"; then
    echo "FAIL: KillXP recursed past depth 20 (harness exit $status)."
    exit 1
fi
python3 - "$log" <<'PY'
from pathlib import Path
import re, sys
lines = Path(sys.argv[1]).read_text().splitlines()
if not lines or lines[-1] != 'DONE':
    print('UNMEASURED: probe did not reach DONE.'); sys.exit(2)
def scene(name):
    for l in lines:
        m = re.match(r'scene=%s (.*)$' % name, l)
        if m:
            return dict(kv.split('=') for kv in m.group(1).split())
    print('UNMEASURED: no %s scene line.' % name); sys.exit(2)
direct, control, loop = scene('direct'), scene('control'), scene('loop')
G = int(direct['gain'])
if G <= 0:
    print('UNMEASURED: direct gain %d is not positive.' % G); sys.exit(2)
want = G * 75 // 100
bad = []
for name, s in (('control', control), ('loop', loop)):
    if int(s['gain']) != want:
        bad.append('%s gain %s, want %d' % (name, s['gain'], want))
    if s['callsA'] != '1' or s['callsB'] != '1':
        bad.append('%s calls A=%s B=%s, want 1 and 1' % (name, s['callsA'], s['callsB']))
if bad:
    print('FAIL: ' + '; '.join(bad)); sys.exit(1)
print('PASS: control and loop both gain %d (75%% of %d); A and B called once each.' % (want, G))
PY
