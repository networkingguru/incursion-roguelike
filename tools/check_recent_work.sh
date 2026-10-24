#!/bin/bash
# gate: cheap
# check_recent_work.sh -- self-test for tools/recent_work.py (inc-bsgy).
# Builds its own transcripts and bead list in a temp dir; reads no real data.
# Exit 0 when every assertion passes, 1 on any FAIL, 2 never (tool errors print FAIL).
# fact: transcript line shapes (user str and list, tool_result, assistant text and tool_use, bad JSON) -- built by this script in a temp dir
# fact: session file mtimes (recent, and 30 days back via touch -t) -- built by this script in a temp dir
# fact: bead list JSON (ids, status, parent, title, description) -- built by this script in a temp dir
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
TOOL="$HERE/recent_work.py"
T=$(mktemp -d) || exit 1
trap 'rm -rf "$T"' EXIT
P="$T/projects"
mkdir -p "$P"

cat > "$T/beads.json" <<'EOF'
[
{"id":"inc-aaaa","title":"Umbrella survey","status":"closed","description":"Survey of the work."},
{"id":"inc-bbbb","title":"Follow-up on the survey","status":"open","description":"Follows up inc-aaaa."},
{"id":"inc-aaaa.1","title":"Child work item","status":"open","parent":"inc-aaaa","description":"Child."},
{"id":"inc-cccc","title":"Rebalance the balance tables","status":"open","description":"Decoy."},
{"id":"inc-dddd","title":"Old finished item","status":"closed","description":"Done."}
]
EOF

cat > "$P/s-a1.jsonl" <<'EOF'
{"type":"user","message":{"content":"look at the survey"}}
{"type":"assistant","message":{"content":[{"type":"text","text":"Looking at inc-aaaa and inc-aaaa.1 now."}]}}
not json {
EOF
cat > "$P/s-a2.jsonl" <<'EOF'
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"bd show inc-aaaa"}}]}}
EOF
cat > "$P/s-b.jsonl" <<'EOF'
{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"x","content":"inc-cccc open\ninc-dddd closed"}]}}
EOF
cat > "$P/s-old.jsonl" <<'EOF'
{"type":"user","message":{"content":"do inc-cccc next"}}
EOF
touch -t "$(date -v-30d +%Y%m%d%H%M)" "$P/s-old.jsonl"

OUT="$T/out.txt"
python3 "$TOOL" --projects-dir "$P" --beads-json "$T/beads.json" > "$OUT" 2> "$T/err.txt"
RC=$?

fails=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }

if [ "$RC" -ne 0 ]; then
  fail "tool exited $RC: $(cat "$T/err.txt")"
else
  grep -q '^inc-aaaa  closed  2s  last ' "$OUT" && pass "1 inc-aaaa listed with 2s" || fail "1 inc-aaaa listed with 2s"
  grep -q '^  -> inc-bbbb  open' "$OUT" && grep -q '^  -> inc-aaaa.1  open' "$OUT" \
    && pass "2 inc-bbbb and inc-aaaa.1 listed under inc-aaaa" || fail "2 inc-bbbb and inc-aaaa.1 listed under inc-aaaa"
  grep -q '^inc-aaaa.1  open  1s' "$OUT" && pass "6 dotted id inc-aaaa.1 counted under its own id" \
    || fail "6 dotted id inc-aaaa.1 counted under its own id"
  if grep -q 'inc-cccc' "$OUT"; then fail "3 inc-cccc not listed"; else pass "3 inc-cccc not listed"; fi
  if grep -q 'inc-dddd' "$OUT"; then fail "4 inc-dddd not listed"; else pass "4 inc-dddd not listed"; fi
fi

python3 "$TOOL" --projects-dir "$T/missing" --beads-json "$T/beads.json" > /dev/null 2>&1
if [ $? -eq 2 ]; then pass "5 missing projects dir exits 2"; else fail "5 missing projects dir exits 2"; fi

if [ "$fails" -ne 0 ]; then
  echo "recent_work check: $fails FAIL"
  exit 1
fi
echo "recent_work check: all PASS"
exit 0
