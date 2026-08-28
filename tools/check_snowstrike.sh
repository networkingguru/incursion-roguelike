#!/bin/bash
# Regression check for the Snowstrike caster/allies immunity, inc-tek.8.7 (PA-07-F7).
#
# THE DEFECT. lib/pspells.irh declared the Druid spell Snowstrike (an EA_BLAST
# cold blast) with NO Flags line, so EF_CASTER_IMMUNE and EF_ALLIES_IMMUNE were
# both absent. Magic.cpp exempts the caster only when EF_CASTER_IMMUNE is set and
# a friendly creature only when EF_ALLIES_IMMUNE is set, so the blast froze the
# caster and her allies -- directly against the spell's own Desc, which promises
# "The caster and her allies are immune to the effect". The fix adds both flags.
#
# THE ORACLE is the Flags declaration inside the Snowstrike block. This check
# isolates the block by name -- from the `Druid Spell "Snowstrike"` header to the
# next `Druid Spell` header -- and demands BOTH flags appear inside it. It fails
# red if either flag is missing (the pre-fix state had no Flags line at all).
#
# WHY THE ORACLE CANNOT BE FAKED. It reads the tracked source directly, scoped to
# the Snowstrike block, so a flag on a neighbouring spell (the sibling Ice Dagger
# carries EF_CASTER_IMMUNE) cannot satisfy it.
#
# Exit 0 pass, 1 an immunity flag is missing, 2 the Snowstrike block could not be
# found -- the declaration moved or was renamed.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FILE="$ROOT/lib/pspells.irh"

[ -f "$FILE" ] || { echo "FAIL(2): $FILE is missing; nothing was examined"; exit 2; }

# The Snowstrike block: from its header to the next Druid Spell header.
BLOCK="$(awk '
  /^Druid Spell "Snowstrike"/ { grab=1; print; next }
  grab && /^Druid Spell "/     { exit }
  grab                         { print }
' "$FILE")"

if [ -z "$BLOCK" ]; then
  echo "FAIL(2): the Snowstrike block was not found in $FILE."
  echo "         The declaration moved or was renamed. Re-point this check before trusting it."
  exit 2
fi

# Only the Flags declaration counts -- the flag NAMES also appear in the
# upstream: comment above the declaration, so match [Ff]lags: lines alone.
FLAGS="$(printf '%s\n' "$BLOCK" | grep -E '^[[:space:]]*[Ff]lags:')"

MISSING=""
printf '%s\n' "$FLAGS" | grep -q 'EF_CASTER_IMMUNE' || MISSING="$MISSING EF_CASTER_IMMUNE"
printf '%s\n' "$FLAGS" | grep -q 'EF_ALLIES_IMMUNE'  || MISSING="$MISSING EF_ALLIES_IMMUNE"

if [ -n "$MISSING" ]; then
  echo "FAIL(1): the Snowstrike block is missing immunity flag(s):$MISSING."
  echo "         Its Desc promises the caster and her allies are immune."
  echo "         Add 'Flags: EF_CASTER_IMMUNE, EF_ALLIES_IMMUNE;' to lib/pspells.irh (inc-tek.8.7)."
  exit 1
fi

echo "PASS: Snowstrike carries EF_CASTER_IMMUNE and EF_ALLIES_IMMUNE; the caster and her allies are immune, as its Desc promises."
exit 0
