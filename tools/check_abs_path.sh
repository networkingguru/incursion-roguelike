#!/bin/bash
# Regression check for the relative-IncursionDirectory bug.
#
# Launched as './incursion', argv[0] gives a relative directory. If main() does
# not resolve it to an absolute path, ChangeDirectory(IncursionDirectory) becomes
# chdir("./") -- a no-op -- so the game never returns to its own folder and the
# second LoadModules() (reached from the start menu) calls Fatal().
#
# The symptom is observable from outside: with a relative home directory the game
# reports missing files as './...', with an absolute one as '/...'.
#
# Usage: tools/check_abs_path.sh      (exits 0 on pass, 1 on fail)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

[ -x ./incursion ] || { echo "FAIL: ./incursion not built. Run ./build_macos.sh"; exit 1; }

# The path only appears in the log when the file is absent, so hide it briefly.
STASHED=""
if [ -f Options.Dat ]; then
    mv Options.Dat Options.Dat.checktmp
    STASHED=yes
fi
restore() { [ -n "$STASHED" ] && mv -f Options.Dat.checktmp Options.Dat; }
trap restore EXIT

LOG="$(mktemp)"
# Deliberately relative, which is what triggers the bug. The game waits for input
# forever, so start it, give it time to log, then stop it.
./incursion >"$LOG" 2>&1 &
GAME=$!
sleep 8
kill "$GAME" 2>/dev/null
wait "$GAME" 2>/dev/null

LINE="$(grep -o "Couldn't open [^ ]*Options.Dat" "$LOG" | head -1)"
rm -f "$LOG"

if [ -z "$LINE" ]; then
    echo "FAIL: game never reported a missing Options.Dat; check cannot conclude"
    exit 1
fi

case "$LINE" in
    *"open /"*) echo "PASS: home directory resolved to an absolute path"; exit 0 ;;
    *)          echo "FAIL: home directory is relative -> $LINE"; exit 1 ;;
esac
