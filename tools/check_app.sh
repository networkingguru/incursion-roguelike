#!/bin/bash
# Verify that Incursion.app is one a stranger can download and double-click.
#
# THIS GATE EXISTS BECAUSE THE PREVIOUS TWO DID NOT CATCH WHAT SHIPPED. Twice.
#
#   * inc-tm4: the folder passed every check and could not load its own module,
#     because the checks inspected the artifact's CONTENTS and never ran it.
#   * inc-g1y: the folder was correctly signed and correctly notarised and still
#     refused to launch for anyone who downloaded it, because the checks ran
#     against local unquarantined files -- the one path no downloader takes.
#
# So the two rules here are: ASK THE BINARY, not the source tree; and ASSESS A
# QUARANTINED COPY, not the build output. Checks 5 and 6 are the ones that would
# have failed on each of those releases.
#
# Usage: tools/check_app.sh <path to Incursion.app>   (exits 0 on pass, 1 on fail)
set -uo pipefail

APP="${1:-}"
if [ -z "$APP" ] || [ ! -d "$APP" ]; then
    echo "usage: tools/check_app.sh <path to Incursion.app>"
    exit 1
fi

APP="$(cd "$APP" && pwd)"
LAUNCHER="$APP/Contents/MacOS/Incursion"
GAME="$APP/Contents/MacOS/incursion-game"
FAIL=0
note_fail() { echo "FAIL: $1"; FAIL=1; }

# Run a command with a hard ceiling, because macOS ships no timeout(1) and a
# gate that can hang is worse than no gate at all. The first version of this
# script wedged a release build for 46 minutes: it exec'd a binary inside a
# QUARANTINED bundle copy, and syspolicyd blocked waiting for a consent dialog
# that nothing in a headless run will ever click. Never exec anything out of a
# quarantined copy -- assess it with spctl, which answers without blocking.
# Returns 124 on timeout, otherwise the command's own status.
run_bounded() {
    local secs="$1"; shift
    if [ -n "${BOUNDED_OUT:-}" ]; then
        "$@" >"$BOUNDED_OUT" 2>/dev/null &
    else
        "$@" >/dev/null 2>&1 &
    fi
    local pid=$! i=0
    while [ "$i" -lt "$secs" ]; do
        kill -0 "$pid" 2>/dev/null || { wait "$pid"; return $?; }
        sleep 1
        i=$((i + 1))
    done
    kill -9 "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
    return 124
}

# --- 1. the bundle is shaped like a bundle -----------------------------------
for f in Contents/Info.plist Contents/MacOS/Incursion Contents/MacOS/incursion-game \
         Contents/Resources/mod/Incursion.Mod Contents/Resources/fonts/8x8.png \
         Contents/Resources/Options.Dat Contents/Resources/Incursion-macOS.txt; do
    [ -e "$APP/$f" ] || note_fail "missing from the bundle: $f"
done
[ "$FAIL" -eq 0 ] && echo "PASS: bundle layout is complete"

# --- 2. the GPLv2 resource compiler must not be in the shipped binary --------
# src/Art.cpp:2-7 forbids distributing it. Do NOT grep for 'accent': no symbol
# carries that word, so it reports 0 either way.
ACCENT="$(nm "$GAME" 2>/dev/null | grep -c 'yyparse\|yyselect\|yymallocerror')"
if [ "$ACCENT" -ne 0 ]; then
    note_fail "game binary carries $ACCENT ACCENT symbol(s); not built with COMPILER=no"
else
    echo "PASS: no ACCENT runtime in the shipped binary"
fi

# --- 3. every load path is an OS library or inside the bundle ----------------
for bin in "$GAME" "$LAUNCHER"; do
    STRAY="$(otool -L "$bin" | tail -n +2 | awk '{print $1}' \
             | grep '^/' | grep -v '^/usr/lib/' | grep -v '^/System/Library/')"
    if [ -n "$STRAY" ]; then
        note_fail "$(basename "$bin") loads libraries from outside the OS:"
        echo "$STRAY" | sed 's/^/    /'
    fi
done
for ref in $(otool -L "$GAME" | tail -n +2 | awk '{print $1}' | grep '^@executable_path/'); do
    f="$APP/Contents/MacOS/${ref#@executable_path/}"
    [ -f "$f" ] || note_fail "game wants $ref but $f is missing"
done
[ "$FAIL" -eq 0 ] && echo "PASS: library paths all resolve inside the bundle or the OS"

# --- 4. the binary can READ the module it ships with ------------------------
# inc-tm4. Ask the binary; a check that recomputed the digest from the source
# tree would agree with itself and pass while the artifact stayed broken.
STAMP_FILE="$(mktemp)"
BOUNDED_OUT="$STAMP_FILE" run_bounded 30 "$GAME" -formatid
STAMP_BIN="$(tr -d '\r' < "$STAMP_FILE" | head -1)"
rm -f "$STAMP_FILE"
STAMP_MOD="$(dd if="$APP/Contents/Resources/mod/Incursion.Mod" bs=1 skip=4 count=10 2>/dev/null | tr -d '\0')"
if [ -z "$STAMP_BIN" ]; then
    note_fail "game binary does not answer -formatid; the module cannot be verified"
elif [ "$STAMP_BIN" != "$STAMP_MOD" ]; then
    note_fail "the binary cannot load its own module: demands $STAMP_BIN, module carries $STAMP_MOD"
else
    echo "PASS: binary and module agree on the save layout ($STAMP_BIN)"
fi

# --- 5. GATEKEEPER MUST ACCEPT IT ------------------------------------------
# inc-g1y. The previous release failed exactly here and nothing asked.
if ! codesign --verify --strict --deep --verbose=2 "$APP" >/dev/null 2>&1; then
    note_fail "the bundle's signature does not verify"
else
    echo "PASS: bundle signature verifies strictly"
fi

SPCTL="$(spctl -a -t exec -vvv "$APP" 2>&1)"
if echo "$SPCTL" | grep -q "accepted"; then
    echo "PASS: Gatekeeper accepts the bundle for launch"
else
    note_fail "Gatekeeper REJECTS the bundle -- a downloader cannot launch it:"
    echo "$SPCTL" | sed 's/^/    /'
    echo "      This is inc-g1y. A bare executable produces 'does not seem to be"
    echo "      an app'; an unsigned or unnotarised bundle produces a rejection"
    echo "      too. Both mean the release must not go out."
fi

# --- 6. THE QUARANTINED PATH, WHICH IS THE ONLY ONE A USER TAKES -----------
# Everything above can pass on a local build and still fail after a download,
# because a downloaded file carries com.apple.quarantine and is assessed
# differently. So do that assessment here rather than discovering it from a bug
# report.
QDIR="$(mktemp -d)"
cp -R "$APP" "$QDIR/" 2>/dev/null
QAPP="$QDIR/$(basename "$APP")"
if [ ! -d "$QAPP" ]; then
    note_fail "could not copy the bundle to test the quarantined path"
else
    xattr -w com.apple.quarantine "0083;00000000;check_app;" "$QAPP" 2>/dev/null
    QSPCTL="$(spctl -a -t exec -vvv "$QAPP" 2>&1)"
    if echo "$QSPCTL" | grep -q "accepted"; then
        echo "PASS: Gatekeeper accepts it with the quarantine flag set"
    else
        note_fail "Gatekeeper rejects the QUARANTINED copy, which is what a user has:"
        echo "$QSPCTL" | sed 's/^/    /'
    fi

    # --- 7. nothing may write inside the bundle ----------------------------
    # A signed bundle that writes into itself breaks its own signature on first
    # run, which is the same "modified or damaged" refusal by another route. Run
    # the launcher against a throwaway HOME and check the signature again.
    #
    # Deliberately the ORIGINAL bundle, not the quarantined copy. Exec'ing a
    # quarantined binary blocks on a Gatekeeper consent dialog that never comes
    # in a headless run -- that wedged this script for 46 minutes on its first
    # outing. Quarantine changes whether macOS will LAUNCH the app, which check 6
    # already answers with spctl; it does not change where the app writes, which
    # is all this check is about.
    FAKEHOME="$QDIR/home"
    mkdir -p "$FAKEHOME"
    if ! HOME="$FAKEHOME" run_bounded 30 "$LAUNCHER" -formatid; then
        note_fail "the launcher did not exit cleanly within 30s (hung, crashed, or refused)"
    fi
    if [ ! -d "$FAKEHOME/Library/Application Support/Incursion" ]; then
        note_fail "the launcher did not create its writable directory under a fresh HOME"
    elif [ ! -L "$FAKEHOME/Library/Application Support/Incursion/mod" ]; then
        note_fail "the launcher did not link mod/ into the writable directory"
    elif [ ! -f "$FAKEHOME/Library/Application Support/Incursion/Options.Dat" ]; then
        note_fail "the launcher did not seed Options.Dat"
    else
        echo "PASS: launcher builds its writable directory outside the bundle"
    fi

    if codesign --verify --strict --deep "$APP" >/dev/null 2>&1; then
        echo "PASS: the bundle's signature survives a run"
    else
        note_fail "running the app BROKE its own signature -- something wrote inside the bundle"
    fi
fi
rm -rf "$QDIR"

echo
if [ "$FAIL" -ne 0 ]; then
    echo "APP REJECTED: $APP"
    exit 1
fi
echo "APP OK: $APP"
exit 0
