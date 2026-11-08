#!/bin/bash
# witness for S01 (both sides add a distinct Character field): in the landed tree, every case field the tree
# declares decodes to its declared value when a real fixture save loads through the real reader, and the tree
# declares at least one. $1 = the worktree, $2 = the oracle's output directory (holds values/<fixture>.txt).
# fact: fixture -- tools/fixtures/chars/elf-mage-spotted-seed1.sav, frozen bytes; the declared defaults 17 and 29 are the case's own
set -uo pipefail
W="$1"; V="$2/values/elf-mage-spotted-seed1.txt"
[ -f "$V" ] || { echo "no value file $V"; exit 2; }
seen=0; bad=0
check() { # <FIELD name> <expected>
    if grep -q "FIELD_U32(\"$1\"" "$W/inc/Creature.h"; then
        seen=$((seen + 1))
        if grep -qE "/Character $1 [a-z0-9]+ [A-Za-z0-9_]+=$2\$" "$V"; then echo "$1 decodes to $2"
        else echo "FAIL: $1 does not decode to $2 in $V: $(grep -m1 " $1 " "$V")"; bad=1; fi
    fi
}
check Ac8MasterAid 17
check Ac8EpicAnger 29
[ $seen -gt 0 ] || { echo "FAIL: the tree declares none of the case fields"; exit 1; }
[ $bad -eq 0 ] && echo "witness: $seen case field(s) decode to their declared values"
exit $bad
