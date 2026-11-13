#!/usr/bin/env bash
# gate: live
#
# Do tools/fill_chars.sh and tools/char_rekey.sh still do what spec amendment A5
# says, on a copy of a real .char?
#
# WHAT IS BEING PROVED (bead inc-10v7f, phase 11):
#   1. A .char with one line removed does not build; after fill_chars.sh it
#      builds, and the removed key is back.
#   2. fill_chars.sh on a set that is already complete changes no byte.
#   3. A key renamed and renamed back leaves every file byte-identical; so does
#      a value renamed and renamed back.
#   4. A rename onto a key that exists is refused and writes nothing; a value
#      rename onto a value the same key already holds is refused and writes
#      nothing.
#   5. A value rename (a resource name) also renames that name inside the
#      contexts of the keys and inside the item, effect and quality names of the
#      item keys, as a WHOLE name, never as part of another name; it round-trips
#      byte-identical; it is refused when the new name is already a context
#      token. Controls: a copy of the tool that matches by substring, and a copy
#      that leaves the contexts alone, MUST each fail this case (phase 11g, A4).
# The work is on copies under logs/. No tracked file is written.
#
# fact: the character -- the tracked hand-written tools/fixtures/chars/orc-barbarian-seed1-opt0822.char, every draw stated in the file; its options: line names the settings file, so no seed and no walk decides anything (inc-10v7f)
# fact: the line removed, the key and value renamed -- read from the copied file itself (its last line; its first line pair with one key and two values), so no key name or value is written in this check
# fact: the key table -- read at run time by tools/char_rekey.sh from inc/CreationSource.h; this check holds no list of keys
# fact: the renamed resource name -- a word of the copied file that is both a value of some line and a token of some context (read from the file by awk, so no name is written here); case 5 renames it
# fact: the whole-name file -- five lines written by this check; kit_item and hp_roll are keys of the table (the case reports INCONCLUSIVE when the tool does not know kit_item as an item key), and the names knife, throwing knife and knife edge are test words, not game data
#
# Usage: INCURSION_BIN=./incursion-headless tools/check_char_tools.sh
# Exit: 0 every case behaved as stated; 1 a case did not; 2 could not run.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2
BIN="${INCURSION_BIN:-./incursion-headless}"
[ -x "$BIN" ] || { echo "INCONCLUSIVE: $BIN is not built"; exit 2; }
export INCURSION_BIN="$BIN"
SRC=tools/fixtures/chars/orc-barbarian-seed1-opt0822.char
[ -f "$SRC" ] || { echo "INCONCLUSIVE: $SRC is missing"; exit 2; }

W="$(mktemp -d "$ROOT/logs/char-tools.XXXXXX")" || exit 2
trap 'rm -rf "$W"' EXIT
fails=0
ok()   { echo "ok   $*"; }
bad()  { echo "FAIL $*"; fails=1; }
sums() { for f in "$1"/*.char; do cksum < "$f"; done; }

# The base case builds at all.
mkdir -p "$W/base"; cp "$SRC" "$W/base/a.char"
if ! tools/build_fixture.sh "$W/base/a.char" "$W/base/out" > "$W/base.log" 2>&1; then
    echo "INCONCLUSIVE: the unedited copy does not build"; tail -3 "$W/base.log"; exit 2
fi

# 1. one line removed, then filled.
LASTKEY="$(tail -1 "$SRC" | sed 's/[ :].*$//')"
[ -n "$LASTKEY" ] || { echo "INCONCLUSIVE: no last key"; exit 2; }
mkdir -p "$W/fill"; sed '$d' "$SRC" > "$W/fill/a.char"
if tools/build_fixture.sh "$W/fill/a.char" "$W/fill/out" > /dev/null 2>&1; then
    bad "1 the copy with its last line removed still builds, so the removal proves nothing"
else
    out="$(tools/fill_chars.sh "$W/fill" 2>&1)"; rc=$?
    if [ $rc -eq 0 ] && grep -q "^$LASTKEY\( \[.*\]\)\?: " <<< "$(tail -1 "$W/fill/a.char")" \
        && tools/build_fixture.sh "$W/fill/a.char" "$W/fill/out" > /dev/null 2>&1; then
        ok "1 fill_chars.sh put \`$LASTKEY\` back and the file builds"
    else
        bad "1 fill_chars.sh did not restore \`$LASTKEY\` (exit $rc): $out"
    fi
fi

# 2. a complete set is not touched.
mkdir -p "$W/full"; cp "$SRC" "$W/full/a.char"; cp "$SRC" "$W/full/b.char"
before="$(sums "$W/full")"
out="$(tools/fill_chars.sh "$W/full" 2>&1)"; rc=$?
if [ $rc -eq 0 ] && [ "$before" = "$(sums "$W/full")" ]; then
    ok "2 fill_chars.sh left a complete set byte-identical"
else
    bad "2 fill_chars.sh touched a complete set or failed (exit $rc): $out"
fi

# 3. a key and a value, renamed and back.
mkdir -p "$W/rk"; cp "$SRC" "$W/rk/a.char"; cp "$SRC" "$W/rk/b.char"
before="$(sums "$W/rk")"
tools/char_rekey.sh "$LASTKEY" zz_renamed_key "$W/rk" > "$W/k1.log" 2>&1
if grep -q '^zz_renamed_key' "$W/rk/a.char" && tools/char_rekey.sh zz_renamed_key "$LASTKEY" "$W/rk" > "$W/k2.log" 2>&1 \
    && [ "$before" = "$(sums "$W/rk")" ]; then
    ok "3 key \`$LASTKEY\` renamed and back, every file byte-identical"
else
    bad "3 the key round trip changed a file or a rename failed: $(cat "$W/k1.log" "$W/k2.log" 2>/dev/null | tail -2)"
fi
# A value: the first key that holds two different values, rename one onto
# a value no line of that key holds.
KV="$(awk '/^[a-z][a-z0-9_]*( \[[^]]*\])?:/ { k=$0; sub(/[ \[:].*$/,"",k); v=$0; sub(/^[^:]*: ?/,"",v);
        if (k in first && first[k] != v && !(k in done)) { print k "\t" first[k] "\t" v; done[k]=1 }
        if (!(k in first)) first[k]=v }' "$SRC" | head -1)"
VKEY="${KV%%$'\t'*}"; rest="${KV#*$'\t'}"; V1="${rest%%$'\t'*}"; V2="${rest#*$'\t'}"
if [ -z "$VKEY" ]; then
    echo "INCONCLUSIVE: no key with two values in $SRC"; exit 2
fi
before="$(sums "$W/rk")"
tools/char_rekey.sh "$V1" zz_renamed_value "$W/rk" > "$W/v1.log" 2>&1
if grep -q 'zz_renamed_value' "$W/rk/a.char" && tools/char_rekey.sh zz_renamed_value "$V1" "$W/rk" > "$W/v2.log" 2>&1 \
    && [ "$before" = "$(sums "$W/rk")" ]; then
    ok "3 value \`$V1\` renamed and back, every file byte-identical"
else
    bad "3 the value round trip changed a file or a rename failed: $(cat "$W/v1.log" "$W/v2.log" 2>/dev/null | tail -2)"
fi

# 4. a collision is refused and writes nothing.
OTHERKEY="$(head -40 "$SRC" | grep -E '^[a-z][a-z0-9_]*( \[[^]]*\])?:' | sed 's/[ :].*$//' | grep -vx -e "$LASTKEY" -e options -e seed | head -1)"
before="$(sums "$W/rk")"
out="$(tools/char_rekey.sh "$LASTKEY" "$OTHERKEY" "$W/rk" 2>&1)"; rc=$?
if [ $rc -ne 0 ] && grep -q REFUSED <<< "$out" && [ "$before" = "$(sums "$W/rk")" ]; then
    ok "4 renaming \`$LASTKEY\` onto the existing key \`$OTHERKEY\` was refused, nothing written"
else
    bad "4 the key collision was not refused cleanly (exit $rc): $out"
fi
out="$(tools/char_rekey.sh "$V1" "$V2" "$W/rk" 2>&1)"; rc=$?
if [ $rc -ne 0 ] && grep -q REFUSED <<< "$out" && [ "$before" = "$(sums "$W/rk")" ]; then
    ok "4 renaming value \`$V1\` onto \`$V2\` (both held by \`$VKEY\`) was refused, nothing written"
else
    bad "4 the value collision was not refused cleanly (exit $rc): $out"
fi

# 5. A resource name inside contexts and item fields, whole names only.
RN="$(awk '/^[a-z][a-z0-9_]*( \[[^]]*\])?:/ && !/^(options|seed):/ {
        c = $0; if (c ~ /^[a-z0-9_]+ \[/) { sub(/^[a-z0-9_]+ \[/, "", c); sub(/\].*$/, "", c); n = split(c, t, ";"); for (i = 1; i <= n; i++) tok[t[i]] = 1 }
        v = $0; sub(/^[^:]*: ?/, "", v); val[v] = 1; vals[++nv] = v }
    END { for (i = 1; i <= nv; i++) if (vals[i] in tok) { print vals[i]; exit } }' "$SRC")"
if [ -z "$RN" ]; then echo "INCONCLUSIVE: no word of $SRC is both a value and a context token"; exit 2; fi
rm -rf "$W/rn"; mkdir -p "$W/rn"; cp "$SRC" "$W/rn/a.char"
out="$(tools/char_rekey.sh "$RN" zz_renamed_name "$W/rn" 2>&1)"; rc=$?
left="$(grep -vE '^[[:space:]]*#' "$W/rn/a.char" | grep -cE "\[$RN[];]|;$RN[];]|^[a-z0-9_]+: $RN\$")"
if [ $rc -eq 0 ] && [ "$left" -eq 0 ] && grep -q "context token(s)" <<< "$out" && ! grep -q ' 0 context token(s)' <<< "$out" \
    && tools/char_rekey.sh zz_renamed_name "$RN" "$W/rn" > /dev/null 2>&1 && cmp -s "$W/rn/a.char" "$SRC"; then
    ok "5 name \`$RN\` renamed in values and contexts ($(echo "$out" | sed 's/.*: \([0-9]* value.*\)/\1/')), and back, byte-identical"
else
    bad "5 the name \`$RN\` was not renamed everywhere ($left line(s) still hold it) or did not round-trip (exit $rc): $out"
fi
cat > "$W/rn/whole.char" <<'EOF'
options: x
seed: 1
kit_item [Orc;a1]: knife, quantity 1
kit_item [Orc;a2]: throwing knife, effect knife, quality knife edge, quantity 2
hp_roll [Knife]: 3
EOF
wholeok() {   # <tool>: renames knife in a copy of whole.char and judges the result
    rm -rf "$W/rn/w"; mkdir -p "$W/rn/w"; cp "$W/rn/whole.char" "$W/rn/w/a.char"
    "$1" knife dagger "$W/rn/w" > "$W/rn/w.log" 2>&1
    [ "$(sed -n 3p "$W/rn/w/a.char")" = "kit_item [Orc;a1]: dagger, quantity 1" ] \
        && [ "$(sed -n 4p "$W/rn/w/a.char")" = "kit_item [Orc;a2]: throwing knife, effect dagger, quality knife edge, quantity 2" ] \
        && [ "$(sed -n 5p "$W/rn/w/a.char")" = "hp_roll [Knife]: 3" ]
}
if wholeok tools/char_rekey.sh; then
    ok "5 knife -> dagger renamed the item, the effect and nothing that only contains the word"
else
    bad "5 the whole-name rename is wrong: $(sed -n 3,5p "$W/rn/w/a.char" | tr '\n' '|') $(cat "$W/rn/w.log")"
fi
MUT="tools/.char_rekey_mutant.$$.sh"
for mut in 's/if (base(n) == old)/if (index(base(n), old))/' 's/if (a\[i\] == old)/if (0)/'; do
    sed "$mut" tools/char_rekey.sh > "$MUT"
    if cmp -s tools/char_rekey.sh "$MUT"; then echo "INCONCLUSIVE: the mutation \"$mut\" changed nothing"; rm -f "$MUT"; exit 2; fi
    chmod +x "$MUT"
    rm -rf "$W/rn/m"; mkdir -p "$W/rn/m"; cp "$SRC" "$W/rn/m/a.char"
    "$MUT" "$RN" zz_renamed_name "$W/rn/m" > /dev/null 2>&1
    stripped="$(grep -vE '^[[:space:]]*#' "$W/rn/m/a.char")"
    if wholeok "$MUT" && ! grep -qE "\[$RN[];]|;$RN[];]" <<< "$stripped"; then
        bad "5 the mutant \"$mut\" passed both whole-name and context cases, so the case cannot fail"
    else
        ok "5 the mutant \"$mut\" fails case 5"
    fi
done
rm -f "$MUT"
mkdir -p "$W/rn/coll"; printf 'options: x\nseed: 1\nhp_roll [Knife]: 3\nhp_roll [zz_other]: 3\n' > "$W/rn/coll/a.char"
before="$(cksum < "$W/rn/coll/a.char")"
out="$(tools/char_rekey.sh Knife zz_other "$W/rn/coll" 2>&1)"; rc=$?
if [ $rc -ne 0 ] && grep -q REFUSED <<< "$out" && [ "$before" = "$(cksum < "$W/rn/coll/a.char")" ]; then
    ok "5 renaming a context token onto an existing token was refused, nothing written"
else
    bad "5 the context collision was not refused cleanly (exit $rc): $out"
fi

[ $fails -eq 0 ] && echo "PASS: fill_chars.sh and char_rekey.sh behave as stated" && exit 0
echo "FAIL: see the FAIL lines above"
exit 1
