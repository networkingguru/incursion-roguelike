#!/bin/bash
# gate: live
# Run tools/keys/phase-plane-name.keys on the fixture character and judge the
# plane it names against the plane it stored. Needs BACKEND=posix
# ./build_macos.sh first. Seed is irrelevant (see the key script header).
#
# PASS (exit 0) only when BOTH hold:
#   * the message line is exactly "You phase into the ethereal plane." and
#   * the wizard dump's PHASED line shows Val 3 (PHASE_ETHEREAL). The dump
#     prints the Val field as "(undefined 3)" -- match the number, not the word.
# Otherwise it prints what it saw and exits 1.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2

mkdir -p ./logs
RUN_ROOT="$(mktemp -d "./logs/phase-plane-name-XXXXXX")"
echo "specimens: $RUN_ROOT"

rc=0
INCURSION_RUN_DIR="$RUN_ROOT/run" \
INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat \
INCURSION_LOAD=tools/fixtures/chars/orc-barbarian-seed1-opt0822.sav \
    tools/headless.sh tools/keys/phase-plane-name.keys 1 > "$RUN_ROOT/session.log" 2>&1 || rc=$?
if [ "$rc" -ne 0 ]; then
    echo "UNMEASURED: harness exit $rc (see $RUN_ROOT/session.log)"
    exit 2
fi

python3 - "$RUN_ROOT" <<'PY'
import pathlib, re, sys
root = pathlib.Path(sys.argv[1])
screens = sorted((root / 'run' / 'logs' / 'screens').glob('*.txt'))
want = "You phase into the ethereal plane."
msgs = []
vals = []
for path in screens:
    for line in path.read_text(errors='replace').splitlines():
        m = re.match(r'You phase into the (.+?)\.\s*\|', line)
        if m:
            msgs.append((path.name, m.group(1)))
        v = re.search(r'PHASED from SS MISC \(Val:\(undefined (-?\d+)\)', line)
        if v:
            vals.append((path.name, int(v.group(1))))
print(f"message lines seen: {msgs}")
print(f"PHASED Val fields seen: {vals}")
ok_msg = any(msg == "ethereal plane" for _, msg in msgs)
ok_val = any(val == 3 for _, val in vals)
if not msgs:
    print("UNMEASURED: no 'You phase into ...' line in any screen")
    sys.exit(2)
if not vals:
    print("UNMEASURED: no PHASED Val field in any screen")
    sys.exit(2)
if ok_msg and ok_val:
    print(f"GREEN: message is exactly {want!r} and PHASED Val is 3 (PHASE_ETHEREAL)")
    sys.exit(0)
print(f"RED: expected {want!r} and PHASED Val 3; "
      f"got messages {[m for _, m in msgs]} and vals {[v for _, v in vals]}")
sys.exit(1)
PY
exit $?
