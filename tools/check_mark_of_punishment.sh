#!/bin/bash
# gate: live
# Does Mark of Punishment hurt the MARKED creature, and not the lawful creature
# it strikes? (bd inc-7mkt)
#
# THE DEFECT. lib/pspells.irh, Effect "Mark of Punishment": the TRAP_EVENT hook
# META(POST(EV_STRIKE)) runs with EActor = the marked creature and EVictim = the
# creature it struck. The hook tests EVictim for MA_LAWFUL (right), then makes
# the Will save with EVICTIM against the DC read off EVICTIM's own stati (the
# victim carries no such stati: DC -1, and SavingThrow fails every DC <= 0), and
# throws the Constitution damage at EVICTIM. So the lawful creature is the one
# that saves, and the one that is hurt. Ruled behavior: the MARKED creature
# makes the Will save against the DC on its own stati, and on a failure takes
# Con damage of N, the count of its unlawful strikes so far (1, 2, 3, ...).
# The lawful creature struck takes none.
#
# THE ORACLE. tools/keys/mark-of-punishment.keys plays the real game on seed 2:
# a lawful paladin touches a hostile ogre (the mark), then waits eight turns
# while the ogre strikes him. INCURSION_FORCE_SAVE_ROLL=1 makes every saving
# throw a natural 1, which always fails, so every unlawful strike takes damage.
# After each turn the script reads the ogre's Constitution (the A_CON line of
# its Examine page) and the paladin's (the sidebar CON). PASS needs, over the
# strikes the session shows:
#   - the ogre's cumulative Con loss steps by 1, then 2, then 3 (a turn that
#     holds two strikes steps by the sum, 1+2 = 3), for at least 3 strikes;
#   - the paladin's Constitution never changes.
# An empty parse, a mark that never landed, or fewer than 3 strikes is
# INCONCLUSIVE (exit 2), never a pass.
#
# WHAT THE UNFIXED TREE DOES. The first strike on the paladin calls ThrowDmg with
# no attacker (the hook reads the mark off the victim and gets NULL); the paladin's
# god-watch script logs "NULL object reference" and the game dies with SIGSEGV
# (exit 139) before the first Constitution read. The check reports that as FAIL.
#
# KNOWN TRAP FOR THE FIX. ThrowDmg sets only e.vDmg, but the Fight.cpp AD_DA*
# branch recomputes the damage as max(1, e.Dmg.Roll()) and e.Dmg is empty on a
# script-thrown event, so ThrowDmg(...,AD_DACO,N,...) takes 1 point whatever N is.
# A fix that passes N and nothing else reads 1,1,1 here and FAILs.
#
# Exit 0 pass, 1 the defect (or any other wrong behavior), 2 could not measure.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=2
KEYS=tools/keys/mark-of-punishment.keys
OPTIONS=tools/gates/Options.Dat

[ -x ./incursion-headless ] || {
    echo "INCONCLUSIVE(2): ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 2
}
[ -f "$KEYS" ] || { echo "INCONCLUSIVE(2): $KEYS is missing"; exit 2; }

RUN_DIR="$ROOT/logs/runs/$(date +%Y%m%d-%H%M%S)-$$-mark-of-punishment"
out="$(INCURSION_FORCE_SAVE_ROLL=1 INCURSION_RUN_DIR="$RUN_DIR" \
    INCURSION_OPTIONS="$OPTIONS" tools/headless.sh "$KEYS" "$SEED" 2>&1 </dev/null)"
status=$?
SHOTS="$RUN_DIR/logs/screens"
ERRLOG="$RUN_DIR/logs/errors.log"
echo "Specimen: $RUN_DIR (seed $SEED)"

# A signal or a Fatal is the game breaking. On the unfixed tree it is the
# defect's own first effect (see the header), so it is a FAIL and says so.
if [ "$status" -eq 1 ] || [ "$status" -ge 128 ]; then
    echo "FAIL(1): the session ended with exit $status before the Constitution reads finished."
    echo "         On the unfixed hook the first strike on the lawful creature throws damage with"
    echo "         no attacker and the game dies. Errors logged:"
    grep -E '^[0-9]' "$ERRLOG" 2>/dev/null | cut -c1-200 | sed 's/^/    | /'
    exit 1
fi
if [ "$status" -ne 0 ]; then
    echo "INCONCLUSIVE(2): tools/headless.sh exited $status; the key script did not finish."
    echo "$out" | tail -5 | sed 's/^/    | /'
    exit 2
fi

shopt -s nullglob
STATES=("$SHOTS"/*-state-[0-9][0-9].txt)
[ "${#STATES[@]}" -ge 5 ] || {
    echo "INCONCLUSIVE(2): found ${#STATES[@]} state screens in $SHOTS; expected 9."
    exit 2
}

# The touch must have landed: the message log is the proof.
LOGS="$(cat "$SHOTS"/*-log[0-9].txt 2>/dev/null)"
if ! grep -q "You have marked the ogre" <<< "$LOGS"; then
    echo "INCONCLUSIVE(2): no 'You have marked the ogre' line; the touch missed or the seed drifted."
    exit 2
fi

# One 'ogre_con paladin_con' pair per state screen, in order.
PAIRS=""
for f in "${STATES[@]}"; do
    ogre="$(grep -oE '^A_CON +[0-9]+ \(base [0-9]+' "$f" | grep -oE '[0-9]+' | sed -n '1p;2p' | tr '\n' ' ')"
    pal="$(grep -oE '\|CON: *[0-9]+' "$f" | grep -oE '[0-9]+$' | sed -n '1p')"
    if [ -z "$ogre" ] || [ -z "$pal" ]; then
        echo "INCONCLUSIVE(2): could not read Constitution from $f (ogre='$ogre' paladin='$pal')."
        exit 2
    fi
    PAIRS+="$ogre$pal"$'\n'
done

read -r -d '' PYCODE <<'PY'
import sys
rows = [tuple(int(x) for x in l.split()) for l in sys.stdin.read().splitlines() if l.strip()]
# each row: ogre current Con, ogre base Con, paladin Con
loss = [r[1] - r[0] for r in rows]
pal = [r[2] for r in rows]
print("OGRE_LOSS", " ".join(map(str, loss)))
print("PALADIN_CON", " ".join(map(str, pal)))
e = 1                      # the damage the next strike must do
ok = True
why = ""
for i in range(1, len(loss)):
    d = loss[i] - loss[i - 1]
    if d < 0:
        ok, why = False, "ogre Con rose between reads"
        break
    if d == 0:
        continue
    total, m = 0, 0
    while total < d:
        total += e + m
        m += 1
    if total != d:
        ok, why = False, "step of %d is not a sum of consecutive damages starting at %d" % (d, e)
        break
    e += m
if len(set(pal)) != 1:
    ok, why = False, "the lawful paladin's Constitution changed: %s" % pal
print("STRIKES", e - 1)
print("OK" if ok else "BAD " + why)
PY
verdict="$(python3 -I -c "$PYCODE" <<< "$PAIRS")"
echo "$verdict" | sed 's/^/  /'

if grep -q '^BAD' <<< "$verdict"; then
    echo "FAIL(1): $(grep '^BAD' <<< "$verdict" | sed 's/^BAD //')"
    echo "         Wanted: ogre Con loss 1, then 2, then 3 per failed-save strike; paladin Con unchanged."
    exit 1
fi
strikes="$(sed -n 's/^STRIKES //p' <<< "$verdict")"
if [ -z "$strikes" ] || [ "$strikes" -lt 3 ]; then
    echo "INCONCLUSIVE(2): only ${strikes:-0} strike(s) read; need 3 to see 1, 2, 3."
    exit 2
fi
echo "PASS: the marked ogre lost Con 1, 2, 3 over $strikes failed-save strikes; the lawful paladin lost none."
exit 0
