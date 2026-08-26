#!/bin/bash
# Structural regression check for rule-triage finding F36 / inc-tek.8.8.
# The Bracers of Defense description must state both rates in its effect:
# Defense Class at PLUS_1PER1 and Coverage at PLUS_2PER1.
#
# Usage: tools/check_bracers_defense_page.sh    (exits 0 on pass, 1 on fail)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

page="$(awk '
  /AI_BRACERS Effect "Defense"/ { in_effect=1 }
  in_effect && /Desc:/ { in_desc=1 }
  in_desc { print }
  in_desc && /twice that\.";/ { exit }
' lib/m_items.irh)"

[ -n "$page" ] || {
    echo "FAIL: could not find the Bracers of Defense description."
    exit 1
}

page="$(printf '%s\n' "$page" | tr '\n' ' ' | tr -s ' ')"
fail=0

case "$page" in
    *"defense class by a magic bonus equal to the magical plus they possess"*) ;;
    *) echo "FAIL: the Bracers of Defense page does not say the Defense Class bonus equals their magical plus."
       fail=1 ;;
esac
case "$page" in
    *"coverage by twice that."*) ;;
    *) echo "FAIL: the Bracers of Defense page does not say the Coverage bonus is twice their magical plus."
       fail=1 ;;
esac

if [ "$fail" -eq 0 ]; then
    echo "PASS: the Bracers of Defense page states the equal Defense Class and doubled Coverage rates."
fi
exit "$fail"
