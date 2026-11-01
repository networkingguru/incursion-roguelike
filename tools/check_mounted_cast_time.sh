#!/bin/bash
# gate: live
# A mounted caster takes 15 extra turns on a non-still spell unless Balance is
# 20 or Ride is 10 (inc-2zpv6; src/Magic.cpp "Casting on a moving mount").
# fact: character and starting world -- fixture orc-mage-seed1-opt0822
# fact: no monster interference -- wizard Genocide Everything before the cast
# fact: Ride and Balance -- scratch gods (tools/fixtures/mounted-cast-gods.irh)
#       set exact totals; control is the "MCT skills Ride r Balance b." line
#       each blessing prints, compared with the case's intended pair
# fact: a mount -- wizard summons a horse beside the player and makes him its
#       master; control is "Mounted" on the status line (and "Afoot" in the
#       unmounted case) in the dump taken just before the cast
# fact: spell and time -- Shield (self-only, somatic); control is its "wall of
#       force" message, and the turn counter in each dump's first line
# fact: baseline cast time -- the unmounted case of the SAME run, same seed
# fact: settings -- frozen options-2026-08-22.dat
# fact: session completed -- headless exit 0 and ended: cleanly
#
# tools/check_mounted_cast_time.sh [seed] (default 1)
# Exit 0: every assertion holds; 1: an assertion failed with all controls
# holding; 2: could not measure. Specimens stay under logs/runs/.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
fail_control() { echo "INCONCLUSIVE: $*"; exit 2; }
[ -x ./incursion-headless ] || fail_control 'build with BACKEND=posix ./build_macos.sh'
SEED="${1:-1}"
OPTIONS=tools/fixtures/options-2026-08-22.dat
FIXTURE=tools/fixtures/chars/orc-mage-seed1-opt0822.sav
TEMPLATE=tools/keys/mounted-cast-time.keys
[ -f "$OPTIONS" ] && [ -f "$FIXTURE" ] && [ -f "$TEMPLATE" ] || fail_control 'missing frozen fixture'
BASE="$ROOT/logs/runs/check-mounted-cast-time-$(date +%s)-$$"
mkdir -p "$BASE/module/mod" "$BASE/module/logs" || fail_control 'mkdir failed'
echo "specimens: $BASE"
cp -Rf "$ROOT/lib" "$BASE/module/lib" || fail_control 'copy lib failed'
ln -s "$ROOT/inc" "$BASE/module/inc" || fail_control 'link inc failed'
cat tools/fixtures/mounted-cast-gods.irh >> "$BASE/module/lib/main.irc"
INCURSIONPATH="$BASE/module/" ./incursion-headless -compile main.irc \
    < /dev/null > "$BASE/module/compile.log" 2>&1
[ "$?" -eq 0 ] && [ -s "$BASE/module/mod/Incursion.Mod" ] || \
    fail_control "scratch compile failed; see $BASE/module/compile.log"
# case name:god:mounted:still
CASES="ride9:R9B0:M:- ride10:R10B0:M:- bal20:R0B20:M:- still:R0B0:M:S plain:R0B0:M:- afoot:R0B0:-:-"
for c in $CASES; do
    IFS=: read -r name god mount still <<< "$c"
    RUN="$BASE/$name"
    mkdir -p "$RUN/mod" "$RUN/lib" || fail_control 'mkdir failed'
    cp -f "$BASE/module/mod/Incursion.Mod" "$RUN/mod/Incursion.Mod"
    sed "s/@GOD@/Mounted Cast Test God $god/" "$TEMPLATE" > "$RUN/script.keys"
    [ "$mount" = M ] && sed -i.bak 's/^#M# //' "$RUN/script.keys"
    [ "$still" = S ] && sed -i.bak 's/^#S# //' "$RUN/script.keys"
    INCURSION_RUN_DIR="$RUN" INCURSION_OPTIONS="$OPTIONS" INCURSION_LOAD="$FIXTURE" \
        tools/headless.sh "$RUN/script.keys" "$SEED" > "$RUN/session.txt" 2>&1
    echo "$?" > "$RUN/exit-code.txt"
done
python3 - "$BASE" <<'PYCODE'
import pathlib, re, sys
base = pathlib.Path(sys.argv[1])
# name: (ride, balance, mounted, expect_extra)
cases = {'ride9': (9, 0, True, True), 'ride10': (10, 0, True, False),
         'bal20': (0, 20, True, False), 'still': (0, 0, True, False),
         'plain': (0, 0, True, True), 'afoot': (0, 0, False, False)}
errors, fails, got = [], [], {}
for name, (ride, bal, mounted, extra) in cases.items():
    run = base / name
    if (run / 'exit-code.txt').read_text().strip() != '0' or \
            not re.search(r'ended: +cleanly', (run / 'session.txt').read_text()):
        errors.append(f'{name}: session did not end cleanly'); continue
    d = {}
    for n in ('ready', 'cast', 'msgs'):
        hits = sorted((run / 'logs/screens').glob(f'*-{n}.txt'))
        if len(hits) != 1:
            errors.append(f'{name}: dump {n} found {len(hits)}'); break
        d[n] = hits[0].read_text()
    else:
        t0 = re.search(r' turn (\d+) ===', d['ready'])
        t1 = re.search(r' turn (\d+) ===', d['cast'])
        msgs = re.sub(r'\s+', ' ', d['msgs'])
        if not (t0 and t1):
            errors.append(f'{name}: turn unreadable'); continue
        if f'MCT skills Ride {ride} Balance {bal}.' not in msgs:
            errors.append(f'{name}: skill line missing or wrong')
        if mounted and 'Mounted' not in d['ready']:
            errors.append(f'{name}: not Mounted before the cast')
        if not mounted and 'Afoot' not in d['ready']:
            errors.append(f'{name}: not Afoot before the cast')
        if 'wall of force' not in msgs:
            errors.append(f'{name}: the cast did not happen')
        got[name] = (int(t1[1]) - int(t0[1]), 'extra time' in msgs)
if errors:
    print('INCONCLUSIVE: ' + '; '.join(errors)); sys.exit(2)
print('case: (turns spent by the cast, extra-time message)')
for n, v in got.items():
    print(f'  {n}: {v}')
base_t = got['afoot'][0]
# Controls: the unmounted cast takes time, and the mounted plain case shows
# the penalty (the path under test is reachable).
if base_t <= 0 or got['afoot'][1]:
    errors.append('control: afoot cast shows no time or an extra-time message')
if not got['plain'][1] or got['plain'][0] != base_t + 15:
    errors.append('control: plain mounted cast is not base + 15 with the message')
if errors:
    print('INCONCLUSIVE: ' + '; '.join(errors)); sys.exit(2)
for n, (ride, bal, mounted, extra) in cases.items():
    spent, msg = got[n]
    want = base_t + (15 if extra else 0)
    if msg != extra or spent != want:
        fails.append(f'{n}: message={msg} turns={spent}, expected message={extra} turns={want}')
if fails:
    print('FAIL: ' + '; '.join(fails) + '; controls hold'); sys.exit(1)
print('PASS: extra mounted casting time only below Ride 10 and Balance 20, not on a still spell')
PYCODE
