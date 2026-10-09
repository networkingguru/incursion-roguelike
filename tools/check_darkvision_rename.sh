#!/bin/bash
# gate: cheap
# Regression check for inc-moh9 phase 3: player-facing "infravision" (and the
# "Infravison" typo) must be renamed to "darkvision" everywhere a player reads it
# in lib/, while every code identifier CA_INFRAVISION is left untouched.
#
# Strategy: scan every lib/*.irh and lib/*.irc line that matches
# infravision/infra-vision/infravison. Any such line that does NOT contain
# CA_INFRAVISION (or an upstream design comment we deliberately kept) is a
# player-facing leak and fails the check. It also proves the two renamed
# resources exist and that no other resource already owned the name.
#
# Red while a player-facing "infravision" remains; green once the rename holds.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

fail=0

# 1. No player-facing infravision/infravison left in lib/.
leaks="$(grep -rn -iE 'infra-?vision|infravison' lib/*.irh lib/*.irc 2>/dev/null |
         grep -v 'CA_INFRAVISION')"
if [ -n "$leaks" ]; then
    echo "FAIL: player-facing infravision/infravison remains in lib/:"
    printf "%s\n" "$leaks"
    fail=1
fi

# 2. The renamed resources exist, in place.
if ! grep -q 'Spell "Darkvision" : EA_INFLICT' lib/wspells.irh; then
    echo "FAIL: spell \"Darkvision\" not found in lib/wspells.irh."
    fail=1
fi
if ! grep -q 'Effect "Darkvision;ring"' lib/m_items.irh; then
    echo "FAIL: item \"Darkvision;ring\" not found in lib/m_items.irh."
    fail=1
fi

# 3. No dangling $\"Infravision\" / $\"infravision\" reference remains.
dangling="$(grep -rn -iE '\$"infra' lib/*.irh lib/*.irc 2>/dev/null)"
if [ -n "$dangling" ]; then
    echo "FAIL: a resource reference to \$\"Infravision\" remains:"
    printf "%s\n" "$dangling"
    fail=1
fi

if [ "$fail" -ne 0 ]; then
    exit 1
fi

ca="$(grep -rc 'CA_INFRAVISION' lib/*.irh lib/*.irc 2>/dev/null | awk -F: '{s+=$2} END{print s}')"
echo "PASS: inc-moh9 phase 3 -- no player-facing infravision in lib/; Darkvision resources present; $ca CA_INFRAVISION identifiers preserved."
