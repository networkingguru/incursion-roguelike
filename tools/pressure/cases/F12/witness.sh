#!/bin/bash
# witness for F12 (two distinct migration names, one per side): in the landed tree, a real fixture save (revision 6)
# loads and the writer saves every registered migration name the tree declares: Game.Migrations lists them, so a
# later load runs none of them again. $1 = the worktree, $2 = the oracle's output directory (values/<fixture>.txt).
# fact: fixture -- tools/fixtures/chars/elf-mage-spotted-seed1.sav, frozen bytes; the two names are the case's own
set -uo pipefail
W="$1"; V="$2/values/elf-mage-spotted-seed1.txt"
[ -f "$V" ] || { echo "no value file $V"; exit 2; }
line="$(grep -m1 '/Game Migrations ' "$V")"
[ -n "$line" ] || { echo "FAIL: the loaded save lists no Game.Migrations"; exit 1; }
seen=0; bad=0
for nm in Ac8SpellRepairA Ac8SpellRepairB; do
    if grep -q "\"$nm\"" "$W/src/SaveV1.cpp"; then
        seen=$((seen + 1))
        case "$line" in *"$nm"*) echo "$nm is in the saved list";; *) echo "FAIL: $nm is declared but Game.Migrations lacks it: $line"; bad=1;; esac
    fi
done
[ $seen -gt 0 ] || { echo "FAIL: the tree declares none of the case migrations"; exit 1; }
[ $bad -eq 0 ] && echo "witness: $seen case migration(s) are in Game.Migrations"
exit $bad
