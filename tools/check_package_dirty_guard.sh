#!/bin/bash
# gate: cheap
# Does every packager refuse a dirty working tree before it builds, signs or
# ships anything? A release on 2026-09-11 shipped another session's uncommitted
# files because the packagers stage the working tree, not a commit. inc-iezk.
#
# Three parts, no Docker and no real build:
#   a. tools/require_clean_tree.sh itself, in throwaway `git init` repos: clean
#      passes, a tracked edit fails, INCURSION_ALLOW_DIRTY=1 warns and passes, a
#      staged edit fails, an untracked file passes, and outside a repo it fails.
#   b. every tools/package_*.sh (glob, so a new packager is covered) copied into
#      a throwaway dirty repo with stub docker/codesign/xcrun/hdiutil first on
#      PATH: it must fail on the dirty tree and never reach a stub or a build.
#   c. every tools/package_*.sh in the real tree calls require_clean_tree.sh.
#
# Exit: 0 pass, 1 fail.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1

FAIL=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; FAIL=1; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/package-dirty-guard.XXXXXX")" || {
    echo "FAIL: mktemp failed"; exit 1; }
trap 'rm -rf "$TMP"' EXIT

# ---------------------------------------------------------------- helpers ----
# Build a throwaway repo with one committed file and a local identity.
new_repo() {
    local dir="$1"
    mkdir -p "$dir" || return 1
    git -C "$dir" init -q || return 1
    git -C "$dir" config user.name "guard check"
    git -C "$dir" config user.email "guard@example.invalid"
    printf 'one\n' > "$dir/tracked.txt"
    git -C "$dir" add tracked.txt
    git -C "$dir" commit -q -m "seed"
}

run_guard() {
    local dir="$1"; shift
    ( cd "$dir" && env "$@" "$ROOT/tools/require_clean_tree.sh" 2>&1 )
}

# ----------------------------------------------------------------- a. guard ----
echo "== a. require_clean_tree.sh =="

A="$TMP/a"
new_repo "$A" || fail "could not build a throwaway repo"

out="$(run_guard "$A")"; rc=$?
if [ "$rc" -eq 0 ] && grep -q 'packaging HEAD' <<< "$out" \
        && grep -q 'tree: clean' <<< "$out"; then
    pass "clean tree exits 0 and names the commit"
else
    fail "clean tree: expected exit 0 with 'packaging HEAD' and 'tree: clean', got rc=$rc:"
    printf '%s\n' "$out"
fi

printf 'dirty\n' >> "$A/tracked.txt"
out="$(run_guard "$A")"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'FAIL: the tree has uncommitted changes' <<< "$out" \
        && grep -q 'tracked.txt' <<< "$out"; then
    pass "modified tracked file exits 1 and names it"
else
    fail "modified tracked file: expected exit 1 naming tracked.txt, got rc=$rc:"
    printf '%s\n' "$out"
fi

out="$(run_guard "$A" INCURSION_ALLOW_DIRTY=1)"; rc=$?
if [ "$rc" -eq 0 ] && grep -q 'WARNING' <<< "$out"; then
    pass "INCURSION_ALLOW_DIRTY=1 warns and exits 0"
else
    fail "INCURSION_ALLOW_DIRTY=1: expected exit 0 with WARNING, got rc=$rc:"
    printf '%s\n' "$out"
fi

# Restore, then stage an edit without committing.
git -C "$A" checkout -q -- tracked.txt
printf 'staged\n' >> "$A/tracked.txt"
git -C "$A" add tracked.txt
out="$(run_guard "$A")"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'tracked.txt' <<< "$out"; then
    pass "staged-but-uncommitted edit exits 1"
else
    fail "staged edit: expected exit 1 naming tracked.txt, got rc=$rc:"
    printf '%s\n' "$out"
fi
git -C "$A" reset -q --hard >/dev/null

printf 'new\n' > "$A/untracked.txt"
out="$(run_guard "$A")"; rc=$?
if [ "$rc" -eq 0 ] && grep -q 'tree: clean' <<< "$out"; then
    pass "only an untracked file exits 0"
else
    fail "untracked-only: expected exit 0, got rc=$rc:"
    printf '%s\n' "$out"
fi

NOTREPO="$TMP/notrepo"
mkdir -p "$NOTREPO"
out="$(run_guard "$NOTREPO")"; rc=$?
if [ "$rc" -ne 0 ] && grep -q 'FAIL' <<< "$out"; then
    pass "outside any git repo exits non-zero"
else
    fail "outside a repo: expected non-zero with FAIL, got rc=$rc:"
    printf '%s\n' "$out"
fi

# ------------------------------------------------------------ b. packagers ----
echo "== b. packagers refuse before any build =="

# Stub tools that each print STUB-REACHED and exit 1, so any reachability shows.
mkdir -p "$TMP/stub"
for tool in docker codesign xcrun hdiutil; do
    cat > "$TMP/stub/$tool" <<'STUB'
#!/bin/bash
echo STUB-REACHED
exit 1
STUB
    chmod +x "$TMP/stub/$tool"
done

PACKAGERS="$(ls tools/package_*.sh 2>/dev/null)"
if [ -z "$PACKAGERS" ]; then
    fail "no tools/package_*.sh found to exercise"
fi

for pkgr in $PACKAGERS; do
    B="$TMP/b-$(basename "$pkgr" .sh)"
    mkdir -p "$B/tools"
    new_repo "$B" || { fail "could not build a repo for $pkgr"; continue; }
    cp -f "$pkgr" "$B/tools/"
    cp -f tools/require_clean_tree.sh "$B/tools/"
    git -C "$B" add tools
    git -C "$B" commit -q -m "add packager"
    # Dirty one tracked file the packager will see.
    printf 'dirty\n' >> "$B/tracked.txt"

    out="$( cd "$B" && PATH="$TMP/stub:$PATH" "./tools/$(basename "$pkgr")" 2>&1 )"; rc=$?
    bad=0
    [ "$rc" -eq 1 ] || { bad=1; echo "  $pkgr: expected exit 1, got $rc"; }
    grep -q 'FAIL: the tree has uncommitted changes' <<< "$out" \
        || { bad=1; echo "  $pkgr: output lacks the dirty-tree FAIL line"; }
    grep -q 'STUB-REACHED' <<< "$out" \
        && { bad=1; echo "  $pkgr: reached a build/sign tool (STUB-REACHED)"; }
    grep -qE '=== [0-9]+/' <<< "$out" \
        && { bad=1; echo "  $pkgr: a build step started"; }
    if [ "$bad" -eq 0 ]; then
        pass "$(basename "$pkgr") refuses the dirty tree before any build"
    else
        fail "$(basename "$pkgr") did not refuse early:"
        printf '%s\n' "$out"
    fi
done

# -------------------------------------------------------------- c. static ----
echo "== c. every packager calls the guard (static) =="
for pkgr in $PACKAGERS; do
    if grep -q 'require_clean_tree.sh' "$pkgr"; then
        pass "$(basename "$pkgr") calls require_clean_tree.sh"
    else
        fail "$(basename "$pkgr") does not call require_clean_tree.sh"
    fi
done

if [ "$FAIL" -eq 0 ]; then
    echo
    echo "package dirty guard: packagers refuse a dirty tree"
    exit 0
fi
echo
echo "package dirty guard: FAILED"
exit 1
