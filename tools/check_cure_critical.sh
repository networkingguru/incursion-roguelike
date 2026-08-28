#!/bin/bash
# Regression check for the Cure Critical Wounds heal amount, inc-tek.8.7.
#
# THE DEFECT. lib/pspells.irh declared the Cure Critical Wounds EA_HEALING
# effect with `pval: 3d8 + LEVEL_MAX20`, while the effect's own Desc promises
# "Heals you of 4d8 + your level ... to a maximum of 4d8+20". The spell paid one
# die less than it advertised. The sibling Inflict Critical Wounds, its damage
# twin, already rolls `4d8 + LEVEL_MAX20`, and Cure Serious Wounds one tier down
# is a DIFFERENT spell that rolls `3d8 + LEVEL_MAX15` and must stay 3d8. So this
# check reads the ONE effect line and demands 4d8 there, without touching the
# Cure Serious line.
#
# THE ORACLE is the pval token on the Cure Critical Wounds EA_HEALING effect
# line. That line is identified without ambiguity by three tokens together:
# `xval: HEAL_HP` (a healing effect), `LEVEL_MAX20` (the level 4 cap, which Cure
# Serious does not carry -- it uses LEVEL_MAX15) and `yval: 30`. The two spell
# list declarations of the same name near the head of their tiers carry no pval
# and never match. Inflict Critical carries `4d8 + LEVEL_MAX20` but with
# `xval: AD_NECR` and `cval: BROWN`, so it never matches either.
#
# WHY THE ORACLE CANNOT BE FAKED. It reads the tracked source directly, so it
# proves the shipped data and not a transient screen. It fails red if the token
# is 3d8, and only passes on 4d8.
#
# Exit 0 pass, 1 the defect is present (still 3d8 or some other value), 2 the
# effect line could not be found -- the declaration moved or was renamed.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FILE="$ROOT/lib/pspells.irh"

[ -f "$FILE" ] || { echo "FAIL(2): $FILE is missing; nothing was examined"; exit 2; }

# The Cure Critical Wounds healing effect line, and only it.
LINE="$(grep -nE 'xval:[[:space:]]*HEAL_HP;[[:space:]]*pval:.*LEVEL_MAX20;[[:space:]]*yval:[[:space:]]*30' "$FILE")"

COUNT="$(printf '%s\n' "$LINE" | grep -c . )"
if [ "$COUNT" -ne 1 ]; then
    echo "FAIL(2): expected exactly one Cure Critical Wounds HEAL_HP/LEVEL_MAX20/yval:30 line, found $COUNT."
    echo "         The declaration moved or was renamed. Re-point this check before trusting it."
    printf '%s\n' "$LINE" | sed 's/^/    | /'
    exit 2
fi

# The dice token immediately before ` + LEVEL_MAX20`.
DICE="$(printf '%s\n' "$LINE" | grep -oE '[0-9]+d[0-9]+[[:space:]]*\+[[:space:]]*LEVEL_MAX20' | grep -oE '^[0-9]+d[0-9]+')"

if [ "$DICE" = "4d8" ]; then
    echo "PASS: Cure Critical Wounds heals 4d8 + LEVEL_MAX20, as its description promises."
    exit 0
fi

echo "FAIL(1): Cure Critical Wounds heals ${DICE:-<unreadable>} + LEVEL_MAX20, not the 4d8 its Desc promises."
echo "         Fix the pval token in lib/pspells.irh (inc-tek.8.7)."
printf '%s\n' "$LINE" | sed 's/^/    | /'
exit 1
