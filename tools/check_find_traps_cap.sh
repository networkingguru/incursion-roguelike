#!/bin/bash
# gate: live
# inc-8mg9: Find Traps must cap its Search bonus at +10, the maximum its own
# description promises.
#
# The spell's Desc reads "an bonus equal to your caster level (maximum +10) on
# Search checks", but its declaration carried `pval: LEVEL_1PER1` -- the
# uncapped `level` -- so the bonus grew without limit. This runs the two key
# scripts the dispatch left in tools/keys/ and reads the Search rating off the
# skill manager before and after the cast.
#
# Both runs LOAD the frozen priest orc-priest-seed1-opt0822 (inc-b4l3g.17),
# never generate one: chargen on some seeds shows a screen the key script does
# not expect. The high run advances it to Priest 11 under wizard Free
# Advancement. Learn Any Spell sets SP_INNATE, so CalcEffect (src/Magic.cpp:
# 633-641) uses ChallengeRating (the sum of class levels), plus the Fate
# domain's Divination +1 (lib/domains.irh:296) -- an effective Find Traps
# caster level of 12. Before the fix that is a +12 enhance; after it is +10.
# The control run stays level 1, effective caster level 2, a +2 enhance either
# way, and proves the cap did not simply switch the spell off.
#
# A run that cannot produce its Search line, or whose high sheet does not show
# Priest 11, is a FAIL and never a pass: a green result from a session that
# never reached the state under test is the mistake this directory guards
# against (inc-loa.3). A harness failure is exit 2 (could not measure).
#
# fact: settings -- pinned tools/fixtures/options-2026-08-22.dat
# fact: character (race, class, god, attributes, perks, domains) -- fixture orc-priest-seed1-opt0822 via INCURSION_LOAD
# fact: character level -- wizard Free Advancement and G in the key script
# fact: level-up menus -- fixed by the fixture's attributes, answered by the key script's @while lines
# fact: the school caster-level bonus -- the fixture's Fate domain, Divination +1 (lib/domains.irh:296); the check's expected control enhance (+2) includes it
# fact: monsters -- wizard Freeze Monsters
# fact: casting roll -- wizard Ignore Spell Failure
# fact: mana -- wizard Infinite Mana
# fact: hit point and mana rolls at level-up -- not read by the check; it reads the Search rating and the class line only
# fact: arrival map -- not read by the check; it reads the sheet and skill screens only
#
# Usage: tools/check_find_traps_cap.sh   (0 pass, 1 fail, 2 could not measure)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=1
OPTIONS=tools/fixtures/options-2026-08-22.dat
FIXTURE=tools/fixtures/chars/orc-priest-seed1-opt0822.char

[ -f "$FIXTURE" ] || { echo "INCONCLUSIVE: character fixture $FIXTURE is not there"; exit 2; }

[ -x ./incursion-headless ] || {
    echo "INCONCLUSIVE: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 2
}

# Read one run's Search rating before and after the cast. Prints "<before>
# <after>" on stdout, or nothing if either line is missing -- the caller turns
# that silence into a FAIL.
_search_ratings() { # <run dir>
    local run="$1" before after
    before="$(sed -n "s/.*> Searching.*Int[[:space:]]*+\\([0-9][0-9]*\\).*/\\1/p" \
        "$run"/logs/screens/*-search-before.txt 2>/dev/null | head -1)"
    after="$(sed -n "s/.*> Searching.*Int[[:space:]]*+\\([0-9][0-9]*\\).*/\\1/p" \
        "$run"/logs/screens/*-search-after.txt 2>/dev/null | head -1)"
    [ -n "$before" ] && [ -n "$after" ] && printf '%s %s\n' "$before" "$after"
}

# Run one key script in its own sandbox directory and echo the run directory on
# success; the harness report goes to the caller's stdout untouched.
_run_one() { # <keyscript> <tag>
    local keys="$1" tag="$2" out status
    local run="$ROOT/logs/runs/$(date +%Y%m%d-%H%M%S)-$$-$tag"
    out="$(INCURSION_LOAD="$FIXTURE" INCURSION_OPTIONS="$OPTIONS" INCURSION_RUN_DIR="$run" \
        tools/headless.sh "$keys" "$SEED" 2>&1)"
    status=$?
    printf '%s\n' "$out"
    if [ "$status" -ne 0 ]; then
        echo "INCONCLUSIVE: tools/headless.sh exit $status running $keys; nothing was measured"
        printf '%s\n' "$out" | sed -n '/^--- after the session ---/,$p' | sed 's/^/      /'
        return 1
    fi
    printf '%s\n' "$run"
}

# The four wizard switches must read YES, else the run did not measure the cast.
_switches_on() { # <run dir>
    local f row
    f="$(ls "$1"/logs/screens/*-switches.txt 2>/dev/null | head -1)"
    [ -n "$f" ] || return 1
    for row in "Free Advancement" "Ignore Spell Failure" "Infinite Mana" "Freeze Monsters"; do
        grep -qE "$row[[:space:]]+YES" "$f" || return 1
    done
}

fail=0
echo "=== high run: tools/keys/find-traps-cap.keys (priest 11, effective CL 12) ==="
high="$(_run_one tools/keys/find-traps-cap.keys find-traps-cap-high)" || { printf '%s\n' "$high"; exit 2; }
high_run="$(printf '%s\n' "$high" | tail -1)"
printf '%s\n' "$high" | sed '$d'

if ! grep -qE 'Class[[:space:]]+Priest 11([[:space:]]|$)' \
        "$high_run"/logs/screens/*-search-before.txt \
        "$high_run"/logs/screens/*-search-after.txt 2>/dev/null; then
    echo "FAIL: the high run's sheets do not show 'Priest 11'; the key script"
    echo "      did not build the character this check measures."
    fail=1
fi

_switches_on "$high_run" || { echo "INCONCLUSIVE: the high run's wizard switches are not all YES."; exit 2; }

echo
echo "=== control run: tools/keys/find-traps-control.keys (priest 1, effective CL 2) ==="
ctl="$(_run_one tools/keys/find-traps-control.keys find-traps-cap-control)" || { printf '%s\n' "$ctl"; exit 2; }
ctl_run="$(printf '%s\n' "$ctl" | tail -1)"
printf '%s\n' "$ctl" | sed '$d'

_switches_on "$ctl_run" || { echo "INCONCLUSIVE: the control run's wizard switches are not all YES."; exit 2; }

high_ratings="$(_search_ratings "$high_run")"
ctl_ratings="$(_search_ratings "$ctl_run")"

echo
if [ -z "$high_ratings" ]; then
    echo "FAIL: no Search line in the high run's search-before/search-after dumps."
    echo "      Looked under $high_run/logs/screens."
    fail=1
fi
if [ -z "$ctl_ratings" ]; then
    echo "FAIL: no Search line in the control run's search-before/search-after dumps."
    echo "      Looked under $ctl_run/logs/screens."
    fail=1
fi
[ "$fail" -eq 0 ] || exit 1

set -- $high_ratings
high_before=$1 high_after=$2
set -- $ctl_ratings
ctl_before=$1 ctl_after=$2
high_enhance=$((high_after - high_before))
ctl_enhance=$((ctl_after - ctl_before))

echo "high:    Search $high_before -> $high_after  (enhance +$high_enhance, want +10)"
echo "control: Search $ctl_before -> $ctl_after  (enhance +$ctl_enhance, want +2)"
echo "specimens: $high_run/logs/screens, $ctl_run/logs/screens"

if [ "$high_enhance" -ne 10 ]; then
    echo "FAIL: the effective-CL-12 Find Traps enhance is +$high_enhance, not the +10"
    echo "      the spell's Desc promises as its maximum."
    fail=1
fi
if [ "$ctl_enhance" -ne 2 ]; then
    echo "FAIL: the effective-CL-2 control enhance is +$ctl_enhance, not +2; the"
    echo "      spell must still grant its uncapped caster level below 10."
    fail=1
fi

if [ "$fail" = 0 ]; then
    echo "PASS: Find Traps caps its Search bonus at +10 (CL 12 -> +10, CL 2 -> +2)."
    exit 0
fi
exit 1
