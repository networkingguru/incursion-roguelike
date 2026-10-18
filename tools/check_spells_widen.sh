#!/bin/bash
# gate: live
# inc-vqla phase 2: a v1 save written before Character::Spells[] was widened
# loads with the flags the file actually holds -- and the loader is exercised
# on both a current-revision (IS1.6) and a legacy (IS1.3) file.
#
# WHAT IS BEING GUARDED. Phase 1 widened Character::Spells[] from uint16 to
# uint32 and retired the old tag-434 (2049 x uint16) array, whose read now runs
# through Registry::V1ArrayWiden16 (inc/Creature.h:1145). A regression there --
# dropping the legacy read, or folding it wrongly into the new tag 448 -- would
# silently lose or misread a pre-change save's flags. Because a raw uint16 and
# its uint32 widening share the low bits, the whole 32-bit word must survive
# the round trip; this check watches the whole word, not one named bit.
#
# THE ORACLE is INCURSION_SPELLFLAG_PROBE (src/Create.cpp, Player::
# SpellFlagProbe). It reports one errors.log line per spell index whose flag
# word is non-zero, and phase 2 appended two fields to each such line:
#
#   SPELLFLAG_PROBE <spell> known=<0|1> pending=<0|1> ... pend_pri=<0|1> \
#       idx=<Spells[] index> raw=0x<whole flag word>
#
# The earlier fields are untouched, so every check that greps them still
# parses. The oracle is checked against an INDEPENDENT reader of the file,
# tools/v1_spells_tag434.py, which does not use the engine at all: it finds the
# zlib stream, decompresses it, and reads the retired tag-434 array (tag b2 01,
# kind 11, count 2049, size 2, then 4098 bytes of uint16) directly. Agreement
# between the engine's probe and that reader is what makes this a check rather
# than a restatement.
#
# TWO RUNS.
#
#   IS1.6  tools/fixtures/chars/human-priest-mage-seed4-gate.sav, written by
#          master BEFORE this change. Its flags are a faithful copy of the file
#          (no migration runs: migrated=0), so the probe's idx/raw pairs must
#          equal the python reader's exactly -- every pair the file holds
#          appears with the same raw value, and the probe reports no non-zero
#          index the file lacks.
#
#   IS1.3  tools/fixtures/chars/orc-priest-seed4-gate.sav, whose flags ARE
#          migrated on load (migrated=1), so its raw words deliberately change.
#          The check asserts only that the load succeeds and the probe prints
#          lines, proving the legacy read is exercised on a rev-3 file too.
#
# PROVED RED with --prove-red (docs/VERIFICATION.md step 2). The declared
# mutation deletes the `r.V1ArrayWiden16(448, 434, Spells, MAX_SPELLS+1);` call
# in inc/Creature.h:1145. Without it the loader never reads tag 434; the v0
# loader refuses the file (or the flags come back empty), so the IS1.6 probe
# disagrees with the python reader and the check fails. --prove-red performs
# this mutation itself on a scratch copy of Creature.h (the check_lib mechanism
# restores it), rebuilds, re-runs, and restores.
#
# Usage: tools/check_spells_widen.sh [--prove-red]
#        (0 pass, 1 fail, 2 inconclusive)
. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat

FIXTURE=tools/fixtures/chars/human-priest-mage-seed4-gate.sav
SEED=4
LEGACY=tools/fixtures/chars/orc-priest-seed4-gate.sav
LEGACY_SEED=4
READER=tools/v1_spells_tag434.py

# The mutation this check defends: the phase-1 legacy read of tag 434. Declared
# before any run so --prove-red intercepts here, before the measurement runs.
check_mutation inc/Creature.h \
'      r.V1ArrayWiden16(448, 434, Spells, MAX_SPELLS+1);' \
'      /* mutation: tag-434 legacy widen disabled */'

[ -f "$FIXTURE" ] || _check_die 2 \
    "no $FIXTURE, so there is no pre-change v1 save to compare."
[ -f "$LEGACY" ] || _check_die 2 \
    "no $LEGACY, so there is no legacy-revision save to load."
[ -f "$READER" ] || _check_die 2 \
    "no $READER, so there is no independent reader to compare against."
command -v python3 >/dev/null 2>&1 || _check_die 2 \
    "python3 is not on PATH, so the independent reader cannot run."

# The file's own tag-434 words, one "idx raw" pair per line.
FILE_PAIRS="$(python3 -I "$READER" "$FIXTURE")" || _check_die 2 \
    "$READER could not read $FIXTURE (exit $?)."
if [ -z "$FILE_PAIRS" ]; then
    _check_die 2 "$READER found no non-zero tag-434 element in $FIXTURE," \
        "so there is nothing to compare."
fi

# run_session <label> <fixture> <seed> -- one sandboxed session, run directly
# (not through check_run, whose verdict calls a refused load INCONCLUSIVE).
# It records the headless exit status, the run directory and its errors.log in
# RUN, STATUS and LOG, and never dies: whether a run with no probe lines is a
# FAIL (the load was refused) or INCONCLUSIVE is the caller's call.
STAMP="$(date +%Y%m%d-%H%M%S)-$$"
run_session() { # <label> <fixture> <seed>
    local label="$1" fixture="$2" seed="$3" out
    export INCURSION_SPELLFLAG_PROBE=1
    export INCURSION_LOAD="$fixture"
    RUN="$PWD/logs/runs/$STAMP-$label-spells-widen"
    mkdir -p "$RUN"
    out="$(INCURSION_RUN_DIR="$RUN" INCURSION_OPTIONS="$CHECK_OPTIONS" \
        tools/headless.sh tools/keys/spellflag-migrate.keys "$seed" \
        2>&1 </dev/null)"
    STATUS=$?
    printf '%s\n' "$out" > "$RUN/harness.txt"
    LOG="$RUN/logs/errors.log"
    echo "  session ($label): $RUN (seed $seed, headless exit $STATUS)"
}

export INCURSION_LOAD="$FIXTURE"
[ -n "$CHECK_OPTIONS" ] && [ -f "$CHECK_OPTIONS" ] || _check_die 2 \
    "CHECK_OPTIONS names a file that is not there: $CHECK_OPTIONS"
run_session is16 "$FIXTURE" "$SEED"
LOG_16="$LOG"
RUN_16="$RUN"

# With the tag-434 widen gone the loader refuses the file before the probe can
# print, and errors.log carries the refusal ("not one this binary reads" /
# "File is Corrupt") with no SPELLFLAG_PROBE lines. That is precisely the
# defect this check watches, so it is a FAIL. A run that logged nothing at all,
# or logged neither the probe nor a refusal, is INCONCLUSIVE instead.
_load_refused() { # <errors.log> <harness output>
    grep -q 'tag 434\|File is Corrupt\|File Version Mismatch' "$1" 2>/dev/null && return 0
    printf '%s\n' "$2" | grep -q 'File is Corrupt\|File Version Mismatch'
}

if [ ! -f "$LOG_16" ]; then
    echo "FAIL: the IS1.6 run logged nothing (headless exit $STATUS); the" \
        "legacy tag-434 read is missing or the load was refused."
    echo "      See $RUN_16."
    exit 1
fi

CLEAN="$(grep -v '^    ' "$LOG_16")"
SPELLS="$(printf '%s\n' "$CLEAN" | grep -E 'SPELLFLAG_PROBE [A-Za-z].* known=' \
    | sed 's/^[0-9-]* [0-9:]*  //')"
if [ -z "$SPELLS" ]; then
    if _load_refused "$LOG_16" "$(cat "$RUN_16/harness.txt" 2>/dev/null)"; then
        echo "FAIL: the IS1.6 fixture was refused (headless exit $STATUS) and" \
            "the probe printed no lines; the legacy tag-434 read is missing."
        echo "      See $RUN_16."
        exit 1
    fi
    _check_die 2 "the IS1.6 run logged no per-spell SPELLFLAG_PROBE lines."
fi

# The probe's "idx raw" set, normalized to one "idx raw" per line.
PROBE_PAIRS="$(printf '%s\n' "$SPELLS" \
    | sed -n 's/.* idx=\([0-9]*\) raw=\(0x[0-9A-Fa-f]*\).*/\1 \2/p')"
if [ -z "$PROBE_PAIRS" ]; then
    _check_die 2 "the IS1.6 probe lines carry no idx=/raw= fields; the" \
        "inc-vqla phase-2 fields are missing from src/Create.cpp."
fi

SORTED_FILE="$(printf '%s\n' "$FILE_PAIRS" | sort)"
SORTED_PROBE="$(printf '%s\n' "$PROBE_PAIRS" | sort)"

FAIL=0
# Every pair the file holds must appear with the same raw value in the probe.
MISSING="$(comm -23 <(printf '%s\n' "$SORTED_FILE") \
    <(printf '%s\n' "$SORTED_PROBE"))"
if [ -n "$MISSING" ]; then
    echo "FAIL: the probe does not match the file's tag-434 flags at:"
    printf '%s\n' "$MISSING" | sed 's/^/      /'
    FAIL=1
fi
# And the probe must report no non-zero index the file lacks.
EXTRA="$(comm -13 <(printf '%s\n' "$SORTED_FILE") \
    <(printf '%s\n' "$SORTED_PROBE"))"
if [ -n "$EXTRA" ]; then
    echo "FAIL: the probe reports flags the file's tag-434 array does not:"
    printf '%s\n' "$EXTRA" | sed 's/^/      /'
    FAIL=1
fi

# ---------------------------------------------------------------------------
# The IS1.3 legacy save: its flags are migrated on load, so only the exercise
# of the legacy read is asserted -- the load succeeds and the probe prints.
run_session is13 "$LEGACY" "$LEGACY_SEED"
RUN_L="$RUN"
LOG_L="$LOG"
[ -f "$LOG_L" ] || _check_die 2 \
    "the IS1.3 run logged nothing. The probe reports through Error(), so an" \
    "empty log means it never ran."
CLEAN_L="$(grep -v '^    ' "$LOG_L")"
L_SPELLS="$(printf '%s\n' "$CLEAN_L" \
    | grep -E 'SPELLFLAG_PROBE [A-Za-z].* known=' \
    | sed 's/^[0-9-]* [0-9:]*  //')"
if [ -z "$L_SPELLS" ]; then
    echo "FAIL: the IS1.3 legacy run logged no per-spell SPELLFLAG_PROBE lines."
    FAIL=1
fi
L_SUM="$(printf '%s\n' "$CLEAN_L" | grep 'SPELLFLAG_PROBE migrated=' | head -1)"
if [ -z "$L_SUM" ]; then
    echo "FAIL: the IS1.3 legacy run logged no SPELLFLAG_PROBE summary line."
    FAIL=1
fi

echo
echo "--- IS1.6 fixture (flags as the file holds them) ---"
printf '%s\n' "$SORTED_FILE" | sed 's/^/  file:  /'
printf '%s\n' "$SORTED_PROBE" | sed 's/^/  probe: /'
echo "--- IS1.3 legacy fixture (flags migrated on load) ---"
printf '%s\n' "$L_SUM"
printf '%s\n' "$L_SPELLS" | head -20
echo "specimen IS1.6: $LOG_16"
echo "specimen IS1.3: $LOG_L"

if [ "$FAIL" -ne 0 ]; then
    echo
    echo "FAIL: a pre-change v1 save did not load with the flags the file"
    echo "      holds -- the tag-434 legacy widen is wrong or absent."
    exit 1
fi

echo
echo "PASS: the IS1.6 fixture's tag-434 words, read independently by"
echo "      $READER, all appear in the probe with the same raw value and no"
echo "      extra word appears; the IS1.3 legacy run migrated and probed."
exit 0
