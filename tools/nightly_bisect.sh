#!/usr/bin/env bash
# gate: none needs a repository, worktrees and bisect steps; not a landing check
#
# The nightly bisect for tools/nightly_verify.sh --record. The harness records
# tonight's state file, then runs this script in the repository at tonight's
# commit T. For every check that failed tonight (non-0, non-2) and has a
# last-good commit G, it bisects G..T by halving, confirms the landing L it
# finds, and writes a report. An absent check, a last-good off the
# first-parent line, a flaky check and a check without a last good night are
# all reported "not measured" and name no landing.
#
#   tools/nightly_bisect.sh                       run the bisect
#   tools/nightly_bisect.sh --help                this text
#
# VARIABLES
#   NIGHTLY_VERIFY_STATE   required. The state file --record wrote. Its
#                          directory D holds nightly-results/,
#                          nightly-last-good.tsv and nightly-bisect/.
#   NIGHTLY_BISECT_REPO    default: the repository this script lives in.
#                          The git repository to bisect.
#   NIGHTLY_BISECT_BUILD_CMD
#                          default: BACKEND=posix ./build_macos.sh. Run in each
#                          candidate worktree that needs a build. Set it to
#                          true to skip building.
#   INCURSION_BISECT_BUDGET
#                          default: 5400 seconds. No new bisect step starts
#                          after this many seconds since the script started.
#   NIGHTLY_BISECT_DATE    default: today (YYYY-MM-DD). Tonight's date, used in
#                          the report and the last-good file.
#
# Exit: 2 when the state file is missing or unreadable; otherwise 0 whatever it
# found. It never changes the branch it runs on, never commits, never pushes.
#
# Sections 5.5-5.7 are implemented: after L is named, the second pass reverts
# L (and any later causes) to find the others, and a bead is filed per named
# landing through tools/bead_new.sh.
set -uo pipefail

# No pipeline here stops early on purpose; keep the writer's status visible.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

case "${1:-}" in
    -h|--help)
        sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'
        exit 0 ;;
    "") ;;
    *) echo "nightly_bisect: unknown argument: $1" >&2; exit 2 ;;
esac

STATE="${NIGHTLY_VERIFY_STATE:-}"
[ -n "$STATE" ] || { echo "nightly_bisect: NIGHTLY_VERIFY_STATE is not set" >&2; exit 2; }
[ -r "$STATE" ] || { echo "nightly_bisect: cannot read state file: $STATE" >&2; exit 2; }

REPO="${NIGHTLY_BISECT_REPO:-$ROOT}"
BUILD_CMD="${NIGHTLY_BISECT_BUILD_CMD:-BACKEND=posix ./build_macos.sh}"
BUDGET="${INCURSION_BISECT_BUDGET:-5400}"
TODAY="${NIGHTLY_BISECT_DATE:-$(date +%Y-%m-%d)}"
SHORTDATE="$(printf '%s' "$TODAY" | tr -cd '0-9')"
BEAD_NEW="${NIGHTLY_BISECT_BEAD_NEW:-$ROOT/tools/bead_new.sh}"
BD="${NIGHTLY_BISECT_BD:-bd}"

[ -d "$REPO/.git" ] || [ -f "$REPO/.git" ] || {
    echo "nightly_bisect: not a git repository: $REPO" >&2; exit 2; }
command -v git > /dev/null 2>&1 || { echo "nightly_bisect: no git" >&2; exit 2; }

D="$(cd "$(dirname "$STATE")" && pwd -P)"
RESULTS_DIR="$D/nightly-results"
LASTGOOD="$D/nightly-last-good.tsv"
BISECT_DIR="$D/nightly-bisect"
BISECT_LOG_DIR="$BISECT_DIR/logs"
mkdir -p "$RESULTS_DIR" "$BISECT_LOG_DIR" || exit 2

STARTED=$(date +%s)

# ---------------------------------------------------------------- worktrees ---
# Every worktree this script adds is removed on the way out, whatever happens.
WT_LIST=""
WT_ROOT=""
cleanup_worktrees() {
    local wt
    for wt in ${WT_LIST}; do
        git -C "$REPO" worktree remove --force "$wt" > /dev/null 2>&1
    done
    WT_LIST=""
    [ -n "$WT_ROOT" ] && rm -rf "$WT_ROOT"
    WT_ROOT=""
}
# One trap removes any worktree still present and every scratch file. The
# variables are read when the trap fires, so empty ones are harmless.
trap 'cleanup_worktrees; rm -f "$OUT_LASTGOOD" "$OUT_LASTGOOD.sorted" "$SEEN_IDS" "$ORD_IDS" "$BIG_IDS"' \
    EXIT INT TERM

# git_run <args...> -> stdout, exit code passed through; never reads a pager.
git_run() { git -C "$REPO" "$@"; }

T="$(git_run rev-parse HEAD 2>/dev/null)" || {
    echo "nightly_bisect: cannot resolve HEAD in $REPO" >&2; exit 2; }
SHORT_T="$(git_run rev-parse --short HEAD 2>/dev/null)"
[ -n "$SHORT_T" ] || SHORT_T="$(printf '%s' "$T" | cut -c1-7)"

# Copy tonight's state beside us, with the commit on the first line.
STATE_COPY="$RESULTS_DIR/$TODAY-$SHORT_T.tsv"
{ printf '# commit %s\n' "$T"; cat "$STATE"; } > "$STATE_COPY" 2>/dev/null || {
    echo "nightly_bisect: cannot copy the state file" >&2; exit 2; }

# ----------------------------------------------------------- last-good file ---
# last_good_of <id> -> G, or nothing.
last_good_of() {
    [ -r "$LASTGOOD" ] || return 0
    awk -F'\t' -v id="$1" '$1 == id { print $2 }' "$LASTGOOD"
}
# last_date_of <id> -> the last date the id appeared, or nothing.
last_date_of() {
    [ -r "$LASTGOOD" ] || return 0
    awk -F'\t' -v id="$1" '$1 == id { print $3 }' "$LASTGOOD"
}

# The last-good table is rebuilt as an output: an id seen tonight keeps (or
# gains) tonight's date; an id not seen and not stale is carried over; an id
# whose last date is more than 30 days old is dropped.
OUT_LASTGOOD="$(mktemp "${TMPDIR:-/tmp}/nlb-lastgood.XXXXXX")" || exit 2

# Bash 3.2 has no associative arrays, so the ids seen tonight and the two
# ordered id lists are kept as TAB-separated lines in temp files.
SEEN_IDS="$(mktemp "${TMPDIR:-/tmp}/nlb-seen.XXXXXX")" || exit 2
ORD_IDS="$(mktemp "${TMPDIR:-/tmp}/nlb-ord.XXXXXX")" || exit 2
BIG_IDS="$(mktemp "${TMPDIR:-/tmp}/nlb-big.XXXXXX")" || exit 2

TMP_RESERVED="${TMPDIR:-/tmp}"

# --------------------------------------------------------------- bisect core --
# test_at <commit> <id> <logfile> [revert-list] -> 0 pass, 1 fail,
# 2 could not measure, 3 a requested revert conflicted.
# Adds a detached worktree at <commit>, reverts each commit in the
# space-separated <revert-list> in order, builds if the check needs it, and
# runs the id's command line there. A revert of a merge (two or more parents)
# needs -m 1; any other commit is reverted without -m. A revert that fails
# (conflict) returns 3, after removing the worktree as every other path does.
test_at() {
    local commit="$1" id="$2" log="$3" reverts="${4:-}"
    local tmp file marker c parents
    file="${id%% *}"
    tmp="$(mktemp -d "$TMP_RESERVED/nlb-wt.XXXXXX")" || return 2
    rmdir "$tmp" 2>/dev/null

    git -C "$REPO" worktree add --detach "$tmp" "$commit" > /dev/null 2>&1 || {
        rm -rf "$tmp"; return 2; }
    WT_LIST="$WT_LIST $tmp"

    for c in $reverts; do
        parents="$(git -C "$tmp" rev-list --parents -n 1 "$c" 2>/dev/null)"
        local np
        np=0
        for _ in $parents; do np=$((np + 1)); done
        if [ "$np" -ge 3 ]; then
            git -C "$tmp" revert --no-commit -m 1 "$c" > /dev/null 2>&1 || {
                git -C "$REPO" worktree remove --force "$tmp" > /dev/null 2>&1
                WT_LIST="${WT_LIST% $tmp}"
                return 3
            }
        else
            git -C "$tmp" revert --no-commit "$c" > /dev/null 2>&1 || {
                git -C "$REPO" worktree remove --force "$tmp" > /dev/null 2>&1
                WT_LIST="${WT_LIST% $tmp}"
                return 3
            }
        fi
    done

    # An absent check is never a failure: cannot measure at this commit.
    if [ ! -e "$tmp/$file" ]; then
        git -C "$REPO" worktree remove --force "$tmp" > /dev/null 2>&1
        WT_LIST="${WT_LIST% $tmp}"
        return 2
    fi

    # Build unless the check is cheap at this commit.
    marker="$(sed -n '1,40p' "$tmp/$file" | grep -xF '# gate: cheap')"
    if [ -z "$marker" ]; then
        ( cd "$tmp" && eval "$BUILD_CMD" ) > "$log.build" 2>&1 || {
            git -C "$REPO" worktree remove --force "$tmp" > /dev/null 2>&1
            WT_LIST="${WT_LIST% $tmp}"
            return 2
        }
    fi

    ( cd "$tmp" && eval "$id" ) > "$log" 2>&1
    local rc=$?
    git -C "$REPO" worktree remove --force "$tmp" > /dev/null 2>&1
    WT_LIST="${WT_LIST% $tmp}"
    case "$rc" in
        0) return 0 ;;
        2) return 2 ;;
        *) return 1 ;;
    esac
}

# budget_exceeded -> 0 once the time budget is spent.
budget_exceeded() {
    local now
    now=$(date +%s)
    [ "$((now - STARTED))" -ge "$BUDGET" ]
}

NAMED_LANDINGS=""   # one "id<TAB>L" line per named landing.
# One "id<TAB>L<TAB>second-pass sentence" line per named landing, for filing.
FILE_LIST=""

# find_landing <id> <lo> <hi> <reverts>: halve lo..hi on the first-parent
# line with the given revert list, then confirm the landing (it must fail,
# its first parent must pass, both with the reverts applied). Prints the
# report text for its own findings to stderr, sets FL_STATUS (named,
# notmeasured, inconsistent, conflict, budget) and FL_L (the landing, when
# named), and returns 0. This is the one place the halving and confirmation
# live; bisect_one calls it for L1, L2 and L3.
find_landing() {
    local id="$1" lo="$2" hi="$3" reverts="$4"
    local mid rc
    FL_STATUS="notmeasured"
    FL_L=""

    while :; do
        local n list c
        list="$(git_run rev-list --first-parent --reverse "$lo..$hi" 2>/dev/null)"
        n=0
        for c in $list; do n=$((n + 1)); done
        if [ "$n" -le 1 ]; then
            break
        fi
        # Midpoint: the (n/2)-th commit in the list.
        local half i
        half=$((n / 2))
        i=0
        mid=""
        for c in $list; do
            i=$((i + 1))
            [ "$i" -eq "$half" ] && { mid="$c"; break; }
        done
        [ -n "$mid" ] || break
        if budget_exceeded; then
            printf 'Time budget exceeded; not measured. Range: %s..%s\n' "$lo" "$hi" >&2
            FL_STATUS="budget"
            return 0
        fi
        test_at "$mid" "$id" "$BISECT_LOG_DIR/$SHORTDATE-step.log" "$reverts"
        rc=$?
        case "$rc" in
            3)
                printf 'a second cause may exist; not measured (revert conflict). Range: %s..%s\n' \
                    "$lo" "$hi" >&2
                FL_STATUS="conflict"
                return 0 ;;
            2)
                printf 'not measured: could not measure at %s. Range: %s..%s\n' \
                    "$mid" "$lo" "$hi" >&2
                FL_STATUS="notmeasured"
                return 0 ;;
            0) lo="$mid" ;;
            1) hi="$mid" ;;
        esac
    done

    # The landing is the first failing candidate after a passing one.
    local L
    L="$hi"

    # Confirmation: L must fail, L^1 must pass.
    if budget_exceeded; then
        printf 'Time budget exceeded; not measured. Range: %s..%s\n' "$lo" "$L" >&2
        FL_STATUS="budget"
        return 0
    fi
    test_at "$L" "$id" "$BISECT_LOG_DIR/$SHORTDATE-confirm-L.log" "$reverts"
    rc=$?
    if [ "$rc" -eq 3 ]; then
        printf 'a second cause may exist; not measured (revert conflict). Range: %s..%s\n' \
            "$lo" "$L" >&2
        FL_STATUS="conflict"
        return 0
    fi
    if [ "$rc" -ne 1 ]; then
        printf 'Inconsistent results, possibly flaky; not measured. Range: %s..%s\n' \
            "$lo" "$L" >&2
        FL_STATUS="inconsistent"
        return 0
    fi
    local parent
    parent="$(git_run rev-parse --verify --quiet "$L^1" 2>/dev/null)"
    if [ -z "$parent" ]; then
        printf 'Inconsistent results, possibly flaky; not measured. Range: %s..%s\n' \
            "$lo" "$L" >&2
        FL_STATUS="inconsistent"
        return 0
    fi
    test_at "$parent" "$id" "$BISECT_LOG_DIR/$SHORTDATE-confirm-parent.log" "$reverts"
    rc=$?
    if [ "$rc" -eq 3 ]; then
        printf 'a second cause may exist; not measured (revert conflict). Range: %s..%s\n' \
            "$lo" "$L" >&2
        FL_STATUS="conflict"
        return 0
    fi
    if [ "$rc" -ne 0 ]; then
        printf 'Inconsistent results, possibly flaky; not measured. Range: %s..%s\n' \
            "$lo" "$L" >&2
        FL_STATUS="inconsistent"
        return 0
    fi

    FL_STATUS="named"
    FL_L="$L"
    return 0
}

# second_pass <id> <L1> <logfile>: run T with L1 reverted. Prints to stderr
# and sets SP_STATUS (only, second, none, conflict, budget, notmeasured,
# more) plus SP_L2 and SP_L3. <logfile> is the message file bisect_one is
# building so far; find_landing's own lines are appended to it. Actually
# bisect_one reads SP_* and formats the report itself.
second_pass() {
    local id="$1" L1="$2"
    local rc L2 L2full L3 L3full
    SP_STATUS="none"
    SP_L2=""
    SP_L3=""

    # T with L1 reverted.
    test_at "$T" "$id" "$BISECT_LOG_DIR/$SHORTDATE-second-L1.log" "$L1"
    rc=$?
    case "$rc" in
        0)
            SP_STATUS="only"
            return 0 ;;
        2)
            SP_STATUS="notmeasured"
            return 0 ;;
        3)
            SP_STATUS="conflict"
            return 0 ;;
    esac

    # A second cause exists. Bisect the candidates after L1 with L1 reverted.
    find_landing "$id" "$L1" "$T" "$L1" 2> "$BISECT_LOG_DIR/$SHORTDATE-second-L2.msg"
    cat "$BISECT_LOG_DIR/$SHORTDATE-second-L2.msg" >&2
    case "$FL_STATUS" in
        named) L2="$FL_L" ;;
        conflict) SP_STATUS="conflict2"; return 0 ;;
        budget) SP_STATUS="budget"; return 0 ;;
        *) SP_STATUS="notmeasured"; return 0 ;;
    esac
    SP_STATUS="second"
    SP_L2="$L2"

    # T with both reverted: does a third cause exist?
    test_at "$T" "$id" "$BISECT_LOG_DIR/$SHORTDATE-second-L12.log" "$L1 $L2"
    rc=$?
    case "$rc" in
        0)
            return 0 ;;
        2)
            SP_STATUS="notmeasured"
            return 0 ;;
        3)
            SP_STATUS="conflict2"
            return 0 ;;
    esac

    # A third cause exists. Bisect the candidates after L2 with L1 L2 reverted.
    find_landing "$id" "$L2" "$T" "$L1 $L2" 2> "$BISECT_LOG_DIR/$SHORTDATE-second-L3.msg"
    cat "$BISECT_LOG_DIR/$SHORTDATE-second-L3.msg" >&2
    case "$FL_STATUS" in
        named) L3="$FL_L" ;;
        conflict) SP_STATUS="conflict2"; return 0 ;;
        budget) SP_STATUS="budget"; return 0 ;;
        *) SP_STATUS="notmeasured"; return 0 ;;
    esac
    SP_STATUS="third"
    SP_L3="$L3"

    # T with all three reverted: if it still fails, more may exist.
    test_at "$T" "$id" "$BISECT_LOG_DIR/$SHORTDATE-second-L123.log" "$L1 $L2 $L3"
    rc=$?
    case "$rc" in
        0) return 0 ;;
        3) SP_STATUS="conflict2"; return 0 ;;
        2) SP_STATUS="notmeasured"; return 0 ;;
        *) SP_STATUS="more" ;;
    esac
    return 0
}

# second_sentence <id> <L1>: format the second-pass result for the report.
second_sentence() {
    local id="$1" L1="$2"
    case "$SP_STATUS" in
        only) printf 'Second pass: L1 is the only cause.' ;;
        second) printf 'Second pass: a second cause exists; landing %s.' "$SP_L2" ;;
        third) printf 'Second pass: a second cause exists; landing %s and %s.' "$SP_L2" "$SP_L3" ;;
        more) printf 'Second pass: more causes may exist; not measured.' ;;
        conflict) printf 'Second pass: a second cause may exist; not measured (revert conflict).' ;;
        conflict2) printf 'Second pass: a second cause may exist; not measured (revert conflict).' ;;
        budget) printf 'Second pass: not measured (time budget exceeded).' ;;
        notmeasured) printf 'Second pass: not measured.' ;;
        *) printf 'Second pass: not measured.' ;;
    esac
}

# bisect_one <id> <G>: try to name a landing between G and T. Prints the report
# section body to stdout.
bisect_one() {
    local id="$1" g="$2"
    local rc L Lfull subject L2full L3full subject2 subject3

    # Fail closed: G must resolve and be an ancestor of T.
    if ! git_run rev-parse --verify --quiet "$g^{commit}" > /dev/null 2>&1; then
        printf 'not measured: last good commit %s does not resolve.\n' "$g"
        return 0
    fi
    if ! git_run merge-base --is-ancestor "$g" "$T" 2>/dev/null; then
        printf "not measured: last good commit is not an ancestor of tonight's; not measured.\n"
        return 0
    fi

    # Candidates c1..cn, cn = T, on the first-parent line.
    local cands
    cands="$(git_run rev-list --first-parent --reverse "$g..$T" 2>/dev/null)"
    [ -n "$cands" ] || {
        printf 'not measured: no candidates between %s and %s.\n' "$g" "$T"
        return 0
    }

    find_landing "$id" "$g" "$T" "" 2> "$BISECT_LOG_DIR/$SHORTDATE-first.msg"
    if [ "$FL_STATUS" != "named" ]; then
        cat "$BISECT_LOG_DIR/$SHORTDATE-first.msg"
        return 0
    fi
    L="$FL_L"
    Lfull="$(git_run rev-parse "$L" 2>/dev/null)"
    subject="$(git_run log -1 --format=%s "$L" 2>/dev/null)"
    NAMED_LANDINGS="$NAMED_LANDINGS$id	$Lfull
"
    printf 'Named landing: %s (%s)\n' "$Lfull" "$subject"
    printf 'Check: %s\n' "$id"
    printf 'Last good: %s\n' "$g"
    printf "Tonight: %s\n" "$T"

    local sent
    second_pass "$id" "$L"
    sent="$(second_sentence "$id" "$L")"
    printf '%s\n' "$sent"

    # Name every additional cause as its own landing line, then record all of
    # them for filing (spec 5.6), in order: L1, then L2 and L3 when named.
    FILE_LIST="$FILE_LIST$id	$Lfull	$sent
"
    if [ "$SP_STATUS" = "second" ] || [ "$SP_STATUS" = "third" ] || [ "$SP_STATUS" = "more" ]; then
        L2full="$(git_run rev-parse "$SP_L2" 2>/dev/null)"
        subject2="$(git_run log -1 --format=%s "$SP_L2" 2>/dev/null)"
        printf 'Named landing: %s (%s)\n' "$L2full" "$subject2"
        FILE_LIST="$FILE_LIST$id	$L2full	$sent
"
    fi
    if [ "$SP_STATUS" = "third" ] || [ "$SP_STATUS" = "more" ]; then
        L3full="$(git_run rev-parse "$SP_L3" 2>/dev/null)"
        subject3="$(git_run log -1 --format=%s "$SP_L3" 2>/dev/null)"
        printf 'Named landing: %s (%s)\n' "$L3full" "$subject3"
        FILE_LIST="$FILE_LIST$id	$L3full	$sent
"
    fi
    return 0
}

# --------------------------------------------------------------- filing ------
# short <hash> -> its first 7 characters or as many as it has.
short() { printf '%s' "$1" | cut -c1-7; }

# file_landing <id> <Lfull> <second-pass sentence>: file one bead for a named
# landing, per spec 5.6. Records the outcome in the report. Never fails the
# script: any filing problem is written down and the run continues.
file_landing() {
    local id="$1" l="$2" sent="$3"
    local Lfull subject label beadid title change bodyfile body rc out candidate

    Lfull="$(git_run rev-parse "$l" 2>/dev/null)"
    [ -n "$Lfull" ] || {
        printf 'Filing: landing %s does not resolve; nothing filed.\n' "$l" >> "$REPORT"
        return 0; }
    subject="$(git_run log -1 --format=%s "$Lfull" 2>/dev/null)"

    # Label: public when the landing changed src/, inc/ or lib/.
    if grep -Eq '^(src|inc|lib)/' \
        <<< "$(git_run diff --name-only "$Lfull^1" "$Lfull" 2>/dev/null)"; then
        label="public"
    else
        label="internal"
    fi

    # Bead id in the merge subject, when it names one.
    beadid="$(printf '%s' "$subject" | grep -oE 'inc-[a-z0-9.]+' | sed -n '1p')"
    if [ -n "$beadid" ]; then
        title="Nightly: $id broke at landing $beadid"
    else
        title="Nightly: $id broke at landing $(short "$Lfull")"
    fi

    # What "build" means for this check: the literal build unless cheap there.
    local file buildword
    file="${id%% *}"
    buildword="BACKEND=posix ./build_macos.sh"
    if [ -e "$REPO/$file" ] && grep -qxF '# gate: cheap' \
        <<< "$(sed -n '1,40p' "$REPO/$file")"; then
        buildword="no build"
    fi

    bodyfile="$(mktemp "${TMPDIR:-/tmp}/nlb-body.XXXXXX")" || return 0
    {
        printf 'The nightly run found that %s passed at %s and fails at %s.\n' \
            "$id" "$G_LASTGOOD" "$T"
        printf 'A bisect of the landings on master between them names %s\n' "$Lfull"
        printf '(%s). %s\n\n' "$subject" "$sent"
        printf '## Steps to Reproduce\n\n'
        printf '1. git worktree add --detach /tmp/a %s; %s; run %s: it passes.\n' \
            "$Lfull^1" "$buildword" "$id"
        printf '2. git worktree add --detach /tmp/b %s; %s; run %s: it fails.\n\n' \
            "$Lfull" "$buildword" "$id"
        printf '## Acceptance Criteria\n\n'
        printf -- '- %s passes at the tip of master.\n' "$id"
    } > "$bodyfile"

    out="$("$BEAD_NEW" "$title" --type bug --priority 1 --labels "$label" \
        --body-file "$bodyfile" 2>&1)"
    rc=$?
    rm -f "$bodyfile"
    case "$rc" in
        0)
            candidate="$(printf '%s' "$out" | grep -oE 'inc-[a-z0-9.]+' | sed -n '1p')"
            [ -n "$candidate" ] || candidate="$title"
            printf 'Filed: %s\n' "$candidate" >> "$REPORT" ;;
        3)
            candidate="$(printf '%s' "$out" | grep -oE 'inc-[a-z0-9.]+' | sed -n '1p')"
            if [ -n "$candidate" ]; then
                "$BD" update "$candidate" --append-notes \
                    "$TODAY nightly bisect: $id broke at $Lfull ($subject)." \
                    >> "$REPORT" 2>&1 \
                    && printf 'Noted on: %s\n' "$candidate" >> "$REPORT" \
                    || printf 'filing failed (exit %s)\n' "$?" >> "$REPORT"
            else
                printf 'duplicate suspected; candidate unknown\n' >> "$REPORT"
            fi ;;
        *)
            printf 'filing failed (exit %s)\n' "$rc" >> "$REPORT" ;;
    esac
    return 0
}

# file_all: file a bead for every named landing, in order. G_LASTGOOD is set
# from the id's last-good line before the call.
file_all() {
    local id l sent
    [ -n "$FILE_LIST" ] || return 0
    while IFS="$(printf '\t')" read -r id l sent; do
        [ -n "$id" ] || continue
        G_LASTGOOD="$(last_good_of "$id")"
        file_landing "$id" "$l" "$sent"
    done <<FILE_LIST_EOF
$FILE_LIST
FILE_LIST_EOF
    return 0
}

# ------------------------------------------------------------------- report ---
REPORT="$BISECT_DIR/$TODAY.md"
{
    printf '# Nightly bisect %s\n\n' "$TODAY"
    printf 'Tonight: %s\n\n' "$T"
} > "$REPORT" 2>/dev/null || {
    echo "nightly_bisect: cannot write report: $REPORT" >&2; exit 2; }

# Read tonight's state, in order, into two files: ordinary ids first, then the
# three big steps, because each big-step bisect step costs minutes.
while IFS="$(printf '\t')" read -r rc id; do
    [ -n "$id" ] || continue
    case "$id" in '#'*) continue ;; esac
    case "$rc" in ''|*[!0-9]*) continue ;; esac
    printf '%s\n' "$id" >> "$SEEN_IDS"
    case "$id" in
        tools/check_linux_build.sh|tools/check_layout_sweep.sh|tools/gate_compare.sh)
            printf '%s\t%s\n' "$rc" "$id" >> "$BIG_IDS" ;;
        *)
            printf '%s\t%s\n' "$rc" "$id" >> "$ORD_IDS" ;;
    esac
done < "$STATE"

# handle_id <rc> <id>: write one report section and append its last-good line
# (if any) to $OUT_LASTGOOD. The seen table already has every id.
handle_id() {
    local rc="$1" id="$2" g
    g="$(last_good_of "$id")"
    printf '## %s\n\n' "$id" >> "$REPORT"

    case "$rc" in
        0)
            printf 'Passed tonight; last good is %s.\n\n' "$T" >> "$REPORT"
            printf '%s\t%s\t%s\n' "$id" "$T" "$TODAY" >> "$OUT_LASTGOOD"
            ;;
        2)
            printf 'Could not measure tonight; not bisected.\n\n' >> "$REPORT"
            if [ -n "$g" ]; then
                printf '%s\t%s\t%s\n' "$id" "$g" "$TODAY" >> "$OUT_LASTGOOD"
            fi
            ;;
        *)
            if [ -z "$g" ]; then
                printf 'No last good night; not bisected.\n\n' >> "$REPORT"
            elif [ "$g" = "$T" ]; then
                printf 'Failing tonight but last good is tonight; not bisected.\n\n' >> "$REPORT"
                printf '%s\t%s\t%s\n' "$id" "$g" "$TODAY" >> "$OUT_LASTGOOD"
            else
                printf '%s\t%s\t%s\n' "$id" "$g" "$TODAY" >> "$OUT_LASTGOOD"
                bisect_one "$id" "$g" >> "$REPORT"
                printf '\n' >> "$REPORT"
            fi
            ;;
    esac
}

while IFS="$(printf '\t')" read -r rc id; do
    [ -n "$id" ] || continue
    handle_id "$rc" "$id"
done < "$ORD_IDS"
while IFS="$(printf '\t')" read -r rc id; do
    [ -n "$id" ] || continue
    handle_id "$rc" "$id"
done < "$BIG_IDS"

# File one bead per named landing, now that every id's second pass has run.
G_LASTGOOD=""
file_all

# Carry over ids not seen tonight unless their last date is more than 30 days
# old (a renamed or deleted check). Compare dates as strings: YYYY-MM-DD sorts.
cutdate="$(date -v-30d +%Y-%m-%d 2>/dev/null)" || cutdate=""
if [ -z "$cutdate" ]; then
    cutdate="$(date -d '30 days ago' +%Y-%m-%d 2>/dev/null)" || cutdate=""
fi
if [ -r "$LASTGOOD" ]; then
    while IFS="$(printf '\t')" read -r id g date; do
        [ -n "$id" ] || continue
        if grep -qxF "$id" "$SEEN_IDS"; then
            continue
        fi
        if [ -n "$cutdate" ] && [ -n "$date" ] && [ "$date" \< "$cutdate" ]; then
            continue
        fi
        printf '%s\t%s\t%s\n' "$id" "$g" "$date" >> "$OUT_LASTGOOD"
    done < "$LASTGOOD"
fi

# Write the last-good file atomically (temp file + mv), LC_ALL=C sorted.
LC_ALL=C sort "$OUT_LASTGOOD" > "$OUT_LASTGOOD.sorted" 2>/dev/null || \
    cp "$OUT_LASTGOOD" "$OUT_LASTGOOD.sorted"
NEW="$(mktemp "$D/nlb-lastgood.XXXXXX")" || exit 2
cat "$OUT_LASTGOOD.sorted" > "$NEW" && mv "$NEW" "$LASTGOOD"

echo "nightly_bisect: report in $REPORT"
exit 0
