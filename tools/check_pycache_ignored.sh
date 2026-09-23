#!/bin/bash
# gate: cheap
#
# Does running a Python check leave the tree clean? A check that imports a
# helper module writes tools/__pycache__/ unless it passes `python3 -B`, and
# tools/finish_bead.sh refuses to land a worktree holding any untracked file.
# So a bead that ran one Python check could not land. This proves the
# __pycache__/ line in .gitignore covers that litter (inc-dz74).
#
#   tools/check_pycache_ignored.sh              exit 0 clean, 1 dirty, 2 could not establish
#   tools/check_pycache_ignored.sh --prove-red  remove the line from a scratch copy,
#                                               run the same probe, require exit 1
#
# THE PROBE. tools/check_ability_descs.sh imports tools/ability_descs_lib.py
# WITHOUT `-B`, so it writes tools/__pycache__/ability_descs_lib.*.pyc. That is
# the real check, run as a check, not a synthetic import. This script does not
# pass `-B` to it -- the flag is the thing under test elsewhere and must stay
# where it is (tools/check_save_pad_rows.sh). If the probe leaves no .pyc the
# run proved nothing, so it exits 2 "could not establish" rather than green.
#
# --prove-red copies .gitignore and the probe's files into a fresh `git init`
# scratch directory, strips the __pycache__/ line from the COPY, and requires
# the same probe to leave the tree dirty there (exit 1). It never edits the real
# .gitignore, and it never uses `git worktree add`, which would write into the
# shared .git directory.
#
# Exit: 0 clean; 1 a .pyc left tools/__pycache__/ visible to git; 2 could not
#       establish (no python3, no .pyc produced, scratch repo could not be built).
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

MARK='__pycache__/'
PROBE="tools/check_ability_descs.sh"
PYC_GLOB="ability_descs_lib"

command -v python3 >/dev/null || { echo "COULD NOT ESTABLISH: python3 missing"; exit 2; }

# Run the probe in place. Echoes the .pyc path it expects to find, or nothing.
run_probe() {
    rm -f tools/__pycache__/"$PYC_GLOB".*.pyc 2>/dev/null
    "$PROBE" >/dev/null 2>&1
    # A non-zero probe exit is not this check's verdict -- the .pyc is written
    # by the import regardless -- but report it so a red is not misread.
    printf '%s\n' "$?"
}

# Use git's own view: an ignored file prints nothing under --untracked-files=all.
#
# Only the `??` lines are litter from running a check. A `D` line is a staged
# deletion of a file that was once tracked (inc-dz74 removes flickerscan's
# .pyc); that is a deliberate tree change, not the litter this check guards
# against, and it clears the moment the bead commits. Asserting on it would
# make this check red for a reason it does not name.
untracked_pycache() {
    git status --porcelain --untracked-files=all -- tools/__pycache__ 2>/dev/null \
        | grep '^??' || true
}

run() {
    local probe_rc pyc dirty
    probe_rc="$(run_probe)"
    pyc="$(ls tools/__pycache__/"$PYC_GLOB".*.pyc 2>/dev/null | head -1)"
    if [ -z "$pyc" ]; then
        echo "COULD NOT ESTABLISH: $PROBE left no tools/__pycache__/$PYC_GLOB.*.pyc"
        echo "(it exited $probe_rc). Nothing was proved."
        return 2
    fi
    dirty="$(untracked_pycache)"
    if [ -n "$dirty" ]; then
        echo "FAIL: $pyc is untracked and not ignored; git sees it:"
        printf '%s\n' "$dirty"
        return 1
    fi
    echo "PASS: $PROBE wrote $pyc, and .gitignore kept it invisible to git"
    return 0
}

# --- --prove-red -------------------------------------------------------------
# Same probe, but in a scratch repository whose .gitignore has had the
# __pycache__/ line deleted. The probe must then leave a file git can see.
prove_red() {
    local tmp probe_rc pyc dirty
    tmp="$(mktemp -d "${TMPDIR:-/tmp}/pycache-ignored.XXXXXX")" || {
        echo "COULD NOT ESTABLISH: mktemp failed"; return 2; }
    # Expanded now, not at exit: $tmp is local and gone by the time EXIT fires.
    trap "rm -rf '$tmp'" EXIT

    mkdir -p "$tmp/tools" || return 2
    [ -f .gitignore ] || { echo "COULD NOT ESTABLISH: no .gitignore"; return 2; }
    grep -vF "$MARK" .gitignore > "$tmp/.gitignore"
    cp -f "$PROBE" "$tmp/tools/" || return 2
    cp -f tools/ability_descs_lib.py "$tmp/tools/" || return 2
    cp -f tools/ability_descs.live "$tmp/tools/" 2>/dev/null
    cp -f tools/ability_descs.exempt "$tmp/tools/" 2>/dev/null
    mkdir -p "$tmp/src" "$tmp/lib"
    cp -f src/Tables.cpp "$tmp/src/" 2>/dev/null

    git -C "$tmp" init -q || { echo "COULD NOT ESTABLISH: git init failed"; return 2; }

    ( cd "$tmp" && "./$(printf '%s' "$PROBE")" >/dev/null 2>&1 )
    probe_rc=$?
    pyc="$(ls "$tmp"/tools/__pycache__/"$PYC_GLOB".*.pyc 2>/dev/null | head -1)"
    if [ -z "$pyc" ]; then
        echo "COULD NOT ESTABLISH: the scratch probe left no .pyc (exited $probe_rc)."
        return 2
    fi
    dirty="$(git -C "$tmp" status --porcelain --untracked-files=all -- tools/__pycache__ 2>/dev/null \
        | grep '^??' || true)"
    if [ -z "$dirty" ]; then
        echo "FAIL: with __pycache__/ deleted from .gitignore the scratch tree is"
        echo "still clean, so this check cannot be shown red. Nothing was proved."
        return 1
    fi
    echo "PASS: without __pycache__/ git sees the litter, so this check can be red:"
    printf '%s\n' "$dirty"
    return 0
}

if [ "${1:-}" = "--prove-red" ]; then
    prove_red
    exit $?
fi

run
exit $?
