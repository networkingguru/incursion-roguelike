#!/bin/bash
# Structural regression check for inc-gx1v.
# The Knowledge (Magic) description promised casting without a spellbook,
# but no code does that (Creature::Cast never reads SK_KNOW_MAGIC).
#
# Usage: tools/check_know_magic_desc.sh    (exits 0 on pass, 1 on fail)
# gate: cheap
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

entry="$(awk '
  /\{ SK_KNOW_MAGIC, "Knowledge \(Magic\)"/ { in_entry=1; next }
  in_entry { print }
  in_entry && /A_INT, A_INT/ { exit }
' src/Tables.cpp)"

[ -n "$entry" ] || {
    echo "FAIL: could not find the SK_KNOW_MAGIC entry in src/Tables.cpp."
    exit 1
}

desc="$(printf '%s\n' "$entry" | grep -o '"[^"]*"' | tr -d '"' | tr -d '\n')"
fail=0

case "$desc" in
    *"without a spellbook"*)
       echo "FAIL: the Knowledge (Magic) description still promises casting without a spellbook."
       fail=1 ;;
esac
case "$desc" in
    *"This skill covers the lore of magic."*) ;;
    *) echo "FAIL: the Knowledge (Magic) description does not open with the lore-of-magic text."
       fail=1 ;;
esac
case "$desc" in
    *"cannot scribe a scroll of a higher level than its skill rating."*) ;;
    *) echo "FAIL: the Knowledge (Magic) description does not state the Scribe Scroll limit."
       fail=1 ;;
esac

if [ "$fail" -eq 0 ]; then
    echo "PASS: the Knowledge (Magic) description describes the skill and makes no spellbook promise."
fi
exit "$fail"
