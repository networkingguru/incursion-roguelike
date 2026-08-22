#!/usr/bin/env bash
#
# The scheduled wrapper around tools/check_probe_hooks.sh.
#
# Install:   tools/probe_hooks_cron.sh --install
# Remove:    tools/probe_hooks_cron.sh --uninstall
# Try it:    tools/probe_hooks_cron.sh --now
#
# It does two things every night. First it re-reads every INCURSION_* hook in
# the shipped source and writes the verdict to logs/probe-hooks.log, newest run
# first, last 30 runs kept. That part is the same shape as
# tools/doc_freshness_cron.sh and answers the same complaint: a list nobody
# regenerates goes stale, and then nobody trusts it.
#
# Second, and unlike the doc-freshness job, IT CORRECTS. When the checker
# reports a hook as RETIRED -- its bead is finished AND its reproduction is
# already saved as a patch under docs/evidence/ -- there is no judgement left to
# make, so this spawns a Claude Code agent to take the dead code out. Brian
# asked for that on 2026-08-22, and the reasoning is that "the bead is closed
# and the evidence is filed" is a fact, not an opinion.
#
# WHERE IT IS ALLOWED TO DO THAT. In a dated git worktree under
# .claude/worktrees/, on its own branch, never on master and never pushed. So
# the worst a bad night can do is leave a branch nobody merges. Read it with
# `git -C <worktree> diff HEAD~1` and merge it, or delete the worktree.
#
# THE CAP. It will act on at most MAX_AUTO hooks in one night. More than that
# means something unusual happened -- a batch of beads closed at once, or the
# checker changed -- and a person should look before an agent starts deleting.
#
# IT DOES NOT COMMIT TO MASTER, PUSH, OR FETCH.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOG="$ROOT/logs/probe-hooks.log"
LABEL="incursion-probe-hooks"
KEEP_RUNS=30
MAX_AUTO=3

usage() { sed -n '2,10p' "$0"; }

retire_with_agent() {
    local names="$1" stamp wt br out
    stamp="$(date '+%Y%m%d-%H%M%S')"
    br="probe-retire-$stamp"
    wt="$ROOT/.claude/worktrees/$br"

    command -v claude > /dev/null || {
        echo "RETIRED hooks found, but the claude CLI is not on PATH; not acting."
        return 0
    }

    git -C "$ROOT" worktree add -B "$br" "$wt" HEAD > /dev/null 2>&1 || {
        echo "RETIRED hooks found, but the worktree $wt could not be created."
        return 0
    }

    read -r -d '' out <<PROMPT
You are removing dead diagnostic code from the Incursion C++ port. You are in a
git worktree and nothing you do here reaches master.

STAY INSIDE THIS WORKTREE. Every file you read or write MUST be under the
directory you started in. Do not touch the main checkout at
/Users/brianhill/Scripts/Incursion -- another session works there and your
edits would collide with work you cannot see.

Read docs/REPORTING-GATE.md and AGENTS.md before you write any comment or
commit message: this repository does not boast, does not claim more than its
evidence proves, and states what a change does NOT fix as plainly as what it
does.

REMOVE EXACTLY THESE ENVIRONMENT HOOKS AND NOTHING ELSE:
$names

Each one has already been judged safe by tools/check_probe_hooks.sh: its bead is
finished AND its reproduction is preserved as a patch under docs/evidence/. Your
job is only the deletion. Do not re-litigate whether it should go.

For each hook:
 1. Find every getenv("<HOOK>") in src/ and inc/, and the function and comment
    block written to serve it. Delete the hook, its helper function, its call
    sites, and its comment. Leave the surrounding game logic untouched.
 2. Confirm the patch under docs/evidence/<bead>/ still applies to the code you
    are deleting. If it does not, STOP for that hook, leave it in place, and say
    so in your report -- a patch that no longer applies is not a reproduction.
 3. Remove the hook from tools/probe_hooks.baseline if it is listed there.

THEN, once, for all of them together:
 4. Build: BACKEND=posix ./build_macos.sh . Never pass -fsanitize=address; it
    deadlocks on this machine.
 5. Run tools/check_headless.sh and tools/check_probe_hooks.sh. Both must pass.
 6. If the build or either check fails, run 'git checkout -- .' to revert
    everything and report the failure. Do NOT commit a broken tree.
 7. If all green, commit on this branch with a message naming each hook removed
    and each bead it served. Do NOT push. Do NOT touch master.

Report: what you deleted, what you refused to delete and why, the build result,
and the two check results.
PROMPT

    ( cd "$wt" && claude -p --permission-mode bypassPermissions "$out" ) \
        > "$ROOT/logs/probe-retire-$stamp.log" 2>&1
    echo "agent ran in $wt (branch $br); transcript logs/probe-retire-$stamp.log"
    echo "review with: git -C $wt log -1 --stat"
}

run_now() {
    cd "$ROOT" || exit 2
    mkdir -p "$ROOT/logs"

    local out rc stamp action retired count tmp
    stamp="$(date '+%Y-%m-%d %H:%M:%S')"
    out="$(tools/check_probe_hooks.sh 2>&1)"
    rc=$?

    # The names between the RETIRED heading and the blank line after it.
    retired="$(printf '%s\n' "$out" |
        awk '/^RETIRED --/ {f=1; next} f && /^$/ {exit} f {print $1}')"
    count="$(printf '%s' "$retired" | grep -c . || true)"

    action=""
    if [ "$count" -eq 0 ]; then
        action="nothing is safe to delete tonight."
    elif [ "$count" -gt "$MAX_AUTO" ]; then
        action="$count hook(s) are safe to delete, which is over the cap of $MAX_AUTO. Not acting; look at this by hand."
    else
        action="$(retire_with_agent "$retired")"
    fi

    tmp="$(mktemp)" || exit 2
    {
        printf '===== %s  (exit %d) =====\n' "$stamp" "$rc"
        printf '%s\n\n' "$out"
        printf 'action: %s\n\n' "$action"
        if [ -f "$LOG" ]; then
            awk -v keep="$KEEP_RUNS" '
                /^===== / { n++ }
                n < keep  { print }
            ' "$LOG"
        fi
    } > "$tmp"
    mv "$tmp" "$LOG"

    [ "$count" -eq 0 ] || printf 'probe-hooks: %s\n' "$action"
    return $rc
}

install_job() {
    local line existing
    # 02:30, after the doc-freshness job at 02:00, so two agents never build in
    # the same tree at once.
    line="30 2 * * * PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$HOME/.local/bin $ROOT/tools/probe_hooks_cron.sh --now >/dev/null 2>&1  # $LABEL"

    existing="$(crontab -l 2>/dev/null)"
    if printf '%s\n' "$existing" | grep -qF "$LABEL"; then
        echo "Already installed. Current entry:"
        printf '%s\n' "$existing" | grep -F "$LABEL"
        return 0
    fi

    { [ -n "$existing" ] && printf '%s\n' "$existing"; printf '%s\n' "$line"; } | crontab -
    echo "Installed. Runs daily at 02:30, writes $LOG"
    crontab -l | grep -F "$LABEL"
}

uninstall_job() {
    local existing
    existing="$(crontab -l 2>/dev/null)"
    if ! printf '%s\n' "$existing" | grep -qF "$LABEL"; then
        echo "Not installed."; return 0
    fi
    printf '%s\n' "$existing" | grep -vF "$LABEL" | crontab -
    echo "Removed."
}

case "${1:-}" in
    --now)       run_now ;;
    --install)   install_job ;;
    --uninstall) uninstall_job ;;
    -h|--help)   usage ;;
    *)           usage; exit 2 ;;
esac
