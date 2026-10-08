#!/usr/bin/env bash
# gate: cheap
#
# Does tools/fast_checks.sh still bite? Plant fake checks in a temp directory,
# run the runner over them, and demand each verdict:
#
#   a. one passing fast check           -> exit 0
#   b. add one failing fast check       -> exit 1, naming that check
#   c. a check that overruns the limit  -> exit 1, "TOO SLOW", under 5 s
#   d. a check with no gate-fast marker -> never run (it would fail if it were)
#   e. an empty directory               -> exit 2 (nothing is not a pass)
#   f. tools/check_worktree_untracked.sh clean/untracked/ignored in a scratch
#      git repo                          -> 0 / 1 / 0
#   g. a slow check beside a fast one    -> 1; only the slow one is TOO SLOW,
#      the fast one still prints ok
#   h. a check exiting 2 alone           -> 0, output says UNMEASURED
#   i. tools/check_worktree_untracked.sh lists "a b.txt" as one line
#
# The fast runner globs tools/check_*.sh, so every fake here is one of those.
# Each is `chmod +x` and carries a `# gate-fast: <reason>` marker unless the
# case is about a file that must NOT have one.
#
# Exit: 0 every assertion held
#       1 any assertion failed
#       2 could not measure (mktemp failed)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUNNER="$ROOT/tools/fast_checks.sh"
WT="$ROOT/tools/check_worktree_untracked.sh"

fails=0
report() { # report <ok|FAIL> <label>
    if [ "$1" = ok ]; then
        printf 'PASS  %s\n' "$2"
    else
        printf 'FAIL  %s\n' "$2"
        fails=$((fails + 1))
    fi
}

TMP="$(mktemp -d "${TMPDIR:-/tmp}/check_fast_checks.XXXXXX")" || exit 2
trap 'rm -rf "$TMP"' EXIT

DIR="$TMP/checks"
mkdir -p "$DIR"

plant() { # plant <name> <marker-line-or-empty> <body...>
    local name="$1" marker="$2"
    shift 2
    {
        printf '#!/usr/bin/env bash\n'
        [ -n "$marker" ] && printf '# gate-fast: %s\n' "$marker"
        printf '%s\n' "$@"
    } > "$DIR/$name"
    chmod +x "$DIR/$name"
}

# ---- a. one passing fast check -> exit 0
plant check_pass.sh "static test" 'exit 0'
out="$("$RUNNER" --dir "$DIR" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ]; then report ok "a: a passing fast check exits 0"; else
    report FAIL "a: a passing fast check exits 0 (got $rc)"; printf '%s\n' "$out"; fi

# ---- b. add one failing fast check -> exit 1, naming it
plant check_fail.sh "static test" 'echo "the failure text"; exit 1'
out="$("$RUNNER" --dir "$DIR" 2>&1)"; rc=$?
if [ "$rc" -eq 1 ]; then
    case "$out" in
        *check_fail.sh*) report ok "b: a failing fast check exits 1 and names the check" ;;
        *) report FAIL "b: the failing check is not named"; printf '%s\n' "$out" ;;
    esac
else
    report FAIL "b: a failing fast check exits 1 (got $rc)"; printf '%s\n' "$out"
fi
rm -f "$DIR/check_fail.sh"

# ---- c. a check that sleeps past the limit -> exit 1, TOO SLOW, under 5 s
plant check_slow.sh "static test" 'sleep 5; exit 0'
start="$SECONDS"
out="$(INCURSION_FAST_LIMIT=2 "$RUNNER" --dir "$DIR" 2>&1)"; rc=$?
elapsed=$(( SECONDS - start ))
if [ "$rc" -eq 1 ] && [ "$elapsed" -lt 5 ]; then
    case "$out" in
        *"TOO SLOW"*) report ok "c: an overrunning check is killed (TOO SLOW, ${elapsed}s)" ;;
        *) report FAIL "c: an overrunning check did not say TOO SLOW"; printf '%s\n' "$out" ;;
    esac
else
    report FAIL "c: overrun case (exit $rc, ${elapsed}s)"; printf '%s\n' "$out"
fi
rm -f "$DIR/check_slow.sh"

# ---- d. a check with no marker is not run
plant check_nomarker.sh "" 'echo "I must not run"; exit 1'
out="$("$RUNNER" --dir "$DIR" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ]; then
    case "$out" in
        *check_nomarker.sh*) report FAIL "d: an unmarked check was run"; printf '%s\n' "$out" ;;
        *) report ok "d: a check with no gate-fast marker is not run" ;;
    esac
else
    report FAIL "d: an unmarked failing check affected the run (exit $rc)"; printf '%s\n' "$out"
fi
rm -f "$DIR/check_nomarker.sh" "$DIR/check_pass.sh"

# ---- e. an empty directory -> exit 2
out="$("$RUNNER" --dir "$DIR" 2>&1)"; rc=$?
if [ "$rc" -eq 2 ]; then report ok "e: an empty directory exits 2"; else
    report FAIL "e: an empty directory exits 2 (got $rc)"; printf '%s\n' "$out"; fi

# ---- f. check_worktree_untracked.sh in a scratch git repo
REPO="$TMP/repo"
mkdir -p "$REPO/tools"
cp "$WT" "$REPO/tools/check_worktree_untracked.sh"
if git -C "$REPO" init -q 2>/dev/null; then
    git -C "$REPO" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init 2>/dev/null
    git -C "$REPO" add tools/check_worktree_untracked.sh 2>/dev/null
    # clean
    out="$(cd "$REPO" && bash tools/check_worktree_untracked.sh 2>&1)"; rc=$?
    if [ "$rc" -eq 0 ]; then report ok "f1: a clean repo exits 0"; else
        report FAIL "f1: a clean repo exits 0 (got $rc)"; printf '%s\n' "$out"; fi

    # untracked file
    : > "$REPO/loose.txt"
    out="$(cd "$REPO" && bash tools/check_worktree_untracked.sh 2>&1)"; rc=$?
    if [ "$rc" -eq 1 ]; then
        case "$out" in
            *loose.txt*) report ok "f2: an untracked file exits 1 and is listed" ;;
            *) report FAIL "f2: the untracked file is not listed"; printf '%s\n' "$out" ;;
        esac
    else
        report FAIL "f2: an untracked file exits 1 (got $rc)"; printf '%s\n' "$out"
    fi

    # ignored file
    printf 'loose.txt\n' > "$REPO/.gitignore"
    git -C "$REPO" add .gitignore 2>/dev/null
    out="$(cd "$REPO" && bash tools/check_worktree_untracked.sh 2>&1)"; rc=$?
    if [ "$rc" -eq 0 ]; then report ok "f3: an ignored file exits 0"; else
        report FAIL "f3: an ignored file exits 0 (got $rc)"; printf '%s\n' "$out"; fi

    # ---- i. a filename with a space is listed on one line, unsplit
    : > "$REPO/a b.txt"
    out="$(cd "$REPO" && bash tools/check_worktree_untracked.sh 2>&1)"; rc=$?
    if [ "$rc" -eq 1 ]; then
        case "$out" in
            *"a b.txt"*) report ok "i: a filename with a space is listed whole" ;;
            *) report FAIL "i: a spaced filename is not listed on one line"; printf '%s\n' "$out" ;;
        esac
    else
        report FAIL "i: a spaced filename exits 1 (got $rc)"; printf '%s\n' "$out"
    fi
    rm -f "$REPO/a b.txt"
else
    report FAIL "f: could not git init a scratch repo"
fi

# ---- g. a slow check beside a fast one: only the slow one is TOO SLOW
plant check_slow_g.sh "static test" 'sleep 5; exit 0'
plant check_fast_g.sh "static test" 'exit 0'
out="$(INCURSION_FAST_LIMIT=2 "$RUNNER" --dir "$DIR" 2>&1)"; rc=$?
if [ "$rc" -eq 1 ]; then
    case "$out" in
        *"ok   check_fast_g.sh"*) fast_ok=1 ;;
        *) fast_ok=0 ;;
    esac
    case "$out" in
        *check_slow_g.sh*) slow_seen=1 ;;
        *) slow_seen=0 ;;
    esac
    if [ "$fast_ok" -eq 1 ] && [ "$slow_seen" -eq 1 ]; then
        report ok "g: only the slow check is TOO SLOW; the fast one still says ok"
    else
        report FAIL "g: a slow check flagged its neighbour (fast_ok=$fast_ok slow=$slow_seen)"
        printf '%s\n' "$out"
    fi
else
    report FAIL "g: slow+fast run exits 1 (got $rc)"; printf '%s\n' "$out"
fi
rm -f "$DIR/check_slow_g.sh" "$DIR/check_fast_g.sh"

# ---- h. a check exiting 2 alone -> exit 0, output says UNMEASURED
plant check_unmeasured.sh "static test" 'echo "cannot measure"; exit 2'
out="$("$RUNNER" --dir "$DIR" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ]; then
    case "$out" in
        *UNMEASURED*) report ok "h: a check exiting 2 does not fail the run (UNMEASURED)" ;;
        *) report FAIL "h: a check exiting 2 did not say UNMEASURED"; printf '%s\n' "$out" ;;
    esac
else
    report FAIL "h: a check exiting 2 left the runner at exit $rc"; printf '%s\n' "$out"
fi
rm -f "$DIR/check_unmeasured.sh"

echo
if [ "$fails" -eq 0 ]; then
    echo "check_fast_checks: PASS"
    exit 0
fi
echo "check_fast_checks: FAIL ($fails assertion(s))"
exit 1
