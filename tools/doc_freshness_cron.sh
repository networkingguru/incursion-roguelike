#!/usr/bin/env bash
#
# The scheduled wrapper around tools/check_doc_freshness.sh.
#
# Install:   tools/doc_freshness_cron.sh --install
# Remove:    tools/doc_freshness_cron.sh --uninstall
# Try it:    tools/doc_freshness_cron.sh --now
#
# WHY A WRAPPER AND NOT A CRONTAB LINE STRAIGHT TO THE CHECKER.
#
# cron runs with almost no environment: no PATH beyond /usr/bin:/bin, no
# working directory, and no login shell. The checker needs git, python3 and a
# known cwd. It also needs somewhere to put its findings that a person will
# actually look at, because a cron job that writes to stdout writes to nobody.
#
# WHAT IT DOES WITH ITS FINDINGS. Writes logs/doc-freshness.log, newest run
# first, and keeps the last 30 runs.
#
# THEN IT FIXES THEM, which it did not used to do. This wrote a list into a file
# nobody opened: three runs recorded, findings every time, nothing ever
# corrected, and inc-ekv still open with 63 citation defects in it. A detector
# whose findings nobody acts on is not a safeguard; it is a record of decay. So
# when the checker reports findings, this spawns a Claude Code agent to correct
# them. The checker's own header already anticipated this -- "a human or an
# agent session fixes".
#
# WHERE IT IS ALLOWED TO DO THAT. In a dated git worktree under
# .claude/worktrees/, on its own branch, committed there and NEVER pushed and
# NEVER on master. Correcting a citation means reading the code the prose points
# at, which is judgement, so the result is a branch to read rather than a change
# that appears in the tree overnight.
#
# IT DOES NOT COMMIT TO MASTER, PUSH, OR FETCH.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOG="$ROOT/logs/doc-freshness.log"
LABEL="incursion-doc-freshness"
KEEP_RUNS=30

usage() { sed -n '2,10p' "$0"; }

fix_with_agent() {
    local findings="$1" stamp wt br prompt
    stamp="$(date '+%Y%m%d-%H%M%S')"
    br="doc-freshness-$stamp"
    wt="$ROOT/.claude/worktrees/$br"

    command -v claude > /dev/null || {
        echo "findings, but the claude CLI is not on PATH; not acting."
        return 0
    }
    git -C "$ROOT" worktree add -B "$br" "$wt" HEAD > /dev/null 2>&1 || {
        echo "findings, but the worktree $wt could not be created."
        return 0
    }

    read -r -d '' prompt <<PROMPT
You are correcting stale documentation in the Incursion C++ port. You are in a
git worktree; nothing you do reaches master.

STAY INSIDE THIS WORKTREE. Every file you read or write MUST be under the
directory you started in. Do not touch the main checkout at
/Users/brianhill/Scripts/Incursion -- another session works there and your
edits would collide with work you cannot see.

READ THESE FIRST, BEFORE YOU EDIT A WORD. They are the house voice and they are
not optional:
  docs/REPORTING-GATE.md -- especially "The four questions", "Titles" and
    "Separate the three things". The rule that matters most: a document MUST NOT
    assert more than its evidence proves. No boasting, no superlatives, no
    calling a fix complete when it is partial. Understate rather than overstate.
    An observation is not a diagnosis, and a diagnosis is not a patch.
  AGENTS.md and CLAUDE.md -- the marking rules and the publishing rules.
  tools/check_doc_freshness.sh, its header -- what a finding actually means.

THE FINDINGS FROM TONIGHT'S RUN:
$findings

Reproduce them yourself with tools/check_doc_freshness.sh before you trust that
list, then correct what it reports. Most of it is line-number drift, and that
part is mechanical.

THREE THINGS YOU MUST NOT DO. The checker's header names them because no script
can judge them:
 1. A line number that RECORDS A PAST RUN is evidence, not a pointer. Rewriting
    it falsifies the record. src/Target.cpp:1104 shows the right shape: keep the
    measured number and name today's location beside it.
 2. A citation can resolve perfectly and still be wrong, because the line it
    names is no longer the line the prose described. Read the code. If the prose
    no longer matches what is there, say so plainly rather than repointing the
    citation at something that merely exists.
 3. A citation can point into a #if 0 block -- src/Display.cpp:575-693 holds
    compiled-out twins of six accessors. Code the compiler never emits is not
    evidence.

WHEN YOU ARE DONE:
 4. Re-run tools/check_doc_freshness.sh and report its exit code and what it
    still says. A finding you deliberately left MUST be named and explained.
    Leaving one is allowed; hiding it is not.
 5. Commit on this branch, with a message naming which documents changed and
    why. Do NOT push. Do NOT touch master. Do NOT close any bead.

Report: what you corrected, what you left and why, and the checker's verdict.
PROMPT

    ( cd "$wt" && claude -p --permission-mode bypassPermissions "$prompt" ) \
        > "$ROOT/logs/doc-freshness-fix-$stamp.log" 2>&1
    echo "agent ran in $wt (branch $br); transcript logs/doc-freshness-fix-$stamp.log"
    echo "review with: git -C $wt log -1 --stat"
}

run_now() {
    cd "$ROOT" || exit 2
    mkdir -p "$ROOT/logs"

    local out rc stamp
    stamp="$(date '+%Y-%m-%d %H:%M:%S')"
    out="$(tools/check_doc_freshness.sh 2>&1)"
    rc=$?

    # Newest first, so the file is useful without scrolling.
    local tmp
    tmp="$(mktemp)" || exit 2
    {
        printf '===== %s  (exit %d) =====\n' "$stamp" "$rc"
        printf '%s\n\n' "$out"
        if [ -f "$LOG" ]; then
            # keep only the most recent KEEP_RUNS blocks
            awk -v keep="$KEEP_RUNS" '
                /^===== / { n++ }
                n < keep  { print }
            ' "$LOG"
        fi
    } > "$tmp"
    mv "$tmp" "$LOG"

    # A cron run says nothing when there is nothing to say.
    if [ "$rc" != 0 ]; then
        local action
        action="$(fix_with_agent "$out")"
        printf 'doc-freshness: findings in %s -- %s\n' "$LOG" "$action"
        printf '\naction: %s\n' "$action" >> "$LOG"
    fi
    return $rc
}

install_job() {
    local line existing
    # PATH is set explicitly: cron's default does not include /opt/homebrew/bin,
    # where git and python3 live on Apple silicon. $HOME/.local/bin is on it for
    # the claude CLI, without which fix_with_agent finds nothing to run and the
    # job quietly goes back to being a list nobody reads.
    # 02:00: the findings are waiting before Brian is up, not landing while he
    # reads them.
    line="0 2 * * * PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$HOME/.local/bin $ROOT/tools/doc_freshness_cron.sh --now >/dev/null 2>&1  # $LABEL"

    existing="$(crontab -l 2>/dev/null)"
    if printf '%s\n' "$existing" | grep -qF "$LABEL"; then
        echo "Already installed. Current entry:"
        printf '%s\n' "$existing" | grep -F "$LABEL"
        return 0
    fi

    { [ -n "$existing" ] && printf '%s\n' "$existing"; printf '%s\n' "$line"; } | crontab -
    echo "Installed. Runs daily at 02:00, writes $LOG"
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
