#!/usr/bin/env bash
# Reproduction for bead inc-a6meq: a scratch-tree check cannot load a pinned fixture.
# tools/check_quality_growth.sh runs headless from a scratch copy of the tree. Under
# INCURSION_FIXTURE_PIN the copy's empty cache cannot serve the pinned entry, so the
# check exits 2. Exit 0 = fixed (pinned entry served, nothing built); exit 1 = defect.
# fact: the fixture -- orc-barbarian-seed1-opt0822, the one tools/check_quality_growth.sh loads; its key is read from tools/fixture_cache.sh, not assumed
# fact: the pin -- written here from that key, so it matches the cache entry by construction
# fact: the cache entry set and fixture-builds.tsv line count -- read before and after the check, compared
# fact: the seed -- not read; this script only compares cache state and the check's exit code
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2
[ -x "$ROOT/incursion-headless" ] || { echo "repro: no incursion-headless here; run BACKEND=posix ./build_macos.sh"; exit 2; }
NAME=orc-barbarian-seed1-opt0822
KEYFILE="$(env -u INCURSION_FIXTURE_PIN -u INCURSION_FIXTURE_CACHE tools/fixture_cache.sh "$NAME")" \
    || { echo "repro: fixture_cache.sh could not serve $NAME"; exit 2; }
KEY="$(basename "$(dirname "$KEYFILE")")"
mkdir -p logs
PIN="$(mktemp "$ROOT/logs/repro-a6meq-pin.XXXXXX")"
trap 'rm -f "$PIN"' EXIT
printf '%s\t%s\n' "$NAME" "$KEY" > "$PIN"
CACHE="$ROOT/logs/fixture-cache"
before="$(ls "$CACHE" | sort)"
blines_before="$(wc -l < logs/fixture-builds.tsv 2>/dev/null || echo 0)"
INCURSION_FIXTURE_PIN="$PIN" tools/check_quality_growth.sh > "$PIN.out" 2>&1
rc=$?
tail -3 "$PIN.out"; rm -f "$PIN.out"
after="$(ls "$CACHE" | sort)"
blines_after="$(wc -l < logs/fixture-builds.tsv 2>/dev/null || echo 0)"
echo "pinned key: $KEY"
echo "check exit code: $rc"
bad=0
[ "$rc" -eq 2 ] && { echo "DEFECT: the check exited 2 (UNMEASURED) under a pin"; bad=1; }
[ "$before" = "$after" ] || { echo "DEFECT: the cache entry list changed"; bad=1; }
[ "$blines_before" = "$blines_after" ] || { echo "DEFECT: fixture-builds.tsv grew ($blines_before -> $blines_after)"; bad=1; }
[ "$bad" -eq 0 ] && echo "OK: the pinned entry served, nothing built"
exit "$bad"
