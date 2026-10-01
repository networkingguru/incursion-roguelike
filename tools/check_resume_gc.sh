#!/usr/bin/env bash
# gate: cheap
# gate-serial: waits on a detached forget under a wall-clock poll (wait_detached); CPU load could flip it
#
# Does tools/resume_gc.sh delete exactly the right bd resume notes, archive
# them first, fail safe on the entrypoint, and warn before it is asked
# whether it is safe to clear? (bd inc-gs36)
#
#   tools/check_resume_gc.sh               run every assertion
#   tools/check_resume_gc.sh --prove-red   break the rule and demand red
#
# IT NEVER CALLS THE REAL bd. A stub `bd` is first on PATH: it serves a fixed
# memories object from a temp file and records each `forget <key>`, removing
# that key from the file exactly as bd would. RESUME_GC_ROOT points the
# archive and log at a temp dir, and RESUME_GC_TODAY pins the date. Nothing
# in the real repository is read or written for memory state.
#
# Exit: 0 pass, 1 fail, 2 could not measure.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GC="$ROOT/tools/resume_gc.sh"

TMP="$(mktemp -d)" || exit 2
trap 'chmod -R u+rwX "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT

FAIL=0
ok()  { echo "OK    $1"; }
bad() { echo "FAIL  $1"; FAIL=1; }

TODAY="2026-09-30"
OLD1="resume-2026-09-22-a"
OLD2="resume-2026-08-01"
EDGE="resume-2026-09-23-b"
TODAYKEY="resume-2026-09-30"
NONRESUME="agents-md-x"
INVALID="resume-2026-02-30-x"
UNIFIED="resume-unified-light"

make_store() {
    python3 - "$1" <<'PY'
import json, sys
store = {
    "resume-2026-09-22-a": "old note a " + "A" * 130,
    "resume-2026-08-01": "old note aug",
    "resume-2026-09-23-b": "edge note b",
    "resume-2026-09-30": "today note",
    "resume-unified-light": "keep me please",
    "resume-2026-02-30-x": "invalid feb 30",
    "agents-md-x": "not a resume note",
}
json.dump(store, open(sys.argv[1], "w"))
PY
}

# A stub bd. `memories --json` cats the store, appending one line per call to
# the memories-call log; `forget <key>` appends the key to the forget log and
# removes it from the store. Anything else: silence.
write_stub() {
    local dir="$1"
    cat > "$dir/bd" <<STUB
#!/usr/bin/env bash
store="$TMP/store.json"
forgot="$TMP/forgot.txt"
memcalls="$TMP/memcalls.txt"
args=("\$@")
cmd=""
key=""
i=0
while [ \$i -lt \${#args[@]} ]; do
    a="\${args[\$i]}"
    case "\$a" in
        -C) i=\$((i+1)) ;;
        memories) cmd="memories" ;;
        forget) cmd="forget"; i=\$((i+1)); key="\${args[\$i]}" ;;
    esac
    i=\$((i+1))
done
if [ "\$cmd" = "memories" ]; then
    printf '%s\n' "memories" >> "\$memcalls"
    cat "\$store"
    exit 0
fi
if [ "\$cmd" = "forget" ]; then
    printf '%s\n' "\$key" >> "\$forgot"
    python3 - "\$store" "\$key" <<'PY'
import json, sys
path, key = sys.argv[1], sys.argv[2]
try:
    d = json.load(open(path))
except Exception:
    d = {}
d.pop(key, None)
json.dump(d, open(path, "w"))
PY
    exit 0
fi
exit 0
STUB
    chmod +x "$dir/bd"
}

setup() {
    rm -rf "$TMP/bin" "$TMP/root" "$TMP/store.json" "$TMP/forgot.txt" "$TMP/memcalls.txt"
    mkdir -p "$TMP/bin" "$TMP/root"
    make_store "$TMP/store.json"
    : > "$TMP/forgot.txt"
    : > "$TMP/memcalls.txt"
    write_stub "$TMP/bin"
}

gc() { # gc [args...] -- with stub bd and temp root
    PATH="$TMP/bin:$PATH" RESUME_GC_ROOT="$TMP/root" RESUME_GC_TODAY="$TODAY" \
        bash "$GC" "$@"
}

forgot_keys() { sort "$TMP/forgot.txt" 2>/dev/null | grep -v '^$' || true; }

# Number of `bd memories` calls recorded by the stub.
memories_calls() { wc -l < "$TMP/memcalls.txt" 2>/dev/null | tr -d ' ' || echo 0; }

# Wait until the detached --run has forgotten the expected number of keys, up
# to ~5s. It forgets the keys one after the other; one quiet 0.1 s poll is not
# proof it is done, so wait for the count. (bd inc-2gl7)
wait_detached() {
    local want="$1" i cur n
    for i in $(seq 1 50); do
        cur="$(forgot_keys)"
        n="$(printf '%s' "$cur" | grep -c . || true)"
        [ "$n" -ge "$want" ] && return 0
        sleep 0.1
    done
    return 0
}

run_suite() {
    FAIL=0

    # --- a. --list prints exactly the two old keys ------------------------
    setup
    got="$(gc --list | sort)"
    want="$(printf '%s\n%s\n' "$OLD2" "$OLD1" | sort)"
    if [ "$got" = "$want" ]; then
        ok "a. --list prints exactly the two old keys"
    else
        bad "a. --list wrong: got [$(printf '%s' "$got" | tr '\n' ' ')]"
    fi

    # --- b. --hook-end, cli transcript: two forgotten, archived ----------
    setup
    cat > "$TMP/cli.jsonl" <<'EOF'
{"type":"summary","foo":1}
{"type":"user","entrypoint":"cli","message":"hi"}
EOF
    printf '{"transcript_path":"%s","reason":"exit"}' "$TMP/cli.jsonl" \
        | gc --hook-end >/dev/null 2>&1
    wait_detached 2
    gotf="$(forgot_keys)"
    wantf="$(printf '%s\n%s\n' "$OLD2" "$OLD1" | sort)"
    if [ "$gotf" = "$wantf" ]; then
        ok "b1. cli transcript forgets exactly the two old keys"
    else
        bad "b1. cli forget wrong: got [$(printf '%s' "$gotf" | tr '\n' ' ')]"
    fi

    remaining="$(python3 -c 'import json,sys; print("\n".join(sorted(json.load(open(sys.argv[1])))))' "$TMP/store.json")"
    if grep -qx "$OLD1" <<< "$remaining" || grep -qx "$OLD2" <<< "$remaining"; then
        bad "b2. an old key survived in the store"
    else
        ok "b2. both old keys removed from the store"
    fi

    default_arch="$TMP/root/logs/resume-gc-archive.jsonl"
    if [ -f "$default_arch" ]; then
        missing=""
        for k in "$OLD1" "$OLD2"; do
            python3 - "$default_arch" "$k" <<'PY' || missing="$missing $k"
import json, sys
path, key = sys.argv[1], sys.argv[2]
found = None
for line in open(path):
    try:
        d = json.loads(line)
    except Exception:
        continue
    if d.get("key") == key:
        found = d
if not found:
    sys.exit(1)
if found.get("rule") != "resume-gc 7d":
    sys.exit(1)
if not isinstance(found.get("value"), str) or not found["value"]:
    sys.exit(1)
if not found.get("deleted_at"):
    sys.exit(1)
PY
        done
        if [ -z "$missing" ]; then
            ok "b3. both keys archived with full text and metadata"
        else
            bad "b3. archive incomplete for:$missing"
        fi
    else
        bad "b3. archive file missing: $default_arch"
    fi

    # --- c. sdk-cli and missing transcript forget nothing ----------------
    setup
    cat > "$TMP/sdk.jsonl" <<'EOF'
{"type":"user","entrypoint":"sdk-cli"}
EOF
    printf '{"transcript_path":"%s","reason":"exit"}' "$TMP/sdk.jsonl" \
        | gc --hook-end >/dev/null 2>&1
    sleep 0.5
    if [ -z "$(forgot_keys)" ]; then
        ok "c1. sdk-cli transcript forgets nothing"
    else
        bad "c1. sdk-cli forgot: $(forgot_keys | tr '\n' ' ')"
    fi

    setup
    printf '{"transcript_path":"%s","reason":"exit"}' "$TMP/does-not-exist" \
        | gc --hook-end >/dev/null 2>&1
    sleep 0.5
    if [ -z "$(forgot_keys)" ] && [ -z "$(gc --list)" ]; then
        bad "c2. --list unexpectedly empty"
    elif [ -z "$(forgot_keys)" ]; then
        ok "c2. missing transcript forgets nothing"
    else
        bad "c2. missing transcript forgot: $(forgot_keys | tr '\n' ' ')"
    fi

    # --- d. --hook-prompt matches and ignores ---------------------------
    setup
    match_phrasings=(
        "safe to clear?"
        "safe to clear"
        "ok to clear"
        "okay to clear?"
        "is it safe to /clear"
        "can I clear"
        "can i clear now"
        "good to clear?"
        "fine to clear"
    )
    dm=0
    for p in "${match_phrasings[@]}"; do
        out="$(printf '%s' "{\"prompt\":\"$p\"}" | gc --hook-prompt 2>/dev/null)"
        ctx="$(printf '%s' "$out" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(1)
o = d.get("hookSpecificOutput", {})
if o.get("hookEventName") != "UserPromptSubmit":
    sys.exit(1)
sys.stdout.write(o.get("additionalContext", ""))
' 2>/dev/null)"
        [ -n "$ctx" ] || { dm=1; echo "  (no ctx for: $p)"; continue; }
        grep -q "$OLD1" <<< "$ctx" || dm=1
        grep -q "$OLD2" <<< "$ctx" || dm=1
        grep -q "$EDGE" <<< "$ctx" && dm=1
        grep -q "$UNIFIED" <<< "$ctx" && dm=1
        grep -qi "resume-gc-archive.jsonl" <<< "$ctx" || dm=1
        grep -qF "Show this list to the user in your answer." <<< "$ctx" || dm=1
    done
    if [ "$dm" -eq 0 ]; then
        ok "d1. every matching phrasing names exactly the two old keys"
    else
        bad "d1. a matching phrasing was wrong"
    fi

    nonmatch=(
        "clear the cache"
        "is that clear?"
        "clear out logs/"
        "look to clear the logs"
    )
    dn=0
    for p in "${nonmatch[@]}"; do
        out="$(printf '%s' "{\"prompt\":\"$p\"}" | gc --hook-prompt 2>/dev/null)"
        [ -z "$out" ] || { dn=1; echo "  (fired on: $p)"; }
    done
    if [ "$dn" -eq 0 ]; then
        ok "d2. no unrelated 'clear' phrasing fires"
    else
        bad "d2. a non-matching phrasing fired"
    fi

    # empty list message
    setup
    python3 - "$TMP/store.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
for k in list(d):
    if k.startswith("resume-"):
        d.pop(k)
json.dump(d, open(sys.argv[1], "w"))
PY
    out="$(printf '%s' '{"prompt":"safe to clear?"}' | gc --hook-prompt 2>/dev/null)"
    if grep -qi "no resume notes will be deleted" <<< "$out"; then
        ok "d3. empty list says so"
    else
        bad "d3. empty list message missing"
    fi

    # --- e. archive failure forgets nothing -----------------------------
    setup
    cat > "$TMP/cli.jsonl" <<'EOF'
{"type":"user","entrypoint":"cli"}
EOF
    mkdir -p "$TMP/root/logs"
    chmod 500 "$TMP/root/logs"
    printf '{"transcript_path":"%s","reason":"exit"}' "$TMP/cli.jsonl" \
        | gc --hook-end >/dev/null 2>&1
    sleep 0.8
    chmod 700 "$TMP/root/logs"
    if [ -z "$(forgot_keys)" ]; then
        ok "e. unwritable archive forgets nothing"
    else
        bad "e. archive failure still forgot: $(forgot_keys | tr '\n' ' ')"
    fi

    # --- f. bd memories is read exactly once per invocation --------------
    setup
    gc --list >/dev/null 2>&1
    n="$(memories_calls)"
    if [ "$n" -eq 1 ]; then
        ok "f1. --list reads bd memories exactly once"
    else
        bad "f1. --list read bd memories $n times, want 1"
    fi

    setup
    printf '{"prompt":"safe to clear?"}' | gc --hook-prompt >/dev/null 2>&1
    n="$(memories_calls)"
    if [ "$n" -eq 1 ]; then
        ok "f2. --hook-prompt reads bd memories exactly once"
    else
        bad "f2. --hook-prompt read bd memories $n times, want 1"
    fi

    setup
    gc --run >/dev/null 2>&1
    n="$(memories_calls)"
    if [ "$n" -eq 1 ]; then
        ok "f3. --run reads bd memories exactly once"
    else
        bad "f3. --run read bd memories $n times, want 1"
    fi
}

# --- --prove-red ----------------------------------------------------------
if [ "${1:-}" = "--prove-red" ]; then
    red_one() { # red_one <fault> <label>
        local fault="$1" label="$2" out rc
        echo "--- mutation: $label ---"
        out="$(RESUME_GC_FAULT="$fault" bash "$ROOT/tools/check_resume_gc.sh")"
        rc=$?
        echo "$out" | grep -E '^(OK|FAIL|red|GREEN|RED)' || true
        if [ "$rc" -ne 0 ]; then
            echo "PASS (as intended): check goes RED under $label"
            return 0
        fi
        echo "FAIL: check stayed GREEN under $label"
        return 1
    }
    st=0
    red_one "off-by-one" "RESUME_GC_FAULT=off-by-one (cutoff <=)" || st=1
    red_one "ignore-entrypoint" "RESUME_GC_FAULT=ignore-entrypoint" || st=1
    red_one "per-key-read" "RESUME_GC_FAULT=per-key-read (read bd per key)" || st=1
    [ "$st" -eq 0 ] && echo "check_resume_gc.sh --prove-red: all three mutations went red"
    exit "$st"
fi

run_suite

if [ "$FAIL" -eq 0 ]; then
    echo "GREEN: check_resume_gc.sh, all assertions"
    exit 0
else
    echo "RED: check_resume_gc.sh, at least one assertion failed"
    exit 1
fi
