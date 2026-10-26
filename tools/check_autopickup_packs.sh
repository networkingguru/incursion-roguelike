#!/bin/bash
# gate: live
# inc-4reo: AutoPickupFloor must search unlocked containers held in slots.
# fact: character and abilities -- fixture orc-rogue-seed1-opt0822.sav
# fact: options -- options-2026-08-22.dat; probe sets AUTOPICKUP=2, AUTOMORE=1
# fact: terrain and absence of threats -- probe builds cleared floor scene (RUNTO_STAGE pattern)
# fact: items, quantities, identification, slots, nesting and locks -- probe Item::Create/MakeMagical and forced Insert (Item Acquisition equivalents)
# fact: refusal/acceptance -- probe verifies FitsNormal against fixture's packrat feat; size in e, weight in f
# fact: matching stacks and eligible magic -- probe verifies equality and AutoPickupFloor prerequisites before call
# fact: result text -- probe emits literal labels and measured parent/quantity; no generated names or rolls
# Builds nothing. Each case uses a fresh fixture and private run directory.
set -uo pipefail
export LC_ALL=C
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
base="$ROOT/logs/runs/$(date +%Y%m%d-%H%M%S)-$$-autopickup-packs"
mkdir -p "$base"
failed=0
for c in a b c d e f g; do
    run="$base/$c"
    INCURSION_AUTOPICKUP_PACKS_PROBE="$c" INCURSION_RUN_DIR="$run" \
        INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat \
        INCURSION_LOAD=tools/fixtures/chars/orc-rogue-seed1-opt0822.sav \
        tools/headless.sh tools/keys/autopickup-packs.keys 1 > "$base/$c-harness.log" 2>&1
    rc=$?
    log="$run/logs/autopickup-packs.log"
    if [ "$rc" != 0 ] || [ ! -f "$log" ] || ! grep -qx COMPLETE "$log"; then
        echo "FAIL case=$c: probe/harness incomplete (exit $rc); specimen $log; harness $base/$c-harness.log"
        failed=1; continue
    fi
    res=$(grep '^RESULT ' "$log")
    case "$c" in
        a) want='where=bagB stackA=0 stackB=4 stackC=0 floor=0' ;;
        b|c) want='where=floor stackA=0 stackB=3 stackC=0 floor=1' ;;
        d) want='where=bagA stackA=4 stackB=0 stackC=0 floor=0' ;;
        e) want='where=bagC stackA=0 stackB=3 stackC=4 floor=0' ;;
        f) want='where=bagB stackA=0 stackB=0 stackC=0 floor=0' ;;
        g) want='where=bagA stackA=0 stackB=0 stackC=0 floor=0' ;;
    esac
    if [ "$res" = "RESULT $want" ]; then
        echo "PASS case=$c: $res; specimen $log"
    else
        echo "FAIL case=$c: $res (want $want); specimen $log"
        failed=1
    fi
done
exit "$failed"
