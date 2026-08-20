#!/bin/bash
# Regression check for inc-upw.39: Registry::Get() must still complain, and
# Registry::GetQuiet() must still stay silent.
#
# WHAT THE SPLIT IS. Registry::Get() used to be one function: look the handle
# up, and if nothing answers, log "Registry::Get -- invalid object handle".
# That is right for a caller who believes the handle is live, and wrong for
# Target::GetThingOrNULL, where a monster holds the handle of something that
# has since died and a dead handle is simply the answer "gone". So the lookup
# moved into GetQuiet() and Get() became GetQuiet() plus the complaint.
#
# WHY THIS CHECK EXISTS. The 40-seed gate covers one half of the split already:
# if GetQuiet() ever resolves a handle differently from Get(), the game plays
# differently and the recorded screens diverge. Nothing covers the other half.
# Get() is what oThing(), oCreature() and every ordinary caller still use, and
# losing its complaint in a later edit would be SILENT -- diagnostics stop
# arriving, errors.log gets shorter, and a shorter errors.log reads as good
# news. This check makes that failure loud.
#
# HOW IT WORKS. INCURSION_QUIET_PROBE arms Registry::QuietProbe(), which runs
# once at the top of Game::Play(). It finds one live handle and one dead one in
# the registry, then exercises both functions against both and narrates what it
# did through Error(), because errors.log is the channel under test. This
# script reads the narration and asserts four things:
#
#   1. Get() and GetQuiet() agree on a LIVE handle, and both resolve it.
#   2. GetQuiet() returns nothing for a DEAD handle.
#   3. GetQuiet() logs NO invalid-handle line for it -- proved by position:
#      no such line appears between the probe's own lines.
#   4. Get() logs EXACTLY ONE invalid-handle line for that same dead handle.
#
# 3 and 4 are the point. Either one alone can be satisfied by a broken build:
# delete the Error() call and 3 passes; put it in GetQuiet() and 4 passes.
#
# Ends: 0 pass, 1 fail, 2 the check could not be run.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED="${1:-3}"
KEYS="tools/keys/dive.keys"
OPTS="$ROOT/tools/gates/Options.Dat"
BIN="incursion-headless"

[ -x "./$BIN" ] || {
    echo "INCONCLUSIVE: ./$BIN is not built. Run: BACKEND=posix ./build_macos.sh"
    exit 2
}
[ -f "$OPTS" ] || { echo "INCONCLUSIVE: no settings file at $OPTS"; exit 2; }

RUN="$(mktemp -d "${TMPDIR:-/tmp}/incursion-quiet.XXXXXX")"
trap 'rm -rf "$RUN"' EXIT

INCURSION_QUIET_PROBE=1 INCURSION_RUN_DIR="$RUN/game" \
    INCURSION_OPTIONS="$OPTS" INCURSION_BIN="./$BIN" \
    tools/headless.sh "$KEYS" "$SEED" > "$RUN/out" 2>&1
STATUS=$?

LOG="$RUN/game/logs/errors.log"
[ -f "$LOG" ] || {
    echo "INCONCLUSIVE: the run logged nothing at all (exit $STATUS)."
    echo "The probe reports through Error(), so an empty log means it never ran."
    sed -n '/--- after the session ---/,$p' "$RUN/out"
    exit 2
}

# Drop the indented backtrace blocks headless.sh attaches to a first
# occurrence; they quote the message text and would be counted twice.
grep -v '^    ' "$LOG" > "$RUN/lines"

if ! grep -q 'QUIET_PROBE:' "$RUN/lines"; then
    echo "INCONCLUSIVE: the probe never ran. Is Registry::QuietProbe() still"
    echo "called from Game::Play(), and does this build contain it?"
    exit 2
fi

if grep -q 'QUIET_PROBE: INCONCLUSIVE' "$RUN/lines"; then
    echo "INCONCLUSIVE: this seed's registry had no gap in it, so there was no"
    echo "dead handle to look up. Try another seed: $0 <seed>"
    grep 'QUIET_PROBE' "$RUN/lines"
    exit 2
fi

FAIL=0

# 1. live handle
if ! grep -q 'QUIET_PROBE: live=.* resolves=1 agree=1' "$RUN/lines"; then
    echo "FAIL: Get() and GetQuiet() disagree on a live handle, or neither"
    echo "      resolved it. They must be the same lookup."
    grep 'QUIET_PROBE: live=' "$RUN/lines"
    FAIL=1
fi

DEAD="$(sed -n 's/.*QUIET_PROBE: calling Get(\([0-9]*\)) now.*/\1/p' "$RUN/lines" | head -1)"
[ -n "$DEAD" ] || { echo "INCONCLUSIVE: the probe did not name its dead handle."; exit 2; }

# 2. dead handle resolves to nothing, both ways
if ! grep -q "QUIET_PROBE: GetQuiet($DEAD) resolves=0" "$RUN/lines"; then
    echo "FAIL: GetQuiet($DEAD) resolved a handle that does not exist."
    FAIL=1
fi
if ! grep -q "QUIET_PROBE: Get($DEAD) resolves=0" "$RUN/lines"; then
    echo "FAIL: Get($DEAD) resolved a handle that does not exist."
    FAIL=1
fi

# 3. GetQuiet said nothing. Proved by position: count the invalid-handle lines
#    for this handle that fall between the probe's first line and its "calling
#    Get() now" line. Must be zero.
BEFORE="$(awk -v d="$DEAD" '
    /QUIET_PROBE: live=/          { inside = 1 }
    /QUIET_PROBE: calling Get\(/  { inside = 0 }
    inside && $0 ~ ("invalid object handle \\(" d "\\)") { n++ }
    END { print n + 0 }' "$RUN/lines")"
if [ "$BEFORE" -ne 0 ]; then
    echo "FAIL: GetQuiet($DEAD) logged $BEFORE invalid-handle line(s). It must"
    echo "      log none -- that is the entire reason it exists."
    FAIL=1
fi

# 4. Get() said it exactly once, after being called.
AFTER="$(awk -v d="$DEAD" '
    /QUIET_PROBE: calling Get\(/ { inside = 1; next }
    /QUIET_PROBE: Get\(.*done/   { inside = 0 }
    inside && $0 ~ ("invalid object handle \\(" d "\\)") { n++ }
    END { print n + 0 }' "$RUN/lines")"
if [ "$AFTER" -ne 1 ]; then
    echo "FAIL: Get($DEAD) logged $AFTER invalid-handle lines; expected exactly 1."
    if [ "$AFTER" -eq 0 ]; then
        echo "      Get() has lost its complaint. Every caller that relies on"
        echo "      that line to notice a stale handle is now silent."
    fi
    FAIL=1
fi

if [ "$FAIL" -ne 0 ]; then
    echo
    echo "--- what the probe logged ---"
    grep -E 'QUIET_PROBE|invalid object handle' "$RUN/lines"
    exit 1
fi

echo "PASS: seed $SEED, live handle $(sed -n 's/.*QUIET_PROBE: live=\([0-9]*\) .*/\1/p' "$RUN/lines" | head -1), dead handle $DEAD."
echo "      Get() and GetQuiet() agree; GetQuiet() logged nothing for the dead"
echo "      handle and Get() logged it exactly once."
exit 0
