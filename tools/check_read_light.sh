#!/bin/bash
# gate: live
# Reproduction for inc-caq8: reading a scroll (Item::ReadScroll, src/Magic.cpp)
# does not read the reader's own light level. The owner's rule (light bands
# are LightLevelAt, 0..255, thresholds inc/Light.h:99-101):
#   dark   level <  48 (LIGHT_SEE_MIN)  -- refused, scroll not spent
#   dim    48 <= level < 90             -- Decipher Script DC +10
#   bright level >= 90 (LIGHT_HIDE_MIN) -- no change
#   InfraRange > 0 (infravision/darkvision) -- reads as if bright, any level
#
# Today nothing in ReadScroll reads light at all, so all four bands roll the
# same bare DC (10 + scroll level) and the scroll is always spent. This check
# measures the reader's square with the source probe
# (INCURSION_READ_LIGHT_PROBE=1, static ReadLightProbe just above
# Item::ReadScroll in src/Magic.cpp, logs/read-light.log in the run dir) so a
# pass or fail is tied to a measured band, never an assumed one, and decides
# each of the five cases independently:
#   dark/no-infravision  PASS = refused (no Decipher roll, scroll count held)
#   dim                  PASS = dim DC is exactly 10 higher than bright's DC
#   bright                PASS = read went ahead and gave a DC to compare against
#   dark/infravision      PASS = read went ahead at the SAME DC as bright
#   dim/lowlight          PASS = low-light reader on a dim square, no +10
#
# inc-caq8 adds the fifth case: an elf (CA_LOWLIGHT 2, no infravision,
# lib/races.irh "elf;temp") on a dim square reads at the bright DC, because
# low-light vision treats dim as bright. Its fixture is elf-search-seed1-
# opt0818.sav, run with that fixture's own seed (1) and options
# (options-2026-08-18.dat), and its key file clears the longer elf arrival
# greeting ("-- more --") before the shared setup.
#
# Measured today (seed 4, human-paladin-seed4-opt0822.sav; seed 1,
# orc-barbarian-seed1-opt0822.sav; tools/fixtures/options-2026-08-22.dat):
#   dark/no-infra   level=0  infra=0  DC=19  stack 2->1  FAIL (read anyway)
#   dim             level=50 infra=0  DC=19  stack 2->1  FAIL (no +10 yet)
#   bright          level=96 infra=0  DC=19  stack 2->1  PASS (baseline)
#   dark/infra      level=0  infra=6  DC=19  stack 2->1  PASS (already bright-like)
# So this check goes RED today (dark/no-infra and dim both FAIL), as required.
#
# A fixture with infravision is needed for the fourth case: orcs have it
# (lib/races.irh), and the no-infravision fixture must not (humans don't).
# tools/fixtures/README.md explains why a LOADED fixture, not a generated
# character, survives a module change.
#
# Usage: tools/check_read_light.sh   (0 pass, 1 fail, 2 inconclusive)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

OPTIONS="tools/fixtures/options-2026-08-22.dat"
NOINFRA_SAV="tools/fixtures/chars/human-paladin-seed4-opt0822.sav"
NOINFRA_SEED=4
INFRA_SAV="tools/fixtures/chars/orc-barbarian-seed1-opt0822.sav"
INFRA_SEED=1
# inc-caq8: the low-light case is an elf (CA_LOWLIGHT 2, no infravision),
# and the run MUST use the fixture's own seed and options file (its .sheet.txt
# records both: seed 1, tools/fixtures/options-2026-08-18.dat).
LOWLIGHT_SAV="tools/fixtures/chars/elf-search-seed1-opt0818.sav"
LOWLIGHT_SEED=1
LOWLIGHT_OPTIONS="tools/fixtures/options-2026-08-18.dat"

[ -x ./incursion-headless ] || {
    echo "INCONCLUSIVE: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 2
}
[ -f "$NOINFRA_SAV" ] || { echo "INCONCLUSIVE: missing fixture $NOINFRA_SAV"; exit 2; }
[ -f "$INFRA_SAV" ] || { echo "INCONCLUSIVE: missing fixture $INFRA_SAV"; exit 2; }
[ -f "$LOWLIGHT_SAV" ] || { echo "INCONCLUSIVE: missing fixture $LOWLIGHT_SAV"; exit 2; }

# run_case <keys> <sav> <seed> <tag> [options]; echoes the run directory on
# stdout. The options default to the shared file; the low-light case passes its
# fixture's own options file, as that fixture's .sheet.txt requires.
run_case() {
    local keys="$1" sav="$2" seed="$3" tag="$4" opts="${5:-$OPTIONS}"
    local rundir out status
    rundir="logs/check-read-light.$$.${tag}"
    rm -rf "$rundir"
    out="$(INCURSION_READ_LIGHT_PROBE=1 \
        INCURSION_OPTIONS="$opts" \
        INCURSION_LOAD="$sav" \
        INCURSION_RUN_DIR="$rundir" \
        tools/headless.sh "tools/keys/$keys" "$seed" 2>&1)"
    status=$?
    if [ "$status" -ne 0 ]; then
        echo "INCONCLUSIVE: $keys exited $status" >&2
        echo "$out" >&2
        return 1
    fi
    echo "$rundir"
}

# probe_field <run> <field>; prints the named key=value from the FIRST line
# of logs/read-light.log (the state before the scroll was taken).
probe_field() {
    local run="$1" field="$2"
    [ -f "$run/logs/read-light.log" ] || return 1
    head -1 "$run/logs/read-light.log" | awk -v f="$field" '{
        for (i = 1; i <= NF; i++) {
            split($i, kv, "=")
            if (kv[1] == f) { print kv[2]; found=1 }
        }
        exit !found
    }'
}

# scroll_count <file>; 0 if the scroll is gone, else the count shown in the
# PACK LISTING ROW ("  07) 2 Scrolls of Wizard Sight"), never a message line
# such as "AutoStowing: Scroll of Wizard Sight." -- that message has no count
# and would otherwise be the first match in the file.
scroll_count() {
    local line n
    line="$(grep -E '^ *[0-9]+\) +([0-9]+ +)?Scrolls? of Wizard Sight' "$1" 2>/dev/null | head -1)"
    [ -z "$line" ] && { echo 0; return; }
    n="$(echo "$line" | grep -oE '[0-9]+ Scrolls? of Wizard Sight' | grep -oE '^[0-9]+')"
    [ -z "$n" ] && n=1
    echo "$n"
}

has_decipher_roll() { grep -q "Decipher Script Check" "$1" 2>/dev/null; }

get_dc() { grep -oE 'vs DC [0-9]+' "$1" 2>/dev/null | head -1 | awk '{print $3}'; }

# measure <run> <band>; prints "level infra mapfor before after dc" or returns
# 1 if the run cannot establish what it needs (missing screens/probe line, or
# a measured band that does not match what this case is supposed to be).
measure() {
    local run="$1" band="$2"
    local level infra mapfor before after dc
    level="$(probe_field "$run" level)" || return 1
    infra="$(probe_field "$run" infra)" || return 1
    mapfor="$(probe_field "$run" mapfor)" || return 1
    [ "$mapfor" = "1" ] || return 1
    for f in 0001-setup-pack 0002-read 0004-after-pack; do
        [ -f "$run/logs/screens/$f.txt" ] || return 1
    done
    before="$(scroll_count "$run/logs/screens/0001-setup-pack.txt")"
    after="$(scroll_count "$run/logs/screens/0004-after-pack.txt")"
    dc="$(get_dc "$run/logs/screens/0002-read.txt")"
    case "$band" in
        dark)  [ "$level" -lt 48 ] || return 1 ;;
        dim)   [ "$level" -ge 48 ] && [ "$level" -lt 90 ] || return 1 ;;
        bright) [ "$level" -ge 90 ] || return 1 ;;
    esac
    printf '%s %s %s %s %s\n' "$level" "$infra" "$before" "$after" "$dc"
}

fail=0
inconclusive=0

echo "running dark/no-infravision case ($NOINFRA_SAV, seed $NOINFRA_SEED)..."
dark_run="$(run_case read-light-dark.keys "$NOINFRA_SAV" "$NOINFRA_SEED" dark)" || { inconclusive=1; dark_run=""; }
echo "running dim case ($NOINFRA_SAV, seed $NOINFRA_SEED)..."
dim_run="$(run_case read-light-dim.keys "$NOINFRA_SAV" "$NOINFRA_SEED" dim)" || { inconclusive=1; dim_run=""; }
echo "running bright case ($NOINFRA_SAV, seed $NOINFRA_SEED)..."
bright_run="$(run_case read-light-bright.keys "$NOINFRA_SAV" "$NOINFRA_SEED" bright)" || { inconclusive=1; bright_run=""; }
echo "running dark/infravision case ($INFRA_SAV, seed $INFRA_SEED)..."
darkinfra_run="$(run_case read-light-dark.keys "$INFRA_SAV" "$INFRA_SEED" darkinfra)" || { inconclusive=1; darkinfra_run=""; }
echo "running dim/lowlight case ($LOWLIGHT_SAV, seed $LOWLIGHT_SEED)..."
lowlight_run="$(run_case read-light-dim-lowlight.keys "$LOWLIGHT_SAV" "$LOWLIGHT_SEED" dimlowlight "$LOWLIGHT_OPTIONS")" || { inconclusive=1; lowlight_run=""; }

report() { # report <label> <result: PASS|FAIL|INCONCLUSIVE> <detail> <rundir>
    printf '%-24s %-13s %s\n' "$1" "$2" "$3"
    [ -n "${4:-}" ] && echo "    Run dir: $4"
}

dark_dc=""
dim_dc=""
bright_dc=""
darkinfra_dc=""
lowlight_dc=""

if [ -n "$dark_run" ]; then
    if read -r level infra before after dc <<<"$(measure "$dark_run" dark)"; then
        dark_dc="$dc"
        if has_decipher_roll "$dark_run/logs/screens/0002-read.txt" || [ "$before" != "$after" ]; then
            report "dark/no-infravision" FAIL \
                "level=$level infra=$infra stack $before->$after -- read went ahead, expected a refusal" "$dark_run"
            fail=1
        elif ! grep -q "It is too dark to read the scroll." "$dark_run/logs/screens/0002-read.txt"; then
            report "dark/no-infravision" FAIL \
                "level=$level infra=$infra stack $before->$after -- no refusal text on the read screen" "$dark_run"
            fail=1
        else
            report "dark/no-infravision" PASS \
                "level=$level infra=$infra stack $before->$after -- refused, scroll held" "$dark_run"
        fi
    else
        report "dark/no-infravision" INCONCLUSIVE \
            "could not establish the dark band or a missing screen/probe line" "$dark_run"
        inconclusive=1
    fi
else
    report "dark/no-infravision" INCONCLUSIVE "the run did not complete" ""
fi

if [ -n "$bright_run" ]; then
    if read -r level infra before after dc <<<"$(measure "$bright_run" bright)"; then
        bright_dc="$dc"
        if [ -z "$dc" ] || [ "$before" = "$after" ]; then
            report "bright" INCONCLUSIVE \
                "level=$level no DC measured or the scroll was never read (stack $before->$after)" "$bright_run"
            inconclusive=1
        else
            report "bright" PASS \
                "level=$level infra=$infra DC=$dc stack $before->$after -- baseline for the dim/dark-infra comparisons" "$bright_run"
        fi
    else
        report "bright" INCONCLUSIVE \
            "could not establish the bright band or a missing screen/probe line" "$bright_run"
        inconclusive=1
    fi
else
    report "bright" INCONCLUSIVE "the run did not complete" ""
fi

if [ -n "$dim_run" ]; then
    if read -r level infra before after dc <<<"$(measure "$dim_run" dim)"; then
        dim_dc="$dc"
        if [ -z "$dim_dc" ] || [ -z "$bright_dc" ]; then
            report "dim" INCONCLUSIVE \
                "level=$level DC not measured on dim and/or bright, cannot compare" "$dim_run"
            inconclusive=1
        elif [ "$dim_dc" -eq $((bright_dc + 10)) ]; then
            report "dim" PASS \
                "level=$level infra=$infra DC=$dim_dc vs bright DC=$bright_dc -- the -10 Decipher Script penalty is applied" "$dim_run"
        else
            report "dim" FAIL \
                "level=$level infra=$infra DC=$dim_dc vs bright DC=$bright_dc -- expected dim DC = bright DC + 10" "$dim_run"
            fail=1
        fi
    else
        report "dim" INCONCLUSIVE \
            "could not establish the dim band or a missing screen/probe line" "$dim_run"
        inconclusive=1
    fi
else
    report "dim" INCONCLUSIVE "the run did not complete" ""
fi

if [ -n "$darkinfra_run" ]; then
    if read -r level infra before after dc <<<"$(measure "$darkinfra_run" dark)"; then
        darkinfra_dc="$dc"
        if [ "$infra" -le 0 ]; then
            report "dark/infravision" INCONCLUSIVE \
                "infra=$infra -- fixture has no infravision, wrong control" "$darkinfra_run"
            inconclusive=1
        elif ! has_decipher_roll "$darkinfra_run/logs/screens/0002-read.txt"; then
            report "dark/infravision" FAIL \
                "level=$level infra=$infra -- infravision reader was refused, expected a normal read" "$darkinfra_run"
            fail=1
        elif [ -z "$darkinfra_dc" ] || [ -z "$bright_dc" ]; then
            report "dark/infravision" INCONCLUSIVE \
                "level=$level DC not measured, cannot compare against bright" "$darkinfra_run"
            inconclusive=1
        elif [ "$darkinfra_dc" -eq "$bright_dc" ]; then
            report "dark/infravision" PASS \
                "level=$level infra=$infra DC=$darkinfra_dc == bright DC=$bright_dc -- reads as if bright" "$darkinfra_run"
        else
            report "dark/infravision" FAIL \
                "level=$level infra=$infra DC=$darkinfra_dc != bright DC=$bright_dc -- infravision did not read as bright" "$darkinfra_run"
            fail=1
        fi
    else
        report "dark/infravision" INCONCLUSIVE \
            "could not establish the dark band or a missing screen/probe line" "$darkinfra_run"
        inconclusive=1
    fi
else
    report "dark/infravision" INCONCLUSIVE "the run did not complete" ""
fi

# dim/lowlight: a low-light reader on a dim square treats it as bright, so its
# Decipher Script DC must equal the bright case's DC (not bright + 10). The
# band must be dim and infra must be 0, or the case proves nothing and fails.
if [ -n "$lowlight_run" ]; then
    if read -r level infra before after dc <<<"$(measure "$lowlight_run" dim)"; then
        lowlight_dc="$dc"
        if [ "$infra" -ne 0 ]; then
            report "dim/lowlight" INCONCLUSIVE \
                "level=$level infra=$infra -- the elf has infravision, wrong control" "$lowlight_run"
            inconclusive=1
        elif [ -z "$lowlight_dc" ] || [ -z "$bright_dc" ]; then
            report "dim/lowlight" INCONCLUSIVE \
                "level=$level DC not measured on dim and/or bright, cannot compare" "$lowlight_run"
            inconclusive=1
        elif [ "$lowlight_dc" -eq "$bright_dc" ]; then
            report "dim/lowlight" PASS \
                "level=$level infra=$infra DC=$lowlight_dc == bright DC=$bright_dc -- low-light vision treats dim as bright" "$lowlight_run"
        else
            report "dim/lowlight" FAIL \
                "level=$level infra=$infra DC=$lowlight_dc vs bright DC=$bright_dc -- expected the bright DC, not +10" "$lowlight_run"
            fail=1
        fi
    else
        report "dim/lowlight" INCONCLUSIVE \
            "could not establish the dim band or a missing screen/probe line" "$lowlight_run"
        inconclusive=1
    fi
else
    report "dim/lowlight" INCONCLUSIVE "the run did not complete" ""
fi

if [ "$fail" -eq 1 ]; then
    echo "FAIL: at least one case did not match the owner's light-band rule."
    exit 1
fi
if [ "$inconclusive" -eq 1 ]; then
    echo "INCONCLUSIVE: at least one case could not be measured."
    exit 2
fi
echo "PASS: all five light-band cases match the owner's rule."
exit 0
