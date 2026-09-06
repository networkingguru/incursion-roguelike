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
# TWO HATCHES, DIFFERENT SHAPES. tools/commit_lane.since is one sha and says
# "the rule starts after this"; everything at or before it is exempt forever.
# tools/commit_lane.exempt names individual commits that are forgiven, so a
# later miss below them still fails. Use the list, not the cutoff, for a commit
# that simply got it wrong -- advancing the cutoff grandfathers everything
# behind it. bd inc-3aqd.
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
EXEMPT_FILE="$ROOT/tools/commit_lane.exempt"

# Full shas of the commits forgiven BY NAME, newline separated. The selftest
# sets this directly against its throwaway repo; load_exempt fills it from
# EXEMPT_FILE for a real run.
EXEMPT=""

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

# Read the exemption list into EXEMPT, resolving each entry to a full sha.
# A named commit that does not exist here is an error, not a silent skip: a
# typo in this file must never quietly widen the exemption.
load_exempt() {
    local line sha full
    EXEMPT=""
    [ -f "$EXEMPT_FILE" ] || return 0
    while read -r line; do
        case "$line" in ''|'#'*) continue ;; esac
        sha="$(printf '%s' "$line" | awk '{print $1}')"
        [ -n "$sha" ] || continue
        full="$(git -C "$ROOT" rev-parse --verify --quiet "$sha^{commit}")" || {
            echo "$EXEMPT_FILE names $sha, which is not a commit here" >&2
            return 2
        }
        EXEMPT="$EXEMPT$full
"
    done < "$EXEMPT_FILE"
    return 0
}

is_exempt() {
    [ -n "$EXEMPT" ] || return 1
    printf '%s' "$EXEMPT" | grep -qx "$1"
}

sweep() {
    local repo="$1" range="$2" n=0 bad=0 skipped=0 sha
    while read -r sha; do
        [ -n "$sha" ] || continue
        n=$((n + 1))
        if is_exempt "$sha"; then
            skipped=$((skipped + 1))
            continue
        fi
        judge_commit "$repo" "$sha" || bad=$((bad + 1))
    done < <(git -C "$repo" rev-list --no-merges "$range" 2>/dev/null)
    echo "$n commit(s) in range, $skipped forgiven by name, $bad unclassified"
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

    # THE EXEMPTION LIST. It must forgive exactly what it names and nothing
    # else, in particular nothing below a forgiven commit. Start from a clean
    # base so the earlier cases cannot colour this one.
    git -C "$tmp" reset -q --hard "$base"

    commit "no lane on this one" 7
    exempt_sha="$(git -C "$tmp" rev-parse HEAD)"
    EXEMPT="$exempt_sha
"
    sweep "$tmp" "$base..HEAD" >/dev/null || {
        echo "SELFTEST FAIL: a commit named in the exemption list still failed"; st=1; }

    EXEMPT=""
    sweep "$tmp" "$base..HEAD" >/dev/null && {
        echo "SELFTEST FAIL: that commit passed with an EMPTY exemption list, so the list is not what forgave it"; st=1; }

    EXEMPT="$exempt_sha
"
    commit "no lane on this one either" 8
    sweep "$tmp" "$base..HEAD" >/dev/null && {
        echo "SELFTEST FAIL: an unlisted laneless commit passed because an older commit was exempt"; st=1; }
    git -C "$tmp" reset -q --hard HEAD~1

    commit "fix: a good one above an exempt one" 9
    sweep "$tmp" "$base..HEAD" >/dev/null || {
        echo "SELFTEST FAIL: refused a good commit stacked on an exempt one"; st=1; }
    EXEMPT=""

    # A typo in the exemption file must be an ERROR, not a silent widening.
    # load_exempt resolves against the real repo, so a sha that does not exist
    # there is exactly the shape of a mistyped entry.
    exempt_file_real="$EXEMPT_FILE"
    EXEMPT_FILE="$tmp/exempt"
    printf '%s\n' "# a comment line" \
        "0000000000000000000000000000000000000000  names no commit" > "$EXEMPT_FILE"
    load_exempt 2>/dev/null && {
        echo "SELFTEST FAIL: accepted an exemption entry that names no commit"; st=1; }
    printf '%s\n' "# a comment line" "" \
        "$(git -C "$ROOT" rev-parse HEAD)  the current tip" > "$EXEMPT_FILE"
    load_exempt || {
        echo "SELFTEST FAIL: refused a well-formed exemption file"; st=1; }
    EXEMPT_FILE="$exempt_file_real"
    EXEMPT=""

    [ "$st" -eq 0 ] && echo "SELFTEST PASS: check_commit_lane.sh bites on all failures, judges message files, and forgives only the commits its list names"
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

load_exempt || exit 2

echo "check_commit_lane: $RANGE"
sweep "$ROOT" "$RANGE" || fail=1

if [ "$fail" -ne 0 ]; then
    echo "FAIL: see AGENTS.md, \"Classifying a change\""
    exit 1
fi
echo "PASS"
exit 0
