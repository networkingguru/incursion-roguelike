#!/bin/bash
# gate: live
# Does a door made by a timed SUMMONED stati vanish when the stati elapses?
# (bd inc-rgzr, instance 2)
#
# THE DEFECT. Thing::StatiOff (inc/Map.h) is virtual with the parameters
# (Status s, bool elapsed = false). Feature::StatiOff (inc/Feature.h) declared
# only (Status s), which is a different function and hides the base instead of
# overriding it. The one call, in the stati-expiry macro in inc/Map.h, goes
# through a Thing*, so Feature::StatiOff (src/Feature.cpp) never ran. That body
# prints "The <name> winks out of existence." and removes the summoned feature.
#
# THE SUBJECT is Wall of Doors (lib/wspells.irh), which gives each door
# GainTempStati(SUMMONED, ..., 2d6 + caster level). tools/keys/
# wall-of-doors-expiry.keys casts it as a first-level mage, dumps the map, waits
# 60 searches (about 17 game hours, far beyond any duration) and dumps again.
#
# THE ORACLE is the map: the door glyph 'x' in the map pane (the left of the
# '|') of the cast dump, then of the waited dump. The cast dump must show doors
# or the session is INCONCLUSIVE. The waited dump must show none, and the
# message log must carry "winks out of existence".
#
# Usage: tools/check_summoned_feature_expiry.sh    (0 pass, 1 fail, 2 could not measure)
. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat

check_run tools/keys/wall-of-doors-expiry.keys 1

doors() { # <dump> -> number of door glyphs in the map pane. Rows 1 and 2 are
          # the header and the message line, which can hold an 'x' of prose.
    awk -F'|' 'NR > 2 { n += gsub(/x/, "", $1) } END { print n + 0 }' "$1"
}

cast="$(ls "$CHECK_RUN"/logs/screens/*-doors-cast.txt 2>/dev/null | head -1)"
waited="$(ls "$CHECK_RUN"/logs/screens/*-doors-waited.txt 2>/dev/null | head -1)"
msgs="$(ls "$CHECK_RUN"/logs/screens/*-messages.txt 2>/dev/null | head -1)"
if [ -z "$cast" ] || [ -z "$waited" ] || [ -z "$msgs" ]; then
    echo "INCONCLUSIVE: the key script did not reach its dumps in $CHECK_RUN."
    exit 2
fi

before="$(doors "$cast")"
after="$(doors "$waited")"
if [ "$before" -eq 0 ]; then
    echo "INCONCLUSIVE: the cast made no door on the map ($cast)."
    exit 2
fi
echo "  doors on the map: $before after the cast, $after after the wait"

if [ "$after" -eq 0 ]; then
    CHECK_EXPECTS=$((CHECK_EXPECTS + 1))
    echo "  ok    every summoned door is gone"
else
    CHECK_FAIL=1
    echo "  FAIL  $after summoned door(s) still stand after the wait ($waited)"
fi
if grep -qF "winks out of existence" "$msgs"; then
    CHECK_EXPECTS=$((CHECK_EXPECTS + 1))
    echo "  ok    the message log says a door winks out of existence"
else
    CHECK_FAIL=1
    echo "  FAIL  no \"winks out of existence\" in the message log ($msgs)"
fi

check_done "a summoned door vanishes when its stati elapses"
