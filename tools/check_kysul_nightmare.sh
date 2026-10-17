#!/bin/bash
# gate: live
# Does Kysul's 6th-rank grant still reach the character as the spell Nightmare?
# (bd inc-pu6v.282.)
#
# THE DEFECT, the ORACLE and the FALSIFIER are set out in the header of
# tools/keys/kysul-nightmare.keys, which this check photographs; this file only
# reads the dump that run leaves. In short:
#
#   defect:    Kysul's 6th-rank Grants: line read
#              Ability[CA_INNATE_SPELL,$"Nightmare"], but $"name" is resolved
#              by Module::FindResource (src/Res.cpp), which searches monsters
#              before spells, so it matched the monster and granted no spell.
#   oracle:    the "Innate Spells:" block in the sheet's right-hand column
#              (src/Sheet.cpp). "Distance Distortion" is the 4th-rank grant and
#              proves the run climbed past that rung; "Nightmare" is the grant
#              under test.
#   falsifier: put $"Nightmare" back on the grant line in lib/religion.irh, and
#              rebuild; the block keeps Distance Distortion but loses Nightmare,
#              and this check exits 1.
#
# Usage: tools/check_kysul_nightmare.sh    (0 pass, 1 fail, 2 could not measure)
. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat

# A run directory of this invocation's own, named for the clock and the PID, so
# a red run and a green run never overwrite each other. headless.sh names the
# same shape when INCURSION_RUN_DIR is unset; this pins it under logs/runs/.
INCURSION_RUN_DIR="$PWD/logs/runs/$(date +%Y%m%d-%H%M%S)-$$-kysul-nightmare"
export INCURSION_RUN_DIR

check_run tools/keys/kysul-nightmare.keys 1

SCREENS="$CHECK_RUN/logs/screens"

# The Innate Spells block. Each dump is a fixed-width two-column screen and the
# right-hand column starts at about column 41 (CreateCharSheet, src/Sheet.cpp,
# builds the sheet as two 40-column flows), but the sheet indents headings and
# entries differently, so the leading blanks are trimmed. Take the right column
# from the "Innate Spells:" heading down to the next heading, which is a
# right-column line ending in ':' -- not into the abilities that follow, nor
# into the next panel.
innate_spells() { # <screens dir> -> the block's lines on stdout
    awk '
      FNR == 1 { inb = 0 }
      { r = substr($0, 41); sub(/[ \t]+$/, "", r); sub(/^[ \t]+/, "", r) }
      index(r, "Innate Spells:") == 1 { inb = 1; next }
      inb && r ~ /:$/ { inb = 0 }
      inb && r != "" { print r }
    ' "$1"/*.txt
}

cant_tell() { # <line>...
    echo "INCONCLUSIVE: $1"; shift
    local l; for l in "$@"; do echo "      $l"; done
    exit 2
}

grep -qF "Innate Spells:" "$SCREENS"/*.txt || cant_tell \
    "no dump shows an 'Innate Spells:' heading, so the sheet never reached" \
    "the block this check reads. The screens are in $SCREENS."

BLOCK="$(innate_spells "$SCREENS")"

printf '%s\n' "$BLOCK" | grep -qF "Distance Distortion" || cant_tell \
    "the Innate Spells block has no 'Distance Distortion', so the run did not" \
    "climb past Kysul's 4th-rank grant and the block cannot be judged." \
    "The screens are in $SCREENS."

if printf '%s\n' "$BLOCK" | grep -qF "Nightmare"; then
    echo "GREEN: the Innate Spells block lists Nightmare, so Kysul's 6th-rank" \
        "grant reached the character as the spell. ($CHECK_RUN)"
    exit 0
fi

echo "RED: the Innate Spells block has Distance Distortion but not Nightmare," \
    "so Kysul's 6th-rank grant granted no spell. ($CHECK_RUN)"
exit 1
