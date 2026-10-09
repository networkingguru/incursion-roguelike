#!/bin/bash
# gate: cheap
# gate-fast: static, reads lib files only, under 1 s
# inc-ac0l: a script passes int32 handles, never C++ pointers. A format tag that
# reads a pointer (<Str>, <Obj>, <Mon>, <Itm>, or a :obj/:mon/:itm suffix inside
# a tag) makes the engine dereference a handle and crash. Scripts must use the
# handle-safe tags (<hObj>, <hText>, ...). Lines inside #if 0 blocks are skipped.
#
# Usage: tools/check_script_formats.sh [libdir]     (default: lib/)
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LIB="${1:-$ROOT/lib}"
[ -d "$LIB" ] || { echo "FAIL: no such directory: $LIB"; exit 1; }
n=0
for f in "$LIB"/*.irh "$LIB"/*.irc; do
    [ -f "$f" ] || continue
    n=$((n+1))
    awk -v F="$(basename "$f")" '
        /^[ \t]*#[ \t]*if[ \t]+0/ { depth = 1; next }
        depth > 0 && /^[ \t]*#[ \t]*if/ { depth++; next }
        depth > 0 && /^[ \t]*#[ \t]*endif/ { depth--; next }
        depth > 0 { next }
        { l = tolower($0) }
        l ~ /<(str|obj|mon|itm)/ || l ~ /<[^<>]*:(obj|mon|itm)/ { print F ":" FNR ": " $0; bad = 1 }
        END { exit bad }' "$f" || fail=1
done
[ "$n" -gt 0 ] || { echo "FAIL: no lib/*.irh or *.irc files in $LIB"; exit 1; }
if [ "${fail:-0}" -eq 1 ]; then
    echo "FAIL: pointer-reading format tag in a script (use the <h...> tags)"
    exit 1
fi
echo "PASS no pointer-reading format tag in $n lib files"
