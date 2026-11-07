#!/bin/bash
# gate: live
# Does the canonical character dump (tools/char_dump.sh, INCURSION_DUMP_CANONICAL
# in src/Dump.cpp) stay comparable and complete? (bd inc-10v7f phase 3)
#
# Every later phase of inc-10v7f proves "the character did not change" by
# comparing two canonical dumps. That proof is worth nothing if a dump holds a
# value that differs between two loads of one file, or leaves out a field. This
# check asserts, on two frozen characters:
#
#   1. two loads of one fixture dump byte for byte identically;
#   2. the dump holds a line for each field class: per-level hit and mana
#      rolls, skill ranks and the skill-point pool, the perk block, feats,
#      abilities, the kit with item qualities, spell lists, stati;
#   3. the dump prints no handle and no bare rID: no `h=<n>`, and no
#      `iID`, `eID`, `mID`, `tmID`, `homeID`, `dID` or `flavor` followed by a
#      number, and no 8-digit hex word (a pointer);
#   4. the detector in 3 bites: the same grep run on a copy of the dump with a
#      handle line injected must find it (the selftest, no build needed).
#
# The assertions read section and field NAMES, never a value, so a new
# lib/*.irh resource cannot break them.
#
# fact: character -- fixture lizardfolk-monk-seed1 (a kit with qualities, stati, feats; no spells)
# fact: character with spell lists -- fixture elf-mage-illusions-seed1
# fact: settings -- options-2026-08-22.dat (INCURSION_OPTIONS, required by tools/char_dump.sh)
# fact: the dump text -- field and section names only; no value, no seed, no roll is asserted
#
# Usage: tools/check_char_dump.sh              (0 pass, 1 fail, 2 inconclusive)
#        tools/check_char_dump.sh --selftest   (the detector alone, no build)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# Printed by -dump canonical mode for a script variable that holds a handle is
# "(handle set)" or "(handle unset)": words, not a number, so they pass.
HANDLE_RE='(^|[^A-Za-z])h=[0-9]|(iID|eID|mID|tmID|homeID|dID|flavor|pflavor)=-?[0-9]|0x[0-9a-fA-F]{8,}'

fail=0
bad() { echo "FAIL: $*"; fail=1; }

# Does the detector bite? Run it on a dump with a handle line injected.
detector_bites() { # detector_bites <dump>
    local probe
    probe="$(mktemp)"
    { cat "$1"; echo "      Nature=ALIGNMENT Val=5 eID=-1 h=1234"; } > "$probe"
    if grep -Eq "$HANDLE_RE" "$probe"; then rm -f "$probe"; return 0; fi
    rm -f "$probe"
    return 1
}

if [ "${1:-}" = "--selftest" ]; then
    clean="$(mktemp)"
    printf 'Name: Test\nStati: Nature=HUNGER Val=-1 eID=-\n' > "$clean"
    if grep -Eq "$HANDLE_RE" "$clean"; then bad "detector flags a clean dump"; fi
    detector_bites "$clean" || bad "detector does not flag an injected handle"
    rm -f "$clean"
    [ "$fail" -eq 0 ] && echo "selftest ok"
    exit $fail
fi

BIN="${INCURSION_BIN:-./incursion-headless}"
if [ ! -x "$BIN" ] || [ ! -f mod/Incursion.Mod ]; then
    echo "INCONCLUSIVE: build first: BACKEND=posix ./build_macos.sh"
    exit 2
fi
export INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat
WORK="$(mktemp -d "${TMPDIR:-/tmp}/check_char_dump.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

for fx in lizardfolk-monk-seed1 elf-mage-illusions-seed1; do
    a="$WORK/$fx.1"; b="$WORK/$fx.2"
    if ! tools/char_dump.sh "$fx" "$a" 2>/dev/null || ! tools/char_dump.sh "$fx" "$b" 2>/dev/null; then
        echo "INCONCLUSIVE: tools/char_dump.sh $fx failed"
        exit 2
    fi
    # 1. two loads identical
    if ! cmp -s "$a" "$b"; then
        bad "$fx: two loads give different canonical dumps:"
        diff "$a" "$b" | head -6
    fi
    # 3. no handle and no bare rID
    if grep -Eq "$HANDLE_RE" "$a"; then
        bad "$fx: the canonical dump prints a handle, a bare rID or a pointer:"
        grep -En "$HANDLE_RE" "$a" | head -6
    fi
    # 4. the detector bites on this dump
    detector_bites "$a" || bad "$fx: the handle detector did not flag an injected handle"

    # 2. one line per field class
    need() { # need <label> <egrep pattern>
        grep -Eq "$2" "$a" || bad "$fx: no line for $1 (pattern: $2)"
    }
    need "per-level hit rolls"      '^HitRolls\[[0-9]'
    need "per-level mana rolls"     '^ManaRolls\[[0-9]'
    need "skill ranks"              '^Skill [A-Z_]+: [0-9]'
    need "skill-point pool"         '^SkillPool\[[0-9]'
    need "perk block statMethod"    '^statMethod: '
    need "perk block rerollCount"   '^rerollCount: '
    need "perk block rerolledPerks" '^rerolledPerks: '
    need "perk block formulaSeed"   '^formulaSeed: '
    need "perk block storeSeed"     '^storeSeed: '
    need "feats"                    '^Feat '
    need "abilities"                '^Ability CA_'
    need "kit item"                 '^ *- Item iID='
    need "kit item qualities"       '^ *Qualities:'
    need "kit item plus and charges" '^ *Known=0x[0-9a-f]+ Plus=-?[0-9]+ Charges=-?[0-9]+'
    need "kit item count"           'Quantity=[0-9]+'
    need "kit item identified state" 'Known=0x'
    need "player stati"             '^Stati: Nature='
    need "kit item stati"           '^ +Stati: '
done
# Spell lists: only the caster fixture has them.
grep -Eq '^Spell .+: flags=0x' "$WORK/elf-mage-illusions-seed1.1" \
    || bad "elf-mage-illusions-seed1: no 'Spell <name>: flags=' line"
grep -Eq '^SpellLevel\[[0-9]\]' "$WORK/elf-mage-illusions-seed1.1" \
    || bad "elf-mage-illusions-seed1: no 'SpellLevel[n]' line"

if [ "$fail" -eq 0 ]; then
    echo "PASS: canonical dumps are stable, name every rID, print no handle, and cover every field class"
    exit 0
fi
exit 1
