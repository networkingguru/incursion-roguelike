#!/bin/bash
# gate: live
# Does tools/soak.sh in fixture mode (SOAK_CHAR) build the same character for
# every session but give each session its own dungeon? (bead inc-nch.1)
#
# The defect it guards. A .char fixture builds ONE level: the one its own
# `seed:` line names. Loaded under different session seeds without a rewrite,
# every session would start on the same level-1 map, and a 100-session soak
# would be one dungeon a hundred times. soak.sh therefore writes a per-seed copy
# of the .char with `seed: <session seed>`; only that line may change.
#
# The check soaks three sessions from the fixture, with tools/keys/load-char-sheet.keys
# (it starts in play, dumps the arrival map and the character sheet, plays one
# turn) and asserts:
#   1 the soak exits 0 and each session exits 0;
#   2 each session built its own copy: <name>-s<N>.char holds `seed: N`, differs
#     from the fixture in that one line only, and the session's save/ holds that
#     build as <name>-s<N>.sav.backup (the game renames the loaded file when it saves);
#   3 the character sheets are byte-identical across the sessions;
#   4 the arrival maps are not all identical;
#   5 the report prints the three outcome lines (never reached play, died,
#     stalled at the death prompt) and counts no session as never reaching play;
#   6 soak.sh refuses, exit 2, a fixture-mode soak whose key script includes
#     chargen.keys, and a SOAK_CHAR that names no fixture.
#
# --selftest: run the same check against a copy of soak.sh with the seed rewrite
#   removed (the copy is a transient file in tools/, deleted on exit). The check
#   MUST go red, on assertions 2 and 4. Exits 0 when it does.
#
# fact: character -- fixture orc-barbarian-seed1-opt0822, built from a per-session copy whose only change is the seed: line; the sheet each session prints is compared across sessions, never read for a value
# fact: level-1 map -- never read for a square; the check asserts only that the arrival maps are not all identical, and the only thing that differs between sessions is the rewritten seed: line, the subject under test
# fact: settings -- INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat, the file the fixture's options: line names
# fact: play after the load -- load-char-sheet.keys plays one turn; no monster, hit or death count is read except that the report prints its lines and counts no session as never reaching play
# fact: the report text -- the labels this check greps are written by tools/soak.sh in the same commit
#
# Usage: tools/check_soak_char.sh [--selftest]
# Exit: 0 pass; 1 fail; 2 could not run.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

if [ "${1:-}" = "--selftest" ]; then
    out="$(SOAK_CHAR_MUTATE=no-seed-rewrite "$0" 2>&1)"
    rc=$?
    if [ "$rc" -ne 1 ]; then
        echo "FAIL: selftest: the no-seed-rewrite mutation exited $rc, want 1"; exit 1
    fi
    grep -q 'FAIL: the arrival maps are all identical' <<< "$out" || {
        echo "FAIL: selftest: the mutation went red, but not on the identical maps"; echo "$out" | tail -5; exit 1; }
    echo "PASS: selftest: with the seed rewrite removed the check fails (identical maps)"
    exit 0
fi

[ -x ./incursion-headless ] || { echo "./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"; exit 2; }

FIX=orc-barbarian-seed1-opt0822
KEYS=tools/keys/load-char-sheet.keys
export INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat
T="$(mktemp -d "${TMPDIR:-/tmp}/soak-char.XXXXXX")" || exit 2
MUT=""
trap 'rm -rf "$T"; [ -n "$MUT" ] && rm -f "$MUT"' EXIT

SOAKSH=tools/soak.sh
if [ "${SOAK_CHAR_MUTATE:-}" = "no-seed-rewrite" ]; then
    MUT="$ROOT/tools/.soak-mutant.$$.sh"
    sed 's|sed "s/^seed:.\*/seed: \$seed/" "\$CHARSRC"|cat "$CHARSRC"|' tools/soak.sh > "$MUT"
    cmp -s "$MUT" tools/soak.sh && { echo "FAIL: the mutation did not apply"; exit 2; }
    chmod +x "$MUT"
    SOAKSH="$MUT"
fi

FAILS=0
fail() { echo "FAIL: $*"; FAILS=$((FAILS + 1)); }

SOAK_DIR="$T/soak" SOAK_JOBS=3 SOAK_CHAR="$FIX" "$SOAKSH" 3 1 "$KEYS" > "$T/report.txt" 2>&1
rc=$?
[ "$rc" -eq 0 ] || fail "the fixture soak exited $rc, want 0"
[ "$(wc -l < "$T/soak/exits" 2>/dev/null | tr -d ' ')" = "3" ] || fail "exits file does not hold 3 sessions"
bad="$(awk '$2 != 0' "$T/soak/exits" 2>/dev/null | wc -l | tr -d ' ')"
[ "$bad" = "0" ] || fail "$bad of 3 sessions ended with a non-zero exit"

for s in 1 2 3; do
    cf="$T/soak/$FIX-s$s.char"
    if [ ! -f "$cf" ]; then fail "session $s has no per-seed copy $FIX-s$s.char"; continue; fi
    [ "$(grep '^seed:' "$cf")" = "seed: $s" ] || fail "per-seed copy $s does not hold 'seed: $s' (holds '$(grep '^seed:' "$cf")')"
    [ "$(diff "$cf" "tools/fixtures/chars/$FIX.char" | grep -c '^[<>]')" -le 2 ] || fail "per-seed copy $s differs from the fixture in more than the seed: line"
    # The game renames the loaded file to <name>.sav.backup when it saves; that
    # file is the build the session loaded, and it must be this seed's build.
    cmp -s "$T/soak/seed-$s/save/$FIX-s$s.sav.backup" "$T/soak/fixture-cache"/*/"$FIX-s$s.sav" || fail "session $s did not load its own build (save/$FIX-s$s.sav.backup is not the cached $FIX-s$s.sav)"
done

sheets=0; maps=0
for s in 1 2 3; do
    [ -f "$T/soak/seed-$s/logs/screens/0003-sheet.txt" ] && [ -f "$T/soak/seed-$s/logs/screens/0001-arrival.txt" ] || { fail "session $s dumped no sheet or arrival screen"; continue; }
done
sheets="$(for s in 1 2 3; do shasum < "$T/soak/seed-$s/logs/screens/0003-sheet.txt"; done | sort -u | wc -l | tr -d ' ')"
maps="$(for s in 1 2 3; do tail -n +2 "$T/soak/seed-$s/logs/screens/0001-arrival.txt" | shasum; done | sort -u | wc -l | tr -d ' ')"
[ "$sheets" = "1" ] || fail "the character sheets differ across sessions ($sheets distinct)"
[ "$maps" -ge 2 ] || fail "the arrival maps are all identical across 3 sessions"

for label in 'never reached play' 'died (' 'stalled at the death prompt'; do
    grep -qF "$label" "$T/report.txt" || fail "the report has no '$label' line"
done
grep -qE '^ +0  never reached play' "$T/report.txt" || fail "the report counts a session as never reaching play"

SOAK_DIR="$T/refuse1" SOAK_CHAR="$FIX" "$SOAKSH" 1 1 tools/keys/dive.keys > "$T/refuse1.txt" 2>&1
[ "$?" -eq 2 ] && grep -q 'chargen.keys' "$T/refuse1.txt" || fail "a fixture soak with a chargen script was not refused with exit 2"
SOAK_DIR="$T/refuse2" SOAK_CHAR=no-such-fixture "$SOAKSH" 1 1 "$KEYS" > "$T/refuse2.txt" 2>&1
[ "$?" -eq 2 ] || fail "a SOAK_CHAR naming no fixture was not refused with exit 2"

if [ "$FAILS" -ne 0 ]; then
    echo "check_soak_char: $FAILS assertion(s) failed"
    exit 1
fi
echo "PASS: 3 sessions, each built its own copy; sheets identical; $maps distinct arrival maps; report counts printed"
exit 0
