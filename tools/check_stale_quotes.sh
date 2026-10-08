#!/usr/bin/env bash
# gate: cheap --base @base
#
# stale-quote-ok: its --selftest quotes real game strings on purpose
#
# Does a check or a document still quote a C/C++ string literal this change
# removed from the source?
#
#   tools/check_stale_quotes.sh                 # against the base ref (master)
#   tools/check_stale_quotes.sh --base <ref>    # ...compared against that ref
#   tools/check_stale_quotes.sh --selftest      # prove the check still bites
#
# Exit: 0 nothing found
#       1 one or more removed literals are still quoted outside the source
#       2 could not measure
#
# WHY THIS EXISTS. A commit removes a message from src/ or inc/ and the tools and
# docs that quoted it keep quoting it. A guard that proves the old text is gone
# can quote it on purpose, and so can a report that records the removal, but a
# help page or a sibling check that still asserts on the deleted words is a
# reader being told something the tree no longer does. Nothing else in the gate
# notices: the words still exist as text in a file nobody compiles.
#
# WHAT IT MEASURES, AND WHAT IT CANNOT. It compares SOURCE literals: a
# double-quoted C/C++ string constant on a line the change removed from src/,
# inc/ or lib/. A message assembled from a format string, or from several
# literals concatenated, is NOT caught when a check or a document quotes the
# RENDERED text -- the rendered text never appeared as one literal in the source.
#
# MARKUP. A quote or a check usually records the RENDERED text, which is not the
# literal as written. The check understands the small amount of markup the game
# puts inside message literals: `|`, the speech mark that the renderer turns into
# `"` and drops (src/Prayer.cpp Character::GodMessage); a leading `__`, whose
# underscores render as spaces (src/TextTerm.cpp Write/SWrite); and nothing else.
# Colour escapes (`<7>`, `-EMERALD`, `%c`), `~`, `{...}` links and `\n` are not
# modelled. For each removed literal it tests the whole literal AND every
# segment split on `|`, trimmed of surrounding whitespace, with a leading `__`
# also stripped (the rendered form). Punctuation inside a segment is the text's
# own and is kept. A literal, or segment, shorter than 20 characters is dropped
# as too common to be evidence. A candidate that still appears verbatim in src/
# inc/ or lib/ is a move, not a stale quote, and is dropped.
#
# EXEMPTION. A file may quote removed text on purpose. Put a line in its first
# 40 lines reading
#
#   # stale-quote-ok: <why>
#
# (or `<!-- stale-quote-ok: <why> -->` in a markdown file) and this check skips
# every literal inside that file. The guard that proves the old text is gone is
# the case this is for.
#
# docs/REPORTING-GATE.md, docs/rules-history/ and docs/evidence/ are history: a
# removal record there is the document doing its job, so they are never scanned.
# A git-ignored file is not scanned either -- it is not part of the tree.
#
# The base ref comes from --base, defaulting to master; the gate passes the
# branch's base through @base. The merge base of HEAD and that ref is what the
# diff is taken against, so an uncommitted removal counts too.
set -uo pipefail

# The repo root is a variable so the selftest can point the whole check at a
# throwaway repository (inc-yg8e). NIGHTLY_BASE_REF is the same variable name
# nightly_verify.sh already exports for @base.
ROOT="${STALE_QUOTES_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
BASE_REF="${NIGHTLY_BASE_REF:-master}"
MODE="check"

while [ $# -gt 0 ]; do
    case "$1" in
        --base)     BASE_REF="${2:-}"; [ -n "$BASE_REF" ] || { echo "--base needs a ref" >&2; exit 2; }; shift 2 ;;
        --selftest) MODE="selftest"; shift ;;
        -h|--help)  sed -n '2,56p' "$0"; exit 0 ;;
        *)          echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

# The literal parsing and the fixed-string search are one python3 pass, because
# unescaping a C literal and finding it verbatim in another file is text work a
# shell loop cannot do safely. Python 3 only, as the other python helpers here.
run_check() { # <repo-root> <merge-base>
    python3 - "$1" "$2" <<'PY'
import os, re, subprocess, sys

root, mb = sys.argv[1], sys.argv[2]
os.chdir(root)

# The exemption is declared in the first 40 lines of a file: a `#` comment for a
# shell/source file, or an HTML comment in markdown. This is Python's own regex
# syntax, not grep's, so it uses \s rather than [[:space:]].
EXEMPT_RE = re.compile(r'^#\s*stale-quote-ok:\s*\S')
EXEMPT_MD_RE = re.compile(r'<!--\s*stale-quote-ok:\s*\S')

def git(*args):
    return subprocess.run(("git",) + args, capture_output=True, text=True)

# ---------------------------------------------------------- removed literals ---
# git diff <mb> (no --cached, no HEAD) compares the merge base to the WORKING
# TREE, so a removal that is not committed yet still counts.
diff = git("diff", mb, "--", "src/", "inc/", "lib/").stdout

# A double-quoted C literal, with \" and \\ honoured, as written in the source.
LIT = re.compile(r'"(?:\\.|[^"\\])*"')

def unescape(raw):
    # The length filter is stated "after unescaping". Only the two escapes that
    # can appear inside a literal that matters here are decoded; everything else
    # is left as written, because the verbatim search below matches the source.
    return raw.replace('\\"', '"').replace('\\\\', '\\')

removed = {}   # raw literal -> first removed source line that carried it
for line in diff.splitlines():
    if not line.startswith("-") or line.startswith("---"):
        continue
    for m in LIT.finditer(line[1:]):
        raw = m.group(0)[1:-1]
        removed.setdefault(raw, line[1:])

if not removed:
    print("PASS: no removed source literal to quote")
    sys.exit(0)

# ------------------------------------------------------------- candidates ---
# A quote records the RENDERED text, so test the whole literal and each speech
# segment split on `|` (the mark the renderer turns into `"` and drops), trimmed
# of surrounding whitespace. A leading `__` also renders as spaces, so its
# stripped form is tried too. The 20-character floor is applied per candidate
# AFTER unescaping, as the check has always stated.
MIN_LEN = 20

def candidates(raw):
    whole = unescape(raw)
    out = [whole]
    for seg in whole.split("|"):
        seg = seg.strip()
        if not seg:
            continue
        out.append(seg)
        if seg.startswith("__"):
            out.append(seg[2:].lstrip())
    seen = set()
    result = []
    for cand in out:
        if len(cand) < MIN_LEN or cand in seen:
            continue
        seen.add(cand)
        result.append(cand)
    return result

# ------------------------------------------------------- moved, not stale ---
# A candidate still present verbatim anywhere in the source is text that moved.
# Search with git grep so ignored files and build output cannot match, and so a
# binary or a huge file is not read whole.
def source_has(cand):
    return git("grep", "-q", "-F", "-e", cand, "--", "src/", "inc/", "lib/").returncode == 0

survivors = {}
for raw, src in removed.items():
    for cand in candidates(raw):
        if not source_has(cand):
            survivors.setdefault(cand, (raw, src))

if not survivors:
    print("PASS: no removed literal or speech segment long enough, and not moved, to quote")
    sys.exit(0)

# ---------------------------------------------------------------- scanning ---
# tools/ and docs/ are searched fixed-string. The three history paths are the
# document doing its job and a git-ignored file is not part of the tree.
SKIP_PREFIX = ("docs/REPORTING-GATE.md", "docs/rules-history/", "docs/evidence/")

ignored = set()
out = git("ls-files", "--others", "--ignored", "--exclude-standard")
for p in out.stdout.splitlines():
    ignored.add(p)

def is_md(path):
    return path.endswith(".md")

def exempted(path):
    # A file that quotes removed text on purpose declares it in its first 40
    # lines. Two spellings: a `#` comment, or an HTML comment in markdown.
    try:
        with open(path, "r", errors="replace") as fh:
            head = [next(fh, "") for _ in range(40)]
    except OSError:
        return False
    if any(EXEMPT_RE.match(ln) for ln in head):
        return True
    if is_md(path):
        return any(EXEMPT_MD_RE.search(ln) for ln in head)
    return False

# One fixed-string pass per candidate over the two trees. A clean tree has few
# survivors; each is searched with grep -rnF, which stops at the first match.
# Findings are de-duplicated by file:line + candidate, so a candidate that is
# both a whole literal and a segment is reported once per quoting line.
findings = []
seen = set()
for cand in sorted(survivors):
    res = subprocess.run(
        ["grep", "-rInF", "--", cand, "tools/", "docs/"],
        capture_output=True, text=True)
    if res.returncode > 1:
        # grep 2 means a path could not be read; that is a failure to measure.
        print("COULD NOT MEASURE: grep failed over tools/ or docs/", file=sys.stderr)
        sys.exit(2)
    for ln in res.stdout.splitlines():
        parts = ln.split(":", 2)
        if len(parts) < 3:
            continue
        path, lineno, _text = parts
        if path.startswith(SKIP_PREFIX) or path in ignored:
            continue
        if exempted(path):
            continue
        key = (path, lineno, cand)
        if key in seen:
            continue
        seen.add(key)
        findings.append((path, lineno, cand))

if not findings:
    print(f"PASS: {len(survivors)} removed source literal/segment candidate(s) checked, none quoted outside src/ inc/ lib/")
    sys.exit(0)

for path, lineno, cand in findings:
    print(f'{path}:{lineno}: "{cand}"')
print(f"=== FAIL: {len(findings)} stale quote(s) of removed source literal(s) ===")
print("Remove the quote, or add '# stale-quote-ok: <why>' to a file that quotes it on purpose.")
sys.exit(1)
PY
}

if [ "$MODE" = "check" ]; then
    [ -d "$ROOT" ] || { echo "COULD NOT MEASURE: $ROOT is not a directory" >&2; exit 2; }
    cd "$ROOT" || exit 2
    if ! git rev-parse --verify --quiet "$BASE_REF" > /dev/null 2>&1; then
        echo "COULD NOT MEASURE: base ref '$BASE_REF' does not resolve." >&2
        exit 2
    fi
    MB="$(git merge-base HEAD "$BASE_REF" 2>/dev/null)"
    if [ -z "$MB" ]; then
        echo "COULD NOT MEASURE: no merge base between HEAD and '$BASE_REF'." >&2
        exit 2
    fi
    run_check "$ROOT" "$MB"
    exit $?
fi

# ---------------------------------------------------------------- selftest ---
# Build a throwaway repo, remove a long literal in a second commit, and drive the
# real logic against it. Wants: the tools/ quote of the removed literal reported;
# the moved literal, the short literal and the exempted guard NOT reported.
selftest() {
    local dir fails=0 rc out
    dir="$(mktemp -d -t stalequotes)" || return 2
    trap "rm -rf '$dir'" EXIT

    local repo="$dir/repo"
    mkdir -p "$repo/src" "$repo/tools" "$repo/docs"
    git -C "$repo" init -q -b trunk || return 2
    git -C "$repo" config user.email test@example.invalid
    git -C "$repo" config user.name "stale-quotes selftest"

    # State 1: the source carries the literals under test; tools/ and docs/
    # quote them; a guard quotes one on purpose with the marker; the moved
    # literal already lives in a SECOND source file. kMarkupGone is a speech
    # literal whose RENDERED interior a tools/ file quotes; kMarkupShort's only
    # speech segment is too short to be evidence.
    cat > "$repo/src/a.c" <<'EOF'
const char *kKept = "This literal stays in the source forever";
const char *kRemoved = "Watchdog fired before it read a key";
const char *kMoved = "This text only moved to another source file";
const char *kMarkupGone = "A voice booms, |Thou art not worthy of my gifts!|";
const char *kMarkupShort = "A voice booms, |Begone!|";
const char *kShortGone = "too short";
EOF
    cat > "$repo/src/b.c" <<'EOF'
const char *kMovedHere = "This text only moved to another source file";
EOF
    cat > "$repo/tools/check_old.sh" <<'EOF'
#!/bin/sh
# gate: none selftest fixture
echo "Watchdog fired before it read a key"
EOF
    cat > "$repo/tools/check_markup.sh" <<'EOF'
#!/bin/sh
# gate: none selftest fixture
check_expect "Thou art not worthy of my gifts!"
EOF
    cat > "$repo/docs/notes.md" <<'EOF'
The short message was "too short" and is not evidence.
The short speech segment was "Begone!" and is not evidence either.
EOF
    cat > "$repo/tools/guard.sh" <<'EOF'
#!/bin/sh
# stale-quote-ok: proves the old text is gone
grep -q "Watchdog fired before it read a key" src/a.c && exit 1
exit 0
EOF
    git -C "$repo" add -A
    git -C "$repo" commit -q -m "state one"
    git -C "$repo" branch master

    # State 2: remove the literals that are gone; everything else stands. Now
    # HEAD vs master's merge base is the state-one commit, so the removal is
    # visible.
    cat > "$repo/src/a.c" <<'EOF'
const char *kKept = "This literal stays in the source forever";
const char *kMoved = "This text only moved to another source file";
EOF
    git -C "$repo" add -A
    git -C "$repo" commit -q -m "state two"

    out="$(STALE_QUOTES_ROOT="$repo" NIGHTLY_BASE_REF="master" "$0" 2>&1)"
    rc=$?

    _want() { # _want <what> <regex>
        if grep -qE "$2" <<<"$out"; then
            printf '  ok    %s\n' "$1"
        else
            printf '  FAIL  %s\n      wanted /%s/\n      got: %s\n' "$1" "$2" "$out"
            fails=$((fails + 1))
        fi
    }
    _want 'the tools/ quote of the removed literal is reported' \
          '^tools/check_old\.sh:[0-9]+: "Watchdog fired before it read a key"$'
    _want 'the tools/ quote of a removed literal speech segment is reported' \
          '^tools/check_markup\.sh:[0-9]+: "Thou art not worthy of my gifts!"$'
    _want 'the check exits 1 when it finds a stale quote' '=== FAIL'

    if grep -q 'Begone!' <<<"$out"; then
        printf '  FAIL  the short speech segment was reported\n      %s\n' "$out"
        fails=$((fails + 1))
    else
        printf '  ok    the short speech segment is not reported\n'
    fi
    if grep -q 'guard\.sh' <<<"$out"; then
        printf '  FAIL  the exempted guard was reported\n      %s\n' "$out"
        fails=$((fails + 1))
    else
        printf '  ok    the exempted guard is not reported\n'
    fi
    if grep -q 'only moved to another source file' <<<"$out"; then
        printf '  FAIL  the moved literal (still in src/b.c) was reported\n'
        fails=$((fails + 1))
    else
        printf '  ok    the moved literal is not reported\n'
    fi
    if grep -q 'too short' <<<"$out"; then
        printf '  FAIL  the short literal was reported\n'
        fails=$((fails + 1))
    else
        printf '  ok    the short literal is not reported\n'
    fi
    if [ "$rc" != 1 ]; then
        printf '  FAIL  the check exits 1 on a stale quote (got %s)\n' "$rc"
        fails=$((fails + 1))
    else
        printf '  ok    the check exits 1 on a stale quote\n'
    fi

    echo
    [ "$fails" = 0 ] && { echo "SELFTEST PASS"; return 0; }
    echo "SELFTEST FAIL: $fails"
    return 1
}

if [ "$MODE" = "selftest" ]; then
    selftest
    exit $?
fi

echo "unknown mode" >&2
exit 2
