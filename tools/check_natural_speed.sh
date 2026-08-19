#!/bin/bash
# Verify that the unarmed/natural attack speed floor still matches the data.
#
# OPT_NATURAL_SPEED floors A_SPD_BRAWL at NATURAL_SPD_FLOOR so that a creature
# which can hold a weapon never attacks more slowly with an empty limb than it
# would with a weapon in that limb. The floor is written as a constant in
# inc/Defines.h rather than derived at load time by scanning every T_WEAPON
# template. That corner cut holds only while the constant equals the fastest
# weapon in lib/weapons.irh. If somebody adds a faster weapon, the rule silently
# stops being true and nothing else in the build complains.
#
# This script is that complaint. It reads the highest Spd percentage in the
# weapon data, converts it the way lang/Grammar.acc:556 does, and compares.
set -u

cd "$(dirname "$0")/.."

data="lib/weapons.irh"
header="inc/Defines.h"

for f in "$data" "$header"; do
    if [ ! -r "$f" ]; then
        echo "FAIL: cannot read $f"
        exit 1
    fi
done

# Every weapon speed in the data, as a bare percentage.
pcts=$(grep -o 'Spd: *[0-9][0-9]*%' "$data" | grep -o '[0-9][0-9]*')
if [ -z "$pcts" ]; then
    echo "FAIL: found no 'Spd: N%' entries in $data"
    exit 1
fi

max_pct=$(echo "$pcts" | sort -n | tail -1)
count=$(echo "$pcts" | wc -l | tr -d ' ')

# lang/Grammar.acc:556 stores a positive percentage as (n - 100) / 5.
expected=$(( (max_pct - 100) / 5 ))

actual=$(grep -o '^#define NATURAL_SPD_FLOOR  *[0-9-][0-9]*' "$header" \
         | grep -o '[0-9-][0-9]*$')
if [ -z "$actual" ]; then
    echo "FAIL: NATURAL_SPD_FLOOR not found in $header"
    exit 1
fi

echo "weapons scanned:      $count"
echo "fastest weapon:       ${max_pct}%"
echo "floor that implies:   $expected"
echo "NATURAL_SPD_FLOOR:    $actual"

if [ "$actual" -ne "$expected" ]; then
    echo
    echo "FAIL: the floor no longer matches the data."
    echo "  The fastest weapon in $data is now ${max_pct}%, which the grammar"
    echo "  stores as $expected. Set NATURAL_SPD_FLOOR in $header to $expected,"
    echo "  and update the 175% figure in the OPT_NATURAL_SPEED help text in"
    echo "  src/Tables.cpp to ${max_pct}%."
    exit 1
fi

echo
echo "PASS: floor matches the fastest weapon in the data."
