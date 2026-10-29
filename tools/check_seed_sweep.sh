#!/usr/bin/env bash
# gate: cheap
#
# Does tools/seed_sweep.sh --slots run the seeds at the same time, each in its
# own slot, with the same verdicts and exit codes as the serial path? (inc-jt3yu)
#   tools/check_seed_sweep.sh
# SEED_SWEEP_SCRIPT=<copy> points the check at a mutated copy of the script.
#
# fact: no game runs -- the check under test is a fake shell script
# fact: wall time -- fake checks sleep 2 s; limits are 6 s (parallel) and 10 s (serial)

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="${SEED_SWEEP_SCRIPT:-$ROOT/tools/seed_sweep.sh}"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
fail=0
ok() { echo "ok: $1"; }
bad() { echo "FAIL: $1"; fail=1; }

SEEDS="101 202 303 404 505"
FAKE="$T/root"
mkdir -p "$FAKE/tools" "$T/rc" "$T/pwd"
cp "$SCRIPT" "$FAKE/tools/seed_sweep.sh"
SLOTS=""
n=0
for s in $SEEDS; do
    n=$((n + 1))
    d="$T/slot$n"
    mkdir -p "$d/tools"
    SLOTS="$SLOTS $d"
done
SLOTS="${SLOTS# }"

cat > "$T/check_fake.sh" <<FAKE_CHECK
#!/usr/bin/env bash
s="\${INCURSION_SEED_OVERRIDE:-4242}"
echo "seed=\$s keys=x" >> "\$INCURSION_SEED_LOG"
pwd > "$T/pwd/\$s"
sleep 2
rc=\$(cat "$T/rc/\$s" 2>/dev/null || echo 0)
if [ "\$rc" -eq 0 ]; then echo "PASS fake \$s"; else echo "FAIL fake \$s"; fi
exit "\$rc"
FAKE_CHECK
for d in "$FAKE" $SLOTS; do
    cp "$T/check_fake.sh" "$d/tools/check_fake.sh"
done

# run <outfile> [sweep options]: returns the exit code, sets ELAPSED seconds
run() {
    local out="$1" t0 rc
    shift
    t0=$(date +%s)
    ( cd "$FAKE" && bash tools/seed_sweep.sh tools/check_fake.sh "$@" ) > "$out" 2>&1
    rc=$?
    ELAPSED=$(( $(date +%s) - t0 ))
    return $rc
}
# strip the output directory line, which holds a timestamp
body() { grep -v '^outputs:' "$1"; }

for s in $SEEDS 4242; do echo 0 > "$T/rc/$s"; done

# 1. all seeds pass
run "$T/serial1" --seeds "$SEEDS"; rc_s=$?; el_s=$ELAPSED
rm -f "$T/pwd"/*
run "$T/slots1" --seeds "$SEEDS" --slots "$SLOTS"; rc_p=$?; el_p=$ELAPSED
if [ "$rc_s" -eq 0 ] && [ "$rc_p" -eq 0 ] \
    && grep -q "SEED-INDEPENDENT on 5 seeds" "$T/serial1" \
    && grep -q "SEED-INDEPENDENT on 5 seeds" "$T/slots1" \
    && [ "$(body "$T/serial1")" = "$(body "$T/slots1")" ]; then
    ok "1 all seeds pass: exit 0, SEED-INDEPENDENT on 5 seeds, serial and --slots output identical"
else
    bad "1 all seeds pass (serial rc=$rc_s, slots rc=$rc_p)"; cat "$T/serial1" "$T/slots1"
fi

# 3. timing
if [ "$el_p" -lt 6 ]; then ok "3a --slots took ${el_p}s for 5 seeds of 2 s (under 6 s)"
else bad "3a --slots took ${el_p}s, expected under 6 s"; fi
if [ "$el_s" -ge 10 ]; then ok "3b serial took ${el_s}s (at least 10 s)"
else bad "3b serial took ${el_s}s, expected at least 10 s"; fi

# 4. each seed in its own slot
dirs="$(cat "$T/pwd"/101 "$T/pwd"/202 "$T/pwd"/303 "$T/pwd"/404 "$T/pwd"/505 2>/dev/null | sort -u | wc -l | tr -d ' ')"
inroot=0
for s in $SEEDS; do
    case "$(cat "$T/pwd/$s" 2>/dev/null)" in "$FAKE"|"$(cd "$FAKE" && pwd -P)") inroot=1 ;; esac
done
if [ "$dirs" -eq 5 ] && [ "$inroot" -eq 0 ]; then ok "4 five seeds ran in five distinct slot dirs, none the root"
else bad "4 slot dirs distinct=$dirs, any in root=$inroot"; fi

# 2. one seed fails
echo 1 > "$T/rc/303"
run "$T/serial2" --seeds "$SEEDS"; rc_s=$?
run "$T/slots2" --seeds "$SEEDS" --slots "$SLOTS"; rc_p=$?
if [ "$rc_s" -eq 1 ] && [ "$rc_p" -eq 1 ] \
    && grep -q "SEED-DEPENDENT: 1 of 5 seeds did not pass" "$T/serial2" \
    && grep -q "SEED-DEPENDENT: 1 of 5 seeds did not pass" "$T/slots2" \
    && [ "$(body "$T/serial2")" = "$(body "$T/slots2")" ]; then
    ok "2 seed 303 fails: exit 1, SEED-DEPENDENT: 1 of 5 seeds did not pass, both paths"
else
    bad "2 seed 303 fails (serial rc=$rc_s, slots rc=$rc_p)"; cat "$T/serial2" "$T/slots2"
fi
echo 0 > "$T/rc/303"

# 5. usage errors
run "$T/bad1" --seeds "$SEEDS" --slots "$T/slot1 $T/slot2"; rc=$?
if [ "$rc" -eq 2 ]; then ok "5a wrong slot count: exit 2"; else bad "5a wrong slot count: exit $rc"; fi
rm -f "$T/slot3/tools/check_fake.sh"
run "$T/bad2" --seeds "$SEEDS" --slots "$SLOTS"; rc=$?
if [ "$rc" -eq 2 ] && grep -q "slot3" "$T/bad2"; then ok "5b slot missing the check: exit 2, names the dir"
else bad "5b slot missing the check: exit $rc"; cat "$T/bad2"; fi

exit "$fail"
