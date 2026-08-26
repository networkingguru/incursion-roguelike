#!/bin/bash
# Regression check for F39 / inc-tek.8.8: the Sunblade's activated light field
# reaches the 60 feet promised by its page, or six 10-foot squares.
#
# Structural fallback: headless screen dumps show that activation fires but do
# not expose the field's radius. Restrict the oracle to the Sunblade effect and
# require its third component to remain the radius-six FI_LIGHT field.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SOURCE="${SOURCE:-lib/m_items.irh}"
effect="$(sed -n '/^AI_WEAPON Effect "Sunblade"/,/^Item /p' "$SOURCE")"

printf '%s\n' "$effect" | grep -Fq 'Flags: EF_NAMEONLY, EF_ACTIVATE3, EF_3PERDAY;' || {
    echo "FAIL: the Sunblade light field is no longer the third activated component."
    exit 1
}
printf '%s\n' "$effect" | grep -Fq '{ xval: RESIST; yval: AD_COLD; pval: PLUS_1PER1; }' || {
    echo "FAIL: the passive Sunblade cold-resistance component was disturbed."
    exit 1
}
printf '%s\n' "$effect" | grep -Fq '{  aval: AR_FIELD; lval: 6; rval: FI_LIGHT; cval: yellow; }' || {
    echo "FAIL: the Sunblade FI_LIGHT field must have radius 6 (60 feet)."
    exit 1
}
if printf '%s\n' "$effect" | grep -Eq 'aval: AR_FIELD; lval: 5; rval: FI_LIGHT'; then
    echo "FAIL: the old 50-foot Sunblade light radius remains."
    exit 1
fi

echo "Sunblade light radius: 6 squares = 60 feet"
echo "PASS: the third, activated Sunblade component is the radius-six FI_LIGHT field."
