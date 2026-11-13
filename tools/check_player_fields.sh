#!/usr/bin/env bash
# gate: cheap --selftest
#
# Is every field a saved Player or Character carries sorted as stated, derived
# or excluded?
#
# WHAT IS BEING PROVED. Spec amendment A13, C7 (bead inc-10v7f, phase 7b): a
# .char file must be able to say everything about a new character that the
# creation screens decide. The way to know a creation fact has not been left
# out is to sort every saved field. This lists each FIELD_* line, and each
# V1Str line, of the archive blocks of Character (inc/Creature.h
# `ARCHIVE_CLASS(Character,...)`) and Player (`ARCHIVE_CLASS(Player,...)`), and
# gives each one a class and a one-line reason:
#   stated    a decision key of the .char file states it, directly or through
#             the picks and rolls that fill it;
#   derived   the engine computes it from stated facts, or sets it the same way
#             on every build, so no line states it;
#   excluded  not a creation fact: play state, interface state, a clock, a
#             counter or map memory, zero or reset when the character is made.
# A saved field the list does not name fails the check, so a new field cannot
# arrive unsorted. A listed field the code no longer has fails it too, so the
# list cannot go stale. The list is inside this script, below.
#
# BASE CLASSES. The Creature and Thing archive blocks also save creation facts
# (the name, the gender, the hit point and mana totals). They are not listed
# here, by the brief of this phase; the report of phase 7b names them.
#
# fact: the text of inc/Creature.h -- read from the working tree by python; no game run, no seed, no map, no character
# fact: the saved field names -- read from the two archive blocks at run time, so a new FIELD_ line is covered the moment it is added
# fact: the class and reason of each field -- the table in this script, reviewed with the code
#
# Usage: tools/check_player_fields.sh [--selftest]
#        --selftest copies inc/Creature.h, adds a FIELD_ line to the Player block
#        and removes one from the Character block in turn, and proves this
#        script goes red on each copy (and green on the untouched copy).
# Exit: 0 every saved field is listed and every listed field exists; 1 not; 2 could not measure.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

HDR="${PLAYER_FIELDS_HEADER:-inc/Creature.h}"

# block | field expression | class | reason. A FIELD_SKIP line is written skip:<name>.
TABLE='
Character|Inv|derived|the carried and worn items; the kit_item, beginkit_item and perk_item lines state the items and the build places them
Character|defMelee|derived|default weapon handle, set when the item is wielded
Character|defRanged|derived|default weapon handle, set when the item is wielded
Character|defAmmo|derived|default ammunition handle, set when the item is readied
Character|defOffhand|derived|default weapon handle, set when the item is wielded
Character|defReach|derived|default weapon handle, set when the item is wielded
Character|defReachOff|derived|default weapon handle, set when the item is wielded
Character|defShort|derived|default weapon handle, set when the item is wielded
Character|defShortOff|derived|default weapon handle, set when the item is wielded
Character|BAttr|stated|the seven attribute lines (attr_str to attr_luc)
Character|KAttr|derived|worked out by CalcValues from the base attributes, race, class and feats
Character|SkillRanks|stated|the skills lines, one rank count per skill (skill_ranks)
Character|Feats|stated|the feat picks (feat and its weapon, skill and school sub-picks); grants from race and class are derived from them
Character|Abilities|stated|the ability picks (domain, fav_enemy, specialist_school, tattoo); grants from race, class and feats follow from the stated picks
Character|SpentSP|derived|skill points spent, summed from the stated ranks
Character|BonusSP|derived|bonus skill points, worked out from race, class and feats
Character|TotalSP|derived|skill point pools, worked out from class, level and intelligence
Character|TurnTypes|excluded|no game code writes it outside the save and the dump (grep of src/)
Character|TurnLevels|excluded|no game code writes it outside the save and the dump (grep of src/)
Character|FavTypes|excluded|no game code writes it outside the save and the dump (grep of src/)
Character|FavLevels|excluded|no game code writes it outside the save and the dump (grep of src/)
Character|IntStudy|stated|the study_area picks (Intensive Study)
Character|FocusWCount|excluded|no game code writes it outside the save and the dump (grep of src/)
Character|FocusSCount|excluded|no game code writes it outside the save and the dump (grep of src/)
Character|ExoticCount|excluded|no game code writes it outside the save and the dump (grep of src/)
Character|aStoryPluses|excluded|story bonus counter earned in play; zero when the character is made
Character|tStoryPluses|excluded|story bonus counter earned in play; zero when the character is made
Character|RageCount|excluded|no game code writes it outside the save and the dump (grep of src/)
Character|xpTicks|excluded|experience tick counter of play; zero when the character is made
Character|Personality|stated|the personality pick
Character|polyTicks|excluded|polymorph timer; zero when the character is made
Character|alignGE|stated|the alignment pick (good or evil axis)
Character|alignLC|stated|the alignment pick (lawful or chaotic axis)
Character|LastRest|excluded|a clock of play
Character|fracFatigue|excluded|fatigue remainder of play
Character|fallen|excluded|fallen-paladin flag of play; false when the character is made
Character|skip:isFallenPaladin|excluded|a bool staged through the fallen field, never stored itself
Character|Level|stated|the class pick and the level lines
Character|hpRollsRow|derived|the row count of hpRolls, worked out from the class levels
Character|hpRolls|stated|the hp_roll lines, one per class level
Character|manaRollsRow|derived|the row count of manaRolls, worked out from the class levels
Character|manaRolls|stated|the mana_roll lines, one per class level
Character|SaveBonus|derived|worked out from race, class and feats
Character|GainAttrRow|derived|the row count of GainAttr, worked out from the level_attr picks
Character|GainAttr|stated|the level_attr picks (the attribute gained at levels 4, 8 and so on)
Character|NotifiedLevel|excluded|interface record of the last level announced
Character|ClassID[i]|stated|the class pick and the addclass lines
Character|RaceID|stated|the race pick
Character|GodID|stated|the god pick
Character|Mount|excluded|a mount of play; none when the character is made
Character|XP|stated|the xp key
Character|XP_Drained|excluded|energy-drain state of play; zero when the character is made
Character|SpellsLearned|derived|count of spells learned per spell level, worked out from the spell_learn picks
Character|SpellSlots|derived|spell slots per level, worked out from class, level and attributes
Character|BonusSlots|derived|bonus spell slots per level, worked out from attributes
Character|RecentSpells|excluded|interface list of recently used spells
Character|RecentSkills|excluded|interface list of recently used skills
Character|RecentItems|excluded|interface list of recently used items
Character|Spells|stated|the spell_learn picks; spells a class or race grants follow from the stated class and race
Character|Tattoos[i]|stated|the tattoo picks
Character|resChance|excluded|resurrection chance of play; set when the character dies
Character|FavourLev|derived|favor level, set when the god pick joins the god
Character|TempFavour|excluded|favor of play; zero when the character is made
Character|Anger|stated|the Transgress roll an Elf of another god makes when made (script_roll); zero for every other character
Character|SacValsRow|excluded|row count of the sacrifice tally of play; zero when the character is made
Character|SacVals|excluded|sacrifice tally of play; zero when the character is made
Character|FavPenalty|excluded|favor penalty of play; zero when the character is made
Character|PrayerTimeout|excluded|prayer clock of play
Character|AngerThisTurn|excluded|god anger of the current turn
Character|lastPulse|excluded|clock of the last god pulse
Character|godFlags|derived|set when the god pick joins the god
Character|desiredAlign|derived|the alignments the god accepts, set when the god pick joins the god
Character|Proficiencies|derived|weapon proficiencies, worked out from class and feats
Player|MapMemoryMask|excluded|map memory of play
Player|GallerySlot|derived|set to -1 by every File build, so no gallery entry is touched (tools/check_build_gallery.sh)
Player|MapSP|excluded|map memory of play
Player|MaxDepths|excluded|deepest level reached, a progress record of play
Player|MMArray|excluded|metamagic settings the player makes in play; zero when the character is made
Player|Macros[i]|excluded|interface macros
Player|QuickKeys[i].Value|excluded|interface quick keys
Player|QuickKeys[i].Type|excluded|interface quick keys
Player|QuickKeys[i].hItem|excluded|interface quick keys
Player|QuickKeys[i].MM|excluded|interface quick keys
Player|MessageQueue[i]|excluded|messages waiting to be shown
Player|AutoBuffs|excluded|interface list of spells to cast on a key
Player|cAutoBuff|excluded|cursor into the interface list above
Player|GraveText|excluded|epitaph written at death
Player|HungerShown|excluded|interface record of the last hunger message
Player|Journal|derived|text the build writes from the stated perks and the arrival on the first level
Player|RecentVerbs|excluded|interface list of recently used verbs
Player|JournalInfo.bestItem|excluded|play statistic
Player|JournalInfo.bestMonster|excluded|play statistic
Player|JournalInfo.bestMonsterVal|excluded|play statistic
Player|JournalInfo.bestItemVal|excluded|play statistic
Player|JournalInfo.numMonSeen|excluded|play statistic
Player|JournalInfo.numMonOfType|excluded|play statistic
Player|GameTimeInfo.LTI|excluded|clock of play
Player|GameTimeInfo.start_turn|excluded|clock of play
Player|GameTimeInfo.actions|excluded|clock of play
Player|GameTimeInfo.keystrokes|excluded|clock of play
Player|GameTimeInfo.start_second|excluded|wall clock of the session
Player|GameTimeInfo.start_xp|excluded|clock of play
Player|bStati|excluded|interface flag that stati changed
Player|skip:statiChanged|excluded|a bool staged through bStati, never stored itself
Player|formulaSeed|stated|the formula_seed line
Player|storeSeed|stated|the store_seed line
Player|SpellKeys|excluded|interface keys for spells
Player|Options|stated|the options line names the settings file the build copies
Player|skip:MyTerm|excluded|a live pointer, rebuilt on load
Player|bShownFF|excluded|interface flag
Player|skip:shownFF|excluded|a bool staged through bShownFF, never stored itself
Player|bVictory|excluded|victory flag of play; false when the character is made
Player|skip:VictoryFlag|excluded|a bool staged through bVictory, never stored itself
Player|bQuit|excluded|quit flag of play; false when the character is made
Player|skip:QuitFlag|excluded|a bool staged through bQuit, never stored itself
Player|bUpdMap|excluded|redraw flag
Player|skip:UpdateMap|excluded|a bool staged through bUpdMap, never stored itself
Player|bDig|excluded|dig mode of play; false when the character is made
Player|skip:DigMode|excluded|a bool staged through bDig, never stored itself
Player|bWiz|stated|the wizard_mode line
Player|skip:WizardMode|excluded|a bool staged through bWiz, never stored itself
Player|bExplore|stated|the explore_mode line
Player|skip:ExploreMode|excluded|a bool staged through bExplore, never stored itself
Player|bReroll|stated|the rerolled_perks line
Player|skip:rerolledPerks|excluded|a bool staged through bReroll, never stored itself
Player|deathCount|excluded|deaths of play; zero when the character is made (the spec names a deaths key; none exists yet)
Player|rerollCount|stated|the rerolls line
Player|statMethod|stated|the stat_method line
'

measure() {
TABLE="$TABLE" python3 - "$HDR" <<'PY'
import os, re, sys
hdr = sys.argv[1]
table = os.environ["TABLE"]
try:
    text = open(hdr).read()
except OSError as e:
    print("INCONCLUSIVE: %s" % e); sys.exit(2)

def strip_comments(t):
    t = re.sub(r"/\*.*?\*/", lambda m: "\n" * m.group(0).count("\n"), t, flags=re.S)
    return re.sub(r"//[^\n]*", "", t)

def args_of(t, i):
    """The comma-separated arguments of the call whose '(' is at t[i]."""
    depth, cur, out = 0, "", []
    while i < len(t):
        ch = t[i]
        if ch == "(":
            depth += 1
            if depth == 1:
                i += 1; continue
        elif ch == ")":
            depth -= 1
            if depth == 0:
                out.append(cur.strip()); return out
        elif ch == "," and depth == 1:
            out.append(cur.strip()); cur = ""; i += 1; continue
        cur += ch; i += 1
    return None

def block(cls):
    m = re.search(r"ARCHIVE_CLASS\(\s*%s\s*,[^)]*\)(.*?)END_ARCHIVE" % cls, text, re.S)
    if not m:
        print("INCONCLUSIVE: no ARCHIVE_CLASS(%s,...) block in %s" % (cls, hdr)); sys.exit(2)
    return strip_comments(m.group(1))

def fields(body):
    found = []
    for m in re.finditer(r"\b(FIELD_[A-Z0-9_]+|V1Str_AT|V1Str)\s*\(", body):
        a = args_of(body, m.end() - 1)
        if a is None:
            print("INCONCLUSIVE: unbalanced %s call" % m.group(1)); sys.exit(2)
        if m.group(1) == "FIELD_SKIP":
            key = "skip:" + a[0]
        else:
            if len(a) < 2:
                print("INCONCLUSIVE: %s call with one argument" % m.group(1)); sys.exit(2)
            # an element call (FIELD_RID_AT, V1Str_AT) names its member in the third argument: ClassID[i]
            key = (a[2] if m.group(1).endswith("_AT") and len(a) > 2 else a[1]).lstrip("&")
        found.append(re.sub(r"\s+", "", key))
    return found

listed = {}
for ln in table.strip().splitlines():
    parts = ln.split("|")
    if len(parts) != 4 or parts[2] not in ("stated", "derived", "excluded") or not parts[3].strip():
        print("INCONCLUSIVE: bad table row: %s" % ln); sys.exit(2)
    listed.setdefault(parts[0], {})[re.sub(r"\s+", "", parts[1])] = (parts[2], parts[3])

bad = 0
for cls in ("Character", "Player"):
    code = fields(block(cls))
    if not code:
        print("INCONCLUSIVE: no fields found in the %s block" % cls); sys.exit(2)
    for f in code:
        if f not in listed.get(cls, {}):
            print("C7 %s field %s is saved and not listed in this script" % (cls, f)); bad = 1
    for f in listed.get(cls, {}):
        if f not in code:
            print("C7 %s field %s is listed and no longer in the archive block" % (cls, f)); bad = 1
    n = {"stated": 0, "derived": 0, "excluded": 0}
    for f in code:
        if f in listed.get(cls, {}):
            n[listed[cls][f][0]] += 1
    print("# %s: %d saved fields: %d stated, %d derived, %d excluded" % (cls, len(code), n["stated"], n["derived"], n["excluded"]))
sys.exit(bad)
PY
}

if [ "${1:-}" = "--selftest" ]; then
    T="$(mktemp -d "${TMPDIR:-/tmp}/playerfields.XXXXXX")" || exit 2
    trap 'rm -rf "$T"' EXIT
    REAL_HDR="$HDR"
    export PLAYER_FIELDS_HEADER="$T/Creature.h"
    HDR="$PLAYER_FIELDS_HEADER"
    fresh() { cp "$ROOT/$REAL_HDR" "$T/Creature.h"; }
    fresh
    out="$(measure 2>&1)"; rc=$?
    if [ $rc -ne 0 ]; then echo "SELFTEST FAIL: the untouched copy is not green (rc=$rc)"; printf '%s\n' "$out"; exit 1; fi
    echo "selftest: untouched copy green"
    fails=0
    expect_red() {   # <label> <pattern the output must hold>
        out="$(measure 2>&1)"; rc=$?
        if [ $rc -eq 1 ] && grep -q "$2" <<< "$out"; then
            echo "selftest: $1 -> red as expected: $(grep -m1 "$2" <<< "$out")"
        else
            echo "SELFTEST FAIL: $1 did not go red (rc=$rc)"; printf '%s\n' "$out"; fails=1
        fi
    }
    fresh
    python3 - "$T/Creature.h" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
a = "      FIELD_I16(\"statMethod\", statMethod);\n"
assert s.count(a) == 1
open(p, "w").write(s.replace(a, a + "      FIELD_I16(\"mutationNew\", mutationNew);\n"))
PY
    expect_red "a FIELD_ line is added to the Player block" "C7 Player field mutationNew is saved"
    fresh
    python3 - "$T/Creature.h" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
a = "      FIELD_U32(\"Personality\", Personality);\n"
assert s.count(a) == 1
open(p, "w").write(s.replace(a, ""))
PY
    expect_red "a FIELD_ line is removed from the Character block" "C7 Character field Personality is listed"
    [ $fails -eq 0 ] && echo "selftest: PASS" && exit 0
    exit 1
fi

out="$(measure 2>&1)"; rc=$?
if [ $rc -eq 0 ]; then
    printf '%s\n' "$out" | sed -n 's/^# /     /p'
    echo "PASS: every saved Character and Player field is listed as stated, derived or excluded"
    exit 0
fi
printf '%s\n' "$out"
[ $rc -eq 1 ] && echo "FAIL: a saved field is unsorted or a listed field is gone (spec A13, C7)"
exit $rc
