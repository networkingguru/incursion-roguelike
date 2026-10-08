#!/bin/bash
# inc-ur9b reproduction: AID_UNCURSE prints "Your <Obj> crumbles to ash!" with
# no <Obj> argument. Builds nothing; run BACKEND=posix ./build_macos.sh first.
# Usage: tools/repro_uncurse_aid.sh [--lldb]
#   --lldb also runs the session under lldb and prints the crash frame.
# Specimens: logs/ur9b-repro/ (run directory, errors.log, lldb.out).
# Exit 0 when the session ran. Unfixed build: errors.log holds a "Probable
# parameter mismatch" line and the run ends with exit 138 / EXC_BAD_ACCESS.
cd "$(dirname "$0")/.." || exit 1
OUT=logs/ur9b-repro
rm -rf "$OUT"; mkdir -p "$OUT"
export INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat
if [ "$1" = "--lldb" ]; then
    printf '#!/bin/bash\nexec lldb -b -o "settings set target.env-vars LINES=48 COLUMNS=80 TERM=xterm" -o run -o bt -o quit -- "$@"\n' > "$OUT/lldbwrap.sh"
    chmod +x "$OUT/lldbwrap.sh"
    INCURSION_LAUNCHER="$PWD/$OUT/lldbwrap.sh" INCURSION_RUN_DIR="$OUT/lldb-run" \
        tools/headless.sh tools/keys/uncurse-aid.keys 5 > "$OUT/lldb.out" 2>&1
    echo "--- lldb crash frame ($OUT/lldb.out) ---"
    grep -A2 "stop reason" "$OUT/lldb.out" | cut -c1-200
fi
INCURSION_RUN_DIR="$OUT/run" tools/headless.sh tools/keys/uncurse-aid.keys 5 > "$OUT/headless.out" 2>&1
grep -E "^ended:" "$OUT/headless.out"
echo "--- ended exit code ---"
grep -E "^ended:" "$OUT/headless.out"
echo "--- ring worn ($OUT/run/logs/screens/0001-worn.txt) ---"
grep -m1 "curses itself" "$OUT/run/logs/screens/0001-worn.txt" | cut -c1-64
echo "--- prayed ($OUT/run/logs/screens/0002-prayed.txt) ---"
grep -m1 "crumbles to ash" "$OUT/run/logs/screens/0002-prayed.txt" | cut -c1-64
echo "--- errors.log ---"
if [ -f "$OUT/run/logs/errors.log" ]; then
    grep -E "Probable parameter|AID_|Null string" "$OUT/run/logs/errors.log"
    echo "--- AID_UNCURSE reached: GiveAid in the first error's call stack ---"
    grep -m1 "GiveAid" "$OUT/run/logs/errors.log" | cut -c1-110
    cp "$OUT/run/logs/errors.log" "$OUT/errors.log" 2>/dev/null
else
    echo "no errors.log written (no parameter mismatch)"
fi
exit 0
