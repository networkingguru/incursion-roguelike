#!/bin/bash
# Gate: the tree must carry NO high-confidence uninitialised-variable reads.
#
# WHAT IT DEFENDS. clang groups "read of a variable before it is assigned" into
# three warning tiers. This gate holds the two that are reliable:
#
#   -Wuninitialized            the value is uninitialised on the ONLY path that
#                              reaches the use; clang is certain.
#   -Wsometimes-uninitialized  a specific branch reaches the use with the
#                              variable still unset; clang names the branch.
#
# It deliberately does NOT hold -Wconditional-uninitialized, clang's third,
# "may be" tier. That tier fires whenever the compiler cannot prove a guard
# covers every path -- most often because a callee's return domain or a pair of
# correlated conditions is opaque to it -- so it is heavily false-positive and a
# blanket initialise-to-silence over it would HIDE the very reads this gate is
# meant to surface, substituting a defined-but-possibly-wrong value. The ~69
# -Wconditional sites are a separate, per-site audit; see the sweep in the
# inc-5aw6 / inc-l796 / inc-5yb work.
#
# HOW IT BUILDS. It reuses build_macos.sh's own per-file flags through the
# WARN_FLAGS override (which REPLACES the ordinary -w), so a new source file or
# a changed compile line is covered with no second flag list to keep in step.
# EXTRA_CXXFLAGS is set so the build takes the instrumented path: its own object
# directory, and no rewrite of the shared mod/Incursion.Mod. BACKEND=posix
# needs neither SDL nor a display. The C files keep their hardcoded -w -- the
# reads this gate defends are all in C++.
#
# WHY COMPILER=no (the shipping surface). This gate audits the code that ships
# to a player. The shipping build drops four sources -- RComp, Art, yygram and
# Tokens (build_macos.sh SKIP_SOURCES) -- which are the resource compiler, the
# GPLv2 ACCENT runtime, and the flex/ACCENT-GENERATED parser. A generated
# parser carries its own uninitialised-read (lang/Grammar.acc:1801 'b',
# inc-nksm), but it is not the game and no released binary contains it, so
# gating on it would block on code no player runs. COMPILER=no needs
# mod/Incursion.Mod to exist already; an ordinary ./build_macos.sh produces it.
#
# WHY IT MATTERS ON THIS ENGINE. A read of an uninitialised local is undefined
# behaviour. clang happens to tolerate most of these today, but an optimiser
# change, a code motion, or the GCC -O2 build already targeted for the Steam
# Deck's second toolchain can turn any of them into a wrong value or a crash --
# inc-nw0v was exactly this class, one constructor over. This gate keeps a NEW
# one from landing unseen.
#
# HOW TO PROVE IT BITES. Revert any one of the six fixes it currently keeps
# green (e.g. put src/Create.cpp's `bool found = false;` back to `bool found;`)
# and run this again: it FAILS and names the file and line.
#
# Usage: tools/check_uninit_reads.sh   (exits 0 on pass, 1 on fail,
#                                        2 on could-not-measure)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

WARN="-Wuninitialized -Wsometimes-uninitialized"
LOG="$(mktemp)"
trap 'rm -f "$LOG"' EXIT

# A distinct OUT and a non-empty EXTRA_CXXFLAGS keep this build's objects and
# binary out of the ordinary build/ and out of the shared module.
WARN_FLAGS="$WARN" EXTRA_CXXFLAGS="-DUNINIT_GATE" OUT=incursion-uninitgate \
    BACKEND=posix COMPILER=no ./build_macos.sh >"$LOG" 2>&1
rc=$?

if [ "$rc" -ne 0 ]; then
    echo "SKIP: the gate build did not complete (exit $rc)"
    echo "--- tail of build log ---"
    tail -20 "$LOG"
    exit 2
fi

# One line per offending use, e.g.
#   src/<file>.cpp:<line>:4: warning: variable 'x' ... [-Wsometimes-uninitialized]
# The placeholders are deliberate. A plausible-looking file:line in a comment is
# read as a citation by tools/check_doc_freshness.sh, which then reports a
# defect for a file that was never meant to exist.
HITS="$(grep -E "warning: variable .*\[-W(sometimes-)?uninitialized\]" "$LOG" | sort -u)"

if [ -n "$HITS" ]; then
    echo "FAIL: high-confidence uninitialised reads present:"
    echo "$HITS"
    exit 1
fi

echo "PASS: no -Wuninitialized or -Wsometimes-uninitialized reads in the tree"
exit 0
