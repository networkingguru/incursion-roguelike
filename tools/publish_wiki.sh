#!/usr/bin/env bash
# publish_wiki.sh -- regenerate the GitHub wiki from the in-game help (inc-k2le).
#
# Spec: docs/specs/2026-10-04-wiki-help-spec.md, section 4.
#
# Usage:
#   tools/publish_wiki.sh [--dry-run] [--tree <dir>] [<commit>]
#
#   <commit>   what to export and build from. Defaults to refs/heads/master.
#              Exported with `git archive <commit> | tar -x -C ...` into a
#              temp dir, so the caller's checkout is never built in and its
#              lib/program.i and lib/dispatch.h are never rewritten.
#   --tree <dir>
#              export a working DIRECTORY instead of a commit: copy it
#              (excluding .git, logs/ and build outputs) into the temp src
#              tree. This is how the phase 1-3 tree, which is uncommitted,
#              is published. When --tree is given no commit is used.
#   --dry-run  do everything except the commit and push; print the clone's
#              `git status --porcelain` and stop.
#
# Test-only override (documented here on purpose, used by the verification
# brief): set INCURSION_WIKI_CHECK to a command run in place of
# `python3 tools/check_wiki.py <dir>`; its exit status decides pass/fail.
# Unset, the real checker from the export is used.
#
# The wiki clone lives at ${INCURSION_WIKI_DIR:-$HOME/Scripts/incursion-roguelike.wiki}.
# If the remote does not exist yet (GitHub creates it on the first browser
# save), this logs a note and exits 0 without publishing.
#
# Logs to logs/wiki-publish.log of the CALLING checkout (append, dated header
# per run). A second concurrent run exits 0 at once. $tmp is always removed.

set -u

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
caller_root=$(git rev-parse --show-toplevel 2>/dev/null || true)
if [ -z "$caller_root" ]; then
    caller_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
fi
mkdir -p "$caller_root/logs"
log="$caller_root/logs/wiki-publish.log"

log() { printf '%s\n' "$*" >>"$log"; }

commit=refs/heads/master
tree=
dry_run=0
while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) dry_run=1; shift ;;
        --tree)
            [ $# -ge 2 ] || { echo "publish_wiki: --tree needs a directory" >&2; exit 2; }
            tree=$2; shift 2 ;;
        --) shift; break ;;
        -*) echo "publish_wiki: unknown option '$1'" >&2; exit 2 ;;
        *) commit=$1; shift ;;
    esac
done

log "=== $(date '+%Y-%m-%d %H:%M:%S') publish_wiki start (commit=$commit tree=${tree:-none} dry_run=$dry_run) ==="

# --- single-run lock: a concurrent run exits 0 at once ----------------------
lock="${TMPDIR:-/tmp}/incursion-wiki-publish.lock"
if ! mkdir "$lock" 2>/dev/null; then
    log "another publish_wiki run holds $lock; exiting 0"
    echo "publish_wiki: another run is active; exiting 0"
    exit 0
fi

tmp=$(mktemp -d "${TMPDIR:-/tmp}/incursion-wiki.XXXXXX")
cleanup() {
    rm -rf "$tmp"
    rmdir "$lock" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

src="$tmp/src"
out="$tmp/out"
mkdir -p "$src" "$out"

# --- 1. export a clean tree, never the calling checkout ---------------------
if [ -n "$tree" ]; then
    log "exporting directory: $tree"
    if ! (cd "$tree" && tar -cf - \
            --exclude=.git --exclude='./logs' --exclude=logs \
            --exclude='./build' --exclude=build \
            --exclude='*.o' --exclude=incursion-wiki \
            --exclude=incursion-headless --exclude=incursion \
            .) | tar -xf - -C "$src"; then
        log "export of directory '$tree' failed"
        echo "publish_wiki: export of directory failed" >&2
        exit 1
    fi
else
    log "exporting commit: $commit"
    if ! git archive "$commit" | tar -x -C "$src"; then
        log "git archive of '$commit' failed"
        echo "publish_wiki: git archive failed" >&2
        exit 1
    fi
fi

# --- 2. build the wiki binary in the export --------------------------------
log "building: BACKEND=posix OUT=incursion-wiki ./build_macos.sh"
if ! (cd "$src" && BACKEND=posix OUT=incursion-wiki ./build_macos.sh) >>"$log" 2>&1; then
    log "build failed in export"
    echo "publish_wiki: build failed (see $log)" >&2
    exit 1
fi
if [ ! -x "$src/incursion-wiki" ]; then
    log "build did not produce $src/incursion-wiki"
    echo "publish_wiki: build produced no incursion-wiki" >&2
    exit 1
fi

# --- 3. generate and check -------------------------------------------------
log "generating: $src/incursion-wiki -wikihelp $out"
if ! (cd "$src" && "$src/incursion-wiki" -wikihelp "$out") >>"$log" 2>&1; then
    log "generator failed"
    echo "publish_wiki: generator failed (see $log)" >&2
    exit 1
fi

page_count=$(find "$out" -maxdepth 1 -name '*.md' | wc -l | tr -d ' ')
log "generated $page_count page(s)"

check_cmd=${INCURSION_WIKI_CHECK:-}
if [ -n "$check_cmd" ]; then
    log "checking with override: $check_cmd"
    # shellcheck disable=SC2086
    if ! (cd "$src" && eval "$check_cmd") >>"$log" 2>&1; then
        log "check_wiki FAILED (override); publishing nothing"
        echo "publish_wiki: check failed; nothing published" >&2
        exit 1
    fi
else
    log "checking: python3 tools/check_wiki.py $out"
    if ! (cd "$src" && python3 tools/check_wiki.py "$out") >>"$log" 2>&1; then
        log "check_wiki FAILED; publishing nothing"
        echo "publish_wiki: check failed; nothing published" >&2
        exit 1
    fi
fi
log "check_wiki passed"

# --- 4. does the wiki repository exist yet? --------------------------------
wiki_url="https://github.com/networkingguru/incursion-roguelike.wiki.git"
if ! git ls-remote "$wiki_url" >/dev/null 2>&1; then
    msg="wiki repository does not exist yet: save one page in the GitHub web UI first"
    log "$msg"
    if [ "$dry_run" -eq 1 ]; then
        echo "publish_wiki: dry-run: generated $page_count page(s)"
    fi
    echo "publish_wiki: $msg"
    exit 0
fi

# --- 5. sync the clone, replace pages, commit, push ------------------------
wiki_dir=${INCURSION_WIKI_DIR:-$HOME/Scripts/incursion-roguelike.wiki}
if [ ! -d "$wiki_dir/.git" ]; then
    log "cloning $wiki_url into $wiki_dir"
    if ! git clone "$wiki_url" "$wiki_dir" >>"$log" 2>&1; then
        log "clone failed"
        echo "publish_wiki: clone failed (see $log)" >&2
        exit 1
    fi
fi
if ! (cd "$wiki_dir" && git pull --ff-only) >>"$log" 2>&1; then
    log "git pull --ff-only failed in $wiki_dir"
    echo "publish_wiki: pull failed (see $log)" >&2
    exit 1
fi

# Replace *.md with the generated set; leave non-.md files alone.
find "$wiki_dir" -maxdepth 1 -name '*.md' -delete
for f in "$out"/*.md; do
    [ -e "$f" ] || continue
    cp "$f" "$wiki_dir/"
done
log "replaced .md files in clone ($page_count page(s))"

if [ "$dry_run" -eq 1 ]; then
    log "dry-run: not committing or pushing"
    (cd "$wiki_dir" && git status --porcelain)
    exit 0
fi

if [ -n "$(cd "$wiki_dir" && git status --porcelain)" ]; then
    short=${commit#refs/heads/}
    if [ -n "$tree" ]; then
        short=$(git -C "$src" rev-parse --short HEAD 2>/dev/null || echo "$short")
    else
        short=$(git rev-parse --short "$commit" 2>/dev/null || echo "$short")
    fi
    (cd "$wiki_dir" && git add -A && git commit -m "Regenerate from $short") >>"$log" 2>&1 || {
        log "commit failed"; echo "publish_wiki: commit failed (see $log)" >&2; exit 1; }
    (cd "$wiki_dir" && git push) >>"$log" 2>&1 || {
        log "push failed"; echo "publish_wiki: push failed (see $log)" >&2; exit 1; }
    log "committed and pushed Regenerate from $short"
else
    log "no changes in clone; nothing to commit"
fi

log "=== publish_wiki done ==="
