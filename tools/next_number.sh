#!/bin/bash
# Allocate the next free stati or event number in the caller's band (inc-24cc).
#
#   tools/next_number.sh <FAMILY> <NAME>
#
# FAMILY is STATI or EV. NAME is the define's name (^[A-Z][A-Z0-9_]*$). The
# script prints the issued number on stdout and nothing else there.
#
# Bands live in tools/number_bands.txt. The caller's band is chosen from its
# branch: master or nightly/* use master's row; a row named for the branch wins
# next; else branch.<branch>.incursionBase (recorded by tools/worktree.sh)
# names a branch whose row is used; else master's row.
#
# Counters are per family and band, kept outside the tree in
# $(git rev-parse --git-common-dir)/incursion-numbers/ so every worktree on the
# machine shares them. A tracked counter would conflict at merge -- the fault
# this bead removes. A mkdir lock serialises calls.
#
# Exit codes: 2 bad arguments, 3 lock timeout, 4 band exhausted.
#
# --selftest needs no build and no network.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
NUMBER_BANDS="${INCURSION_NUMBER_BANDS:-$SELF_DIR/number_bands.txt}"
NUMBER_BANDS_PY="$SELF_DIR/number_bands.py"
RES_H="${INCURSION_NUMBERS_RES_H:-inc/Res.h}"

usage() {
    echo "usage: next_number.sh <STATI|EV> <NAME>" >&2
}

# Read the table and set BAND_LOW/BAND_HIGH for <family> <branch>, or return 1
# when no row names that pair.
lookup_band() { # lookup_band <family> <branch> -> 0 found, 1 not
    local family="$1" branch="$2" fam row_branch row_low row_high
    [ -f "$NUMBER_BANDS" ] || { echo "next_number: no band table at $NUMBER_BANDS" >&2; return 2; }
    while read -r fam row_branch row_low row_high _; do
        case "$fam" in ''|\#*) continue ;; esac
        if [ "$fam" = "$family" ] && [ "$row_branch" = "$branch" ]; then
            BAND_LOW="$row_low"
            BAND_HIGH="$row_high"
            return 0
        fi
    done < "$NUMBER_BANDS"
    return 1
}

branch_band() { # branch_band <family> -> sets BAND_BRANCH/BAND_LOW/BAND_HIGH
    local family="$1" branch base
    branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
    BAND_BRANCH="master"
    if [ "$branch" = "master" ] || [ "${branch#nightly/}" != "$branch" ]; then
        BAND_BRANCH="master"
    elif lookup_band "$family" "$branch"; then
        BAND_BRANCH="$branch"
        return 0
    else
        base="$(git config --get "branch.$branch.incursionBase" 2>/dev/null)"
        if [ -n "$base" ] && lookup_band "$family" "$base"; then
            BAND_BRANCH="$base"
            return 0
        fi
        BAND_BRANCH="master"
    fi
    lookup_band "$family" "master" || return 1
    return 0
}

# --- locking ----------------------------------------------------------------

LOCK_DIR=""
LOCK_HELD=0

release_lock() {
    [ "$LOCK_HELD" -eq 1 ] || return 0
    [ "$(cat "$LOCK_DIR/pid" 2>/dev/null)" = "$$" ] || return 0
    rm -rf "$LOCK_DIR"
}

lock_holder_dead() { # lock_holder_dead <pid> -> 0 dead, 1 alive
    local pid="$1" now
    if [ -n "$pid" ]; then
        kill -0 "$pid" 2>/dev/null && return 1 || return 0
    fi
    now="$(date +%s)"
    if [ $((now - $(stat -f %m "$LOCK_DIR" 2>/dev/null || echo "$now"))) -gt 60 ]; then
        return 0
    fi
    return 1
}

acquire_lock() { # acquire_lock <dir>
    local dir="$1" waited=0 holder pid
    LOCK_DIR="$dir/lock"
    if [ "${INCURSION_NUMBERS_NO_LOCK:-}" = "1" ] && [ "${INCURSION_NUMBERS_SELFTEST:-}" = "1" ]; then
        LOCK_HELD=1
        return 0
    fi
    while :; do
        if mkdir "$LOCK_DIR" 2>/dev/null; then
            LOCK_HELD=1
            printf '%s\n' "$$" > "$LOCK_DIR/pid"
            return 0
        fi
        pid="$(cat "$LOCK_DIR/pid" 2>/dev/null)"
        if lock_holder_dead "$pid"; then
            # ponytail: two waiters that both judge the same dead holder can race
            # on this remove; the ceiling is a lock broken twice after a killed
            # run, and the upgrade path is an atomic mv of the lock dir plus a
            # pid re-read.
            rm -rf "$LOCK_DIR" 2>/dev/null
            continue
        fi
        if [ "$waited" -eq 0 ]; then
            echo "next_number: waiting for lock held by pid ${pid:-?}" >&2
        fi
        sleep 0.1
        waited=$((waited + 1))
        if [ "$waited" -ge 300 ]; then
            echo "next_number: lock timeout after 30s; holder pid ${pid:-?}" >&2
            return 3
        fi
    done
}

# --- the counter ------------------------------------------------------------

highest_seen() { # highest_seen <family> <bandbranch> <low> <high>
    local family="$1" bandbranch="$2" low="$3" high="$4" v
    {
        local top
        top="$(git rev-parse --show-toplevel 2>/dev/null)"
        if [ -n "$top" ] && [ -f "$top/inc/Defines.h" ]; then
            cat "$top/inc/Defines.h"
        fi
        if git rev-parse --verify --quiet "${bandbranch}:inc/Defines.h" >/dev/null; then
            git show "${bandbranch}:inc/Defines.h"
        fi
    } | python3 -I "$NUMBER_BANDS_PY" "$family" \
        | awk -v lo="$low" -v hi="$high" '$1>=lo && $1<=hi { if ($1>m) m=$1 } END { print m+0 }'
}

# --- main -------------------------------------------------------------------

selftest() {
    local tmp rc=0 fails=0 pass=0
    tmp="$(mktemp -d "${TMPDIR:-/tmp}/next-number-selftest.XXXXXX")" || return 1
    trap 'rm -rf "$tmp"' RETURN

    local repo="$tmp/repo" numdir="$tmp/nums" bands="$tmp/bands.txt"
    mkdir -p "$repo/inc" || return 1
    cp "$NUMBER_BANDS" "$bands"

    cat > "$repo/inc/Defines.h" <<'DEF'
#define GENERIC_STATI 0
#define SICKNESS 1
#define BLINDNESS 3
#define TG_SOMETHING 7
#define SUBSPELL_FOO 9
#define COMPEL_WALK_STEP_MS 50
#define LAST_STATI 5
#define EV_MOVE 1
#define EV_BREAK 2
#define EV_CMT 301 // note
#define EV_ALIAS EV_MOVE
DEF
    cat > "$repo/inc/Res.h" <<'RES'
struct Status
{
  unsigned int Nature :8;
  signed int Val      :16;
};
RES
    ( cd "$repo" && git init -q && git add -A && \
      git -c user.email=t@t -c user.name=t commit -qm init && \
      git checkout -q -b workb ) || { echo "selftest: repo setup failed"; rm -rf "$tmp"; return 1; }

    export INCURSION_NUMBER_BANDS="$bands"
    export INCURSION_NUMBERS_DIR="$numdir"

    local SCRIPT="$SELF_DIR/next_number.sh"

    # 1. sequential calls: consecutive. The fixture's only in-band STATI member
    #    is none (SICKNESS 1, BLINDNESS 3, LAST_STATI 5 are below the floor), so
    #    the master band 243-255 issues 243 then 244, both within 8 bits.
    local a b
    a="$(cd "$repo" && "$SCRIPT" STATI X 2>/dev/null)"
    b="$(cd "$repo" && "$SCRIPT" STATI Y 2>/dev/null)"
    if [ "$a" = "243" ] && [ "$b" = "244" ]; then pass=$((pass+1)); else
        echo "SELFTEST FAIL: sequential returned '$a','$b' expected 243,244"; fails=$((fails+1)); fi

    # 1b. a define with a trailing comment is counted (defect 1). CMT_STATI 250
    #     and EV_CMT 301 sit inside the bands and MUST push the first issued
    #     numbers above them.
    python3 - "$repo/inc/Defines.h" <<'PY'
import sys
p = sys.argv[1]
lines = open(p).read().splitlines()
out = []
for ln in lines:
    if ln.startswith("#define LAST_STATI"):
        out.append("#define CMT_STATI 250 /* note */")
    out.append(ln)
open(p, "w").write("\n".join(out) + "\n")
PY
    rm -rf "$numdir"; mkdir -p "$numdir"
    a="$(cd "$repo" && "$SCRIPT" STATI CMT_A 2>/dev/null)"
    if [ "$a" = "251" ]; then pass=$((pass+1)); else
        echo "SELFTEST FAIL: trailing-comment stati returned '$a', expected 251"; fails=$((fails+1)); fi
    rm -rf "$numdir"; mkdir -p "$numdir"
    a="$(cd "$repo" && "$SCRIPT" EV EV_NEW 2>/dev/null)"
    if [ "$a" = "302" ]; then pass=$((pass+1)); else
        echo "SELFTEST FAIL: trailing-comment EV returned '$a', expected 302"; fails=$((fails+1)); fi
    git -C "$repo" checkout -q -- inc/Defines.h

    # 2. concurrent: 20 distinct numbers.
    local i nums dup
    rm -rf "$numdir"; mkdir -p "$numdir"
    : > "$tmp/nums.txt"
    for i in $(seq 1 20); do
        ( cd "$repo" && "$SCRIPT" EV EV_N$i 2>/dev/null >> "$tmp/nums.txt" ) &
    done
    wait
    nums="$(sort -n "$tmp/nums.txt")"
    dup="$(printf '%s\n' "$nums" | uniq -d | head -n1)"
    if [ "$(printf '%s\n' "$nums" | wc -l | tr -d ' ')" = "20" ] && [ -z "$dup" ]; then
        pass=$((pass+1))
    else
        echo "SELFTEST FAIL: 20 concurrent calls gave $(printf '%s\n' "$nums" | wc -l | tr -d ' ') numbers, dup='$dup'"; fails=$((fails+1))
    fi

    # 2b. red case: disable the lock and require a duplicate within 5 attempts.
    export INCURSION_NUMBERS_NO_LOCK=1 INCURSION_NUMBERS_SELFTEST=1
    local saw_dup=0 attempt
    for attempt in 1 2 3 4 5; do
        rm -rf "$numdir"; mkdir -p "$numdir"
        : > "$tmp/nums.txt"
        for i in $(seq 1 20); do
            ( cd "$repo" && "$SCRIPT" EV EV_N$((attempt*100+i)) 2>/dev/null >> "$tmp/nums.txt" ) &
        done
        wait
        if [ -n "$(sort -n "$tmp/nums.txt" | uniq -d | head -n1)" ]; then
            saw_dup=1; break
        fi
    done
    unset INCURSION_NUMBERS_NO_LOCK INCURSION_NUMBERS_SELFTEST
    if [ "$saw_dup" -eq 1 ]; then pass=$((pass+1)); else
        echo "SELFTEST FAIL: red case (no lock) never produced a duplicate in 5 attempts"; fails=$((fails+1)); fi

    # 3. a full band exits 4. Use a scratch table with a one-wide band and drive
    #    the counter above it. The band high 250 is within 8 bits, so the width
    #    rule does not fire and the full-band refusal does.
    local fbands="$tmp/fullbands.txt"
    {
        echo "STATI master 250 250"
        echo "EV master 301 499"
    } > "$fbands"
    export INCURSION_NUMBER_BANDS="$fbands"
    rm -rf "$numdir"; mkdir -p "$numdir"
    printf '250\n' > "$numdir/STATI.master"
    ( cd "$repo" && "$SCRIPT" STATI Z >/dev/null 2>&1 )
    rc=$?
    if [ "$rc" -eq 4 ]; then pass=$((pass+1)); else
        echo "SELFTEST FAIL: full band exited $rc, expected 4"; fails=$((fails+1)); fi

    # 3b. the width rule: an 8-bit Res.h with a scratch band STATI master 250 300
    #     and the counter at 255 must refuse 256 with exit 4, issuing nothing.
    local wbands="$tmp/widthbands.txt"
    {
        echo "STATI master 250 300"
        echo "EV master 301 499"
    } > "$wbands"
    export INCURSION_NUMBER_BANDS="$wbands"
    rm -rf "$numdir"; mkdir -p "$numdir"
    printf '255\n' > "$numdir/STATI.master"
    ( cd "$repo" && "$SCRIPT" STATI W >/dev/null 2>&1 )
    rc=$?
    if [ "$rc" -eq 4 ] && [ ! -f "$numdir/issued.log" ]; then pass=$((pass+1)); else
        echo "SELFTEST FAIL: width refusal exited $rc, expected 4 (issued.log present: $([ -f "$numdir/issued.log" ] && echo yes || echo no))"; fails=$((fails+1)); fi
    export INCURSION_NUMBER_BANDS="$bands"

    # 4. a stale lock (dead pid) is broken and the call succeeds.
    rm -rf "$numdir"; mkdir -p "$numdir/lock"
    printf '999999\n' > "$numdir/lock/pid"
    a="$(cd "$repo" && "$SCRIPT" EV EV_STALE 2>/dev/null)"
    if [ -n "$a" ]; then pass=$((pass+1)); else
        echo "SELFTEST FAIL: stale lock not broken"; fails=$((fails+1)); fi

    # 4b. a lock with no pid file yet and a fresh mtime is NOT broken (defect
    #     2): a second caller must wait, not steal the live lock. Break the lock
    #     afterwards and require the call to finish.
    rm -rf "$numdir"; mkdir -p "$numdir/lock"
    ( cd "$repo" && "$SCRIPT" EV EV_NOPID 2>/dev/null > "$tmp/nopid.out" ) &
    local nopid_pid=$!
    sleep 1
    if kill -0 "$nopid_pid" 2>/dev/null; then pass=$((pass+1)); else
        echo "SELFTEST FAIL: no-pid fresh lock was broken immediately"; fails=$((fails+1)); fi
    rmdir "$numdir/lock" 2>/dev/null || rm -rf "$numdir/lock"
    local waited_nopid=0
    while kill -0 "$nopid_pid" 2>/dev/null && [ "$waited_nopid" -lt 30 ]; do
        sleep 0.1; waited_nopid=$((waited_nopid+1))
    done
    if [ -s "$tmp/nopid.out" ]; then pass=$((pass+1)); else
        echo "SELFTEST FAIL: call did not succeed after the no-pid lock was released"; fails=$((fails+1)); fi
    wait "$nopid_pid" 2>/dev/null

    # 5b. the worktree's Defines.h is found from a subdirectory (defect 3):
    #     add a band member only in the working-tree file, call from $repo/inc,
    #     and require a number above it. The member sits before LAST_STATI so
    #     the STATI family sees it.
    python3 - "$repo/inc/Defines.h" <<'PY'
import sys
p = sys.argv[1]
lines = open(p).read().splitlines()
out = []
for ln in lines:
    if ln.startswith("#define LAST_STATI"):
        out.append("#define CMT_SUB 250 /* sub */")
    out.append(ln)
open(p, "w").write("\n".join(out) + "\n")
PY
    rm -rf "$numdir"; mkdir -p "$numdir"
    a="$(cd "$repo/inc" && "$SCRIPT" STATI SUBMEMBER 2>/dev/null)"
    if [ "$a" = "251" ]; then pass=$((pass+1)); else
        echo "SELFTEST FAIL: subdirectory call returned '$a', expected 251"; fails=$((fails+1)); fi
    git -C "$repo" checkout -q -- inc/Defines.h

    # 5. branch.<name>.incursionBase=inc-pu6v selects the inc-pu6v band; an
    #    unknown branch with no base record gets master's.
    rm -rf "$numdir"
    ( cd "$repo" && git config branch.workb.incursionBase inc-pu6v )
    a="$(cd "$repo" && "$SCRIPT" EV EV_BASE 2>/dev/null)"
    if [ "$a" = "221" ]; then pass=$((pass+1)); else
        echo "SELFTEST FAIL: base-branch band returned '$a', expected 221"; fails=$((fails+1)); fi
    ( cd "$repo" && git config --unset branch.workb.incursionBase )
    a="$(cd "$repo" && "$SCRIPT" EV EV_NOBASE 2>/dev/null)"
    if [ "$a" = "302" ]; then pass=$((pass+1)); else
        echo "SELFTEST FAIL: unknown branch returned '$a', expected 302"; fails=$((fails+1)); fi

    # 6. invalid FAMILY or NAME exits 2.
    ( cd "$repo" && "$SCRIPT" NOPE X >/dev/null 2>&1 ); rc=$?
    if [ "$rc" -eq 2 ]; then pass=$((pass+1)); else
        echo "SELFTEST FAIL: bad family exited $rc, expected 2"; fails=$((fails+1)); fi
    ( cd "$repo" && "$SCRIPT" STATI bad_name >/dev/null 2>&1 ); rc=$?
    if [ "$rc" -eq 2 ]; then pass=$((pass+1)); else
        echo "SELFTEST FAIL: bad name exited $rc, expected 2"; fails=$((fails+1)); fi

    unset INCURSION_NUMBER_BANDS INCURSION_NUMBERS_DIR
    rm -rf "$tmp"
    trap - RETURN
    if [ "$fails" -ne 0 ]; then
        echo "selftest: $pass passed, $fails failed"
        return 1
    fi
    echo "selftest: $pass passed"
    return 0
}

if [ "${1:-}" = "--selftest" ]; then
    selftest
    exit $?
fi

FAMILY="${1:-}"
NAME="${2:-}"

case "$FAMILY" in
    STATI|EV) ;;
    *) usage >&2; echo "next_number: FAMILY must be STATI or EV, got '${FAMILY}'" >&2; exit 2 ;;
esac

case "$NAME" in
    '') usage >&2; echo "next_number: NAME is required" >&2; exit 2 ;;
esac
case "$NAME" in
    *[!A-Z0-9_]*|[!A-Z]*) usage >&2; echo "next_number: NAME '$NAME' must match ^[A-Z][A-Z0-9_]*$" >&2; exit 2 ;;
esac

branch_band "$FAMILY" || { echo "next_number: no $FAMILY band row for master" >&2; exit 2; }

STATE_DIR="${INCURSION_NUMBERS_DIR:-$(git rev-parse --git-common-dir)/incursion-numbers}"
case "$STATE_DIR" in
    /*) ;;
    *) STATE_DIR="$(cd "$(dirname "$STATE_DIR")" 2>/dev/null && pwd)/$(basename "$STATE_DIR")" ;;
esac
mkdir -p "$STATE_DIR" || { echo "next_number: cannot create state dir $STATE_DIR" >&2; exit 1; }

acquire_lock "$STATE_DIR"
rc=$?
if [ "$rc" -ne 0 ]; then
    exit "$rc"
fi
trap release_lock EXIT

COUNTER_FILE="$STATE_DIR/$FAMILY.$BAND_BRANCH"
if [ -f "$COUNTER_FILE" ]; then
    counter="$(cat "$COUNTER_FILE" 2>/dev/null)"
else
    counter=""
fi
case "$counter" in
    ''|*[!0-9]*) counter=$((BAND_LOW - 1)) ;;
esac

seen="$(highest_seen "$FAMILY" "$BAND_BRANCH" "$BAND_LOW" "$BAND_HIGH")"
[ -n "$seen" ] || seen=0

next="$counter"
[ "$seen" -gt "$next" ] && next="$seen"
next=$((next + 1))

# A STATI MUST fit the branch's Nature field (spec "Size limits"): a master
# stati above 255 is silently truncated. Read N from the worktree's inc/Res.h.
if [ "$FAMILY" = "STATI" ]; then
    nature_width="$(
        top="$(git rev-parse --show-toplevel 2>/dev/null)"
        [ -n "$top" ] && [ -f "$top/$RES_H" ] && cat "$top/$RES_H"
    )"
    width="$(printf '%s\n' "$nature_width" | python3 -I "$NUMBER_BANDS_PY" --nature-width 2>/dev/null)"
    case "$width" in
        ''|*[!0-9]*)
            echo "next_number: cannot measure the Nature width in $RES_H; no number issued" >&2
            exit 4
            ;;
    esac
    if [ "$next" -gt "$((2 ** width - 1))" ]; then
        echo "next_number: STATI $next exceeds the ${width}-bit Nature field in $RES_H (max $((2 ** width - 1))); no number issued" >&2
        exit 4
    fi
fi

if [ "$next" -gt "$BAND_HIGH" ]; then
    echo "next_number: $FAMILY band $BAND_BRANCH ($BAND_LOW-$BAND_HIGH) is full; no number issued" >&2
    exit 4
fi

tmpfile="$STATE_DIR/.$FAMILY.$BAND_BRANCH.tmp.$$"
printf '%s\n' "$next" > "$tmpfile" || { rm -f "$tmpfile"; echo "next_number: cannot write counter" >&2; exit 1; }
mv -f "$tmpfile" "$COUNTER_FILE" || { rm -f "$tmpfile"; echo "next_number: cannot replace counter" >&2; exit 1; }

printf '%s %s %s %s %s\n' "$FAMILY" "$next" "$NAME" "$BAND_BRANCH" \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$STATE_DIR/issued.log"

printf '%s\n' "$next"
exit 0
