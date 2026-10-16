#!/bin/bash
# gate: live
# inc-dp5u: a template's CR bonus must add to the creature's CR without a floor
# at zero. MVal::Adjust (inc/Base.h) computes max(0, oval + Value) for MVAL_ADD,
# so a negative base CR is lifted to 0 before the next template adds, and the
# result depends on the order the templates are applied.
#
# Case "pair": a myconid (base CR -2, lib/mon2.irh) takes "skilled" (CR +1) and
# "experienced" (CR +2), once in each order, through wizard mode "Add Template
# to Creature". Neither template has a Min bound. The right CR is -2+1+2 = 1 in
# both orders. Current code reads 2 when skilled is applied first (max(0,-1)=0,
# then +2) and 1 the other way.
# Case "single" (one template smaller than the negative base) CANNOT be read
# here: Creature::ChallengeRating() returns max(0,CR) when allow_neg is false,
# and the sidebar of the wizard dump uses that, so -1 and 0 both print 0. Only
# a caller with allow_neg=true would show it; no wizard screen has one.
#
# The oracle is the "CR:" field of Creature::Dump, shown by wizard mode
# "Examine Nearby Things" (src/Debug.cpp). The key script is
# tools/keys/template-cr-clamp.keys.
# Build: BACKEND=posix ./build_macos.sh
# Run: tools/check_template_cr_clamp.sh   (0 pass, 1 fail, 2 inconclusive)
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

[ -x ./incursion-headless ] || {
    echo "INCONCLUSIVE: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 2
}
out="$(INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat \
       tools/headless.sh tools/keys/template-cr-clamp.keys 1 2>&1)"
hstatus=$?
run="$(echo "$out" | awk '/^run:/ {print $2}')"
S="$run/logs/screens"
if [ "$hstatus" -ne 0 ] || grep -qE 'NO GAMEPLAY|gave up|failed' <<< "$out"; then
    echo "INCONCLUSIVE: the session did not complete its measurement (harness exit $hstatus)."
    echo "$out" | tail -15
    exit 2
fi

fail=0
for pair in skilled-experienced experienced-skilled; do
    f="$S/"*"-$pair.txt"
    line="$(grep -h 'CR:' $f 2>/dev/null | head -1)"
    cr="$(echo "$line" | sed -n 's/.*CR:\(-\{0,1\}[0-9]*\).*/\1/p')"
    if ! grep -q 'class T_MONSTER' $f 2>/dev/null || [ -z "$cr" ]; then
        echo "INCONCLUSIVE: no monster CR read for $pair in $S"
        exit 2
    fi
    if [ "$cr" -eq 1 ]; then
        echo "PASS: $pair CR $cr (want 1 = -2 + 1 + 2)"
    else
        echo "FAIL: $pair CR $cr, want 1 = -2 + 1 + 2.  Sheet line: $(echo "$line" | sed 's/ *|.*//')"
        fail=1
    fi
done
exit "$fail"
