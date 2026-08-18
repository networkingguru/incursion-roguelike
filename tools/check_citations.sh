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
#   3. Every bare `File.ext:NNNN` citation in the prose -- resolved to a unique
#      path under src/, inc/ or lib/, then printed with its content.
#   4. With --expect, each `path:line<TAB>substring` line in the expectations
#      file must match the resolved content, and a mismatch fails the run.
#
# WHAT IT CANNOT CHECK. Whether the sentence around the citation is true. Use
# the expectations file for the claims that matter, and read the rest.
#
# Exit status: 0 all good, 1 a defect was found, 2 the invocation was wrong.

set -uo pipefail

UPSTREAM_REF=${UPSTREAM_REF:-upstream/master}
ORIGIN_REF=${ORIGIN_REF:-origin/master}
UPSTREAM_HOST=${UPSTREAM_HOST:-rmtew/incursion-roguelike}
ORIGIN_HOST=${ORIGIN_HOST:-networkingguru/incursion-roguelike}

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || {
    echo "not inside a git repository" >&2; exit 2; }

defects=0

fail() { printf 'DEFECT  %s\n' "$1"; defects=$((defects + 1)); }

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
# upstream tree carries that name; anything else is ambiguous and must be
# written out in full.
resolve_basename() {
    local base=$1 hits
    hits=$(list_ref "$UPSTREAM_REF" | grep -E "(^|/)$(printf '%s' "$base" | sed 's/[.[\*^$]/\\&/g')$")
    [ "$(printf '%s\n' "$hits" | grep -c .)" = 1 ] || return 1
    printf '%s\n' "$hits"
}

line_at() { git -C "$ROOT" show "$UPSTREAM_REF:$1" 2>/dev/null | sed -n "${2}p"; }
line_at_ref() { git -C "$ROOT" show "$1:$2" 2>/dev/null | sed -n "${3}p"; }

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
            "$ORIGIN_HOST"/blob/master/*|"$ORIGIN_HOST"/tree/master/*)
                path=${path#"$ORIGIN_HOST"/blob/master/}
                path=${path#"$ORIGIN_HOST"/tree/master/}
                path=${path%/}
                if list_ref "$ORIGIN_REF" | grep -qE "^$(printf '%s' "$path" | sed 's/[.[\*^$]/\\&/g')(/|$)"; then
                    printf 'ours     %s  present on %s\n' "$path" "$ORIGIN_REF"
                else
                    fail "$path is not on $ORIGIN_REF -- unpushed or misspelt (link: $url)"
                fi
                ;;
            *)
                fail "link points at neither tree: $url"
                ;;
        esac
    done < <(grep -oE 'https://github\.com/[A-Za-z0-9_.@:/~-]+(#L[0-9]+(-L[0-9]+)?)?' "$doc" | sort -u)

    # 3. Bare File.ext:NNNN citations.
    local cite base num full
    while read -r cite; do
        [ -n "$cite" ] || continue
        base=${cite%%:*}
        num=${cite##*:}
        if full=$(resolve_basename "$base"); then
            printf '%s:%s\t%s\n' "$full" "$num" "$(line_at "$full" "$num")" >> "$resolved"
            printf 'bare     %s:%s  %s\n' "$full" "$num" "$(line_at "$full" "$num")"
        else
            fail "cannot resolve '$base' to one file in $UPSTREAM_REF (cited as $cite)"
        fi
    done < <(grep -oE '\b[A-Za-z_][A-Za-z0-9_]*\.(cpp|h|irh):[0-9]+' "$doc" | sort -u)

    # 4. Expectations.
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

selftest() {
    local dir="${TMPDIR:-/tmp}/checkcit-selftest.$$"
    mkdir -p "$dir"
    # One citation that must resolve, one link to a path that cannot exist.
    printf 'Feature.cpp:850 is Thing::MoveDepth.\n' > "$dir/good.md"
    printf 'See https://github.com/%s/blob/master/src/NoSuchFile.cpp#L1\n' \
        "$UPSTREAM_HOST" > "$dir/bad.md"
    printf 'src/Feature.cpp:850\tThing::MoveDepth\n' > "$dir/good.expect"

    local rc_good rc_bad
    ( check_document "$dir/good.md" "$dir/good.expect" ) > "$dir/good.out" 2>&1
    grep -q '^DEFECT' "$dir/good.out"; rc_good=$?     # 1 means no defect found
    ( defects=0; check_document "$dir/bad.md" ) > "$dir/bad.out" 2>&1
    grep -q '^DEFECT' "$dir/bad.out"; rc_bad=$?       # 0 means a defect was found

    rm -rf "$dir"
    if [ "$rc_good" = 1 ] && [ "$rc_bad" = 0 ]; then
        echo "selftest: pass -- a good citation reports nothing, a dead link reports a defect"
        return 0
    fi
    echo "selftest: FAIL (clean doc flagged=$((1 - rc_good)), dead link caught=$((1 - rc_bad)))"
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

if [ "$defects" -gt 0 ]; then
    printf '\n%d defect(s). Fix them before this goes anywhere public.\n' "$defects"
    exit 1
fi
printf '\nNo defects. Every citation resolves in %s and every evidence link is on %s.\n' \
    "$UPSTREAM_REF" "$ORIGIN_REF"
