#!/usr/bin/env bash
# gate: cheap
#
# Does src/Create.cpp still branch on MO_RECREATE or on `reincarnate`, does
# Resource::GrantGear in src/Annot.cpp still branch on MO_RECREATE, and does
# src/Create.cpp still ask a prompt or read a key outside a sourced decision?
#
# WHAT IS BEING PROVED. Every character-creation decision goes through the
# creation source (inc/CreationSource.h, src/CreationSource.cpp): a site calls
# SourcedRoll, SourcedPick or SourcedItem, and the active source (Live or
# Replay) answers or does not. A site that tests MO_RECREATE or `reincarnate`
# itself is a second code path beside the source, and the fixture builder
# (bead inc-10v7f, spec A6) depends on there being exactly one. This check
# fails on any such branch in src/Create.cpp. The mode value MO_CREATE stays
# legal: it is read by display code that decides nothing.
#
# WHAT IT FLAGS (a line in src/Create.cpp that is not a pure comment line):
#   - any occurrence of MO_RECREATE;
#   - the word `reincarnate` used in a condition: if/while/for (...reincarnate,
#     `!reincarnate`, `reincarnate ==`, `reincarnate !=`, `reincarnate ?`,
#     `reincarnate &&`, `reincarnate ||`, or `(reincarnate)`.
# A function parameter, a string literal and the method name Reincarnate (capital
# R) are not branches and are not flagged.
#
# fact: the text of src/Create.cpp -- read from the working tree by grep; no game run, no seed, no map
# fact: the text of Resource::GrantGear in src/Annot.cpp -- read from the working tree by awk and grep; no game run, no seed, no map
# fact: which tokens count as a branch -- the two patterns above, fixed in this file
# fact: which calls count as a prompt or a key read -- LMenu, ChoicePrompt, yn, GetCharRaw and GetCharCmd, fixed in the scan_prompts script below
# fact: where a sourced decision begins and ends -- the balanced parentheses of a SourcedPick, SourcedRoll or SourcedItem call, found by the same script; no game run, no seed, no map
# fact: which prompts are exempt -- the ALLOW table in scan_prompts, each entry with its reason
#
# PROMPTS (inc-10v7f phase 6a). The third scan fails on any LMenu(, ChoicePrompt(,
# yn(, GetCharRaw( or GetCharCmd( call in src/Create.cpp that does not sit inside
# the parentheses of a SourcedPick, SourcedRoll or SourcedItem call, which is the
# sourced primitive's live function. Comments, string literals and `#if 0`
# blocks are set aside first. The ALLOW table names the prompts that are exempt,
# each with its reason; a new entry needs one.
#
# Usage: tools/check_creation_source_sites.sh [--selftest]
#        --selftest copies src/Create.cpp and src/Annot.cpp, adds one branch of
#        each kind, unwraps one prompt, and proves this script goes red on each
#        copy.
# Exit: 0 no branch; 1 a branch is present; 2 could not measure.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

FILE="${CREATION_SOURCE_SITES_FILE:-src/Create.cpp}"
GEAR_FILE="${CREATION_SOURCE_SITES_GEAR_FILE:-src/Annot.cpp}"

scan() {
    local f="$1"
    [ -f "$f" ] || { echo "INCONCLUSIVE: $f is not there"; return 2; }
    # Drop pure comment lines (//, /*, *) before matching.
    local code
    code="$(grep -nvE '^[[:space:]]*(//|/\*|\*)' "$f")" || true
    [ -n "$code" ] || { echo "INCONCLUSIVE: $f has no code lines"; return 2; }
    local bad=0 hits
    hits="$(printf '%s\n' "$code" | grep -E 'MO_RECREATE')" || true
    if [ -n "$hits" ]; then
        echo "FAIL: MO_RECREATE in $f (use the creation source):"
        printf '%s\n' "$hits" | sed 's/^/  /'
        bad=1
    fi
    hits="$(printf '%s\n' "$code" | grep -E '(if|while|for)[[:space:]]*\(.*\breincarnate\b|!reincarnate\b|\breincarnate[[:space:]]*(==|!=|\?|&&|\|\|)|\([[:space:]]*reincarnate[[:space:]]*\)')" || true
    if [ -n "$hits" ]; then
        echo "FAIL: a branch on reincarnate in $f (use the creation source):"
        printf '%s\n' "$hits" | sed 's/^/  /'
        bad=1
    fi
    return $bad
}


# A prompt or key read outside a sourced primitive's live function.
scan_prompts() {
    local f="$1"
    [ -f "$f" ] || { echo "INCONCLUSIVE: $f is not there"; return 2; }
    python3 -I - "$f" <<'PY'
import re, sys
path = sys.argv[1]
src = open(path).read()

# ALLOW: a prompt exempt from the rule. (substring of the source line, reason)
ALLOW = [
    ('"Choose a character:"',
     "Player::Reincarnate menu: asked before Player::Create opens its window, "
     "so no creation decision (spec section 2, sites list P-table last line)"),
]

def mask(t):
    """Blank comments and string/char literals, keeping every offset and newline."""
    out = list(t); i = 0; n = len(t)
    while i < n:
        c = t[i]
        if t.startswith("//", i):
            j = t.find("\n", i)
            j = n if j < 0 else j
            for k in range(i, j): out[k] = " "
            i = j
        elif t.startswith("/*", i):
            j = t.find("*/", i + 2)
            j = n if j < 0 else j + 2
            for k in range(i, j):
                if t[k] != "\n": out[k] = " "
            i = j
        elif c == '"' or c == "'":
            j = i + 1
            while j < n and t[j] != c:
                j += 2 if t[j] == "\\" else 1
            for k in range(i + 1, min(j, n)):
                if t[k] != "\n": out[k] = " "
            i = j + 1
        else:
            i += 1
    return "".join(out)

def drop_if0(t):
    """Blank the body of each #if 0 ... #endif block."""
    lines = t.split("\n"); depth = 0; inz = False; res = []
    for ln in lines:
        s = ln.strip()
        if inz:
            if re.match(r"#\s*if", s): depth += 1
            elif re.match(r"#\s*endif", s):
                depth -= 1
                if depth == 0: inz = False
            res.append("")
        elif re.match(r"#\s*if\s+0\b", s):
            inz = True; depth = 1; res.append("")
        else:
            res.append(ln)
    return "\n".join(res)

masked = drop_if0(mask(src))
if len(masked) != len(src.replace("\r", "")) and len(masked) != len(src):
    pass

spans = []
for m in re.finditer(r"\bSourced(?:Pick|Roll|Item)\s*\(", masked):
    depth = 1; i = m.end()
    while i < len(masked) and depth:
        if masked[i] == "(": depth += 1
        elif masked[i] == ")": depth -= 1
        i += 1
    if depth:
        print("INCONCLUSIVE: unbalanced parentheses in a Sourced call at line %d" % (masked.count("\n", 0, m.start()) + 1))
        sys.exit(2)
    spans.append((m.end(), i))

lines = src.split("\n")
bad = []
for m in re.finditer(r"(?<![\w.>])(?:\w+->)?(LMenu|ChoicePrompt|yn|GetCharRaw|GetCharCmd)\s*\(", masked):
    if any(a <= m.start() < b for a, b in spans):
        continue
    ln = masked.count("\n", 0, m.start()) + 1
    text = lines[ln - 1]
    if any(a in text for a, _ in ALLOW):
        continue
    bad.append((ln, text.strip()))
# a call written without the arrow form is matched above; a call through
# `->` or `.` needs its own pass because of the lookbehind
for m in re.finditer(r"(?:->|\.)(LMenu|ChoicePrompt|yn|GetCharRaw|GetCharCmd)\s*\(", masked):
    if any(a <= m.start() < b for a, b in spans):
        continue
    ln = masked.count("\n", 0, m.start()) + 1
    text = lines[ln - 1]
    if any(a in text for a, _ in ALLOW):
        continue
    if (ln, text.strip()) not in bad:
        bad.append((ln, text.strip()))
if not spans:
    print("INCONCLUSIVE: no Sourced call found in %s" % path)
    sys.exit(2)
if bad:
    print("FAIL: a prompt or key read outside a sourced decision in %s:" % path)
    for ln, text in sorted(bad):
        print("  %d: %s" % (ln, text))
    sys.exit(1)
sys.exit(0)
PY
}

# MO_RECREATE inside the body of Resource::GrantGear: from its definition at
# column 0 to the first line that is exactly two spaces and a closing brace.
scan_gear() {
    local f="$1"
    [ -f "$f" ] || { echo "INCONCLUSIVE: $f is not there"; return 2; }
    local body
    body="$(awk '/^void Resource::GrantGear\(/ {on=1} on {print NR ": " $0} on && /^  }[[:space:]]*$/ {exit}' "$f")"
    [ -n "$body" ] || { echo "INCONCLUSIVE: Resource::GrantGear is not in $f"; return 2; }
    local hits
    hits="$(printf '%s\n' "$body" | grep -E 'MO_RECREATE')" || true
    if [ -n "$hits" ]; then
        echo "FAIL: MO_RECREATE in Resource::GrantGear in $f (use the creation source):"
        printf '%s\n' "$hits" | sed 's/^/  /'
        return 1
    fi
    return 0
}

if [ "${1:-}" = "--selftest" ]; then
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    fail=0
    scan "$FILE" > /dev/null || { echo "selftest: the real file already fails"; exit 1; }
    cp "$FILE" "$tmp/a.cpp"; echo '    if (MyTerm->GetMode() == MO_RECREATE) { }' >> "$tmp/a.cpp"
    cp "$FILE" "$tmp/b.cpp"; echo '    if (reincarnate) { }' >> "$tmp/b.cpp"
    cp "$FILE" "$tmp/c.cpp"; echo '    x = !reincarnate;' >> "$tmp/c.cpp"
    for c in a b c; do
        if scan "$tmp/$c.cpp" > /dev/null; then
            echo "selftest: mutation $c was NOT caught"; fail=1
        fi
    done
    scan_gear "$GEAR_FILE" > /dev/null || { echo "selftest: the real GrantGear already fails"; exit 1; }
    sed '/t = (time_t)NextSeed();/a\
    if (T1->GetMode() == MO_RECREATE) { }' "$GEAR_FILE" > "$tmp/d.cpp"
    if scan_gear "$tmp/d.cpp" > /dev/null; then
        echo "selftest: mutation d (MO_RECREATE in GrantGear) was NOT caught"; fail=1
    fi
    scan_prompts "$FILE" > /dev/null || { echo "selftest: the real file already fails the prompt scan"; exit 1; }
    cp "$FILE" "$tmp/e.cpp"; printf '    x = MyTerm->LMenu(0, "Choose:");\n' >> "$tmp/e.cpp"
    if scan_prompts "$tmp/e.cpp" > /dev/null; then
        echo "selftest: mutation e (a bare LMenu) was NOT caught"; fail=1
    fi
    # Unwrap one real site: the abandon prompt loses its SourcedPick.
    sed 's/return SourcedPick(CK_ABANDON, YesNoList(), \[&\]() {/return [\&]() {/' "$FILE" > "$tmp/f.cpp"
    if cmp -s "$FILE" "$tmp/f.cpp"; then
        echo "selftest: mutation f did not change the file"; fail=1
    elif scan_prompts "$tmp/f.cpp" > /dev/null; then
        echo "selftest: mutation f (the abandon prompt unwrapped) was NOT caught"; fail=1
    fi
    [ $fail -eq 0 ] && echo "selftest: all 6 mutations caught"
    exit $fail
fi

out="$(scan "$FILE")"; rc=$?
[ -n "$out" ] && echo "$out"
pout="$(scan_prompts "$FILE")"; prc=$?
[ -n "$pout" ] && echo "$pout"
[ $prc -gt $rc ] && rc=$prc
gout="$(scan_gear "$GEAR_FILE")"; grc=$?
[ -n "$gout" ] && echo "$gout"
[ $grc -gt $rc ] && rc=$grc
if [ $rc -eq 0 ]; then
    echo "PASS: no MO_RECREATE or reincarnate branch in $FILE, none in GrantGear in $GEAR_FILE, every prompt in $FILE inside a sourced decision"
fi
exit $rc
