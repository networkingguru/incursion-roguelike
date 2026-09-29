#!/bin/bash
# Start work on a bead in a worktree of its own.
#
#   tools/worktree.sh inc-abcd                 create branch inc-abcd from master
#   tools/worktree.sh inc-abcd inc-pu6v        ... or from another base branch
#   tools/worktree.sh inc-abcd --take-over     claim it even if a live session holds it
#   tools/worktree.sh --selftest               prove the refusals fire
#
# WHY THIS EXISTS. Several agent sessions work in this repository at once, and
# before 2026-09-11 they all worked in the SAME checkout. One directory has one
# HEAD, one index and one working tree, so a session that changes branch changes
# it for everybody, silently. It failed twice in one hour that day:
#
#   * A session ran `git checkout -b inc-w26h-remaining` at 13:54:55. A second
#     session, which had read "current branch: master" when it started and never
#     touched HEAD, committed at 16:09 and landed on that branch. `git commit`
#     takes no branch argument -- it advances whatever branch HEAD names. Master
#     did not get the fix. The same class stranded b855fe2 on a review branch on
#     2026-09-04.
#   * tools/package_linux.sh exports the WORKING TREE, so another session's
#     uncommitted src/Values.cpp and three lib/*.irh files compiled into
#     published release assets (inc-iezk).
#
# A worktree has its own HEAD, its own index and its own files, and shares only
# the object database. Neither failure can happen across two of them.
#
# THE BRANCH IS NAMED BY THE BEAD, AND THAT IS THE WHOLE FILING SYSTEM. Branch
# inc-abcd, worktree Incursion-inc-abcd, bead inc-abcd. Nobody has to remember
# what a branch was for, because nothing is remembered -- it is derivable. A
# branch whose name is not a bead id is itself a defect, and
# tools/check_orphan_branches.sh reports it as one.
#
# IT REFUSES A CLOSED BEAD ON PURPOSE. Brian's constraint on 2026-09-11 was that
# isolation alone is not acceptable, because branches accumulate and fixes never
# reach master. The branch is scaffolding: tools/finish_bead.sh destroys it when
# the work lands. Opening a worktree for a bead that is already closed means one
# of those two has gone wrong, so it stops and says so rather than growing the
# pile this exists to prevent.
#
# IT CLAIMS THE BEAD, BECAUSE EVERY SESSION LOOKS LIKE THE SAME PERSON. All
# sessions share git user "Brian Hill", so bd's default actor is identical for
# all of them and a plain claim never refuses: a second session on the same bead
# would silently take it over. The claim uses a per-session actor name derived
# from the ancestor Claude process (session_actor) so bd can tell two sessions
# apart and refuse the second one. See bead inc-u1mt.
#
# Ends: 0 the worktree is ready, 1 refused, 2 the check could not be run.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/tools/worktree.sh"

# Worktrees sit beside the checkout, which is where Incursion-upw31 already
# lives. Keeping them out of the repository means no .gitignore entry and no
# chance of one worktree being scanned as part of another's tree.
WORKTREE_PARENT="$(dirname "$ROOT")"
WORKTREE_PREFIX="Incursion-"

# The branch every bead starts from. Not origin/master: the remote is not always
# reachable, and this repository's master is the integration branch by local
# convention. A second argument names another base -- an epic branch, e.g.
# inc-pu6v, so a bead builds on the epic instead of on master. --take-over may
# appear anywhere after the bead id; the other positional argument is the base.
BASE_BRANCH="master"
TAKE_OVER=0
BASE_SEEN=0
FIRST_ARG="${1:-}"
# First argument is the bead id (or --selftest); parse only the rest.
for arg in "${@:2}"; do
    case "$arg" in
        --take-over) TAKE_OVER=1 ;;
        *) if [ "$BASE_SEEN" -eq 0 ]; then BASE_BRANCH="$arg"; BASE_SEEN=1; fi ;;
    esac
done

die()  { echo "$1" >&2; exit 1; }
cannot() { echo "INCONCLUSIVE: $1" >&2; exit 2; }

# A bead id as this repository spells it: the `inc-` prefix, then the short id,
# optionally a dotted sub-id (inc-loa.40 is a real bead).
is_bead_id() {
    printf '%s' "$1" | grep -Eq '^inc-[a-z0-9]+(\.[0-9]+)?$'
}

bead_status() {
    # Prints the bead's status, or nothing at all when there is no such bead.
    # `bd show` writes its own diagnostics to stderr; we want only the answer.
    bd show "$1" --json 2>/dev/null \
        | python3 -c 'import json,sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
if isinstance(d, list):
    d = d[0] if d else {}
print(d.get("status", ""))' 2>/dev/null
}

# Prints claude-<pid> for the Claude Code session running this script, or
# nothing when no ancestor is claude (a human terminal, which should fall back
# to bd's own default actor). The PID is stable across /clear, and two
# concurrent sessions have different claude PIDs, so the name tells them apart.
session_actor() {
    local pid ppid comm
    pid=$$
    while [ "$pid" -gt 1 ]; do
        ppid="$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')"
        [ -n "$ppid" ] || break
        comm="$(ps -o comm= -p "$ppid" 2>/dev/null | tr -d ' ')"
        if [ "$comm" = "claude" ]; then
            echo "claude-$ppid"
            return 0
        fi
        pid="$ppid"
    done
    return 0
}

# True when the holder is a session actor whose process is gone or is no longer
# claude. An arbitrary holder (a person's name, or bd's default) is never stale:
# we cannot judge it, so the caller must refuse instead of taking over.
# ponytail: PID reuse by another claude process is the ceiling here -- a fresh
# claude inheriting a dead holder's PID reads as live and blocks a takeover.
# Upgrade path: record the process start time in the actor name and compare it.
holder_is_stale() {
    local holder="$1" pid comm probetool
    case "$holder" in
        claude-*) ;;
        *) return 1 ;;
    esac
    pid="${holder#claude-}"
    case "$pid" in
        ''|*[!0-9]*) return 1 ;;
    esac
    # If ps cannot report even on ourselves it cannot judge the holder, and a
    # tool that cannot see processes must not declare a live session dead.
    probetool="$(ps -o comm= -p $$ 2>/dev/null | tr -d ' ')"
    [ -n "$probetool" ] || return 1
    comm="$(ps -o comm= -p "$pid" 2>/dev/null | tr -d ' ')"
    [ "$comm" = "claude" ] && return 1
    return 0
}

selftest() {
    local out status

    out="$("$SCRIPT" 2>&1)"; status=$?
    [ "$status" -eq 1 ] || { echo "SELFTEST FAIL: no argument returned $status, expected 1"; return 1; }

    out="$("$SCRIPT" not-a-bead-id 2>&1)"; status=$?
    [ "$status" -eq 1 ] || { echo "SELFTEST FAIL: malformed id returned $status, expected 1"; return 1; }
    case "$out" in *"is not a bead id"*) ;; *) echo "SELFTEST FAIL: malformed id said: $out"; return 1;; esac

    # An id that is well formed but names nothing. inc-zzzzzz is not allocated;
    # if it ever is, this refuses for the closed-bead reason instead and the
    # message check below catches the drift.
    out="$("$SCRIPT" inc-zzzzzz 2>&1)"; status=$?
    [ "$status" -eq 1 ] || { echo "SELFTEST FAIL: unknown bead returned $status, expected 1"; return 1; }
    case "$out" in *"no bead"*) ;; *) echo "SELFTEST FAIL: unknown bead said: $out"; return 1;; esac

    # The second argument names the base branch. A well-formed, open bead with
    # a base branch that does not exist must be refused for THAT reason, before
    # any worktree is made. bd is stubbed for this one case so the run files
    # nothing and touches no real bead. The stub accepts `update --claim` with
    # exit 0, since the claim now runs before the base-branch check.
    local stubdir out2 status2
    stubdir="$(mktemp -d "${TMPDIR:-/tmp}/worktree-selftest.XXXXXX")" || return 1
    cat > "$stubdir/bd" <<'STUB'
#!/bin/sh
case "$*" in
    *--claim*) exit 0 ;;
esac
echo '[{"status":"open","issue_type":"task"}]'
STUB
    chmod +x "$stubdir/bd"
    out2="$(PATH="$stubdir:$PATH" "$SCRIPT" inc-testbase no-such-base 2>&1)"; status2=$?
    rm -rf "$stubdir"
    [ "$status2" -eq 2 ] || { echo "SELFTEST FAIL: bad base returned $status2, expected 2"; return 1; }
    case "$out2" in *"no-such-base"*) ;; *) echo "SELFTEST FAIL: bad base said: $out2"; return 1;; esac

    # The claim cases. Each has its own stub bd in a temp dir on PATH, and the
    # run is given a base branch that does not exist so it exits 2 for the
    # base-branch reason instead of creating a real worktree. The stub answers
    # `update ... --claim` with exit 1 and "issue already claimed by <holder>",
    # `show --json` with the holder as assignee, and exits 0 for other updates.
    local holder out3 status3
    for holder in claude-999999999 "Brian Hill"; do
        stubdir="$(mktemp -d "${TMPDIR:-/tmp}/worktree-selftest.XXXXXX")" || return 1
        cat > "$stubdir/bd" <<STUB
#!/bin/sh
case "\$*" in
    *--claim*)
        echo "issue already claimed by $holder" >&2
        exit 1 ;;
    "show "*--json*)
        echo '[{"status":"in_progress","assignee":"$holder","issue_type":"task"}]' ;;
    *) exit 0 ;;
esac
STUB
        chmod +x "$stubdir/bd"
        # (a) holder is claude-999999999, whose PID is dead: must TAKE OVER.
        # Where ps is denied, holder_is_stale fails closed and refuses, so
        # there is no answer to measure; skip rather than report a false fail.
        if [ "$holder" = claude-999999999 ]; then
            if [ -z "$(ps -o comm= -p $$ 2>/dev/null | tr -d ' ')" ]; then
                echo "SELFTEST SKIP: ps unavailable, stale-holder case not measured"
            else
                out3="$(PATH="$stubdir:$PATH" "$SCRIPT" inc-testclaim no-such-base 2>&1)"; status3=$?
                [ "$status3" -eq 2 ] || { rm -rf "$stubdir"; echo "SELFTEST FAIL: stale-holder claim returned $status3, expected 2"; return 1; }
                case "$out3" in *"Taking over"*) ;; *) rm -rf "$stubdir"; echo "SELFTEST FAIL: stale holder did not take over: $out3"; return 1;; esac
            fi
        else
            # (b) holder is "Brian Hill": must REFUSE.
            out3="$(PATH="$stubdir:$PATH" "$SCRIPT" inc-testclaim no-such-base 2>&1)"; status3=$?
            [ "$status3" -eq 1 ] || { rm -rf "$stubdir"; echo "SELFTEST FAIL: human holder claim returned $status3, expected 1"; return 1; }
            case "$out3" in *"claimed by Brian Hill"*) ;; *) rm -rf "$stubdir"; echo "SELFTEST FAIL: human holder said: $out3"; return 1;; esac
            # (c) same holder with --take-over: must NOT refuse on the claim.
            out3="$(PATH="$stubdir:$PATH" "$SCRIPT" inc-testclaim no-such-base --take-over 2>&1)"; status3=$?
            [ "$status3" -eq 2 ] || { rm -rf "$stubdir"; echo "SELFTEST FAIL: --take-over claim returned $status3, expected 2"; return 1; }
            case "$out3" in *"Taking over"*) ;; *) rm -rf "$stubdir"; echo "SELFTEST FAIL: --take-over did not take over: $out3"; return 1;; esac
        fi
        rm -rf "$stubdir"
    done

    echo "SELFTEST PASS"
    return 0
}

if [ "$FIRST_ARG" = "--selftest" ]; then
    selftest
    exit $?
fi

BEAD="$FIRST_ARG"
[ -n "$BEAD" ] || die "usage: tools/worktree.sh <bead-id> [base-branch] [--take-over]
Start work on a bead in a worktree of its own. Run tools/worktree.sh --selftest
to prove the refusals still fire."

is_bead_id "$BEAD" || die "REFUSED: '$BEAD' is not a bead id.
A branch is named by its bead so that nobody has to remember what it was for.
Expected something like inc-abcd or inc-loa.40."

command -v bd >/dev/null 2>&1 || cannot "bd is not on PATH, so the bead cannot be checked"
command -v python3 >/dev/null 2>&1 || cannot "python3 is not on PATH, so the bead cannot be read"

STATUS="$(bead_status "$BEAD")"
[ -n "$STATUS" ] || die "REFUSED: there is no bead $BEAD.
File it first -- tools/bead_new.sh \"title\" --type bug -d \"...\" --label internal
-- so the branch, the worktree and the tracker agree on one name."

if [ "$STATUS" = "closed" ]; then
    die "REFUSED: bead $BEAD is already closed.
A branch exists only while its bead is open; tools/finish_bead.sh deletes it
when the work lands. Opening one for a closed bead means either the bead was
closed early or the earlier branch was never merged. Check
tools/check_orphan_branches.sh before reopening anything."
fi

# Claim the bead before touching any worktree. All sessions share git user
# "Brian Hill", so the actor name is what lets bd tell them apart; without it a
# second session silently takes the bead. ACTOR is empty for a human terminal,
# where bd's default actor applies and the claim behaves as it always did.
ACTOR="$(session_actor)"
CLAIM=(bd update "$BEAD" --claim)
[ -n "$ACTOR" ] && CLAIM+=(--actor "$ACTOR")
if ! CLAIM_OUT="$("${CLAIM[@]}" 2>&1)"; then
    case "$CLAIM_OUT" in
        *"already claimed"*) ;;
        *) cannot "bd could not claim $BEAD: $CLAIM_OUT" ;;
    esac
    HOLDER="$(bd show "$BEAD" --json 2>/dev/null | python3 -c 'import json,sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
if isinstance(d, list):
    d = d[0] if d else {}
print(d.get("assignee", ""))' 2>/dev/null)"
    if [ "$TAKE_OVER" -eq 1 ] || holder_is_stale "$HOLDER"; then
        TAKEOVER_ACTOR="$ACTOR"
        if [ -z "$TAKEOVER_ACTOR" ]; then
            TAKEOVER_ACTOR="${BEADS_ACTOR:-$(git -C "$ROOT" config user.name)}"
        fi
        [ -n "$TAKEOVER_ACTOR" ] \
            || cannot "cannot take over $BEAD from $HOLDER: no actor to assign it to.
Set BEADS_ACTOR or git config user.name, or pass --assignee by hand."
        TAKEOVER=(bd update "$BEAD")
        TAKEOVER+=(--assignee "$TAKEOVER_ACTOR")
        TAKEOVER+=(--status in_progress)
        "${TAKEOVER[@]}" >/dev/null 2>&1 \
            || cannot "bd could not take over $BEAD from $HOLDER"
        if [ "$TAKE_OVER" -eq 1 ]; then
            echo "Taking over bead $BEAD from $HOLDER (--take-over given)." >&2
        else
            echo "Taking over bead $BEAD from $HOLDER (that session is gone)." >&2
        fi
    else
        die "REFUSED: bead $BEAD is claimed by $HOLDER. Another session may be working on it. Run bd show $BEAD. If the holder is gone, rerun with --take-over."
    fi
fi

WORKTREE="$WORKTREE_PARENT/$WORKTREE_PREFIX$BEAD"

if git -C "$ROOT" show-ref --verify --quiet "refs/heads/$BEAD"; then
    if [ -d "$WORKTREE" ]; then
        echo "Branch $BEAD and its worktree already exist. Work there:"
        echo "  $WORKTREE"
        exit 0
    fi
    die "REFUSED: branch $BEAD exists but has no worktree at $WORKTREE.
Somebody started this bead and the worktree is gone. Either restore it with
  git worktree add \"$WORKTREE\" $BEAD
or, if the work is finished and merged, delete the branch."
fi

[ -e "$WORKTREE" ] && die "REFUSED: $WORKTREE already exists and is not a worktree of this branch.
Move it aside before starting $BEAD."

git -C "$ROOT" show-ref --verify --quiet "refs/heads/$BASE_BRANCH" \
    || cannot "there is no $BASE_BRANCH branch to start from"

git -C "$ROOT" worktree add -b "$BEAD" "$WORKTREE" "$BASE_BRANCH" >/dev/null 2>&1 \
    || die "FAILED: git worktree add refused. Run it by hand to see why:
  git -C \"$ROOT\" worktree add -b \"$BEAD\" \"$WORKTREE\" \"$BASE_BRANCH\""

echo "Bead $BEAD is open in a worktree of its own."
echo "  branch:   $BEAD (from $BASE_BRANCH at $(git -C "$ROOT" rev-parse --short "$BASE_BRANCH"))"
echo "  worktree: $WORKTREE"
echo
echo "Work there and nowhere else. When Brian says commit, finish it with:"
echo "  tools/finish_bead.sh $BEAD"
exit 0
