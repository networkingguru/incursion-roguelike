#!/bin/bash
# gate: live
# gate-serial: writes and rm -rf's the fixed scratch path logs/feat-list-limit/
# Does the module compiler accept a monster Feats list and a template Feats list of
# exactly MAX_MON_FEATS entries, and refuse one entry more with an error that names
# the monster or template? (bd inc-h9snz)
#
# THE DEFECT. The lists held 16 entries. The compiler wrote Feats[CurrFeat++] BEFORE it
# checked the bound (monsters), or never checked it (templates), so a long list
# overran the record and corrupted the fields after it.
#
# THE ROUTE. Four scratch modules, each lib/ copied under logs/feat-list-limit/<case>/
# with one monster or template appended to the COPY of lib/main.irc and compiled with
# ./incursion-headless -compile. The tracked lib/ is never touched. MAX_MON_FEATS is
# read from inc/Defines.h, not written here.
#   mon-at   monster with MAX entries    must compile
#   mon-over monster with MAX+1 entries  must NOT compile; output names the monster
#   tem-at   template with MAX entries   must compile
#   tem-over template with MAX+1 entries must NOT compile; output names the template
#
# PROVING IT RED
#   tools/check_feat_list_limit.sh --selftest   stub compilers: one that accepts every
#     module (the over cases must FAIL), one that refuses every module (the at cases
#     must FAIL), one that refuses without naming (the over cases must FAIL).
#   tools/check_feat_list_limit.sh --prove-red  edits src/yygram.cpp so no bound check
#     remains, rebuilds incursion-headless, expects this check to FAIL, restores the
#     file, rebuilds. Needs a green run first.
#
# SEED INDEPENDENCE (docs/VERIFICATION.md, "A check must not depend on the seed"):
# fact: the compiled module -- scratch lib/ copy plus one generated Monster or Template, no character, no key script, no random call
# fact: the list length -- MAX_MON_FEATS read from inc/Defines.h at run time
# fact: the entries of each list -- FT_DODGE repeated; the compiler only counts them
# fact: the text matched (the monster or template name) -- chosen by this script
# fact: settings -- none enter; the check starts no game session
#
# Usage: tools/check_feat_list_limit.sh [--selftest | --prove-red]
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2
ROOT=$PWD
SELF="$ROOT/tools/check_feat_list_limit.sh"
MODE=check
case "${1:-}" in
  "") ;;
  --selftest) MODE=selftest ;;
  --prove-red) MODE=prove ;;
  *) echo "usage: $0 [--selftest | --prove-red]" >&2; exit 2 ;;
esac

MAX="$(sed -n 's/^#define MAX_MON_FEATS[[:space:]]*\([0-9][0-9]*\).*/\1/p' inc/Defines.h)"
case "$MAX" in ''|*[!0-9]*) echo "UNMEASURED: MAX_MON_FEATS not found in inc/Defines.h"; exit 2 ;; esac

# feats <count> -> "FT_DODGE, FT_DODGE, ... FT_DODGE" (count entries)
feats() { awk -v n="$1" 'BEGIN { for (i = 1; i <= n; i++) printf "%sFT_DODGE", (i > 1 ? ", " : ""); }'; }

mon_text() { # <name> <count>
  cat <<EOT
Monster "$1" : MA_GOBLIN
{
    Image: Green 'g'; Size: SZ_SMALL; Mana: 6;
    CR: 1/4; HD: 3; Hit: +0; Def: 12; Mov: 50%; Spd: 80%;
    Str 6, Dex 12, Con 10, Int 12, Wis 10, Cha 8;
    Attk: A_PUNC for 1d2 damage;
    Flags: M_CARNI, M_HERBI, M_HUMANOID, M_NEUTER, M_NOGEN;
    Feats: $(feats "$2");
    Desc: "A scratch monster for check_feat_list_limit.";
}
EOT
}
tem_text() { # <name> <count>
  cat <<EOT
Template "$1" : TM_NATURE for MA_NLIVING
{
    CR: +1;
    Feats: $(feats "$2");
    Desc: "A scratch template for check_feat_list_limit.";
}
EOT
}

# run_case <compiler> <case> -> sets VERDICT (compiled|refused) and OUT (log path)
run_case() {
  local comp="$1" c="$2" D="logs/feat-list-limit/$2" n name
  case "$c" in *-over) n=$((MAX + 1)) ;; *) n=$MAX ;; esac
  name="featlimit-$c"
  rm -rf "$D"; mkdir -p "$D/mod" "$D/save" "$D/logs"
  cp -Rf lib "$D/lib"; ln -sfn "$ROOT/inc" "$D/inc"
  case "$c" in mon-*) mon_text "$name" "$n" ;; *) tem_text "$name;template" "$n" ;; esac >> "$D/lib/main.irc"
  INCURSIONPATH="$ROOT/$D/" "$comp" -compile main.irc < /dev/null > "$D/compile.log" 2>&1
  local st=$?
  OUT="$D/compile.log"
  if [ "$st" -eq 0 ] && [ -f "$D/mod/Incursion.Mod" ]; then VERDICT=compiled; else VERDICT=refused; fi
}

# evaluate <compiler> -> prints PASS/FAIL lines, returns number of failures
evaluate() {
  local comp="$1" c fails=0
  for c in mon-at mon-over tem-at tem-over; do
    run_case "$comp" "$c"
    case "$c" in
      *-at)
        if [ "$VERDICT" = compiled ]; then echo "  PASS  $c: $MAX entries compile"
        else echo "  FAIL  $c: $MAX entries must compile (see $OUT)"; tail -3 "$OUT" | sed 's/^/        /'; fails=$((fails+1)); fi ;;
      *-over)
        if [ "$VERDICT" = refused ] && grep -q "featlimit-$c" "$OUT"; then echo "  PASS  $c: $((MAX+1)) entries refused, the error names it"
        elif [ "$VERDICT" = compiled ]; then echo "  FAIL  $c: $((MAX+1)) entries compiled"; fails=$((fails+1))
        else echo "  FAIL  $c: refused, but the error does not name featlimit-$c (see $OUT)"; fails=$((fails+1)); fi ;;
    esac
  done
  return "$fails"
}

if [ "$MODE" = selftest ]; then
  S="$(mktemp -d "${TMPDIR:-/tmp}/featlimit-selftest.XXXXXX")" || exit 2
  trap 'rm -rf "$S"' EXIT
  # stubs read the case's lib/main.irc via INCURSIONPATH; $S/real is unused
  cat > "$S/accept" <<'EOT'
#!/bin/bash
mkdir -p "$INCURSIONPATH/mod"; : > "$INCURSIONPATH/mod/Incursion.Mod"; exit 0
EOT
  cat > "$S/refuse" <<'EOT'
#!/bin/bash
rm -f "$INCURSIONPATH/mod/Incursion.Mod"; echo "Fatal: refused $(grep -o 'featlimit-[a-z-]*' "$INCURSIONPATH/lib/main.irc" | head -1)"; exit 1
EOT
  cat > "$S/refuse-named" <<'EOT'
#!/bin/bash
rm -f "$INCURSIONPATH/mod/Incursion.Mod"; echo "Fatal: refused everything, names nothing"; exit 1
EOT
  chmod +x "$S/accept" "$S/refuse" "$S/refuse-named"
  bad=0
  for s in accept refuse refuse-named; do
    evaluate "$S/$s" > "$S/$s.out"; f=$?
    case "$s" in accept) want=2 ;; refuse) want=2 ;; refuse-named) want=4 ;; esac
    # accept: over cases fail (2). refuse: at cases fail (2). refuse-named: all four fail (4).
    # (refuse-named's at cases fail too, since it refuses them)
    if [ "$f" -eq "$want" ]; then echo "  ok    stub '$s' gives $f failures"; else echo "  BAD   stub '$s' gave $f failures, want $want"; cat "$S/$s.out"; bad=1; fi
  done
  [ "$bad" -eq 0 ] || { echo "FAIL: the check's judgement is wrong"; exit 1; }
  echo "PASS: the check goes red for a compiler that accepts, refuses everything, or refuses without naming"
  exit 0
fi

[ -x ./incursion-headless ] || { echo "UNMEASURED: build ./incursion-headless first (BACKEND=posix ./build_macos.sh)"; exit 2; }
mkdir -p logs

if [ "$MODE" = prove ]; then
  "$SELF" > /dev/null 2>&1 || { echo "UNMEASURED: the check is not green to begin with"; exit 2; }
  F=src/yygram.cpp
  KEEP="$(mktemp -d "${TMPDIR:-/tmp}/featlimit-prove.XXXXXX")" || exit 2
  cp -p "$F" "$KEEP/orig"
  restore() { cp -p "$KEEP/orig" "$F"; }
  trap 'restore' EXIT
  n="$(grep -c 'if (CurrFeat >= MAX_MON_FEATS)' "$F")"
  [ "$n" -eq 4 ] || { echo "UNMEASURED: expected 4 bound checks in $F, found $n"; exit 2; }
  sed -i.bak 's/if (CurrFeat >= MAX_MON_FEATS)/if (0)/' "$F"; rm -f "$F.bak"
  BACKEND=posix ./build_macos.sh > "$KEEP/build.log" 2>&1 || { echo "UNMEASURED: mutated build failed ($KEEP/build.log)"; exit 2; }
  "$SELF" > "$KEEP/red.out" 2>&1; st=$?
  cat "$KEEP/red.out"
  restore
  cmp -s "$KEEP/orig" "$F" || { echo "INCONCLUSIVE: restore failed; original at $KEEP/orig"; trap - EXIT; exit 2; }
  BACKEND=posix ./build_macos.sh > "$KEEP/rebuild.log" 2>&1 || { echo "UNMEASURED: rebuild failed ($KEEP/rebuild.log)"; exit 2; }
  rm -rf "$KEEP"; trap - EXIT
  [ "$st" -eq 1 ] && { echo "PROVED RED: with the bound checks removed this check exits 1."; exit 0; }
  echo "NOT RED: with the bound checks removed this check exited $st."; exit 1
fi

mkdir -p logs/feat-list-limit
evaluate ./incursion-headless; fails=$?
echo
if [ "$fails" -ne 0 ]; then echo "FAIL: $fails of 4 feat-list-limit cases are wrong"; exit 1; fi
echo "PASS: $MAX-entry feat lists compile, $((MAX+1))-entry lists are refused by name"
exit 0
