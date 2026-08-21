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
# first, and keeps the last 30 runs. It does NOT edit a document, open an issue,
# or send anything anywhere. See the checker's header for why detection is
# automated and correction is not.
#
# IT DOES NOT COMMIT, PUSH, OR FETCH. It reads the repository as it finds it.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOG="$ROOT/logs/doc-freshness.log"
LABEL="incursion-doc-freshness"
KEEP_RUNS=30

usage() { sed -n '2,10p' "$0"; }

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
    [ "$rc" = 0 ] || printf 'doc-freshness: findings in %s\n' "$LOG"
    return $rc
}

install_job() {
    local line existing
    # PATH is set explicitly: cron's default does not include /opt/homebrew/bin,
    # where git and python3 live on Apple silicon.
    # 02:00: the findings are waiting before Brian is up, not landing while he
    # reads them.
    line="0 2 * * * PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin $ROOT/tools/doc_freshness_cron.sh --now >/dev/null 2>&1  # $LABEL"

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
