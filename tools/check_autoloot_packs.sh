#!/bin/bash
# gate: live
# inc-f99j: does AutoLoot try every container held in an inventory slot?
# Opt-in AutoLootPacksProbe (src/AutoLootPacksProbe.cpp) runs the macro on a
# long sword with: a) full pack-slot bag + a second bag in a belt slot, b) a
# locked bag before an open bag, c) a bag nested inside the pack-slot bag,
# d) every candidate too small. Builds nothing; needs incursion-headless.
set -uo pipefail
export LC_ALL=C
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
base="$ROOT/logs/runs/$(date +%Y%m%d-%H%M%S)-$$-autoloot-packs"
mkdir -p "$base"
failed=0
for c in a b c d; do
    run="$base/$c"
    INCURSION_AUTOLOOT_PACKS_PROBE="$c" INCURSION_RUN_DIR="$run" \
        INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat \
        INCURSION_LOAD=tools/fixtures/chars/orc-rogue-seed1-opt0822.sav \
        tools/headless.sh tools/keys/autoloot-packs.keys 1 > "$base/$c-harness.log" 2>&1
    rc=$?
    log="$run/logs/autoloot-packs.log"
    if [ ! -f "$log" ] || ! grep -q '^COMPLETE' "$log"; then
        echo "FAIL case=$c: probe did not complete (harness exit $rc, $base/$c-harness.log)"
        failed=1; continue
    fi
    res=$(grep '^RESULT ' "$log")
    case "$c" in
        a) want="where=bagB taken=1 toolarge=0 canonlyhold=0 locked=0" ;;
        b) want="where=bagC taken=1 toolarge=0 canonlyhold=0 locked=0" ;;
        c) want="NOT where=bagB" ;;
        d) want="toolarge=1, item in neither bag" ;;
    esac
    ok=1
    case "$c" in
        a|b) [ "$res" = "RESULT $want" ] || ok=0 ;;
        c) case "$res" in *where=bagB*) ok=0 ;; esac
           case "$res" in *where=bagA*) ok=0 ;; esac ;;
        d) case "$res" in *toolarge=1*) ;; *) ok=0 ;; esac
           case "$res" in *where=bagA*|*where=bagB*) ok=0 ;; esac ;;
    esac
    if [ "$ok" = 1 ]; then echo "PASS case=$c: $res"
    else echo "FAIL case=$c: $res (want $want) specimen $log"; failed=1; fi
done
exit "$failed"
