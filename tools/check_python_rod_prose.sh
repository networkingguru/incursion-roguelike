#!/bin/bash
# Regression check for PA-08-F83 / inc-tek.8.8: the "Rod of the Python" (entity
# "the Python") must carry a description, and that description must name all
# three of its coded effects -- a per-plus saving-throw bonus against poison
# (SAVE_BONUS SN_POISON), a per-plus Constitution bonus (ADJUST A_CON), and a
# three-times-daily transformation into a boa constrictor (EF_3PERDAY, boa
# constrictor summon). The entity declared no Desc in any of its three blocks.
# Red on HEAD (no Desc at all), green once a Desc names poison, Constitution and
# the boa/serpent transformation.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SOURCE="${SOURCE:-lib/m_items.irh}"
# Anchor on the Rod of the Python block, then extract the Desc STRING itself
# (from 'Desc: "' to its first closing '";'), so the upstream: comment above the
# Desc -- which also names these effects -- is not read as the Desc naming them.
block="$(sed -n '/AI_ROD Effect "the Python"/,/AI_ROD Effect "Rod of Lordly Might"/p' "$SOURCE")"
desc="$(printf "%s\n" "$block" | sed -n '/Desc: "/,/";/p')"

if [ -z "$desc" ]; then
    echo "FAIL: the Rod of the Python declares no Desc; the item has no description text."
    exit 1
fi

missing=""
printf "%s\n" "$desc" | grep -q "poison"       || missing="$missing poison-save"
printf "%s\n" "$desc" | grep -q "Constitution" || missing="$missing Constitution"
printf "%s\n" "$desc" | grep -Eq "boa|serpent" || missing="$missing boa/serpent-transformation"

if [ -n "$missing" ]; then
    echo "FAIL: the Rod of the Python Desc does not name:$missing."
    exit 1
fi

echo "PASS: PA-08-F83 / inc-tek.8.8 the Rod of the Python Desc names its poison-save, Constitution and boa-constrictor transformation effects."
exit 0
