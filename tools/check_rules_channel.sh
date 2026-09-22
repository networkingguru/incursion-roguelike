#!/bin/bash
# gate: cheap
#
# Does the rules channel that replaced the truncating SessionStart hook still
# actually deliver the rules?
#
# WHY THIS EXISTS. Claude Code 2.1.271 truncates each SessionStart hook's
# output at 10,000 characters and injects only a 2,000-character preview, the
# rest spilled to a file the model never reads. That silently dropped the rule
# "commit-means-land-the-bead" on 2026-09-17 (bd inc-2e9w), the same day it was
# written. `tools/prime_rules.py` and `tools/check_prime_budget.sh`, which used
# to certify that channel, are gone (they measured against a 100000-character
# constant that never matched the host's real 10000). The replacement is
# CLAUDE.md's `@AGENTS.md` import and `.claude/rules/*.md`, both of which load
# through the memory loader instead of a hook, with no per-file truncation and
# only a 4 MiB skip. This check is the standing proof that the replacement
# channel is actually in place and actually under its own limits, and that no
# SessionStart hook has quietly grown back into the truncating one.
#
# Four conditions, every one of them a FAIL:
#
#   1. any SessionStart hook registered in .claude/settings.json emits more
#      than CHAR_BUDGET characters. Run and measure, never trust a hook's own
#      claim about its size.
#   2. CLAUDE.md carries no `@AGENTS.md` import.
#   3. .claude/rules/ is missing or holds no *.md.
#   4. AGENTS.md or any .claude/rules/*.md exceeds MAX_BYTES.
#
# Usage: tools/check_rules_channel.sh              run the four conditions
#        tools/check_rules_channel.sh --selftest    prove all four can fire
#        exits 0 pass, 1 fail, 2 could not measure
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

# The two numbers this check enforces. --selftest below reads these same
# variables rather than repeating them: a selftest with its own hard-coded
# number is exactly what made check_prime_budget.sh worthless, since it kept
# printing "PASS: ... at 87744 characters" against a 100000 constant that
# never matched the host's real 10000-character limit.
CHAR_BUDGET=9000
MAX_BYTES=$((4 * 1024 * 1024))

# Character count of stdin, decoded as UTF-8 -- the host's truncation limit
# counts characters, not bytes.
_chars() {
    python3 -c 'import sys; sys.stdout.write(str(len(sys.stdin.buffer.read().decode("utf-8","replace"))))'
}

# Every "command" registered under hooks.SessionStart in a settings.json.
_session_start_commands() {
    local settings="$1"
    [ -f "$settings" ] || return 0
    python3 -c '
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(0)
for block in d.get("hooks", {}).get("SessionStart", []):
    for h in block.get("hooks", []):
        if h.get("type") == "command" and h.get("command"):
            print(h["command"])
' "$settings"
}

# --- condition 1: run every SessionStart hook and measure its own output ----
# <settings.json> <dir to run the commands from>
check_hooks_budget() { # -> prints one line per hook, returns 1 if any is over
    local settings="$1" rundir="$2" cmd out chars st=0 saw=0
    while IFS= read -r cmd; do
        [ -n "$cmd" ] || continue
        saw=1
        out="$(cd "$rundir" && bash -c "$cmd" 2>/dev/null </dev/null)"
        chars="$(printf '%s' "$out" | _chars)"
        if [ "${chars:-0}" -gt "$CHAR_BUDGET" ]; then
            echo "FAIL: SessionStart hook '$cmd' emits $chars characters, over the $CHAR_BUDGET budget."
            st=1
        else
            echo "  ok    $cmd: $chars characters"
        fi
    done < <(_session_start_commands "$settings")
    [ "$saw" -eq 1 ] || echo "  (no SessionStart hooks registered)"
    return "$st"
}

# --- condition 2: CLAUDE.md imports AGENTS.md -------------------------------
check_claude_import() { # <CLAUDE.md path>
    local claudemd="$1"
    if [ ! -f "$claudemd" ]; then
        echo "FAIL: $claudemd does not exist."
        return 1
    fi
    if grep -qF '@AGENTS.md' "$claudemd"; then
        return 0
    fi
    echo "FAIL: $claudemd contains no @AGENTS.md import."
    return 1
}

# --- condition 3: .claude/rules/ holds *.md ---------------------------------
check_rules_dir() { # <.claude/rules path>
    local dir="$1" n
    if [ ! -d "$dir" ]; then
        echo "FAIL: $dir is missing."
        return 1
    fi
    n="$(find "$dir" -maxdepth 1 -type f -name '*.md' 2>/dev/null | wc -l | tr -d ' ')"
    if [ "${n:-0}" -eq 0 ]; then
        echo "FAIL: $dir holds no *.md file."
        return 1
    fi
    echo "  ok    $dir holds $n *.md file(s)"
    return 0
}

# --- condition 4: no instruction file over MAX_BYTES ------------------------
check_file_sizes() { # <AGENTS.md path> <.claude/rules dir>
    local agents="$1" rulesdir="$2" f size st=0
    if [ -f "$agents" ]; then
        size="$(wc -c < "$agents" | tr -d ' ')"
        if [ "$size" -gt "$MAX_BYTES" ]; then
            echo "FAIL: $agents is $size bytes, over $MAX_BYTES (4 MiB)."
            st=1
        fi
    fi
    for f in "$rulesdir"/*.md; do
        [ -f "$f" ] || continue
        size="$(wc -c < "$f" | tr -d ' ')"
        if [ "$size" -gt "$MAX_BYTES" ]; then
            echo "FAIL: $f is $size bytes, over $MAX_BYTES (4 MiB)."
            st=1
        fi
    done
    return "$st"
}

# ---------------------------------------------------------------------------
# --selftest: prove each of the four conditions actually fires, and that each
# also passes on the shape that should pass. Every fixture is built in a temp
# directory; nothing here touches the real repository.
_selftest() {
    local tmp st=0 big_out
    tmp="$(mktemp -d -t rules_channel_selftest)" || return 2
    trap 'rm -rf "$tmp"' RETURN

    echo "--- 1. an oversized SessionStart hook ---"
    mkdir -p "$tmp/big/.claude" "$tmp/big/tools"
    printf '#!/bin/sh\npython3 -c "print(%s*%d)"\n' "'x'" "$((CHAR_BUDGET + 1000))" \
        > "$tmp/big/tools/bighook.sh"
    chmod +x "$tmp/big/tools/bighook.sh"
    cat > "$tmp/big/.claude/settings.json" <<'JSON'
{"hooks":{"SessionStart":[{"matcher":"","hooks":[{"type":"command","command":"tools/bighook.sh"}]}]}}
JSON
    # A var-then-grep, not a piped grep: with `set -o pipefail` a piped
    # `check_hooks_budget | grep -q ...` reports check_hooks_budget's own
    # FAIL exit code (1) to the `if`, not grep's match result, so a real
    # match was read as "not found". Capturing the text first removes the
    # pipeline pipefail was watching.
    big_out="$(check_hooks_budget "$tmp/big/.claude/settings.json" "$tmp/big" 2>&1)"
    if grep -q "over the $CHAR_BUDGET budget" <<< "$big_out"; then
        echo "  ok    an oversized hook is caught"
    else
        echo "  SELFTEST FAIL: an oversized hook was not caught"
        st=1
    fi

    mkdir -p "$tmp/small/.claude" "$tmp/small/tools"
    printf '#!/bin/sh\necho hi\n' > "$tmp/small/tools/smallhook.sh"
    chmod +x "$tmp/small/tools/smallhook.sh"
    cat > "$tmp/small/.claude/settings.json" <<'JSON'
{"hooks":{"SessionStart":[{"matcher":"","hooks":[{"type":"command","command":"tools/smallhook.sh"}]}]}}
JSON
    if check_hooks_budget "$tmp/small/.claude/settings.json" "$tmp/small" >/dev/null 2>&1; then
        echo "  ok    a small hook passes"
    else
        echo "  SELFTEST FAIL: a small hook was wrongly flagged"
        st=1
    fi

    echo "--- 2. CLAUDE.md with no @AGENTS.md import ---"
    printf '# no import here\n' > "$tmp/CLAUDE-noimport.md"
    if check_claude_import "$tmp/CLAUDE-noimport.md" >/dev/null 2>&1; then
        echo "  SELFTEST FAIL: a CLAUDE.md with no import passed"
        st=1
    else
        echo "  ok    a missing import is caught"
    fi
    printf '@AGENTS.md\n\n# rest\n' > "$tmp/CLAUDE-import.md"
    if check_claude_import "$tmp/CLAUDE-import.md" >/dev/null 2>&1; then
        echo "  ok    a present import passes"
    else
        echo "  SELFTEST FAIL: a real import was not recognised"
        st=1
    fi

    echo "--- 3. .claude/rules/ missing or empty ---"
    mkdir -p "$tmp/emptyrules"
    if check_rules_dir "$tmp/emptyrules" >/dev/null 2>&1; then
        echo "  SELFTEST FAIL: an empty rules dir passed"
        st=1
    else
        echo "  ok    an empty rules dir is caught"
    fi
    if check_rules_dir "$tmp/no-such-dir" >/dev/null 2>&1; then
        echo "  SELFTEST FAIL: a missing rules dir passed"
        st=1
    else
        echo "  ok    a missing rules dir is caught"
    fi
    mkdir -p "$tmp/somerules"
    printf 'x\n' > "$tmp/somerules/a.md"
    if check_rules_dir "$tmp/somerules" >/dev/null 2>&1; then
        echo "  ok    a populated rules dir passes"
    else
        echo "  SELFTEST FAIL: a populated rules dir was wrongly flagged"
        st=1
    fi

    echo "--- 4. a file over $MAX_BYTES bytes ---"
    mkdir -p "$tmp/oversize/rules"
    python3 -c "open('$tmp/oversize/AGENTS.md','wb').write(b'x' * ($MAX_BYTES + 1))"
    if check_file_sizes "$tmp/oversize/AGENTS.md" "$tmp/oversize/rules" >/dev/null 2>&1; then
        echo "  SELFTEST FAIL: an oversized AGENTS.md passed"
        st=1
    else
        echo "  ok    an oversized AGENTS.md is caught"
    fi
    python3 -c "open('$tmp/oversize/rules/big.md','wb').write(b'x' * ($MAX_BYTES + 1))"
    if check_file_sizes "$tmp/oversize/nope.md" "$tmp/oversize/rules" >/dev/null 2>&1; then
        echo "  SELFTEST FAIL: an oversized .claude/rules/*.md passed"
        st=1
    else
        echo "  ok    an oversized .claude/rules/*.md is caught"
    fi
    mkdir -p "$tmp/undersize/rules"
    printf 'small\n' > "$tmp/undersize/AGENTS.md"
    printf 'small\n' > "$tmp/undersize/rules/a.md"
    if check_file_sizes "$tmp/undersize/AGENTS.md" "$tmp/undersize/rules" >/dev/null 2>&1; then
        echo "  ok    small files pass"
    else
        echo "  SELFTEST FAIL: small files were wrongly flagged"
        st=1
    fi

    echo
    if [ "$st" -eq 0 ]; then
        echo "SELFTEST PASS: all four conditions fire, and their pass paths hold."
    else
        echo "SELFTEST FAIL: see above."
    fi
    return "$st"
}

if [ "${1:-}" = "--selftest" ]; then
    _selftest
    exit $?
fi

FAIL=0

echo "--- 1. SessionStart hooks, run and measured ---"
check_hooks_budget "$ROOT/.claude/settings.json" "$ROOT" || FAIL=1

echo "--- 2. CLAUDE.md imports AGENTS.md ---"
if check_claude_import "$ROOT/CLAUDE.md"; then
    echo "  ok    CLAUDE.md carries an @AGENTS.md import"
else
    FAIL=1
fi

echo "--- 3. .claude/rules/ holds *.md ---"
check_rules_dir "$ROOT/.claude/rules" || FAIL=1

echo "--- 4. no instruction file over 4 MiB ---"
if check_file_sizes "$ROOT/AGENTS.md" "$ROOT/.claude/rules"; then
    echo "  ok    AGENTS.md and every .claude/rules/*.md are under 4 MiB"
else
    FAIL=1
fi

echo
if [ "$FAIL" -eq 0 ]; then
    echo "PASS: the rules channel is intact."
else
    echo "FAIL: see above."
fi
exit "$FAIL"
