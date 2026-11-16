#!/usr/bin/env bash
# gate: live
#
# Does a fixture build fail by name, with the right line, when creation asks for
# a key, a prompt or a random draw that the .char file did not state?
#
# WHAT IS BEING PROVED. Spec section 2 (the two tripwires), amendments A1, A8,
# A9, B1 and section 9, C3 (bead inc-10v7f, phase 7b). A build with the File
# creation source runs the same Player::Create a player runs. If creation grows
# a prompt, a raw-key screen or a random draw that nothing in the .char file
# answers, the build must stop with one named line, not hang, draw on the
# screen and answer by accident, or roll a different character silently.
# The binary has one fault-insertion switch, INCURSION_TRIPWIRE_PROBE=<case>;
# unset, it changes nothing. This builds the committed .char with each fault:
#   yn              a yes/no prompt, wrapped as a sourced pick, in Player::Create
#                   -> the missing-line message (A5) naming the key and context
#   rawkey          a raw-key screen opened by Player::Create (through
#                   CreationTripwireRawKeyScreen, which holds the read so the
#                   static guard on src/Create.cpp stays whole)
#                   -> BUILD FAILED: T1
#   random-create   a random() in Player::Create        -> BUILD FAILED: T2
#   random-advance  a random() in AdvanceLevel, which creation runs
#                   -> BUILD FAILED: T2
#   random-mapgen   a random() in map generation, after Create returns
#                   -> the build passes (A1: that span is outside the window)
#   random-unstated a random() inside an unstatedDraw scope -> the build passes
# and asserts the exit code and the exact stderr line of each. A fault that
# passes must also have run: the binary writes `tripwire probe <case>: fault
# inserted` before it acts, and a passing case without that line fails the
# check. A case with no probe at all must build (the control).
#
# THE BASELINE. Every unstatedDraw("<reason>") in src/ and inc/ is one row of
# tools/fixtures/unstated_draws.baseline, `<file><TAB><function><TAB><reason>`.
# A site with no row fails; a row with no site fails. The file may only shrink:
# when the merge base with master holds a baseline, this branch's row count may
# not exceed it (B1, A9); when it holds none, there is no ratchet. The function
# is the one named on the definition line above the site.
#
# fact: the character -- tools/fixtures/chars/orc-barbarian-seed1-opt0822.char, committed beside this check; the faults are tested against its build, no walk and no key script
# fact: the random stream -- the seed: line of that .char file feeds the build; every assertion is on an exit code and a failure line that names no drawn value, so no stream value is read
# fact: the unstatedDraw sites and the baseline rows -- read as text from src/, inc/ and tools/fixtures/unstated_draws.baseline; no game run
# fact: the options -- the options: line of the .char file names tools/fixtures/options-2026-08-22.dat; build_fixture.sh passes no other settings
#
# Usage: INCURSION_BIN=./incursion-headless tools/check_fixture_tripwires.sh
#        tools/check_fixture_tripwires.sh --baseline-only   (the baseline part, no binary)
#        tools/check_fixture_tripwires.sh --selftest        (the baseline matcher, no binary)
# Exit: 0 pass; 1 fail; 2 could not run.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

BASELINE="${TRIPWIRE_BASELINE:-tools/fixtures/unstated_draws.baseline}"
SRC_ROOT="${TRIPWIRE_SRC_ROOT:-.}"

# scan <src-root> <baseline> <base-count or -1>: python prints one problem per
# line and exits 1; exit 0 when the sites and the rows match.
baseline_match() {
python3 - "$1" "$2" "$3" <<'PY'
import collections, os, re, sys
root, baseline, base_count = sys.argv[1], sys.argv[2], int(sys.argv[3])

SITE = re.compile(r'\bunstatedDraw\(\s*"([^"\\]*)"\s*\)')
FUNC = re.compile(r'^(?:[A-Za-z_][\w\s\*&:<>,~]*?[\s\*&])?([A-Za-z_~][\w:~]*)\s*\(')
NOT_FUNC = ("if", "for", "while", "switch", "else", "return", "do", "case", "sizeof")

def sites():
    out = []
    for d in ("src", "inc"):
        for name in sorted(os.listdir(os.path.join(root, d))):
            if not name.endswith((".cpp", ".h", ".c")):
                continue
            rel = d + "/" + name
            lines = open(os.path.join(root, rel), errors="replace").read().split("\n")
            for n, line in enumerate(lines):
                code = line.strip()
                if code.startswith(("//", "*", "/*", "#")):
                    continue
                m = SITE.search(line)
                if not m:
                    continue
                fn = None
                for k in range(n, -1, -1):
                    l = lines[k]
                    if l[:1] in (" ", "\t", "}", "{", "#", "/", "*", "") or l.rstrip().endswith(";"):
                        continue
                    fm = FUNC.match(l)
                    if fm and fm.group(1) not in NOT_FUNC:
                        fn = fm.group(1); break
                if fn is None:
                    print("cannot name the function around %s:%d" % (rel, n + 1)); sys.exit(2)
                out.append((rel, fn, m.group(1)))
    return out

code = collections.Counter(sites())
rows = collections.Counter()
try:
    for n, line in enumerate(open(baseline).read().split("\n"), 1):
        if not line.strip() or line.startswith("#"):
            continue
        f = line.split("\t")
        if len(f) != 3 or not all(x.strip() for x in f):
            print("%s:%d: a row is <file><TAB><function><TAB><reason>" % (baseline, n)); sys.exit(2)
        rows[tuple(f)] += 1
except OSError as e:
    print("INCONCLUSIVE: %s" % e); sys.exit(2)

bad = 0
for k in sorted(code - rows):
    print("T3 site with no baseline row: %s\t%s\t%s" % k); bad = 1
for k in sorted(rows - code):
    print("T3 baseline row with no site: %s\t%s\t%s" % k); bad = 1
total = sum(rows.values())
if base_count >= 0 and total > base_count:
    print("T3 the baseline has %d rows; the merge base with master has %d, and it may only shrink" % (total, base_count)); bad = 1
print("# %d unstatedDraw sites, %d baseline rows" % (sum(code.values()), total))
sys.exit(bad)
PY
}

# The ratchet's reference count: rows in the baseline at the merge base with
# master, or -1 when it has none.
base_row_count() {
    local mb
    mb="$(git merge-base HEAD master 2>/dev/null)" || return 2
    if git cat-file -e "$mb:tools/fixtures/unstated_draws.baseline" 2>/dev/null; then
        git show "$mb:tools/fixtures/unstated_draws.baseline" | grep -cv '^[[:space:]]*\(#\|$\)'
    else
        echo -1
    fi
}

if [ "${1:-}" = "--selftest" ]; then
    T="$(mktemp -d "${TMPDIR:-/tmp}/tripwires.XXXXXX")" || exit 2
    trap 'rm -rf "$T"' EXIT
    mkdir -p "$T/src" "$T/inc"
    cat > "$T/src/a.cpp" <<'EOF'
#include "x.h"

static void NamePerk(Perk& p, String& str) {
    unstatedDraw("one reason");
    int a = 1;
}

String & TEffect::Power(int8 Mod, Creature *Caster)
  {
    unstatedDraw("another reason");
  }
EOF
    printf 'src/a.cpp\tNamePerk\tone reason\nsrc/a.cpp\tTEffect::Power\tanother reason\n' > "$T/ok.baseline"
    fails=0
    case_() {   # <label> <want rc> <baseline file> <base count> [pattern]
        out="$(baseline_match "$T" "$3" "$4" 2>&1)"; rc=$?
        if [ "$rc" -eq "$2" ] && { [ -z "${5:-}" ] || grep -q "$5" <<< "$out"; }; then
            echo "selftest: $1 -> rc $rc as expected"
        else
            echo "SELFTEST FAIL: $1 (rc $rc, wanted $2)"; printf '%s\n' "$out"; fails=1
        fi
    }
    case_ "sites and rows match" 0 "$T/ok.baseline" -1
    head -1 "$T/ok.baseline" > "$T/short.baseline"
    case_ "a site has no row" 1 "$T/short.baseline" -1 "T3 site with no baseline row"
    { cat "$T/ok.baseline"; printf 'src/a.cpp\tGone\tgone reason\n'; } > "$T/extra.baseline"
    case_ "a row has no site" 1 "$T/extra.baseline" -1 "T3 baseline row with no site"
    printf 'src/a.cpp\tNamePerk\twrong reason\nsrc/a.cpp\tTEffect::Power\tanother reason\n' > "$T/reason.baseline"
    case_ "a row names another reason" 1 "$T/reason.baseline" -1 "T3 site with no baseline row"
    case_ "the baseline is over the merge-base count" 1 "$T/ok.baseline" 1 "may only shrink"
    case_ "the baseline equals the merge-base count" 0 "$T/ok.baseline" 2
    printf 'src/a.cpp\tNamePerk\n' > "$T/bad.baseline"
    case_ "a malformed row" 2 "$T/bad.baseline" -1
    [ $fails -eq 0 ] && echo "selftest: PASS" && exit 0
    exit 1
fi

# ---- the baseline ---------------------------------------------------------
BASECOUNT="$(base_row_count)"; rc=$?
[ $rc -eq 0 ] || { echo "INCONCLUSIVE: git merge-base HEAD master failed"; exit 2; }
out="$(baseline_match "$SRC_ROOT" "$BASELINE" "$BASECOUNT" 2>&1)"; rc=$?
if [ $rc -eq 2 ]; then printf '%s\n' "$out"; echo "INCONCLUSIVE: the baseline could not be matched"; exit 2; fi
if [ $rc -ne 0 ]; then printf '%s\n' "$out"; echo "FAIL: the unstatedDraw sites and the baseline disagree (spec A9, B1)"; exit 1; fi
echo "ok   baseline: $(sed -n 's/^# //p' <<< "$out")$([ "$BASECOUNT" -ge 0 ] && echo "; merge base has $BASECOUNT")"
[ "${1:-}" = "--baseline-only" ] && { echo "PASS: the baseline matches the code"; exit 0; }

# ---- the faults -----------------------------------------------------------
BIN="${INCURSION_BIN:-./incursion-headless}"
[ -x "$BIN" ] || { echo "INCONCLUSIVE: $BIN is not built"; exit 2; }
CHAR=tools/fixtures/chars/orc-barbarian-seed1-opt0822.char
[ -f "$CHAR" ] || { echo "INCONCLUSIVE: $CHAR is missing"; exit 2; }

W="$(mktemp -d "${TMPDIR:-/tmp}/tripwires-run.XXXXXX")" || exit 2
trap 'rm -rf "$W"' EXIT
fails=0

run_case() {   # <case or none> -> sets RC and ERR (the file of stderr)
    local c="$1" run="$W/run-$1"
    ERR="$W/$1.err"
    if [ "$c" = none ]; then
        INCURSION_BIN="$BIN" INCURSION_BUILD_RUN_DIR="$run" tools/build_fixture.sh "$CHAR" "$W/out-$c" > "$W/$c.out" 2> "$ERR"
    else
        INCURSION_TRIPWIRE_PROBE="$c" INCURSION_BIN="$BIN" INCURSION_BUILD_RUN_DIR="$run" tools/build_fixture.sh "$CHAR" "$W/out-$c" > "$W/$c.out" 2> "$ERR"
    fi
    RC=$?
}
ok()   { echo "ok   $1"; }
bad()  { echo "FAIL $1"; fails=1; }

# The control: no fault, the build passes and no probe line is written.
run_case none
if [ $RC -eq 0 ] && ! grep -q 'tripwire probe' "$ERR" && ! grep -q 'BUILD FAILED' "$ERR"; then
    ok "control: with no fault the committed .char builds"
else
    bad "control: the committed .char did not build (exit $RC): $(grep -m1 'BUILD FAILED' "$ERR" || tail -1 "$ERR")"
fi

expect_fail() {   # <case> <extended regex for the one BUILD FAILED line> <what it proves>
    run_case "$1"
    local n line
    n="$(grep -c '^BUILD FAILED:' "$ERR")"
    line="$(grep -m1 '^BUILD FAILED:' "$ERR")"
    if [ $RC -eq 10 ] && [ "$n" -eq 1 ] && grep -q "^tripwire probe $1: fault inserted\$" "$ERR" \
        && grep -Eq "$2" <<< "$line"; then
        ok "$1: $3"
        echo "       $line"
    else
        bad "$1: wanted exit 10 and one line matching $2; got exit $RC, $n BUILD FAILED lines: ${line:-none}"
    fi
}
expect_pass() {   # <case> <what it proves>
    run_case "$1"
    if [ $RC -eq 0 ] && grep -q "^tripwire probe $1: fault inserted\$" "$ERR" && ! grep -q 'BUILD FAILED' "$ERR"; then
        ok "$1: $2"
    else
        bad "$1: wanted the fault to run and the build to pass; got exit $RC: $(grep -m1 'BUILD FAILED' "$ERR" || echo "no probe line or no pass")"
    fi
}

expect_fail yn '^BUILD FAILED: missing line in .*orc-barbarian-seed1-opt0822\.char; add: script_yn \[tripwire probe\]: no$' \
    "an unstated prompt is a missing line that names its key, context and the line to add (A5)"
expect_fail rawkey '^BUILD FAILED: T1 key read outside a sourced decision: GetCharRaw called from CreationTripwireRawKeyScreen\(Term\*\)\+0x[0-9a-f]+; the screen shows "Tripwire probe screen"' \
    "a raw-key screen fails T1 and names the screen and the caller"
expect_fail random-create '^BUILD FAILED: T2 unstated random draw in Create at Create\.cpp:[0-9]+:' \
    "a draw in Player::Create fails T2 and names the function and the site"
expect_fail random-advance '^BUILD FAILED: T2 unstated random draw in AdvanceLevel at Create\.cpp:[0-9]+:' \
    "a draw in AdvanceLevel, run by creation, fails T2"
expect_pass random-mapgen "a draw in map generation, after Create returns, is outside the window (A1)"
expect_pass random-unstated "a draw inside an unstatedDraw scope passes T2"

[ $fails -eq 0 ] && { echo "PASS: T1 and T2 fire with their lines on each fault, pass where they must, and the baseline matches the code"; exit 0; }
echo "FAIL: a tripwire did not behave as stated (spec section 2, C3)"
exit 1
