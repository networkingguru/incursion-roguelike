#!/usr/bin/env bash
# gate: cheap
# gate-fast: fake checks and a stub sweep, ~10 s
#
# Does tools/nightly_seed_sweep.sh pick, rotate, budget and report correctly? (inc-ug5y)
#   tools/check_nightly_seed_sweep.sh
# NIGHTLY_SWEEP_SCRIPT=<copy> points the check at a mutated copy of the script.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="${NIGHTLY_SWEEP_SCRIPT:-$ROOT/tools/nightly_seed_sweep.sh}"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/checks" "$T/rc"
fail=0
ok() { echo "ok: $1"; }
bad() { echo "FAIL: $1"; fail=1; }

for spec in a:live b:live c:smoke d:cheap e:live; do
    n="check_${spec%%:*}.sh"
    printf '#!/usr/bin/env bash\n# gate: %s\n' "${spec##*:}" > "$T/checks/$n"
done
echo 0 > "$T/rc/check_a.sh"; echo 1 > "$T/rc/check_b.sh"
echo 0 > "$T/rc/check_c.sh"; echo 2 > "$T/rc/check_e.sh"
cat > "$T/sweep" <<STUB
#!/usr/bin/env bash
n="\$(basename "\$1")"
echo "\$n" >> "$T/swept.log"
sleep "\$(cat "$T/sleep" 2>/dev/null || echo 0)"
echo "verdict for \$n"
exit "\$(cat "$T/rc/\$n")"
STUB
printf '#!/usr/bin/env bash\nexit 0\n' > "$T/guard"
chmod +x "$T/sweep" "$T/guard"

run() { # run <budget> ; uses $T/state and $T/report
    : > "$T/swept.log"
    NIGHTLY_SWEEP_CHECK_DIR="$T/checks" NIGHTLY_SWEEP_CMD="$T/sweep" \
        NIGHTLY_SWEEP_LOAD_GUARD="$T/guard" \
        "$SCRIPT" --budget "$1" --state "$T/state" --report "$T/report.md" > "$T/stdout" 2>&1
}
swept() { tr '\n' ' ' < "$T/swept.log" | sed 's/check_//g; s/\.sh//g; s/ $//'; }

run 100; rc=$?
[ "$rc" -eq 0 ] && ok "exit 0 with a seed-dependent check" || bad "exit $rc, want 0"
[ "$(swept)" = "a b c e" ] && ok "only live/smoke swept, each once" || bad "swept '$(swept)', want 'a b c e'"
grep -q 'check_d' "$T/swept.log" && bad "cheap check swept"
[ "$(cat "$T/state")" = "check_e.sh" ] && ok "state names last check" || bad "state '$(cat "$T/state")'"
sec_dep="$(sed -n '/^## Seed-dependent/,/^## No answer/p' "$T/report.md")"
sec_no="$(sed -n '/^## No answer/,$p' "$T/report.md")"
echo "$sec_dep" | grep -q 'check_b.sh.*verdict for check_b.sh' && ok "exit-1 check under Seed-dependent" || bad "Seed-dependent section: $sec_dep"
echo "$sec_no" | grep -q 'check_e.sh.*exit 2' && ok "exit-2 check under No answer" || bad "No answer section: $sec_no"
grep -q 'A check must not depend on the seed' "$T/report.md" && ok "report names VERIFICATION rule" || bad "rule line missing"

echo check_a.sh > "$T/state"; run 100
[ "$(swept)" = "b c e a" ] && ok "rotation resumes after state and wraps" || bad "resume swept '$(swept)', want 'b c e a'"
echo nonsense > "$T/state"; run 100
[ "$(swept)" = "a b c e" ] && ok "unknown state starts at first" || bad "unknown state swept '$(swept)'"

echo 2 > "$T/sleep"; rm -f "$T/state"
run 1
[ "$(swept)" = "a" ] && ok "tiny budget stops after one check" || bad "budget run swept '$(swept)', want 'a'"
[ "$(cat "$T/state")" = "check_a.sh" ] && ok "state names the check after a budget stop" || bad "state '$(cat "$T/state")'"
run 1
[ "$(swept)" = "b" ] && ok "next run starts at the next check" || bad "next run swept '$(swept)', want 'b'"

NIGHTLY_SWEEP_CHECK_DIR="$T/checks" NIGHTLY_SWEEP_CMD="$T/missing" NIGHTLY_SWEEP_LOAD_GUARD="$T/guard" \
    "$SCRIPT" --state "$T/state" --report "$T/report.md" > /dev/null 2>&1
[ "$?" -eq 2 ] && ok "missing sweep command gives exit 2" || bad "missing sweep command did not give exit 2"

if [ "$fail" -eq 0 ]; then echo "PASS: nightly seed sweep"; exit 0; fi
echo "FAIL: nightly seed sweep"; exit 1
