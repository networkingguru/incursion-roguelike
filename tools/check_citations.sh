#!/usr/bin/env bash
#
# Resolve every code citation in a document against the tree it claims to cite.
#
#   tools/check_citations.sh docs/outgoing/pr43.md
#   tools/check_citations.sh docs/outgoing/pr43.md --expect docs/outgoing/pr43.expect
#   tools/check_citations.sh --selftest
#
# WHY THIS EXISTS. Anything we send upstream cites rmtew's tree, but we read our
# own. The two have drifted by hundreds of lines in some files, so a line number
# copied from our working tree points at unrelated code in his. That mistake was
# made and caught three times on 2026-08-17 alone, twice in the same document
# (src/Main.cpp:280 for :220, src/Registry.cpp:597 for :561). Attention does not
# fix a mistake that recurs; a gate does.
#
# WHAT IT CHECKS
#   1. Every GitHub blob/tree link to the UPSTREAM repo -- the path exists at
#      the ref NAMED IN THE URL, and the #L anchor is printed with its actual
#      content at that ref. Pinning links to a commit rather than to master is
#      what keeps a comment's line numbers true after the branch moves, so the
#      check follows whatever ref the reader would follow.
#   2. Every GitHub link to OUR fork -- the path exists on the published ref,
#      because an evidence link that is only in the working tree 404s for the
#      reader. This is the check that fails when we forget to push.
#   3. Every named `File.ext:NNNN` citation in the prose -- ANY extension, not
#      a list of favoured ones -- resolved to a unique path, range-checked
#      against that file's length, then printed with its content.
#   4. Every bare `:NNNN` continuation -- a line number written with no file in
#      front of it, which inherits the file named before it in the prose. The
#      inheritance rule is strict and is described at the check itself.
#
# There is no citation this tool looks at and says nothing about. Checks 3 and 4
# are two spellings of one question, so they MUST give the same verdict for the
# same citation; the selftest asserts that directly. They did not always: a
# `.sh` citation written in full was invisible to check 3, while the bare form
# was a hard error telling the writer to write it in full. Following the tool's
# own advice silenced the tool. If you ever narrow one of these two scans,
# narrow both, or you rebuild that trapdoor.
#   5. With --expect, each `path:line<TAB>substring` line in the expectations
#      file must match the resolved content, and a mismatch fails the run.
#
# WHAT IT CANNOT CHECK, AND WHY A PASS IS NOT AN ALL-CLEAR
#
# The tool cannot tell whether the sentence around a citation is true. A
# citation can resolve fine and still be wrong, because the line it names is not
# the line the prose described. That is a limit of the design, not a defect in
# it. The only thing that catches it is a person re-reading the claim against
# the source. Keep that manual pass in the routine; do not let a green gate
# replace it.
#
# Concretely: this tool answers "does src/Art.cpp:1337 exist, and what is on
# it". It does not answer "is line 1337 the malloc cast the paragraph claims".
# Use the expectations file (--expect) to pin the claims that matter, because an
# expectation is the only part of this tool that reads the content rather than
# the address. Everything else is an address check.
#
# TWO TREES, AND WHY THE SECOND ONE IS NOT A SOFTENING
#
# Most citations point at files rmtew has. Some point at files only this port
# has -- tools/*.sh, tools/*.py, src/Wposix.cpp, src/MapAudit.cpp, the documents
# themselves. Those are perfectly checkable; they are simply not checkable
# against upstream. So the tool resolves against UPSTREAM_REF first and falls
# back to FALLBACK_REF, and the fallback can never launder a wrong upstream
# citation, because it is only ever reached for a basename upstream does not
# carry AT ALL. A file upstream has is always measured against upstream.
#
# A citation resolved by the fallback is reported, counted, and exits 3. It is
# never reported as "no defects", because the reader of an outgoing document
# needs to know that this line number was confirmed somewhere rmtew cannot see.
#
# Exit status:
#   0  every citation was checked against UPSTREAM_REF and every one resolved
#   1  a defect was found
#   2  the invocation was wrong
#   3  no defects, but N citations could only be checked against FALLBACK_REF.
#      Non-zero on purpose. A gate for anything going upstream MUST require 0.
#      A gate for an internal document MAY accept 3, having read the list.

set -uo pipefail

UPSTREAM_REF=${UPSTREAM_REF:-upstream/master}
ORIGIN_REF=${ORIGIN_REF:-origin/master}
UPSTREAM_HOST=${UPSTREAM_HOST:-rmtew/incursion-roguelike}
ORIGIN_HOST=${ORIGIN_HOST:-networkingguru/incursion-roguelike}

# HEAD and not the working tree. A citation must be reproducible by anyone who
# checks out the same commit; a number that resolves only against an unsaved
# buffer is not evidence. The cost is that a citation into a file edited but not
# yet committed reads the committed lengths, which is the safer way to be wrong.
FALLBACK_REF=${FALLBACK_REF:-HEAD}

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || {
    echo "not inside a git repository" >&2; exit 2; }

defects=0
unchecked=0

fail() { printf 'DEFECT  %s\n' "$1"; defects=$((defects + 1)); }

# One place decides the exit status, because the selftest must be able to assert
# on the same rule the caller sees. A defect outranks an unchecked citation:
# both are non-zero, and the worse news goes first.
verdict() {
    [ "$defects" -gt 0 ] && return 1
    [ "$unchecked" -gt 0 ] && return 3
    return 0
}

# Cache one tree listing per ref; ls-tree on every citation is slow enough to
# notice on a document with fifty of them. The cache lives in a per-run
# directory: a cache that outlives the run would answer for a ref that has moved
# since, and an empty one would report every path as missing.
CACHE_DIR=$(mktemp -d "${TMPDIR:-/tmp}/checkcit.XXXXXX") || exit 2
trap 'rm -rf "$CACHE_DIR"' EXIT

list_ref() {
    # Two statements, not one `local a=.. b=..$a..`: bash expands every word of
    # a single declaration before assigning any of them, so the second would
    # read an unset variable and abort the function under `set -u`.
    local ref=$1
    local cache="$CACHE_DIR/$(printf '%s' "$ref" | tr / _).list"
    [ -s "$cache" ] || git -C "$ROOT" ls-tree -r --name-only "$ref" > "$cache" 2>/dev/null
    cat "$cache"
}

path_in_ref() { list_ref "$1" | grep -qxF "$2"; }

# A bare citation gives only a basename. Accept it when exactly one file in the
# named tree carries that name; anything else is ambiguous and must be written
# out in full.
resolve_in_ref() {
    local ref=$1 base=$2 hits
    hits=$(list_ref "$ref" | grep -E "(^|/)$(printf '%s' "$base" | sed 's/[.[\*^$]/\\&/g')$")
    [ "$(printf '%s\n' "$hits" | grep -c .)" = 1 ] || return 1
    printf '%s\n' "$hits"
}

# Resolve a basename and say which tree answered, so the caller can report the
# difference. Prints "<ref><TAB><path>" and returns 1 when neither tree has it.
resolve_basename() {
    local base=$1 hit
    if hit=$(resolve_in_ref "$UPSTREAM_REF" "$base"); then
        printf '%s\t%s\n' "$UPSTREAM_REF" "$hit"; return 0
    fi
    if hit=$(resolve_in_ref "$FALLBACK_REF" "$base"); then
        printf '%s\t%s\n' "$FALLBACK_REF" "$hit"; return 0
    fi
    return 1
}

line_at_ref() { git -C "$ROOT" show "$1:$2" 2>/dev/null | sed -n "${3}p"; }
lines_in_ref() { git -C "$ROOT" show "$1:$2" 2>/dev/null | grep -c ''; }

check_document() {
    local doc=$1 expect=${2:-} url_ref
    [ -r "$doc" ] || { echo "cannot read $doc" >&2; exit 2; }

    local resolved="${TMPDIR:-/tmp}/checkcit-resolved.$$"
    : > "$resolved"

    # 1 & 2. Links.
    local url path anchor
    while read -r url; do
        [ -n "$url" ] || continue
        path=${url#https://github.com/}
        anchor=${path#*\#}
        [ "$anchor" = "$path" ] && anchor=""
        path=${path%%\#*}
        case "$path" in
            "$UPSTREAM_HOST"/blob/*)
                # Accept any ref in the URL, not just master: a link meant to
                # outlive the branch is pinned to a commit. Resolve the content
                # at the ref the READER will follow, which is the whole point.
                path=${path#"$UPSTREAM_HOST"/blob/}
                url_ref=${path%%/*}
                path=${path#*/}
                if ! git -C "$ROOT" rev-parse --verify --quiet "$url_ref^{commit}" > /dev/null; then
                    fail "link names a ref this clone cannot resolve: $url_ref ($url)"
                    continue
                fi
                if path_in_ref "$url_ref" "$path"; then
                    if [ -n "$anchor" ]; then
                        local n=${anchor#L}; n=${n%%-*}
                        printf '%s:%s\t%s\n' "$path" "$n" "$(line_at_ref "$url_ref" "$path" "$n")" >> "$resolved"
                        printf 'upstream %s@%s:%s  %s\n' "$path" "${url_ref:0:10}" "$n" \
                            "$(line_at_ref "$url_ref" "$path" "$n")"
                    else
                        printf 'upstream %s@%s  (no anchor)\n' "$path" "${url_ref:0:10}"
                    fi
                else
                    fail "$path is not in $url_ref (link: $url)"
                fi
                ;;
            "$ORIGIN_HOST"/blob/*|"$ORIGIN_HOST"/tree/*)
                # Same rule as upstream: honour the ref in the URL. An evidence
                # link on a branch shows the reader whatever the branch says
                # later, which is not what was reviewed.
                path=${path#"$ORIGIN_HOST"/blob/}
                path=${path#"$ORIGIN_HOST"/tree/}
                url_ref=${path%%/*}
                path=${path#*/}
                path=${path%/}
                # No silent fallback to ORIGIN_REF. A ref this clone cannot
                # resolve is usually a placeholder that was never repinned, and
                # falling back hides it: the path exists on origin/master, the
                # check passes, and the document goes out carrying a URL that
                # 404s. Found on 2026-08-18, when three placeholders were
                # reported and a fourth was not.
                if ! git -C "$ROOT" rev-parse --verify --quiet "$url_ref^{commit}" > /dev/null; then
                    fail "link names a ref this clone cannot resolve: $url_ref ($url)"
                    continue
                fi
                if list_ref "$url_ref" | grep -qE "^$(printf '%s' "$path" | sed 's/[.[\*^$]/\\&/g')(/|$)"; then
                    printf 'ours     %s  present at %s\n' "$path" "${url_ref:0:10}"
                else
                    fail "$path is not at $url_ref -- unpushed or misspelt (link: $url)"
                fi
                ;;
            *)
                fail "link points at neither tree: $url"
                ;;
        esac
    done < <(grep -oE 'https://github\.com/[A-Za-z0-9_.@:/~-]+(#L[0-9]+(-L[0-9]+)?)?' "$doc" | sort -u)

    # 3. Named File.ext:NNNN citations.
    #
    # The pattern takes ANY extension, not just cpp/h/irh. It used to take only
    # those three, so `build_macos.sh:34` was never looked at by any part of
    # this tool and the run said "no defects" about it. `build_macos.sh:99999`
    # said the same. A checker that is silent about a citation it never read is
    # the failure this file exists to prevent, and an extension list is no
    # excuse for it. Same shape rules as the continuation check below: the stem
    # is at least two characters and the extension at most four, so that C++
    # member access in prose is not mistaken for a file name.
    #
    # THE LINE NUMBER IS RANGE-CHECKED. It was not, and `src/Display.cpp:99999`
    # printed an empty content line and passed -- on the upstream path, which is
    # the one an outgoing PR comment travels. An empty line is not evidence that
    # a line exists; it is evidence that `sed -n 99999p` had nothing to print.
    local cite base num hit ref full len
    while read -r cite; do
        [ -n "$cite" ] || continue
        base=${cite%%:*}
        num=${cite##*:}
        if ! hit=$(resolve_basename "$base"); then
            fail "cannot resolve '$base' to one file in $UPSTREAM_REF or $FALLBACK_REF (cited as $cite)"
            continue
        fi
        ref=${hit%%$'\t'*}
        full=${hit#*$'\t'}
        len=$(lines_in_ref "$ref" "$full")
        if [ "$num" -gt "$len" ] || [ "$num" -lt 1 ]; then
            fail "$cite is past the end of $full, which has $len lines in $ref"
            continue
        fi
        printf '%s:%s\t%s\n' "$full" "$num" "$(line_at_ref "$ref" "$full" "$num")" >> "$resolved"
        if [ "$ref" = "$UPSTREAM_REF" ]; then
            printf 'bare     %s:%s  %s\n' "$full" "$num" "$(line_at_ref "$ref" "$full" "$num")"
        else
            printf 'UNCHECKED %s:%s  (only in %s, not in %s)  %s\n' \
                "$full" "$num" "$ref" "$UPSTREAM_REF" "$(line_at_ref "$ref" "$full" "$num")"
            unchecked=$((unchecked + 1))
        fi
    done < <(grep -oE '\b[A-Za-z_][A-Za-z0-9_-]+\.[A-Za-z][A-Za-z0-9]{0,3}:[0-9]+' "$doc" | sort -u)

    # 4. Bare continuation citations -- a `:NNNN` with no file in front of it.
    #
    # The prose writes `Skills.cpp:4161` once and then `:4181` for the next
    # reference, so a bare number inherits whatever file was named last. Move a
    # paragraph, or write a new one between them, and the number silently
    # re-points at a different file. That has now happened twice in this
    # document: `:887` and `:927` inherited Skills.cpp when they meant
    # Feature.cpp, and `:4161` inherited Feature.cpp, which has 1049 lines.
    # Neither is catchable by eye and both survive a full read.
    #
    # The check walks the document in order, tracks the file the prose is
    # talking about, and resolves each bare number against it. A number past the
    # end of that file is certainly wrong. A number inside it may still be
    # wrong, so the resolved line is printed for reading.
    #
    # WHEN THE CONTEXT CANNOT BE ESTABLISHED, THIS IS A DEFECT AND NOT A PASS.
    # The first version of this check carried the last file named anywhere in
    # the document forward for ever, and skipped in silence when no file had
    # been named yet. Both behaviours hid errors instead of finding them. On
    # 2026-08-18 that cost four false alarms and four silent passes in one
    # sentence of docs/PORT-STATUS.md: the prose said "all in `src/Art.cpp`"
    # without a line number, so `:550`, `:552`, `:554`, `:556`, `:1337`,
    # `:1339`, `:1341` and `:1343` all inherited inc/Map.h from a paragraph
    # further up. The four large ones were reported as defects although they
    # were correct, and -- much worse -- the four small ones were reported as
    # GOOD after being checked against a file they have nothing to do with.
    # A checker that validates a citation against the wrong file is worse than
    # no checker, because it produces evidence of a check that never happened.
    # So a number whose file cannot be established now fails the run.
    python3 - "$doc" "$UPSTREAM_REF" "$ROOT" "$FALLBACK_REF" "$CACHE_DIR" \
        <<'PYCHECK' || defects=$((defects + 1))
import os, re, subprocess, sys

doc, ref, root, fallback, cache = sys.argv[1:6]
text = open(doc).read()

# One regex for every filename-shaped token, with the line number optional. The
# line number is optional because a file named WITHOUT one -- "all in
# `src/Art.cpp`" -- is still the prose telling you what it is talking about, and
# the old regex, which required the number, could not see it at all.
#
# The stem must be at least two characters and the extension at most four,
# because prose about C++ is full of member access that is otherwise identical
# in shape. `s.h` is a struct member in an outgoing draft, not a header;
# `fh.Version`, `VM.Execute` and `ts.removeCreatureTarget` are calls, not files.
# A one-character stem is never a real file in this tree (checked against
# upstream/master), and no extension used in these documents -- cpp, h, irh, sh,
# py, md, log, keys, irc, i, c, acc, bat, Dat, Mod -- is longer than four.
#
# There is no extension WHITELIST here any more. The first version of this check
# treated a name as a file only when the extension was cpp, h or irh, so a
# `.sh` was a thing that destroyed the context and could never provide one. That
# produced advice the tool could not honour: it told the writer to name the file
# in full, and naming `build_macos.sh:34` in full made the tool say nothing at
# all. What decides now is whether the file can be FOUND, which is the question
# that was always being asked.
fileish = re.compile(r'\b([A-Za-z_][A-Za-z0-9_-]+)\.([A-Za-z][A-Za-z0-9]{0,3})\b(?::(\d+))?')
bare    = re.compile(r'(?<![\w.])(?<!\.cpp)(?<!\.h)(?<!\.irh):(\d+)')

trees = {}
def tree(r):
    if r not in trees:
        out = subprocess.run(['git', '-C', root, 'ls-tree', '-r', '--name-only', r],
                             capture_output=True, text=True).stdout.split()
        index = {}
        for p in out:
            index.setdefault(p.split('/')[-1], []).append(p)
        trees[r] = index
    return trees[r]

# Upstream first, then the fallback. The order is the whole safety argument: a
# basename upstream carries is ALWAYS measured against upstream, so the fallback
# cannot quietly bless a line number rmtew's tree does not have. The fallback is
# reached only for a file upstream does not carry at all.
#
# `unresolved` says WHY, because the two reasons need opposite fixes. A name no
# tree carries needs a different name. A name several files carry -- Options.Dat
# is both `Options.Dat` and `tools/gates/Options.Dat` -- needs a path, and
# telling that writer to "name a file that is committed" would be nonsense,
# since the file is committed twice over.
lengths, unresolved = {}, {}
def length_of(base):
    if base not in lengths:
        lengths[base] = (None, None, 0)
        unresolved[base] = (f"is in neither {ref} nor {fallback}",
                            "Name a file that is committed, or cite the generator input.")
        for r in (ref, fallback):
            hits = tree(r).get(base, [])
            if len(hits) == 1:
                body = subprocess.run(['git', '-C', root, 'show', f'{r}:{hits[0]}'],
                                      capture_output=True, text=True).stdout
                lengths[base] = (r, hits[0], body.count('\n'))
                unresolved[base] = None
                break
            if len(hits) > 1:
                unresolved[base] = (f"is the name of {len(hits)} different files in {r}",
                                    "Write the path, not just the file name.")
    return lengths[base]

def line_of(r, path, num):
    body = subprocess.run(['git', '-C', root, 'show', f'{r}:{path}'],
                          capture_output=True, text=True).stdout.splitlines()
    return body[num - 1] if 0 < num <= len(body) else ''

# Two kinds of event, in document order.
#   'file'  a name -- it becomes the context, or destroys it if nothing has it.
#   'bare'  a lone :NNNN -- it consumes the context.
events = []
for m in fileish.finditer(text):
    name, num = m.group(1) + '.' + m.group(2), m.group(3)
    events.append((m.start(), m.end(), 'file', name, int(num) if num else None))
for m in bare.finditer(text):
    events.append((m.start(), m.end(), 'bare', None, int(m.group(1))))
events.sort(key=lambda e: e[0])

# Two distances, two units, so two settings. CITATION_FAR is measured in LINES
# of the cited source file; CITATION_FAR_CHARS is measured in CHARACTERS of the
# document being read. They are deliberately not the same number.
#
# 1000 characters is roughly a long paragraph of this repository's prose. It was
# not guessed: every bare continuation in docs/ and tools/README.md was measured
# on 2026-08-18, and the furthest HONEST one sits 779 characters from its file
# name (docs/outgoing/pr43-reply.md:73, four numbers in Feature.cpp). Setting
# the limit below that would reject correct writing, so 1000 gives that measured
# worst case about a 20% margin and nothing more. Raise it only with the same
# measurement, never to quieten a document.
FAR       = int(os.environ.get('CITATION_FAR', '400'))
FAR_CHARS = int(os.environ.get('CITATION_FAR_CHARS', '1000'))

# The context is [basename, end offset of the most recent citation in this
# thread, scoped]. A run of continuations keeps the thread alive: each accepted
# number moves the offset forward, so "Event.cpp:339 ... :55 ... :75 ... :95"
# stays one reference however long the list runs. What the thread cannot survive
# is a stretch of prose with no citation in it, or the naming of any other file.
#
# `scoped` is true when the file was named WITHOUT a line number. That
# distinction decides whether the line-gap heuristic below applies, and the
# reason is at the heuristic itself.
#
# `dead` remembers WHY the context went away, so the second and third numbers of
# a broken run say something as useful as the first. Without it the report reads
# "no file is named before it" for a number that plainly has a file name three
# words to its left, and the reader concludes the tool is confused rather than
# that the file it names is one the tool cannot open.
ctx, dead, bad, unchecked, cited = None, None, 0, 0, {}

# The advice at the end of the message is the writer's next action, so it has to
# be an action that works. It used to read "write the file name out in full"
# unconditionally, which was wrong advice for a `.sh`: writing it out reached a
# part of the tool that ignored the extension entirely, so the hard error turned
# into a silent pass and nothing was gained. The caller now supplies the advice
# with the reason, and every branch below offers something the tool can honour.
def lost(num, why, advice):
    global bad, ctx, dead
    print(f"DEFECT  bare ':{num}' has no file context -- {why}. {advice}")
    bad += 1
    ctx, dead = None, (why, advice)

for start, end, kind, name, num in events:
    if kind == 'file':
        r, path, n = length_of(name)
        if path is None:
            # Named, and not resolvable. It is still the subject of the prose,
            # so it ends the previous file's claim on the numbers that follow --
            # answering about a different file is the error this check exists to
            # find. `program.i` is generated and not committed; a log file quoted
            # in an example block is not a file in the repository at all.
            ctx = None
            reason, advice = unresolved[name]
            dead = (f"the last file named before it is {name}, which {reason}", advice)
            continue
        ctx, dead = [name, end, num is None], None
        if num is not None:
            cited.setdefault(name, set()).add(num)
        continue

    if ctx is None:
        why, advice = dead or ("no file is named before it",
                               "Name the file this number is in.")
        lost(num, why, advice)
        continue
    base, anchor, scoped = ctx
    gap_chars = start - anchor
    if gap_chars > FAR_CHARS:
        lost(num, f"the nearest {base} citation is {gap_chars} characters back, "
                  f"too far to be sure it is the same reference "
                  f"(CITATION_FAR_CHARS={FAR_CHARS})",
                  f"Write `{base}:{num}` here.")
        continue
    r, path, n = length_of(base)
    if num > n:
        print(f"DEFECT  bare ':{num}' follows {base}, which has only {n} lines "
              f"-- it inherited the wrong file")
        bad += 1
        ctx = [base, end, scoped]
        continue
    # A continuation that lands thousands of lines from anything else cited in
    # that file has almost certainly inherited the wrong file and happened to
    # be in range. In the document this was written for, every honest
    # continuation sat within a hundred lines of its anchor, and all three real
    # errors were over three thousand away.
    #
    # It does NOT apply to a scoped context -- a file named without a line
    # number, as in "eight survive, all in `src/Art.cpp` (`:550` ... `:1343`)".
    # That sentence is the writer declaring the scope of everything that
    # follows, and a declared scope is exactly where numbers 800 lines apart are
    # normal and correct. The heuristic guesses at whether a number INHERITED
    # the wrong file; where the writer states the file outright there is no
    # inheritance left to guess about. Applying it there reported all four of
    # the 1337-1343 casts in docs/PORT-STATUS.md as defects when all four were
    # right. The protection that matters is untouched: `Skills.cpp:4161`
    # followed much later by `:887` still carries a number, so it is not scoped,
    # and the heuristic still fires on it.
    seen = cited.get(base)
    if seen and not scoped:
        gap = min(abs(num - c) for c in seen)
        if gap > FAR:
            print(f"DEFECT  bare ':{num}' follows {base}, but the nearest other "
                  f"{base} citation is {gap} lines away -- check it did not "
                  f"inherit the wrong file")
            bad += 1
            ctx = [base, end, scoped]
            continue
    if r != ref:
        # Checked, and checked correctly -- but against a tree the reader of an
        # outgoing document cannot see. Printed and counted, never silent.
        print(f"UNCHECKED {path}:{num}  (only in {r}, not in {ref})  "
              f"{line_of(r, path, num)}")
        unchecked += 1
    cited.setdefault(base, set()).add(num)
    ctx = [base, end, scoped]

# Hand the count back through a file. The block's stdout is the report the user
# reads, so it cannot also be a return channel, and an exit status carries one
# number badly.
open(os.path.join(cache, 'unchecked'), 'w').write(str(unchecked))
sys.exit(1 if bad else 0)
PYCHECK
    if [ -s "$CACHE_DIR/unchecked" ]; then
        unchecked=$((unchecked + $(cat "$CACHE_DIR/unchecked")))
        rm -f "$CACHE_DIR/unchecked"
    fi

    # 5. Expectations.
    if [ -n "$expect" ]; then
        [ -r "$expect" ] || { echo "cannot read $expect" >&2; exit 2; }
        local want key sub got
        while IFS=$'\t' read -r key sub; do
            case "$key" in ''|\#*) continue ;; esac
            got=$(git -C "$ROOT" show "$UPSTREAM_REF:${key%%:*}" 2>/dev/null | sed -n "${key##*:}p")
            case "$got" in
                *"$sub"*) printf 'expect   %s  ok\n' "$key" ;;
                *)        fail "$key does not contain '$sub' -- it has: $got" ;;
            esac
        done < "$expect"
    fi

    rm -f "$resolved"
}

selftest_failures=0

# Run one fixture and compare the run's verdict with the wanted one. The verdict
# is the real exit path -- "did $defects end at zero" -- and not a grep for the
# word DEFECT, because the thing a caller depends on is the exit status. A test
# that watches the message instead of the status passes a tool that prints a
# complaint and then exits 0, which is the failure mode this file is here to
# prevent in documents.
selftest_case() {
    local label=$1 want=$2 doc=$3 exp=${4:-} got
    ( defects=0; unchecked=0; check_document "$doc" "$exp" > "$doc.out" 2>&1; verdict )
    got=$?
    [ "$got" = "$want" ] && return 0
    printf 'selftest FAIL: %s -- wanted exit %s, got %s\n' "$label" "$want" "$got"
    sed 's/^/    | /' "$doc.out"
    selftest_failures=$((selftest_failures + 1))
}

selftest() {
    local dir="${TMPDIR:-/tmp}/checkcit-selftest.$$"
    mkdir -p "$dir"
    selftest_failures=0

    # One citation that must resolve, one link to a path that cannot exist.
    printf 'Feature.cpp:850 is Thing::MoveDepth.\n' > "$dir/good.md"
    printf 'See https://github.com/%s/blob/master/src/NoSuchFile.cpp#L1\n' \
        "$UPSTREAM_HOST" > "$dir/bad.md"
    printf 'src/Feature.cpp:850\tThing::MoveDepth\n' > "$dir/good.expect"

    # A file named with NO line number must become the context for the bare
    # numbers after it. This is the docs/PORT-STATUS.md sentence of 2026-08-18,
    # cut down: inc/Map.h stops 981 lines short of 1337, so before the fix this
    # fixture reported a defect on a citation that was right, and the small
    # numbers in the same list were checked against Map.h and passed on a file
    # they have nothing to do with.
    printf 'The cast at `inc/Map.h:649` was dropped. Eight survive, all in\n' \
        > "$dir/adopt.md"
    printf '`src/Art.cpp` (`:550`, `:552`, `:1337`, `:1343`).\n' >> "$dir/adopt.md"

    # A bare number with no file named anywhere before it. The old code skipped
    # it in silence and the run passed.
    printf 'The generation loop at `:4161` reads one past the end.\n' \
        > "$dir/nocontext.md"

    # Naming another file ends the previous file's claim on the numbers that
    # follow. Before this check existed `:34` was checked against Art.cpp -- 34
    # is inside Art.cpp and four lines from the 30 already cited, so it passed,
    # silently, against the wrong file. build_macos.sh is not in upstream, so
    # the honest verdict is 3: checked, but not where rmtew can see it.
    printf 'The cast is at `src/Art.cpp:30`. `tools/build_macos.sh:31` sets\n' \
        > "$dir/otherext.md"
    printf 'BACKEND, and `:34` maps it to an output name.\n' >> "$dir/otherext.md"

    # Both sides of the prose-distance boundary, driven through the environment
    # variable so the fixtures stay small and so the override itself is tested.
    # The padding carries no dot and no colon, so it is prose and nothing else.
    local near far
    near=$(printf 'padding %.0s' {1..8})     # 63 characters after the strip
    far=$(printf 'padding %.0s' {1..30})     # 239 characters after the strip
    printf '`src/Art.cpp` %s `:1337` is the cast.\n' "$near" > "$dir/near.md"
    printf '`src/Art.cpp` %s `:1337` is the cast.\n' "$far"  > "$dir/far.md"

    # A citation NAMED IN FULL into a file this tool cannot resolve upstream. It
    # used to pass in silence -- exit 0, no output -- because the scan only ever
    # matched cpp, h and irh. That made the hard error on the bare form useless
    # advice: the tool told the writer to name the file, and naming it turned
    # the error into nothing at all.
    printf 'The default is set at `build_macos.sh:34`.\n' > "$dir/named-local.md"

    # The same citation with a line number that cannot exist. Silence here is
    # the worst case of all, because nothing about it is right.
    printf 'The default is set at `build_macos.sh:99999`.\n' > "$dir/named-local-eof.md"

    # And the same disease on the UPSTREAM path, which is the one an outgoing PR
    # comment travels. `sed -n 99999p` printed an empty line and the run said
    # "Every citation resolves in upstream/master".
    printf 'The list walk is at `src/Display.cpp:99999`.\n' > "$dir/named-eof.md"

    # A file in neither tree. This one MUST stay a defect: there is nothing to
    # check it against, so the fallback is not an answer.
    printf 'The call sites are at `program.i:30782` in the generated script.\n' \
        > "$dir/nowhere.md"

    selftest_case "a resolving citation and its expectation" 0 "$dir/good.md" "$dir/good.expect"
    selftest_case "a link to a path that cannot exist"       1 "$dir/bad.md"
    selftest_case "a file named without a line number"       0 "$dir/adopt.md"
    selftest_case "a bare number with no file context"       1 "$dir/nocontext.md"
    selftest_case "a continuation into a non-upstream file"  3 "$dir/otherext.md"
    CITATION_FAR_CHARS=100 \
        selftest_case "a continuation inside the distance"   0 "$dir/near.md"
    CITATION_FAR_CHARS=100 \
        selftest_case "a continuation past the distance"     1 "$dir/far.md"
    selftest_case "a named citation only in the fallback"    3 "$dir/named-local.md"
    selftest_case "a named fallback citation past the end"   1 "$dir/named-local-eof.md"
    selftest_case "a named upstream citation past the end"   1 "$dir/named-eof.md"
    selftest_case "a citation into a file in neither tree"   1 "$dir/nowhere.md"

    # The bare and the named form of the SAME citation must agree. They did not:
    # the bare form was a hard error whose advice was to write the named form,
    # and the named form was silence. A rule that can be escaped by following
    # the tool's own advice is not a rule.
    local rc_bare rc_named
    printf 'See `build_macos.sh` -- the default is set at `:34`.\n' > "$dir/pair-bare.md"
    ( defects=0; unchecked=0; check_document "$dir/pair-bare.md" > "$dir/pair-bare.out" 2>&1; verdict )
    rc_bare=$?
    ( defects=0; unchecked=0; check_document "$dir/named-local.md" > /dev/null 2>&1; verdict )
    rc_named=$?
    if [ "$rc_bare" != "$rc_named" ]; then
        printf 'selftest FAIL: bare and named forms disagree -- bare=%s named=%s\n' \
            "$rc_bare" "$rc_named"
        sed 's/^/    | /' "$dir/pair-bare.out"
        selftest_failures=$((selftest_failures + 1))
    fi

    rm -rf "$dir"
    if [ "$selftest_failures" -eq 0 ]; then
        echo "selftest: pass -- 12 cases"
        return 0
    fi
    printf 'selftest: FAIL -- %d of 12 cases\n' "$selftest_failures"
    return 1
}

case "${1:-}" in
    --selftest) selftest; exit $? ;;
    "" ) echo "usage: $0 <document> [--expect <file>] | --selftest" >&2; exit 2 ;;
esac

doc=$1; shift
expect=""
while [ $# -gt 0 ]; do
    case "$1" in
        --expect) expect=${2:-}; shift 2 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

check_document "$doc" "$expect"
verdict
rc=$?

case "$rc" in
    1)
        printf '\n%d defect(s). Fix them before this goes anywhere public.\n' "$defects"
        [ "$unchecked" -gt 0 ] && printf \
            '%d citation(s) also went unchecked against %s (UNCHECKED above).\n' \
            "$unchecked" "$UPSTREAM_REF"
        ;;
    # Exit 3, not 0. The old wording -- "Every citation resolves in
    # upstream/master" -- was printed for documents in which dozens of citations
    # had never been looked at, and a claim of coverage the run did not have is
    # the exact thing this tool exists to stop a person doing. Non-zero forces a
    # gate to make a decision instead of inheriting a green tick.
    3)
        printf '\nNo defects, but %d citation(s) could NOT be checked against %s.\n' \
            "$unchecked" "$UPSTREAM_REF"
        printf 'Each is marked UNCHECKED above and was verified against %s instead.\n' "$FALLBACK_REF"
        printf 'That is fine for a document about this port. For anything going to\n'
        printf 'rmtew, every citation must resolve in %s -- exit 0 and nothing less.\n' "$UPSTREAM_REF"
        ;;
    *)
        printf '\nNo defects. Every citation resolves in %s and every evidence link is on %s.\n' \
            "$UPSTREAM_REF" "$ORIGIN_REF"
        ;;
esac
exit "$rc"
