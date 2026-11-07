#!/usr/bin/env bash
# gate: cheap
#
# Does src/Create.cpp still branch on MO_RECREATE or on `reincarnate`, and does
# Resource::GrantGear in src/Annot.cpp still branch on MO_RECREATE?
#
# WHAT IS BEING PROVED. Every character-creation decision goes through the
# creation source (inc/CreationSource.h, src/CreationSource.cpp): a site calls
# SourcedRoll, SourcedPick or SourcedItem, and the active source (Live or
# Replay) answers or does not. A site that tests MO_RECREATE or `reincarnate`
# itself is a second code path beside the source, and the fixture builder
# (bead inc-10v7f, spec A6) depends on there being exactly one. This check
# fails on any such branch in src/Create.cpp. The mode value MO_CREATE stays
# legal: it is read by display code that decides nothing.
#
# WHAT IT FLAGS (a line in src/Create.cpp that is not a pure comment line):
#   - any occurrence of MO_RECREATE;
#   - the word `reincarnate` used in a condition: if/while/for (...reincarnate,
#     `!reincarnate`, `reincarnate ==`, `reincarnate !=`, `reincarnate ?`,
#     `reincarnate &&`, `reincarnate ||`, or `(reincarnate)`.
# A function parameter, a string literal and the method name Reincarnate (capital
# R) are not branches and are not flagged.
#
# fact: the text of src/Create.cpp -- read from the working tree by grep; no game run, no seed, no map
# fact: the text of Resource::GrantGear in src/Annot.cpp -- read from the working tree by awk and grep; no game run, no seed, no map
# fact: which tokens count as a branch -- the two patterns above, fixed in this file
#
# Usage: tools/check_creation_source_sites.sh [--selftest]
#        --selftest copies src/Create.cpp and src/Annot.cpp, adds one branch of
#        each kind, and proves this script goes red on each copy.
# Exit: 0 no branch; 1 a branch is present; 2 could not measure.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

FILE="${CREATION_SOURCE_SITES_FILE:-src/Create.cpp}"
GEAR_FILE="${CREATION_SOURCE_SITES_GEAR_FILE:-src/Annot.cpp}"

scan() {
    local f="$1"
    [ -f "$f" ] || { echo "INCONCLUSIVE: $f is not there"; return 2; }
    # Drop pure comment lines (//, /*, *) before matching.
    local code
    code="$(grep -nvE '^[[:space:]]*(//|/\*|\*)' "$f")" || true
    [ -n "$code" ] || { echo "INCONCLUSIVE: $f has no code lines"; return 2; }
    local bad=0 hits
    hits="$(printf '%s\n' "$code" | grep -E 'MO_RECREATE')" || true
    if [ -n "$hits" ]; then
        echo "FAIL: MO_RECREATE in $f (use the creation source):"
        printf '%s\n' "$hits" | sed 's/^/  /'
        bad=1
    fi
    hits="$(printf '%s\n' "$code" | grep -E '(if|while|for)[[:space:]]*\(.*\breincarnate\b|!reincarnate\b|\breincarnate[[:space:]]*(==|!=|\?|&&|\|\|)|\([[:space:]]*reincarnate[[:space:]]*\)')" || true
    if [ -n "$hits" ]; then
        echo "FAIL: a branch on reincarnate in $f (use the creation source):"
        printf '%s\n' "$hits" | sed 's/^/  /'
        bad=1
    fi
    return $bad
}

# MO_RECREATE inside the body of Resource::GrantGear: from its definition at
# column 0 to the first line that is exactly two spaces and a closing brace.
scan_gear() {
    local f="$1"
    [ -f "$f" ] || { echo "INCONCLUSIVE: $f is not there"; return 2; }
    local body
    body="$(awk '/^void Resource::GrantGear\(/ {on=1} on {print NR ": " $0} on && /^  }[[:space:]]*$/ {exit}' "$f")"
    [ -n "$body" ] || { echo "INCONCLUSIVE: Resource::GrantGear is not in $f"; return 2; }
    local hits
    hits="$(printf '%s\n' "$body" | grep -E 'MO_RECREATE')" || true
    if [ -n "$hits" ]; then
        echo "FAIL: MO_RECREATE in Resource::GrantGear in $f (use the creation source):"
        printf '%s\n' "$hits" | sed 's/^/  /'
        return 1
    fi
    return 0
}

if [ "${1:-}" = "--selftest" ]; then
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    fail=0
    scan "$FILE" > /dev/null || { echo "selftest: the real file already fails"; exit 1; }
    cp "$FILE" "$tmp/a.cpp"; echo '    if (MyTerm->GetMode() == MO_RECREATE) { }' >> "$tmp/a.cpp"
    cp "$FILE" "$tmp/b.cpp"; echo '    if (reincarnate) { }' >> "$tmp/b.cpp"
    cp "$FILE" "$tmp/c.cpp"; echo '    x = !reincarnate;' >> "$tmp/c.cpp"
    for c in a b c; do
        if scan "$tmp/$c.cpp" > /dev/null; then
            echo "selftest: mutation $c was NOT caught"; fail=1
        fi
    done
    scan_gear "$GEAR_FILE" > /dev/null || { echo "selftest: the real GrantGear already fails"; exit 1; }
    sed '/t = (time_t)NextSeed();/a\
    if (T1->GetMode() == MO_RECREATE) { }' "$GEAR_FILE" > "$tmp/d.cpp"
    if scan_gear "$tmp/d.cpp" > /dev/null; then
        echo "selftest: mutation d (MO_RECREATE in GrantGear) was NOT caught"; fail=1
    fi
    [ $fail -eq 0 ] && echo "selftest: all 4 mutations caught"
    exit $fail
fi

out="$(scan "$FILE")"; rc=$?
[ -n "$out" ] && echo "$out"
gout="$(scan_gear "$GEAR_FILE")"; grc=$?
[ -n "$gout" ] && echo "$gout"
[ $grc -gt $rc ] && rc=$grc
if [ $rc -eq 0 ]; then
    echo "PASS: no MO_RECREATE or reincarnate branch in $FILE, none in GrantGear in $GEAR_FILE"
fi
exit $rc
