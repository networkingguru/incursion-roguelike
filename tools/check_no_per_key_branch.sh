#!/usr/bin/env bash
# gate: cheap --selftest
#
# Does the .char parser, the File creation source, the recorder or the builder
# script branch on ONE decision key?
#
# WHAT IS BEING PROVED. Spec amendment B18 (docs/specs/2026-11-06-fixture-
# builder-spec.md): a new decision kind must arrive as a small mechanical step,
# not a redesign. That holds only while the code that reads and writes the
# `.char` file is data driven: the key name is looked up in the X-macro table
# (inc/CreationSource.h), the context text is the exact text the recorder
# writes, and the value is read by the key's KIND (ROLL, PICK, ITEM). A line of
# code that tests for one key by name is a special case the next decision
# would have to learn about.
#
# THE FILES. src/CharFile.cpp (the parser and the File backend), src/Creation
# Source.cpp (the recorder and its serializers), tools/build_fixture.sh and
# tools/check_fixture_equivalence.sh (C2, whose coverage list reads the enum).
#
# WHAT IT FLAGS (a code line: comments and blank lines are set aside first):
#   R1  `case CK_<NAME>` -- a switch arm on a key.
#   R2  a comparison with a CK_ value: `==`, `!=`, `<=`, `>=`, `<` or `>` beside
#       CK_<NAME>. CK_COUNT is the table's end, not a key, and is allowed.
#   R3  a string literal that is exactly a key name as the .char file spells it
#       (lower case): "attr_str". (The data lines `options` and `seed` are not
#       keys. The upper-case PERK_ITEM and its kin are perk TYPE values the
#       Perk table names; they share a spelling with keys and are not tested.)
#   R4  `switch (k)`, `switch (key)` or `switch (<x>.key)` -- a switch over a key.
#   R5  in tools/build_fixture.sh and tools/check_fixture_equivalence.sh: a CK_ name, or a shell word that is exactly a
#       key name in a `case` arm or a string test.
#
# fact: the text of src/CharFile.cpp, src/CreationSource.cpp and tools/build_fixture.sh -- read from the working tree by grep and awk; no game run, no seed, no map
# fact: the key names -- read from the CREATION_KEY_LIST X-macro in inc/CreationSource.h by sed at run time, so a new key is covered the moment it is added
# fact: which patterns count as a branch -- R1 to R5 above, fixed in this file
#
# Usage: tools/check_no_per_key_branch.sh [--selftest]
#        --selftest copies the three files, inserts one branch of each rule into
#        a copy, and proves this script goes red on each copy (and green on the
#        untouched copies).
# Exit: 0 no per-key branch; 1 a branch is present; 2 could not measure.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

HDR="${NO_PER_KEY_HEADER:-inc/CreationSource.h}"
CHARFILE="${NO_PER_KEY_CHARFILE:-src/CharFile.cpp}"
RECORDER="${NO_PER_KEY_RECORDER:-src/CreationSource.cpp}"
BUILDER="${NO_PER_KEY_BUILDER:-tools/build_fixture.sh}"
EQUIV="${NO_PER_KEY_EQUIV:-tools/check_fixture_equivalence.sh}"

# The key names, upper case, one per line.
key_names() {
    sed -n 's/^[[:space:]]*X(\([A-Z0-9_]*\),.*/\1/p' "$HDR"
}

# Code lines of a C++ file: drop // and block-comment lines, number the rest.
code_lines() {
    awk '
        BEGIN { inblock = 0 }
        {
            line = $0
            if (inblock) { if (index(line, "*/")) { inblock = 0 } ; next }
            t = line; sub(/^[ \t]+/, "", t)
            if (t ~ /^\/\//) next
            if (t ~ /^\/\*/) { if (!index(t, "*/")) inblock = 1; next }
            if (t == "") next
            printf "%d:%s\n", NR, line
        }' "$1"
}

scan_cpp() {   # <file> -> prints hits, returns 1 when any
    local f="$1" bad=0 hits keys alt
    [ -f "$f" ] || { echo "INCONCLUSIVE: $f is not there"; return 2; }
    keys="$(key_names)"
    [ -n "$keys" ] || { echo "INCONCLUSIVE: no keys found in $HDR"; return 2; }
    alt="$(printf '%s\n' "$keys" | paste -sd'|' -)"
    local code
    code="$(code_lines "$f")"
    [ -n "$code" ] || { echo "INCONCLUSIVE: $f has no code lines"; return 2; }

    hits="$(printf '%s\n' "$code" | grep -E 'case[[:space:]]+CK_[A-Z0-9_]+')" || true
    [ -n "$hits" ] && { echo "R1 case on a key in $f:"; printf '%s\n' "$hits" | sed 's/^/  /'; bad=1; }

    hits="$(printf '%s\n' "$code" | grep -E '(==|!=|<=|>=|<|>)[[:space:]]*\(?CK_[A-Z0-9_]+|CK_[A-Z0-9_]+\)?[[:space:]]*(==|!=|<=|>=|<|>)' | grep -vE 'CK_COUNT')" || true
    [ -n "$hits" ] && { echo "R2 comparison with a key in $f:"; printf '%s\n' "$hits" | sed 's/^/  /'; bad=1; }

    lalt="$(printf '%s' "$alt" | tr 'A-Z' 'a-z')"
    hits="$(printf '%s\n' "$code" | grep -E "\"(${lalt})\"")" || true
    [ -n "$hits" ] && { echo "R3 key name as a string in $f:"; printf '%s\n' "$hits" | sed 's/^/  /'; bad=1; }

    hits="$(printf '%s\n' "$code" | grep -E 'switch[[:space:]]*\([[:space:]]*(k|key|[A-Za-z_.>\[\]-]*[.>]key)[[:space:]]*\)')" || true
    [ -n "$hits" ] && { echo "R4 switch over a key in $f:"; printf '%s\n' "$hits" | sed 's/^/  /'; bad=1; }
    return $bad
}

scan_sh() {   # <file>
    local f="$1" bad=0 hits keys alt code
    [ -f "$f" ] || { echo "INCONCLUSIVE: $f is not there"; return 2; }
    keys="$(key_names | tr 'A-Z' 'a-z')"
    [ -n "$keys" ] || { echo "INCONCLUSIVE: no keys found in $HDR"; return 2; }
    alt="$(printf '%s\n' "$keys" | paste -sd'|' -)"
    code="$(grep -nvE '^[[:space:]]*(#|$)' "$f")" || true
    hits="$(printf '%s\n' "$code" | grep -E 'CK_[A-Z0-9_]+')" || true
    [ -n "$hits" ] && { echo "R5 CK_ name in $f:"; printf '%s\n' "$hits" | sed 's/^/  /'; bad=1; }
    # A key name as a whole `case` arm or as one side of a string test.
    hits="$(printf '%s\n' "$code" | grep -E "^[0-9]+:[[:space:]]*(${alt})(\\|[a-z_]+)*\\)|(=|==|!=)[[:space:]]*\"?(${alt})\"?[[:space:]]*(\\]|;|$)")" || true
    [ -n "$hits" ] && { echo "R5 key name tested in $f:"; printf '%s\n' "$hits" | sed 's/^/  /'; bad=1; }
    return $bad
}

run_all() {
    local rc=0 r
    scan_cpp "$CHARFILE"; r=$?; [ $r -gt $rc ] && rc=$r
    scan_cpp "$RECORDER"; r=$?; [ $r -gt $rc ] && rc=$r
    scan_sh "$BUILDER";   r=$?; [ $r -gt $rc ] && rc=$r
    scan_sh "$EQUIV";     r=$?; [ $r -gt $rc ] && rc=$r
    return $rc
}

if [ "${1:-}" = "--selftest" ]; then
    T="$(mktemp -d "${TMPDIR:-/tmp}/nopkb.XXXXXX")" || exit 2
    trap 'rm -rf "$T"' EXIT
    cp "$CHARFILE" "$T/CharFile.cpp"; cp "$RECORDER" "$T/CreationSource.cpp"; cp "$BUILDER" "$T/build_fixture.sh"; cp "$EQUIV" "$T/check_fixture_equivalence.sh"
    export NO_PER_KEY_CHARFILE="$T/CharFile.cpp" NO_PER_KEY_RECORDER="$T/CreationSource.cpp" NO_PER_KEY_BUILDER="$T/build_fixture.sh" NO_PER_KEY_EQUIV="$T/check_fixture_equivalence.sh"
    out="$("$0" 2>&1)"; rc=$?
    if [ $rc -ne 0 ]; then echo "SELFTEST FAIL: the untouched copies are not green (rc=$rc)"; printf '%s\n' "$out"; exit 1; fi
    echo "selftest: untouched copies green"
    fails=0
    mutate() {   # <rule> <file-in-T> <text to append>
        cp "$CHARFILE" "$T/CharFile.cpp"; cp "$RECORDER" "$T/CreationSource.cpp"; cp "$BUILDER" "$T/build_fixture.sh"; cp "$EQUIV" "$T/check_fixture_equivalence.sh"
        printf '%s\n' "$3" >> "$T/$2"
        out="$("$0" 2>&1)"; rc=$?
        if [ $rc -eq 1 ] && grep -q "^$1 " <<< "$out"; then
            echo "selftest: $1 red as expected ($2)"
        else
            echo "SELFTEST FAIL: $1 did not go red on $2 (rc=$rc)"; fails=1
        fi
    }
    mutate R1 CharFile.cpp        'static int m1(int k) { switch (k) { case CK_RACE: return 1; } return 0; }'
    mutate R2 CharFile.cpp        'static bool m2(CreationKey k) { return k == CK_RACE; }'
    mutate R2 CreationSource.cpp  'static bool m2b(CreationKey k) { return CK_GOD != k; }'
    mutate R3 CharFile.cpp        'static const char *m3 = "attr_str";'
    mutate R3 CreationSource.cpp  'static const char *m3b = "gear_stream";'
    mutate R4 CreationSource.cpp  'static int m4(CreationKey k) { switch (k) { default: return 0; } }'
    mutate R5 build_fixture.sh    'if [ "$X" = "race" ]; then echo; fi'
    mutate R5 build_fixture.sh    'echo CK_RACE'
    mutate R5 check_fixture_equivalence.sh 'echo CK_RACE'
    mutate R5 check_fixture_equivalence.sh 'if [ "$k" = "attr_str" ]; then echo; fi'
    [ $fails -eq 0 ] && echo "selftest: PASS" && exit 0
    exit 1
fi

out="$(run_all)"; rc=$?
if [ $rc -eq 0 ]; then
    echo "PASS: no per-key branch in $CHARFILE, $RECORDER, $BUILDER, $EQUIV"
    exit 0
fi
printf '%s\n' "$out"
[ $rc -eq 1 ] && echo "FAIL: per-key branch (spec B18)"
exit $rc
