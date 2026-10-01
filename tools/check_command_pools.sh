#!/bin/bash
# gate: live
# gate-serial: --prove-red overwrites tracked src/inc/lib files and rebuilds the shared binaries
# inc-sgre: fresh Priest 2 / Mage 3, Evil domain, no command bonuses.
# Read Player::Dump, not source text. Old code has one command cap of 5;
# fixed code has separate spider/devil/undead caps of 2.
# Admission is Traced only: this script does not force a command roll or
# construct enough followers to exhaust this character's large party pool.
# --prove-red saves the working sources, builds HEAD's original sources,
# requires this check to fail, restores the working sources, rebuilds and
# requires green. All backups and specimens stay under logs/.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p logs/inc-sgre
if [[ ${1:-} == --prove-red ]]; then
    proof=$(mktemp -d "$PWD/logs/inc-sgre/proof-XXXXXX")
    files=(src/Social.cpp src/Skills.cpp src/Debug.cpp inc/Creature.h lib/domains.irh)
    for file in "${files[@]}"; do
        mkdir -p "$proof/fixed/$(dirname "$file")" "$proof/old/$(dirname "$file")"
        cp -f "$file" "$proof/fixed/$file"
        git show "HEAD:$file" > "$proof/old/$file"
    done
    restore() {
        for file in "${files[@]}"; do cp -f "$proof/fixed/$file" "$file"; done
    }
    trap restore EXIT
    for file in "${files[@]}"; do cp -f "$proof/old/$file" "$file"; done
    BACKEND=posix ./build_macos.sh > "$proof/build-red.log" 2>&1
    set +e
    "$0" > "$proof/red.log" 2>&1
    result=$?
    set -e
    restore
    trap - EXIT
    BACKEND=posix ./build_macos.sh > "$proof/build-green.log" 2>&1
    if [[ $result != 1 ]] || ! grep -Fxq "PHD COMMAND -8 / 5" "$proof/red.log"; then
        echo "FAIL: expected old cap 5 and assertion failure (1), got status $result; $proof"
        exit 2
    fi
    "$0" > "$proof/green.log" 2>&1
    cat "$proof/red.log" "$proof/green.log"
    echo "Red/green proof: $proof"
    exit 0
fi
[[ $# == 0 ]] || { echo "usage: $0 [--prove-red]"; exit 2; }
run=$(mktemp -d "$PWD/logs/inc-sgre/command-pools-XXXXXX")
export INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat
export INCURSION_RUN_DIR="$run"
set +e
tools/headless.sh tools/keys/command-pools.keys 1 > "$run/session.log" 2>&1
result=$?
set -e
cat "$run/session.log"
[[ $result == 0 ]] || { echo "ERROR: headless run failed: $run"; exit 2; }
python3 - "$run" <<'PY'
import pathlib, re, sys
run = pathlib.Path(sys.argv[1])
def screen(label):
    paths = list((run / "logs/screens").glob("*-" + label + ".txt"))
    if len(paths) != 1:
        raise RuntimeError(f"expected one {label} screen: {paths}")
    return paths[0].read_text()
classes = screen("classes")
if not all(s in classes for s in ("Priest 2", "Mage 3", "Faith  Xel", "Lawful Evil")):
    raise RuntimeError("wrong character")
group = screen("group")
lines = [s.split("|")[0].strip() for s in group.splitlines() if "PHD COMMAND" in s]
print("\n".join(lines))
for kind in ("devil", "undead", "spider"):
    if not re.search(r"PHD COMMAND " + kind + r"\s+-8 / 2\b", group):
        print(f"FAIL: expected {kind} command cap 2 (Priest 2, zero bonuses); {run}")
        sys.exit(1)
print(f"PASS: separate devil, undead, spider caps = 2; specimens: {run}")
PY
