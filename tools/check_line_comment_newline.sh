#!/bin/bash
# gate: live
# inc-vsiqf: a // comment must preserve the following #define's line boundary.
# fact: source and following constant -- fixed, self-contained scratch fixture
# fact: diagnostic text -- fixed source fixture (no seed-selected text)
# fact: constant expansion -- paired block/line-comment fixtures and program.i
# fact: compilation result -- -compile only; no character, world, or random rolls
# Controls: fixed fixtures, per docs/VERIFICATION.md; no game session is run.
# Exit 0: survives; 1: lost; 2: unable to establish the result.
set -euo pipefail

scratch=''
finish() { printf '%s\n' "$2"; exit "$1"; }
cleanup() { [ -z "$scratch" ] || rm -rf -- "$scratch"; }
trap cleanup EXIT
trap 'finish 2 "UNMEASURED: line-comment check interrupted"' HUP INT TERM
trap 'finish 2 "UNMEASURED: line-comment check setup or inspection failed"' ERR
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
[ -x ./incursion-headless ] || finish 2 'UNMEASURED: ./incursion-headless missing; run BACKEND=posix ./build_macos.sh'
command -v python3 >/dev/null || finish 2 'UNMEASURED: python3 missing'
mkdir -p logs
scratch="$(mktemp -d "$root/logs/line-comment-$$-XXXXXX")"
mkdir -p "$scratch/lib" "$scratch/mod" "$scratch/logs"
cat > "$scratch/lib/main.irc" <<'EOF'
#include "probe.h"
Effect "probe" : VSIQF_B { Level: 1; }
Module "Line comment probe";
File "Vsiqf.Mod";
Slot 0;
EOF

compile() {
    local status=0
    INCURSIONPATH="$scratch/" ./incursion-headless -compile main.irc \
        </dev/null > "$scratch/$1.log" 2>&1 || status=$?
    return "$status"
}

printf '#define VSIQF_A 1 /* x */\n#define VSIQF_B 2\n' > "$scratch/lib/probe.h"
compile control || finish 2 'UNMEASURED: block-comment control did not compile'
cp -f "$scratch/lib/program.i" "$scratch/control.i"
printf '#define VSIQF_A 1 // x\n#define VSIQF_B 2\n' > "$scratch/lib/probe.h"
rm -f "$scratch/lib/program.i"
status=0
compile comment || status=$?

# Compare the complete preprocessed module, ignoring only #line and whitespace.
# This rejects unrelated preprocessing changes instead of calling them this bug.
result=0
python3 - "$scratch" "$status" <<'PY' || result=$?
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])
status = int(sys.argv[2])

def normalized(path):
    return re.sub(r'\s+', ' ', re.sub(r'^#line[^\n]*', '', path.read_text(),
                                   flags=re.M)).strip()

try:
    control = normalized(root / 'control.i')
    comment = normalized(root / 'lib/program.i')
    expected = ('Effect "probe" : 2 { Level: 1; } '
                'Module "Line comment probe"; File "Vsiqf.Mod"; Slot 0;')
    diagnostic = (root / 'comment.log').read_text()
    if control != expected:
        sys.exit(2)
    if status == 0 and comment == expected:
        sys.exit(0)
    if (status == 20 and comment == expected.replace(': 2', ': VSIQF_B')
            and 'Illegal word token: "VSIQF_B"' in diagnostic):
        sys.exit(1)
except (OSError, UnicodeError):
    pass
sys.exit(2)
PY
case "$result" in
    0) finish 0 'PASS: following define VSIQF_B survives the // comment' ;;
    1) finish 1 'FAIL: following define VSIQF_B is lost after the // comment' ;;
    *) finish 2 'UNMEASURED: compilation or preprocessing failed for another reason' ;;
esac
