#!/usr/bin/env bash
#
# Does every new commit subject open with one of the seven lanes, and does every
# rules: commit name a design bead?
#
#   tools/check_commit_lane.sh              every commit since the rule started
#   tools/check_commit_lane.sh --since REF  an explicit range
#   tools/check_commit_lane.sh --selftest   prove this script still bites
#
# THE RULE is in AGENTS.md, "Classifying a change". Seven lanes: fix, port, data,
# rules, graphics, docs, tools. A rules: commit changes how the game plays, so
# its body must name the bead that holds the ruling.
#
# WHY A START SHA AND NOT A DATE. 807 commits predate the rule and none of them
# carries a lane. Relabelling history is not possible, and failing on it would
# make this check useless from its first run. tools/commit_lane.since holds the
# sha the rule starts after. Everything at or before it is exempt, forever.
#
# Exit: 0 every commit in range is classified
#       1 at least one is not
#       2 could not measure

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LANES='fix|port|data|rules|graphics|docs|tools'
SINCE_FILE="$ROOT/tools/commit_lane.since"

fail=0

# Read one commit's subject and body from a repo, and judge it. Echoes each
# complaint. Returns 1 if the commit is bad.
judge() {
    local repo="$1" sha="$2" subject body short
    subject="$(git -C "$repo" log -1 --format=%s "$sha")"
    short="$(git -C "$repo" log -1 --format=%h "$sha")"

    if ! printf '%s' "$subject" | grep -qE "^($LANES): ."; then
        echo "  $short  no lane: $subject"
        return 1
    fi
    if printf '%s' "$subject" | grep -qE '^rules: '; then
        body="$(git -C "$repo" log -1 --format=%B "$sha")"
        if ! printf '%s' "$body" | grep -qE 'inc-[a-z0-9]+(\.[0-9]+)*'; then
            echo "  $short  rules: with no design bead: $subject"
            return 1
        fi
    fi
    return 0
}

sweep() {
    local repo="$1" range="$2" n=0 bad=0 sha
    while read -r sha; do
        [ -n "$sha" ] || continue
        n=$((n + 1))
        judge "$repo" "$sha" || bad=$((bad + 1))
    done < <(git -C "$repo" rev-list --no-merges "$range" 2>/dev/null)
    echo "$n commit(s) in range, $bad unclassified"
    [ "$bad" -eq 0 ]
}

if [ "${1:-}" = "--selftest" ]; then
    # Build a throwaway repo with one commit of each shape and confirm this
    # script accepts the good ones and refuses the bad ones. A check that has
    # stopped checking looks exactly like a check that passes.
    tmp="$(mktemp -d)" || exit 2
    trap 'rm -rf "$tmp"' EXIT
    git -C "$tmp" init -q 2>/dev/null || exit 2
    git -C "$tmp" config user.email selftest@example.com
    git -C "$tmp" config user.name selftest
    commit() { echo "$2" > "$tmp/f"; git -C "$tmp" add f; git -C "$tmp" commit -q -m "$1" -m "${3:-}"; }

    commit "base" 0
    base="$(git -C "$tmp" rev-parse HEAD)"

    st=0
    commit "fix: guard the divisor" 1
    sweep "$tmp" "$base..HEAD" >/dev/null || { echo "SELFTEST FAIL: refused a good fix: subject"; st=1; }

    commit "graphics: soften the light map" 2
    sweep "$tmp" "$base..HEAD" >/dev/null || { echo "SELFTEST FAIL: refused a good graphics: subject"; st=1; }

    commit "rules: make armour subtract" 3 "Design: bd inc-b0w2."
    sweep "$tmp" "$base..HEAD" >/dev/null || { echo "SELFTEST FAIL: refused a rules: commit that names a bead"; st=1; }

    commit "Make armour subtract damage" 4
    sweep "$tmp" "$base..HEAD" >/dev/null && { echo "SELFTEST FAIL: accepted a subject with no lane"; st=1; }
    git -C "$tmp" reset -q --hard HEAD~1

    commit "rules: rebalance the daggers" 5 "No bead here."
    sweep "$tmp" "$base..HEAD" >/dev/null && { echo "SELFTEST FAIL: accepted a rules: commit with no bead"; st=1; }
    git -C "$tmp" reset -q --hard HEAD~1

    commit "fixing: not a lane" 6
    sweep "$tmp" "$base..HEAD" >/dev/null && { echo "SELFTEST FAIL: accepted a near-miss lane word"; st=1; }

    [ "$st" -eq 0 ] && echo "SELFTEST PASS: check_commit_lane.sh bites on all three failures"
    exit "$st"
fi

if [ "${1:-}" = "--since" ]; then
    [ -n "${2:-}" ] || { echo "--since needs a ref" >&2; exit 2; }
    RANGE="$2..HEAD"
else
    [ -f "$SINCE_FILE" ] || { echo "missing $SINCE_FILE" >&2; exit 2; }
    start="$(grep -vE '^\s*(#|$)' "$SINCE_FILE" | head -1 | tr -d '[:space:]')"
    git -C "$ROOT" cat-file -e "$start^{commit}" 2>/dev/null || {
        echo "$SINCE_FILE names $start, which is not a commit here" >&2; exit 2; }
    RANGE="$start..HEAD"
fi

echo "check_commit_lane: $RANGE"
sweep "$ROOT" "$RANGE" || fail=1

if [ "$fail" -ne 0 ]; then
    echo "FAIL: see AGENTS.md, \"Classifying a change\""
    exit 1
fi
echo "PASS"
exit 0
