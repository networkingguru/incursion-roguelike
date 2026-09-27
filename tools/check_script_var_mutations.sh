#!/bin/bash
# gate: none -- a mutation harness: it deliberately breaks src/Dump.cpp and the
# compiler, rebuilds twice, and restores. The gate must not run it on every
# branch. Its subjects are tools/check_script_var_recovery.py (gate: live) and
# tools/check_script_var_compile.sh (gate: live); this proves those two bite.
# inc-glnx: temporary mutations prove both oracles fail; restore sources/build.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
WORK="$(mktemp -d "$ROOT/logs/script-var-mutations.XXXXXX")"
echo "Specimens: $WORK"
for file in src/Dump.cpp src/yygram.cpp lang/Grammar.acc; do
    mkdir -p "$WORK/$(dirname "$file")"
    cp -f "$file" "$WORK/$file"
done
restore() {
    for file in src/Dump.cpp src/yygram.cpp lang/Grammar.acc; do
        cp -f "$WORK/$file" "$file"
    done
}
trap 'restore; BACKEND=posix ./build_macos.sh > "$WORK/build-restored-on-error.log" 2>&1' EXIT
python3 - <<'PY'
from pathlib import Path
p = Path('src/Dump.cpp')
s = p.read_text()
needle = '    return PrintScriptVariables(false);'
assert s.count(needle) == 1
s = s.replace(needle, '    Game::Modules[0]->szDataSeg = 0;\n' + needle)
p.write_text(s)
for file in ['src/yygram.cpp', 'lang/Grammar.acc']:
    p = Path(file)
    s = p.read_text()
    needle = 'if (((uint32)b->xID >> 24) != 1 || theModule->__GetResource(b->xID) != theRes)'
    assert s.count(needle) == 2
    p.write_text(s.replace(needle, 'if (false) /* deliberate owner-check mutation */'))
PY
BACKEND=posix ./build_macos.sh > "$WORK/build-red.log" 2>&1
mkdir -p "$WORK/driver/save" "$WORK/driver/logs"
ln -s "$ROOT/mod" "$WORK/driver/mod"
ln -s "$ROOT/lib" "$WORK/driver/lib"
status=0
INCURSIONPATH="$WORK/driver/" ./incursion-headless -scriptvars > "$WORK/validity-red.log" 2>&1 || status=$?
[ "$status" = 22 ]
grep -F 'szDataSeg=0; 98 variable rows require 392 bytes' "$WORK/validity-red.log"
status=0
tools/check_script_var_compile.sh > "$WORK/name-red.log" 2>&1 || status=$?
[ "$status" = 1 ]
echo 'owner oracle rejected the deliberately disabled check'
restore
trap - EXIT
BACKEND=posix ./build_macos.sh > "$WORK/build-green.log" 2>&1
INCURSIONPATH="$WORK/driver/" ./incursion-headless -scriptvars > "$WORK/validity-green.log" 2>&1
grep -F 'Validity: OK module=0 variables=98 szDataSeg=392' "$WORK/validity-green.log"
tools/check_script_var_compile.sh > "$WORK/name-green.log" 2>&1
cat "$WORK/name-green.log"
echo 'PASS: validity and owner-check mutations rejected; sources and build restored'
