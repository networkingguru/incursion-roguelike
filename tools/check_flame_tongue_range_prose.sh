#!/bin/bash
# Regression check for PA-08-F69 / inc-tek.8.8: the flame tongue sword's
# description must state its Tongue of Flame reach as a 30-foot base plus 10
# feet per point of Charisma modifier (minimum 30 feet), matching its
# EV_CALC_EFFECT handler, e.vRange = 3 + max(0, EActor->Mod(A_CHA)). vRange is
# in SQUARES and this file scales 10 feet per square, so (3 + Cha mod) squares =
# 30 feet + 10 feet per Charisma-modifier point, floored at 30 feet by the
# max(0, ...) clamp. The old prose said "the bearer's Charisma modifier times
# ten in feet (minimum 20)", which dropped the 30-foot base and stated a 20-foot
# floor the clamp cannot produce; the code wins. Red while the Desc still reads
# the old range clause, green once it states the 30-foot base plus 10 feet per
# Charisma modifier.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SOURCE="${SOURCE:-lib/m_items.irh}"
# Anchor on the flame tongue weapon block, from its header to the first closing
# "; (the Desc's own close), then test the Desc STRING itself, NOT the whole
# block, so the upstream: comment that quotes the old wording is excluded.
block="$(sed -n '/AI_WEAPON Effect "flame tongue" : EA_GRANT/,/";/p' "$SOURCE")"
desc="$(printf "%s\n" "$block" | sed -n '/Desc: "/,/";/p')"

if printf "%s\n" "$desc" | grep -q "maximum range of 30"; then
    echo "PASS: PA-08-F69 / inc-tek.8.8 the flame tongue sword description states its Tongue of Flame reach as a 30-foot base plus 10 feet per Charisma modifier, matching its vRange = 3 + max(0, Mod(A_CHA)) squares code."
    exit 0
fi

if printf "%s\n" "$desc" | grep -q "Charisma modifier times ten in feet"; then
    echo "FAIL: the flame tongue sword description states the Tongue of Flame range as \"the bearer's Charisma modifier times ten in feet (minimum 20)\", yet its EV_CALC_EFFECT sets vRange = 3 + max(0, Mod(A_CHA)) squares = 30 feet plus 10 feet per Charisma modifier."
    exit 1
fi

echo "FAIL: the flame tongue sword description no longer contains the expected range clause; the anchor or wording changed."
exit 1
