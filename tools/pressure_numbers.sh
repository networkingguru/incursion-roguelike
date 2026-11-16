#!/bin/bash
# gate: none builds a scratch repository per case and route and lands real beads in it; minutes per run, run by hand
# fact: the cases -- tools/pressure/cases/<case>/ (A.patch, B.patch, optional P.patch and witness.sh, expect, routes); each applies to the snapshot P of this working tree
# fact: the routes -- tools/pressure/route.sh, real tools/worktree.sh and tools/finish_bead.sh in a scratch repository under logs/phase8/d2/runs/; the case oracle replaces only the landing gate
# fact: fixtures -- tools/fixtures/chars/*.sav, frozen bytes; no seed, no key script
#
# AC8 pressure numbers (inc-cjos0 phase 8, D2): each case through each of its routes, one line per run.
#
#   tools/pressure_numbers.sh [--keep] [case[:route] ...]   default: every case under tools/pressure/cases/
#                                                    `S01:M` runs that one route of the case
#
# For each case and each route in the case's `routes` file it makes a fresh scratch repository under
# logs/phase8/d2/runs/<case>/<route>/ (an existing run directory is replaced), applies the case, runs
# tools/pressure/route.sh, and prints
#   AC8 <case> route=<R> result=<PASS|FAIL|UNMEASURED> <reason>
# PASS: `expect works` and the case oracle passed on every landing with the destination advanced, or
# `expect refuse <re>` and a step refused with a line matching <re> while the destination did not advance.
# FAIL: everything else that ran. UNMEASURED: a step exited 2, the oracle could not measure, or git conflicted.
# Wall time per case is printed, and logs/phase8/d2/results.md is rewritten from every run directory. A finished run keeps its log/, steps.tsv and
# route.out; --keep also keeps the repository, worktrees and value files (about 1.2 GB a run).
#
# Exit: 0 every run PASS, 1 a run FAIL, 2 no run FAIL but one UNMEASURED.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
D2="$ROOT/logs/phase8/d2"
CASES="$ROOT/tools/pressure/cases"
unset INCURSIONPATH INCURSION_LOAD INCURSION_OPTIONS INCURSION_RUN_DIR
mkdir -p "$D2/runs" || exit 2
rm -rf "$D2/baseline-cache"   # the shared baseline of P lives for this invocation only (routes of a case share it)
rm -rf "$D2/bin-cache"        # so do the binaries of built C++ trees (tools/pressure/srchash.sh): reused only within this invocation

names=(); KEEP=0
for a in "$@"; do
    if [ "$a" = --keep ]; then KEEP=1; else names+=("$a"); fi
done
if [ ${#names[@]} -eq 0 ]; then
    for d in "$CASES"/*/; do [ -f "$d/routes" ] && names+=("$(basename "$d")"); done
fi
[ ${#names[@]} -gt 0 ] || { echo "pressure_numbers: no cases" >&2; exit 2; }

worst=0
for c in "${names[@]}"; do
    only=""
    case "$c" in *:*) only="${c#*:}"; c="${c%%:*}";; esac
    cdir="$CASES/$c"
    [ -f "$cdir/routes" ] || { echo "pressure_numbers: no case $c" >&2; worst=2; continue; }
    t_case=$SECONDS
    for r in $(cat "$cdir/routes"); do
        [ -z "$only" ] || [ "$only" = "$r" ] || continue
        run="$D2/runs/$c/$r"
        case "$run" in "$D2/runs/"?*/?*) ;; *) echo "pressure_numbers: bad run path $run" >&2; exit 2;; esac
        rm -rf "$run"
        mkdir -p "$run" || exit 2
        t_run=$SECONDS
        pp=""; [ -f "$cdir/P.patch" ] && pp="$cdir/P.patch"
        if ! "$ROOT/tools/pressure/scratch.sh" make "$run/repo" $pp > "$run/make.log" 2>&1; then
            res="AC8 $c route=$r result=UNMEASURED the scratch repository could not be made (see $run/make.log)"
        else
            "$ROOT/tools/pressure/route.sh" "$run/repo" "$r" "$cdir" > "$run/route.out" 2>&1
            v="$(grep '^VERDICT ' "$run/route.out" | tail -1)"
            if [ -z "$v" ]; then
                res="AC8 $c route=$r result=UNMEASURED the route printed no verdict (see $run/route.out)"
            else
                v="${v#VERDICT }"
                res="AC8 $c route=$r result=${v%% *} ${v#* }"
            fi
        fi
        res="$res [$((SECONDS - t_run))s]"
        # a run leaves its logs, steps.tsv and fake beads; the repository, its worktrees and the value files
        # (about 1.2 GB a run) go unless --keep
        if [ "$KEEP" = 0 ]; then
            rm -rf "$run/repo" "$run"/Incursion-* "$run/pressure-state/tmp" "$run/pressure-state/values" \
                "$run"/pressure-state/baseline-*
        fi
        echo "$res"
        printf '%s\n' "$res" > "$run/result.line"
        case "$res" in *"result=FAIL"*) [ $worst -lt 1 ] && worst=1;; *"result=UNMEASURED"*) [ $worst -eq 0 ] && worst=2;; esac
    done
    echo "pressure_numbers: case $c took $((SECONDS - t_case))s"
done

# results.md from every run directory
{
    echo "# AC8 pressure results (tools/pressure_numbers.sh)"
    echo
    echo "| case | route | result | reason | seconds |"
    echo "|---|---|---|---|---|"
    for f in "$D2"/runs/*/*/result.line; do
        [ -f "$f" ] || continue
        l="$(cat "$f")"
        c="$(printf '%s' "$l" | sed -n 's/^AC8 \([^ ]*\) route=.*/\1/p')"
        r="$(printf '%s' "$l" | sed -n 's/^AC8 [^ ]* route=\([^ ]*\) .*/\1/p')"
        res="$(printf '%s' "$l" | sed -n 's/.* result=\([A-Z]*\) .*/\1/p')"
        why="$(printf '%s' "$l" | sed -n 's/.* result=[A-Z]* \(.*\) \[[0-9]*s\]$/\1/p' | sed 's/|/\\|/g')"
        secs="$(printf '%s' "$l" | sed -n 's/.*\[\([0-9]*\)s\]$/\1/p')"
        echo "| $c | $r | $res | $why | $secs |"
    done
} > "$D2/results.md"
rm -rf "$D2/baseline-cache"
echo "pressure_numbers: wrote $D2/results.md"
exit "$worst"
