#!/bin/bash
# Regression check for bd inc-tek.8.3 finding PA-03-F11: seven prestige
# classes promise weapon or armour proficiencies in their prose and never
# declare the field that grants them. Two of the seven are playable -- the
# Assassin and the Blackguard -- and both are fixed.
#
# THE ORACLE is the sheet's Proficiencies line. src/Sheet.cpp:861-876 walks
# the character's proficiency bits against WeaponGroupNames[]
# (src/Tables.cpp:1329) and prints the name of every group he holds, so the
# line names the very bits the Proficiencies: field sets.
#
# WHAT THE TWO CHARACTERS PROVE. Both start as elf rogues, so both carry the
# rogue's own proficiencies -- Simple Weapons, Short Blades, Archery, Thrown,
# Daggers, Flexible, Light Armour -- before the prestige class is taken. Every
# name asserted below is one the rogue does NOT bring, so it can only have
# come from the prestige class.
#
# On a module compiled from the pre-fix lib/prestige.irh both characters print
# the bare rogue list and nothing else.
#
# NOT ASSERTED, deliberately: the Assassin's "light weapons". WG_LIGHT has no
# row in WeaponGroupNames at all, so it never prints for anybody -- that is bd
# inc-tek.15, a separate defect found while fixing this one. The grant is
# there; the line simply cannot report it.
#
# Usage: tools/check_prestige_profs.sh      (exits 0 on pass, 1 on fail)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=1

[ -x ./incursion-headless ] || {
    echo "FAIL: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 1
}

fail=0

# $1 key script, $2 dump basename, $3 guard string, $4... expected group names
check_class () {
    local keys="$1" base="$2" guard="$3"; shift 3
    local out run dump line name
    out="$(tools/headless.sh "$keys" "$SEED" 2>&1)"
    run="$(echo "$out" | awk '/^run:/ {print $2}')"
    dump="$run/logs/$base.txt"

    if echo "$out" | grep -q "NO GAMEPLAY"; then
        echo "FAIL: $base -- the run never entered a map, so it measured nothing"
        fail=1; return
    fi
    if [ ! -f "$dump" ]; then
        echo "FAIL: $base -- the character dump was never written to $dump"
        echo "$out" | tail -8
        fail=1; return
    fi
    # Guard first. A key script that stops producing the class must read as
    # rotted, not as a broken game.
    if ! grep -q "$guard" "$dump"; then
        echo "INCONCLUSIVE: $base -- no \"$guard\" on the sheet, so the key"
        echo "              script has rotted. Nothing was measured."
        fail=1; return
    fi
    line="$(grep -m1 "^Proficiencies" "$dump")"
    for name in "$@"; do
        if echo "$line" | grep -q "$name"; then
            echo "  ok: $guard is proficient with $name"
        else
            echo "FAIL: $guard is not proficient with $name"
            echo "      $line"
            fail=1
        fi
    done
}

# The Assassin's prose promises "crossbows and light weapons". WG_CROSSBOWS
# is the group that had to be invented for it: the arbalest sat in
# WG_SIMPLE|WG_ARCHERY and the cranquin and hand crossbow in WG_EXOTIC, and
# no group named the three of them.
check_class tools/keys/prestige-assassin.keys assn "Assassin 2" \
    "Crossbows"

# The Blackguard's prose promises blades, impact weapons, polearms and
# spears, all classes of armour, and -- added to prose and grant together on
# Brian's ruling -- shields.
check_class tools/keys/prestige-blackguard.keys bguard "Blackguard 3" \
    "Long Blades" "Impact" "Polearms" "Spears" "Shields" \
    "Medium Armour" "Heavy Armour"

if [ "$fail" = 0 ]; then
    echo "PASS: the Assassin and the Blackguard each receive the proficiencies"
    echo "      their own prose promises"
    exit 0
fi
exit 1
