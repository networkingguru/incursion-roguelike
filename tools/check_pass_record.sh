#!/usr/bin/env bash
# gate: cheap
#
# Does a landing reuse a full gate pass on the same files, and only then?
#
#   tools/check_pass_record.sh      run every case
#
# WHY THIS EXISTS. tools/finish_bead.sh used to run the whole gate, about ten
# minutes, on files that had just passed it (inc-689z). tools/nightly_verify.sh
# now records each full pass, and --reuse-pass re-runs only the cheap tier when
# the files, the recorded base and the toolchain all match that record. A fault
# is quiet in both directions: too loose and a landing trusts a pass nobody
# earned, too tight and every landing pays for the gate twice again.
#
# IT TESTS A SCRATCH REPOSITORY, NOT THIS ONE. It copies the real
# nightly_verify.sh, finish_bead.sh and docs_only_change.sh into a repository
# under TMPDIR, beside a fake build and fake checks that log each call. The
# count of build calls is the oracle: a full gate builds twice, a reused pass
# builds nothing. Nothing here touches the repository it is run from.
#
# THE SUITE CANNOT PASS VACUOUSLY. Some cases demand a reuse and some demand a
# full run, so a record that never matches fails the first kind and a record
# that always matches fails the second.
#
# Exit: 0 every case behaved
#       1 a case did not
#       2 could not measure
set -uo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
for f in nightly_verify.sh finish_bead.sh docs_only_change.sh; do
    [ -r "$ROOT/tools/$f" ] || { echo "check_pass_record: no tools/$f" >&2; exit 2; }
done
command -v git > /dev/null 2>&1 || { echo "check_pass_record: no git" >&2; exit 2; }

TMP=$(mktemp -d "${TMPDIR:-/tmp}/pass-record.XXXXXX") || exit 2
trap 'chmod -R u+rw "$TMP" 2> /dev/null; rm -rf "$TMP"' EXIT
# The physical path, so git and finish_bead.sh spell every worktree the same way.
TMP=$(cd "$TMP" && pwd -P) || exit 2

# A scratch repository answers to nothing the person running this has
# configured, and the gate's own variables would point these runs at real state.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export PATH=/usr/bin:/bin
unset NIGHTLY_VERIFY_STATE NIGHTLY_CHECK_DIR NIGHTLY_BASE_REF \
      INCURSION_FINISH_GATE INCURSION_BASE_BRANCH INCURSIONPATH CC CXX

REPO="$TMP/repo"
LOG="$TMP/calls"             # one line per call of the fake build or a fake check
FAIL_LIVE="$TMP/fail-live"   # while this exists, the live check fails
TOUCH_LIVE="$TMP/touch-live" # while this exists, the live check edits a tracked file
: > "$LOG"

mkdir -p "$REPO/tools" "$REPO/src"
cp "$ROOT/tools/nightly_verify.sh" "$ROOT/tools/finish_bead.sh" \
   "$ROOT/tools/docs_only_change.sh" "$REPO/tools/" || exit 2
printf '#!/bin/sh\necho build >> "%s"\n' "$LOG" > "$REPO/build_macos.sh"
# The three steps that run beside the builds. No gate marker, so not checks.
for step in check_linux_build.sh check_layout_sweep.sh gate_compare.sh; do
    printf '#!/bin/sh\nexit 0\n' > "$REPO/tools/$step"
done
printf '#!/bin/sh\n# gate: cheap\necho cheap >> "%s"\n' "$LOG" > "$REPO/tools/check_fake_cheap.sh"
printf '#!/bin/sh\n# gate: live\necho live >> "%s"\n[ -e "%s" ] && echo x >> src/game.c\n[ -e "%s" ] && exit 1\nexit 0\n' \
    "$LOG" "$TOUCH_LIVE" "$FAIL_LIVE" > "$REPO/tools/check_fake_live.sh"
chmod +x "$REPO/build_macos.sh" "$REPO"/tools/*.sh
printf 'logs/\n' > "$REPO/.gitignore"
echo 'int main(void) { return 0; }' > "$REPO/src/game.c"

git init -q "$REPO" || exit 2
git -C "$REPO" symbolic-ref HEAD refs/heads/master
git -C "$REPO" config user.name "gate"
git -C "$REPO" config user.email "gate@example.invalid"
git -C "$REPO" config commit.gpgsign false
git -C "$REPO" add -A
git -C "$REPO" commit -q --no-verify -m "base" || exit 2

fails=0
OUT=""; RC=0; BUILT=0
calls()  { grep -c "^$1\$" "$LOG"; }
commit() { git -C "$1" add -A && git -C "$1" commit -q --no-verify -m "$2"; }
bead()   { git -C "$REPO" worktree add -q -b "$1" "$TMP/Incursion-$1" master; }
record() { printf '%s/logs/nightly-verify-pass.txt' "$1"; }

# run <dir> <command...> -> OUT, RC, and BUILT: the builds this run made
run() {
    local dir=$1 b; shift
    b=$(calls build)
    OUT=$(cd "$dir" && "$@" 2>&1); RC=$?
    BUILT=$(( $(calls build) - b ))
}
gate() { run "$1" tools/nightly_verify.sh "${@:2}"; }
land() { run "$REPO" tools/finish_bead.sh "$1"; }

expect() { # expect <label> <command...>
    local label=$1; shift
    if "$@"; then
        printf 'ok    %s\n' "$label"
    else
        printf 'FAIL  %s\n' "$label"
        printf '%s\n' "$OUT" | sed 's/^/        /' | tail -8
        fails=$(( fails + 1 ))
    fi
}
says() { printf '%s\n' "$OUT" | grep -q -- "$1"; }

expect "the real record path is ignored in this repository" \
    git -C "$ROOT" check-ignore -q logs/nightly-verify-pass.txt

# The first report: a green gate, a merge refused because the master checkout
# is dirty, then the same landing again.
bead inc-aaaa; W="$TMP/Incursion-inc-aaaa"
echo 'int a;' >> "$W/src/game.c"; commit "$W" "fix: a"
touch "$REPO/dirt.txt"
land inc-aaaa
expect "an interrupted landing stops at the dirty master checkout" [ "$RC" = 1 ]
expect "  after it ran the full gate" [ "$BUILT" = 2 ]
rm -f "$REPO/dirt.txt"
live=$(calls live)
land inc-aaaa
expect "the same landing again lands" [ "$RC" = 0 ]
expect "  without building" [ "$BUILT" = 0 ]
expect "  without the live tier" [ "$(calls live)" = "$live" ]
expect "  and names the pass it reused" says "REUSED from a full pass at"

# The second report: the gate ran before the commit, and the commit changes no
# file, so the pass still holds.
bead inc-bbbb; W="$TMP/Incursion-inc-bbbb"
echo 'int b;' >> "$W/src/game.c"
gate "$W" --compare
commit "$W" "fix: b"
land inc-bbbb
expect "a gate run before the commit counts at the landing" [ "$RC" = 0 ]
expect "  so the landing does not build" [ "$BUILT" = 0 ]
expect "  and says so" says "REUSED from a full pass at"

# One byte changed after the pass.
bead inc-cccc; W="$TMP/Incursion-inc-cccc"
echo 'int c;' >> "$W/src/game.c"
gate "$W" --compare
printf x >> "$W/src/game.c"; commit "$W" "fix: c"
land inc-cccc
expect "one byte changed after the pass runs the full gate" [ "$BUILT" = 2 ]
expect "  and says why" says "the files differ"

# Master moved after the pass, so the landing's merge changes the files.
bead inc-dddd; W="$TMP/Incursion-inc-dddd"
echo 'int d;' >> "$W/src/game.c"
gate "$W" --compare
commit "$W" "fix: d"
echo 'int m;' > "$REPO/src/other.c"; commit "$REPO" "fix: master moves"
land inc-dddd
expect "a master that moved after the pass runs the full gate" [ "$BUILT" = 2 ]

# An explicit INCURSION_FINISH_GATE is run as given, record or no record.
bead inc-ffff; W="$TMP/Incursion-inc-ffff"
echo 'int f;' >> "$W/src/game.c"
gate "$W" --compare
commit "$W" "fix: f"
export INCURSION_FINISH_GATE="tools/nightly_verify.sh --compare"
land inc-ffff
unset INCURSION_FINISH_GATE
expect "an explicit INCURSION_FINISH_GATE is honoured untouched" [ "$BUILT" = 2 ]

# The record itself, driven through --reuse-pass in one worktree that never
# lands. Each case starts from a fresh full pass.
bead inc-eeee; W="$TMP/Incursion-inc-eeee"; R=$(record "$W")
echo 'int e;' >> "$W/src/game.c"
fresh() { gate "$W" --compare; }

fresh; gate "$W" --reuse-pass
expect "a matching record is reused" [ "$BUILT" = 0 ]

fresh; echo junk > "$W/logs/junk.txt"; gate "$W" --reuse-pass
expect "an ignored file does not change the key" [ "$BUILT" = 0 ]

fresh; echo 'int n;' > "$W/src/new.c"; gate "$W" --reuse-pass
expect "an untracked file changes the key" [ "$BUILT" = 2 ]
rm -f "$W/src/new.c"

fresh; echo "0	tools/check_fake_cheap.sh" > "$W/logs/nightly-verify-base.txt"
gate "$W" --reuse-pass
expect "a changed base is a miss" [ "$BUILT" = 2 ]
expect "  and says why" says "the recorded base changed"
rm -f "$W/logs/nightly-verify-base.txt"

fresh; export CXX=/usr/bin/false; gate "$W" --reuse-pass; unset CXX
expect "a changed toolchain variable is a miss" [ "$BUILT" = 2 ]
expect "  and says why" says "the toolchain"

fresh; export INCURSIONPATH=/elsewhere; gate "$W" --reuse-pass; unset INCURSIONPATH
expect "a changed variable the game reads is a miss" [ "$BUILT" = 2 ]

# A landing onto an epic branch sets this; a gate run by hand does not.
fresh; export INCURSION_BASE_BRANCH=epic; gate "$W" --reuse-pass; unset INCURSION_BASE_BRANCH
expect "finish_bead.sh's own variable is not part of the key" [ "$BUILT" = 0 ]

fresh; sed "s/^time .*/time $(( $(date +%s) - 86401 ))/" "$R" > "$R.new"; mv -f "$R.new" "$R"
gate "$W" --reuse-pass
expect "a record over 24 hours old is a miss" [ "$BUILT" = 2 ]

fresh; sed "s/^time .*/time $(( $(date +%s) - 86000 ))/" "$R" > "$R.new"; mv -f "$R.new" "$R"
old=$(sed -n 's/^time //p' "$R")
gate "$W" --reuse-pass
expect "a record 23 hours old is still reused" [ "$BUILT" = 0 ]
expect "  and the reuse does not renew it" [ "$(sed -n 's/^time //p' "$R")" = "$old" ]

fresh; echo garbage > "$R"; gate "$W" --reuse-pass
expect "a malformed record is a miss" [ "$BUILT" = 2 ]
expect "  and says why" says "malformed"

fresh; sed 's/^time .*/time 99999999999999999999999/' "$R" > "$R.new"; mv -f "$R.new" "$R"
gate "$W" --reuse-pass
expect "a time too large to subtract is malformed, not a match" says "malformed"

fresh; chmod 000 "$R"
if [ -r "$R" ]; then
    echo "skip  an unreadable record (this user can read a mode-000 file)"
else
    gate "$W" --reuse-pass
    expect "an unreadable record is a miss" [ "$BUILT" = 2 ]
fi
chmod 600 "$R"

rm -f "$R"; gate "$W" --reuse-pass
expect "no record is a miss" [ "$BUILT" = 2 ]
expect "  and says why" says "no full pass on record"

fresh; touch "$FAIL_LIVE"; gate "$W" --compare; rm -f "$FAIL_LIVE"
expect "a full run that fails" [ "$RC" = 1 ]
expect "  deletes the earlier pass on the same files" [ ! -e "$R" ]

touch "$TOUCH_LIVE"; gate "$W" --compare; rm -f "$TOUCH_LIVE"
expect "a full run whose files change while it runs" [ "$RC" = 0 ]
expect "  writes no record" [ ! -e "$R" ]

gate "$W" --checks-only
expect "a --checks-only run" [ "$RC" = 0 ]
expect "  writes no record" [ ! -e "$R" ]
gate "$W" --docs-only
expect "a --docs-only run" [ "$RC" = 0 ]
expect "  writes no record" [ ! -e "$R" ]

echo
if [ "$fails" = 0 ]; then
    echo "PASS: every case behaved"
    exit 0
fi
echo "FAIL: $fails case(s)"
exit 1
