# gate: live
# inc-ympc (replaces inc-4999 phase 5's "(arc)" name prefix): does the Spell
# Manager show each held source in its own Src column, and do the other spell
# lists show the bare name?
#
# WHAT IS BEING GUARDED. A spell is HELD from one or more sources
# (SP_ARCANE/SP_DIVINE/SP_PRIMAL/SP_BARDIC). The Spell Manager ('m',
# src/Managers.cpp) gives one row per (spell, source). The owner's ruling: a
# three-letter Src column between Spell and Mana holds arc/div/pri/brd (or inn
# for an innate entry), and NO spell list prefixes the name with "(arc)".
#
# THE CHARACTER is tools/fixtures/chars/human-priest-mage-dual-seed4-gate.sav:
# Kethad, Priest 1 / Mage 1, holding Protection from Evil from BOTH sources
# (arcane=1 divine=1), saved in wizard mode at depth 2. The innate row is
# checked by tools/check_spell_src_column.sh (a fixture with SP_INNATE spells).
#
# THE ORACLES:
#   A (cast menu). The header reads "Spell   Src Mana"; Protection from Evil has
#     two rows, "Protection from Evil   arc" and "...   div"; no "(arc)" prefix
#     is drawn; no dumped line is wider than 80 columns.
#   B (Learn Spells). Unchanged: the Source column reads Arcane / Divine.
#   C (character sheet). logs/charprobe.txt (INCURSION_CHAR_PROBE=1, written by
#     Game::SaveGame) lists Protection from Evil twice, each with its own
#     rating, and no line leads with "(arc)" or "(div)".
#
# PROVED RED with --prove-red (docs/VERIFICATION.md step 2). The mutation makes
# SpellSrcColumnName return "" for the arcane case, so the arcane row loses its
# Src text; the "Protection from Evil   arc" assertion then fails.
#
# Usage: tools/check_spell_tags.sh [--prove-red]
#   0 every expectation holds   1 one fails   2 could not measure
. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat
FIXTURE=tools/fixtures/chars/human-priest-mage-dual-seed4-gate.sav
KEYS=tools/keys/spell-tags.keys
SEED=4

check_mutation src/Managers.cpp \
'        case SP_ARCANE: return "arc";' \
'        case SP_ARCANE: return "";'

[ -f "$FIXTURE" ] || _check_die 2 "no $FIXTURE to load."
[ -f "$KEYS" ]    || _check_die 2 "no $KEYS to run."

export INCURSION_LOAD="$FIXTURE"
export INCURSION_CHAR_PROBE=1
check_run "$KEYS" "$SEED"

# A. the cast menu: the Src column, the bare name, nothing wider than the box.
check_screens '*-cast-menu'
check_expect "Spell                  Src Mana" "A: the header puts Src between Spell and Mana"
check_expect "Protection from Evil   arc" "A: the arcane row has Src arc beside the bare name"
check_expect "Protection from Evil   div" "A: the divine row has Src div beside the bare name"
check_reject "(arc)" "A: the cast menu draws no (arc) name prefix"
check_reject "(div)" "A: the cast menu draws no (div) name prefix"
for f in "${CHECK_SCREENS[@]}"; do
    wide="$(awk 'length($0) > 80 { n++ } END { print n + 0 }' "$f")"
    if [ "$wide" -ne 0 ]; then
        echo "  FAIL  $wide line(s) wider than 80 columns in $f"
        CHECK_FAIL=1
    else
        CHECK_EXPECTS=$((CHECK_EXPECTS + 1))
        echo "  ok    no line wider than 80 columns in $(basename "$f")"
    fi
done

# B. the Learn Spells table names each held version's source in its Source
# column (the table replaced the old "(arc)"/"(div)"-prefixed checklist rows).
check_screens '*-learn-spells'
check_expect "Protection from Evil   Arcane" "B: the arcane table row names its source"
check_expect "Protection from Evil   Divine" "B: the divine table row names its source"

# C. the character sheet's Known Spells list has one line per held version. charprobe.txt is that whole sheet.
PROBE="$CHECK_RUN/logs/charprobe.txt"
[ -f "$PROBE" ] || _check_die 2 \
    "no logs/charprobe.txt -- INCURSION_CHAR_PROBE=1 should have made" \
    "Game::SaveGame write one. See $CHECK_RUN."
cp "$PROBE" "$CHECK_RUN/logs/screens/charprobe-sheet.txt"
check_screens 'charprobe-sheet'
n="$(grep -c 'Protection from Evil' "$PROBE")"
if [ "$n" -eq 2 ]; then
    CHECK_EXPECTS=$((CHECK_EXPECTS + 1))
    echo "  ok    C: the sheet lists Protection from Evil once per held source"
else
    echo "  FAIL  C: the sheet has $n Protection from Evil lines, not 2"
    CHECK_FAIL=1
fi
check_reject "(arc)" "C: the sheet draws no (arc) name prefix"
check_reject "(div)" "C: the sheet draws no (div) name prefix"

check_done "the Spell Manager shows each source in its Src column and no list prefixes the name"
