#!/bin/bash
# Refuse to package a dirty working tree, and print the commit being packaged.
#
# WHY. Packagers stage the WORKING-TREE content of tracked files, so an
# uncommitted edit rides into the release. On 2026-09-11 a release shipped
# another session's uncommitted files exactly this way. This guard makes the
# state explicit and refuses by default: a release is a commit, not a tree.
#
# Untracked files are NOT a failure -- they do not reach the payload. Staged and
# unstaged edits to tracked files ARE. Set INCURSION_ALLOW_DIRTY=1 to ship them
# deliberately; the guard then warns and passes.
#
# Run from the repo root (not sourced):
#     tools/require_clean_tree.sh
#     INCURSION_ALLOW_DIRTY=1 tools/require_clean_tree.sh
#
# Exit: 0 clean, or dirty with INCURSION_ALLOW_DIRTY=1; 1 otherwise, including
# when the state cannot be established (no work tree, git failure).
#
# Bead inc-iezk
set -euo pipefail

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "FAIL: not inside a git work tree; cannot establish what would be packaged"
    exit 1
fi

HEAD_SHA="$(git rev-parse HEAD 2>/dev/null)" || {
    echo "FAIL: cannot read HEAD; cannot establish the packaged commit"
    exit 1
}
SUBJECT="$(git log -1 --format=%s 2>/dev/null)" || {
    echo "FAIL: cannot read the HEAD commit subject"
    exit 1
}
echo "packaging HEAD $HEAD_SHA $SUBJECT"

DIRTY="$(git status --porcelain --untracked-files=no 2>/dev/null)" || {
    echo "FAIL: git status failed; cannot establish the tree state"
    exit 1
}

if [ -z "$DIRTY" ]; then
    echo "tree: clean"
    exit 0
fi

if [ "${INCURSION_ALLOW_DIRTY:-}" = "1" ]; then
    echo "WARNING: packaging uncommitted changes (INCURSION_ALLOW_DIRTY=1):"
    printf '%s\n' "$DIRTY"
    exit 0
fi

echo "FAIL: the tree has uncommitted changes to tracked files:"
printf '%s\n' "$DIRTY"
echo "Commit or stash them, package from a clean worktree at the intended commit,"
echo "or set INCURSION_ALLOW_DIRTY=1 to ship them deliberately."
exit 1
