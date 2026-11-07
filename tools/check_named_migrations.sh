#!/bin/bash
# gate: live
# inc-cjos0 phase 4: a data migration has a NAME, the Game record saves the
# names applied (field "Migrations"), and a load runs every known migration the
# file lacks. A file of revision >= a migration's impliedRev counts as having it
# even when its list lacks the name (SaveV1 migration table, src/SaveV1.cpp).
#
# THE ORACLE is the line Registry.cpp logs under INCURSION_SPELLFLAG_PROBE:
#   MIGRATION_PROBE ran=<comma list, or empty> rev=<file revision>
#
# CASES (each is one headless load of a frozen character, tools/keys/
# spellflag-migrate.keys, which also saves once with Save and Continue):
#   1  IS1.4 fixture   -> ran=SpellFlagsRev5,SpellFlagsRev6
#   2  IS1.6 fixture   -> ran=            (its revision implies both)
#   2b the save case 2 wrote holds the text SpellFlagsRev5,SpellFlagsRev6 (the
#      Game record's Migrations field; INCURSION_V1_RAW=1 keeps it greppable)
#   3  the IS1.<CUR> save case 2 wrote -> ran=   and the save's stamp is current
#      (the Migrations list the writer saved is what makes the revision-<CUR>
#      reload run nothing; a writer that saves a short list runs the rest)
#
# PROVED RED with --prove-red, two mutations (run both, see the report):
#   default          the writer saves only SpellFlagsRev5 -> case 3 runs
#                    SpellFlagsRev6.
#   --reader         the reader ignores impliedRev -> case 2 runs both.
# There is no pure-logic part, so there is no --selftest.
#
# Usage: tools/check_named_migrations.sh [--prove-red] [--reader]
#        (0 pass, 1 fail, 2 inconclusive)
. "$(dirname "$0")/check_lib.sh"

# fact: settings -- options-2026-08-22.dat (CHECK_OPTIONS)
# fact: the character -- fixtures tools/fixtures/chars/orc-bard-reapply-seed1.sav (IS1.4) and elf-mage-spotted-seed1.sav (IS1.6) (INCURSION_LOAD)
# fact: the fixtures' revisions -- read from each fixture's IS1.<n> stamp
# fact: the revision this build writes -- read from the SCHEMA_REV define in src/SaveV1.cpp, not typed here
# fact: the migration names -- the table in src/SaveV1.cpp; no dice, the seed only names the run
CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat

OLD=tools/fixtures/chars/orc-bard-reapply-seed1.sav
NEW=tools/fixtures/chars/elf-mage-spotted-seed1.sav
SEED=1
KEYS=tools/keys/spellflag-migrate.keys

READER_FIRST=0
for _arg in "$@"; do [ "$_arg" = "--reader" ] && READER_FIRST=1; done
unset _arg

_mut_writer() {
    check_mutation inc/Res.h \
'            migs = SaveV1_MigrationList();' \
'            migs = "SpellFlagsRev5"; /* mutation: short list */'
}
_mut_reader() {
    check_mutation src/SaveV1.cpp \
'        if (m.impliedRev && m.impliedRev <= v1FileRevision)
          continue;' \
'        /* mutation: impliedRev ignored */'
}
if [ "$READER_FIRST" = 1 ]; then _mut_reader; _mut_writer; else _mut_writer; _mut_reader; fi

stamp() { dd if="$1" bs=1 skip=4 count=5 2>/dev/null; }
for f in "$OLD" "$NEW"; do
    [ -f "$f" ] || _check_die 2 "no $f."
done
OLD_REV="$(stamp "$OLD" | sed 's/^IS1\.//')"
NEW_REV="$(stamp "$NEW" | sed 's/^IS1\.//')"
CUR="$(sed -n 's/^#define SCHEMA_REV[[:space:]]\{1,\}\([0-9]\{1,\}\).*/\1/p' src/SaveV1.cpp | head -1)"
[ -n "$CUR" ] || _check_die 2 "cannot parse SCHEMA_REV from src/SaveV1.cpp."
[ "$OLD_REV" -lt 5 ] && [ "$NEW_REV" -ge 6 ] && [ "$NEW_REV" -lt "$CUR" ] || \
    _check_die 2 "fixture revisions $OLD_REV / $NEW_REV do not fit (<5, 6..$((CUR-1)))."

export INCURSION_SPELLFLAG_PROBE=1
export INCURSION_V1_RAW=1   # DEBUG writer: uncompressed, so the Migrations text is greppable
FAIL=0

# probe_of <fixture> -> sets RUN and PROBE (the MIGRATION_PROBE line)
probe_of() {
    export INCURSION_LOAD="$1"
    check_run "$KEYS" "$SEED"
    RUN="$CHECK_RUN"
    [ -f "$RUN/logs/errors.log" ] || _check_die 2 "no errors.log in $RUN."
    PROBE="$(grep -v '^    ' "$RUN/logs/errors.log" | grep 'MIGRATION_PROBE' \
             | head -1 | sed 's/^[0-9-]* [0-9:]*  //')"
    [ -n "$PROBE" ] || _check_die 2 "$RUN logged no MIGRATION_PROBE line."
}
want() { # <case> <expected line>
    if [ "$PROBE" != "$2" ]; then
        echo "FAIL case $1: wanted \"$2\""
        echo "      got    \"$PROBE\""
        FAIL=1
    fi
}

probe_of "$OLD"; want 1 "MIGRATION_PROBE ran=SpellFlagsRev5,SpellFlagsRev6 rev=$OLD_REV"
probe_of "$NEW"; want 2 "MIGRATION_PROBE ran= rev=$NEW_REV"
SAVE="$(ls -t "$RUN"/save/*.sav 2>/dev/null | head -1)"
[ -n "$SAVE" ] || _check_die 2 "case 2 wrote no save under $RUN/save."
[ "$(stamp "$SAVE")" = "IS1.$CUR" ] || { echo "FAIL: case 2's save is $(stamp "$SAVE"), wanted IS1.$CUR."; FAIL=1; }
grep -aq "SpellFlagsRev5,SpellFlagsRev6" "$SAVE" || {
    echo "FAIL: case 2's save does not hold Migrations = SpellFlagsRev5,SpellFlagsRev6."
    FAIL=1
}
cp "$SAVE" "$RUN/case2.sav"
probe_of "$RUN/case2.sav"; want 3 "MIGRATION_PROBE ran= rev=$CUR"

echo "specimen: $RUN/logs/errors.log"
if [ "$FAIL" -ne 0 ]; then exit 1; fi
echo "PASS: IS1.$OLD_REV ran both migrations, IS1.$NEW_REV ran none, and the IS1.$CUR"
echo "      save it wrote ran none on reload."
exit 0
