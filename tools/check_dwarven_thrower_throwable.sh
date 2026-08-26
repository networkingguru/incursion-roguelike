#!/bin/bash
# Regression check for F46 / inc-tek.8.8: the Dwarven Thrower's base item is a
# throwable, non-generated hand-copy of the ordinary warhammer.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

item="$(sed -n '/^Item "warhammer;thrown"[[:space:]]*:/,$p' lib/main.irc)"
effect="$(sed -n '/^AI_WEAPON Effect "Dwarven Thrower"/,/^AI_WEAPON Effect /p' lib/m_items.irh)"

if grep -Eq '^Item[[:space:]]+"warhammer;thrown"[[:space:]]*:' lib/weapons.irh; then
    echo 'FAIL: lib/weapons.irh contains the save-breaking mid-array warhammer;thrown item.'
    exit 1
fi
printf '%s\n' "$item" | grep -Eq '^Item[[:space:]]+"warhammer;thrown"[[:space:]]*:[[:space:]]*T_WEAPON' || {
    echo 'FAIL: lib/main.irc does not define Item "warhammer;thrown".'
    exit 1
}
printf '%s\n' "$item" | grep -Eq '^[[:space:]]*Flags:.*(^|[[:space:],])IT_THROWABLE([[:space:],;]|$)' || {
    echo 'FAIL: warhammer;thrown does not carry IT_THROWABLE on its Flags line.'
    exit 1
}
printf '%s\n' "$effect" | grep -Eq '^AI_WEAPON[[:space:]]+Effect[[:space:]]+"Dwarven Thrower"' || {
    echo 'FAIL: the Dwarven Thrower effect was not found.'
    exit 1
}
printf '%s\n' "$effect" | grep -Eq '^[[:space:]]*\*[[:space:]]*BASE_ITEM[[:space:]]+\$"warhammer;thrown"[[:space:]]*,' || {
    echo 'FAIL: the Dwarven Thrower does not use the throwable warhammer base.'
    exit 1
}
if printf '%s\n' "$effect" | grep -Eq '^[[:space:]]*\*[[:space:]]*BASE_ITEM[[:space:]]+\$"warhammer"[[:space:]]*,'; then
    echo 'FAIL: the Dwarven Thrower still uses the plain, non-throwable warhammer.'
    exit 1
fi

echo 'PASS: F46 / inc-tek.8.8 Dwarven Thrower uses an IT_THROWABLE warhammer base.'
