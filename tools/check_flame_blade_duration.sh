#!/bin/bash
# Regression check for Flame Blade's duration, inc-wbq9 (PA-07-F9).
#
# THE DEFECT. lib/pspells.irh declared both of Flame Blade's forms with a
# finite duration -- `flame blade;augment` with EF_DXLONG (1000 + 100*level
# ticks) and `flame blade;conjure` with EF_DLONG (100 + 10*level) -- while the
# spell's own Desc promises "both of which last for a full day". The project's
# persistent-buff mechanism is duration -2 (src/Magic.cpp:526-527, EF_PERSISTANT)
# which lasts until the caster rests (src/Player.cpp:2204-2205 -> Map::DaysPassed
# at src/Player.cpp:2484/2501 removes every Duration == -2 stati). Both
# sub-effects MUST therefore carry EF_PERSISTANT and MUST NOT carry EF_DLONG or
# EF_DXLONG.
#
# THE ORACLE is the Flags line of each sub-effect block in the tracked source.
# This reads the shipped data directly, so it proves the declaration and not a
# transient screen. It fails red when either block still has EF_DLONG/EF_DXLONG
# or lacks EF_PERSISTANT, and passes only when both are persistent.
#
# Exit 0 pass, 1 the defect is present, 2 a block could not be found -- the
# effect moved or was renamed.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FILE="${PSPELLS:-$ROOT/lib/pspells.irh}"
case "$FILE" in
    /*) : ;;
    *) FILE="$ROOT/$FILE" ;;
esac

[ -f "$FILE" ] || { echo "FAIL(2): $FILE is missing; nothing was examined"; exit 2; }

fail=0

check_block() {
    local name="$1"
    local block flags

    block="$(awk -v pat="Effect \"$name\"" '
      $0 ~ pat { inblk=1 }
      inblk { print }
      inblk && /^  \}/ { exit }
    ' "$FILE")"

    if [ -z "$block" ]; then
        echo "FAIL(2): the '$name' effect block was not found in $FILE."
        echo "         The effect moved or was renamed. Re-point this check before trusting it."
        exit 2
    fi

    flags="$(printf '%s\n' "$block" | grep -E 'Flags:' | head -1)"

    if printf '%s' "$flags" | grep -qE 'EF_DXLONG|EF_DLONG'; then
        echo "FAIL(1): '$name' still carries a finite duration flag, so it expires far"
        echo "         sooner than the full day its Desc promises."
        printf '%s\n' "$flags" | sed 's/^/    | /'
        fail=1
    fi

    if ! printf '%s' "$flags" | grep -q 'EF_PERSISTANT'; then
        echo "FAIL(1): '$name' lacks EF_PERSISTANT, so it is not a duration -2 buff"
        echo "         that lasts until the caster rests."
        printf '%s\n' "$flags" | sed 's/^/    | /'
        fail=1
    fi
}

check_block "flame blade;augment"
check_block "flame blade;conjure"

if [ "$fail" -eq 1 ]; then
    echo "         Fix the Flags line of the affected block(s) in lib/pspells.irh (inc-wbq9)."
    exit 1
fi

echo "PASS: both Flame Blade forms carry EF_PERSISTANT and no finite duration flag, so they last until rest."
exit 0
