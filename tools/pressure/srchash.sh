#!/bin/bash
# The hash of every input of the C++ compile of a tree: src/, inc/, compat/, build_macos.sh, lib/dispatch.h (included
# by src/VMachine.cpp) and the two generators build_macos.sh runs. Two trees with one hash build the same binary
# (inc-cjos0 phase 8, D5); lib/*.irh and the rest are the module, which tools/pressure/oracle.sh recompiles.
#
#   tools/pressure/srchash.sh <tree>      prints the hash; exit 2 and prints nothing when it cannot hash every input
#   tools/pressure/srchash.sh --selftest  shows each failure path exits 2, and the hash tracks content
#
# fact: the tree's files -- read from <tree> as they are on disk; no seed, no options file, no clock
set -uo pipefail
SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"

hash_tree() {   # prints the hash, or nothing and returns 2
    local tree="$1" tmp list f h
    [ -d "$tree/src" ] || return 2
    tmp="$(mktemp -d "${TMPDIR:-/tmp}/srchash.XXXXXX")" || return 2
    list="$tmp/list"
    if ! ( cd "$tree" && git ls-files -co --exclude-standard -z -- src inc compat build_macos.sh lib/dispatch.h \
            tools/gen_record_layout.py tools/gen_family_names.py ) > "$list" 2>/dev/null; then
        rm -rf "$tmp"; return 2
    fi
    [ -s "$list" ] || { rm -rf "$tmp"; return 2; }
    # every listed file must be readable, or the hash would skip it
    while IFS= read -r -d '' f; do
        [ -f "$tree/$f" ] && [ -r "$tree/$f" ] || { rm -rf "$tmp"; return 2; }
    done < "$list"
    if ! ( cd "$tree" && xargs -0 shasum < "$list" ) > "$tmp/sums" 2>/dev/null || [ ! -s "$tmp/sums" ]; then
        rm -rf "$tmp"; return 2
    fi
    h="$(shasum < "$tmp/sums" | cut -c1-16)"
    rm -rf "$tmp"
    [ ${#h} -eq 16 ] || return 2
    echo "$h"
}

selftest() {
    local d out rc fail=0 a b
    d="$(mktemp -d "${TMPDIR:-/tmp}/srchash-self.XXXXXX")" || exit 2
    mk() {  # mk <dir>: a git tree with the two kinds of input
        mkdir -p "$1/src" && git -C "$1" init -q && echo 'int a;' > "$1/src/a.cpp" && echo x > "$1/build_macos.sh"
    }
    expect2() {  # expect2 <label> <tree>
        out="$("$SELF" "$2" 2>/dev/null)"; rc=$?
        if [ "$rc" -eq 2 ] && [ -z "$out" ]; then echo "PASS $1: exit 2, no output"
        else echo "FAIL $1: rc=$rc out=[$out]"; fail=1; fi
    }
    mkdir -p "$d/notgit/src"; echo 'int a;' > "$d/notgit/src/a.cpp"
    expect2 "git ls-files fails (not a repo)" "$d/notgit"
    mkdir -p "$d/empty/src"; git -C "$d/empty" init -q
    expect2 "empty file list" "$d/empty"
    mk "$d/unread"; chmod 000 "$d/unread/src/a.cpp"
    expect2 "listed file unreadable" "$d/unread"; chmod 644 "$d/unread/src/a.cpp"
    mk "$d/gone"; git -C "$d/gone" add src/a.cpp; rm "$d/gone/src/a.cpp"
    expect2 "listed file missing" "$d/gone"
    mkdir -p "$d/bin"; printf '#!/bin/sh\nexit 1\n' > "$d/bin/shasum"; chmod +x "$d/bin/shasum"
    mk "$d/hashfail"
    out="$(PATH="$d/bin:$PATH" "$SELF" "$d/hashfail" 2>/dev/null)"; rc=$?
    if [ "$rc" -eq 2 ] && [ -z "$out" ]; then echo "PASS hash step fails: exit 2, no output"
    else echo "FAIL hash step fails: rc=$rc out=[$out]"; fail=1; fi
    expect2 "no src dir" "$d/nonexistent"
    mk "$d/t1"; mk "$d/t2"
    a="$("$SELF" "$d/t1")"; b="$("$SELF" "$d/t2")"
    if [ -n "$a" ] && [ "$a" = "$b" ]; then echo "PASS identical trees give one hash ($a)"; else echo "FAIL identical trees: [$a] [$b]"; fail=1; fi
    echo 'int b;' > "$d/t2/src/a.cpp"
    b="$("$SELF" "$d/t2")"
    if [ -n "$b" ] && [ "$a" != "$b" ]; then echo "PASS one-byte change gives another hash ($b)"; else echo "FAIL change: [$a] [$b]"; fail=1; fi
    rm -rf "$d"
    exit "$fail"
}

[ "${1:-}" = "--selftest" ] && selftest
[ $# -eq 1 ] || { echo "usage: $0 <tree> | --selftest" >&2; exit 2; }
out="$(hash_tree "$1")" || exit 2
[ -n "$out" ] || exit 2
echo "$out"
