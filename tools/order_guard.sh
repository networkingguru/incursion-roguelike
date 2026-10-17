#!/bin/bash
# gate: none the build runs it directly after -compile (inc-4320); the gate
# would have to build first. The append-only save format (docs/SAVE-SCHEMA-SPEC.md,
# Amendment 1) needs the check on every developer build, not only at landing.
#
# inc-4320. Run from the repository root after the module compiles. A resource
# or script variable that moved makes the build fail closed: a save written
# before the move would not load. Brian may approve one exact list for one bead;
# tools/approve_order_break.sh writes that approval, and the fixed path from
# tools/order_approval_path.sh (password database, never $HOME) is the only
# place it is read. No environment variable changes it.
#
# --module-root DIR passes through to the check, which measures the module in
# DIR instead of this checkout. --ledger FILE passes through too, so the check
# compares against FILE instead of the committed ledger. --bead ID names the
# bead whose approval to look for, instead of the current branch: a landing that
# runs the SHARED guard while on the bead's worktree branch (inc-fo8o) must
# still find the approval under the bead's own id. The build never passes any of
# these; the reproduction and tools/finish_bead.sh do.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CHECK=tools/resource_order_check.py

usage() {
    echo "usage: tools/order_guard.sh [--module-root DIR] [--ledger FILE] [--bead ID]" >&2
    exit 2
}

bead_arg=""
module_args=()
while [ "$#" -gt 0 ]; do
    case "$1" in
        --module-root)
            [ "$#" -ge 2 ] || usage
            module_args+=(--module-root "$2")
            shift 2
            ;;
        --ledger)
            [ "$#" -ge 2 ] || usage
            module_args+=(--ledger "$2")
            shift 2
            ;;
        --bead)
            [ "$#" -ge 2 ] || usage
            bead_arg="$2"
            shift 2
            ;;
        *)
            usage
            ;;
    esac
done

# Same pattern as tools/approve_order_break.sh: an approval is only ever looked
# up for a real bead id.
if [ -n "$bead_arg" ] && ! [[ "$bead_arg" =~ ^inc-[a-z0-9]+(\.[0-9]+)*$ ]]; then
    echo "refuse: '$bead_arg' is not a bead id (^inc-[a-z0-9]+(\\.[0-9]+)*\$)" >&2
    exit 2
fi

out="$(python3 "$CHECK" "${module_args[@]+${module_args[@]}}" 2>&1)"
rc=$?
case "$rc" in
    0)
        echo "order check: ok"
        exit 0
        ;;
    2)
        # The check could not measure (unbuilt binary, bad module root). That
        # is not "the order is broken": tell callers apart with exit 2.
        echo "$out"
        exit 2
        ;;
esac

# rc == 1: the module breaks the order rule. Look for Brian's approval.
if [ -n "$bead_arg" ]; then
    bead="$bead_arg"
else
    bead="$(git rev-parse --abbrev-ref HEAD)"
fi
approval="$(tools/order_approval_path.sh "$bead")"
hash_now="$(python3 "$CHECK" "${module_args[@]+${module_args[@]}}" --failure-hash 2>/dev/null || true)"

if [ -f "$approval" ]; then
    line1="$(sed -n '1p' "$approval")"
    line2="$(sed -n '2p' "$approval")"
    if [ "$line1" = "$bead" ] && [ -n "$hash_now" ] && [ "$line2" = "$hash_now" ]; then
        echo "order check: FAILED, but Brian approved this exact list for $bead"
        python3 "$CHECK" "${module_args[@]+${module_args[@]}}" --failures
        exit 0
    fi
    echo "an approval exists for $bead but for a different list of failures"
fi

python3 "$CHECK" "${module_args[@]+${module_args[@]}}" --failures
echo "A resource or script variable moved. Saves made before this build will"
echo "not load. Move the new entry to the END of its array or body."
echo "If the move is intended, Brian approves it by running:"
echo "    tools/approve_order_break.sh $bead"
exit 1
