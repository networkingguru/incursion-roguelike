#!/bin/bash
# gate: live
# inc-4999 phase 1: a kind bit on a spell means "HELD from that source" (the
# player learned that version), never "this spell is on one of your lists".
# CalcSpellAccess must not write Spells[] at all, and a learn from a list must
# set the bit of the row it learned (ls[i].Type) alongside SP_KNOWN.
#
# THE DEFECT this guards. Before inc-4999, Character::CalcSpellAccess() ORed
# the list's kind (SP_ARCANE / SP_DIVINE / SP_PRIMAL / SP_BARDIC) into Spells[]
# for every spell on every list, and cleared all four on every call. Access was
# therefore encoded in Spells[] and readers depended on that. The bead gives
# the bit a different meaning ("held"), so if CalcSpellAccess still wrote it,
# a spell nobody had learned would carry a kind bit with known=0 -- exactly
# the state the probe spotlights.
#
# THE ORACLE is INCURSION_SPELLFLAG_PROBE (src/Create.cpp, Player::
# SpellFlagProbe), whose new second call point fires at the end of
# Player::Create so a freshly generated character can be probed with no save.
# One errors.log line per spell that has SP_KNOWN or any kind bit:
#
#   SPELLFLAG_PROBE <spell> known=<0|1> pending=<0|1> granted=<0|1> \
#       arcane=<0|1> divine=<0|1> primal=<0|1> bardic=<0|1>
#
# Two fresh characters, one keys script each, both at seed 4 with
# tools/gates/Options.Dat:
#
#   Priest  tools/keys/chargen-priest-save.keys (== the frozen fixture
#           tools/fixtures/chars/orc-priest-seed4-gate.keys, byte-identical;
#           the fixture copy's @include resolves next to the file, and only the
#           tools/keys/ copy sits next to chargen-priest.keys, so the check runs
#           the one that loads).
#   Mage    tools/keys/chargen-mage-save.keys (same, for orc-mage-seed4-gate).
#
# ASSERTIONS
#   1. No probe line carries a kind bit with known=0. A list spell nobody has
#      learned showing a source bit is CalcSpellAccess writing Spells[] again.
#   2. Every known priest spell is divine=1 (every known mage spell arcane=1):
#      a learn from a list sets the row's own kind bit. The priest learns only
#      divine rows, the mage only arcane rows.
#   3. Each run logs at least one known spell, so the run reached the state the
#      assertions are about.
#
# PROVED RED with --prove-red (docs/VERIFICATION.md step 2). The mutation drops
# the SpellSyncKnown call from the character-creation REMEM learn in Player::
# LearnSpell, so a marked pick records its kind bit (ls[i].Type) but never gets
# SP_KNOWN. The menu still shows the row marked (its `known` reads the kind
# bit, not SP_KNOWN), so the key scripts complete; but the probe reports a
# spell carrying a source bit with known=0, and assertion 1 fails.
#
# Usage: tools/check_spell_source_bits.sh [--prove-red]  (0 pass, 1 fail, 2 inconclusive)
. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/gates/Options.Dat

# The mutation this check defends: a creation learn must keep SP_KNOWN in step
# with the kind bit it just set. Declared before any run so --prove-red
# intercepts here, before the (build-needing) measurement runs.
check_mutation src/Create.cpp \
'                Spells[sn] |= ls[i].Type | pendBit;
                SpellsLearned[L-1]++;
                SpellSyncKnown(&Spells[sn]);' \
'                Spells[sn] |= ls[i].Type | pendBit;
                SpellsLearned[L-1]++;'

export INCURSION_SPELLFLAG_PROBE=1

# Judged below by hand so the two characters share one implementation.
FAIL=0

# _probe_spells <run dir> -- the per-spell probe lines, stripped of their
# timestamp and any indented call-stack lines.
_probe_spells() {
    grep -E '^[0-9-]+ [0-9:]+  SPELLFLAG_PROBE [A-Za-z].* known=' "$1/logs/errors.log" \
        | sed 's/^[0-9-]* [0-9:]*  //'
}

# _bit <line> <field> -- the 0/1 the named field carries.
_bit() {
    printf '%s' "$1" | grep -oE "$2=[01]" | sed "s/$2=//"
}

# _check_char <label> <keys> <kind field> -- run one fresh caster and judge it.
_check_char() {
    local label="$1" keys="$2" field="$3"
    local dir spells nknown line known arc div pri bar anybit
    check_run "$keys" 4
    dir="$CHECK_RUN"
    spells="$(_probe_spells "$dir")"
    if [ -z "$spells" ]; then
        echo "FAIL: $label logged no per-spell SPELLFLAG_PROBE lines."
        echo "      Is INCURSION_SPELLFLAG_PROBE exported, and does Player::"
        echo "      Create call SpellFlagProbe (src/Create.cpp)?"
        FAIL=1
        return
    fi
    nknown=0
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        known="$(_bit "$line" known)"
        arc="$(_bit "$line" arcane)"
        div="$(_bit "$line" divine)"
        pri="$(_bit "$line" primal)"
        bar="$(_bit "$line" bardic)"
        anybit=0
        for b in "$arc" "$div" "$pri" "$bar"; do
            [ "$b" = "1" ] && anybit=1
        done
        # (1) a kind bit on an unlearned spell means CalcSpellAccess wrote it.
        if [ "$known" = "0" ] && [ "$anybit" = "1" ]; then
            echo "FAIL: $label has a source bit on an unlearned spell:"
            echo "      $line"
            FAIL=1
        fi
        if [ "$known" = "1" ]; then
            nknown=$((nknown + 1))
            # (2) the learned row sets its own kind bit.
            case "$field" in
                arcane) b="$arc" ;;
                divine) b="$div" ;;
                primal) b="$pri" ;;
                bardic) b="$bar" ;;
            esac
            if [ "$b" != "1" ]; then
                echo "FAIL: $label learned a spell without its $field bit:"
                echo "      $line"
                FAIL=1
            fi
        fi
    done <<< "$spells"
    # (3) the run reached the state the assertions are about.
    if [ "$nknown" -eq 0 ]; then
        echo "FAIL: $label logged no known spell, so nothing was proven."
        FAIL=1
    fi
    echo "  $label: $nknown known spell(s) from $dir"
}

_check_char "Priest" tools/keys/chargen-priest-save.keys divine
_check_char "Mage"   tools/keys/chargen-mage-save.keys   arcane

echo
if [ "$FAIL" -ne 0 ]; then
    echo "FAIL: a source bit stands for holding, and one is set on a spell the"
    echo "      character does not hold -- CalcSpellAccess is writing Spells[]"
    echo "      again, or a learn did not name its row's kind (inc-4999)."
    exit 1
fi
echo "PASS: no unlearned spell carries a source bit, and every known divine"
echo "      pick (priest) and every known arcane pick (mage) carries its own."
exit 0
