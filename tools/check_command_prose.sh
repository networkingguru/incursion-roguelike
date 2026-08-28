#!/bin/bash
# Regression check for F8 / inc-tek.8.7: Command's description does NOT advertise
# the EF_LIM_LEVEL restriction the code deliberately removed. The Desc used to
# end "Does not affect creatures whose CR is more than 2/3rds your level"; the
# commented-out tval/EF_LIM_LEVEL line and the maintainer's "Let's remove that
# limit" note show the limit is gone from the code, so the prose must not
# promise it.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SOURCE="${SOURCE:-lib/pspells.irh}"
# Anchor on the effect's unique choice prompt so the check reads Command's real
# EA_GENERIC block and its Desc, not some other spell.
effect="$(sed -n '/Command -- Flee, Yield, Kneel/,/^  }/p' "$SOURCE")"

if printf '%s\n' "$effect" | grep -Eq '2/3rds your level|Does not affect creatures whose CR'; then
    echo "FAIL: Command's description still advertises the removed CR/level limit."
    exit 1
fi

echo "PASS: F8 / inc-tek.8.7 Command description does not advertise the removed level limit."
