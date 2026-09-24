#!/bin/bash
# Does tools/bead_dupes.py actually gate tools/bead_new.sh and report in
# tools/finish_bead.sh? Offline: no bd, no network, no OpenRouter.
#
#   tools/check_bead_dupe_wiring.sh      (0 pass, 1 fail)
#
# IT NEVER TOUCHES THE REAL DATABASE OR THE NETWORK. bead_new.sh is copied into
# a throwaway tree where both its engine and its publish checker are stubs, and
# a stub `bd` on PATH records argv instead of filing. The wrapper's draft-args
# call is delegated to the REAL engine, so the argument extraction under test is
# the shipped one; only check-draft's verdict is stubbed.
#
# finish_bead.sh is exercised only on its TAIL -- the STEP 7 duplicate check --
# inside a throwaway git repo of its own (the same shape its own selftest
# builds), never against the real checkout. That proves the check runs and that
# an engine failure (exit 1/3 or an absent engine) still leaves exit status 0.
#
# inc-zu0r phase 2.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REAL_ENGINE="$ROOT/tools/bead_dupes.py"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
FAIL=0

ok()  { echo "OK    $1"; }
bad() { echo "FAIL  $1"; FAIL=1; }

# Fake HOME so the engine never finds the Keychain key, and blank the env var:
# every real-engine run here is keyless, and therefore offline.
export OPENROUTER_API_KEY=""
export HOME="$TMP/home"
mkdir -p "$HOME"

# ---------------------------------------------------------------- stub bd
# Records every argument, one per line; answers `create` with a fixed id.
cat > "$TMP/bd" <<'STUB'
#!/bin/bash
{
    for a in "$@"; do printf '%s\n' "$a"; done
    printf '%s\n' "--"
} >> "${BD_REC:?BD_REC must be set}"
for a in "$@"; do
    if [ "$a" = "create" ]; then
        echo '{"id": "inc-stub"}'
        exit 0
    fi
done
exit 0
STUB
chmod +x "$TMP/bd"

# ---------------------------------------------------------------- stub engine
# Python, because the wrapper runs the engine under python3. draft-args
# delegates to the real engine (so the shipped extractor is under test);
# check-draft obeys STUB_CHECK_RC and records the description it was handed,
# so the test can see what reached it.
cat > "$TMP/bead_dupes.py" <<STUB
#!/usr/bin/env python3
import json, os, subprocess, sys

REAL = r"$REAL_ENGINE"

if len(sys.argv) > 1 and sys.argv[1] == "draft-args":
    sys.exit(subprocess.call([sys.executable, REAL] + sys.argv[1:]))

if len(sys.argv) > 1 and sys.argv[1] == "check-draft":
    with open(os.environ["ENGINE_REC"], "a") as fh:
        fh.write("CHECK " + " ".join(sys.argv[1:]) + "\n")
    out = None
    desc = None
    args = sys.argv[2:]
    for i, a in enumerate(args):
        if a == "--json-out" and i + 1 < len(args):
            out = args[i + 1]
        if a == "--description-file" and i + 1 < len(args):
            desc = args[i + 1]
    if desc is not None:
        with open(os.environ["DESC_REC"], "w") as fh:
            fh.write(open(desc).read())
    rc = int(os.environ.get("STUB_CHECK_RC", "0"))
    payload = {
        0: {"hits": []},
        1: {"hits": [{"id": "inc-dup", "status": "open", "title": "Dup",
                      "probability": 0.91}]},
        2: {"unavailable": "bad input: cannot read the draft"},
        3: {"unavailable": "no OpenRouter API key"},
    }.get(rc, {"hits": []})
    if out:
        with open(out, "w") as fh:
            json.dump(payload, fh)
    if rc == 1:
        print("inc-dup\topen\tDup\t0.910")
    elif rc == 2:
        print("bead_dupes: check-draft bad input", file=sys.stderr)
    elif rc == 3:
        print("bead_dupes: Jev unavailable: no OpenRouter API key",
              file=sys.stderr)
    sys.exit(rc)

sys.exit(0)
STUB

# A publish checker that always passes, so the duplicate wiring is what is
# under test rather than the publish rules.
cat > "$TMP/check_bead_publish.py" <<'STUB'
#!/bin/bash
exit 0
STUB
chmod +x "$TMP/check_bead_publish.py"

# The wrapper under test, in a tree whose tools/ hold the two stubs.
mkdir -p "$TMP/tree/tools"
cp "$ROOT/tools/bead_new.sh" "$TMP/tree/tools/bead_new.sh"
cp "$TMP/bead_dupes.py" "$TMP/tree/tools/bead_dupes.py"
cp "$TMP/check_bead_publish.py" "$TMP/tree/tools/check_bead_publish.py"

# run_wrapper <check-rc> <args...> ; prints output, sets RC
run_wrapper() {
    local rc="$1"; shift
    rm -f "$TMP/bd.rec" "$TMP/engine.rec"
    : > "$TMP/bd.rec"; : > "$TMP/engine.rec"
    PATH="$TMP:$PATH" BD_REC="$TMP/bd.rec" ENGINE_REC="$TMP/engine.rec" \
        DESC_REC="$TMP/desc.rec" STUB_CHECK_RC="$rc" \
        "$TMP/tree/tools/bead_new.sh" "$@" 2>&1
}

bd_create_called() {
    grep -qx "create" "$TMP/bd.rec"
}

# ---------------------------------------------------------------- bead_new

# 1. a clean draft: the check runs, the bead is filed, the publish check runs.
OUT=$(run_wrapper 0 "a clean title" -d "a clean body"); RC=$?
[ $RC -eq 0 ] && ok "clean draft: exit 0" || bad "clean draft: exit $RC, wanted 0"
bd_create_called && ok "clean draft: bd create was called" \
                 || bad "clean draft: bd create was NOT called"
grep -q "inc-stub" <<<"$OUT" && ok "clean draft: names the filed id" \
                             || bad "clean draft: did not name the filed id"

# 2. a duplicate, no override: nothing filed, exit 3, names the override.
OUT=$(run_wrapper 1 "a duplicate title" -d "a duplicate body"); RC=$?
[ $RC -eq 3 ] && ok "duplicate: exit 3" || bad "duplicate: exit $RC, wanted 3"
bd_create_called && bad "duplicate: bd create WAS called" \
                 || ok "duplicate: nothing was filed"
case "$OUT" in
    *"--not-a-duplicate"*) ok "duplicate: names the override" ;;
    *) bad "duplicate: did not name --not-a-duplicate" ;;
esac
case "$OUT" in
    *"bd duplicate"*) ok "duplicate: names the bd duplicate command" ;;
    *) bad "duplicate: did not name the bd duplicate command" ;;
esac

# 3. a duplicate WITH the override: filed, notes appended, flag stripped.
OUT=$(run_wrapper 1 "a duplicate title" -d "a duplicate body" --not-a-duplicate); RC=$?
[ $RC -eq 0 ] && ok "override: exit 0" || bad "override: exit $RC, wanted 0"
bd_create_called && ok "override: bd create was called" \
                 || bad "override: bd create was NOT called"
grep -qx -- "--not-a-duplicate" "$TMP/bd.rec" \
    && bad "override: --not-a-duplicate reached bd" \
    || ok "override: --not-a-duplicate was stripped before bd"
grep -q "append-notes" "$TMP/bd.rec" \
    && ok "override: a note was appended" \
    || bad "override: no note was appended"
grep -q "inc-dup" "$TMP/bd.rec" && ok "override: note names the candidate" \
                                || bad "override: note did not name the candidate"

# 4. Jev unavailable: filed, skipped note, directive printed.
OUT=$(run_wrapper 3 "an unjudged title" -d "an unjudged body"); RC=$?
[ $RC -eq 0 ] && ok "unavailable: exit 0" || bad "unavailable: exit $RC, wanted 0"
bd_create_called && ok "unavailable: bd create was called" \
                 || bad "unavailable: bd create was NOT called"
grep -q "duplicate check skipped: no OpenRouter API key" "$TMP/bd.rec" \
    && ok "unavailable: skip note appended with the reason" \
    || bad "unavailable: skip note missing or wrong"
case "$OUT" in
    *"DIRECTIVE TO THE FILING AGENT"*"haiku"*) ok "unavailable: directive printed" ;;
    *) bad "unavailable: no haiku directive" ;;
esac

# 5. --stdin: the description reaches the check, bd gets --body-file <temp>.
OUT=$(printf 'stdin body text' | run_wrapper 0 "a stdin title" --stdin); RC=$?
[ $RC -eq 0 ] && ok "stdin: exit 0" || bad "stdin: exit $RC, wanted 0"
[ "$(cat "$TMP/desc.rec" 2>/dev/null)" = "stdin body text" ] \
    && ok "stdin: the description reached the check" \
    || bad "stdin: the check did not get the description"
grep -q -- "--description-file" "$TMP/engine.rec" \
    && ok "stdin: the check was given a description file" \
    || bad "stdin: no --description-file at the check"
grep -qx -- "--body-file" "$TMP/bd.rec" \
    && ok "stdin: bd was given --body-file" \
    || bad "stdin: bd did not get --body-file"
grep -qx -- "-" "$TMP/bd.rec" \
    && bad "stdin: bd was handed a literal - (stdin was not materialised)" \
    || ok "stdin: bd was not handed a literal -"

# 5b. --parent passes through to the check and to bd.
OUT=$(run_wrapper 0 "a child title" -d "a child body" --parent inc-epic); RC=$?
[ $RC -eq 0 ] && ok "parent: exit 0" || bad "parent: exit $RC, wanted 0"
grep -q -- "--parent inc-epic" "$TMP/engine.rec" \
    && ok "parent: the check was given --parent" \
    || bad "parent: the check did not get --parent"
grep -q -- "--parent" "$TMP/bd.rec" \
    && ok "parent: bd was given --parent" \
    || bad "parent: bd did not get --parent"

# 6. bulk -f: no check, notice printed.
OUT=$(run_wrapper 1 "a bulk title" -f plan.md); RC=$?
[ $RC -eq 0 ] && ok "bulk: exit 0" || bad "bulk: exit $RC, wanted 0"
[ -s "$TMP/engine.rec" ] && bad "bulk: the duplicate check was run" \
                         || ok "bulk: no duplicate check"
bd_create_called && ok "bulk: bd create was called" \
                 || bad "bulk: bd create was NOT called"
case "$OUT" in
    *"bulk filing is not checked"*) ok "bulk: notice printed" ;;
    *) bad "bulk: no notice" ;;
esac

# 7. --help: pass-through, no engine, no scratch.
OUT=$(run_wrapper 1 --help); RC=$?
[ $RC -eq 0 ] && ok "help: exit 0" || bad "help: exit $RC, wanted 0"
[ -s "$TMP/engine.rec" ] && bad "help: the engine was invoked" \
                         || ok "help: the engine was not invoked"
grep -qx -- "--help" "$TMP/bd.rec" && ok "help: passed straight to bd create" \
                                   || bad "help: did not reach bd create"

# ------------------------------------------------- real engine, offline check
# The real engine with no key and no network must exit 3 and write the
# unavailable reason to --json-out -- never exit 0.
printf 'anything' > "$TMP/real.desc"
python3 "$REAL_ENGINE" check-draft --title "anything" \
    --description-file "$TMP/real.desc" \
    --beads-json "$ROOT/logs/bead-dupes-offline-proof.json" \
    --json-out "$TMP/real.json" >"$TMP/real.out" 2>&1
RC=$?
[ $RC -eq 3 ] && ok "real engine offline: exit 3" \
              || bad "real engine offline: exit $RC, wanted 3"
grep -q '"unavailable"' "$TMP/real.json" \
    && ok "real engine offline: wrote {\"unavailable\": ...}" \
    || bad "real engine offline: no unavailable reason in --json-out"
case "$(cat "$TMP/real.out")" in
    *0.9*|*Dragon*|*Ancient*) bad "real engine offline: looked like a live result" ;;
    *) ok "real engine offline: no candidate numbers" ;;
esac

# ---------------------------------------------------------------- finish_bead
# Only the STEP 7 tail, in a throwaway git repo. Build a repo with a master and
# a bead branch/worktree exactly as finish_bead.sh's own selftest does, copy the
# script (and the docs-only classifier it may call) in, and put a stub engine in
# the SHARED checkout's tools/ so the check reads a verdict the test chooses.

finish_repo() { # prints "<tmp> <script-copy> "
    local tmp bead="inc-slftst"
    tmp="$(mktemp -d "${TMPDIR:-/tmp}/bead-dupe-wiring.XXXXXX")" || return 1
    mkdir -p "$tmp/work/Incursion/tools" "$tmp/work/Incursion/src" || return 1
    git -C "$tmp/work/Incursion" init -q -b trunk || return 1
    git -C "$tmp/work/Incursion" config user.email test@example.invalid || return 1
    git -C "$tmp/work/Incursion" config user.name "wiring selftest" || return 1
    echo base >"$tmp/work/Incursion/base.txt" || return 1
    echo "int Foo() { return 1; }" >"$tmp/work/Incursion/src/Foo.cpp" || return 1
    git -C "$tmp/work/Incursion" add base.txt src/Foo.cpp || return 1
    git -C "$tmp/work/Incursion" commit -q -m initial || return 1
    git -C "$tmp/work/Incursion" branch master trunk || return 1

    git -C "$tmp/work/Incursion" worktree add -q -b "$bead" \
        "$tmp/work/Incursion-$bead" master || return 1
    echo bead >"$tmp/work/Incursion-$bead/bead-work.txt" || return 1
    git -C "$tmp/work/Incursion-$bead" add bead-work.txt || return 1
    git -C "$tmp/work/Incursion-$bead" commit -q -m "bead work" || return 1

    cp "$ROOT/tools/finish_bead.sh" "$tmp/work/Incursion/tools/finish_bead.sh" || return 1
    cp "$ROOT/tools/docs_only_change.sh" "$tmp/work/Incursion/tools/docs_only_change.sh" || return 1

    printf '%s %s\n' "$tmp" "$tmp/work/Incursion/tools/finish_bead.sh"
}

# A stub engine in the throwaway shared checkout, with the chosen verdict.
# Python, because finish_bead.sh runs it under python3.
finish_stub_engine() { # finish_stub_engine <shared> <rc>
    local shared="$1" rc="$2"
    cat > "$shared/tools/bead_dupes.py" <<STUB
#!/usr/bin/env python3
import sys
if len(sys.argv) < 2 or sys.argv[1] != "check-bead":
    sys.exit(0)
if $rc == 1:
    print("inc-other\topen\tSome other bead\t0.880")
elif $rc == 3:
    print("bead_dupes: Jev unavailable: no OpenRouter API key", file=sys.stderr)
sys.exit($rc)
STUB
}

run_finish() { # run_finish <line> <engine-rc|absent>
    local line rc tmp copy shared
    line="$1"; rc="$2"
    read -r tmp copy <<<"$line"
    shared="$(sed -n '1s/^worktree //p' < <(git -C "$tmp/work/Incursion" worktree list --porcelain))"
    if [ "$rc" = "absent" ]; then
        rm -f "$shared/tools/bead_dupes.py"
    else
        finish_stub_engine "$shared" "$rc"
    fi
    INCURSION_FINISH_GATE=true "$copy" inc-slftst 2>&1
    local out=$?
    rm -rf "$tmp"
    return $out
}

# 8. engine exit 1: the candidates line and the bd duplicate command print, and
#    the landing still exits 0.
OUT=$(run_finish "$(finish_repo)" 1); RC=$?
[ $RC -eq 0 ] && ok "finish tail (dup): exit stays 0" \
              || bad "finish tail (dup): exit $RC, wanted 0"
case "$OUT" in
    *"Open beads that may duplicate inc-slftst"*) ok "finish tail (dup): candidates header" ;;
    *) bad "finish tail (dup): no candidates header" ;;
esac
case "$OUT" in
    *"bd duplicate <id> --of inc-slftst"*) ok "finish tail (dup): names the command" ;;
    *) bad "finish tail (dup): no bd duplicate command" ;;
esac

# 9. engine exit 3: the closer's haiku directive prints, exit stays 0.
OUT=$(run_finish "$(finish_repo)" 3); RC=$?
[ $RC -eq 0 ] && ok "finish tail (unavailable): exit stays 0" \
              || bad "finish tail (unavailable): exit $RC, wanted 0"
case "$OUT" in
    *"DIRECTIVE TO THE CLOSING AGENT"*"haiku"*) ok "finish tail (unavailable): directive" ;;
    *) bad "finish tail (unavailable): no directive" ;;
esac

# 10. engine absent on the base branch: a line is printed, exit stays 0.
OUT=$(run_finish "$(finish_repo)" absent); RC=$?
[ $RC -eq 0 ] && ok "finish tail (absent): exit stays 0" \
              || bad "finish tail (absent): exit $RC, wanted 0"
case "$OUT" in
    *"skipping the duplicate check"*) ok "finish tail (absent): says it skipped" ;;
    *) bad "finish tail (absent): no skip line" ;;
esac

echo ""
[ $FAIL -eq 0 ] && echo "bead duplicate wiring verified" \
                || echo "bead duplicate wiring BROKEN"
exit $FAIL
