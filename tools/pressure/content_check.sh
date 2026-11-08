#!/bin/bash
# Load every kept content save in a built tree and compare it with the value file its planting build recorded
# (inc-cjos0 phase 8, D3).
#
#   tools/pressure/content_check.sh <tree> <content-dir> <out-dir> [<fixture-values-dir>]
#
# <content-dir> holds <tag>.sav (a save tools/pressure/plant.sh wrote), <tag>.txt (its value file from the build
# that planted it: the baseline), <tag>.fixture (the fixture it was planted in) and <tag>.scored (planted by a
# landing on master). Each save is loaded in <tree> through field_values.sh and compared with its baseline; every
# planted value must keep its meaning, so a `changed` or `missing` line fails a scored save (an `added` line is
# fine). A save without <tag>.scored came from the epic, whose saves are disposable: it is printed, never scored.
# <fixture-values-dir>, when given, holds <fixture>.txt of the same tree, so the planted lines can be printed.
# Output: one `    planted: ...` line per planted value (up to 8 a save), the failing lines, then
# `content: PASS|FAIL|UNMEASURED -- <detail>`.
# Exit: 0 every scored save kept every value, 1 one lost a value, 2 a save could not be measured.
#
# fact: the content saves -- written by plant.sh from a frozen fixture and a case spec; no seed, no key script
# fact: the baseline values -- recorded by the build that planted each save, not by this tree
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
[ $# -ge 3 ] || { echo "usage: $0 <tree> <content-dir> <out-dir> [<fixture-values-dir>]" >&2; exit 2; }
WORK="$1"; CONTENT="$2"; OUT="$3"; FXV="${4:-}"
mkdir -p "$OUT" || exit 2
cn=0; cbad=0; cunm=0
for cs in "$CONTENT"/*.sav; do
    [ -f "$cs" ] || continue
    tag="$(basename "$cs" .sav)"
    fx="$(cat "$CONTENT/$tag.fixture" 2>/dev/null)"
    if ! "$HERE/field_values.sh" "$WORK" "$cs" "$OUT/$tag.txt" 2> "$OUT/$tag.err"; then
        cunm=$((cunm + 1)); echo "    could not load content save $tag in the landed tree: $(head -c 200 "$OUT/$tag.err")"; continue
    fi
    "$HERE/compare_values.py" "$CONTENT/$tag.txt" "$OUT/$tag.txt" > "$OUT/$tag.cmp" 2>&1; crc=$?
    cn=$((cn + 1))
    if [ -n "$FXV" ] && [ -f "$FXV/$fx.txt" ]; then
        "$HERE/compare_values.py" --planted "$FXV/$fx.txt" "$OUT/$tag.txt" 2>&1 | sed "s/^/    ($tag) /"
    fi
    if [ $crc -eq 1 ]; then
        if [ -f "$CONTENT/$tag.scored" ]; then
            cbad=$((cbad + 1)); echo "    content save $tag lost the meaning of a planted value:"
            grep -E '^(changed|missing)' "$OUT/$tag.cmp" | head -5 | sed 's/^/      /'
        else
            echo "    content save $tag (epic, disposable, not scored) changed:"
            grep -E '^(changed|missing)' "$OUT/$tag.cmp" | head -3 | sed 's/^/      /'
        fi
    elif [ $crc -ne 0 ]; then
        cunm=$((cunm + 1)); echo "    content save $tag: compare could not measure: $(head -c 200 "$OUT/$tag.cmp")"
    fi
done
if [ $cbad -gt 0 ]; then echo "content: FAIL -- $cbad of $cn content saves lost the meaning of a planted value"; exit 1; fi
if [ $cunm -gt 0 ] || [ $cn -eq 0 ]; then echo "content: UNMEASURED -- $cunm content saves could not be measured, $cn compared"; exit 2; fi
echo "content: PASS -- $cn content saves load with every planted value kept"
exit 0
