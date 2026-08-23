#!/bin/bash
# Every printf-style format string in the engine agrees with its arguments.
#
# Usage: tools/check_format_strings.sh              # check
#        tools/check_format_strings.sh --baseline   # re-record the known backlog
# Exit:  0 the warning count equals the baseline
#        1 the count is above the baseline (a new defect) or below it (a stale
#          baseline that nobody lowered)
#        2 nothing was measured, and the reason is printed
#
# WHY THIS EXISTS. The engine builds nearly every string it shows through
# Format() in src/Base.cpp, which is a plain vsprintf, and reports nearly every
# internal fault through Error(), which is a plain vsnprintf. Both are varargs,
# so a format string that disagrees with its arguments compiles without
# complaint and misbehaves at run time: an argument short, vsprintf reads
# whatever the register file holds next and prints it.
#
# NOTHING CAUGHT THESE FOR TWENTY YEARS, and the reason is one flag.
# build_macos.sh compiled with -w, which suppresses every warning, so the 58
# defects inc-9t6 lists were invisible on this machine, and Windows never had
# the attribute to warn from. The two declarations that make the compiler able
# to see them at all are:
#
#     inc/Base.h:163      Format()   __attribute__((format(printf,1,2)))
#     inc/Globals.h:10    Error()    __attribute__((format(printf,1,2)))
#
# THE FLAG ORDER MATTERS AND IS NOT OBVIOUS. clang's -w is not an ordinary -W
# option that a later one overrides. It sets SuppressAllDiagnostics on the
# diagnostic engine, and nothing after it revives a warning: -w -Wformat prints
# nothing, and so does -w -Werror=format. The suggested incantation
# EXTRA_CXXFLAGS="-Wno-everything -Wformat" therefore measures nothing and
# reports a clean tree. -w has to be REPLACED, which is what the WARN_FLAGS
# knob in build_macos.sh exists for.
#
# WHY -Wformat-security IS EXCLUDED. It fires on a non-literal format string --
# Format(s) where s is a runtime String -- and 402 of its 447 hits are in
# lib/dispatch.h, which the resource compiler generates. That is a real but
# entirely different problem with a different fix, and mixing it in here would
# bury the arity defects this check is for. The count is printed for
# information and never gates.
#
# WHY A BASELINE AND NOT A HARD ZERO. The count is zero today, so the two
# behave identically today. The baseline is a file rather than a literal so the
# next person who fixes an engine wart that resurrects a warning class -- or
# who regenerates src/yygram.cpp and src/Tokens.cpp from lang/ with a tool that
# does not carry our fixes -- can record the backlog and keep the check green
# while working it down, instead of deleting the check. Going BELOW the
# baseline fails too: a suppression nobody lowered is how a check quietly stops
# checking.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
BASELINE="tools/format_strings.baseline"

command -v clang++ > /dev/null || {
    echo "COULD NOT MEASURE: clang++ is not on PATH."
    exit 2
}

# The attribute is the whole oracle. Without it the build is silent and this
# check would report a clean tree no matter what the code said.
for decl in "inc/Base.h:Format" "inc/Globals.h:Error"; do
    f="${decl%%:*}"; sym="${decl##*:}"
    grep -q "$sym(.*\.\.\..*format(printf,1,2)" "$f" || {
        echo "COULD NOT MEASURE: $f has no format(printf,1,2) attribute on $sym()."
        echo "Without it clang cannot see a single one of these defects."
        exit 2
    }
done

grep -q 'WARN_FLAGS' build_macos.sh || {
    echo "COULD NOT MEASURE: build_macos.sh has no WARN_FLAGS knob, so its -w"
    echo "cannot be replaced and no warning can reach us."
    exit 2
}

LOG="$(mktemp)"
trap 'rm -f "$LOG"' EXIT

# EXTRA_CXXFLAGS must be non-empty so build_macos.sh takes its instrumented
# path: a private object directory, and no rewrite of the shared
# mod/Incursion.Mod that the ordinary binary has to be able to load.
echo "--- building with -Wformat (this takes a minute) ---"
WARN_FLAGS="-Wno-everything -Wformat" \
EXTRA_CXXFLAGS="-DFMTAUDIT" \
OUT=incursion-fmtcheck BACKEND=posix ./build_macos.sh > "$LOG" 2>&1
BUILD=$?

if [ "$BUILD" -ne 0 ]; then
    echo "COULD NOT MEASURE: the instrumented build failed, so no count is"
    echo "trustworthy. A build that does not finish is not a smaller warning"
    echo "count. Last lines:"
    tail -20 "$LOG"
    exit 2
fi

# A build that compiled nothing would report zero warnings and look perfect.
COMPILED="$(grep -c -- '--- compiling Incursion ---' "$LOG")"
[ "$COMPILED" -ge 1 ] || {
    echo "COULD NOT MEASURE: the build never reached the compile step."
    exit 2
}

# One build answers both questions: -Wformat turns -Wformat-security on with
# it, so the two classes are separated here by their tag, not by two builds.
COUNT="$(grep 'warning:.*\[-Wformat' "$LOG" | grep -vc '\[-Wformat-security\]')"
SECURITY="$(grep -c 'warning:.*\[-Wformat-security\]' "$LOG")"

if [ "${1:-}" = "--baseline" ]; then
    echo "$COUNT" > "$BASELINE"
    echo "recorded baseline: $COUNT"
    exit 0
fi

[ -f "$BASELINE" ] || {
    echo "COULD NOT MEASURE: $BASELINE is missing. Record it with --baseline."
    exit 2
}
WANT="$(tr -dc '0-9' < "$BASELINE")"
[ -n "$WANT" ] || {
    echo "COULD NOT MEASURE: $BASELINE holds no number."
    exit 2
}

echo
echo "format-string warnings: $COUNT   baseline: $WANT"
echo "(-Wformat-security, not gated, different defect: $SECURITY)"

if [ "$COUNT" -gt "$WANT" ]; then
    echo
    echo "=== FAIL: $((COUNT - WANT)) format-string warning(s) above the baseline ==="
    grep 'warning:.*\[-Wformat' "$LOG" | grep -v '\[-Wformat-security\]' | sort -u
    echo
    echo "Fix the call, or -- only if it is genuinely correct and the compiler is"
    echo "wrong -- file it and raise the baseline with --baseline."
    exit 1
fi

if [ "$COUNT" -lt "$WANT" ]; then
    echo
    echo "=== FAIL: stale baseline ==="
    echo "$((WANT - COUNT)) fewer warning(s) than $BASELINE tolerates. The"
    echo "backlog shrank and nobody lowered it, so the check has been passing"
    echo "on room it no longer needs. Re-record it:"
    echo "    tools/check_format_strings.sh --baseline"
    exit 1
fi

echo "PASS"
exit 0
