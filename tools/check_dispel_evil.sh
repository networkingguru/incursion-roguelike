#!/bin/bash
# gate: live
# inc-5v5l: Dispel Evil follows the SRD -- one touch per casting, the touch
# ends the whole spell (the +4/+6 deflection bonus and any remaining touch)
# once it lands on an evil creature, AND the deflection bonus itself must
# actually fire on a real attack, not just sit in the data as a dead grant.
#
# THE RULE (lib/pspells.irh, "Dispel Evil"). Two components:
#   Component 0 (the base declaration, xval TRAP_EVENT, yval
#   EVICTIM(EV_STRIKE)) must actually be EA_INFLICT, not EA_GENERIC.
#   Magic::MagicHit's eval switch (src/Magic.cpp) does nothing for
#   EA_GENERIC, so that action type never grants the TRAP_EVENT stati the
#   component names, and the META(EVICTIM(EV_STRIKE)) handler that applies
#   the +4/+6 bonus never gets registered to fire at all. EA_INFLICT is the
#   pattern the structurally identical "Combat Mind" (lib/alchemy.irh) uses
#   for the same idiom.
#   Component 1 (aval AR_TOUCH) carries lval, the number of touches per
#   casting: it must be a flat 1, not LEVEL_1PER2 (one per two caster
#   levels). Its EV_MAGIC_HIT handler, when the touch lands on an evil
#   creature -- either the banish branch or the dispel-magic branch --
#   must remove every stati this effect granted the caster
#   (EActor->RemoveEffStati(e.eID)): both TOUCH_ATTACK and component 0's
#   TRAP_EVENT deflection bonus, if any is present.
#
# THE ORACLE for the touch has two parts. The DISPEL_EVIL_PROBE build
# (src/Fight.cpp) logs three lines per landed touch, at the landed-touch
# path in Creature::Hit's AfterEffects:
#   before -- just before the touch's EV_MAGIC_HIT fires (this casting's
#             current TOUCH_ATTACK magnitude, and whether the TRAP_EVENT
#             deflection stati is present on the caster: defl=).
#   mid    -- right after EV_MAGIC_HIT returns, BEFORE Fight.cpp's own
#             generic TOUCH_ATTACK decrement runs. This is the only point
#             that can tell "the spell's own handler discharged everything"
#             apart from "Fight.cpp's ordinary per-touch decrement removed
#             the last charge anyway" -- both read touch=0/0 by the time
#             "after" logs, regardless of whether inc-5v5l's fix is present,
#             once lval is a flat 1.
#   after  -- once Fight.cpp's own decrement has run.
# Each line reads token pairs including touch=<TOUCH_ATTACK magnitude>/<1 if
# present else 0>, defl=<1 if the TRAP_EVENT deflection stati is present,
# else 0> and any=<1 if any stati under this eID remains, else 0>.
#
# THE ORACLE for the deflection bonus is the game's own combat-roll line,
# already stored in the message log because OPT_STORE_ROLLS is on in
# tools/gates/Options.Dat (src/Fight.cpp prints "Attack: 1d20 (n) ... vs.
# Def <breakdown> = N [hit/miss]", and this spell's own META handler's
# e.strDef append lands inside that breakdown). The handler writes
# "e.strDef += XPrint(" +<Num> DispEv",bonus - curr)", so the literal label
# must read "+4 DispEv" or "+6 DispEv" (inc-5v5l's third defect: this used to
# read "e.strDef += XPrint(" +%d DispEv",...)", printf's token rather than
# XPrint's own <Num>, so the game printed the LITERAL text "+%d DispEv"
# instead of the real bonus -- found only because the EA_INFLICT fix made
# the handler run in play for the first time). The check requires BOTH: the
# label's own printed number is exactly 4 or 6, AND it agrees with the
# bonus computed arithmetically -- BASE (the number right after "Def ") plus
# every OTHER named term's own signed number, versus TOTAL (the number
# right after the final "="), attributing whatever is left over to the term
# named DispEv. It also fails outright if "%d" appears anywhere in the
# message log: that substring can only mean the old, unsubstituted format
# came back.
#
# THE SCENES:
#   tools/keys/dispel-evil-touch.keys -- an orc priest of Aiswin raised to
#   character level 11 learns Dispel Evil through Learn Any Spell (SP_INNATE,
#   so caster level == character level == 11). A goblin (evil, not an
#   outsider, so a landed touch takes the dispel-magic branch, not banish) is
#   summoned two squares away; the script closes the distance and
#   bump-attacks until a touch lands.
#   tools/keys/dispel-evil-deflection.keys -- a fresh, un-levelled orc priest
#   (the deflection bonus is flat, not level-scaled) with Infinite Mana only,
#   casts Dispel Evil, summons a goblin ADJACENT with Freeze Monsters left
#   OFF, and waits three turns so the hostile goblin gets to attack the
#   caster on its own turn, before any touch happens.
#
# ASSERTS:
#   (a) exactly one "before" line, reading touch=1/1 defl=1 -- one touch per
#       casting at every caster level, not scaled by LEVEL_1PER2, and the
#       deflection stati present on the caster before the touch.
#   (b) at least one "Attack:" line in the deflection scene's message log
#       carries the literal label "+4 DispEv" (or "+6 DispEv" for an
#       M_IALIGN attacker), and that label's own number agrees with what the
#       breakdown's arithmetic attributes to it -- the bonus actually
#       applies to a real attack roll, correctly labelled, not merely
#       exists in the data. No line anywhere in the log may contain "%d".
#   (c) the touch scene's "mid" line already reads touch=0/0 defl=0 any=0 --
#       the spell's own handler discharged everything BEFORE Fight.cpp's
#       generic decrement had a chance to. Without inc-5v5l's RemoveEffStati
#       call, "mid" still reads touch=1/1 any=1 (Fight.cpp's decrement has
#       not run yet), and only "after" would reach 0/0 -- so "mid" is the
#       line that must go red under that mutation.
#
# FAILS outright (not "inconclusive") on NO GAMEPLAY, a missing/empty probe
# log, or no DispEv attack line in the deflection scene: all three mean the
# run measured nothing about the thing it exists to check.
#
# Build (module first, THEN the probe -- EXTRA_CXXFLAGS builds deliberately
# do not recompile mod/Incursion.Mod, see build_macos.sh's game-data section,
# so a stale module would silently hide a lib/ fix):
#   BACKEND=posix ./build_macos.sh
#   EXTRA_CXXFLAGS=-DDISPEL_EVIL_PROBE OUT=incursion-dispel-evil BACKEND=posix ./build_macos.sh
# Usage: tools/check_dispel_evil.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

BIN=./incursion-dispel-evil
TOUCH_KEYS=tools/keys/dispel-evil-touch.keys
DEFL_KEYS=tools/keys/dispel-evil-deflection.keys
SEED=1
OPTIONS=tools/gates/Options.Dat

field() { # field "<line>" "<prefix>"  ->  value, or empty if absent
    awk -v p="$2" '{for(i=1;i<=NF;i++) if (index($i,p)==1) {print substr($i,length(p)+1); exit}}' <<< "$1"
}

[ -x "$BIN" ] || {
    echo "FAIL: $BIN not built. Run:"
    echo "  BACKEND=posix ./build_macos.sh"
    echo "  EXTRA_CXXFLAGS=-DDISPEL_EVIL_PROBE OUT=incursion-dispel-evil BACKEND=posix ./build_macos.sh"
    exit 1
}

TMP="$(mktemp -d -t dispel-evil-check.XXXXXX)" || exit 2
trap "rm -rf '$TMP'" EXIT

# --- scene 1: the touch (assertions a and c) ---------------------------
RUN="$TMP/touch-run"

OUT="$(INCURSION_BIN="$BIN" INCURSION_OPTIONS="$OPTIONS" INCURSION_RUN_DIR="$RUN" \
    tools/headless.sh "$TOUCH_KEYS" "$SEED" 2>&1)"
STATUS=$?

if grep -q "NO GAMEPLAY" <<< "$OUT"; then
    echo "FAIL: the touch scene never entered a map, so it measured nothing."
    echo "$OUT"
    exit 1
fi
if [ "$STATUS" -ne 0 ]; then
    echo "$OUT" | tail -20
    echo "FAIL: tools/headless.sh exited $STATUS on the touch scene."
    exit 1
fi

LOG="$RUN/logs/dispel-evil-touch.log"
[ -s "$LOG" ] || {
    echo "FAIL: no (or empty) probe log at $LOG. The cast or the touch never happened."
    exit 1
}

BEFORE_COUNT="$(grep -c '^before ' "$LOG")"
FIRST_BEFORE="$(awk '/^before / {print; exit}' "$LOG")"
MID_LINE="$(awk '/^mid / {print; exit}' "$LOG")"

BEFORE_TOUCH="$(field "$FIRST_BEFORE" "touch=")"
BEFORE_DEFL="$(field "$FIRST_BEFORE" "defl=")"
MID_TOUCH="$(field "$MID_LINE" "touch=")"
MID_DEFL="$(field "$MID_LINE" "defl=")"
MID_ANY="$(field "$MID_LINE" "any=")"

echo "Dispel Evil touch scene: $BEFORE_COUNT landed touch(es), first touch=$BEFORE_TOUCH defl=$BEFORE_DEFL, mid touch=$MID_TOUCH defl=$MID_DEFL any=$MID_ANY"

[ "$BEFORE_COUNT" = 1 ] ||
    { echo "FAIL: $BEFORE_COUNT landed touches, expected exactly 1 (one touch per casting, every caster level)."; exit 1; }
[ "$BEFORE_TOUCH" = "1/1" ] ||
    { echo "FAIL: the casting's only touch read magnitude $BEFORE_TOUCH, expected 1/1 -- lval is not a flat 1."; exit 1; }
[ "$BEFORE_DEFL" = 1 ] ||
    { echo "FAIL: before the touch, defl=$BEFORE_DEFL, expected 1 -- the deflection stati was never granted on cast (component 0 is not EA_INFLICT, or its dispatch is broken)."; exit 1; }
[ -n "$MID_LINE" ] ||
    { echo "FAIL: no 'mid' probe line -- the touch handler never returned to Fight.cpp."; exit 1; }
[ "$MID_TOUCH" = "0/0" ] && [ "$MID_DEFL" = 0 ] && [ "$MID_ANY" = 0 ] ||
    { echo "FAIL: mid touch=$MID_TOUCH defl=$MID_DEFL any=$MID_ANY, expected 0/0, 0 and 0 -- the touch landed on an evil creature but the spell's own handler did not discharge it (RemoveEffStati) before Fight.cpp's own decrement ran."; exit 1; }

# --- scene 2: the deflection bonus on a real attack (assertion b) ------
DEFL_RUN="$TMP/deflection-run"

DEFL_OUT="$(INCURSION_BIN="$BIN" INCURSION_OPTIONS="$OPTIONS" INCURSION_RUN_DIR="$DEFL_RUN" \
    tools/headless.sh "$DEFL_KEYS" "$SEED" 2>&1)"
DEFL_STATUS=$?

if grep -q "NO GAMEPLAY" <<< "$DEFL_OUT"; then
    echo "FAIL: the deflection scene never entered a map, so it measured nothing."
    echo "$DEFL_OUT"
    exit 1
fi
if [ "$DEFL_STATUS" -ne 0 ]; then
    echo "$DEFL_OUT" | tail -20
    echo "FAIL: tools/headless.sh exited $DEFL_STATUS on the deflection scene."
    exit 1
fi

MSG="$(ls "$DEFL_RUN"/logs/screens/*messages-top*.txt 2>/dev/null | head -1)"
[ -n "$MSG" ] || {
    echo "FAIL: the deflection scene left no *messages-top*.txt screen."
    exit 1
}

# Reconstruct the message box's logical text: strip the left margin and the
# "|"-delimited sidebar, keep exactly the content between the first and the
# LAST pipe on each row, and join every row with a single space so a line
# the game wrapped mid-sentence (e.g. "...+4" | "DispEv = 14 [miss]") reads
# as one sentence again.
BOXTEXT="$(sed -n 's/^ *| \(.*\)|[^|]*$/\1/p' "$MSG" | sed 's/[[:space:]]*$//' | tr '\n' ' ')"

grep -q '%d' <<< "$BOXTEXT" &&
    { echo "FAIL: the message log contains the literal text \"%d\" -- XPrint's format string regressed to printf's token instead of <Num>."; exit 1; }

DEFL_RESULT="$(python3 - <<'PY' "$BOXTEXT"
import re
import sys

text = sys.argv[1]
pat = re.compile(
    r"Attack: 1d20 \(\d+\)[^=]*=\s*-?\d+ vs\. Def (-?\d+)"
    r"((?:\s+[+-]\S+\s+\S+)*?)\s*=\s*(-?\d+)\s*\[(\w+)\]"
)
term_pat = re.compile(r"([+-])(\S+)\s+(\S+)")

found = 0
bad = []
for m in pat.finditer(text):
    base, terms_str, total, result = int(m.group(1)), m.group(2), int(m.group(3)), m.group(4)
    terms = term_pat.findall(terms_str)
    dispev_terms = [(sign, num) for sign, num, name in terms if name == "DispEv"]
    if not dispev_terms:
        continue
    found += 1
    sign, num = dispev_terms[0]
    if not re.fullmatch(r"\d+", num):
        bad.append(f"unsubstituted label ({sign}{num} DispEv)")
        continue
    label_value = int(num) if sign == "+" else -int(num)
    known_sum = 0
    for s, n, name in terms:
        if name == "DispEv":
            continue
        known_sum += int(n) if s == "+" else -int(n)
    attributed = total - base - known_sum
    print(f"LINE base={base} terms={terms} total={total} result={result} "
          f"label={sign}{num} attributed={attributed}")
    if label_value not in (4, 6):
        bad.append(f"label={sign}{num}, not +4 or +6")
    elif label_value != attributed:
        bad.append(f"label={sign}{num} but the breakdown's own arithmetic gives {attributed}")

print(f"FOUND {found}")
print(f"BAD {'; '.join(bad)}")
PY
)"

echo "$DEFL_RESULT" | grep -v '^FOUND \|^BAD '
DEFL_FOUND="$(sed -n 's/^FOUND //p' <<< "$DEFL_RESULT")"
DEFL_BAD="$(sed -n 's/^BAD //p' <<< "$DEFL_RESULT")"

echo "Dispel Evil deflection scene: $DEFL_FOUND DispEv attack line(s) found"

[ "${DEFL_FOUND:-0}" -ge 1 ] ||
    { echo "FAIL: no attack line named DispEv in the deflection scene's message log -- the caster was never attacked by the evil creature before any touch, or the bonus never applied. This check cannot see what it exists to check."; exit 1; }
[ -z "$DEFL_BAD" ] ||
    { echo "FAIL: $DEFL_BAD"; exit 1; }

echo "PASS: Dispel Evil grants exactly one touch per casting; the +4/+6 deflection stati is present on the caster before any touch and actually raises Def by a correctly-labelled +4 on a real attack; and the touch discharges the whole spell (TOUCH_ATTACK and the deflection stati) the instant it lands on an evil creature, before Fight.cpp's own generic decrement runs."
