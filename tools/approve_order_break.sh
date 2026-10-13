#!/bin/bash
# gate: none Brian runs it by hand to approve one bead's exact order break; no
# agent runs it, and it writes outside every worktree.
#
# inc-4320. Usage: tools/approve_order_break.sh <bead-id>
# Typing the command is the approval. It refuses any bead id that is not
# ^inc-[a-z0-9]+(\.[0-9]+)*$ and any bead with no worktree, measures the bead's
# own module, and writes the fixed approval file order_guard.sh reads. That path
# comes from tools/order_approval_path.sh (the password database, never $HOME):
#   <home>/.config/incursion/order-approvals/<bead>
# line 1 is the bead, line 2 the failure hash, then the failure lines.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECK="$ROOT/tools/resource_order_check.py"

usage() {
    echo "usage: tools/approve_order_break.sh <bead-id>" >&2
    exit 2
}

[ "$#" -eq 1 ] || usage
bead="$1"

case "$bead" in
    inc-*) ;;
    *) echo "refuse: '$bead' is not a bead id (^inc-[a-z0-9]+(\\.[0-9]+)*\$)" >&2
       exit 2 ;;
esac
[[ "$bead" =~ ^inc-[a-z0-9]+(\.[0-9]+)*$ ]] || {
    echo "refuse: '$bead' is not a bead id" >&2
    exit 2
}

worktree="$HOME/Scripts/Incursion-$bead"
if [ ! -d "$worktree" ] || [ ! -f "$worktree/mod/Incursion.Mod" ]; then
    echo "refuse: no bead worktree with a module at $worktree" >&2
    exit 2
fi

failures="$(cd "$worktree" && python3 tools/resource_order_check.py --failures)"
frc=$?
hash="$(cd "$worktree" && python3 tools/resource_order_check.py --failure-hash)"
hrc=$?

case "$frc" in
    0)
        echo "nothing to approve"
        exit 0
        ;;
    2)
        echo "$failures"
        exit 2
        ;;
esac
[ "$hrc" = 1 ] || {
    echo "refuse: the failure hash could not be measured (exit $hrc)" >&2
    exit 2
}

file="$("$ROOT/tools/order_approval_path.sh" "$bead")"
dir="$(dirname "$file")"
mkdir -p "$dir"
{
    printf '%s\n' "$bead"
    printf '%s\n' "$hash"
    printf '%s\n' "$failures"
} > "$file"
chmod 600 "$file"

echo "Approved for $bead:"
printf '%s\n' "$failures"
exit 0
