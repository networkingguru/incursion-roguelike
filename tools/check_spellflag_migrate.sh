#!/bin/bash
# gate: live
# inc-j5yo revision 5: loading a pre-revision-5 save migrates the player's
# spell flags exactly once, and the save that session writes comes back at
# revision 5 without migrating again.
#
# WHAT IS BEING GUARDED. Revision 5 gave SP_PENDING and SP_GRANTED meaning
# (the arcane selection for the next rest; a spell handed out by a class or
# script grant). A file written before revision 5 holds only SP_KNOWN bits,
# so Player::MigrateSpellFlagsRev5() runs once on load to set those two flags,
# and a save written afterwards -- by the very same binary -- must not run it
# a second time. Two runs, one keys script:
#
#   Run A  loads tools/fixtures/chars/orc-mage-seed1-opt0822.sav and must
#          report migrated=1 with the file's own revision. That fixture is
#          IS1.3, so the expected line is migrated=1 rev=3.
#   Run B  loads the save Run A wrote and must report migrated=0 rev=5, with
#          every spell flag exactly as Run A ended.
#
# THE ORACLE is INCURSION_SPELLFLAG_PROBE (src/Create.cpp, Player::
# SpellFlagProbe, src/Create.cpp:Player::MigrateSpellFlagsRev5). One
# errors.log line per known spell:
#
#   SPELLFLAG_PROBE <spell> known=1 pending=<0|1> granted=<0|1> arcane=<0|1>
#   SPELLFLAG_PROBE migrated=<0|1> rev=<file revision>
#
# The migration rules (bead inc-j5yo): the two spells of the specialist
# school on the class's SPECIALTY_SPELLS list that already carry SP_KNOWN
# become SP_GRANTED; every other known arcane spell that is neither granted
# nor a domain spell becomes SP_PENDING. So every known arcane spell is
# either granted=1 pending=0 or pending=1, and the migration changes no flag
# but those two.
#
# PROVED RED with --prove-red (docs/VERIFICATION.md step 2). The mutation
# removes the SP_PENDING assignment loop; the pending=1 spells then log
# pending=0 and this check exits 1. Recorded result in the report.
#
# Usage: tools/check_spellflag_migrate.sh [--prove-red]  (0 pass, 1 fail, 2 inconclusive)
. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat

FIXTURE=tools/fixtures/chars/orc-mage-seed1-opt0822.sav
SEED=1

# The mutation this check defends: the SP_PENDING assignment loop from
# Player::MigrateSpellFlagsRev5 (src/Create.cpp). Declared before any run so
# --prove-red intercepts here, before the (build-needing) measurement runs.
check_mutation src/Create.cpp \
'    for (i = 0; i <= MAX_SPELLS; i++)
        if ((Spells[i] & (SP_KNOWN | SP_ARCANE)) == (SP_KNOWN | SP_ARCANE) &&
            !(Spells[i] & (SP_GRANTED | SP_DOMAIN)))
            Spells[i] |= SP_PENDING;' \
'    /* mutation: SP_PENDING loop disabled */'

[ -f "$FIXTURE" ] || _check_die 2 \
    "no $FIXTURE, so there is no pre-revision-5 save to migrate."

# The fixture's own stamp is the revision Run A must report. Read it rather
# than type it: the test's claim is "the probe names the file's revision",
# and a literal here would hide a probe that reports a wrong one.
REV="$(dd if="$FIXTURE" bs=1 skip=4 count=5 2>/dev/null | sed 's/^IS1\.//')"
[ -n "$REV" ] || _check_die 2 \
    "$FIXTURE does not carry an IS1.<n> stamp, so its revision is unknown."

export INCURSION_SPELLFLAG_PROBE=1

# ---------------------------------------------------------------------------
# Run A: load the pre-revision-5 fixture. It must migrate.
export INCURSION_LOAD="$FIXTURE"
check_run tools/keys/spellflag-migrate.keys "$SEED"
RUN_A="$CHECK_RUN"
LOG_A="$RUN_A/logs/errors.log"
[ -f "$LOG_A" ] || _check_die 2 \
    "Run A logged nothing. The probe reports through Error(), so an empty" \
    "log means it never ran."

CLEAN_A="$(grep -v '^    ' "$LOG_A")"

summary() { printf '%s\n' "$1" | grep 'SPELLFLAG_PROBE migrated=' | head -1; }
spells()  { printf '%s\n' "$1" | grep 'SPELLFLAG_PROBE .* known=1' \
              | sed 's/^[0-9-]* [0-9:]*  //'; }

A_SUM="$(summary "$CLEAN_A")"
FAIL=0
if [ -z "$A_SUM" ]; then
    echo "FAIL: Run A logged no SPELLFLAG_PROBE summary line."
    echo "      Is INCURSION_SPELLFLAG_PROBE exported, and does this build"
    echo "      contain Player::SpellFlagProbe (src/Create.cpp)?"
    FAIL=1
elif ! printf '%s\n' "$A_SUM" | grep -q "migrated=1 rev=$REV\$"; then
    echo "FAIL: Run A must migrate the IS1.$REV fixture; its summary reads:"
    echo "      $A_SUM"
    FAIL=1
fi

# Every known arcane spell ends either granted=1 pending=0 (the class grant)
# or pending=1. Neither-and-arcane is the state the migration exists to fix.
A_SPELLS="$(spells "$CLEAN_A")"
if [ -z "$A_SPELLS" ]; then
    echo "FAIL: Run A logged no per-spell SPELLFLAG_PROBE lines."
    FAIL=1
fi
while IFS= read -r line; do
    [ -n "$line" ] || continue
    pend="$(printf '%s' "$line" | grep -oE 'pending=[01]' | sed 's/pending=//')"
    grant="$(printf '%s' "$line" | grep -oE 'granted=[01]' | sed 's/granted=//')"
    arc="$(printf '%s' "$line" | grep -oE 'arcane=[01]' | sed 's/arcane=//')"
    if [ "$arc" = "1" ] && [ "$pend" = "0" ] && [ "$grant" = "0" ]; then
        echo "FAIL: a known arcane spell is neither pending nor granted:"
        echo "      $line"
        FAIL=1
    fi
done <<< "$A_SPELLS"

# ---------------------------------------------------------------------------
# Run B: load the save Run A wrote. It must not migrate a second time, and
# the flags must match Run A's end state exactly.
A_SAVE="$(ls -t "$RUN_A"/save/*.sav 2>/dev/null | head -1)"
[ -n "$A_SAVE" ] || _check_die 2 \
    "Run A wrote no save under $RUN_A/save, so there is nothing to reload." \
    "The keys script must reach the System Menu's [b] Save and Continue."
STAMP_A="$(dd if="$A_SAVE" bs=1 skip=4 count=5 2>/dev/null)"
[ "$STAMP_A" = "IS1.5" ] || {
    echo "FAIL: Run A's save stamp is \"$STAMP_A\", wanted IS1.5."
    FAIL=1
}
cp "$A_SAVE" "$RUN_A/runA.sav"

export INCURSION_LOAD="$RUN_A/runA.sav"
check_run tools/keys/spellflag-migrate.keys "$SEED"
RUN_B="$CHECK_RUN"
LOG_B="$RUN_B/logs/errors.log"
[ -f "$LOG_B" ] || _check_die 2 "Run B logged nothing."

CLEAN_B="$(grep -v '^    ' "$LOG_B")"
B_SUM="$(summary "$CLEAN_B")"
if [ -z "$B_SUM" ]; then
    echo "FAIL: Run B logged no SPELLFLAG_PROBE summary line."
    FAIL=1
elif ! printf '%s\n' "$B_SUM" | grep -q 'migrated=0 rev=5$'; then
    echo "FAIL: Run B reloaded a revision-5 save and must not migrate; it reads:"
    echo "      $B_SUM"
    FAIL=1
fi

B_SPELLS="$(spells "$CLEAN_B")"
if [ "$A_SPELLS" != "$B_SPELLS" ]; then
    echo "FAIL: Run B's spell flags differ from Run A's end state."
    echo "--- Run A ---"; printf '%s\n' "$A_SPELLS"
    echo "--- Run B ---"; printf '%s\n' "$B_SPELLS"
    FAIL=1
fi

echo
echo "--- Run A (IS1.$REV fixture) ---"
printf '%s\n' "$A_SPELLS"; printf '%s\n' "$A_SUM"
echo "--- Run B (Run A's IS1.5 save) ---"
printf '%s\n' "$B_SPELLS"; printf '%s\n' "$B_SUM"
echo "specimen A: $LOG_A"
echo "specimen B: $LOG_B"

if [ "$FAIL" -ne 0 ]; then
    exit 1
fi

echo
echo "PASS: the IS1.$REV fixture migrated once (migrated=1 rev=$REV), every"
echo "      known arcane spell ended granted or pending, and reloading the"
echo "      IS1.5 save it wrote did not migrate again (migrated=0 rev=5)."
exit 0
