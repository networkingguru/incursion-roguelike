#!/bin/bash
# gate: live
# inc-w6t0: does Stone to Flesh remove STONING, deal no damage and print the
# limber line, cast on self (spell) and drunk (potion)?
#
#   tools/check_stone_to_flesh.sh      exit 0 every point holds, 1 otherwise
#
# BUILD FIRST: BACKEND=posix ./build_macos.sh. Two seeded sessions from a frozen
# character; src/StoneToFleshProbe.cpp runs on load under
# INCURSION_STONE_FLESH_PROBE=spell|potion: it gives the player STONING, then
# throws EV_EFFECT (spell) or EV_DRINK (potion) with the Stone to Flesh effect.
# The first screen dump shows the message line.
set -uo pipefail
cd "$(dirname "$0")/.."
[ -x ./incursion-headless ] || { echo "FAIL: build with BACKEND=posix ./build_macos.sh"; exit 1; }
mkdir -p logs/runs
bad=0
for mode in spell potion; do
    run=$(mktemp -d "$PWD/logs/runs/stone-to-flesh-$mode.XXXXXX")
    echo "Specimens ($mode): $run"
    export INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat
    export INCURSION_LOAD=tools/fixtures/chars/orc-mage-seed4-gate.sav
    export INCURSION_RUN_DIR="$run"
    export INCURSION_STONE_FLESH_PROBE=$mode
    if ! tools/headless.sh tools/keys/stone-to-flesh.keys 1 >"$run/harness.txt" 2>&1; then
        cat "$run/harness.txt"; echo "FAIL: $mode harness could not measure"; bad=1; continue
    fi
    python3 -I - "$run" "$mode" <<'PY' || bad=1
import pathlib, re, sys
run, mode = pathlib.Path(sys.argv[1]), sys.argv[2]
logs = list(run.rglob('errors.log'))
shots = sorted(run.rglob('0001-*.txt'))
if len(logs) != 1 or len(shots) != 1:
    sys.exit('FAIL: %s: missing or ambiguous errors.log or first dump' % mode)
text = logs[0].read_text(errors='replace')
m = re.findall(r'STONE_FLESH mode=(\w+) return=(-?\d+) stoning_before=(\d) stoning_after=(\d) hp_before=(-?\d+) hp_after=(-?\d+)', text)
if len(m) != 1 or 'INCONCLUSIVE' in text:
    sys.exit('FAIL: %s: probe line missing or inconclusive' % mode)
_, ret, sb, sa, hb, ha = m[0]
print('%s: stoning %s -> %s, hp %s -> %s' % (mode, sb, sa, hb, ha))
screen = ' '.join(shots[0].read_text(errors='replace').splitlines()[1:6])
screen = re.sub(r'\|\S*', '', screen)
n = screen.count('You feel more limber now.')
print('%s: limber line printed %d time(s)' % (mode, n))
bad = []
if sb != '1': bad.append('STONING not present before')
if sa != '0': bad.append('STONING still present after')
if hb != ha: bad.append('HP changed %s -> %s' % (hb, ha))
if n != 1: bad.append('limber line printed %d times, want 1' % n)
if bad:
    sys.exit('FAIL: %s: %s' % (mode, '; '.join(bad)))
PY
done
[ $bad -eq 0 ] && echo 'PASS: Stone to Flesh cures STONING, spell and potion' || exit 1
