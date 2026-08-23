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
#  2b. Every embedded image -- `![alt](path)` -- exists in FALLBACK_REF. An
#      embed names a file and nothing else, so existence is the whole check. A
#      README whose screenshot is not in the tree shows a broken image to every
#      reader, and nothing looked for that until 2026-08-23.
#   3. Every named `File.ext:NNNN` citation in the prose -- ANY extension, not
#      a list of favoured ones -- resolved to a unique path, range-checked
#      against that file's length, then printed with its content.
#   4. Every bare `:NNNN` continuation -- a line number written with no file in
#      front of it, which inherits the file named before it in the prose. The
#      inheritance rule is strict and is described at the check itself.
#
# WHAT IS NOT A CITATION. A GitHub link that names no path -- a repository root,
# a releases page, an issue, a pull request -- is not a citation and is not
# checked as one. It is printed and skipped. Until 2026-08-23 it was reported as
# a defect, so README.md failed its own gate on three correct links, one of them
# the download link a player follows. A binary file is the same idea from the
# other side: it exists or it does not, and it has no lines to cite. Neither
# rule is a softening, because neither one can make an unreadable citation pass:
# a blob link into OUR fork or into upstream naming a path that is not there
# still fails, an unknown URL shape still fails, and a line number written on a
# binary file still fails. A blob link into a THIRD-PARTY repository is a
# separate case with its own section below: it is unchecked, not a defect.
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
# WHICH TREE A DOCUMENT IS ABOUT -- THE PER-DOCUMENT DECLARATION
#
# Upstream-first is right for a document going to rmtew and wrong for a document
# describing this port's own engine. docs/ENGINE-MAP-CREATURE.md cites
# src/Display.cpp:1720. Our Display.cpp has 2230 lines and rmtew's has 1325, so
# the citation is correct and the tool called it a defect. On 2026-08-23 that
# accounted for 74 of the 112 defects reported across every tracked markdown
# file: 45 named citations past the end of the UPSTREAM file, and 29 bare
# continuations measured the same way. Every one of the 74 was right.
#
# So a document may declare, in itself, which tree it is written against. The
# declaration is one line, alone on the line, inside the first 20 lines:
#
#     <!-- citations: this-port -->
#
# An HTML comment renders as nothing, so it costs the reader no page. It lives
# in the document rather than in a list inside this script, because a list here
# goes stale the moment somebody renames a file, and because a reader who opens
# the document can see which tree its numbers are in.
#
# IT FAILS CLOSED. A document that declares nothing is resolved exactly as
# before: upstream first, fallback second. Nothing about the outgoing path
# changes unless a writer types the line.
#
# A declared document is resolved against FALLBACK_REF FIRST and UPSTREAM_REF
# second. Every run prints one `tree` line naming the order it used, so no
# reader can mistake a document checked against ours for one checked against
# rmtew's.
#
# THE DECLARATION IS NOT A SOFTENING, AND THREE RULES KEEP IT FROM BECOMING ONE.
#   * A number past the end of OUR file is still a defect. src/Annot.cpp is
#     1338 lines upstream and 1337 here, so `Annot.cpp:1338` passes undeclared
#     and fails declared. The selftest holds that case.
#   * A citation that resolves in NEITHER tree is still a defect. Declaring a
#     tree does not invent a file.
#   * A document under docs/outgoing/ MUST NOT declare it. That directory is
#     what goes to rmtew, where every citation must resolve in HIS tree. The
#     declaration there is a hard error naming the file, exit 2, not a silent
#     ignore -- a silent ignore would let a writer believe he had relaxed a gate
#     that in fact still held, or the reverse.
#
# The marker is matched as a WHOLE LINE and only in the first 20 lines. The
# whole-line match is so that prose quoting the marker inside backticks does not
# declare the document by accident. The 20-line window is so the declaration
# stays where a reader meets it. A marker found BELOW line 20 is a hard error
# telling the writer to move it up, because honouring it silently and ignoring
# it silently are both worse than saying so.
#
# A LINK INTO A THIRD-PARTY REPOSITORY
#
# `https://github.com/gastownhall/beads/blob/main/docs/SYNC_CONCEPTS.md` is a
# blob link into a repository this clone has no remote for and never will. It
# works in a browser. Calling it "points at neither tree" says it is broken,
# which is false, and four such links were reported that way on 2026-08-23.
# A blob/tree/raw/blame link into a repository that is neither ORIGIN_HOST nor
# UPSTREAM_HOST is now reported as a link this tool CANNOT CHECK, and counted
# the way an UNCHECKED citation is counted -- visible, non-zero, never a defect.
#
# That is narrow on purpose. The catch-all still fails a URL shape this tool has
# never been taught, and a blob link into OUR fork or into upstream naming a
# path that is not there still fails. Both are in the selftest.
#
# Exit status:
#   0  every citation was checked against the document's PRIMARY tree and every
#      one resolved
#   1  a defect was found
#   2  the invocation was wrong, or a document declared a tree it may not
#      declare
#   3  no defects, but N citations could only be checked against the SECONDARY
#      tree, or are links into a repository this clone has no remote for.
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

# The order the CURRENT document is resolved in. Set once per document by
# check_document, from the declaration described in the header. The defaults are
# the undeclared behaviour, so a caller that never sets them gets exactly what
# this tool did before 2026-08-23.
PRIMARY_REF=$UPSTREAM_REF
SECONDARY_REF=$FALLBACK_REF

# The declaration itself. One constant, used by the reader, by the error
# messages and by the selftest, so the three can never drift apart.
OURS_MARK='<!-- citations: this-port -->'
OURS_MARK_LINES=20

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || {
    echo "not inside a git repository" >&2; exit 2; }

# The selftest needs to re-run this script as a whole, not just call
# check_document. The summary line -- "N defect(s)" -- is printed by the
# dispatcher at the bottom of the file, and on 2026-08-23 the summary was the
# thing under test: it said 4 for a run that printed 6. A case that calls
# check_document directly never sees that line and cannot catch it. Resolved to
# an absolute path so the re-run does not depend on the caller's directory.
SELF=$(cd -- "$(dirname -- "$0")" 2>/dev/null && pwd -P)/$(basename -- "$0")

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
#
# PRIMARY_REF and SECONDARY_REF, not UPSTREAM_REF and FALLBACK_REF. The order is
# still the whole safety argument -- a basename the PRIMARY tree carries is
# always measured against the primary tree -- but which tree is primary is now
# the document's own declaration. See the header.
resolve_basename() {
    local base=$1 hit
    if hit=$(resolve_in_ref "$PRIMARY_REF" "$base"); then
        printf '%s\t%s\n' "$PRIMARY_REF" "$hit"; return 0
    fi
    if hit=$(resolve_in_ref "$SECONDARY_REF" "$base"); then
        printf '%s\t%s\n' "$SECONDARY_REF" "$hit"; return 0
    fi
    return 1
}

# Does this document sit in docs/outgoing/? Answered from the ABSOLUTE directory
# so that `docs/outgoing/pr43.md`, `./docs/outgoing/pr43.md` and a scratch copy
# under /tmp/x/docs/outgoing all give the same answer. A relative spelling that
# slipped past this test would let an outgoing draft declare itself ours.
in_outgoing() {
    local dir
    dir=$(cd -- "$(dirname -- "$1")" 2>/dev/null && pwd -P) || return 1
    case "$dir" in */docs/outgoing) return 0 ;; esac
    return 1
}

# Read the per-document tree declaration and set PRIMARY_REF/SECONDARY_REF.
# Prints the `tree` line, which is the record of which tree answered.
read_declaration() {
    local doc=$1
    PRIMARY_REF=$UPSTREAM_REF
    SECONDARY_REF=$FALLBACK_REF
    if head -n "$OURS_MARK_LINES" "$doc" | grep -qxF "$OURS_MARK"; then
        if in_outgoing "$doc"; then
            # Hard error, not a silent ignore. docs/outgoing/ is what goes to
            # rmtew; a citation there that resolves only in our tree is exactly
            # the mistake this whole file exists to stop.
            printf 'cannot check %s: it is in docs/outgoing/ and carries `%s`.\n' \
                "$doc" "$OURS_MARK" >&2
            printf 'Everything in docs/outgoing/ goes to rmtew, so every citation in it\n' >&2
            printf 'must resolve in %s. Delete the declaration line.\n' "$UPSTREAM_REF" >&2
            exit 2
        fi
        PRIMARY_REF=$FALLBACK_REF
        SECONDARY_REF=$UPSTREAM_REF
        printf 'tree     %s declares `%s` -- resolved against %s first, %s second\n' \
            "$doc" "$OURS_MARK" "$PRIMARY_REF" "$SECONDARY_REF"
        return 0
    fi
    # Found, but too far down to be the header a reader meets. Saying nothing
    # would be a silent miss either way round, so it is an error with an
    # instruction attached.
    if grep -qxF "$OURS_MARK" "$doc"; then
        printf 'cannot check %s: `%s` appears below line %s.\n' \
            "$doc" "$OURS_MARK" "$OURS_MARK_LINES" >&2
        printf 'The declaration must be in the first %s lines, where a reader meets it.\n' \
            "$OURS_MARK_LINES" >&2
        exit 2
    fi
    printf 'tree     %s declares nothing -- resolved against %s first, %s second\n' \
        "$doc" "$PRIMARY_REF" "$SECONDARY_REF"
}

line_at_ref() { git -C "$ROOT" show "$1:$2" 2>/dev/null | sed -n "${3}p"; }
lines_in_ref() { git -C "$ROOT" show "$1:$2" 2>/dev/null | grep -c ''; }

# Is the blob at <ref>:<path> binary? The test is git's own: a NUL byte inside
# the first 8000 bytes. The tool needs this because a document may name a file
# that has no lines at all. On 2026-08-18 README.md embedded
# docs/media/incursion-macos.png, the checker measured the PNG like source and
# died decoding it, and the traceback was then counted as a defect in the
# README. The README was correct.
#
# Two reads and not one: the count of bytes and the count of bytes with NUL
# removed. They differ exactly when a NUL is present. This runs only for a
# citation that carries a line number, which is rare, so the second read costs
# nothing that anyone can measure.
blob_is_binary() {
    local bytes stripped
    bytes=$(git -C "$ROOT" show "$1:$2" 2>/dev/null | head -c 8000 | wc -c)
    stripped=$(git -C "$ROOT" show "$1:$2" 2>/dev/null | head -c 8000 | LC_ALL=C tr -d '\000' | wc -c)
    [ "$bytes" != "$stripped" ]
}

# GitHub URL shapes that are not file citations at all.
#
# A repository root, a releases page, an issue, a pull request or a comparison
# names no path and no line. There is nothing in it for this tool to resolve, so
# raising it as "link points at neither tree" says something false about a link
# that works. That happened on 2026-08-18 to three correct links in README.md,
# one of them the download link a player follows.
#
# The list is deliberately a list of KNOWN shapes. It does not say "anything
# without /blob/ passes", because the catch-all still has a job: a blob or tree
# link into a repository this clone cannot resolve is a real defect and must
# stay one. Returns 0 when the link names no file.
non_file_link() {
    case "$1" in
        */blob/*|*/tree/*|*/raw/*|*/blame/*) return 1 ;;
    esac
    case "$1" in
        */releases|*/releases/*|*/issues|*/issues/*|*/pull/*|*/pulls|\
        */discussions|*/discussions/*|*/compare/*|*/commit/*|*/commits|*/commits/*|\
        */tags|*/branches|*/wiki|*/wiki/*|*/actions|*/actions/*|*/graphs/*)
            return 0 ;;
    esac
    # What is left is a bare owner page or a bare owner/repo root: at most two
    # path segments. Three or more segments is a shape this tool has never been
    # taught, and an unknown shape must fail rather than pass.
    case "$1" in
        */*/*) return 1 ;;
        *)     return 0 ;;
    esac
}

# A file link into a repository that is NEITHER our fork nor upstream.
#
# `https://github.com/gastownhall/beads/blob/main/docs/SYNC_CONCEPTS.md` is the
# case. It names a path, so it is a citation, and this clone has no remote that
# could resolve it, so the tool cannot check it and never will. Until 2026-08-23
# it was reported as "link points at neither tree", which reads as a broken link
# about four links that work. It is now reported as unchecked.
#
# The caller has already matched our two hosts, so this test only has to see a
# file-shaped path. It stays narrow: no /blob/, /tree/, /raw/ or /blame/ and the
# link falls through to the catch-all, which still fails an unknown shape.
third_party_file_link() {
    case "$1" in
        "$UPSTREAM_HOST"/*|"$ORIGIN_HOST"/*) return 1 ;;
    esac
    case "$1" in
        */blob/*|*/tree/*|*/raw/*|*/blame/*) return 0 ;;
    esac
    return 1
}

check_document() {
    local doc=$1 expect=${2:-} url_ref py_rc
    [ -r "$doc" ] || { echo "cannot read $doc" >&2; exit 2; }

    # Which tree this document is about, decided by the document. Printed, never
    # assumed. See the header for why the default is upstream-first.
    read_declaration "$doc"

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
        # A trailing slash is the same address with one more character in it.
        # Without this strip, `.../beads/` had three segments and looked like a
        # shape the tool did not know.
        path=${path%/}
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
                # Not silence. The tool says what it decided about every link it
                # read, because a link it never mentions is a link nobody can
                # tell it skipped.
                if non_file_link "$path"; then
                    printf 'link     %s  (names no file -- nothing to resolve)\n' "$url"
                elif third_party_file_link "$path"; then
                    # Counted like an UNCHECKED citation and worded like one, so
                    # the run stays non-zero and nobody reads it as a pass.
                    printf 'UNCHECKED %s  (third-party repository -- this clone has no remote for it)\n' "$url"
                    unchecked=$((unchecked + 1))
                else
                    fail "link points at neither tree: $url"
                fi
                ;;
        esac
    done < <(grep -oE 'https://github\.com/[A-Za-z0-9_.@:/~-]+(#L[0-9]+(-L[0-9]+)?)?' "$doc" | sort -u)

    # 2b. Embedded images -- `![alt](path)`.
    #
    # An embed is a citation of a different kind: it names a file, and the only
    # thing that can be true or false about a binary file is whether it is
    # there. README.md:16 embeds docs/media/incursion-macos.png, and a README
    # whose screenshot is not in the tree shows every reader a broken image.
    # Nothing checked this before 2026-08-23; the path went to the source-
    # citation scan instead, which tried to count the lines in a PNG.
    #
    # FALLBACK_REF and not UPSTREAM_REF. The screenshots belong to this port and
    # rmtew's tree has never carried one, so upstream is the wrong tree to ask.
    #
    # The path is read as repo-relative first, then relative to the directory
    # the document sits in, because both spellings are correct markdown.
    local img docdir=""
    if [ -d "$ROOT" ]; then
        docdir=$(cd -- "$(dirname -- "$doc")" 2>/dev/null && pwd -P)
        case "$docdir" in
            "$ROOT")   docdir="" ;;
            "$ROOT"/*) docdir=${docdir#"$ROOT"/} ;;
            *)         docdir="" ;;   # the document is outside the repository
        esac
    fi
    while read -r img; do
        [ -n "$img" ] || continue
        img=${img%%#*}          # `path#anchor`
        img=${img%% *}          # `path "title"`
        [ -n "$img" ] || continue
        case "$img" in
            http*|/*|'<'*) continue ;;   # remote or absolute: not ours to resolve
        esac
        if path_in_ref "$FALLBACK_REF" "$img"; then
            printf 'asset    %s  present at %s\n' "$img" "$FALLBACK_REF"
        elif [ -n "$docdir" ] && path_in_ref "$FALLBACK_REF" "$docdir/$img"; then
            printf 'asset    %s/%s  present at %s\n' "$docdir" "$img" "$FALLBACK_REF"
        else
            fail "embedded image $img is not in $FALLBACK_REF -- the reader sees a broken image"
        fi
    done < <(grep -oE '!\[[^]]*\]\([^)]+\)' "$doc" | sed -E 's/^!\[[^]]*\]\(//; s/\)$//' | sort -u)

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
            fail "cannot resolve '$base' to one file in $PRIMARY_REF or $SECONDARY_REF (cited as $cite)"
            continue
        fi
        ref=${hit%%$'\t'*}
        full=${hit#*$'\t'}
        # A line number on a binary file is nonsense, and it must be reported as
        # nonsense rather than measured. `grep -c` will happily count "lines" in
        # a PNG, so `incursion-macos.png:12` would otherwise resolve and print a
        # line of binary as though it were evidence.
        if blob_is_binary "$ref" "$full"; then
            fail "$cite names a line in a binary file ($full in $ref), which has no lines"
            continue
        fi
        len=$(lines_in_ref "$ref" "$full")
        if [ "$num" -gt "$len" ] || [ "$num" -lt 1 ]; then
            fail "$cite is past the end of $full, which has $len lines in $ref"
            continue
        fi
        printf '%s:%s\t%s\n' "$full" "$num" "$(line_at_ref "$ref" "$full" "$num")" >> "$resolved"
        if [ "$ref" = "$PRIMARY_REF" ]; then
            printf 'bare     %s:%s  %s\n' "$full" "$num" "$(line_at_ref "$ref" "$full" "$num")"
        else
            printf 'UNCHECKED %s:%s  (only in %s, not in %s)  %s\n' \
                "$full" "$num" "$ref" "$PRIMARY_REF" "$(line_at_ref "$ref" "$full" "$num")"
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
    #
    # THE COUNT COMES BACK BY FILE, NOT BY EXIT STATUS. It used to come back as
    # `|| defects=$((defects + 1))`, which added exactly ONE however many
    # defects the block had printed. On 2026-08-23 docs/PORT-STATUS.md printed
    # six DEFECT lines and the summary claimed four. A tool that prints a number
    # it did not measure is the same fault this file exists to stop, and the run
    # that removed the hardcoded case count from the selftest summary had
    # already applied that rule one screen further down.
    # PRIMARY_REF and SECONDARY_REF, in that order: the block resolves a
    # basename against the first tree that carries it, and the document's own
    # declaration decides which tree is first. Undeclared, these are upstream
    # and the fallback, which is what they always were.
    python3 - "$doc" "$PRIMARY_REF" "$ROOT" "$SECONDARY_REF" "$CACHE_DIR" \
        <<'PYCHECK'
import os, re, subprocess, sys

# `primary` is the tree this document is written against and `secondary` is the
# other one. Undeclared that is upstream then ours; a document carrying
# `<!-- citations: this-port -->` swaps them. Nothing else in this block cares
# which is which, which is why the swap is one argument and not a branch.
doc, primary, root, secondary, cache = sys.argv[1:6]

# errors='replace', here and everywhere else in this block. Strict decoding was
# the default and it ended a whole run in a traceback on 2026-08-18. The tool
# reports on citations; a traceback reports on nothing, and the run that printed
# it went on to count its own crash as a defect in the document.
text = open(doc, encoding='utf-8', errors='replace').read()

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

# The primary tree first, then the secondary. The order is the whole safety
# argument: a basename the primary tree carries is ALWAYS measured against the
# primary tree, so the secondary cannot quietly bless a line number the primary
# does not have. The secondary is reached only for a file the primary does not
# carry at all.
#
# `unresolved` says WHY, because the two reasons need opposite fixes. A name no
# tree carries needs a different name. A name several files carry -- Options.Dat
# is both `Options.Dat` and `tools/gates/Options.Dat` -- needs a path, and
# telling that writer to "name a file that is committed" would be nonsense,
# since the file is committed twice over.
#
# The fourth field of a length is `binary`. A binary file has no lines, so the
# only question this tool can answer about one is whether the tree carries it.
lengths, unresolved = {}, {}

# BYTES, never text. text=True decodes as UTF-8 and raises on the first byte
# that is not, and README.md embeds a PNG whose first byte is 0x89. Each caller
# below decides what to do with the bytes it gets.
def blob(r, path):
    return subprocess.run(['git', '-C', root, 'show', f'{r}:{path}'],
                          capture_output=True).stdout

# git's own test for a binary file: a NUL byte in the first 8000 bytes.
def is_binary(data):
    return b'\x00' in data[:8000]

def decode(data):
    return data.decode('utf-8', 'replace')

def length_of(base):
    if base not in lengths:
        lengths[base] = (None, None, 0, False)
        unresolved[base] = (f"is in neither {primary} nor {secondary}",
                            "Name a file that is committed, or cite the generator input.")
        for r in (primary, secondary):
            hits = tree(r).get(base, [])
            if len(hits) == 1:
                data = blob(r, hits[0])
                if is_binary(data):
                    lengths[base] = (r, hits[0], 0, True)
                else:
                    lengths[base] = (r, hits[0], decode(data).count('\n'), False)
                unresolved[base] = None
                break
            if len(hits) > 1:
                unresolved[base] = (f"is the name of {len(hits)} different files in {r}",
                                    "Write the path, not just the file name.")
    return lengths[base]

def line_of(r, path, num):
    body = decode(blob(r, path)).splitlines()
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
        r, path, n, binary = length_of(name)
        if path is not None and binary:
            # The file is there, and that is the whole of what a binary file can
            # be asked. Existence is a real check and it can still fail: a
            # missing screenshot is caught by the embed check further up.
            #
            # A LINE number on it is still a defect -- `incursion-macos.png:12`
            # names a line in a PNG -- and check 3 above reports it, with the
            # full path. This block does not report it a second time. That is
            # the division of labour the two scans already had: check 3 owns
            # every NAMED citation's range check, this block owns the bare
            # continuations. Reporting here as well would count one bad citation
            # twice, and it would hide a break in check 3 from the selftest case
            # that guards it.
            #
            # The name ends the previous file's claim on the numbers that
            # follow, for the same reason any other file name does: a bare
            # `:NNN` after an embedded screenshot has no file to be checked
            # against.
            ctx = None
            dead = (f"the last file named before it is {name}, a binary file with no lines",
                    "Name the source file this number is in.")
            continue
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
    # `binary` is discarded here on purpose: a binary name never becomes the
    # context, so `base` is always a text file at this point.
    r, path, n, _ = length_of(base)
    if num > n:
        # THE MESSAGE MUST NAME THE TREE IT MEASURED AGAINST.
        #
        # It did not, and the omission made the message a false diagnosis. On
        # 2026-08-23 twenty-nine bare continuations in the ENGINE-* documents
        # read "bare ':1739' follows Display.cpp, which has only 1325 lines --
        # it inherited the wrong file". Nothing had inherited anything. 1325 is
        # rmtew's Display.cpp; ours has 2230 lines and the citation was right.
        # A reader sent to hunt for a paragraph that stole a file name cannot
        # find one, and concludes the document is wrong when the tool was.
        # Naming the tree lets him tell the two apart in one glance.
        #
        # Two sentences after that, because they send the writer to two
        # different fixes. Where the number INHERITED its file, the file may be
        # the thing that is wrong and the wording still says so -- that
        # diagnosis is the whole point of this check. Where the prose named the
        # file outright, with no line number, nothing was inherited at all: the
        # writer chose that file and the number is simply past the end of it.
        why = ("the number is past the end of the file the prose names"
               if scoped else
               f"it inherited the wrong file, or it was written against a tree "
               f"that is not {r}")
        print(f"DEFECT  bare ':{num}' follows {base}, which has only {n} lines "
              f"in {r} -- {why}")
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
    if r != primary:
        # Checked, and checked correctly -- but against a tree the reader of an
        # outgoing document cannot see. Printed and counted, never silent.
        print(f"UNCHECKED {path}:{num}  (only in {r}, not in {primary})  "
              f"{line_of(r, path, num)}")
        unchecked += 1
    cited.setdefault(base, set()).add(num)
    ctx = [base, end, scoped]

# Hand the count back through a file. The block's stdout is the report the user
# reads, so it cannot also be a return channel, and an exit status carries one
# number badly.
open(os.path.join(cache, 'unchecked'), 'w').write(str(unchecked))
open(os.path.join(cache, 'defects'), 'w').write(str(bad))
sys.exit(1 if bad else 0)
PYCHECK
    # `py_rc=$?` and nothing before it. `local py_rc` on its own line SUCCEEDS,
    # which sets `$?` to 0, so the declaration must live with the other locals
    # at the top of the function or the crash below can never be seen. That
    # mistake was made and caught on 2026-08-23, in the very commit that added
    # this branch: a deliberately crashed block reported no crash.
    py_rc=$?
    if [ -s "$CACHE_DIR/defects" ]; then
        defects=$((defects + $(cat "$CACHE_DIR/defects")))
        rm -f "$CACHE_DIR/defects"
    elif [ "$py_rc" != 0 ]; then
        # The block died before it could say how many it found. Silence here
        # would turn a crash into "no defects", so the crash itself is reported
        # as one -- through `fail`, so the line count and the summary still
        # agree, which a bare increment would have broken.
        fail "the bare-continuation check did not finish (python exit $py_rc)"
    fi
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
            # PRIMARY_REF: an expectation pins the CONTENT of a line, so it
            # must read the same tree the address check read. Undeclared that
            # is UPSTREAM_REF, exactly as before.
            got=$(git -C "$ROOT" show "$PRIMARY_REF:${key%%:*}" 2>/dev/null | sed -n "${key##*:}p")
            case "$got" in
                *"$sub"*) printf 'expect   %s  ok\n' "$key" ;;
                *)        fail "$key does not contain '$sub' -- it has: $got" ;;
            esac
        done < "$expect"
    fi

    rm -f "$resolved"
}

selftest_failures=0

# The number of cases is counted and not written down. It was written down, as
# the literal 12 in two printf strings, and adding a case meant remembering to
# edit both. A count that has to be maintained by hand eventually lies, and this
# tool has no business printing a number it did not measure.
selftest_total=0

# Run one fixture and compare the run's verdict with the wanted one. The verdict
# is the real exit path -- "did $defects end at zero" -- and not a grep for the
# word DEFECT, because the thing a caller depends on is the exit status. A test
# that watches the message instead of the status passes a tool that prints a
# complaint and then exits 0, which is the failure mode this file is here to
# prevent in documents.
selftest_case() {
    local label=$1 want=$2 doc=$3 exp=${4:-} got
    selftest_total=$((selftest_total + 1))
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

    # THE FALSE-NEGATIVE HALF of the same 2026-08-18 sentence, and the half the
    # fixture above cannot see. `adopt.md` wants exit 0, so an implementation
    # that named the file, set the context and then SKIPPED every bare number
    # under it would pass that case while checking nothing at all. Silence and
    # correctness are the same colour there. This fixture wants exit 1 instead,
    # so silence fails it.
    #
    # The numbers are chosen so that only the right file gives the right answer.
    # src/Art.cpp runs to 1578 lines and inc/Map.h stops at 981, so `:1000` is
    # comfortably inside the STALE file and past the end of the one the prose
    # actually names. The gap from `:900` is 100 lines, inside CITATION_FAR, so
    # the distance heuristic cannot catch it either. Before 2026-08-18 a run on
    # this shape printed no defects: the tool measured the number against a file
    # the sentence never mentioned and reported that as a check. That is the
    # defect inc-loa.6 was filed for, and it is the one nothing was watching.
    printf 'The cast at `src/Art.cpp:900` was dropped. The rest are in `inc/Map.h`\n' \
        > "$dir/stale-short.md"
    printf '(`:1000`).\n' >> "$dir/stale-short.md"

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

    # A document that embeds a binary asset. README.md:16 does exactly this. The
    # tool read the PNG as UTF-8, died on byte 0x89, printed the traceback and
    # counted it as a defect in the document. The document was correct. A binary
    # file has no lines, so the only question the tool can ask about it is
    # whether it is in the tree.
    printf '![iNCURSION on macOS](docs/media/incursion-macos.png)\n' > "$dir/binary.md"

    # The same asset with a line number on it. Existence is all that can be
    # checked about a PNG, so a LINE in one is nonsense and stays a defect.
    # Silence here would trade one wrong answer for another.
    printf 'The shot is at `docs/media/incursion-macos.png:12`.\n' > "$dir/binary-line.md"

    # An embedded image that is NOT in the tree. This is the failure the
    # existence check keeps alive: the reader of the README sees a broken image.
    printf '![missing](docs/media/no-such-screenshot.png)\n' > "$dir/missing-asset.md"

    # A repository root URL and a releases URL. Neither names a path or a line,
    # so neither is a citation and neither can be resolved as one. Both were
    # reported as "link points at neither tree" on 2026-08-18, and one of them
    # was README.md's own download link -- the link a player follows. A gate
    # that is red about the download link teaches everyone to ignore the gate.
    printf 'Download it from https://github.com/%s/releases, and the tracker\n' \
        "$ORIGIN_HOST" > "$dir/nonfile-link.md"
    printf 'is https://github.com/gastownhall/beads.\n' >> "$dir/nonfile-link.md"

    # A blob link into a repository that is neither ours nor upstream. This
    # clone has no remote for it and never will, so the tool cannot check it.
    # It wanted exit 1 until 2026-08-23, which said "broken link" about four
    # links that work -- the beads documentation linked from AGENTS.md,
    # CLAUDE.md and .beads/README.md. It now wants 3: unchecked, printed,
    # non-zero, and not a defect.
    printf 'See https://github.com/nobody/nothing/blob/master/src/Art.cpp#L1\n' \
        > "$dir/unknown-blob.md"

    # The same shape in the tree form, which is what .beads/README.md carries.
    printf 'See https://github.com/steveyegge/beads/tree/main/docs\n' \
        > "$dir/thirdparty-tree.md"

    # THE GUARD ON THE TWO CASES ABOVE. Skipping a link shape that names no
    # file, and declining to check a repository we cannot reach, must never
    # become skipping a link this tool COULD have read. A URL with three or more
    # path segments and no /blob/, /tree/, /raw/ or /blame/ in it is a shape
    # this tool has never been taught, and an unknown shape stays a defect.
    printf 'See https://github.com/foo/bar/baz/qux\n' > "$dir/malformed-link.md"

    # A blob link into OUR OWN fork naming a path that is not there. The
    # third-party rule must not reach this: we can resolve origin, so we must.
    printf 'See https://github.com/%s/blob/master/src/NoSuchFile.cpp\n' \
        "$ORIGIN_HOST" > "$dir/ours-blob-missing.md"

    # THE PER-DOCUMENT TREE DECLARATION.
    #
    # src/Display.cpp:1720 is a real line of OUR Display.cpp, which has 2230
    # lines, and is 395 lines past the end of rmtew's, which has 1325. On
    # 2026-08-23 this shape accounted for 74 of the 112 defects reported across
    # every tracked markdown file, and every one of the 74 was right.
    printf '%s\n' "$OURS_MARK" > "$dir/declared.md"
    printf 'The status line is drawn at `src/Display.cpp:1720`.\n' >> "$dir/declared.md"

    # FAIL CLOSED. The same body with no declaration must still be a defect,
    # because that is the outgoing behaviour and nothing about it may change by
    # accident. If this case ever goes green, the declaration has stopped being
    # a declaration and has become the default.
    printf 'The status line is drawn at `src/Display.cpp:1720`.\n' \
        > "$dir/undeclared.md"

    # THE DECLARATION IS NOT A SOFTENING, PART ONE. A number past the end of OUR
    # file is still a defect. src/Annot.cpp is the one file in this tree that is
    # LONGER upstream -- 1338 lines there, 1337 here -- so `Annot.cpp:1338`
    # passes undeclared and must fail declared. That asymmetry is what makes
    # this case able to go red; every other file would fail both ways and prove
    # nothing about the declaration.
    printf '%s\n' "$OURS_MARK" > "$dir/declared-past-ours.md"
    printf 'The last line is `src/Annot.cpp:1338`.\n' >> "$dir/declared-past-ours.md"

    # THE DECLARATION IS NOT A SOFTENING, PART TWO. Declaring a tree does not
    # invent a file. `program.i` is generated and committed nowhere, so it is
    # unresolvable in both trees and stays a defect.
    printf '%s\n' "$OURS_MARK" > "$dir/declared-nowhere.md"
    printf 'The call sites are at `program.i:30782`.\n' >> "$dir/declared-nowhere.md"

    # docs/outgoing/ MUST NOT DECLARE IT. That directory is what goes to rmtew.
    # A silent ignore would leave a writer believing he had changed which tree
    # his draft was measured against when he had not, so it is a hard error,
    # exit 2, naming the file.
    mkdir -p "$dir/docs/outgoing"
    printf '%s\n' "$OURS_MARK" > "$dir/docs/outgoing/draft.md"
    printf 'The status line is drawn at `src/Display.cpp:56`.\n' \
        >> "$dir/docs/outgoing/draft.md"

    # A declaration too far down to be the header a reader meets. Honouring it
    # silently and ignoring it silently are both worse than saying so, so this
    # is a hard error with an instruction attached.
    printf 'padding\n%.0s' {1..25} > "$dir/declared-late.md"
    printf '%s\n' "$OURS_MARK" >> "$dir/declared-late.md"
    printf 'The status line is drawn at `src/Display.cpp:1720`.\n' \
        >> "$dir/declared-late.md"

    selftest_case "a resolving citation and its expectation" 0 "$dir/good.md" "$dir/good.expect"
    selftest_case "a link to a path that cannot exist"       1 "$dir/bad.md"
    selftest_case "a file named without a line number"       0 "$dir/adopt.md"
    selftest_case "a named file shorter than the stale one"  1 "$dir/stale-short.md"
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
    selftest_case "an embedded binary asset"                 0 "$dir/binary.md"
    selftest_case "a line number on a binary file"           1 "$dir/binary-line.md"
    selftest_case "an embedded image not in the tree"        1 "$dir/missing-asset.md"
    selftest_case "a repository root and a releases URL"     0 "$dir/nonfile-link.md"
    selftest_case "a blob link into a third-party repository" 3 "$dir/unknown-blob.md"
    selftest_case "a tree link into a third-party repository" 3 "$dir/thirdparty-tree.md"
    selftest_case "a URL shape the tool has never been taught" 1 "$dir/malformed-link.md"
    selftest_case "a blob into our fork with no such path"   1 "$dir/ours-blob-missing.md"
    selftest_case "a document declaring this port's tree"    0 "$dir/declared.md"
    selftest_case "the same document declaring nothing"      1 "$dir/undeclared.md"
    selftest_case "a declared document past the end of ours" 1 "$dir/declared-past-ours.md"
    selftest_case "a declared document citing no tree's file" 1 "$dir/declared-nowhere.md"
    selftest_case "a declaration inside docs/outgoing"       2 "$dir/docs/outgoing/draft.md"
    selftest_case "a declaration below the header"           2 "$dir/declared-late.md"

    # The bare and the named form of the SAME citation must agree. They did not:
    # the bare form was a hard error whose advice was to write the named form,
    # and the named form was silence. A rule that can be escaped by following
    # the tool's own advice is not a rule.
    local rc_bare rc_named
    selftest_total=$((selftest_total + 1))
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

    # THE OVER-LENGTH MESSAGE MUST NAME THE TREE IT MEASURED AGAINST.
    #
    # It did not, and the omission turned the message into a false diagnosis:
    # "bare ':1739' follows Display.cpp, which has only 1325 lines -- it
    # inherited the wrong file". Nothing had inherited anything. 1325 is
    # rmtew's file; ours has 2230 lines and the citation was right. Twenty-nine
    # bare continuations read that way on 2026-08-23. This case watches the
    # WORDS and not the exit status, because the exit status was already 1 and
    # was already correct -- the defect was in what the tool told the reader.
    local msg
    selftest_total=$((selftest_total + 1))
    printf 'The walk is at `src/Display.cpp:1300`, and `:1739` follows it.\n' \
        > "$dir/whichtree.md"
    "$SELF" "$dir/whichtree.md" > "$dir/whichtree.out" 2>&1
    msg=$(grep '^DEFECT  bare' "$dir/whichtree.out")
    case "$msg" in
        *"only 1325 lines in $UPSTREAM_REF"*) ;;
        *)
            printf 'selftest FAIL: the over-length message does not name the tree it measured\n'
            sed 's/^/    | /' "$dir/whichtree.out"
            selftest_failures=$((selftest_failures + 1))
            ;;
    esac

    # EVERY RUN MUST SAY WHICH TREE IT READ. A reader who cannot tell a document
    # checked against ours from one checked against rmtew's has no way to know
    # what a green run means, and the declaration above makes the two possible
    # in the same sweep. The line is printed for a declared document and for an
    # undeclared one, because silence on the default is the same gap.
    local decl_line undecl_line
    selftest_total=$((selftest_total + 1))
    decl_line=$(grep -c "^tree .*declares .* $FALLBACK_REF first" "$dir/declared.md.out")
    undecl_line=$(grep -c "^tree .*declares nothing -- resolved against $UPSTREAM_REF first" \
        "$dir/undeclared.md.out")
    if [ "$decl_line" != 1 ] || [ "$undecl_line" != 1 ]; then
        printf 'selftest FAIL: the run does not name the tree it read -- declared=%s undeclared=%s\n' \
            "$decl_line" "$undecl_line"
        sed 's/^/    | /' "$dir/declared.md.out" "$dir/undeclared.md.out"
        selftest_failures=$((selftest_failures + 1))
    fi

    # THE SUMMARY MUST EQUAL WHAT THE RUN PRINTED. It did not. The embedded
    # python block reports every bare-number defect it finds, but the shell
    # collected its verdict through `|| defects=$((defects + 1))`, which adds
    # exactly ONE however many the block printed. So on 2026-08-23
    # docs/PORT-STATUS.md printed six DEFECT lines and the summary claimed four.
    # This tool has no business printing a number it did not measure -- the same
    # rule that took the hardcoded case count out of the summary above.
    #
    # The fixture needs TWO python-side defects and no shell-side ones, because
    # one of each would have agreed by accident. Two bare numbers with no file
    # named anywhere before them are both lost, and nothing else in the document
    # is a citation at all.
    local printed claimed
    selftest_total=$((selftest_total + 1))
    printf 'The loop at `:4161` reads past the end, and `:99` does too.\n' \
        > "$dir/count.md"
    "$SELF" "$dir/count.md" > "$dir/count.out" 2>&1
    printed=$(grep -c '^DEFECT' "$dir/count.out")
    claimed=$(sed -n 's/^\([0-9][0-9]*\) defect(s).*/\1/p' "$dir/count.out")
    if [ "$printed" -lt 2 ] || [ "$printed" != "$claimed" ]; then
        printf 'selftest FAIL: the summary count is not the count printed -- %s DEFECT lines, summary says %s\n' \
            "$printed" "${claimed:-nothing}"
        sed 's/^/    | /' "$dir/count.out"
        selftest_failures=$((selftest_failures + 1))
    fi

    rm -rf "$dir"
    if [ "$selftest_failures" -eq 0 ]; then
        printf 'selftest: pass -- %d cases\n' "$selftest_total"
        return 0
    fi
    printf 'selftest: FAIL -- %d of %d cases\n' "$selftest_failures" "$selftest_total"
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
            "$unchecked" "$PRIMARY_REF"
        ;;
    # Exit 3, not 0. The old wording -- "Every citation resolves in
    # upstream/master" -- was printed for documents in which dozens of citations
    # had never been looked at, and a claim of coverage the run did not have is
    # the exact thing this tool exists to stop a person doing. Non-zero forces a
    # gate to make a decision instead of inheriting a green tick.
    3)
        printf '\nNo defects, but %d citation(s) could NOT be checked against %s.\n' \
            "$unchecked" "$PRIMARY_REF"
        printf 'Each is marked UNCHECKED above and was verified against %s instead,\n' "$SECONDARY_REF"
        printf 'or is a link into a repository this clone has no remote for.\n'
        printf 'That is fine for a document about this port. For anything going to\n'
        printf 'rmtew, every citation must resolve in %s -- exit 0 and nothing less.\n' "$UPSTREAM_REF"
        ;;
    *)
        # PRIMARY_REF and not UPSTREAM_REF. Printing "resolves in upstream/master"
        # about a document resolved against HEAD would be a claim of coverage
        # the run does not have -- the exact fault the exit-3 wording above was
        # rewritten for on 2026-08-18.
        printf '\nNo defects. Every citation resolves in %s and every evidence link is on %s.\n' \
            "$PRIMARY_REF" "$ORIGIN_REF"
        ;;
esac
exit "$rc"
