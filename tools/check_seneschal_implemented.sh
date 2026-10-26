#!/bin/bash
# gate: live
# Bead inc-qylz: the Seneschal skill does work, so its SkillInfo row MUST carry imp == true and its description MUST NOT print "(NOT IMPLEMENTED!)".
# fact: skill row -- parsed from the SK_SENESCHAL row of SkillInfo[] in src/Tables.cpp; field order from struct SkillInfoStruct in inc/Creature.h
# fact: description text -- incursion-headless -wikihelp, which calls DescribeSkill(); no character, map, seed or RNG involved
# fact: settings -- tools/fixtures/options-2026-08-22.dat copied into the run directory
# fact: binary freshness -- the behavioral part reads the built binary, the structural part reads the source; rebuild after a source change
# Exit 0: both parts hold; 1: a part fails; 2: cannot measure.
set -uo pipefail
cd "$(dirname "$0")/.."

# --- 1. structural: parse the row, never grep one literal line ---------------
python3 -I - <<'PY'
import re, sys
src = open('src/Tables.cpp', errors='replace').read()
decl = open('inc/Creature.h', errors='replace').read()
m = re.search(r'struct\s+SkillInfoStruct\s*\{(.*?)\}', decl, re.S)
fields = re.findall(r'^\s*[\w ]+?[\s*]+(\w+)\s*;', m.group(1), re.M) if m else []
if fields[:4] != ['sk', 'name', 'imp', 'active']:
    print('SENESCHAL INCONCLUSIVE SkillInfoStruct no longer starts sk, name, imp, active'); sys.exit(2)
rows = re.findall(r'\{\s*SK_SENESCHAL\s*,\s*"Seneschal"\s*,\s*(\w+)\s*,\s*(\w+)\s*,', src)
if len(rows) != 1 or rows[0][0] not in ('true', 'false'):
    print('SENESCHAL INCONCLUSIVE cannot find exactly one SK_SENESCHAL row in src/Tables.cpp'); sys.exit(2)
if rows[0][0] != 'true':
    print('SENESCHAL FAIL structural: SkillInfo row has imp=false'); sys.exit(1)
print('SENESCHAL structural ok: imp=true')
PY
structural=$?
[ "$structural" -eq 2 ] && exit 2

# --- 2. behavioral: the description the game produces ------------------------
[ -x ./incursion-headless ] || { echo 'SENESCHAL INCONCLUSIVE build with BACKEND=posix ./build_macos.sh'; exit 2; }
mkdir -p logs/runs
run=$(mktemp -d "$PWD/logs/runs/seneschal-implemented.XXXXXX") || exit 2
echo "Specimens: $run"
mkdir -p "$run/save" "$run/logs" "$run/out"
ln -sfn "$PWD/mod" "$run/mod"
ln -sfn "$PWD/lib" "$run/lib"
cp tools/fixtures/options-2026-08-22.dat "$run/Options.Dat" || { echo 'SENESCHAL INCONCLUSIVE no options fixture'; exit 2; }
if ! INCURSIONPATH="$run/" ./incursion-headless -wikihelp "$run/out" >"$run/harness.txt" 2>&1; then
    cat "$run/harness.txt"
    echo 'SENESCHAL INCONCLUSIVE -wikihelp failed'
    exit 2
fi
page="$run/out/Seneschal.md"
[ -s "$page" ] || { echo 'SENESCHAL INCONCLUSIVE no Seneschal.md produced'; exit 2; }
text=$(<"$page")
grep -q '^# Seneschal' <<<"$text" || { echo 'SENESCHAL INCONCLUSIVE Seneschal.md has no title'; exit 2; }
grep -q 'Passive\|Active' <<<"$text" || { echo 'SENESCHAL INCONCLUSIVE description text missing'; exit 2; }
behavioral=0
if grep -q 'NOT IMPLEMENTED' <<<"$text"; then
    echo 'SENESCHAL FAIL behavioral: description says (NOT IMPLEMENTED!)'
    behavioral=1
else
    echo 'SENESCHAL behavioral ok: description has no NOT IMPLEMENTED marker'
fi
[ "$structural" -eq 0 ] && [ "$behavioral" -eq 0 ] && { echo 'SENESCHAL PASS'; exit 0; }
exit 1
