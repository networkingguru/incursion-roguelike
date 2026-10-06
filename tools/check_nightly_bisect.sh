#!/usr/bin/env bash
# gate: cheap
#
# Does tools/nightly_bisect.sh name the landing that broke a check, and
# nothing it cannot prove?
#
#   tools/check_nightly_bisect.sh      run every case
#
# WHY THIS EXISTS. tools/nightly_bisect.sh bisects the range between a check's
# last good night and tonight's commit, then writes a report naming the landing
# that broke it. A fault is quiet in both directions: too eager and the report
# accuses an innocent commit (or a check that merely bears the same name), too
# timid and a real breakage stays anonymous. The dangerous cases are all
# negatives -- a check absent at the early commit, a last good commit off the
# first-parent line, a result that flips on a re-run, and an exhausted time
# budget -- and in each the script must name nothing.
#
# IT TESTS A THROWAWAY REPOSITORY, NOT THIS ONE. It builds a repository under
# TMPDIR with one base commit G and four --no-ff landings (L1..L4) on master,
# plus a made-up check tools/check_x.sh that fails once state.txt holds the
# word broken. L2 writes that word; the bisect must name L2 and no other
# landing. Nothing here touches the repository it is run from.
#
# Exit: 0 every case behaved
#       1 a case did not
#       2 could not measure
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BISECT="$ROOT/tools/nightly_bisect.sh"
[ -r "$BISECT" ] || { echo "check_nightly_bisect: no $BISECT" >&2; exit 2; }
command -v git > /dev/null 2>&1 || { echo "check_nightly_bisect: no git" >&2; exit 2; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/nightly-bisect.XXXXXX")" || exit 2
trap 'chmod -R u+rw "$TMP" 2> /dev/null; rm -rf "$TMP"' EXIT
TMP="$(cd "$TMP" && pwd -P)" || exit 2

# The throwaway repository answers to nothing the caller configured.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid
export GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
unset NIGHTLY_VERIFY_STATE NIGHTLY_BISECT_REPO NIGHTLY_BISECT_BUILD_CMD \
      NIGHTLY_BISECT_DATE INCURSION_BISECT_BUDGET

REPO="$TMP/repo"
GIT="git -c user.name=t -c user.email=t@example.invalid"

# ------------------------------------------------------------------- build ---
# One base commit G, then four landings on master, each merged with --no-ff.
trap 'chmod -R u+rw "$TMP" 2> /dev/null; rm -rf "$TMP"' EXIT
mkdir -p "$REPO/tools" || exit 2

# check_x: cheap, fails when state.txt holds the word broken.
cat > "$REPO/tools/check_x.sh" <<'CHK'
#!/usr/bin/env bash
# gate: cheap
if grep -qw broken state.txt 2> /dev/null; then
    echo "state is broken" >&2
    exit 1
fi
exit 0
CHK
chmod +x "$REPO/tools/check_x.sh"

# check_flaky: cheap; fails on its first run and passes afterwards. The
# counter lives outside any worktree, in the case's temp dir; the check reads
# it through $FLAKY_COUNTER, so it is state shared across worktree runs.
cat > "$REPO/tools/check_flaky.sh" <<'CHK'
#!/usr/bin/env bash
# gate: cheap
n=$(cat "$FLAKY_COUNTER" 2> /dev/null || echo 0)
n=$((n + 1))
printf '%s\n' "$n" > "$FLAKY_COUNTER"
if [ "$n" -eq 1 ]; then
    exit 1
fi
exit 0
CHK
chmod +x "$REPO/tools/check_flaky.sh"

( cd "$REPO" && $GIT init -q -b master . ) > /dev/null 2>&1 || \
    ( cd "$REPO" && $GIT init -q . && $GIT symbolic-ref HEAD refs/heads/master ) \
    > /dev/null 2>&1 || { echo "check_nightly_bisect: git init failed" >&2; exit 2; }

printf 'base\n' > "$REPO/base.txt"
printf 'a0\n' > "$REPO/a.txt"
printf 'b0\n' > "$REPO/b.txt"
printf 'c0\n' > "$REPO/c.txt"
printf 'ok\n' > "$REPO/state.txt"
( cd "$REPO" && $GIT add -A && $GIT commit -q -m 'base G' ) || exit 2
G="$( cd "$REPO" && $GIT rev-parse HEAD )"

# landing <name> <file> <content> ; merges the branch --no-ff into master.
landing() {
    local name="$1" file="$2" content="$3"
    ( cd "$REPO" \
        && $GIT checkout -q -b "$name" master \
        && printf '%s\n' "$content" > "$file" \
        && $GIT add -A \
        && $GIT commit -q -m "$name work" \
        && $GIT checkout -q master \
        && $GIT merge -q --no-ff -m "$name merge" "$name" ) || return 1
    ( cd "$REPO" && $GIT rev-parse HEAD )
}

L1="$(landing L1 a.txt a1)" || exit 2
# L2's merge subject names a bead id (inc-test2), for the filing cases.
L2="$( cd "$REPO" && $GIT checkout -q -b L2 master \
    && printf 'broken\n' > state.txt \
    && $GIT add -A && $GIT commit -q -m 'L2 work' \
    && $GIT checkout -q master \
    && $GIT merge -q --no-ff -m 'Merge inc-test2: L2 broke state' L2 \
    && $GIT rev-parse HEAD )" || exit 2
# L3 touches b.txt AND adds check_y.sh, so check_y exists from L3 on but not
# at G, L1 or L2 -- where it must read as "could not measure", not a failure.
cat > "$TMP/check_y.sh" <<'CHK'
#!/usr/bin/env bash
# gate: cheap
exit 1
CHK
chmod +x "$TMP/check_y.sh"
L3="$( cd "$REPO" && $GIT checkout -q -b L3 master \
    && printf 'b1\n' > b.txt \
    && cp "$TMP/check_y.sh" tools/check_y.sh \
    && $GIT add -A && $GIT commit -q -m 'L3 work' \
    && $GIT checkout -q master \
    && $GIT merge -q --no-ff -m 'L3 merge' L3 \
    && $GIT rev-parse HEAD )" || exit 2
L4="$(landing L4 c.txt c1)" || exit 2
T="$( cd "$REPO" && $GIT rev-parse HEAD )"
[ -n "$L1" ] && [ -n "$L2" ] && [ -n "$L3" ] && [ -n "$L4" ] && [ -n "$T" ] || exit 2

# ------------------------------------------------- extra repos for 8, 9, 11 ---
# REPO2 (case 9): L2 writes broken to state.txt; L3 edits that same line, so
# reverting L2 at T conflicts.
REPO2="$TMP/repo2"
mkdir -p "$REPO2/tools" || exit 2
cat > "$REPO2/tools/check_multi.sh" <<'CHK'
#!/usr/bin/env bash
# gate: cheap
if grep -qw broken state.txt 2> /dev/null; then exit 1; fi
exit 0
CHK
chmod +x "$REPO2/tools/check_multi.sh"
( cd "$REPO2" && $GIT init -q -b master . ) > /dev/null 2>&1 || \
    ( cd "$REPO2" && $GIT init -q . && $GIT symbolic-ref HEAD refs/heads/master ) \
    > /dev/null 2>&1 || { echo "check_nightly_bisect: git init repo2 failed" >&2; exit 2; }
printf 'base\n' > "$REPO2/base.txt"
printf 'ok\n' > "$REPO2/state.txt"
( cd "$REPO2" && $GIT add -A && $GIT commit -q -m 'base G2' ) || exit 2
G2="$( cd "$REPO2" && $GIT rev-parse HEAD )"
# landing2 <name> <cmds...>: run the given shell steps on a branch and merge.
landing2() {
    local name="$1"; shift
    ( cd "$REPO2" && $GIT checkout -q -b "$name" master ) || return 1
    ( cd "$REPO2" && eval "$*" ) || return 1
    ( cd "$REPO2" && $GIT add -A && $GIT commit -q -m "$name work" \
        && $GIT checkout -q master \
        && $GIT merge -q --no-ff -m "$name merge" "$name" ) || return 1
    ( cd "$REPO2" && $GIT rev-parse HEAD )
}
L2a="$(landing2 L2a 'printf "a1\n" > a.txt')" || exit 2
L2b="$(landing2 L2b 'printf "broken\n" > state.txt')" || exit 2
# L2c edits the very line L2b wrote, so reverting L2b at T conflicts.
L2c="$(landing2 L2c 'printf "broken edited\n" > state.txt')" || exit 2
[ -n "$L2a" ] && [ -n "$L2b" ] && [ -n "$L2c" ] || exit 2
T2="$( cd "$REPO2" && $GIT rev-parse HEAD )"

# REPO3 (cases 8, 11): check_multi reads state.txt and state2.txt; L2 writes
# state.txt=broken and changes src/x.c (public); L4 writes state2.txt=broken
# and changes tools/only_tools.txt (internal). Two causes.
REPO3="$TMP/repo3"
mkdir -p "$REPO3/tools" "$REPO3/src" || exit 2
cat > "$REPO3/tools/check_multi.sh" <<'CHK'
#!/usr/bin/env bash
# gate: cheap
if grep -qw broken state.txt 2> /dev/null; then exit 1; fi
if grep -qw broken state2.txt 2> /dev/null; then exit 1; fi
exit 0
CHK
chmod +x "$REPO3/tools/check_multi.sh"
( cd "$REPO3" && $GIT init -q -b master . ) > /dev/null 2>&1 || \
    ( cd "$REPO3" && $GIT init -q . && $GIT symbolic-ref HEAD refs/heads/master ) \
    > /dev/null 2>&1 || { echo "check_nightly_bisect: git init repo3 failed" >&2; exit 2; }
printf 'base\n' > "$REPO3/base.txt"
printf 'ok\n' > "$REPO3/state.txt"
printf 'ok\n' > "$REPO3/state2.txt"
printf 'x0\n' > "$REPO3/src/x.c"
printf 't0\n' > "$REPO3/tools/only_tools.txt"
( cd "$REPO3" && $GIT add -A && $GIT commit -q -m 'base G3' ) || exit 2
G3="$( cd "$REPO3" && $GIT rev-parse HEAD )"
landing3() {
    local name="$1"; shift
    ( cd "$REPO3" && $GIT checkout -q -b "$name" master ) || return 1
    ( cd "$REPO3" && eval "$*" ) || return 1
    ( cd "$REPO3" && $GIT add -A && $GIT commit -q -m "$name work" \
        && $GIT checkout -q master \
        && $GIT merge -q --no-ff -m "$name merge" "$name" ) || return 1
    ( cd "$REPO3" && $GIT rev-parse HEAD )
}
L3a="$(landing3 M1 'printf "a1\n" > a.txt')" || exit 2
L3b="$(landing3 M2 'printf "broken\n" > state.txt; printf "x1\n" > src/x.c')" || exit 2
L3c="$(landing3 M3 'printf "b1\n" > b.txt')" || exit 2
L3d="$(landing3 M4 'printf "broken\n" > state2.txt; printf "t1\n" > tools/only_tools.txt')" || exit 2
[ -n "$L3a" ] && [ -n "$L3b" ] && [ -n "$L3c" ] && [ -n "$L3d" ] || exit 2
T3="$( cd "$REPO3" && $GIT rev-parse HEAD )"

# ------------------------------------------------------------------ helpers ---
PASS=0
FAIL=0
note() { printf '  %s  %s\n' "$1" "$2"; }

# run_case <state-dir> <build-cmd> <budget> <date> [extra env assignments...]
# Builds a state file with the given lines (one per argument after the fixed
# ones is NOT used; callers write their own when needed). This wrapper exists
# only to keep the environment identical across cases.
fresh_state_dir() { # fresh_state_dir <name> -> a new directory path
    local d="$TMP/$1"
    mkdir -p "$d" || return 1
    printf '%s' "$d"
}

# names_landing <report> <hash>: the report names <hash> as a landing.
names_landing() { grep -qF -- "Named landing: $2" "$1"; }

# make_stubs <dir>: write a bead_new stub and a bd stub into <dir>. Both
# append their arguments to <dir>/bead_new.log and <dir>/bd.log. The bead_new
# stub prints inc-zz1 and exits 0, or prints candidates and exits 3 when
# STUB_DUP=1. Echoes the two paths, TAB-separated: bead_new then bd.
make_stubs() {
    local dir="$1"
    mkdir -p "$dir" || return 1
    cat > "$dir/bead_new_stub.sh" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$dir/bead_new.log"
if [ "\${STUB_DUP:-0}" = "1" ]; then
    echo "candidates: inc-yy9 0.91"
    exit 3
fi
echo "inc-zz1"
exit 0
EOF
    chmod +x "$dir/bead_new_stub.sh"
    cat > "$dir/bd_stub.sh" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$dir/bd.log"
exit 0
EOF
    chmod +x "$dir/bd_stub.sh"
    printf '%s\t%s' "$dir/bead_new_stub.sh" "$dir/bd_stub.sh"
}

# A global stub pair wired into every case, so no case can reach the real
# tools/bead_new.sh or bd. Cases 8-11 use their own pair for per-case logs.
GLOBAL_STUBS="$TMP/global-stubs"
GLOBAL_STUB_LINE="$(make_stubs "$GLOBAL_STUBS")" || exit 2
export NIGHTLY_BISECT_BEAD_NEW="${GLOBAL_STUB_LINE%%	*}"
export NIGHTLY_BISECT_BD="${GLOBAL_STUB_LINE##*	}"

# run_bisect <state-dir> <repo> <bead_new> <bd> [extra assignments...]:
# run the script with both stubs wired in and the usual env. Writes out.log.
run_bisect() {
    local d="$1" repo="$2" bn="$3" bd="$4"; shift 4
    env NIGHTLY_BISECT_BEAD_NEW="$bn" NIGHTLY_BISECT_BD="$bd" \
        NIGHTLY_VERIFY_STATE="$d/state.txt" NIGHTLY_BISECT_REPO="$repo" \
        NIGHTLY_BISECT_BUILD_CMD=true NIGHTLY_BISECT_DATE="$(date +%Y-%m-%d)" \
        "$@" bash "$BISECT" > "$d/out.log" 2>&1
}

# ------------------------------------------------------------------ case 1 ----
case1() {
    local d; d="$(fresh_state_dir case1)" || return 1
    printf '1\ttools/check_x.sh\n' > "$d/state.txt"
    printf 'tools/check_x.sh\t%s\t%s\n' "$G" "$(date +%Y-%m-%d)" > "$d/nightly-last-good.tsv"
    NIGHTLY_VERIFY_STATE="$d/state.txt" NIGHTLY_BISECT_REPO="$REPO" \
        NIGHTLY_BISECT_BUILD_CMD=true NIGHTLY_BISECT_DATE="$(date +%Y-%m-%d)" \
        bash "$BISECT" > "$d/out.log" 2>&1
    local rc=$?
    local rep="$d/nightly-bisect/$(date +%Y-%m-%d).md"
    [ "$rc" -eq 0 ] || { note FAIL "case1: exit $rc"; return 1; }
    [ -f "$rep" ] || { note FAIL "case1: no report"; return 1; }
    names_landing "$rep" "$L2" || { note FAIL "case1: did not name L2"; return 1; }
    names_landing "$rep" "$L1" && { note FAIL "case1: named L1"; return 1; }
    names_landing "$rep" "$L3" && { note FAIL "case1: named L3"; return 1; }
    names_landing "$rep" "$L4" && { note FAIL "case1: named L4"; return 1; }
    note ok "case1: names L2 only"
    return 0
}

# ------------------------------------------------------------------ case 2 ----
# check_y appears at L3 and fails from then on; last-good is G (absent there).
case2() {
    local d; d="$(fresh_state_dir case2)" || return 1
    # check_y (added at L3) is absent at G..L2, so it reads "could not
    # measure" there; its last good is G, where the file does not exist.
    printf '1\ttools/check_x.sh\n1\ttools/check_y.sh\n' > "$d/state.txt"
    printf 'tools/check_y.sh\t%s\t%s\n' "$G" "$(date +%Y-%m-%d)" > "$d/nightly-last-good.tsv"
    NIGHTLY_VERIFY_STATE="$d/state.txt" NIGHTLY_BISECT_REPO="$REPO" \
        NIGHTLY_BISECT_BUILD_CMD=true NIGHTLY_BISECT_DATE="$(date +%Y-%m-%d)" \
        bash "$BISECT" > "$d/out.log" 2>&1
    local rc=$?
    local rep="$d/nightly-bisect/$(date +%Y-%m-%d).md"
    [ "$rc" -eq 0 ] || { note FAIL "case2: exit $rc"; return 1; }
    # Its section must say not measured and name no landing.
    if ! awk -v id='## tools/check_y.sh' '
        $0 == id { insec=1; next }
        insec && /^## / { insec=0 }
        insec { print }
    ' "$rep" > "$d/y.sec" 2>/dev/null; then :; fi
    grep -qF 'not measured' "$d/y.sec" || { note FAIL "case2: check_y not 'not measured'"; return 1; }
    grep -qF 'Named landing' "$d/y.sec" && { note FAIL "case2: named a landing for absent check"; return 1; }
    note ok "case2: absent check names nothing"
    return 0
}

# ------------------------------------------------------------------ case 3 ----
# last-good names a commit on a side branch never merged.
case3() {
    local d; d="$(fresh_state_dir case3)" || return 1
    local orphan
    orphan="$( cd "$REPO" && $GIT checkout -q -b orphan "$G" \
        && printf 'x\n' > orphan.txt && $GIT add -A \
        && $GIT commit -q -m 'orphan work' && $GIT rev-parse HEAD )"
    ( cd "$REPO" && $GIT checkout -q master ) > /dev/null 2>&1
    printf '1\ttools/check_x.sh\n' > "$d/state.txt"
    printf 'tools/check_x.sh\t%s\t%s\n' "$orphan" "$(date +%Y-%m-%d)" > "$d/nightly-last-good.tsv"
    NIGHTLY_VERIFY_STATE="$d/state.txt" NIGHTLY_BISECT_REPO="$REPO" \
        NIGHTLY_BISECT_BUILD_CMD=true NIGHTLY_BISECT_DATE="$(date +%Y-%m-%d)" \
        bash "$BISECT" > "$d/out.log" 2>&1
    local rc=$?
    local rep="$d/nightly-bisect/$(date +%Y-%m-%d).md"
    [ "$rc" -eq 0 ] || { note FAIL "case3: exit $rc"; return 1; }
    grep -qF 'not an ancestor' "$rep" || { note FAIL "case3: no 'not an ancestor'"; return 1; }
    grep -qF 'Named landing' "$rep" && { note FAIL "case3: named a landing"; return 1; }
    note ok "case3: off-line last good names nothing"
    return 0
}

# ------------------------------------------------------------------ case 4 ----
# A check that fails on its first worktree run and passes on its second. The
# counter lives outside the worktree, in the case's temp dir, via an env var.
case4() {
    local d; d="$(fresh_state_dir case4)" || return 1
    # check_flaky exists at every candidate; its counter is outside the
    # worktree, so the first worktree run fails and the second passes.
    printf '1\ttools/check_flaky.sh\n' > "$d/state.txt"
    printf 'tools/check_flaky.sh\t%s\t%s\n' "$G" "$(date +%Y-%m-%d)" > "$d/nightly-last-good.tsv"
    : > "$d/counter"
    FLAKY_COUNTER="$d/counter" \
        NIGHTLY_VERIFY_STATE="$d/state.txt" NIGHTLY_BISECT_REPO="$REPO" \
        NIGHTLY_BISECT_BUILD_CMD=true NIGHTLY_BISECT_DATE="$(date +%Y-%m-%d)" \
        bash "$BISECT" > "$d/out.log" 2>&1
    local rc=$?
    local rep="$d/nightly-bisect/$(date +%Y-%m-%d).md"
    [ "$rc" -eq 0 ] || { note FAIL "case4: exit $rc"; return 1; }
    grep -qF 'Inconsistent' "$rep" || { note FAIL "case4: no 'Inconsistent'"; return 1; }
    grep -qF 'Named landing' "$rep" && { note FAIL "case4: named a landing"; return 1; }
    note ok "case4: flaky names nothing"
    return 0
}

# ------------------------------------------------------------------ case 5 ----
case5() {
    local d; d="$(fresh_state_dir case5)" || return 1
    printf '1\ttools/check_x.sh\n' > "$d/state.txt"
    printf 'tools/check_x.sh\t%s\t%s\n' "$G" "$(date +%Y-%m-%d)" > "$d/nightly-last-good.tsv"
    INCURSION_BISECT_BUDGET=0 \
        NIGHTLY_VERIFY_STATE="$d/state.txt" NIGHTLY_BISECT_REPO="$REPO" \
        NIGHTLY_BISECT_BUILD_CMD=true NIGHTLY_BISECT_DATE="$(date +%Y-%m-%d)" \
        bash "$BISECT" > "$d/out.log" 2>&1
    local rc=$?
    local rep="$d/nightly-bisect/$(date +%Y-%m-%d).md"
    [ "$rc" -eq 0 ] || { note FAIL "case5: exit $rc"; return 1; }
    grep -qF 'Time budget exceeded' "$rep" || { note FAIL "case5: no budget message"; return 1; }
    grep -qF 'Named landing' "$rep" && { note FAIL "case5: named a landing"; return 1; }
    note ok "case5: zero budget names nothing"
    return 0
}

# ------------------------------------------------------------------ case 6 ----
# A passing check moves last-good to T; a stale id (31 days before the
# NIGHTLY_BISECT_DATE, absent tonight) is dropped.
case6() {
    local d; d="$(fresh_state_dir case6)" || return 1
    local today stale
    today="$(date +%Y-%m-%d)"
    stale="$(date -v-31d +%Y-%m-%d 2>/dev/null || date -d '31 days ago' +%Y-%m-%d)"
    printf '0\ttools/check_x.sh\n' > "$d/state.txt"
    {
        printf 'tools/check_x.sh\t%s\t%s\n' "$G" "$today"
        printf 'tools/check_gone.sh\t%s\t%s\n' "$G" "$stale"
    } > "$d/nightly-last-good.tsv"
    NIGHTLY_VERIFY_STATE="$d/state.txt" NIGHTLY_BISECT_REPO="$REPO" \
        NIGHTLY_BISECT_BUILD_CMD=true NIGHTLY_BISECT_DATE="$today" \
        bash "$BISECT" > "$d/out.log" 2>&1
    local rc=$?
    [ "$rc" -eq 0 ] || { note FAIL "case6: exit $rc"; return 1; }
    local lg="$d/nightly-last-good.tsv"
    # check_x's last-good commit is now T.
    local got
    got="$(awk -F'\t' '$1 == "tools/check_x.sh" { print $2 }' "$lg")"
    [ "$got" = "$T" ] || { note FAIL "case6: last-good not T (got $got)"; return 1; }
    # The stale absent id is gone.
    grep -qF 'tools/check_gone.sh' "$lg" && { note FAIL "case6: stale id not dropped"; return 1; }
    note ok "case6: last-good moves to T, stale dropped"
    return 0
}

# ------------------------------------------------------------------ case 7 ----
# No worktree left behind; missing state file exits 2.
case7() {
    local d; d="$(fresh_state_dir case7)" || return 1
    printf '1\ttools/check_x.sh\n' > "$d/state.txt"
    printf 'tools/check_x.sh\t%s\t%s\n' "$G" "$(date +%Y-%m-%d)" > "$d/nightly-last-good.tsv"
    NIGHTLY_VERIFY_STATE="$d/state.txt" NIGHTLY_BISECT_REPO="$REPO" \
        NIGHTLY_BISECT_BUILD_CMD=true NIGHTLY_BISECT_DATE="$(date +%Y-%m-%d)" \
        bash "$BISECT" > "$d/out.log" 2>&1
    local rc=$?
    [ "$rc" -eq 0 ] || { note FAIL "case7: exit $rc"; return 1; }
    local n
    n="$( cd "$REPO" && $GIT worktree list | wc -l | tr -d ' ' )"
    [ "$n" -eq 1 ] || { note FAIL "case7: worktrees left behind ($n)"; return 1; }

    # A missing state file exits 2.
    NIGHTLY_VERIFY_STATE="$d/no-such-state.txt" NIGHTLY_BISECT_REPO="$REPO" \
        bash "$BISECT" > /dev/null 2>&1
    [ "$?" -eq 2 ] || { note FAIL "case7: missing state did not exit 2"; return 1; }
    note ok "case7: no worktree left; missing state exits 2"
    return 0
}

# ------------------------------------------------------------------ case 8 ----
# Two causes: L3b writes state.txt=broken, L3d writes state2.txt=broken, in
# REPO3 where check_multi reads both. The report names both landings and the
# bead_new stub is called twice.
case8() {
    local d; d="$(fresh_state_dir case8)" || return 1
    local stubs bn bd
    stubs="$(make_stubs "$d/stubs")"; bn="${stubs%%	*}"; bd="${stubs##*	}"
    printf '1\ttools/check_multi.sh\n' > "$d/state.txt"
    printf 'tools/check_multi.sh\t%s\t%s\n' "$G3" "$(date +%Y-%m-%d)" > "$d/nightly-last-good.tsv"
    run_bisect "$d" "$REPO3" "$bn" "$bd"
    local rc=$?
    local rep="$d/nightly-bisect/$(date +%Y-%m-%d).md"
    [ "$rc" -eq 0 ] || { note FAIL "case8: exit $rc"; return 1; }
    names_landing "$rep" "$L3b" || { note FAIL "case8: did not name first cause"; return 1; }
    names_landing "$rep" "$L3d" || { note FAIL "case8: did not name second cause"; return 1; }
    local calls
    calls="$(wc -l < "$d/stubs/bead_new.log" | tr -d ' ')"
    [ "$calls" -eq 2 ] || { note FAIL "case8: bead_new called $calls times"; return 1; }
    note ok "case8: two causes named, two beads filed"
    return 0
}

# ------------------------------------------------------------------ case 9 ----
# Revert conflict: L2b wrote state.txt=broken, L2c edited that same line, so
# reverting L2b at T conflicts. The report says revert conflict and names only
# L2b (the first cause).
case9() {
    local d; d="$(fresh_state_dir case9)" || return 1
    local stubs bn bd
    stubs="$(make_stubs "$d/stubs")"; bn="${stubs%%	*}"; bd="${stubs##*	}"
    printf '1\ttools/check_multi.sh\n' > "$d/state.txt"
    printf 'tools/check_multi.sh\t%s\t%s\n' "$G2" "$(date +%Y-%m-%d)" > "$d/nightly-last-good.tsv"
    run_bisect "$d" "$REPO2" "$bn" "$bd"
    local rc=$?
    local rep="$d/nightly-bisect/$(date +%Y-%m-%d).md"
    [ "$rc" -eq 0 ] || { note FAIL "case9: exit $rc"; return 1; }
    grep -qF 'revert conflict' "$rep" || { note FAIL "case9: no 'revert conflict'"; return 1; }
    names_landing "$rep" "$L2b" || { note FAIL "case9: did not name L2b"; return 1; }
    names_landing "$rep" "$L2c" && { note FAIL "case9: named a second cause"; return 1; }
    note ok "case9: revert conflict names only first cause"
    return 0
}

# ----------------------------------------------------------------- case 10 ----
# Duplicate path: the bead_new stub exits 3 and prints a candidate. Nothing is
# filed; the bd stub is called with --append-notes on inc-yy9.
case10() {
    local d; d="$(fresh_state_dir case10)" || return 1
    local stubs bn bd
    stubs="$(make_stubs "$d/stubs")"; bn="${stubs%%	*}"; bd="${stubs##*	}"
    printf '1\ttools/check_x.sh\n' > "$d/state.txt"
    printf 'tools/check_x.sh\t%s\t%s\n' "$G" "$(date +%Y-%m-%d)" > "$d/nightly-last-good.tsv"
    run_bisect "$d" "$REPO" "$bn" "$bd" STUB_DUP=1
    local rc=$?
    local rep="$d/nightly-bisect/$(date +%Y-%m-%d).md"
    [ "$rc" -eq 0 ] || { note FAIL "case10: exit $rc"; return 1; }
    grep -qF 'Filed:' "$rep" && { note FAIL "case10: filed a duplicate"; return 1; }
    grep -qF 'inc-yy9' "$d/stubs/bd.log" || { note FAIL "case10: bd not noted on inc-yy9"; return 1; }
    grep -qF -- '--append-notes' "$d/stubs/bd.log" || { note FAIL "case10: no --append-notes"; return 1; }
    note ok "case10: duplicate noted, nothing filed"
    return 0
}

# ----------------------------------------------------------------- case 11 ----
# Labels: L3b changed src/x.c -> public; L3d changed only tools/ -> internal.
case11() {
    local d; d="$(fresh_state_dir case11)" || return 1
    local stubs bn bd
    stubs="$(make_stubs "$d/stubs")"; bn="${stubs%%	*}"; bd="${stubs##*	}"
    printf '1\ttools/check_multi.sh\n' > "$d/state.txt"
    printf 'tools/check_multi.sh\t%s\t%s\n' "$G3" "$(date +%Y-%m-%d)" > "$d/nightly-last-good.tsv"
    run_bisect "$d" "$REPO3" "$bn" "$bd"
    local rc=$?
    [ "$rc" -eq 0 ] || { note FAIL "case11: exit $rc"; return 1; }
    grep -qF -- '--labels public' "$d/stubs/bead_new.log" || { note FAIL "case11: no public label"; return 1; }
    grep -qF -- '--labels internal' "$d/stubs/bead_new.log" || { note FAIL "case11: no internal label"; return 1; }
    note ok "case11: public and internal labels correct"
    return 0
}

# ----------------------------------------------------------------- case 12 ----
# Case 1 again with the filing stub: L2 is the only cause, the report says so,
# and the bead_new stub was called once with a title naming L2's bead id.
case12() {
    local d; d="$(fresh_state_dir case12)" || return 1
    local stubs bn bd
    stubs="$(make_stubs "$d/stubs")"; bn="${stubs%%	*}"; bd="${stubs##*	}"
    printf '1\ttools/check_x.sh\n' > "$d/state.txt"
    printf 'tools/check_x.sh\t%s\t%s\n' "$G" "$(date +%Y-%m-%d)" > "$d/nightly-last-good.tsv"
    run_bisect "$d" "$REPO" "$bn" "$bd"
    local rc=$?
    local rep="$d/nightly-bisect/$(date +%Y-%m-%d).md"
    [ "$rc" -eq 0 ] || { note FAIL "case12: exit $rc"; return 1; }
    grep -qF 'only cause' "$rep" || { note FAIL "case12: no 'only cause'"; return 1; }
    names_landing "$rep" "$L2" || { note FAIL "case12: did not name L2"; return 1; }
    local calls
    calls="$(wc -l < "$d/stubs/bead_new.log" | tr -d ' ')"
    [ "$calls" -eq 1 ] || { note FAIL "case12: bead_new called $calls times"; return 1; }
    grep -qF 'inc-test2' "$d/stubs/bead_new.log" || { note FAIL "case12: title lacks bead id"; return 1; }
    note ok "case12: only cause, one bead titled with bead id"
    return 0
}

# ------------------------------------------------------------------- drive ----
run_case() {
    local name="$1" fn="$2"
    if "$fn"; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
    fi
}

run_case case1 case1
run_case case2 case2
run_case case3 case3
run_case case4 case4
run_case case5 case5
run_case case6 case6
run_case case7 case7
run_case case8 case8
run_case case9 case9
run_case case10 case10
run_case case11 case11
run_case case12 case12

echo "check_nightly_bisect: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
