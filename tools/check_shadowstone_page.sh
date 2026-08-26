#!/bin/bash
# Structural regression check for rule-triage finding F35 / inc-tek.8.8.
# The Shadowstone description was copied from a cloak and also understated
# PLUS_2PER1 as equal to, rather than twice, the item's magical plus.
#
# Usage: tools/check_shadowstone_page.sh    (exits 0 on pass, 1 on fail)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

page="$(awk '
  /AI_STONE Effect "Shadowstone"/ { in_effect=1 }
  in_effect && /Desc:/ { in_desc=1 }
  in_desc { print }
  in_desc && /magical plus\.";/ { exit }
' lib/m_items.irh)"

[ -n "$page" ] || {
    echo "FAIL: could not find the Shadowstone description."
    exit 1
}

page="$(printf '%s\n' "$page" | tr '\n' ' ' | tr -s ' ')"
fail=0

case "$page" in
    *"addition, the stone grants a bonus to Hide skill checks equal to twice its magical plus."*) ;;
    *) echo "FAIL: the Shadowstone page does not say the stone grants a Hide bonus equal to twice its magical plus."
       fail=1 ;;
esac
case "$page" in
    *"addition, the cloak grants a bonus to Hide skill checks"*)
       echo "FAIL: the Shadowstone page still calls the item a cloak."
       fail=1 ;;
esac

if [ "$fail" -eq 0 ]; then
    echo "PASS: the Shadowstone page names the stone and says its Hide bonus is twice its magical plus."
fi
exit "$fail"
