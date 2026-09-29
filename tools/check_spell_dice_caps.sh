#!/bin/bash
# gate: live
# inc-r6u1: Searing Light, and the two Glyphs of Warding, must roll no more
# dice than the maximum their own Desc (and the SRD) states.
#
# THE DEFECT. `lib/pspells.irh` scaled three spells with the unbounded
# `LEVEL_SCALED` / `LEVEL_SCALED2` curves (inc/Inline.h), which never stop:
# Searing Light's living branch was `(LEVEL_SCALED2)d8` where the Desc caps it
# at 5d8, its undead branch `(LEVEL_SCALED)d6` where the Desc caps it at 10d6,
# and its construct branch `(LEVEL_SCALED2)d6` where the Desc caps it at 5d6;
# Glyph of Warding carried the same `(LEVEL_SCALED2)d8` against a 5d8 cap and
# Greater Glyph of Warding `(LEVEL_SCALED)d8` against a 10d8 cap. At caster
# level 20 the old curves give 7d8 / 12d6 / 7d8 / 7d8 / 12d8.
#
# WHAT THIS CHECK CAN AND CANNOT OBSERVE. The caster level here is the priest's
# ChallengeRating (Learn Any Spell sets SP_INNATE, src/Magic.cpp:483), and
# MAX_CHAR_LEVEL is 11 (inc/Defines.h), so the highest effective Searing Light
# caster level a player can reach is 11 -- Aiswin's domains (Fate, Knowledge,
# Night, Planning) grant no SC_EVO/SC_LIGHT school bonus. At caster level 11
# the LIVING branch is already at its 5d8 cap on both builds, so the living half
# of the over-cap defect needs caster level 15 and is unreachable; the UNDEAD
# branch is where the defect is visible in play, rolling 9d6 before the fix
# where the Desc promises 10d6. This check therefore asserts the PROMISED
# maximum exactly (living 5d8, undead 10d6), which fails on the unfixed build
# for the undead branch and is a stronger, not weaker, test than "no more than".
# The Glyphs are covered structurally: `ThrowTerraDmg` (src/Event.cpp:733)
# prints a flat rolled number, not the dice string, so a blast in play cannot
# reveal the die COUNT the way the Searing Light combat line does.
#
# The control run is a priest 6 (effective caster level 6), where both formulas
# are below their caps and the fix must change nothing: living 3d8, undead 6d6.
#
# A run that cannot produce its Damage line, or whose sheet is not the level
# this check measures, is a FAIL and never a pass: a green result from a session
# that never reached the state under test is the mistake this directory guards
# against (inc-loa.3).
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=1
OPTIONS=tools/fixtures/options-2026-08-22.dat
PSPELLS=lib/pspells.irh

[ -x ./incursion-headless ] || {
    echo "FAIL: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 1
}

# The die COUNT N off the game's own Damage line ("Mummy's Damage: 10d6+2 =
# 40 Light Damage"). Prints the first such N and quits; prints nothing when no
# Damage line exists, which the caller turns into a FAIL. One sed, no pipe into
# head (tools/check_sigpipe_status.sh).
_dice_of() { # <screen dump>
    sed -n -e 's/.*Damage: *\([0-9][0-9]*\)d[0-9][0-9]*.*/\1/p' \
        -e 't done' -e 'b' -e ':done' -e 'q' "$1" 2>/dev/null
}

# The class line off the run's own sheet ("Class  Priest 11").
_class_line() { # <screen dump>
    sed -n -e 's/^ *Class *\(.*[^ ].*\)$/\1/p' -e 't done' -e 'b' -e ':done' \
        -e 'q' "$1" 2>/dev/null
}

# Run one key script in its own sandbox directory and echo the run directory on
# success; the harness report goes to the caller's stdout untouched.
_run_one() { # <keyscript> <tag>
    local keys="$1" tag="$2" out status
    local run="$ROOT/logs/runs/$(date +%Y%m%d-%H%M%S)-$$-$tag"
    out="$(INCURSION_OPTIONS="$OPTIONS" INCURSION_RUN_DIR="$run" \
        tools/headless.sh "$keys" "$SEED" 2>&1)"
    status=$?
    printf '%s\n' "$out"
    if [ "$status" -ne 0 ]; then
        echo "FAIL: tools/headless.sh exit $status running $keys"
        printf '%s\n' "$out" | sed -n '/^--- after the session ---/,$p' | sed 's/^/      /'
        return 1
    fi
    printf '%s\n' "$run"
}

fail=0

# --- structural: the five pvals, and the new cap constant -------------------
echo "=== structural: lib/pspells.irh pvals use the capped constants ==="
want_glyph='rval: $"strange rune"; sval: REF; pval: (LEVEL_1PER2_MAX5)d8;'
want_gglyph='rval: $"strange rune"; sval: REF; pval: (LEVEL_MAX10)d8;'
want_liv='xval: AD_SUNL; pval: (LEVEL_1PER2_MAX5)d8; tval: MA_LIVING;'
want_und='{ xval: AD_SUNL; pval: (LEVEL_MAX10)d6; tval: MA_UNDEAD;'
want_con='{ xval: AD_SUNL; pval: (LEVEL_1PER2_MAX5)d6; tval: MA_CONSTRUCT;'
for pair in "Glyph of Warding|$want_glyph" "Greater Glyph|$want_gglyph" \
            "Searing Light living|$want_liv" "Searing Light undead|$want_und" \
            "Searing Light construct|$want_con"; do
    name="${pair%%|*}"; pat="${pair#*|}"
    if ! grep -qF -- "$pat" "$PSPELLS"; then
        echo "FAIL: lib/pspells.irh has no '$pat' ($name)."
        fail=1
    fi
done
if ! grep -qE '^#define +LEVEL_1PER2_MAX5 +-127\b' inc/Defines.h; then
    echo "FAIL: inc/Defines.h does not define LEVEL_1PER2_MAX5 as -127."
    fail=1
fi
if ! grep -qF 'case LEVEL_1PER2_MAX5: return min(5,level/2);' inc/Inline.h; then
    echo "FAIL: inc/Inline.h has no LevelAdjust arm for LEVEL_1PER2_MAX5."
    fail=1
fi
[ "$fail" -eq 0 ] && echo "structural: all five pvals and the LEVEL_1PER2_MAX5 arm present."

# --- live: high runs at the maximum reachable caster level -------------------
echo
echo "=== high living: tools/keys/searing-light-living.keys (priest 11, CL 11) ==="
hl="$(_run_one tools/keys/searing-light-living.keys searing-light-cap-living)" || exit 1
hl_run="$(printf '%s\n' "$hl" | tail -1)"
printf '%s\n' "$hl" | sed '$d'

echo
echo "=== high undead: tools/keys/searing-light-undead.keys (priest 11, CL 11) ==="
hu="$(_run_one tools/keys/searing-light-undead.keys searing-light-cap-undead)" || exit 1
hu_run="$(printf '%s\n' "$hu" | tail -1)"
printf '%s\n' "$hu" | sed '$d'

echo
echo "=== control: tools/keys/searing-light-control.keys (priest 6, CL 6) ==="
ctl="$(_run_one tools/keys/searing-light-control.keys searing-light-cap-control)" || exit 1
ctl_run="$(printf '%s\n' "$ctl" | tail -1)"
printf '%s\n' "$ctl" | sed '$d'

# The high runs must be the level this check measures, or nothing below means
# anything.
if ! grep -qE 'Class[[:space:]]+Priest 11([[:space:]]|$)' \
        "$hl_run"/logs/screens/*-level.txt "$hu_run"/logs/screens/*-level.txt 2>/dev/null; then
    echo "FAIL: a high run's sheet does not show 'Priest 11'; the key script did"
    echo "      not build the character this check measures."
    fail=1
fi
if ! grep -qE 'Class[[:space:]]+Priest 6([[:space:]]|$)' \
        "$ctl_run"/logs/screens/*-level.txt 2>/dev/null; then
    echo "FAIL: the control's sheet does not show 'Priest 6'."
    fail=1
fi

hl_dice="$(_dice_of "$hl_run"/logs/screens/*-living-after-cast.txt)"
hu_dice="$(_dice_of "$hu_run"/logs/screens/*-undead-after-cast.txt)"
ctl_liv="$(_dice_of "$ctl_run"/logs/screens/*-control-after-living.txt)"
ctl_und="$(_dice_of "$ctl_run"/logs/screens/*-control-after-undead.txt)"

echo
if [ -z "$hl_dice" ]; then
    echo "FAIL: the high living run produced no Damage line; cannot read the dice."
    fail=1
fi
if [ -z "$hu_dice" ]; then
    echo "FAIL: the high undead run produced no Damage line; cannot read the dice."
    fail=1
fi
if [ -z "$ctl_liv" ] || [ -z "$ctl_und" ]; then
    echo "FAIL: the control run produced no living or no undead Damage line;"
    echo "      cannot read the dice."
    fail=1
fi

echo
echo "high living:    ${hl_dice:-?}d8   (Desc max 5d8)"
echo "high undead:    ${hu_dice:-?}d6   (Desc max 10d6)"
echo "control living: ${ctl_liv:-?}d8   (want 3d8)"
echo "control undead: ${ctl_und:-?}d6   (want 6d6)"
echo "specimens: $hl_run/logs/screens, $hu_run/logs/screens, $ctl_run/logs/screens"

# The over-cap test: living must not exceed 5d8 and undead must not exceed
# 10d6. On top of that the high runs must reach the promised maximum, which is
# how the unfixed undead branch (9d6) fails. Skip a comparison whose dice could
# not be read -- that is already a FAIL above, and arithmetic on an empty
# string would be a second, noisier one.
if [ -n "$hl_dice" ]; then
if [ "$hl_dice" -gt 5 ]; then
    echo "FAIL: high Searing Light rolls ${hl_dice}d8 living, over the 5d8 maximum."
    fail=1
elif [ "$hl_dice" -ne 5 ]; then
    echo "FAIL: high Searing Light rolls ${hl_dice}d8 living, not the promised 5d8."
    fail=1
fi
fi
if [ -n "$hu_dice" ]; then
if [ "$hu_dice" -gt 10 ]; then
    echo "FAIL: high Searing Light rolls ${hu_dice}d6 undead, over the 10d6 maximum."
    fail=1
elif [ "$hu_dice" -ne 10 ]; then
    echo "FAIL: high Searing Light rolls ${hu_dice}d6 undead, not the promised 10d6;"
    echo "      the unbounded LEVEL_SCALED curve is still in place."
    fail=1
fi
fi

# The control must be unchanged below the caps.
if [ -n "$ctl_liv" ] && [ "$ctl_liv" -ne 3 ]; then
    echo "FAIL: control Searing Light living is ${ctl_liv}d8, not the uncapped 3d8;"
    echo "      the cap must not bite below its ceiling."
    fail=1
fi
if [ -n "$ctl_und" ] && [ "$ctl_und" -ne 6 ]; then
    echo "FAIL: control Searing Light undead is ${ctl_und}d6, not the uncapped 6d6;"
    echo "      the cap must not bite below its ceiling."
    fail=1
fi

if [ "$fail" = 0 ]; then
    echo "PASS: Searing Light is capped at 5d8 living / 10d6 undead (CL 11), the"
    echo "      control is unchanged (CL 6 -> 3d8 / 6d6), and the five pvals use"
    echo "      the capped constants."
    exit 0
fi
exit 1
