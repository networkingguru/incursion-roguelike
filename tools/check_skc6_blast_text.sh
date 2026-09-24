#!/bin/bash
# gate: live
# Assert the Magic::Blast Damage line is clean for bead inc-skc6.
#
#   tools/check_skc6_blast_text.sh      exit 0 pass, 1 a failed assertion,
#                                        2 the check could not be run
#
# Bead inc-skc6. `String` had no copy constructor, so an implicit copy shared
# the source's Buffer: the first destructor freed it and the second freed it
# again. src/Effects.cpp:279's `(const char*)(e.strDmg ? e.strDmg : "")` has
# type String, so the `?:` copy-constructed a temporary sharing e.strDmg's
# buffer and freed it -- the freed text showed as garbage on the Damage line and
# was freed again at exit (SIGABRT, exit 134). Separately Magic::Blast printed
# the caller's e.strDmg that it never cleared, so modifier text from an outer
# event (a weapon hit, a previous area-spell victim) landed on the blast's own
# Damage line. Two measurements below, one per defect.
#
# MEASUREMENT 1: THE SHARED-BUFFER ABORT. tools/keys/inc-skc6-biocurrent-
# touch.keys builds a wizard-mode priest, grants and casts the innate power
# Biocurrent, summons a giant rat, and attacks it. The attack is a magic
# touch, so the Damage line goes through Magic::Blast. The key script dumps
# screens; the Damage line for the Biocurrent hit reads
# `Damage: 1d12+2 = <n> Lightning`.
#
# The session must exit 0 -- before the copy-constructor and cast fix it
# aborts with exit 134, which is the red result. And at least one damage
# screen must carry a line matching exactly
# `Damage: 1d12+2 = <digits> Lightning`, with nothing between the dice and
# ` = ` (the shared-buffer and uncleared-strDmg defects both put text there).
# A run that shows no Damage line at all FAILS: finding nothing is not a pass.
#
# MEASUREMENT 2: THE LEFTOVER LORE TEXT. tools/keys/inc-skc6-blast-leftover.
# keys (see that file's own header for the full story and the two dead ends
# it took to get here) grants Lore of Storms via a test god
# (tools/fixtures/inc-skc6-blast-god.irh, spliced onto a SCRATCH copy of
# lib/main.irc, never the tracked file -- see _build_scratch below), learns
# the globe spell Electric Loop, summons two brown bears one square apart,
# and casts it. Magic::AGlobe (src/Magic.cpp) reuses ONE EventInfo across
# both bears with no per-victim reset, so on the unfixed build the SECOND
# bear's Damage line carries the FIRST bear's " +1 Lore" as well as its own:
# `Damage: (1d4+2) / 2 +1 Lore +1 Lore = 3 Lightning`. Fixed, each bear's
# line carries exactly one Lore term. A run showing no Damage line, or fewer
# than two, FAILS: finding nothing (or only one hit) is not a pass.
#
# The pinned options file is tools/fixtures/options-2026-08-22.dat, as in the
# bead's own reproduction. Each run gets a fresh directory.
#
# Commands (Brian's brief, docs/VERIFICATION.md):
#   BACKEND=posix ./build_macos.sh
#   tools/check_skc6_blast_text.sh      # green on the fixed build
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[ -x ./incursion-headless ] || { echo "INCONCLUSIVE: build with BACKEND=posix ./build_macos.sh"; exit 2; }

OPTIONS="${INCURSION_OPTIONS:-tools/fixtures/options-2026-08-22.dat}"
[ -f "$OPTIONS" ] || { echo "INCONCLUSIVE: settings file $OPTIONS is not there"; exit 2; }
KEYS=tools/keys/inc-skc6-biocurrent-touch.keys
[ -f "$KEYS" ] || { echo "INCONCLUSIVE: key script $KEYS is not there"; exit 2; }

TOKEN="${INCURSION_CHECK_TOKEN:-$$-$(date +%s)}"
RUN_DIR="$ROOT/logs/runs/check-skc6-$TOKEN"
rm -rf "$RUN_DIR"

echo "--- measurement 1: the shared-buffer abort (Biocurrent touch) ---"
echo "options: $OPTIONS"
echo "keys:    $KEYS"

out="$(INCURSION_OPTIONS="$OPTIONS" INCURSION_RUN_DIR="$RUN_DIR" \
        tools/headless.sh "$KEYS" 1 2>&1)"
STATUS=$?
echo "$out" | sed 's/^/  | /'
echo

if [ "$STATUS" -ne 0 ]; then
    echo "FAIL: the session exited $STATUS; before the fix it aborts with exit 134"
    exit 1
fi

# The Damage line appears on the after-strike screen and in the message log.
# Read every screen; assert one line matches the exact shape.
MATCHES="$(grep -hoE 'Damage: 1d12\+2 = [0-9]+ Lightning' "$RUN_DIR"/logs/screens/*.txt 2>/dev/null | sort -u)"
LINES="$(grep -hoE 'Damage: [^|]*' "$RUN_DIR"/logs/screens/*.txt 2>/dev/null | sort -u)"

if [ -z "$LINES" ]; then
    echo "FAIL: no Damage line at all in $RUN_DIR/logs/screens -- nothing was measured"
    exit 1
fi

if [ -z "$MATCHES" ]; then
    echo "FAIL: no Damage line matches 'Damage: 1d12+2 = <digits> Lightning'"
    echo "      Damage line(s) seen:"
    echo "$LINES" | sed 's/^/        /'
    exit 1
fi

echo "Damage line(s) matched:"
echo "$MATCHES" | sed 's/^/  /'
echo
echo "measurement 1: PASS -- the session exits 0 and the Biocurrent Damage"
echo "               line is exactly 'Damage: 1d12+2 = <digits> Lightning'"
echo

# --- measurement 2: the leftover Lore text (Magic::AGlobe, two victims) -----
#
# Build a scratch copy of lib/ under logs/, with tools/fixtures/inc-skc6-
# blast-god.irh appended (the Lore-of-Storms grant route). Same shape as
# tools/check_heal_maladies.sh's _build_scratch: the tracked lib/ is never
# touched, and headless.sh's own `ln -sfn "$ROOT/mod" "$RUN/mod"` (and the
# matching one for lib/) cannot clobber a REAL pre-existing directory at
# that path on macOS -- it places the symlink INSIDE it instead -- so the
# scratch module and god-augmented lib survive being handed to headless.sh.
LEFTOVER_KEYS=tools/keys/inc-skc6-blast-leftover.keys
GOD_FIXTURE=tools/fixtures/inc-skc6-blast-god.irh
[ -f "$LEFTOVER_KEYS" ] || { echo "INCONCLUSIVE: key script $LEFTOVER_KEYS is not there"; exit 2; }
[ -f "$GOD_FIXTURE" ] || { echo "INCONCLUSIVE: fixture $GOD_FIXTURE is not there"; exit 2; }

SCRATCH_DIR="$ROOT/logs/runs/check-skc6-leftover-$TOKEN"
rm -rf "$SCRATCH_DIR"
mkdir -p "$SCRATCH_DIR/mod" "$SCRATCH_DIR/save" "$SCRATCH_DIR/logs"
cp -Rf "$ROOT/lib" "$SCRATCH_DIR/lib" || { echo "INCONCLUSIVE: could not copy lib/"; exit 2; }
ln -sfn "$ROOT/inc" "$SCRATCH_DIR/inc"
cat "$GOD_FIXTURE" >> "$SCRATCH_DIR/lib/main.irc"

INCURSIONPATH="$SCRATCH_DIR/" ./incursion-headless -compile main.irc \
    < /dev/null > "$SCRATCH_DIR/compile.log" 2>&1
if [ ! -f "$SCRATCH_DIR/mod/Incursion.Mod" ]; then
    echo "--- compile output ---"
    tail -30 "$SCRATCH_DIR/compile.log"
    echo "INCONCLUSIVE: the scratch module (with the test god appended) did not compile"
    exit 2
fi

echo "--- measurement 2: the leftover Lore text (two-victim AGlobe) ---"
echo "options: $OPTIONS"
echo "keys:    $LEFTOVER_KEYS"

out2="$(INCURSION_OPTIONS="$OPTIONS" INCURSION_RUN_DIR="$SCRATCH_DIR" \
        tools/headless.sh "$LEFTOVER_KEYS" 1 2>&1)"
STATUS2=$?
echo "$out2" | sed 's/^/  | /'
echo

if [ "$STATUS2" -ne 0 ]; then
    echo "FAIL: the leftover-text session exited $STATUS2"
    exit 1
fi

DMG_LINES="$(grep -ahoE "Brown bear's Damage: [^|]*" "$SCRATCH_DIR"/logs/screens/*.txt 2>/dev/null | sort -u)"

if [ -z "$DMG_LINES" ]; then
    echo "FAIL: no brown bear Damage line at all in $SCRATCH_DIR/logs/screens --"
    echo "      nothing was measured"
    exit 1
fi

HIT_COUNT="$(printf '%s\n' "$DMG_LINES" | grep -c 'Lightning')"
if [ "$HIT_COUNT" -lt 2 ]; then
    echo "FAIL: only $HIT_COUNT distinct brown bear Damage line(s) seen; need one"
    echo "      per bear (two) to say anything about leftover text"
    printf '%s\n' "$DMG_LINES" | sed 's/^/        /'
    exit 1
fi

LEFTOVER="$(printf '%s\n' "$DMG_LINES" | grep -E '\+1 Lore.*\+1 Lore')"
if [ -n "$LEFTOVER" ]; then
    echo "FAIL: a Damage line carries leftover Lore text from an earlier victim:"
    printf '%s\n' "$LEFTOVER" | sed 's/^/        /'
    exit 1
fi

echo "Damage line(s) matched:"
printf '%s\n' "$DMG_LINES" | sed 's/^/  /'
echo
echo "measurement 2: PASS -- two distinct brown bear Damage lines, neither"
echo "               carrying another victim's Lore text"
echo

echo "PASS: both inc-skc6 measurements are clean"
exit 0
