#!/usr/bin/env bash
# gate: none tools/finish_bead.sh STEP 1 already refuses a dirty worktree at landing, and in the shared checkout untracked evidence is legitimate
# gate-fast: static, reads git status only, under a second
#
# Does this repository hold an untracked file?
#
# WHY THIS EXISTS. `git status --porcelain --untracked-files=all` lists a file
# with a `??` line. In a worktree an untracked file is either a reproduction
# that belongs in tools/ and must be committed, or a specimen that belongs in
# logs/ (ignored, so it never shows here) or in docs/evidence/<bead>/ of the
# shared checkout ~/Scripts/Incursion. A file left `??` in the worktree is
# neither, and tools/finish_bead.sh STEP 1 refuses it at landing. This check
# gives that refusal a fast, standalone form. It is `gate: none` because the
# shared checkout deliberately keeps untracked evidence, so the landing gate
# must not run it there; only the fast set does, and only from a worktree.
#
# Ignored files (logs/, __pycache__, build output) do not appear and are not
# the concern here.
#
# Exit: 0 no untracked file
#       1 at least one untracked file, listed on stdout
#       2 could not run git
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || { echo "COULD NOT MEASURE: cannot enter $ROOT" >&2; exit 2; }

command -v git >/dev/null 2>&1 || {
    echo "COULD NOT MEASURE: git is not on PATH" >&2
    exit 2
}

status="$(git status --porcelain --untracked-files=all 2>&1)" || {
    echo "COULD NOT MEASURE: git status failed: $status" >&2
    exit 2
}

untracked="$(printf '%s\n' "$status" | awk '/^\?\?/ { print substr($0, 4) }')"

if [ -z "$untracked" ]; then
    echo "PASS: no untracked file in the worktree"
    exit 0
fi

echo "FAIL: the worktree holds untracked file(s):"
printf '%s\n' "$untracked" | while IFS= read -r line; do
    printf '  %s\n' "$line"
done
echo
echo "A reproduction belongs in tools/ and is committed."
echo "A specimen (log, dump, save) belongs in logs/ or in"
echo "docs/evidence/<bead>/ in the shared checkout ~/Scripts/Incursion,"
echo "never in the worktree."
exit 1
