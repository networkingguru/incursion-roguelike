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
# fact: which calls count as a prompt or a key read -- LMenu, ChoicePrompt, yn, GetCharRaw, GetCharCmd, SkillManager, LearnTable and OptionManager, fixed in the scan_prompts script below
# fact: where a sourced decision begins and ends -- the balanced parentheses of a SourcedPick, SourcedRoll or SourcedItem call, found by the same script; no game run, no seed, no map
# fact: which prompts are exempt -- the ALLOW table in scan_prompts, each entry with its reason
# fact: the text of Resource::Event in src/Annot.cpp, of src/VMachine.cpp and of Character::Transgress in src/Prayer.cpp -- read from the working tree by python; no game run, no seed, no map
# fact: which script routings are required -- the RULES table in scan_script, each entry with the text it needs and the file it must be in
#
# PROMPTS (inc-10v7f phases 6a and 6b). The third scan fails on any LMenu(,
# ChoicePrompt(, yn(, GetCharRaw(, GetCharCmd(, SkillManager(, LearnTable( or
# OptionManager( call in src/Create.cpp that does not sit inside the parentheses
# of a SourcedPick, SourcedRoll or SourcedItem call, which is the sourced
# primitive's live function. The last three are whole screens (the creation
# skill screen, the spell table, the creation option screen) that read keys in
# TextTerm and Managers code this scan does not read; the creation
# Player::LearnSpell(true) calls (and the level-up one) reach LearnTable inside
# Player::LearnSpell, so the LearnTable call is where they are held. Comments, string literals and `#if 0`
# blocks are set aside first. The ALLOW table names the prompts that are exempt,
# each with its reason; a new entry needs one.
#
# SCRIPTS (inc-10v7f phase 6c). A creation script's draws and prompts are
# sourced decisions too. scan_script fails when Resource::Event stops pushing a
# CreationScope for a creation event (Annot.cpp), when the VM stops routing a
# script's random(n), its dice rolls (the ROLL opcode) or Transgress through
# SourcedRoll(CK_SCRIPT_ROLL, ...) (VMachine.cpp, Prayer.cpp), or when a
# script's yn, ChoicePrompt or LMenu stops going through SourcedPick with
# CK_SCRIPT_YN, CK_SCRIPT_CHOICE or CK_SCRIPT_MENU (VMachine.cpp).
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
VM_FILE="${CREATION_SOURCE_SITES_VM_FILE:-src/VMachine.cpp}"
PRAYER_FILE="${CREATION_SOURCE_SITES_PRAYER_FILE:-src/Prayer.cpp}"

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
for m in re.finditer(r"(?<![\w.>])(?:\w+->)?(LMenu|ChoicePrompt|yn|GetCharRaw|GetCharCmd|SkillManager|LearnTable|OptionManager)\s*\(", masked):
    if any(a <= m.start() < b for a, b in spans):
        continue
    ln = masked.count("\n", 0, m.start()) + 1
    text = lines[ln - 1]
    if any(a in text for a, _ in ALLOW):
        continue
    bad.append((ln, text.strip()))
# a call written without the arrow form is matched above; a call through
# `->` or `.` needs its own pass because of the lookbehind
for m in re.finditer(r"(?:->|\.)(LMenu|ChoicePrompt|yn|GetCharRaw|GetCharCmd|SkillManager|LearnTable|OptionManager)\s*\(", masked):
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

# Script routing (phase 6c): the scope push, the draw routing and the prompt
# routing. Each rule is (tag, file role, regex that must match the masked code,
# what it proves). A rule that cannot find its file is INCONCLUSIVE.
scan_script() {
    local annot="$1" vm="$2" prayer="$3"
    local f
    for f in "$annot" "$vm" "$prayer"; do
        [ -f "$f" ] || { echo "INCONCLUSIVE: $f is not there"; return 2; }
    done
    python3 -I - "$annot" "$vm" "$prayer" <<'PY'
import re, sys
annot, vm, prayer = [open(p).read() for p in sys.argv[1:4]]

def mask(t):
    """Blank comments and string/char literals, keeping every offset."""
    out = list(t); i = 0; n = len(t)
    while i < n:
        c = t[i]
        if t.startswith("//", i):
            j = t.find("\n", i); j = n if j < 0 else j
            for k in range(i, j): out[k] = " "
            i = j
        elif t.startswith("/*", i):
            j = t.find("*/", i + 2); j = n if j < 0 else j + 2
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

def body(text, head):
    """The text from a definition's head to the first line that is a closing
    brace in column 0 or two spaces, or '' when the head is not there."""
    m = re.search(head, text, re.M)
    if not m: return ""
    e = re.compile(r"^(\}|  \})[ \t]*$", re.M).search(text, m.end())
    return text[m.start(): e.end() if e else len(text)]

a, v, p = mask(annot), mask(vm), mask(prayer)
# string literals are blanked, so the key names (identifiers) stay visible.
ev = body(a, r"^EvReturn Resource::Event\(EventInfo &e, rID xID, int16 Event\)")
tr = body(p, r"^void Character::Transgress\(")
rd = body(v, r"^static int16 ScriptRandom\(")
dc = body(v, r"^static int16 ScriptDice\(")
inc = vm.find('#include "dispatch.h"')   # the masked text blanks the quoted name; offsets agree
pre = v[:inc] if inc >= 0 else ""
pre = pre[pre.rfind("#pragma push_macro"):] if "#pragma push_macro" in pre else ""
yn = body(v, r"^bool Creature::ScriptYn\(")
cp = body(v, r"^int8 Creature::ScriptChoicePrompt\(")
lm = body(v, r"^int32 Term::ScriptLMenu\(")

RULES = [
    ("scope-push", ev and re.search(r"\bCreationScope\s+\w+\s*\(", ev) and "CreationWindowOpen()" in ev,
     "Resource::Event (src/Annot.cpp) pushes no CreationScope for a creation event"),
    ("draw-random", rd and re.search(r"SourcedRoll\s*\(\s*CK_SCRIPT_ROLL\b", rd)
        and re.search(r"#define\s+random\s*\(\s*mx\s*\)\s*ScriptRandom\s*\(", pre),
     "a script's random(n) is not routed through SourcedRoll(CK_SCRIPT_ROLL) (src/VMachine.cpp)"),
    ("draw-dice", dc and re.search(r"SourcedRoll\s*\(\s*CK_SCRIPT_ROLL\b", dc)
        and re.search(r"case\s+ROLL\s*:[^;]*\bScriptDice\s*\(", v),
     "a script's dice roll (the ROLL opcode) is not routed through SourcedRoll(CK_SCRIPT_ROLL) (src/VMachine.cpp)"),
    ("draw-transgress", tr and re.search(r"SourcedRoll\s*\(\s*CK_SCRIPT_ROLL\b", tr),
     "Character::Transgress's random(60) is not routed through SourcedRoll(CK_SCRIPT_ROLL) (src/Prayer.cpp)"),
    ("prompt-yn", yn and re.search(r"SourcedPick\s*\(\s*CK_SCRIPT_YN\b", yn)
        and re.search(r"#define\s+yn\s+ScriptYn\b", pre),
     "a script's yn is not routed through SourcedPick(CK_SCRIPT_YN) (src/VMachine.cpp)"),
    ("prompt-choice", cp and re.search(r"SourcedPick\s*\(\s*CK_SCRIPT_CHOICE\b", cp)
        and re.search(r"#define\s+ChoicePrompt\s+ScriptChoicePrompt\b", pre),
     "a script's ChoicePrompt is not routed through SourcedPick(CK_SCRIPT_CHOICE) (src/VMachine.cpp)"),
    ("prompt-menu", lm and re.search(r"SourcedPick\s*\(\s*CK_SCRIPT_MENU\b", lm)
        and re.search(r"#define\s+LMenu\s+ScriptLMenu\b", pre),
     "a script's LMenu is not routed through SourcedPick(CK_SCRIPT_MENU) (src/VMachine.cpp)"),
]
bad = [(t, why) for t, ok, why in RULES if not ok]
if bad:
    print("FAIL: a script's draw, prompt or scope is no longer sourced:")
    for t, why in bad: print("  [%s] %s" % (t, why))
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
    # Phase 6b: unwrap each screen from its sourced decision. The scan MUST
    # name that screen's call, not just fail.
    for m in "g:SkillManager:CK_SKILL_RANKS" "h:LearnTable:CK_SPELL_LEARN" "i:OptionManager:CK_ALTER_OPTIONS"; do
        id="${m%%:*}"; rest="${m#*:}"; call="${rest%%:*}"; key="${rest#*:}"
        sed -E "s/Sourced(Roll|Pick)\\(${key},/Unsourced(${key},/" "$FILE" > "$tmp/$id.cpp"
        if cmp -s "$FILE" "$tmp/$id.cpp"; then
            echo "selftest: mutation $id did not change the file"; fail=1
        else
            mout="$(scan_prompts "$tmp/$id.cpp" 2>&1)"
            case "$mout" in
                *"$call("*) ;;
                *) echo "selftest: mutation $id (${call} unwrapped) was NOT caught"; fail=1 ;;
            esac
        fi
    done
    # Phase 6c: unwrap each script rule. The scan MUST name that rule's tag.
    scan_script "$GEAR_FILE" "$VM_FILE" "$PRAYER_FILE" > /dev/null || { echo "selftest: the real script routing already fails"; exit 1; }
    mutate_script() {   # mutate_script <id> <tag> <file-role> <sed expression>
        local id="$1" tag="$2" role="$3" expr="$4" a="$GEAR_FILE" v="$VM_FILE" p="$PRAYER_FILE" src
        case "$role" in annot) src="$a" ;; vm) src="$v" ;; prayer) src="$p" ;; esac
        sed -E "$expr" "$src" > "$tmp/$id.cpp"
        if cmp -s "$src" "$tmp/$id.cpp"; then
            echo "selftest: mutation $id did not change the file"; fail=1; return
        fi
        case "$role" in annot) a="$tmp/$id.cpp" ;; vm) v="$tmp/$id.cpp" ;; prayer) p="$tmp/$id.cpp" ;; esac
        mout="$(scan_script "$a" "$v" "$p" 2>&1)"
        case "$mout" in
            *"[$tag]"*) ;;
            *) echo "selftest: mutation $id ($tag unwrapped) was NOT caught"; fail=1 ;;
        esac
    }
    mutate_script j scope-push annot 's/CreationScope creationScope\(/Unscoped creationScope(/'
    mutate_script k draw-dice vm 's/case ROLL: REGS\(0\) = ScriptDice\(/case ROLL: REGS(0) = Dice::Roll(/'
    mutate_script l draw-random vm 's/#define random\(mx\) ScriptRandom\(/#define random(mx) census_random(/'
    mutate_script m draw-transgress prayer 's/SourcedRoll\(CK_SCRIPT_ROLL, \[&\]\(\) -> int32 \{ return random\(60\); \}\)/random(60)/'
    mutate_script n prompt-yn vm 's/SourcedPick\(CK_SCRIPT_YN,/Unsourced(CK_SCRIPT_YN,/'
    mutate_script o prompt-choice vm 's/SourcedPick\(CK_SCRIPT_CHOICE,/Unsourced(CK_SCRIPT_CHOICE,/'
    mutate_script q prompt-menu vm 's/SourcedPick\(CK_SCRIPT_MENU,/Unsourced(CK_SCRIPT_MENU,/'
    [ $fail -eq 0 ] && echo "selftest: all 16 mutations caught"
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
sout="$(scan_script "$GEAR_FILE" "$VM_FILE" "$PRAYER_FILE")"; src=$?
[ -n "$sout" ] && echo "$sout"
[ $src -gt $rc ] && rc=$src
if [ $rc -eq 0 ]; then
    echo "PASS: no MO_RECREATE or reincarnate branch in $FILE, none in GrantGear in $GEAR_FILE, every prompt in $FILE inside a sourced decision, every script draw, prompt and scope sourced"
fi
exit $rc
