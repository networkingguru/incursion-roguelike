#!/usr/bin/env bash
# Rename a key, or a value, in every `.char` in a directory (bead inc-10v7f,
# spec amendment A5). Run by hand in the bead that renames a decision key or a
# resource name; its output is a reviewed diff.
#
# Usage: tools/char_rekey.sh <old> <new> [dir]      dir defaults to tools/fixtures/chars
#
# KEY OR VALUE. <old> is a KEY when it is a key name of the CREATION_KEY_LIST
# table in inc/CreationSource.h (read at run time, as tools/check_no_per_key_
# branch.sh reads it) or a key on a line of some .char in dir (so a key the
# table has already lost, or a rename run backward, still works). A key rename
# changes every line `<old>: v` and `<old> [ctx]: v` to `<new>...`. Anything
# else is a VALUE (a resource name): <old> becomes <new> wherever it names that
# resource, as a WHOLE name, never as part of another name:
#   - a line whose value is exactly <old>;
#   - a token of a context: `hp_roll [Barbarian]`, `gear_chance [Barbarian;a1]`,
#     `script_roll [Barbarian;EV_153]` (the context splits at `;`);
#   - the item, `effect` and `quality` names inside the value of an item key
#     (the keys of kind ITEM in the table: kit_item, beginkit_item, perk_item),
#     including the effect of a `stati` field; a tagged name `Remove Curse;potion`
#     matches by the part before the `;` and keeps its tag.
# A word that is a key and also a value somewhere is renamed as a key only; the
# script says so. The script holds no key list of its own and no per-key branch
# (B18): the table says which keys are items.
#
# REFUSED, with nothing written (exit 1): <new> is already a key on a line of
# any .char in dir (key rename), already a value on a line of a key that has
# a line with the value <old>, already a context token, or already an item,
# effect or quality name (value rename); each would merge two things, and the
# round trip would lose the difference. Also refused: <old> equal to <new>,
# <old> found nowhere, and the data lines `options` and `seed`.
#
# Comments (#) and the `options:` and `seed:` lines are not touched. A file that
# needs no change is not rewritten (byte-identical).
# The last line says how many values, context tokens and item-field names a value
# rename changed, and in how many files.
# Exit: 0 renamed; 1 refused or nothing to rename; 2 bad usage.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

OLD="${1:-}"
NEW="${2:-}"
DIR="${3:-tools/fixtures/chars}"
HDR="${CHAR_REKEY_HEADER:-inc/CreationSource.h}"
if [ -z "$OLD" ] || [ -z "$NEW" ] || [ ! -d "$DIR" ]; then
    echo "usage: tools/char_rekey.sh <old> <new> [dir]" >&2
    exit 2
fi
if [ "$OLD" = "$NEW" ]; then echo "char_rekey: <old> and <new> are the same" >&2; exit 1; fi
case "$OLD" in options|seed) echo "char_rekey: \`$OLD\` is a data line, not a decision key" >&2; exit 1 ;; esac
shopt -s nullglob
FILES=("$DIR"/*.char)
[ "${#FILES[@]}" -gt 0 ] || { echo "char_rekey: no .char file in $DIR" >&2; exit 1; }

# One awk program, three modes. A key line is `key: value` or `key [ctx]: value`.
# MODE=scan prints "key <name>", "val <key> <value>", "ctx <token>" and, for the
# keys named in RK_ITEMKEYS, "item <name>" for every key line.
# MODE=key renames the key OLD; MODE=val renames the value OLD (see the header).
AWK='
function base(n,   i) { i = index(n, ";"); return i ? substr(n, 1, i - 1) : n }
function tag(n,   i) { i = index(n, ";"); return i ? substr(n, i) : "" }
function ren_name(n) { if (base(n) == old) { nitem++; return new tag(n) } return n }
function is_field(s) { return s ~ /^(effect|plus|bane|flag|quality|quantity|charges|stati) / }
# The pieces of an item text; a part that opens no field belongs to the piece before it.
function pieces_of(v, pieces,   n, a, i, np) {
    n = split(v, a, ", "); np = 0
    for (i = 1; i <= n; i++) {
        if (i == 1 || is_field(a[i])) { np++; pieces[np] = a[i] }
        else pieces[np] = pieces[np] ", " a[i]
    }
    return np
}
function ren_item(v,   pieces, np, j, p, out, q) {
    np = pieces_of(v, pieces); out = ""
    for (j = 1; j <= np; j++) {
        p = pieces[j]
        if (j == 1) p = ren_name(p)
        else if (p ~ /^effect /) p = "effect " ren_name(substr(p, 8))
        else if (p ~ /^quality /) p = "quality " ren_name(substr(p, 9))
        else if (p ~ /^stati .* effect /) { q = index(p, " effect "); p = substr(p, 1, q + 7) ren_name(substr(p, q + 8)) }
        out = out (j > 1 ? ", " : "") p
    }
    return out
}
function ren_ctx(c,   n, a, i, out) {
    n = split(c, a, ";"); out = ""
    for (i = 1; i <= n; i++) {
        if (a[i] == old) { nctx++; out = out (i > 1 ? ";" : "") new }
        else out = out (i > 1 ? ";" : "") a[i]
    }
    return out
}
function scan_item(v,   pieces, np, j, p, q) {
    np = pieces_of(v, pieces)
    for (j = 1; j <= np; j++) {
        p = pieces[j]
        if (j == 1) print "item " base(p)
        else if (p ~ /^effect /) print "item " base(substr(p, 8))
        else if (p ~ /^quality /) print "item " base(substr(p, 9))
        else if (p ~ /^stati .* effect /) { q = index(p, " effect "); print "item " base(substr(p, q + 8)) }
    }
}
BEGIN { old = ENVIRON["RK_OLD"]; new = ENVIRON["RK_NEW"]; mode = ENVIRON["RK_MODE"]
        n = split(ENVIRON["RK_ITEMKEYS"], ik, " "); for (i = 1; i <= n; i++) isitem[ik[i]] = 1 }
END { if (ENVIRON["RK_COUNTS"] != "") print nval + 0, nctx + 0, nitem + 0 > ENVIRON["RK_COUNTS"] }
/^[ \t]*#/ || !/^[a-z][a-z0-9_]*( \[[^]]*\])?:/ { if (mode != "scan") print; next }
{
    k = $0; sub(/[ \[:].*$/, "", k)
    rest = substr($0, length(k) + 1)
    v = rest; sub(/^( \[[^]]*\])?: ?/, "", v)
    head = substr(rest, 1, length(rest) - length(v))
    ctx = ""
    if (head ~ /^ \[/) { ctx = head; sub(/^ \[/, "", ctx); sub(/\].*$/, "", ctx) }
    if (k == "options" || k == "seed") { if (mode != "scan") print; next }
    if (mode == "scan") {
        print "key " k; print "val " k " " v
        if (ctx != "") { n = split(ctx, ca, ";"); for (i = 1; i <= n; i++) print "ctx " ca[i] }
        if (k in isitem) scan_item(v)
        next
    }
    if (mode == "key" && k == old) { print new head v; next }
    if (mode == "val") {
        if (ctx != "") { nc = ren_ctx(ctx); if (nc != ctx) head = " [" nc "]: " }
        if (k in isitem) v = ren_item(v)
        else if (v == old) { v = new; nval++ }
        print k head v; next
    }
    print
}'
run_awk() { RK_OLD="$OLD" RK_NEW="$NEW" RK_MODE="$1" RK_ITEMKEYS="$ITEMKEYS" RK_COUNTS="${3:-}" awk "$AWK" "$2"; }

# The keys of kind ITEM, read from the table like the key names.
ITEMKEYS="$(sed -n 's/^[[:space:]]*X(\([A-Z0-9_]*\), *ITEM,.*/\1/p' "$HDR" | tr 'A-Z' 'a-z' | tr '\n' ' ')"

SCAN="$(for f in "${FILES[@]}"; do run_awk scan "$f"; done)"

IS_KEY=0
HDR_KEYS="$(sed -n 's/^[[:space:]]*X(\([A-Z0-9_]*\),.*/\1/p' "$HDR" | tr 'A-Z' 'a-z')"
if grep -qx -- "$OLD" <<< "$HDR_KEYS"; then IS_KEY=1; fi
if grep -qxF -- "key $OLD" <<< "$SCAN"; then IS_KEY=1; fi

if [ "$IS_KEY" -eq 1 ]; then
    MODE=key
    if grep -qxF -- "key $NEW" <<< "$SCAN"; then
        echo "char_rekey: REFUSED, \`$NEW\` is already a key in a .char of $DIR; the rename would merge two keys" >&2
        exit 1
    fi
    grep -qxF -- "key $OLD" <<< "$SCAN" || { echo "char_rekey: no line with key \`$OLD\` in $DIR" >&2; exit 1; }
    if grep -q -- "^val [^ ]* $OLD\$" <<< "$SCAN"; then
        echo "char_rekey: \`$OLD\` is a key and also a value; renaming the key only"
    fi
else
    MODE=val
    KEYS="$(printf '%s\n' "$SCAN" | RK_OLD="$OLD" awk '$1 == "val" { v = $0; sub(/^val [^ ]* ?/, "", v); if (v == ENVIRON["RK_OLD"]) print $2 }' | sort -u)"
    HAS_CTX=0; HAS_ITEM=0
    grep -qxF -- "ctx $OLD" <<< "$SCAN" && HAS_CTX=1
    grep -qxF -- "item $OLD" <<< "$SCAN" && HAS_ITEM=1
    { [ -n "$KEYS" ] || [ "$HAS_CTX" -eq 1 ] || [ "$HAS_ITEM" -eq 1 ]; } || { echo "char_rekey: no key and no value, context token or item name \`$OLD\` in $DIR" >&2; exit 1; }
    while IFS= read -r k; do
        [ -n "$k" ] || continue
        if grep -qxF -- "val $k $NEW" <<< "$SCAN"; then
            echo "char_rekey: REFUSED, \`$NEW\` is already a value of \`$k\` in a .char of $DIR; the rename would merge two values" >&2
            exit 1
        fi
    done <<< "$KEYS"
    if [ "$HAS_CTX" -eq 1 ] && grep -qxF -- "ctx $NEW" <<< "$SCAN"; then
        echo "char_rekey: REFUSED, \`$NEW\` is already a context token in a .char of $DIR; the rename would merge two contexts" >&2
        exit 1
    fi
    if [ "$HAS_ITEM" -eq 1 ] && grep -qxF -- "item $NEW" <<< "$SCAN"; then
        echo "char_rekey: REFUSED, \`$NEW\` is already an item, effect or quality name in a .char of $DIR; the rename would merge two names" >&2
        exit 1
    fi
fi

T="$(mktemp -d "${TMPDIR:-/tmp}/rekey.XXXXXX")" || exit 2
trap 'rm -rf "$T"' EXIT
n=0; TV=0; TC=0; TI=0
for f in "${FILES[@]}"; do
    run_awk "$MODE" "$f" "$T/counts" > "$T/$(basename "$f")" || exit 2
    if [ "$MODE" = val ]; then
        read -r cv cc ci < "$T/counts"
        TV=$((TV + cv)); TC=$((TC + cc)); TI=$((TI + ci))
    fi
done
for f in "${FILES[@]}"; do
    if ! cmp -s "$f" "$T/$(basename "$f")"; then
        cp -f "$T/$(basename "$f")" "$f" || exit 2
        n=$((n + 1))
    fi
done
if [ "$MODE" = val ]; then
    echo "char_rekey: val \`$OLD\` -> \`$NEW\`: $TV value(s), $TC context token(s), $TI item-field name(s), in $n file(s)"
else
    echo "char_rekey: $MODE \`$OLD\` -> \`$NEW\` in $n file(s)"
fi
