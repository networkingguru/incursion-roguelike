#!/usr/bin/env bash
# gate: live
#
# Does the build precheck behave the same with no git program as with no git history?
#
# build_macos.sh runs check_define_dups.py, check_stored_values.py and
# check_save_names.py before it compiles. On a source copy with no .git it expects
# exit 0, 2, 2 and goes on (inc-cjos0 gap 13b). A Debian image has no git program
# at all; the three checks MUST give the same exits there, with no traceback
# (bead inc-cf3k0). This check exports the working tree outside any checkout, runs
# the three with a PATH that holds only python3, then again with git on the PATH,
# and asserts exit 0, 2, 2 and no "Traceback" both times.
#
# RED: with the fix reverted, the no-git run crashes with exit 1 and a Traceback
# (FileNotFoundError: 'git').
#
# fact: the game, a seed, a character -- none read; the check runs three static python checks on an exported copy of the tree
# fact: the exported tree -- git ls-files of the worktree, copied to a fresh mktemp -d directory outside any checkout
# fact: the PATH -- built by the check: a directory holding a python3 symlink only, or the caller's PATH
#
# Usage: tools/check_precheck_no_git.sh
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2
command -v python3 >/dev/null 2>&1 || { echo "UNMEASURED: python3 is missing"; exit 2; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
EXPORT="$WORK/tree"
BIN="$WORK/bin"
mkdir -p "$EXPORT" "$BIN"
git ls-files -z | xargs -0 tar -cf - 2>/dev/null | tar -x -C "$EXPORT" \
    || { echo "UNMEASURED: could not export the tree"; exit 2; }
ln -s "$(command -v python3)" "$BIN/python3"

fail=0
run_all() {   # label, PATH
    local label="$1" path="$2" chk want rc out
    for chk in check_define_dups.py:0 check_stored_values.py:2 check_save_names.py:2; do
        want="${chk#*:}"; chk="${chk%%:*}"
        rc=0
        out="$(cd "$EXPORT" && PATH="$path" python3 "tools/$chk" 2>&1)" || rc=$?
        if [ "$rc" != "$want" ]; then
            echo "FAIL: [$label] $chk exit $rc, expected $want: $(printf '%s\n' "$out" | tail -1)"
            fail=1
        elif printf '%s' "$out" | grep -q Traceback; then
            echo "FAIL: [$label] $chk printed a Traceback"
            fail=1
        elif [ "$want" = 2 ] && [ "$label" = "no git" ] && ! printf '%s' "$out" | grep -qi "git is not installed"; then
            echo "FAIL: [$label] $chk exit 2 but no UNMEASURED line says git is not installed"
            fail=1
        fi
    done
}
run_all "no git" "$BIN"
run_all "git present" "$PATH"
[ "$fail" = 0 ] && echo "PASS: the build precheck gives exit 0, 2, 2 with and without a git program"
exit "$fail"
