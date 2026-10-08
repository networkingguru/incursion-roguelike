#!/bin/bash
# Repro for inc-1boo: the bead-id pattern must accept any number of dotted
# numeric suffixes, and refuse malformed ids.
#
#   tools/repro_inc_1boo.sh
#
# Calls each script's is_bead_id in isolation -- no branch or worktree is
# created. Prints ACCEPTED/REFUSED per id and exits 1 if any is wrong.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Extract an is_bead_id function from a script and call it. The function body is
# the three-line definition that follows the is_bead_id() header.
check_script() { # check_script <script> <grep-variant>
    local script="$1"
    printf '=== %s ===\n' "${script#"$ROOT"/}"
    (
        eval "$(sed -n '/^is_bead_id() {/,/^}/p' "$script")"
        local id bad=0
        for id in inc-tek.8.3 inc-a.1.2.3; do
            if is_bead_id "$id"; then echo "  ACCEPTED $id"; else echo "  REFUSED  $id (WRONG)"; bad=1; fi
        done
        for id in inc-tek. inc-tek..3 inc-tek.8.a INC-tek not-a-bead-id; do
            if is_bead_id "$id"; then echo "  ACCEPTED $id (WRONG)"; bad=1; else echo "  REFUSED  $id"; fi
        done
        exit "$bad"
    )
}

rc=0
check_script "$ROOT/tools/worktree.sh" || rc=1
check_script "$ROOT/tools/finish_bead.sh" || rc=1
check_script "$ROOT/tools/check_orphan_branches.sh" || rc=1

if [ "$rc" -eq 0 ]; then echo "REPRO OK: all three agree"; else echo "REPRO FAIL: a script disagrees"; fi
exit "$rc"
