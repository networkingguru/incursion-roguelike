#!/bin/bash
# gate: live
# Does a first-level specialist mage still KNOW the two spells of his school
# after the grant moved from the script switch to a * SPECIALTY_SPELLS list?
# (bd inc-j5yo)
#
# THE CHANGE. lib/classes.irh's Mage EV_ADVANCE used to gain the two spells of
# the specialist's school from a nine-case switch, two GainSpell calls each.
# The spells are now a * SPECIALTY_SPELLS list on the Mage class (school order
# 0-8, two spells each) that src/Create.cpp reads after the class EV_ADVANCE
# event and grants with GainSpell. The switch keeps only case 7's
# WG_LIGHT proficiency, which is not a spell. The player-visible result must be
# identical: level one still knows exactly the two spells of his school.
#
# THE ORACLE is the character dump's "Known Spells:" section. It is written by
# the engine's own writer (DumpCharacter, src/Sheet.cpp), but only from
# Game::SaveGame under INCURSION_CHAR_PROBE=1 (src/Registry.cpp:1105-1111), so
# each key script finishes character generation and saves. A sheet that never
# reached the save has no charprobe.txt and is INCONCLUSIVE (exit 2), not a
# pass.
#
# WHAT IS ASSERTED, per school. The two spells from lib/classes.irh
# SPECIALTY_SPELLS for that school must appear in the Known Spells section:
#
#   Evocation   (school 4): Magic Missile, Shield
#   Necromancy  (school 6): Minor Drain, Phase Door
#
# The expected pairs are written out here rather than read from lib/ so that a
# silent edit to the list cannot make this check agree with it. Each pair is
# also the same pair the removed switch granted for that case, so a pass here
# is a pass for NO behaviour change.
#
# PROVED RED on 2026-10-16 by commenting out the grant in src/Create.cpp (the
# `if (LevelAs(ClassID[c]) == 1)` block after RES(ClassID[c])->Event), rebuilding
# with BACKEND=posix ./build_macos.sh, and running this check: both schools
# reported their ground-caster spells only and neither specialty pair was
# present (exit 1). Restoring the block and rebuilding made it pass again.
#
# Usage: tools/check_specialty_grant.sh
#   0 every school knows both of its specialty spells
#   1 a school is missing one or both
#   2 could not measure (no charprobe.txt or a bad run)
# Quiet: one line per school plus a total; runs live under logs/runs/.
. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat
OPTIONS="$CHECK_OPTIONS"
SEED=42

[ -x ./incursion-headless ] || _check_die 2 "incursion-headless is not built." \
    "Run: BACKEND=posix ./build_macos.sh"

STAMP="$(date +%Y%m%d-%H%M%S)-$$"
FAIL=0; UNMEAS=0; NCASES=0

# school label | key script | spell one | spell two
while IFS='|' read -r school keys spell1 spell2; do
    [ -n "$school" ] || continue
    NCASES=$((NCASES + 1))

    RUN="$PWD/logs/runs/$STAMP-specialty-grant-$school"
    INCURSION_OPTIONS="$OPTIONS" INCURSION_CHAR_PROBE=1 \
        INCURSION_RUN_DIR="$RUN" \
        tools/headless.sh "$keys" "$SEED" > "$RUN.out" 2>&1
    rc=$?
    if [ "$rc" -ne 0 ]; then
        echo "$school: UNMEASURED headless.sh exited $rc (see $RUN.out)"
        UNMEAS=1
        continue
    fi
    PROBE="$RUN/logs/charprobe.txt"
    if [ ! -f "$PROBE" ]; then
        echo "$school: UNMEASURED no logs/charprobe.txt under $RUN"
        UNMEAS=1
        continue
    fi

    # Read only the Known Spells section: from its header line to the next
    # blank line. A spell name in the inventory or the journal must not count.
    SECTION="$(awk '/^Known Spells:/{p=1;next} p&&/^[[:space:]]*$/{exit} p' "$PROBE")"
    if [ -z "$SECTION" ]; then
        echo "$school: UNMEASURED no Known Spells section in charprobe.txt"
        UNMEAS=1
        continue
    fi

    missing=""
    case "$SECTION" in *"$spell1"*) ;; *) missing="$spell1";; esac
    case "$SECTION" in *"$spell2"*) ;; *) missing="${missing:+$missing, }$spell2";; esac
    if [ -n "$missing" ]; then
        echo "$school: FAIL missing specialty spell(s): $missing"
        FAIL=1
        continue
    fi
    echo "$school: ok knows $spell1 and $spell2"
done <<'CASES'
Evocation|tools/keys/specialty-grant-check.keys|Magic Missile|Shield
Necromancy|tools/keys/specialty-grant-check-nec.keys|Minor Drain|Phase Door
CASES

if [ "$UNMEAS" -ne 0 ]; then
    echo "INCONCLUSIVE: a school could not be measured."
    exit 2
fi
if [ "$FAIL" -ne 0 ]; then
    echo "FAIL: a specialist mage did not know both spells of his school."
    exit 1
fi
echo "PASS: all $NCASES specialist schools knew both of their specialty spells."
exit 0
