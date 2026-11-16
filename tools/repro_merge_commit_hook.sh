#!/usr/bin/env bash
# repro_merge_commit_hook.sh -- does .beads/hooks/pre-commit run the fast checks on a MERGE commit
# made by hand in a bead worktree? (inc-cjos0 gap 13a; .claude/rules/epic-branches.md)
#
# It builds a scratch repository under logs/ with a tiny stored family, a bead worktree and the
# real hook, fast_checks.sh and check_stored_values.py. Two merges of master into the bead branch:
#   RED   master added A_P = 3 and the bead added A_Q = 3 (one family value, two names): the
#         merge commit MUST be refused (hook exit 1).
#   GREEN master added A_R = 9: the merge commit MUST pass.
# Usage: tools/repro_merge_commit_hook.sh [path to a pre-commit hook; default .beads/hooks/pre-commit]
# Exit:  0 red refused and green passed   1 otherwise   2 could not build the scratch repository
#
# fact: the hook, fast_checks.sh and check_stored_values.py -- copied from this tree, read as files; no game run, no seed
# fact: the compiler -- clang++ at the flags of check_stored_values.py; a stub inc/Incursion.h; no randomness
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="${1:-$ROOT/.beads/hooks/pre-commit}"
[ -f "$HOOK" ] || { echo "no such hook: $HOOK" >&2; exit 2; }
mkdir -p "$ROOT/logs"
G() { git -C "$1" -c user.name=t -c user.email=t@t "${@:2}"; }
setup() { # a fresh scratch repository in S, with M (main) and W (bead worktree)
    S="$(mktemp -d "$ROOT/logs/merge-hook.XXXXXX")" || exit 2
    SCRATCH+=( "$S" )
    M="$S/main"; W="$S/wt"
    mkdir -p "$M/inc" "$M/tools" "$M/.beads/hooks"
    cp "$HOOK" "$M/.beads/hooks/pre-commit"; chmod +x "$M/.beads/hooks/pre-commit"
    for f in fast_checks.sh run_capped.py check_stored_values.py check_define_dups.py; do
        cp "$ROOT/tools/$f" "$M/tools/$f"
    done
    : > "$M/tools/retired_values.txt"
    printf '#include "Defines.h"\n' > "$M/inc/Incursion.h"
    {
        echo "// family: stati stored ordinal u8"
        echo "#define A_X 1"; echo "#define A_Y 2"
        for i in 1 2 3 4 5 6 7; do echo "#define A_PAD$i $((10 + i))"; done
        echo "#define A_END 30"
        echo "// end family: stati"
    } > "$M/inc/Defines.h"
    G "$M" init -q -b master || exit 2
    G "$M" add -A
    G "$M" -c core.hooksPath=/dev/null commit -qm base || exit 2
    G "$M" config core.hooksPath "$M/.beads/hooks"
    G "$M" worktree add -q "$W" -b bead || exit 2
}

try_merge() { # <label> <master edit sed> <bead edit sed> <want: refused|passed>
    local label="$1" want="$4" rc
    setup
    sed -i '' "$2" "$M/inc/Defines.h"
    G "$M" -c core.hooksPath=/dev/null commit -qam "master $label"
    sed -i '' "$3" "$W/inc/Defines.h"
    G "$W" -c core.hooksPath=/dev/null commit -qam "bead $label"
    G "$W" merge -q --no-commit master >/dev/null 2>&1
    ( cd "$W" && git -c user.name=t -c user.email=t@t commit -qm "merge master ($label)" ) >"$S/$label.out" 2>&1
    rc=$?
    if [ $rc -ne 0 ]; then got=refused; else got=passed; fi
    echo "$label: merge commit $got (exit $rc), wanted $want"
    [ "$got" = "$want" ] || FAIL=1
}
FAIL=0
SCRATCH=()
try_merge red   's/^#define A_X 1$/#define A_X 1\n#define A_P 3/' 's/^#define A_END 30$/#define A_END 30\n#define A_Q 3/' refused
try_merge green 's/^#define A_X 1$/#define A_X 1\n#define A_R 9/'  's/^#define A_END 30$/#define A_END 30\n#define A_S 40/' passed
[ $FAIL -eq 0 ] && { rm -rf "${SCRATCH[@]}"; echo "repro_merge_commit_hook: PASS"; } || echo "repro_merge_commit_hook: FAIL (scratch repositories and hook output under $ROOT/logs/merge-hook.*)"
exit $FAIL
