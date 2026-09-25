#!/bin/bash
# Regression check for Flame Blade's augment branch, inc-wbq9 (PA-07-F9).
#
# THE DEFECT. lib/pspells.irh declared the `flame blade;augment` effect with an
# EV_MAGIC_STRIKE handler whose already-flaming branch (the `else if
# (ETarget->HasQuality(WQ_FLAMING) && ETarget->QualityOK(WQ_BURST))` arm) called
# GainTempStati(EXTRA_QUALITY, ..., WQ_FLAMING, WQ_FLAMING, $"flame blade").
# That re-grants Flaming, which the blade already has, while the spell's own
# Desc promises "A weapon that already has the flaming quality is granted the
# Burst quality instead." The branch MUST grant WQ_BURST, so the value the
# already-flaming branch passes to GainTempStati MUST be WQ_BURST.
#
# THE ORACLE is the quality token on the GainTempStati call inside that branch.
# The check extracts the `flame blade;augment` effect block, isolates the
# already-flaming branch (the line guarded by HasQuality(WQ_FLAMING) &&
# QualityOK(WQ_BURST)), and reads the first argument after SS_ENCH. The first
# branch (a plain blade -> Flaming) is deliberately not examined.
#
# WHY THE ORACLE CANNOT BE FAKED. It reads the tracked source directly, so it
# proves the shipped data and not a transient screen. It fails red when the
# already-flaming branch passes WQ_FLAMING, and only passes on WQ_BURST.
#
# Exit 0 pass, 1 the defect is present (the branch still grants WQ_FLAMING or
# some other value), 2 the block or branch could not be found -- the handler
# moved or was renamed.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FILE="$ROOT/lib/pspells.irh"

[ -f "$FILE" ] || { echo "FAIL(2): $FILE is missing; nothing was examined"; exit 2; }

# The `flame blade;augment` effect block: from its Effect line to the line that
# closes the block. The block contains no nested brace-only lines at column 0,
# so the next `^\s*}` at two-space indent after the Effect line ends it.
BLOCK="$(awk '
  /Effect "flame blade;augment"/ { inblk=1 }
  inblk { print }
  inblk && /^  \}/ { exit }
' "$FILE")"

if [ -z "$BLOCK" ]; then
    echo "FAIL(2): the 'flame blade;augment' effect block was not found in $FILE."
    echo "         The effect moved or was renamed. Re-point this check before trusting it."
    exit 2
fi

# The already-flaming branch: the GainTempStati call guarded by the HasQuality /
# QualityOK(WQ_BURST) test. Match the guard line then the two continuation lines.
BRANCH="$(printf '%s\n' "$BLOCK" | awk '
  /HasQuality\(WQ_FLAMING\)[[:space:]]*&&[[:space:]]*ETarget->QualityOK\(WQ_BURST\)/ { grab=1 }
  grab { print; n++ }
  grab && n==3 { exit }
')"

if [ -z "$BRANCH" ]; then
    echo "FAIL(2): the already-flaming (WQ_BURST) branch was not found in the block."
    echo "         The branch moved or was renamed. Re-point this check before trusting it."
    printf '%s\n' "$BLOCK" | sed 's/^/    | /'
    exit 2
fi

# The quality token on the GainTempStati call: the first identifier after
# SS_ENCH. The call may break across lines, so join the branch into one line
# before reading it.
JOINED="$(printf '%s' "$BRANCH" | tr '\n' ' ')"
VAL="$(printf '%s' "$JOINED" | grep -oE 'SS_ENCH,[[:space:]]*[A-Za-z0-9_]+' | grep -oE '[A-Za-z0-9_]+$' | head -1)"

if [ "$VAL" = "WQ_BURST" ]; then
    echo "PASS: Flame Blade's already-flaming branch grants WQ_BURST, as the Desc promises."
    exit 0
fi

echo "FAIL(1): Flame Blade's already-flaming branch grants ${VAL:-<unreadable>}, not the WQ_BURST its Desc promises."
echo "         Fix the quality value in the already-flaming branch of lib/pspells.irh (inc-wbq9)."
printf '%s\n' "$BRANCH" | sed 's/^/    | /'
exit 1
