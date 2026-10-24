#!/bin/bash
# inc-yp23: before/after gameplay observation. A hiding rogue steps into a
# watcher's view and strikes it before the watcher acts.
#
#   tools/observe_hide_strike.sh <after-tree> <before-tree> [seeds=40]
#
# Both trees need a posix build (BACKEND=posix ./build_macos.sh) that carries
# src/HideStrikeProbe.cpp and its hook in src/Main.cpp; the file is identical in
# both. Exit: 0 old behaviour seen BEFORE, absent AFTER, control rolls AFTER;
# 1 AFTER lets a watcher perceive a hider at the strike with no watcher action;
# 2 could not measure (a trial set too small, or BEFORE shows no old behaviour).
#
# THE SCENE. The probe (INCURSION_HIDE_STRIKE_PROBE) finds, on the frozen map, a
# square P0, the square P1 east of it, and a square W north-east of P1, with a
# wall that hides P0 from W but not P1. It puts an awake hostile giant rat on W
# and the loaded rogue, hiding, on P0. The key script steps east to P1 (into the
# rat's view) and then strikes north-east. Both are real player commands.
#   freeze: the rat cannot act for 200 ticks, so it has no action between the
#           step and the blow. BEFORE rolled its spot check at the step; AFTER
#           must not roll it at all.
#   act:    the rat acts between the step and the blow (control).
#   freeze-lone: as freeze, but no other creature on the map is hiding. The old
#           HidePairsFor returned at once unless SOME OTHER creature was hiding,
#           so the old hider-side roll needs a second hider on the level; the
#           other modes put a sleeping, hiding rat far away.
# The count is of the game's own pre-strike line (INCURSION_SNEAK_PROBE, src/
# Fight.cpp): surprise=1 means the rat did not perceive the rogue at the blow.
#
# fact: character and map -- INCURSION_LOAD fixture orc-rogue-seed1-opt0822 (a save pins the level)
# fact: options -- INCURSION_OPTIONS=tools/fixtures/options-2026-08-22-noroomdesc.dat (no arrival-room box to eat keys)
# fact: scene squares, rat awake and hostile, rogue hiding, light off -- INCURSION_HIDE_STRIKE_PROBE places them and logs them; a run whose scene line is missing or INCONCLUSIVE is not counted
# fact: another creature hiding on the map -- probe places a sleeping hiding rat >40 squares away (not in -lone modes)
# fact: rat does or does not act between step and blow -- probe sets its Timeout (200 or 5)
# fact: the rat's spot roll -- NONE (no control); the check never asserts a roll value: AFTER/freeze must be 0 of N on any dice, BEFORE needs >=1 of N (exit 2 when 0)
# fact: Move Silently vs Listen at the STEP ("hears you! You are exposed!", a noise reveal, not a spot check; a spot reveal reads "You are exposed! Catching you off-guard" and is NOT excluded) -- NONE; those runs are counted apart and left out of the strike counts
# fact: Move Silently vs Listen after the blow ("hears you") -- NONE; reported, not asserted
set -uo pipefail
AFTER="${1:?after tree}"; BEFORE="${2:?before tree}"; N="${3:-40}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$(mktemp -d "$ROOT/logs/hide-strike-XXXXXX")"
OPTS="$ROOT/tools/fixtures/options-2026-08-22-noroomdesc.dat"
SAV="$ROOT/tools/fixtures/chars/orc-rogue-seed1-opt0822.sav"
for t in "$AFTER" "$BEFORE"; do [ -x "$t/incursion-headless" ] || { echo "INCONCLUSIVE: no posix build in $t"; exit 2; }; done
for arm in after before; do
  tree="$AFTER"; [ $arm = before ] && tree="$BEFORE"
  for mode in freeze act freeze-lone; do
    keys="$ROOT/tools/keys/hide-strike.keys"
    for seed in $(seq 1 "$N"); do
      run="$OUT/$arm-$mode-$seed"
      ( cd "$tree" && INCURSION_HIDE_STRIKE_PROBE=$mode INCURSION_SNEAK_PROBE=1 INCURSION_RUN_DIR="$run" \
          INCURSION_OPTIONS="$OPTS" INCURSION_LOAD="$SAV" tools/headless.sh "$keys" "$seed" > "$run.out" 2>&1 )
    done
  done
done
python3 - "$OUT" "$N" <<'PY'
import pathlib, re, sys
out = pathlib.Path(sys.argv[1]); n = int(sys.argv[2])
res = {}; example = {}
for arm in ('before', 'after'):
    for mode in ('freeze', 'act', 'freeze-lone'):
        c = dict(runs=0, bad=0, exposed=0, strikes=0, perceived=0, unperceived=0, hears=0, surprise_hit=0)
        for seed in range(1, n + 1):
            d = out / f'{arm}-{mode}-{seed}'
            err = d / 'logs/errors.log'; sn = d / 'logs/sneak.log'
            e = err.read_text() if err.exists() else ''
            if 'HIDE_STRIKE SCENE' not in e or 'HIDE_STRIKE INCONCLUSIVE' in e:
                c['bad'] += 1; continue
            c['runs'] += 1
            st = d / 'logs/screens'
            stepped = ''.join(f.read_text() for f in sorted(st.glob('*hide-strike-stepped*'))) if st.exists() else ''
            head = ' '.join(l[:64].strip() for l in stepped.splitlines()[:4])
            if re.search(r'hears you! You are exposed', head):
                c['exposed'] += 1; continue
            lines = sn.read_text().splitlines() if sn.exists() else []
            mine = [l for l in lines if 'victim=<giant rat>' in l and 'actor=<giant rat>' not in l]
            pre = [l for l in mine if ': pre ' in l]
            if not pre: continue
            c['strikes'] += 1
            p = pre[0]
            if 'surprise=0' in p: c['perceived'] += 1
            else: c['unperceived'] += 1
            if any(': hears-you' in l for l in mine): c['hears'] += 1
            if any(': attack ' in l and 'surprise=1' in l for l in mine): c['surprise_hit'] += 1
            key = (arm, mode, 'perceived' if 'surprise=0' in p else 'unperceived')
            example.setdefault(key, (d.name, p))
        res[(arm, mode)] = c
print(f'{"arm":7} {"mode":11} {"runs":>4} {"bad":>3} {"noise-exposed":>13} {"strikes":>7} {"perceived":>9} {"unperceived":>11} {"hears-you":>9} {"surprise-hits":>13}')
for (arm, mode), c in res.items():
    print(f'{arm:7} {mode:11} {c["runs"]:4} {c["bad"]:3} {c["exposed"]:13} {c["strikes"]:7} {c["perceived"]:9} {c["unperceived"]:11} {c["hears"]:9} {c["surprise_hit"]:13}')
for k, (name, line) in sorted(example.items()):
    print(f'EXAMPLE {k[0]}/{k[1]}/{k[2]}: {name}: {line}')
bf, af, ac = res[('before', 'freeze')], res[('after', 'freeze')], res[('after', 'act')]
print(f'specimens: {out}')
bl, al = res[('before', 'freeze-lone')], res[('after', 'freeze-lone')]
print(f'lone hider (no second hider on the map): BEFORE perceived {bl["perceived"]}/{bl["strikes"]}, AFTER perceived {al["perceived"]}/{al["strikes"]}')
if min(bf['strikes'], af['strikes']) < max(5, n // 2):
    print('INCONCLUSIVE: too few strikes measured'); sys.exit(2)
if af['perceived'] > 0 or al['perceived'] > 0:
    print('RED: AFTER, a watcher perceived the hider at the blow with no action of its own'); sys.exit(1)
if bf['perceived'] == 0:
    print('INCONCLUSIVE: BEFORE showed no perception at the blow; the old behaviour was not seen'); sys.exit(2)
if ac['perceived'] == 0:
    print('INCONCLUSIVE: AFTER control: the watcher never perceived once it acted'); sys.exit(2)
print('GREEN: BEFORE perceives at the blow, AFTER never does, AFTER control perceives once the watcher acts')
PY
