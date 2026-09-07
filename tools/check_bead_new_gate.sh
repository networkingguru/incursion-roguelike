#!/bin/bash
# Does tools/bead_new.sh actually refuse an unfit bead?
#
#   tools/check_bead_new_gate.sh      (0 pass, 1 fail)
#
# A gate nobody has watched bite is a gate you are trusting on its comments.
# tools/check_bead_publish.py had exactly that problem: it was written on
# 2026-09-02, three documents said it failed a commit, and it was wired into
# nothing for four days while inc-b12m reached the public tracker with an empty
# body. So this file watches the wrapper bite before anyone relies on it.
#
# IT NEVER TOUCHES THE REAL DATABASE. `bd` and the checker are both stubbed on
# PATH, so no bead is filed, none is deleted, and the run leaves nothing
# behind. That matters more than it looks: the obvious way to test this script
# is to file a deliberately broken bead, and a broken bead filed by a test is
# indistinguishable from a broken bead filed by a person -- it would block the
# next commit in the tree.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
FAIL=0

ok()  { echo "OK    $1"; }
bad() { echo "FAIL  $1"; FAIL=1; }

# A stub bd that answers `create ... --json` with a fixed id and nothing else.
cat > "$TMP/bd" <<'STUB'
#!/bin/bash
for a in "$@"; do [ "$a" = "create" ] && { echo '{"id": "inc-stub"}'; exit 0; }; done
exit 0
STUB
chmod +x "$TMP/bd"

# A stub checker whose verdict the test chooses, so both branches are reachable
# without depending on what any real bead happens to contain today.
make_checker() {
    cat > "$TMP/check_bead_publish.py" <<STUB
#!/bin/bash
echo "stub checker saw: \$*"
exit $1
STUB
    chmod +x "$TMP/check_bead_publish.py"
}

# The wrapper calls the checker by absolute path under ROOT, so the stub has to
# stand in for that path. Copy the wrapper into a throwaway tree instead of
# editing the real one.
mkdir -p "$TMP/tree/tools"
cp "$ROOT/tools/bead_new.sh" "$TMP/tree/tools/"
run_wrapper() {
    make_checker "$1"
    cp "$TMP/check_bead_publish.py" "$TMP/tree/tools/check_bead_publish.py"
    PATH="$TMP:$PATH" "$TMP/tree/tools/bead_new.sh" "a title" 2>&1
}

# 1. an unfit bead must fail the wrapper, not be waved through
OUT=$(run_wrapper 1); RC=$?
[ $RC -eq 1 ] && ok "unfit bead: wrapper exits 1" \
              || bad "unfit bead: wrapper exited $RC, wanted 1"
case "$OUT" in
    *"NOT fit to publish"*) ok "unfit bead: says what is wrong" ;;
    *) bad "unfit bead: no explanation in the output" ;;
esac
case "$OUT" in
    *inc-stub*) ok "unfit bead: names the id it filed" ;;
    *) bad "unfit bead: did not name the bead id" ;;
esac

# 2. a fit bead must pass, or the wrapper is useless in daily work
OUT=$(run_wrapper 0); RC=$?
[ $RC -eq 0 ] && ok "fit bead: wrapper exits 0" \
              || bad "fit bead: wrapper exited $RC, wanted 0"

# 3. the checker must be asked about the id that was just filed, by --bead.
#    Without this the wrapper could "pass" by checking nothing at all.
case "$OUT" in
    *"--bead inc-stub"*) ok "the filed id is what gets checked" ;;
    *) bad "the wrapper did not run --bead against the new id" ;;
esac

# 4. --dry-run must not be checked, because it files nothing
OUT=$(PATH="$TMP:$PATH" "$TMP/tree/tools/bead_new.sh" --dry-run "t" 2>&1); RC=$?
[ $RC -eq 0 ] && ok "--dry-run passes straight through" \
              || bad "--dry-run exited $RC, wanted 0"
case "$OUT" in
    *"stub checker"*) bad "--dry-run ran the checker on a bead that was never filed" ;;
    *) ok "--dry-run does not run the checker" ;;
esac

echo ""
[ $FAIL -eq 0 ] && echo "bead_new gate verified" || echo "bead_new gate BROKEN"
exit $FAIL
