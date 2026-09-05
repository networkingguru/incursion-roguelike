#!/usr/bin/env bash
#
# Does every new commit subject open with one of the seven lanes, and does every
# rules: commit name a design bead?
#
#   tools/check_commit_lane.sh              every commit since the rule started
#   tools/check_commit_lane.sh --since REF  an explicit range
#   tools/check_commit_lane.sh --message FILE  judge a proposed commit message
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

# Judge a subject and body from either history or a proposed message. Returns 1
# if the message is bad and sets REASON for the caller's chosen report format.
judge() {
    local subject="$1" body="$2"
    REASON=
    case "$subject" in
        "Merge "*|"Revert "*|fixup\!*|squash\!*|amend\!*) return 0 ;;
    esac
    if ! printf '%s' "$subject" | grep -qE "^($LANES): ."; then
        REASON="no lane"
        return 1
    fi
    if printf '%s' "$subject" | grep -qE '^rules: '; then
        if ! printf '%s' "$body" | grep -qE 'inc-[a-z0-9]+(\.[0-9]+)*'; then
            REASON="rules: with no design bead"
            return 1
        fi
    fi
    return 0
}

judge_commit() {
    local repo="$1" sha="$2" subject body short
    subject="$(git -C "$repo" log -1 --format=%s "$sha")"
    body="$(git -C "$repo" log -1 --format=%B "$sha")"
    short="$(git -C "$repo" log -1 --format=%h "$sha")"
    judge "$subject" "$body" || { echo "  $short  $REASON: $subject"; return 1; }
}

judge_message() {
    local file="$1" message subject
    [ -f "$file" ] || { echo "cannot read commit message file: $file" >&2; return 2; }
    message="$(grep -v '^#' "$file")"
    subject="$(printf '%s\n' "$message" | sed -n '/[^[:space:]]/{p;q;}')"
    judge "$subject" "$message" && return 0
    printf '%s\n' \
        "Commit subject refused: $subject" \
        "Reason: $REASON." \
        "Choose one of the seven lanes:" \
        "  fix: correct a defect" \
        "  port: platform, build, toolchain, or packaging" \
        "  data: correct lib/*.irh content" \
        "  rules: deliberately change game rules (body must name an inc-* design bead)" \
        "  graphics: renderer, light map, terminal output, or appearance" \
        "  docs: prose only" \
        "  tools: harness, checks, gate, or scripts" \
        "See AGENTS.md, \"Classifying a change\"." \
        "Emergency escape hatch: INCURSION_NO_LANE_CHECK=1 git commit ..." >&2
    return 1
}

sweep() {
    local repo="$1" range="$2" n=0 bad=0 sha
    while read -r sha; do
        [ -n "$sha" ] || continue
        n=$((n + 1))
        judge_commit "$repo" "$sha" || bad=$((bad + 1))
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

    printf '%s\n' "fix: guard the divisor" > "$tmp/message"
    judge_message "$tmp/message" 2>/dev/null || { echo "SELFTEST FAIL: refused a good fix: message file"; st=1; }
    printf '%s\n' "Make armour subtract damage" > "$tmp/message"
    judge_message "$tmp/message" >/dev/null 2>&1 && { echo "SELFTEST FAIL: accepted a message file with no lane"; st=1; }
    printf '%s\n' "rules: rebalance the daggers" "" "No bead here." > "$tmp/message"
    judge_message "$tmp/message" >/dev/null 2>&1 && { echo "SELFTEST FAIL: accepted a rules: message file with no bead"; st=1; }
    printf '%s\n' "rules: rebalance the daggers" "" "Design: bd inc-b0w2." > "$tmp/message"
    judge_message "$tmp/message" 2>/dev/null || { echo "SELFTEST FAIL: refused a rules: message file that names a bead"; st=1; }
    printf '%s\n' "# template comment" "Merge branch 'topic'" > "$tmp/message"
    judge_message "$tmp/message" 2>/dev/null || { echo "SELFTEST FAIL: refused an exempt Merge message file"; st=1; }

    [ "$st" -eq 0 ] && echo "SELFTEST PASS: check_commit_lane.sh bites on all failures and judges message files"
    exit "$st"
fi

if [ "${1:-}" = "--message" ]; then
    [ -n "${2:-}" ] || { echo "--message needs a file" >&2; exit 2; }
    judge_message "$2"
    exit $?
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
