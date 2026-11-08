#!/bin/bash
# The case oracle: what tools/pressure/route.sh sets as INCURSION_FINISH_GATE (inc-cjos0 phase 8, D2).
#
#   (run by tools/finish_bead.sh in the bead's worktree, after it brought the base branch in)
#
# Owner ruling 2026-11-07: the full landing gate is replaced, per case, by this oracle. Every other step of
# finish_bead.sh runs for real. In the worktree it runs, in order:
#   build      BACKEND=posix ./build_macos.sh   (its own prechecks run first and may stop it); a landing whose C++
#              sources equal a tree already built reuses that binary and recompiles only the module (see below)
#   defdups    python3 tools/check_define_dups.py
#   stored     python3 tools/check_stored_values.py --base <frozen master SHA>
#   savenames  python3 tools/check_save_names.py
#   fieldnames tools/check_field_names.sh
#   compat     every tools/fixtures/chars/*.sav through tools/pressure/field_values.sh, compared with
#              compare_values.py against the baseline value files recorded from the frozen master build; one
#              `changed` or `missing` line fails it
#   plant      when INCURSION_PRESSURE_PLANT names a spec: tools/pressure/plant.sh plants the case's content in the
#              chosen fixture with THIS tree's build, keeps the new save and its value file in content-new/ (route.sh
#              keeps them after a successful landing)
#   content    every content save an earlier landing kept (INCURSION_PRESSURE_CONTENT): load it in this tree, compare
#              with the value file recorded by the build that planted it; one `changed` or `missing` line fails it
#              for a scored save (planted by a landing on master), and is only printed for an epic one
#   witness    the case's own command, when INCURSION_PRESSURE_WITNESS names one (run in the worktree)
#
# Environment (all set by route.sh):
#   INCURSION_PRESSURE_BASE_SHA     the frozen master commit: what master was before this merge
#   INCURSION_PRESSURE_BASELINE     directory of <fixture>.txt value files recorded from that master's build
#   INCURSION_PRESSURE_VALUES_OUT   directory for this run's value files and `verdict`; route.sh keeps them as the
#                                   next baseline when the landing succeeds (this tree IS the landed tree)
#   INCURSION_PRESSURE_WITNESS      optional path of the case's witness.sh
#   INCURSION_PRESSURE_PLANT        optional spec file this landing plants (plant.A or plant.B of the case), with
#   INCURSION_PRESSURE_PLANT_TAG    A or B, INCURSION_PRESSURE_PLANT_FIXTURE the fixture name, and
#   INCURSION_PRESSURE_PLANT_SCORED 1 when the landing is on master (an epic save is disposable: never scored)
#   INCURSION_PRESSURE_CONTENT      optional directory of kept content saves: <tag>.sav, <tag>.txt (baseline values),
#                                   <tag>.fixture, <tag>.scored
#
#   INCURSION_PRESSURE_LANDING      `full` (default) or `source`. `source` runs the three source checks that need no binary (defdups, stored, savenames): no build, no
#                                   fixture compare, no plant, no content, no witness (a side landing that is not scored)
#   INCURSION_PRESSURE_BINCACHE     optional directory of binaries, <srchash>/incursion-headless, shared by the suite
#
# Output: one `oracle: <step> PASS|FAIL|UNMEASURED` line per step, then `oracle: PASS|FAIL|UNMEASURED`.
# Exit: 0 every step passed, 1 a step failed, 2 no step failed but one could not measure (never a pass).
#
# fact: the frozen master -- INCURSION_PRESSURE_BASE_SHA, a commit of the scratch repository
# fact: fixtures -- tools/fixtures/chars/*.sav, frozen bytes; no seed, no key script, no options file (dumps only)
# fact: baseline -- value files of the frozen master's own build, recorded by route.sh
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
unset INCURSIONPATH INCURSION_LOAD INCURSION_OPTIONS INCURSION_RUN_DIR
: "${INCURSION_PRESSURE_BASE_SHA:?oracle: INCURSION_PRESSURE_BASE_SHA is unset}"
: "${INCURSION_PRESSURE_BASELINE:?oracle: INCURSION_PRESSURE_BASELINE is unset}"
BASE_SHA="$INCURSION_PRESSURE_BASE_SHA"
BASELINE="$INCURSION_PRESSURE_BASELINE"
OUT="${INCURSION_PRESSURE_VALUES_OUT:-}"
OWN_OUT=0
if [ -z "$OUT" ]; then OUT="$(mktemp -d "${TMPDIR:-/tmp}/incursion-oracle.XXXXXX")"; OWN_OUT=1; fi
mkdir -p "$OUT" || exit 2
[ "$OWN_OUT" = 1 ] && trap 'rm -rf "$OUT"' EXIT
WORK="$(pwd -P)"

FAIL=0; UNM=0
say() { echo "oracle: $1 $2${3:+ -- $3}"; }
note() { # <step> <rc> [detail]
    case "$2" in
        0) say "$1" PASS "${3:-}";;
        2) say "$1" UNMEASURED "${3:-}"; UNM=1;;
        *) say "$1" FAIL "${3:-}"; FAIL=1;;
    esac
}
tailn() { grep -v '^KNOWN' "$1" | tail -"${2:-8}" | sed 's/^/    /'; }

# 1. build. A SOURCE landing (route.sh sets INCURSION_PRESSURE_LANDING=source: a side landing whose save is not
# scored) runs the source checks only. A full landing builds; where the C++ sources are byte-identical to a tree this
# suite already built (tools/pressure/srchash.sh names them), the cached binary is put in place and only the module is
# recompiled from lib/ (build_macos.sh, INCURSION_MODULE_ONLY=1: the same data step a full build runs).
LANDING="${INCURSION_PRESSURE_LANDING:-full}"
BINCACHE="${INCURSION_PRESSURE_BINCACHE:-}"
if [ "$LANDING" = source ]; then
    echo "oracle: build SKIPPED -- source landing: a side landing whose save is not scored runs the source checks only"
else
    blog="$OUT/build.log"; mode=full; hash=""
    if [ -n "$BINCACHE" ]; then
        hash="$("$HERE/srchash.sh" "$WORK")" || hash=""
        if [ -n "$hash" ] && [ -x "$BINCACHE/$hash/incursion-headless" ]; then
            cp -f "$BINCACHE/$hash/incursion-headless" "$WORK/incursion-headless" && mode=module
        fi
    fi
    t_build=$SECONDS
    if [ "$mode" = module ]; then
        INCURSION_MODULE_ONLY=1 BACKEND=posix ./build_macos.sh > "$blog" 2>&1; rc=$?
    else
        BACKEND=posix ./build_macos.sh > "$blog" 2>&1; rc=$?
    fi
    if [ $rc -ne 0 ]; then
        note build 1 "exit $rc"; tailn "$blog" 20
        echo FAIL > "$OUT/verdict"; echo "oracle: FAIL"; exit 1
    fi
    if [ "$mode" = module ]; then
        note build 0 "reused the binary of the identical C++ tree $hash, recompiled the module from lib/ ($((SECONDS - t_build))s)"
    else
        note build 0 "full build ($((SECONDS - t_build))s)${hash:+, C++ tree $hash}"
        if [ -n "$hash" ] && [ -x "$WORK/incursion-headless" ]; then
            mkdir -p "$BINCACHE/$hash.tmp" && cp -f "$WORK/incursion-headless" "$BINCACHE/$hash.tmp/" \
                && rm -rf "$BINCACHE/$hash" && mv "$BINCACHE/$hash.tmp" "$BINCACHE/$hash"
        fi
    fi
    grep -q 'WARNING.*could not measure' "$blog" && { note build-prechecks 2 "a build precheck could not measure"; tailn "$blog" 4; }
fi

run_step() { # <name> <cmd...>
    local name="$1" log="$OUT/$1.log" rc; shift
    "$@" > "$log" 2>&1; rc=$?
    note "$name" "$rc" "$([ $rc -ne 0 ] && echo "exit $rc")"
    [ $rc -ne 0 ] && tailn "$log" 12
    return 0
}
run_step defdups python3 tools/check_define_dups.py
run_step stored python3 tools/check_stored_values.py --base "$BASE_SHA"
run_step savenames python3 tools/check_save_names.py
if [ "$LANDING" = source ]; then
    # check_field_names.sh runs incursion-headless -schematest, so it needs the build a source landing does not make
    echo "oracle: fieldnames SKIPPED -- it runs the built binary; a source landing builds none"
else
    run_step fieldnames tools/check_field_names.sh
fi

if [ "$LANDING" = source ]; then
    echo "oracle: compat, plant, content, witness SKIPPED -- source landing"
    [ -n "${INCURSION_PRESSURE_PLANT:-}" ] && echo "oracle: plant SKIPPED -- the case plants nothing on a source landing (an epic save is not scored)"
else
# 2. back-compat load of every fixture
mkdir -p "$OUT/values"
n=0; bad=0; unm=0
for s in "$WORK"/tools/fixtures/chars/*.sav; do
    b="$(basename "$s" .sav)"
    if [ ! -f "$BASELINE/$b.txt" ]; then
        unm=$((unm + 1)); echo "    no baseline for $b" ; continue
    fi
    if ! "$HERE/field_values.sh" "$WORK" "$s" "$OUT/values/$b.txt" 2> "$OUT/values/$b.err"; then
        # An engine refusal that names the space the case expects is a refusal, not a failure to measure
        # (owner ruling: a correct refusal that names the space is PASS). Only the first two are printed.
        if [ -n "${INCURSION_PRESSURE_REFUSAL_RE:-}" ] && grep -qE "$INCURSION_PRESSURE_REFUSAL_RE" "$OUT/values/$b.err"; then
            bad=$((bad + 1)); n=$((n + 1))
            [ $bad -le 2 ] && echo "    $b: the engine refused the load: $(grep -m1 -E "$INCURSION_PRESSURE_REFUSAL_RE" "$OUT/values/$b.err" | cut -c1-220)"
            continue
        fi
        unm=$((unm + 1)); echo "    could not load $b in the landed tree: $(head -c 200 "$OUT/values/$b.err")"; continue
    fi
    rm -f "$OUT/values/$b.err"
    "$HERE/compare_values.py" "$BASELINE/$b.txt" "$OUT/values/$b.txt" > "$OUT/values/$b.cmp" 2>&1; crc=$?
    n=$((n + 1))
    if [ $crc -eq 1 ]; then
        bad=$((bad + 1)); echo "    $b:"; grep -E '^(changed|missing)' "$OUT/values/$b.cmp" | head -5 | sed 's/^/      /'
    elif [ $crc -ne 0 ]; then
        unm=$((unm + 1)); echo "    $b: compare could not measure: $(head -c 200 "$OUT/values/$b.cmp")"
    fi
done
if [ $bad -gt 0 ]; then note compat 1 "$bad of $n fixtures changed or lost a value"
elif [ $unm -gt 0 ] || [ $n -eq 0 ]; then note compat 2 "$unm fixtures could not be measured, $n compared"
else note compat 0 "$n of $n fixtures load with every baseline value kept"; fi
# the after-values become the next baseline only when every fixture was measured
[ $unm -gt 0 ] && rm -f "$OUT/values/.complete" || : > "$OUT/values/.complete"

# 2b. the case's content: plant it, and load what earlier landings planted
planted_lines() { # <fixture-values> <content-values>: the lines the planting added or changed
    [ -f "$1" ] || return 0
    "$HERE/compare_values.py" --planted "$1" "$2" 2>&1 | sed 's/^/      /'
}
if [ -n "${INCURSION_PRESSURE_PLANT:-}" ]; then
    ptag="${INCURSION_PRESSURE_PLANT_TAG:?oracle: INCURSION_PRESSURE_PLANT_TAG is unset}"
    pfx="${INCURSION_PRESSURE_PLANT_FIXTURE:?oracle: INCURSION_PRESSURE_PLANT_FIXTURE is unset}"
    mkdir -p "$OUT/content-new"
    "$HERE/plant.sh" "$WORK" "$WORK/tools/fixtures/chars/$pfx.sav" "$INCURSION_PRESSURE_PLANT" \
        "$OUT/content-new/$ptag.sav" "$OUT/content-new/$ptag.txt" > "$OUT/plant.log" 2>&1; prc=$?
    if [ $prc -eq 0 ]; then
        echo "$pfx" > "$OUT/content-new/$ptag.fixture"
        [ "${INCURSION_PRESSURE_PLANT_SCORED:-0}" = 1 ] && : > "$OUT/content-new/$ptag.scored"
        note plant 0 "planted $(basename "$INCURSION_PRESSURE_PLANT") in $pfx; the new save holds it"
        planted_lines "$OUT/values/$pfx.txt" "$OUT/content-new/$ptag.txt"
    elif [ -n "${INCURSION_PRESSURE_REFUSAL_RE:-}" ] && grep -qE "$INCURSION_PRESSURE_REFUSAL_RE" "$OUT/plant.log"; then
        # the writer or reader refused while planting, and the line names the space the case expects: a refusal
        note plant 1 "the engine refused the plant: $(grep -m1 -E "$INCURSION_PRESSURE_REFUSAL_RE" "$OUT/plant.log" | cut -c1-220)"
    else
        note plant "$prc" "$(head -c 300 "$OUT/plant.log")"
    fi
fi
if [ -n "${INCURSION_PRESSURE_CONTENT:-}" ] && ls "$INCURSION_PRESSURE_CONTENT"/*.sav > /dev/null 2>&1; then
    "$HERE/content_check.sh" "$WORK" "$INCURSION_PRESSURE_CONTENT" "$OUT/content-values" "$OUT/values" > "$OUT/content.log" 2>&1; crc=$?
    grep -v '^content: ' "$OUT/content.log"
    note content "$crc" "$(grep '^content: ' "$OUT/content.log" | tail -1 | sed 's/^content: [A-Z]* -- //')"
fi

# 3. the case's own witness
if [ -n "${INCURSION_PRESSURE_WITNESS:-}" ]; then
    wlog="$OUT/witness.log"
    bash "$INCURSION_PRESSURE_WITNESS" "$WORK" "$OUT" > "$wlog" 2>&1; rc=$?
    note witness "$rc" "$(tail -1 "$wlog")"
    [ $rc -ne 0 ] && tailn "$wlog" 10
fi
fi

if [ $FAIL -ne 0 ]; then echo FAIL > "$OUT/verdict"; echo "oracle: FAIL"; exit 1; fi
if [ $UNM -ne 0 ]; then echo UNMEASURED > "$OUT/verdict"; echo "oracle: UNMEASURED"; exit 2; fi
echo PASS > "$OUT/verdict"; echo "oracle: PASS"
exit 0
