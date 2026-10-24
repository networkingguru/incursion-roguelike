#!/bin/bash
# gate: cheap
# gate-fast: static, reads lib/*.irh and src/Feature.cpp only, under 1 s
# inc-w91w: Trap::RemoteEffect (src/Feature.cpp) holds a hard-coded table of
# trap -> redirected spell. When a found trap is attacked, the trap's own
# script RedirectEffs that spell and the spell does the work; if a trap's
# redirect is missing from the table the remote attack silently uses the
# trap's own effect instead. This check cross-references every "AI_TRAP Effect"
# in lib/*.irh whose script calls RedirectEff(e,$"<spell>",EV_EFFECT) against
# that table. It fails on any missing pair and fails when it finds no pairs at
# all, so it cannot pass by parsing nothing.
#
# Usage: tools/check_trap_redirect_table.sh [root]   (default: repo root)
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="${1:-$ROOT}"
LIB="$ROOT/lib"
SRC="$ROOT/src/Feature.cpp"
[ -d "$LIB" ] || { echo "FAIL: no such directory: $LIB"; exit 1; }
[ -f "$SRC" ] || { echo "FAIL: no such file: $SRC"; exit 1; }

pairs="$(awk '
    function count(s, c,   i, k) { k = 0; for (i = 1; i <= length(s); i++) if (substr(s,i,1) == c) k++; return k }
    FNR == 1 { trap = ""; depth = 0 }
    /^[ \t]*#[ \t]*if[ \t]+0/ { disabled = 1; next }
    disabled && /^[ \t]*#[ \t]*if/ { next }
    disabled && /^[ \t]*#[ \t]*endif/ { disabled = 0; next }
    disabled { next }
    /AI_TRAP[ \t]+Effect[ \t]+"/ {
        line = $0
        sub(/^.*AI_TRAP[ \t]+Effect[ \t]+"/, "", line)
        sub(/".*$/, "", line)
        trap = line
        depth = count($0, "{") - count($0, "}")
        next
    }
    trap != "" {
        if (depth > 0 && /RedirectEff[ \t]*\([ \t]*e[ \t]*,[ \t]*\$"/ && /EV_EFFECT/) {
            line = $0
            sub(/^.*RedirectEff[ \t]*\([ \t]*e[ \t]*,[ \t]*\$"/, "", line)
            sub(/".*$/, "", line)
            print trap "\t" line
        }
        depth += count($0, "{") - count($0, "}")
        if (depth <= 0) trap = ""
    }
' "$LIB"/*.irh | sort -u)"

npairs="$(printf '%s\n' "$pairs" | grep -c $'\t' || true)"
if [ "$npairs" -eq 0 ]; then
    echo "FAIL: found no AI_TRAP RedirectEff(...,EV_EFFECT) pair in $LIB/*.irh (check parsing?)"
    exit 1
fi

missing=0
while IFS=$'\t' read -r trap spell; do
    [ -n "$trap" ] || continue
    if ! grep -qF "{\"$trap\", \"$spell\"}" "$SRC"; then
        echo "MISSING: (\"$trap\", \"$spell\") absent from Trap::RemoteEffect"
        missing=1
    fi
done <<< "$pairs"

if [ "$missing" -ne 0 ]; then
    echo "FAIL: Trap::RemoteEffect is missing $npairs-pair table rows above"
    exit 1
fi
echo "PASS: all $npairs AI_TRAP -> RedirectEff(EV_EFFECT) pairs are in Trap::RemoteEffect"
