#!/bin/bash
# gate: live
# Does OPT_AUTO_TERMS ("Auto-Offer Terms", Options.Dat byte 312) make the game
# offer terms before it asks "Confirm attack fleeing victim?"  (bd inc-gfq2)
#
#   BACKEND=posix ./build_macos.sh
#   tools/check_auto_terms.sh               # expect exit 0
#   tools/check_auto_terms.sh --prove-red   # forces byte 312 to 0 for the "on"
#                                           # runs; expect the check to FAIL
#
# THE SCENARIO. The Lawful Good paladin fixture attacks a fleeing, sapient,
# hostile creature, so attackSanity (src/Fight.cpp) would ask the fleeing-victim
# question. Two ways to make the victim flee:
#   natural  tools/keys/auto-terms-natural.keys. A wizard-summoned ogre is hit
#            until the engine gives it AFRAID/FEAR_HP ("turns to flee!"). Creature::
#            OfferTerms accepts that fear.
#   magic    tools/keys/auto-terms-magic.keys. A black orc under repeated Cause
#            Fear (FEAR_MAGIC). OfferTerms refuses by rule.
#
# THE FOUR OUTCOMES, each read off the engine's own log and screen dumps:
#   1  option on, natural fear, Diplomacy succeeds: "accepts your terms", no
#      prompt, and no attack by the paladin after it.
#   2  option on, natural fear, Diplomacy fails: "refuses your terms", no
#      prompt, and the paladin's attack follows.
#   3  option on, magic fear: "You can't offer terms to magically frightened
#      creatures." and then the existing prompt.
#   4  option off: the prompt, and no offer, for natural fear and magic fear.
# Outcomes 1 and 2 hang on a Diplomacy roll. A seed fixes the roll, so the check
# plays seeds 1..SEEDS (default 40), skips a seed whose ogre dies before it
# flees, and needs at least one seed of each result. A run that cannot show its
# own staging is INCONCLUSIVE (exit 2), never a pass.
#
# Exit 0 = all four proved, 1 = a FAIL, 2 = could not measure.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [ "${1:-}" = "--prove-red" ]; then
    AUTO_TERMS_ON_BYTE=0 "$0"
    rc=$?
    if [ "$rc" -eq 1 ]; then
        echo "PROVE-RED OK: with byte 312 forced to 0 the check FAILED (exit 1), as it must."
        exit 0
    fi
    echo "PROVE-RED BAD: the check exited $rc with byte 312 forced to 0; it should exit 1."
    exit 1
fi

ON_BYTE="${AUTO_TERMS_ON_BYTE:-1}"
SEEDS="${SEEDS:-40}"
BASE=tools/fixtures/options-2026-08-22-noroomdesc.dat
CHAR=tools/fixtures/chars/human-paladin-seed4-opt0822.sav
STAMP="$(date +%Y%m%d-%H%M%S)-$$"
OUT="$ROOT/logs/runs/auto-terms-$STAMP"

# The generation byte and its current value, read from inc/Defines.h at run
# time. The fixture was written before OPT_SETTINGS_GEN existed, so its stamp is
# 0; leaving it there would make MigrateOptions (src/OptionsGen.cpp) force byte
# 312 back to 1 at load and undo the "off" staging. Reading OPT_GEN_CURRENT
# rather than hard-coding it keeps this correct when a generation is added.
SETTINGS_GEN_IDX="$(sed -nE 's/^#define[[:space:]]+OPT_SETTINGS_GEN[[:space:]]+([0-9]+).*/\1/p' inc/Defines.h | head -1)"
GEN_CURRENT="$(sed -nE 's/^#define[[:space:]]+OPT_GEN_CURRENT[[:space:]]+([0-9]+).*/\1/p' inc/Defines.h | head -1)"
if ! [ "$SETTINGS_GEN_IDX" -ge 0 ] 2>/dev/null || ! [ "$GEN_CURRENT" -ge 0 ] 2>/dev/null; then
    echo "INCONCLUSIVE: could not parse OPT_SETTINGS_GEN ($SETTINGS_GEN_IDX) or OPT_GEN_CURRENT ($GEN_CURRENT) from inc/Defines.h"
    exit 2
fi

[ -x ./incursion-headless ] || {
    echo "INCONCLUSIVE: build first with BACKEND=posix ./build_macos.sh"
    exit 2
}
for f in "$BASE" "$CHAR" tools/keys/auto-terms-natural.keys tools/keys/auto-terms-magic.keys; do
    [ -f "$f" ] || { echo "INCONCLUSIVE: missing $f"; exit 2; }
done
unset INCURSION_BIN INCURSION_LAUNCHER
mkdir -p "$OUT"

# Settings: a copy of the fixture with byte 312 set. The tracked file is never
# written. "on" gets ON_BYTE (1, or 0 under --prove-red); "off" gets 0.
cp -f "$BASE" "$OUT/off.dat"
cp -f "$BASE" "$OUT/on.dat"
printf '\000' | dd of="$OUT/off.dat" bs=1 seek=312 conv=notrunc 2>/dev/null
if [ "$ON_BYTE" = 1 ]; then
    printf '\001' | dd of="$OUT/on.dat" bs=1 seek=312 conv=notrunc 2>/dev/null
else
    printf '\000' | dd of="$OUT/on.dat" bs=1 seek=312 conv=notrunc 2>/dev/null
fi
# Stamp both copies at the current generation, so MigrateOptions treats the
# byte-312 write above as the player's own choice and leaves it alone.
printf "$(printf '\\%03o' "$GEN_CURRENT")" | \
    dd of="$OUT/off.dat" bs=1 seek="$SETTINGS_GEN_IDX" conv=notrunc 2>/dev/null
printf "$(printf '\\%03o' "$GEN_CURRENT")" | \
    dd of="$OUT/on.dat" bs=1 seek="$SETTINGS_GEN_IDX" conv=notrunc 2>/dev/null

runs=0
run() { # <settings name> <keys> <seed> <dir name>
    INCURSION_OPTIONS="$OUT/$1.dat" INCURSION_LOAD="$CHAR" \
        INCURSION_RUN_DIR="$OUT/$4" \
        tools/headless.sh "$2" "$3" > "$OUT/$4.out" 2>&1
    runs=$((runs + 1))
}

for v in on off; do
    run "$v" tools/keys/auto-terms-magic.keys 4 "magic-$v"
done
for s in $(seq 1 "$SEEDS"); do
    for v in on off; do
        run "$v" tools/keys/auto-terms-natural.keys "$s" "natural-$v-$s"
    done
done

made=$(find "$OUT" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
if [ "$made" != "$runs" ]; then
    echo "INCONCLUSIVE: $runs runs but $made run directories (runs shared a directory)"
    exit 2
fi

python3 -I - "$OUT" "$SEEDS" "$ON_BYTE" <<'PY'
import re
import sys
from pathlib import Path

out, seeds, on_byte = Path(sys.argv[1]), int(sys.argv[2]), sys.argv[3]
PROMPT = "Confirm attack fleeing victim?"
CANT = "You can't offer terms to magically frightened creatures."
fails, notes = [], []


def screens(run):
    return run / "logs" / "screens"


def dump(run, label):
    hits = list(screens(run).glob("*-" + label + ".txt"))
    return hits[0].read_text() if len(hits) == 1 else None


def log_text(run):
    """The message log screen as one whitespace-collapsed string."""
    raw = dump(run, "log")
    if raw is None:
        return None
    parts = []
    for line in raw.split("\n")[1:]:
        m = re.match(r"^\s*\|\s?(.*?)\s*\|", line)
        if m:
            parts.append(m.group(1))
    return re.sub(r"\s+", " ", " ".join(parts))


def fail(msg):
    fails.append(msg)


# ---- outcomes 3 and 4 (magic fear) -----------------------------------------
mon, moff = out / "magic-on", out / "magic-off"
a_on, a_off = dump(mon, "attack"), dump(moff, "attack")
if a_on is None or a_off is None:
    print("INCONCLUSIVE: the magic-fear sessions never reached their attack screen")
    sys.exit(2)
if PROMPT not in a_off:
    print("INCONCLUSIVE: option off, magic fear: no fleeing-victim prompt, staging failed")
    sys.exit(2)
if CANT in a_off:
    fail("outcome 4 (magic): option off, yet an offer was tried: " + CANT)
if PROMPT not in a_on:
    fail("outcome 3: option on, magic fear: no existing prompt after the refused offer")
if CANT not in a_on:
    fail("outcome 3: option on, magic fear: the rules refusal '%s' never appeared" % CANT)

# ---- outcomes 1, 2 and 4 (natural fear) ------------------------------------
accepted, refused, viable = [], [], 0
for s in range(1, seeds + 1):
    on, off = out / ("natural-on-%d" % s), out / ("natural-off-%d" % s)
    off_attack, on_attack = dump(off, "attack"), dump(on, "attack")
    off_sw, on_sw = dump(off, "switches"), dump(on, "switches")
    if off_attack is None or on_attack is None or off_sw is None or on_sw is None:
        continue                         # the ogre died before it fled: skip the seed
    if not re.search(r"Freeze Monsters\s+YES", off_sw + on_sw):
        continue
    if PROMPT not in off_attack:
        fail("seed %d, outcome 4: option off, natural fear: no fleeing-victim prompt" % s)
        continue
    off_log = log_text(off)
    if off_log and re.search(r"(accepts|refuses) your terms", off_log):
        fail("seed %d, outcome 4: option off, yet terms were offered" % s)
    viable += 1
    lg = log_text(on)
    if lg is None:
        fail("seed %d: option on: no message log screen" % s)
        continue
    if PROMPT in on_attack or PROMPT in (dump(on, "after") or ""):
        fail("seed %d: option on, natural fear: the prompt appeared" % s)
    acc, ref = lg.find("accepts your terms"), lg.find("refuses your terms")
    if acc < 0 and ref < 0:
        fail("seed %d, outcomes 1/2: option on, natural fear: terms were never offered" % s)
    elif acc >= 0:
        accepted.append(s)
        if "Vorkai's Attack:" in lg[acc:]:
            fail("seed %d, outcome 1: the paladin attacked after the ogre accepted terms" % s)
    else:
        refused.append(s)
        if "Vorkai's Attack:" not in lg[ref:]:
            fail("seed %d, outcome 2: no attack followed the refusal" % s)

print("natural-fear seeds that reached the attack: %d of %d" % (viable, seeds))
print("  outcome 1 (accepted): seeds %s" % accepted)
print("  outcome 2 (refused):  seeds %s" % refused)
print("  on-byte at 312: %s    run directory: %s" % (on_byte, out))

if fails:
    print("FAIL:")
    for f in fails:
        print("  " + f)
    sys.exit(1)
if viable == 0:
    print("INCONCLUSIVE: no natural-fear seed reached the attack screen")
    sys.exit(2)
if not accepted or not refused:
    print("INCONCLUSIVE: need both an accepted and a refused offer; widen SEEDS")
    sys.exit(2)
print("PASS: outcome 1 accepted (no prompt, no attack), outcome 2 refused (no prompt, attack),")
print("      outcome 3 magic fear (rules refusal, then the prompt), outcome 4 option off (prompt, no offer).")
PY
