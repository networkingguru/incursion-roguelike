#!/bin/bash
# Plant a case's content in a real save and record what the new save holds (inc-cjos0 phase 8, D3).
#
#   tools/pressure/plant.sh <binary-dir> <fixture.sav> <spec> <out.sav> <out-values>
#
# <binary-dir> is a built tree. The fixture is loaded through the real reader by -dump with INCURSION_PLANT=<spec>:
# each spec line (symbolic names only, see src/Dump.cpp "INCURSION_PLANT") is applied through the game's own calls
# and the real writer writes a NEW save at <out.sav>. <out-values> is then tools/pressure/field_values.sh of that
# new save, taken with the SAME build: the baseline a later merged build must keep.
# Exit: 0 written; 2 could not measure (a spec line refused, the writer refused, no change from the input).
#
# The spec language of INCURSION_PLANT (moved from src/Dump.cpp, which keeps the invariant):
#     status <STATI_NAME> [val] [mag]     GainPermStati from SS_MISC
#     item <resource name>                Item::Create, into the pack (Container::XInsert)
#     spell <spell resource name>         GainSpell, SP_KNOWN
#     feat <FT_NAME|SK_NAME>              the Feats bit (a skill number is a feat-bit number too); refused when the
#                                         name has no row in FeatInfo (a feat) or SkillInfo (a skill)
#     skill <SK_NAME> <ranks>             SkillRanks[SkillIndex]; refused without a SkillInfo row
#     attr <A_NAME> <value>               Attr[] (and BAttr[] for the seven base scores)
#     known <item resource name> <KN_A|KN_B>   Item.Known of an item planted earlier in this spec, by KN_ names
#     roll <hp|mana> <row 0..2> <col> <val>   hpRolls / manaRolls cell, bounded by MAX_CHAR_LEVEL
#     sacval <god> <col> <val>            SacVals cell, bounded by MAX_GODS and MAX_SAC_CATS + 2
#     xp <value>                          Character.XP
#     resave                              no change: the real writer re-saves, so a staged field the build declares
#                                         is written with its declared value
#     option <OPT_NAME> <value>           skipped: options live in Options.Dat, not in a save
#     var <owner resource> <name> <val>   a script variable of the module's data segment ("(module)" = global)
#     varrid <owner> <name> @ <resource>  the same, holding the rID of a resource by name (a DT_RID variable)
#     monster <monster resource>          a Monster placed on a free cell beside the player
#     template <template> @ <monster>     AddTemplate on a monster planted earlier in this spec
#     target <TargetWhyType name> @ <monster>   the planted monster holds a target of the player with that why
#     feature <feature resource>          a Feature placed on a free cell beside the player
#     terrain <terrain resource>          a map cell (beside the player) of that terrain
#     region <region resource>            a map cell (beside the player) of that region
#     god <god resource> <favour|anger|flags> <val>   Player arrays at theGame->GodNum
#     dungeon <dungeon resource> <depth>  the dungeon enters Game::DungeonID and Player::MaxDepths[slot] = depth
#     ability <CA_NAME> <value>           Abilities[CA_NAME]
#     slot <SL_NAME> @ <item resource>    Inv[SL_NAME] = the item planted earlier in this spec
#     monkills <MA_NAME> <count>          JournalInfo.numMonOfType[MA_NAME]
#     iflags <item resource> <IF_A[|IF_B]>   Item.IFlags of an item planted earlier in this spec
#     status ... src=<SS_NAME>            the status's source (default SS_MISC)
#     class <class resource>              Player::ClassID[0]
#     race <race resource>                Player::RaceID
#     flavor <effect resource> @ <flavour resource>   the flavour of a potion effect (EffMem)
#     field <scope> <member> <value>      refused: this build stages no test field
#   Any other line, an unknown name, or a call the engine refuses: exit 2 naming the line.
#
# fact: the fixture -- a tools/fixtures/chars/*.sav, frozen bytes; no seed, no key script
# fact: the spec -- a case file, symbolic names only; no number names a status, feat, skill or attribute
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
[ $# -eq 5 ] || { echo "usage: $0 <binary-dir> <fixture.sav> <spec> <out.sav> <out-values>" >&2; exit 2; }
BIND="$(cd "$1" && pwd)" || exit 2
SAVE="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"
SPEC="$(cd "$(dirname "$3")" && pwd)/$(basename "$3")"
OUT="$4"; VALS="$5"
[ -x "$BIND/incursion-headless" ] || { echo "no $BIND/incursion-headless" >&2; exit 2; }
[ -f "$SAVE" ] && [ -f "$SPEC" ] || { echo "no fixture or no spec" >&2; exit 2; }
SB="$(mktemp -d "${TMPDIR:-/tmp}/incursion-plant.XXXXXX")"
trap 'rm -rf "$SB"' EXIT
mkdir -p "$SB/save" "$SB/logs"
ln -sfn "$BIND/mod" "$SB/mod"
ln -sfn "$BIND/lib" "$SB/lib"
INCURSIONPATH="$SB/" INCURSION_PLANT="$SPEC" INCURSION_PLANT_OUT="$SB/planted.sav" \
    "$BIND/incursion-headless" -dump "$SAVE" >"$SB/plant.out" 2>"$SB/plant.err"
st=$?
if [ $st -ne 0 ]; then echo "plant exit $st: $(head -c 300 "$SB/plant.err")" >&2; exit 2; fi
[ -s "$SB/planted.sav" ] || { echo "the planter wrote no save" >&2; exit 2; }
cmp -s "$SB/planted.sav" "$SAVE" && { echo "the planted save equals the input" >&2; exit 2; }
mkdir -p "$(dirname "$OUT")" "$(dirname "$VALS")" || exit 2
cp -f "$SB/planted.sav" "$OUT" || exit 2
"$HERE/field_values.sh" "$BIND" "$OUT" "$VALS" || exit 2
