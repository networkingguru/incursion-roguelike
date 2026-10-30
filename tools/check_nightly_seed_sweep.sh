#!/usr/bin/env bash
# gate: cheap
#
# Does tools/nightly_seed_sweep.sh pick, queue, rotate, budget, build its own trees and report
# correctly? (inc-ug5y, inc-jt3yu)
#   tools/check_nightly_seed_sweep.sh
# NIGHTLY_SWEEP_SCRIPT=<copy> points the check at a mutated copy of the script.
# The script runs inside a git repo made in a temp dir, so its worktrees never touch this one.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="${NIGHTLY_SWEEP_SCRIPT:-$ROOT/tools/nightly_seed_sweep.sh}"
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
T="$(cd "$T" && pwd -P)"
REPO="$T/repo"
BASE="$T/base"
mkdir -p "$T/rc" "$REPO/tools"
fail=0
ok() { echo "ok: $1"; }
bad() { echo "FAIL: $1"; fail=1; }

git init -q -b master "$REPO"
git -C "$REPO" config user.name t; git -C "$REPO" config user.email t@t
printf 'logs/\n' > "$REPO/.gitignore"
cp "$SCRIPT" "$REPO/tools/nightly_seed_sweep.sh"; chmod +x "$REPO/tools/nightly_seed_sweep.sh"
for spec in a:live b:live c:smoke d:cheap e:live; do
    printf '#!/usr/bin/env bash\n# gate: %s\n' "${spec##*:}" > "$REPO/tools/check_${spec%%:*}.sh"
done
git -C "$REPO" add -A; git -C "$REPO" commit -q -m init
echo 0 > "$T/rc/check_a.sh"; echo 1 > "$T/rc/check_b.sh"
echo 0 > "$T/rc/check_c.sh"; echo 2 > "$T/rc/check_e.sh"
cat > "$T/sweep" <<STUB
#!/usr/bin/env bash
n="\$(basename "\$3")"
echo "\$n|\$PWD|\$2|\$(date +%s)" >> "$T/swept.log"
sleep "\$(cat "$T/sleep" 2>/dev/null || echo 0)"
date +%s >> "$T/ends.log"
echo "verdict for \$n"
exit "\$(cat "$T/rc/\$n")"
STUB
printf '#!/usr/bin/env bash\nexit 0\n' > "$T/guard"
chmod +x "$T/sweep" "$T/guard"

run() { # run <budget> [lanes]; uses $T/state, $T/pending, $T/report.md
    : > "$T/swept.log"; : > "$T/ends.log"
    NIGHTLY_SWEEP_CMD="$T/sweep" NIGHTLY_SWEEP_LOAD_GUARD="$T/guard" \
        NIGHTLY_SWEEP_BUILD_CMD=true NIGHTLY_SWEEP_BASE="$BASE" \
        "$REPO/tools/nightly_seed_sweep.sh" --budget "$1" --lanes "${2:-1}" --state "$T/state" \
        --pending "$T/pending" --report "$T/report.md" > "$T/stdout" 2>&1
    local rc=$?
    [ "$rc" -eq 0 ] || echo "note: sweep script exited $rc: $(tail -3 "$T/stdout" | tr '\n' ' ')"
    return "$rc"
}
swept() { cut -d'|' -f1 "$T/swept.log" | tr '\n' ' ' | sed 's/check_//g; s/\.sh//g; s/ $//'; }
statekey() { sed -n "s/^$1=//p" "$T/state"; }
setcheck() { { grep -v '^last_check=' "$T/state"; echo "last_check=$1"; } > "$T/state.new"; mv "$T/state.new" "$T/state"; }
touchcheck() { echo "# edit $RANDOM" >> "$REPO/tools/$1"; git -C "$REPO" commit -q -am "edit $1"; }

run 100; rc=$?
[ "$rc" -eq 0 ] && ok "exit 0 with a seed-dependent check" || bad "exit $rc, want 0"
[ "$(swept)" = "a b c e" ] && ok "only live/smoke swept, each once" || bad "swept '$(swept)', want 'a b c e'"
grep -q 'check_d' "$T/swept.log" && bad "cheap check swept"
[ "$(statekey last_check)" = "check_e.sh" ] && ok "state names last check" || bad "state '$(cat "$T/state")'"
[ "$(statekey last_commit)" = "$(git -C "$REPO" rev-parse master)" ] && ok "state names the swept commit" || bad "last_commit '$(statekey last_commit)'"
sec_dep="$(sed -n '/^## Seed-dependent/,/^## No answer/p' "$T/report.md")"
sec_no="$(sed -n '/^## No answer/,/^## Changed/p' "$T/report.md")"
echo "$sec_dep" | grep -q 'check_b.sh.*verdict for check_b.sh' && ok "exit-1 check under Seed-dependent" || bad "Seed-dependent section: $sec_dep"
echo "$sec_no" | grep -q 'check_e.sh.*exit 2' && ok "exit-2 check under No answer" || bad "No answer section: $sec_no"
grep -q 'A check must not depend on the seed' "$T/report.md" && ok "report names VERIFICATION rule" || bad "rule line missing"
grep -q '^- lanes: 1$' "$T/report.md" && ok "report names the lane count" || bad "lanes line missing"

# 4. every sweep ran under the sweep base, never the repo root, with 5 distinct slot dirs
badpwd=0; badslots=0
while IFS='|' read -r n pwd_ slots _; do
    case "$pwd_" in "$BASE"/*) ;; *) badpwd=1 ;; esac
    [ "$pwd_" = "$REPO" ] && badpwd=1
    [ "$(echo $slots | tr ' ' '\n' | sort -u | grep -c "^$BASE/")" -eq 5 ] || badslots=1
done < "$T/swept.log"
[ "$badpwd" -eq 0 ] && ok "every sweep ran under the sweep base, not the repo root" || bad "a sweep ran outside the base: $(cat "$T/swept.log")"
[ "$badslots" -eq 0 ] && ok "every sweep got 5 distinct slot dirs under the base" || bad "slots: $(cat "$T/swept.log")"

# 5. trees are removed, and a leftover worktree under the base goes
[ "$(git -C "$REPO" worktree list | wc -l | tr -d ' ')" = 1 ] && ok "only the main tree remains after a run" || bad "worktrees left: $(git -C "$REPO" worktree list)"
git -C "$REPO" worktree add -q --detach "$BASE/lane9/root" master
run 100
if git -C "$REPO" worktree list | grep -q lane9 || [ -d "$BASE/lane9" ]; then bad "leftover worktree from an earlier run survived"; else ok "leftover worktree under the base is removed"; fi
[ "$(git -C "$REPO" worktree list | wc -l | tr -d ' ')" = 1 ] || bad "worktrees left after the leftover run"

# 7. an old one-line state file (a bare check name) still resumes the rotation
echo check_a.sh > "$T/state"; run 100
[ "$(swept)" = "b c e a" ] && ok "old one-line state resumes the rotation and wraps" || bad "resume swept '$(swept)', want 'b c e a'"
echo nonsense > "$T/state"; run 100
[ "$(swept)" = "a b c e" ] && ok "unknown state starts at first" || bad "unknown state swept '$(swept)'"

echo 2 > "$T/sleep"; rm -f "$T/state"
run 1
[ "$(swept)" = "a" ] && ok "tiny budget stops after one check" || bad "budget run swept '$(swept)', want 'a'"
[ "$(statekey last_check)" = "check_a.sh" ] && ok "state names the check after a budget stop" || bad "state '$(cat "$T/state")'"
run 1
[ "$(swept)" = "b" ] && ok "next run starts at the next check" || bad "next run swept '$(swept)', want 'b'"

# 3. no check starts after the budget: budget 3 s, 2 s checks -> starts at 0 s and 2 s only
rm -f "$T/state"; run 3
[ "$(swept)" = "a b" ] && ok "no check starts after the budget" || bad "budget 3 swept '$(swept)', want 'a b'"

# 6. two lanes sweep four 2 s checks in under 6 s. The time runs from the first sweep start to
# the last sweep end: the setup and cleanup around it are real work that load stretches.
rm -f "$T/state"; run 100 2
span=$(( $(sort -n "$T/ends.log" | tail -1) - $(cut -d'|' -f4 "$T/swept.log" | sort -n | head -1) ))
[ "$(swept | wc -w | tr -d ' ')" = 4 ] && [ "$span" -lt 6 ] && ok "--lanes 2 swept 4 two-second checks in $span s" || bad "lanes 2: '$(swept)' in $span s"
grep -q '^- lanes: 2$' "$T/report.md" || bad "lanes 2 not in the report"

# 1. a check changed since last_commit is swept before every rotation check
echo 0 > "$T/sleep"; touchcheck check_c.sh
setcheck check_a.sh; run 100
[ "$(swept)" = "c b e a" ] && ok "a changed check is swept before the rotation" || bad "changed-first swept '$(swept)', want 'c b e a'"
sec_ch="$(sed -n '/^## Changed since last sweep/,/^## Carried/p' "$T/report.md")"
echo "$sec_ch" | grep -q 'check_c.sh.*verdict for check_c.sh' && ok "report lists the changed check with its verdict" || bad "Changed section: $sec_ch"

# 2. an unreached changed check stays pending, shows under Carried, and goes first next run
touchcheck check_b.sh; touchcheck check_e.sh
echo 2 > "$T/sleep"; run 1
[ "$(swept)" = "b" ] && ok "budget run sweeps the first changed check" || bad "changed budget run swept '$(swept)', want 'b'"
[ "$(cat "$T/pending")" = "check_e.sh" ] && ok "unreached changed check stays in pending.txt" || bad "pending: '$(cat "$T/pending")'"
sec_ca="$(sed -n '/^## Carried to next run/,$p' "$T/report.md")"
echo "$sec_ca" | grep -q 'check_e.sh' && ok "unreached changed check is listed under Carried" || bad "Carried section: $sec_ca"
echo 0 > "$T/sleep"; run 100
[ "$(swept | cut -d' ' -f1)" = "e" ] && ok "carried check is swept first on the next run" || bad "next run swept '$(swept)', want e first"
[ ! -s "$T/pending" ] && ok "pending is empty once swept" || bad "pending not empty: $(cat "$T/pending")"

# a failing setup build is UNMEASURED, exit 2, and cleans up
NIGHTLY_SWEEP_CMD="$T/sweep" NIGHTLY_SWEEP_LOAD_GUARD="$T/guard" NIGHTLY_SWEEP_BUILD_CMD=false \
    NIGHTLY_SWEEP_BASE="$BASE" "$REPO/tools/nightly_seed_sweep.sh" --lanes 1 --state "$T/state" \
    --pending "$T/pending" --report "$T/report.md" > /dev/null 2>&1
[ "$?" -eq 2 ] && grep -q 'UNMEASURED.*sweep-setup-build.txt' "$T/report.md" && ok "failed setup build gives UNMEASURED and exit 2" || bad "build failure: $(cat "$T/report.md")"
[ "$(git -C "$REPO" worktree list | wc -l | tr -d ' ')" = 1 ] && ok "failed setup build still removes its trees" || bad "worktrees left after build failure"

NIGHTLY_SWEEP_CMD="$T/missing" NIGHTLY_SWEEP_LOAD_GUARD="$T/guard" NIGHTLY_SWEEP_BUILD_CMD=true NIGHTLY_SWEEP_BASE="$BASE" \
    "$REPO/tools/nightly_seed_sweep.sh" --state "$T/state" --pending "$T/pending" --report "$T/report.md" > /dev/null 2>&1
[ "$?" -eq 2 ] && ok "missing sweep command gives exit 2" || bad "missing sweep command did not give exit 2"

if [ "$fail" -eq 0 ]; then echo "PASS: nightly seed sweep"; exit 0; fi
echo "FAIL: nightly seed sweep"; exit 1
