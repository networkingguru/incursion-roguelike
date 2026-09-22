#!/usr/bin/env bash
# gate: cheap
#
#   tools/check_sigpipe_status.sh              scan every file, then selftest
#   tools/check_sigpipe_status.sh --record     re-record tools/sigpipe_status.baseline
#   tools/check_sigpipe_status.sh --selftest   just the ten detector cases
#   tools/check_sigpipe_status.sh --stress     reproduce the race under load
#                                               (minutes; NOT run by the gate)
#
# WHY THIS EXISTS. Every check script in tools/ sets `set -uo pipefail`. Many
# ask a yes/no question with a pipeline whose READER stops at the first
# match, e.g. `printf '%s' "$MARKED" | grep -qxF "$tp<TAB>$oneid"`. `grep -q`
# exits as soon as it matches; the WRITER is then killed by SIGPIPE and exits
# 141; `pipefail` makes 141 the status of the whole pipeline; the script
# reads that as "no match" for data that DOES match. The race is between the
# writer's last write() and the reader's decision to exit, so it is
# intermittent and worse under load. docs/specs/2026-09-22-sigpipe-status-spec.md
# is the normative account, including two real landings this cost
# (check_citations.sh, check_upstream_marks.sh, both on 2026-09-22).
#
# WHAT IT FLAGS, spec section 4.1. A file is in scope when it matches
# tools/*.sh and contains "pipefail". A LOGICAL LINE joins backslash
# continuations. An EARLY-EXIT READER is `grep` carrying `q` in a short-flag
# cluster, or `grep -m <n>`, or `head`. A PIPE INTO A READER is a `|` (not
# `||`) then an optional `!`, optional `VAR=value` prefixes, then a reader.
# The STATUS IS CONSUMED when the logical line begins with
# if/elif/while/until, ends with `; then` or `; do`, the pipeline is preceded
# by `!`, or the pipeline is the left operand of `&&`/`||` on that line. It is
# NOT consumed -- and MUST NOT be flagged -- when the pipeline sits inside a
# command substitution used as a value (`VAR=$(...)`, `local VAR=$(...)`),
# because nothing there tests the pipeline's own exit status; whatever reads
# $? next, if anything, does so on a different logical line, which this tool
# does not attribute back to the substitution.
#
# RULE (e), added after P3 found `path_in_ref` (inc-mwjc): the LAST top-level
# pipe on a logical line is ALSO consumed when that line is the LAST STATEMENT
# OF A FUNCTION -- either the function closes on the very next logical line
# (blank and comment-only lines skipped), or the whole function is written on
# one line, `name() { ... | reader; }`. Such a pipeline becomes the
# function's own return status, and whether some caller, elsewhere, tests
# that status is not visible on this line -- so this deliberately
# OVER-reports every such site, including the value-position ones no caller
# will ever read, and leaves the baseline to forgive them one at a time.
#
# THE RATCHET, spec section 4.2, the same shape as tools/check_doc_citations.sh
# and tools/doc_citations.baseline. tools/sigpipe_status.baseline holds one
# line per file, "<count> <path>", LC_ALL=C sorted, omitting files that scan
# at zero (absent reads as 0). FAILS when a file's count is ABOVE its
# baseline (a new site), when a file absent from the baseline has a nonzero
# count, or when a file's count is BELOW its baseline (a fix nobody
# re-recorded, so the floor never drops). --record rewrites the baseline.
#
# THE SELFTEST, spec section 4.3, runs every time this script is asked to
# check anything (no-argument run = scan, then selftest; either failing
# fails the run). It is pure text over temporary files and costs
# milliseconds. It proves: (1) a new site fails, (2) a dropped count fails
# until re-recorded, (3) an equal count passes, (4) `||` is not read as a
# pipe, (5) a `| head` nested in a command substitution used as a value is
# not flagged even inside an `if`, (6) a `| head` directly in an `if`
# condition IS flagged, (7) a file with no "pipefail" is not scanned at all,
# (8) a pipeline split across a backslash continuation is still seen whole,
# (9) a NEW verdict prints each flagged site's file:line and its own
# truncated source line beneath the summary, so a commit that trips this
# gate names the line rather than sending the author hunting for it,
# (10) rule (e): a whole function written on one line, `name() { cmd | grep
# -q X; }`, is flagged -- no if/while/;then/;do/! anywhere on that line for
# rules (a)-(d) to see, which is exactly the shape that got past every scan
# before rule (e) existed.
#
# Exit: 0 every scanned file matches its baseline, and the selftest passes
#       1 a file is above/below its baseline, or a selftest case failed
#       2 could not measure -- missing baseline, python3 missing, bad usage

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

BASELINE="$ROOT/tools/sigpipe_status.baseline"

command -v python3 > /dev/null 2>&1 || {
    echo "COULD NOT MEASURE: python3 is not on PATH" >&2
    exit 2
}

# ------------------------------------------------------------- the engine ---
# py_scan <path> [<path> ...] -- for every path given, in argv order:
#   COUNT\t<total>\t<path>              always, count 0 included
#   LINE\t<path>\t<lineno>\t<excerpt>   once per flagged site, in file order
# One pass per file produces both, so a caller who wants the sites behind a
# NEW verdict reads the LINE rows already in hand -- it never re-scans the
# file. This is the whole detector: a quote/heredoc/command-substitution-
# aware character scan, never a real shell parse, in keeping with every
# other structural check in this directory. Reused unmodified by the
# ratchet and by the selftest, so a selftest case that turns red is red
# because of THIS code, not a copy of it.
py_scan() {
    python3 - "$@" <<'PYEOF'
import re
import sys


def mask_file(text):
    """Same length/line-structure as text, with: comment text (unquoted '#'
    to EOL) blanked; heredoc bodies blanked (newlines kept); single/double
    quote CONTENTS blanked to 'x' (the quote marks themselves kept); $( and )
    kept intact so a later pass can recover nesting depth. Each $( opens an
    independent quoting frame -- a nested command substitution parses its
    own quotes fresh even when it sits inside an outer double-quoted string
    (out="$(cmd "$x")" -- the inner "$x" is a real nested double-quoted
    string, not literal text of the outer one; treating it as literal was
    an early bug here, caught by check_virtual_override.sh:374 reporting at
    line 372 instead)."""
    n = len(text)
    out = list(text)
    i = 0
    stack = [{'sq': False, 'dq': False}]
    heredoc_stack = []  # list of (terminator, strip_tabs)
    at_line_start = True
    while i < n:
        frame = stack[-1]
        c = text[i]

        if heredoc_stack and at_line_start and len(stack) == 1 and not frame['sq'] and not frame['dq']:
            term, strip_tabs = heredoc_stack[-1]
            eol = text.find('\n', i)
            if eol == -1:
                eol = n
            line = text[i:eol]
            check = line.lstrip('\t') if strip_tabs else line
            if check == term:
                heredoc_stack.pop()
                at_line_start = False
                continue
            for k in range(i, eol):
                out[k] = ' '
            i = eol
            if i < n:
                i += 1
            at_line_start = True
            continue

        at_line_start = False

        if frame['sq']:
            if c == "'":
                frame['sq'] = False
            elif c == '\n':
                at_line_start = True
            else:
                out[i] = 'x'
            i += 1
            continue

        if frame['dq']:
            if c == '\\' and i + 1 < n and text[i+1] in '$`"\\\n':
                out[i] = ' '
                if text[i+1] == '\n':
                    i += 2
                    at_line_start = True
                    continue
                out[i+1] = 'x'
                i += 2
                continue
            if text[i:i+2] == '$(':
                stack.append({'sq': False, 'dq': False})
                i += 2
                continue
            if c == '"':
                frame['dq'] = False
                i += 1
                continue
            if c == '\n':
                at_line_start = True
                i += 1
                continue
            out[i] = 'x'
            i += 1
            continue

        # bare code state of the current frame (no quote open here)
        if c == '\\':
            if i + 1 < n and text[i+1] == '\n':
                out[i] = '\\'  # a phase-2 continuation marker
                i += 2
                at_line_start = True
                continue
            if i + 1 < n:
                out[i] = ' '
                out[i+1] = ' '
                i += 2
                continue
            i += 1
            continue
        if c == "'":
            frame['sq'] = True
            i += 1
            continue
        if c == '"':
            frame['dq'] = True
            i += 1
            continue
        if text[i:i+2] == '$(':
            stack.append({'sq': False, 'dq': False})
            i += 2
            continue
        if c == ')' and len(stack) > 1:
            stack.pop()
            i += 1
            continue
        if c == '#':
            eol = text.find('\n', i)
            if eol == -1:
                eol = n
            for k in range(i, eol):
                out[k] = ' '
            i = eol
            continue
        if c == '\n':
            at_line_start = True
            i += 1
            continue
        if len(stack) == 1 and text[i:i+2] == '<<' and text[i:i+3] != '<<<':
            m = re.match(r"<<-?~?\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\1", text[i:])
            if m:
                term = m.group(2)
                strip_tabs = m.group(0).startswith('<<-')
                heredoc_stack.append((term, strip_tabs))
                i += len(m.group(0))
                continue
        i += 1
    return ''.join(out)


def logical_lines(masked, raw):
    """Join lines whose masked form ends with a lone backslash (the
    continuation marker mask_file leaves behind). raw is the file's own,
    UNmasked text, joined at the same points, so a caller can show a real
    person the actual source line rather than the 'x'-blanked scan text.
    Returns [(start_lineno, masked_text, display_text), ...], 1-indexed."""
    mlines = masked.split('\n')
    rlines = raw.split('\n')
    n = len(mlines)
    result = []
    i = 0
    while i < n:
        start = i
        mparts = [mlines[i]]
        rparts = [rlines[i] if i < len(rlines) else '']
        while mparts[-1].endswith('\\'):
            mparts[-1] = mparts[-1][:-1]
            if rparts[-1].endswith('\\'):
                rparts[-1] = rparts[-1][:-1]
            i += 1
            if i >= n:
                break
            mparts.append(mlines[i])
            rparts.append(rlines[i] if i < len(rlines) else '')
        result.append((start + 1, ' '.join(mparts), ' '.join(rparts)))
        i += 1
    return result


GREP_Q_CLUSTER = re.compile(r'^-[A-Za-z]*q[A-Za-z]*$')
GREP_M_SEP = re.compile(r'^-m$')
GREP_M_ATTACHED = re.compile(r'^-[A-Za-z]*m[0-9]+$')
LEADING_KW = re.compile(r'^\s*(if|elif|while|until)\b')
TRAILING_THEN_DO = re.compile(r';\s*(then|do)\s*$')


def split_words(text):
    return [(m.group(0), m.start()) for m in re.finditer(r'\S+', text)]


def is_reader_at(words, idx):
    if idx >= len(words):
        return False
    cmd = words[idx][0]
    if cmd == 'head':
        return True
    if cmd != 'grep':
        return False
    j = idx + 1
    while j < len(words):
        w = words[j][0]
        if w == '--' or not w.startswith('-'):
            break
        if GREP_Q_CLUSTER.match(w) or GREP_M_ATTACHED.match(w):
            return True
        if GREP_M_SEP.match(w) and j + 1 < len(words) and re.match(r'^[0-9]+$', words[j+1][0]):
            return True
        j += 1
    return False


def paren_depth(text):
    """depth[i] = number of enclosing $( ... ) at char i, recovered from the
    $( / ) markers mask_file left intact. A stray ')' with nothing open is
    left at depth 0 rather than going negative."""
    depth = [0] * len(text)
    cur = 0
    open_count = 0
    i = 0
    n = len(text)
    while i < n:
        if text[i:i+2] == '$(':
            cur += 1
            open_count += 1
            depth[i] = cur
            if i + 1 < n:
                depth[i+1] = cur
            i += 2
            continue
        if text[i] == ')' and open_count > 0:
            depth[i] = cur
            cur -= 1
            open_count -= 1
            i += 1
            continue
        depth[i] = cur
        i += 1
    return depth


def scan_logical_line(text, next_is_close=False):
    """next_is_close: True when the NEXT logical line in the file (blank and
    comment-only lines skipped) is exactly '}' -- the caller works this out
    once per file, looking across lines, which this function never does on
    its own."""
    words = split_words(text)
    depths = paren_depth(text)
    n = len(text)

    # top-level '|' occurrences (not part of '||'), with their depth
    pipes = []
    i = 0
    while i < n:
        if text[i] == '|':
            if i + 1 < n and text[i+1] == '|':
                i += 2
                continue
            if i > 0 and text[i-1] == '|':
                i += 1
                continue
            pipes.append((i, depths[i]))
        i += 1
    if not pipes:
        return 0

    begins_kw = bool(LEADING_KW.match(text))
    ends_then_do = bool(TRAILING_THEN_DO.search(text))
    depth0 = [p for p, d in pipes if d == 0]
    last_depth0_pos = depth0[-1] if depth0 else None

    count = 0
    for pos, depth in pipes:
        if depth > 0:
            continue  # inside $( ... ) -- used as a value, spec 4.1

        j = None
        for k, (_, p) in enumerate(words):
            if p > pos:
                j = k
                break
        if j is None:
            continue
        idx = j
        if words[idx][0] == '!':
            idx += 1
        while idx < len(words) and re.match(r'^[A-Za-z_][A-Za-z0-9_]*=', words[idx][0]):
            idx += 1
        if not is_reader_at(words, idx):
            continue

        consumed = begins_kw or ends_then_do
        if not consumed:
            # this pipeline's own segment: walk back to the previous
            # top-level ';', '&&', '||' or line start
            seg_start = 0
            k = pos - 1
            while k >= 0:
                if depths[k] == 0:
                    if text[k] == ';':
                        seg_start = k + 1
                        break
                    if text[k:k+2] in ('&&', '||'):
                        seg_start = k + 2
                        break
                k -= 1
            if re.match(r'^\s*!(\s|$)', text[seg_start:pos]):
                consumed = True
            else:
                semi_pos = None
                k2 = pos + 1
                while k2 < n:
                    if depths[k2] == 0:
                        if text[k2:k2+2] in ('&&', '||'):
                            consumed = True
                            break
                        if text[k2] == ';':
                            semi_pos = k2
                            break
                    k2 += 1
                # Rule (e): a pipe into an early-exit reader that is the
                # LAST STATEMENT OF A FUNCTION becomes that function's own
                # return status one call away from whatever tests it --
                # path_in_ref (inc-mwjc) was exactly this, called as
                # `if path_in_ref ...; then` two lines below its own body.
                # Whether a caller actually consumes it is not visible on
                # this line, so this deliberately over-reports: every such
                # site is flagged, and the baseline forgives the ones that
                # turn out to be value position or genuinely unread. Only
                # the LAST top-level pipe on the line can be a function's
                # last statement.
                if not consumed and pos == last_depth0_pos:
                    if semi_pos is None:
                        # Nothing follows this reader at all: a multi-line
                        # function body, closed on the line right after.
                        consumed = next_is_close
                    elif text[semi_pos + 1:].strip() == '}':
                        # One-line function: name() { ... | reader; }
                        consumed = True
        if consumed:
            count += 1
    return count


def scan_file(path):
    """One pass over the file. Returns (total, hits, err). hits is
    [(lineno, display_text), ...] with ONE entry per flagged site -- a line
    good for two sites appears twice -- display_text already trimmed and
    truncated, so a caller never re-reads or re-scans the file to report
    where a NEW site is."""
    try:
        text = open(path, encoding='utf-8', errors='replace').read()
    except OSError as e:
        return None, None, str(e)
    masked = mask_file(text)
    total = 0
    hits = []
    llines = logical_lines(masked, text)
    for idx, (lineno, mtext, dtext) in enumerate(llines):
        next_is_close = False
        j = idx + 1
        while j < len(llines) and llines[j][1].strip() == '':
            j += 1
        if j < len(llines) and llines[j][1].strip() == '}':
            next_is_close = True
        n = scan_logical_line(mtext, next_is_close)
        if n:
            total += n
            disp = dtext.strip().replace('\t', ' ')
            if len(disp) > 100:
                disp = disp[:100].rstrip() + '...'
            hits.extend([(lineno, disp)] * n)
    return total, hits, None


if __name__ == '__main__':
    for path in sys.argv[1:]:
        total, hits, err = scan_file(path)
        if err is not None:
            print(f"COULD NOT MEASURE {path}: {err}", file=sys.stderr)
            sys.exit(2)
        print(f"COUNT\t{total}\t{path}")
        for lineno, disp in hits:
            print(f"LINE\t{path}\t{lineno}\t{disp}")
PYEOF
}

# scope_files -- every tools/*.sh containing "pipefail", relative paths,
# LC_ALL=C order. A direct (unpiped) grep, so scanning the scope list is
# itself exempt from the class of bug this tool hunts for.
scope_files() {
    local f
    for f in "$ROOT"/tools/*.sh; do
        [ -f "$f" ] || continue
        grep -q "pipefail" "$f" && printf 'tools/%s\n' "$(basename "$f")"
    done | LC_ALL=C sort
}

# baseline_for <baseline-file> <path> -- the recorded count, or 0 if absent.
baseline_for() {
    awk -v p="$2" '$2 == p { print $1; found=1 } END { if (!found) print 0 }' "$1" | head -1
}

# verdict <count> <baseline> -> NEW|STALE|OK. The whole ratchet decision,
# copied in shape from tools/check_doc_citations.sh's verdict(), isolated so
# the selftest can drive it directly with made-up numbers.
verdict() {
    local n="$1" w="$2"
    if [ "$n" -gt "$w" ]; then echo NEW
    elif [ "$n" -lt "$w" ]; then echo STALE
    else echo OK; fi
}

# ------------------------------------------------------------------ record ---
do_record() {
    local files
    files="$(scope_files)"
    [ -n "$files" ] || { echo "no files in scope" >&2; return 2; }
    py_scan $files | awk -F'\t' '$1 == "COUNT" && $2 > 0 { print $2, $3 }' | LC_ALL=C sort -k2 > "$BASELINE.tmp" || return 2
    mv "$BASELINE.tmp" "$BASELINE"
    local n total
    n=$(wc -l < "$BASELINE" | tr -d ' ')
    total=$(awk '{s+=$1} END {print s+0}' "$BASELINE")
    printf 'recorded baseline: %d file(s), %d site(s) total\n' "$n" "$total"
}

# -------------------------------------------------------------------- scan ---
do_scan() {
    [ -r "$BASELINE" ] || {
        echo "COULD NOT MEASURE: $BASELINE is missing. Record it with:"
        echo "    tools/check_sigpipe_status.sh --record"
        return 2
    }
    local files out path count w v new=0 stale=0 checked=0
    files="$(scope_files)"
    out="$(py_scan $files)" || return 2
    while read -r path; do
        [ -n "$path" ] || continue
        checked=$((checked + 1))
        count="$(printf '%s\n' "$out" | awk -F'\t' -v p="$path" '$1 == "COUNT" && $3 == p { print $2 }')"
        [ -n "$count" ] || count=0
        w="$(baseline_for "$BASELINE" "$path")"
        v="$(verdict "$count" "$w")"
        case "$v" in
            NEW)
                echo "NEW SITE    $path: $count site(s), baseline $w"
                # Reads the SAME $out this file's count came from -- no second
                # scan of $path. One LINE row per flagged site, in file order.
                printf '%s\n' "$out" | awk -F'\t' -v p="$path" '$1 == "LINE" && $2 == p { print $2":"$3": "$4 }'
                echo "    fix: the transform rules are docs/specs/2026-09-22-sigpipe-status-spec.md section 3"
                new=$((new + 1))
                ;;
            STALE) echo "STALE       $path: $count site(s), baseline $w -- lower the baseline"; stale=$((stale + 1)) ;;
        esac
    done <<< "$files"

    echo "checked $checked file(s) against $BASELINE"
    if [ "$new" -gt 0 ]; then
        echo "=== FAIL: $new file(s) gained a sigpipe-status site ==="
        echo "Convert it per docs/specs/2026-09-22-sigpipe-status-spec.md section 3,"
        echo "or file it and re-record if the finding is wrong."
        return 1
    fi
    if [ "$stale" -gt 0 ]; then
        echo "=== FAIL: $stale file(s) are below their baseline ==="
        echo "A site was fixed and the floor was never lowered. Re-record it:"
        echo "    tools/check_sigpipe_status.sh --record"
        return 1
    fi
    echo "=== PASS: no file gained a sigpipe-status site ==="
    return 0
}

# --------------------------------------------------------------- selftest ---
do_selftest() {
    local fails=0 tmp
    tmp="$(mktemp -d "${TMPDIR:-/tmp}/sigpipe_selftest.XXXXXX")" || return 2
    trap 'rm -rf "$tmp"' RETURN

    # 1-3: the ratchet's verdict logic, unit-tested directly (no fixture
    # files needed), the same way check_doc_citations.sh drives its own
    # verdict().
    t() { # t <label> <count> <baseline> <want>
        local got
        got="$(verdict "$2" "$3")"
        if [ "$got" != "$4" ]; then
            echo "FAIL case $1: verdict($2, $3) = $got, wanted $4"
            fails=1
        fi
    }
    t 1-new-site-fails 3 2 NEW
    t 2-dropped-count-fails 2 3 STALE
    t 3-equal-count-passes 3 3 OK

    # 4-6, 8: the detector engine, one fixture apiece.
    detect_case() { # detect_case <label> <want-count> <fixture line...>
        local label="$1" want="$2" f="$tmp/d.sh" got
        shift 2
        printf '%s\n' "$@" > "$f"
        got="$(py_scan "$f" | awk -F'\t' '$1 == "COUNT" { print $2 }')"
        [ -n "$got" ] || got=0
        if [ "$got" != "$want" ]; then
            echo "FAIL case $label: got $got site(s), wanted $want"
            sed 's/^/    fixture: /' "$f"
            fails=1
        fi
        rm -f "$f"
    }

    # 4: '||' must not be read as a pipe -- no writer feeds this grep, it
    # reads "file" directly.
    detect_case 4-or-not-pipe 0 \
        'set -uo pipefail' \
        'if true || grep -q pattern file; then echo hi; fi'

    # 5: a '| head' nested inside a command substitution used as a value is
    # not flagged, even though the enclosing line begins with 'if'.
    detect_case 5-value-position 0 \
        'set -uo pipefail' \
        'if [ -n "$(cmd | head -1)" ]; then echo hi; fi'

    # 6: the same reader, piped directly in the if's own condition (not
    # nested in a substitution), IS flagged.
    detect_case 6-if-condition 1 \
        'set -uo pipefail' \
        'if cmd | head -1; then echo hi; fi'

    # 8: a pipeline split across a backslash continuation is still seen as
    # one logical line. 'then' sits on its own physical line, unjoined, so
    # only the join of the first two lines can make this flag: the joined
    # line begins with 'if' (rule a); the unjoined second line alone begins
    # with '|' and ends with just "pattern", satisfying no consumption rule.
    detect_case 8-backslash-continuation 1 \
        'set -uo pipefail' \
        'if cmd \' \
        '    | grep -q pattern' \
        'then' \
        '    echo hi' \
        'fi'

    # 10: rule (e). A pipe into an early-exit reader that is the LAST
    # STATEMENT OF A FUNCTION is flagged, because it becomes that function's
    # own return status -- path_in_ref (inc-mwjc) was exactly this, one call
    # away from an `if`, and every scan before rule (e) was blind to it. This
    # is the shape that mattered most to catch: the WHOLE function on one
    # line, `name() { cmd | grep -q X; }`, which has no if/while/;then/;do/!
    # anywhere on the line for rules (a)-(d) to see.
    detect_case 10-function-last-statement-oneline 1 \
        'set -uo pipefail' \
        'name() { cmd | grep -q X; }'

    # 7: a file with no "pipefail" anywhere is not scanned at all. Proves
    # BOTH halves: the fixture line would flag on its own (so the exclusion
    # is scope_files, not a detector bug), and scope_files leaves it out.
    local scope_dir="$tmp/scope7" f7 listed got7
    mkdir -p "$scope_dir/tools"
    f7="$scope_dir/tools/check_nopipefail.sh"
    printf '%s\n' '#!/bin/bash' 'if cmd | grep -q pattern; then echo hi; fi' > "$f7"
    got7="$(py_scan "$f7" | awk -F'\t' '$1 == "COUNT" { print $2 }')"
    listed="$(ROOT="$scope_dir" scope_files)"
    if [ "$got7" != "1" ]; then
        echo "FAIL case 7-no-pipefail-not-scanned: fixture line did not flag on its own" \
             "(got $got7, wanted 1) -- the fixture does not exercise the exclusion"
        fails=1
    elif grep -qx 'tools/check_nopipefail.sh' <<< "$listed"; then
        echo "FAIL case 7-no-pipefail-not-scanned: scope_files listed a file with no pipefail"
        fails=1
    fi

    # 9: a NEW verdict prints each flagged site's file:line and a truncated
    # excerpt beneath the summary line -- exercised through the real
    # do_scan/scope_files path (local ROOT/BASELINE shadow the globals for
    # the length of this call; bash resolves a function's free variables
    # dynamically, so do_scan and scope_files see these, not the real tree).
    new_site_case() {
        local ROOT="$tmp/case9"
        local BASELINE="$ROOT/tools/base.baseline"
        mkdir -p "$ROOT/tools"
        printf '%s\n' \
            '#!/bin/bash' \
            'set -uo pipefail' \
            '' \
            'if cmd | grep -q "the marker text"; then' \
            '    echo hi' \
            'fi' > "$ROOT/tools/check_c9.sh"
        printf '0 tools/check_c9.sh\n' > "$BASELINE"
        local got
        got="$(cd "$ROOT" && do_scan 2>&1)"
        if ! grep -qF 'tools/check_c9.sh:4:' <<< "$got"; then
            echo "FAIL case 9-new-site-listing: no 'tools/check_c9.sh:4:' row under the NEW verdict"
            sed 's/^/    | /' <<< "$got"
            fails=1
        elif ! grep -qF 'the marker text' <<< "$got"; then
            echo "FAIL case 9-new-site-listing: listing did not carry the flagged line's own text"
            sed 's/^/    | /' <<< "$got"
            fails=1
        fi
    }
    new_site_case

    if [ "$fails" -eq 0 ]; then
        echo "selftest: PASS (10/10 cases)"
        return 0
    fi
    echo "selftest: FAIL"
    return 1
}

# --------------------------------------------------------------- --stress ---
# Reproduces spec section 1.3 and 4.5. NOT reachable from the gate -- the
# `# gate: cheap` marker at the top of this file carries no arguments, and
# nightly_verify.sh only ever invokes the marked, no-argument form. This
# takes minutes and needs a loaded machine to say anything at all.
#
# FOUR ROWS, not two shapes measured twice. An earlier version of this put
# the ONE `cat` measurement's match on line 1 of the writer, so grep -q
# always exited after its very first read with ~100KB still unwritten: 200
# of 200 misses with NO load running at all. Load changed nothing, so the
# "both shipped shapes are zero" branch could never fire -- a guard that
# cannot fire is not a guard. Splitting `cat` into two rows fixes that:
#
#   row 1  MECHANISM   match on line 1. Deterministic; proves SIGPIPE can
#                       truncate the writer's exit status AT ALL. Needs no
#                       load and should read close to ITER1/ITER1.
#   row 2  FIELD RATE   match at roughly 80% of a ~100KB writer, the shape
#                       the real checks actually have. THIS is the row the
#                       load generator exists for; expect a small fraction,
#                       not most of them. Position matters more than it
#                       looks: measured on this machine (10 cores, idle
#                       otherwise), the miss rate was ~100% up to 66% of the
#                       file and near zero past 90% -- there is a narrow
#                       band, not a smooth gradient, because what decides a
#                       miss is whether `cat` has already finished writing
#                       by the time `grep -q` exits, and that flips sharply
#                       around how many pipe-buffer's worth of data precede
#                       the match, not smoothly with byte position. 80% was
#                       chosen empirically to land in single digits under
#                       load; re-tune it if a future machine disagrees.
#   row 3, 4            the replacements, unchanged, measured against the
#                       row-2 writer; expected zero regardless of load.
do_stress() {
    local cores n_workers load_pids=() i
    local w1 w2 p1 p2 content2
    local miss1=0 miss2=0 miss_here=0 miss_file=0
    local ITER1=1200 ITER2=1200

    cores="$(getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 1)"
    n_workers=$(( cores > 12 ? cores : 12 ))

    w1="$(mktemp "${TMPDIR:-/tmp}/sigpipe_stress_w1.XXXXXX")" || return 2
    w2="$(mktemp "${TMPDIR:-/tmp}/sigpipe_stress_w2.XXXXXX")" || return 2
    p1="STRESS_LINE1_$$"
    p2="STRESS_FIELD_$$"
    { printf '%s\n' "$p1"; head -c 80000 /dev/urandom | base64; } > "$w1"
    { head -c 80000 /dev/urandom | base64
      printf '%s\n' "$p2"
      head -c 20000 /dev/urandom | base64; } > "$w2"
    content2="$(cat "$w2")"

    # Row 1 needs no load and is measured before any is generated, so its
    # number means "the mechanism exists," not "the load helped."
    echo "row 1 (mechanism, no load): $ITER1 iterations..."
    for ((i = 0; i < ITER1; i++)); do
        cat "$w1" | grep -qxF "$p1" || miss1=$((miss1 + 1))
    done

    echo "generating load: $n_workers background worker(s) on $cores core(s)," \
         "serving row 2 only..."
    for ((i = 0; i < n_workers; i++)); do
        ( while true; do cat "$w2" | grep -q "$p2" > /dev/null; done ) &
        load_pids+=("$!")
    done
    trap 'kill "${load_pids[@]}" 2>/dev/null' RETURN

    echo "row 2 (field rate, under load): $ITER2 iterations..."
    for ((i = 0; i < ITER2; i++)); do
        cat "$w2" | grep -qxF "$p2" || miss2=$((miss2 + 1))
    done
    echo "row 3, 4 (replacements, under load): $ITER2 iterations each..."
    for ((i = 0; i < ITER2; i++)); do
        grep -qxF "$p2" <<< "$content2" || miss_here=$((miss_here + 1))
    done
    for ((i = 0; i < ITER2; i++)); do
        grep -qxF "$p2" "$w2" || miss_file=$((miss_file + 1))
    done

    kill "${load_pids[@]}" 2>/dev/null
    wait "${load_pids[@]}" 2>/dev/null
    rm -f "$w1" "$w2"

    printf '\n%-46s %s\n' "row" "misses"
    printf '%-46s %d / %d\n' "1  cat FILE | grep -qxF P   (mechanism)"   "$miss1"  "$ITER1"
    printf '%-46s %d / %d\n' "2  cat FILE | grep -qxF P   (field rate)" "$miss2"  "$ITER2"
    printf '%-46s %d / %d\n' "3  grep -qxF P <<< \$VAR    (replacement)" "$miss_here" "$ITER2"
    printf '%-46s %d / %d\n' "4  grep -qxF P FILE         (replacement)" "$miss_file" "$ITER2"
    echo

    # THE VERDICT, spec 4.5 and 5.1, restated after the row-1/row-2 split.
    if [ "$miss1" -eq 0 ]; then
        echo "INCONCLUSIVE: row 1 (mechanism, no load needed) measured zero misses."
        echo "SIGPIPE did not truncate the writer's status even once, so nothing"
        echo "below this line means anything on this run."
        return 2
    fi
    if [ "$miss2" -eq 0 ]; then
        echo "INCONCLUSIVE: row 2 (field rate, under load) measured zero misses."
        echo "The load generator did not reproduce the race on this machine this"
        echo "run -- this is NOT evidence the bug is gone. Re-run, or on a busier"
        echo "machine."
        return 2
    fi
    if [ "$miss_here" -gt 0 ] || [ "$miss_file" -gt 0 ]; then
        echo "FAIL: a replacement shape reported a miss on data known to match."
        echo "The fix does not hold."
        return 1
    fi
    echo "PASS: the shipped shape lost data to SIGPIPE both on line 1 and at"
    echo "field rate under load; neither replacement shape did, in the same run."
    return 0
}

# ------------------------------------------------------------------- main ---
case "${1:-}" in
    --record)   do_record;   exit $? ;;
    --selftest) do_selftest; exit $? ;;
    --stress)   do_stress;   exit $? ;;
    -h|--help)  sed -n '3,6p' "$0"; exit 0 ;;
    "")
        rc=0
        do_scan || rc=1
        do_selftest || rc=1
        exit "$rc"
        ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
esac
