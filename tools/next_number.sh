#!/bin/bash
# Allocate the next free number in the caller's band for a family (inc-24cc).
#
#   tools/next_number.sh <FAMILY> <NAME>
#
# FAMILY is any family with a row in tools/number_bands.txt (STATI, EV, and the
# god message families MSG_SINGLE, MSG_BADSAC, MSG_BLESSING, MSG_CUSTOM,
# MSG_AID, MSG_FALL, MSG_HATE, MSG_SHEET). NAME is the define's name
# (^[A-Z][A-Z0-9_]*$). The script prints the issued number on stdout and nothing
# else there; on a successful issue it also prints one line "band: <BAND_BRANCH>
# <LOW>-<HIGH>" to stderr.
#
# Bands live in tools/number_bands.txt. The caller's band is chosen from its
# branch, in order: master or nightly/* use master's row; a row named for the
# branch wins next; else follow the branch.<branch>.incursionBase chain
# (recorded by tools/worktree.sh) b -> base1 -> base2 ..., taking the first
# branch that is master or has a row (stop after 10 hops or on a repeat); else
# refuse with exit 5. A number is issued only when the band can be proved.
#
# Counters are per family and band, kept outside the tree in
# $(git rev-parse --git-common-dir)/incursion-numbers/ so every worktree on the
# machine shares them. A tracked counter would conflict at merge -- the fault
# this bead removes. Two locks serialise calls: /usr/bin/lockf holds a kernel
# flock on $STATE_DIR/alloc.lock for the whole run (the kernel drops it when the
# holder dies, so there is no stale lock to break, and two waiters cannot both
# judge the same dead holder), and the older mkdir lock inside the child
# additionally excludes worktrees on older branches that still run the old
# script and know only the mkdir lock. No number is issued from the main worktree
# unless the branch is nightly/*: that checkout belongs to no bead, so the script
# refuses and names the fix.
#
# Exit codes: 1 cannot create or resolve the state dir, 2 bad arguments or no
# master band row, 3 lock failure (timeout, missing lockf, INCURSION_NUMBERS_LOCKED
# set but the lock not held, allocation child died by a signal, cannot create the
# lock file), 4 band exhausted or number out of width, 5 refused, band cannot be
# proved (main worktree off nightly/*, detached HEAD, outside a repo, no band).
#
# --selftest needs no build and no network.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
NUMBER_BANDS="${INCURSION_NUMBER_BANDS:-$SELF_DIR/number_bands.txt}"
NUMBER_BANDS_PY="$SELF_DIR/number_bands.py"
RES_H="${INCURSION_NUMBERS_RES_H:-inc/Res.h}"

usage() {
    echo "usage: next_number.sh <STATI|EV|MSG_SINGLE|MSG_BADSAC|MSG_BLESSING|MSG_CUSTOM|MSG_AID|MSG_FALL|MSG_HATE|MSG_SHEET> <NAME>" >&2
}

# List the families that have a row in the band table, one per line, ignoring
# comments. Used to validate FAMILY and to build the refusal message.
known_families() {
    [ -f "$NUMBER_BANDS" ] || return 0
    while read -r fam _; do
        case "$fam" in ''|\#*) continue ;; esac
        printf '%s\n' "$fam"
    done < "$NUMBER_BANDS" | sort -u
}

# 0 when <family> names a row in the band table, 1 otherwise.
family_known() { # family_known <family>
    grep -qxF "$1" <<< "$(known_families)"
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
    # 0 found; 1 no master row; 5 band cannot be proved.
    local family="$1" branch cand base hops seen
    branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
    if [ "$branch" = "master" ] || [ "${branch#nightly/}" != "$branch" ]; then
        BAND_BRANCH="master"
    elif lookup_band "$family" "$branch"; then
        BAND_BRANCH="$branch"
        return 0
    else
        # Follow the incursionBase chain. Take the first branch that is master
        # or has a row for this family. Stop after 10 hops or on a repeat.
        cand="$branch"
        seen=" "
        hops=0
        while [ "$hops" -lt 10 ]; do
            base="$(git config --get "branch.$cand.incursionBase" 2>/dev/null)"
            [ -n "$base" ] || break
            case "$seen" in
                *" $base "*) break ;;
            esac
            seen="$seen$base "
            if [ "$base" = "master" ]; then
                BAND_BRANCH="master"
                lookup_band "$family" "master" || return 1
                return 0
            fi
            if lookup_band "$family" "$base"; then
                BAND_BRANCH="$base"
                return 0
            fi
            cand="$base"
            hops=$((hops + 1))
        done
        echo "next_number: branch '$branch' has no band and no recorded base; record one with: git config branch.$branch.incursionBase <base-branch>" >&2
        return 5
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
            # on this remove -- but only a caller on an older branch, still
            # running the old script with no lockf wrap around it, can be in this
            # path against another old-script caller; every caller that carries
            # this script is already serialised by the outer lockf, so the race is
            # removed once every branch carries this script. The upgrade path
            # remains an atomic mv of the lock dir plus a pid re-read.
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
    unset INCURSION_NUMBERS_LOCKED INCURSION_NUMBERS_NO_LOCK INCURSION_NUMBERS_SELFTEST
    tmp="$(mktemp -d "${TMPDIR:-/tmp}/next-number-selftest.XXXXXX")" || return 1
    trap 'rm -rf "$tmp"' RETURN

    local main="$tmp/main" repo="$tmp/repo" numdir="$tmp/nums" bands="$tmp/bands.txt"
    mkdir -p "$main/inc" || return 1
    cp "$NUMBER_BANDS" "$bands"

    cat > "$main/inc/Defines.h" <<'DEF'
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
#define MSG_BAND_SINGLE 1000
#define MSG_BAND_END 9000
#define MSG_BAND_SIZE 1000
#define MSG_BAND_ZZZ 1900
#define MSG_FOO 1005
#define MSG_BAR 5000
#define MSG_BLASTNAME 200
DEF
    cat > "$main/inc/Res.h" <<'RES'
struct Status
{
  unsigned int Nature :8;
  signed int Val      :16;
};
RES
    # $repo must be a LINKED worktree, not the main one, so the main-worktree
    # refusal does not fire for the existing cases. Build the main worktree on
    # master, commit, then add $repo as a linked worktree on branch workb.
    ( cd "$main" && git init -q -b master && git add -A && \
      git -c user.email=t@t -c user.name=t commit -qm init ) || { echo "selftest: repo setup failed"; rm -rf "$tmp"; return 1; }
    git -C "$main" worktree add -q -b workb "$repo" || { echo "selftest: worktree add failed"; rm -rf "$tmp"; return 1; }
    # workb is a master-based bead branch: record its base so the band chain
    # resolves to master's row (defect 3 replaces the old silent fall-through).
    ( cd "$repo" && git config branch.workb.incursionBase master )
    local main_branch
    main_branch="$(git -C "$main" rev-parse --abbrev-ref HEAD)"

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
    #    unknown branch with no base record now refuses (defect 3): exit 5,
    #    empty stdout.
    rm -rf "$numdir"
    ( cd "$repo" && git config branch.workb.incursionBase inc-pu6v )
    a="$(cd "$repo" && "$SCRIPT" EV EV_BASE 2>/dev/null)"
    if [ "$a" = "221" ]; then pass=$((pass+1)); else
        echo "SELFTEST FAIL: base-branch band returned '$a', expected 221"; fails=$((fails+1)); fi
    ( cd "$repo" && git config --unset branch.workb.incursionBase )
    a="$(cd "$repo" && "$SCRIPT" EV EV_NOBASE 2>/dev/null)"; rc=$?
    if [ "$rc" -eq 5 ] && [ -z "$a" ]; then pass=$((pass+1)); else
        echo "SELFTEST FAIL: unknown branch exited $rc, stdout='$a', expected exit 5, empty stdout"; fails=$((fails+1)); fi
    # Restore workb's base to master so later cases see a master-based branch.
    ( cd "$repo" && git config branch.workb.incursionBase master )

    # 6. invalid FAMILY or NAME exits 2.
    ( cd "$repo" && "$SCRIPT" NOPE X >/dev/null 2>&1 ); rc=$?
    if [ "$rc" -eq 2 ]; then pass=$((pass+1)); else
        echo "SELFTEST FAIL: bad family exited $rc, expected 2"; fails=$((fails+1)); fi
    ( cd "$repo" && "$SCRIPT" STATI bad_name >/dev/null 2>&1 ); rc=$?
    if [ "$rc" -eq 2 ]; then pass=$((pass+1)); else
        echo "SELFTEST FAIL: bad name exited $rc, expected 2"; fails=$((fails+1)); fi

    # 7. main worktree on master refuses: exit 5, empty stdout, and neither the
    #    counter nor issued.log is created or changed.
    rm -rf "$numdir"; mkdir -p "$numdir"
    printf '5\n' > "$numdir/STATI.master"
    local before_counter after_counter
    before_counter="$(cat "$numdir/STATI.master")"
    a="$(cd "$main" && "$SCRIPT" STATI X 2>/dev/null)"; rc=$?
    after_counter="$(cat "$numdir/STATI.master")"
    if [ "$rc" -eq 5 ] && [ -z "$a" ] && \
       [ "$before_counter" = "$after_counter" ] && [ ! -f "$numdir/issued.log" ]; then
        pass=$((pass+1))
    else
        echo "SELFTEST FAIL: main-worktree refusal exited $rc, stdout='$a', counter $before_counter->$after_counter, issued.log present: $([ -f "$numdir/issued.log" ] && echo yes || echo no)"; fails=$((fails+1))
    fi

    # 7b. main worktree on a nightly/* branch is allowed to issue.
    ( cd "$main" && git checkout -q -b nightly/x ) || { echo "selftest: nightly branch failed"; fails=$((fails+1)); }
    rm -rf "$numdir"; mkdir -p "$numdir"
    a="$(cd "$main" && "$SCRIPT" EV EV_NIGHT 2>/dev/null)"; rc=$?
    if [ "$rc" -eq 0 ] && [ -n "$a" ]; then pass=$((pass+1)); else
        echo "SELFTEST FAIL: nightly main-worktree call exited $rc, stdout='$a'"; fails=$((fails+1)); fi
    ( cd "$main" && git checkout -q "$main_branch" ) || true

    # 7c. linked worktree issues, stdout is digits only, and stderr carries the
    #     band line.
    rm -rf "$numdir"; mkdir -p "$numdir"
    a="$(cd "$repo" && "$SCRIPT" STATI LW 2>"$tmp/lw.err")"; rc=$?
    if [ "$rc" -eq 0 ] && [ -n "$a" ] && [ -z "${a//[0-9]/}" ] && \
       grep -qE '^band: [^ ]+ [0-9]+-[0-9]+$' "$tmp/lw.err"; then
        pass=$((pass+1))
    else
        echo "SELFTEST FAIL: linked worktree exited $rc, stdout='$a', stderr='$(cat "$tmp/lw.err")'"; fails=$((fails+1))
    fi

    # 8a. cwd outside any repo refuses: exit 5, empty stdout, no issued.log, and
    #     stderr names the worktree fix (defect 1: refuse when git gives no
    #     answer, rather than fall through).
    local outside
    outside="$(mktemp -d "${TMPDIR:-/tmp}/next-number-outside.XXXXXX")"
    rm -rf "$numdir"; mkdir -p "$numdir"
    a="$(cd "$outside" && "$SCRIPT" STATI OUT 2>"$tmp/out.err")"; rc=$?
    if [ "$rc" -eq 5 ] && [ -z "$a" ] && [ ! -f "$numdir/issued.log" ] && \
       grep -q 'not inside an Incursion worktree' "$tmp/out.err"; then
        pass=$((pass+1))
    else
        echo "SELFTEST FAIL: outside-repo exited $rc, stdout='$a', stderr='$(cat "$tmp/out.err")', issued.log present: $([ -f "$numdir/issued.log" ] && echo yes || echo no), expected exit 5, empty stdout, 'not inside an Incursion worktree'"; fails=$((fails+1))
    fi
    rm -rf "$outside"

    # 8b. detached HEAD in the linked worktree refuses: exit 5, empty stdout;
    #     restore the branch afterwards.
    rm -rf "$numdir"; mkdir -p "$numdir"
    ( cd "$repo" && git checkout -q --detach ) || { echo "selftest: detach in repo failed"; fails=$((fails+1)); }
    a="$(cd "$repo" && "$SCRIPT" STATI DET 2>/dev/null)"; rc=$?
    if [ "$rc" -eq 5 ] && [ -z "$a" ]; then pass=$((pass+1)); else
        echo "SELFTEST FAIL: linked detached HEAD exited $rc, stdout='$a', expected exit 5, empty stdout"; fails=$((fails+1)); fi
    ( cd "$repo" && git checkout -q workb ) || { echo "selftest: restore repo branch failed"; fails=$((fails+1)); }

    # 8c. detached HEAD in the main worktree refuses: exit 5, and stderr must
    #     NOT contain "branch 'HEAD'".
    rm -rf "$numdir"; mkdir -p "$numdir"
    ( cd "$main" && git checkout -q --detach ) || { echo "selftest: detach in main failed"; fails=$((fails+1)); }
    a="$(cd "$main" && "$SCRIPT" STATI DETM 2>"$tmp/detm.err")"; rc=$?
    if [ "$rc" -eq 5 ] && [ -z "$a" ] && ! grep -q "branch 'HEAD'" "$tmp/detm.err"; then
        pass=$((pass+1))
    else
        echo "SELFTEST FAIL: main detached HEAD exited $rc, stdout='$a', stderr='$(cat "$tmp/detm.err")', expected exit 5, empty stdout, no \"branch 'HEAD'\""; fails=$((fails+1))
    fi
    ( cd "$main" && git checkout -q "$main_branch" ) || true

    # 8d. chain walk: sub -> workb2 -> inc-pu6v, and inc-pu6v has a band row, so
    #     the call issues inside the inc-pu6v EV band (221-299).
    rm -rf "$numdir"; mkdir -p "$numdir"
    ( cd "$repo" && git config branch.workb.incursionBase workb2 )
    ( cd "$repo" && git config branch.workb2.incursionBase inc-pu6v )
    a="$(cd "$repo" && "$SCRIPT" EV EV_CHAIN 2>/dev/null)"; rc=$?
    if [ "$rc" -eq 0 ] && [ -n "$a" ] && [ "$a" -ge 221 ] && [ "$a" -le 299 ]; then pass=$((pass+1)); else
        echo "SELFTEST FAIL: chain walk exited $rc, stdout='$a', expected an EV number in 221-299"; fails=$((fails+1)); fi
    ( cd "$repo" && git config --unset branch.workb.incursionBase )
    ( cd "$repo" && git config --unset branch.workb2.incursionBase )
    ( cd "$repo" && git config branch.workb.incursionBase master )

    # 8d2. god message families: on a branch whose chain reaches inc-pu6v,
    #      MSG_SINGLE issues above the highest in-range MSG member. The fixture
    #      has MSG_FOO 1005 (1000-1999) and MSG_BAND_ZZZ 1900 (a MSG_BAND_*
    #      constant the parser must ignore), so the first number is 1006, not
    #      1901. MSG_AID issues above MSG_BAR 5000, so 5001.
    rm -rf "$numdir"; mkdir -p "$numdir"
    ( cd "$repo" && git config branch.workb.incursionBase workb2 )
    ( cd "$repo" && git config branch.workb2.incursionBase inc-pu6v )
    a="$(cd "$repo" && "$SCRIPT" MSG_SINGLE X 2>/dev/null)"; rc=$?
    if [ "$rc" -eq 0 ] && [ "$a" = "1006" ]; then pass=$((pass+1)); else
        echo "SELFTEST FAIL: MSG_SINGLE returned '$a' (rc=$rc), expected 1006 (above MSG_FOO 1005; MSG_BAND_* ignored)"; fails=$((fails+1)); fi
    a="$(cd "$repo" && "$SCRIPT" MSG_AID Y 2>/dev/null)"; rc=$?
    if [ "$rc" -eq 0 ] && [ "$a" = "5001" ]; then pass=$((pass+1)); else
        echo "SELFTEST FAIL: MSG_AID returned '$a' (rc=$rc), expected 5001 (above MSG_BAR 5000)"; fails=$((fails+1)); fi

    # 8d3. a master-based branch has no MSG row, so a message family exits 2
    #      with empty stdout, as for any family with a missing master row.
    ( cd "$repo" && git config --unset branch.workb.incursionBase )
    ( cd "$repo" && git config --unset branch.workb2.incursionBase )
    ( cd "$repo" && git config branch.workb.incursionBase master )
    rm -rf "$numdir"; mkdir -p "$numdir"
    a="$(cd "$repo" && "$SCRIPT" MSG_SINGLE X 2>/dev/null)"; rc=$?
    if [ "$rc" -eq 2 ] && [ -z "$a" ]; then pass=$((pass+1)); else
        echo "SELFTEST FAIL: master-based MSG_SINGLE exited $rc, stdout='$a', expected exit 2, empty stdout"; fails=$((fails+1)); fi

    # 8d4. an unknown message family exits 2.
    ( cd "$repo" && "$SCRIPT" MSG_NOPE X >/dev/null 2>&1 ); rc=$?
    if [ "$rc" -eq 2 ]; then pass=$((pass+1)); else
        echo "SELFTEST FAIL: unknown MSG family exited $rc, expected 2"; fails=$((fails+1)); fi

    # 8e. base cycle a -> b -> a with no rows refuses: exit 5 and does not hang
    #     (hop limit / repeat guard).
    rm -rf "$numdir"; mkdir -p "$numdir"
    ( cd "$repo" && git config branch.workb.incursionBase cyc_a )
    ( cd "$repo" && git config branch.cyc_a.incursionBase cyc_b )
    ( cd "$repo" && git config branch.cyc_b.incursionBase cyc_a )
    if command -v timeout >/dev/null 2>&1; then
        a="$(cd "$repo" && timeout 10 "$SCRIPT" EV EV_CYCLE 2>/dev/null)"; rc=$?
    else
        a="$(cd "$repo" && "$SCRIPT" EV EV_CYCLE 2>/dev/null)"; rc=$?
    fi
    if [ "$rc" -eq 5 ] && [ -z "$a" ]; then pass=$((pass+1)); else
        echo "SELFTEST FAIL: base cycle exited $rc, stdout='$a', expected exit 5, empty stdout"; fails=$((fails+1)); fi
    ( cd "$repo" && git config --unset branch.workb.incursionBase )
    ( cd "$repo" && git config --unset branch.cyc_a.incursionBase )
    ( cd "$repo" && git config --unset branch.cyc_b.incursionBase )
    ( cd "$repo" && git config branch.workb.incursionBase master )

    # 8f. a numeric counter below the band floor is clamped: seed the STATI
    #     master counter with 5; a master-based branch must issue 243 or higher,
    #     never below 243.
    rm -rf "$numdir"; mkdir -p "$numdir"
    printf '5\n' > "$numdir/STATI.master"
    a="$(cd "$repo" && "$SCRIPT" STATI CLAMP 2>/dev/null)"; rc=$?
    if [ "$rc" -eq 0 ] && [ -n "$a" ] && [ "$a" -ge 243 ]; then pass=$((pass+1)); else
        echo "SELFTEST FAIL: below-floor counter exited $rc, stdout='$a', expected a STATI >= 243"; fails=$((fails+1)); fi

    # 8g. INCURSION_NUMBERS_LOCKED=1 without the caller actually holding the
    #     lock must refuse: the in-process probe finds the lock free, so exit 3
    #     and empty stdout (finding 1).
    rm -rf "$numdir"; mkdir -p "$numdir"
    a="$(cd "$repo" && INCURSION_NUMBERS_LOCKED=1 "$SCRIPT" STATI LOCKFALSE 2>/dev/null)"; rc=$?
    if [ "$rc" -eq 3 ] && [ -z "$a" ]; then pass=$((pass+1)); else
        echo "SELFTEST FAIL: LOCKED=1 with no lock exited $rc, stdout='$a', expected exit 3, empty stdout"; fails=$((fails+1)); fi

    # 8h. a relative INCURSION_NUMBERS_DIR whose parent does not exist must
    #     refuse (finding 3), and must NOT create anything at the root-level path
    #     the old cd-failure fallback would have produced.
    local badbase="incursion-nonexistent-$$-$$"
    local badroot="/$badbase"
    a="$(cd "$repo" && INCURSION_NUMBERS_DIR="incursion-no-such-parent-$$/$badbase" "$SCRIPT" STATI RELBAD 2>/dev/null)"; rc=$?
    if [ "$rc" -eq 1 ] && [ -z "$a" ] && [ ! -e "$badroot" ]; then pass=$((pass+1)); else
        echo "SELFTEST FAIL: relative bad dir exited $rc, stdout='$a', root path '$badroot' exists: $([ -e "$badroot" ] && echo yes || echo no), expected exit 1, empty stdout, no root path"; fails=$((fails+1)); fi

    # 8i. a 2-cycle (a -> b -> a) is caught by the repeat guard, not the hop
    #     limit. Count git-config lookups: a repeat guard breaks after 2 lookups,
    #     while the 10-hop limit would need 10. The wrapper is a git shim that
    #     logs each config --get, so fewer than 5 lookups proves the repeat guard.
    rm -rf "$numdir"; mkdir -p "$numdir"
    ( cd "$repo" && git config branch.workb.incursionBase cyc2_a )
    ( cd "$repo" && git config branch.cyc2_a.incursionBase cyc2_b )
    ( cd "$repo" && git config branch.cyc2_b.incursionBase cyc2_a )
    local shimdir="$tmp/shim" gitlog="$tmp/gitcalls.log"
    mkdir -p "$shimdir"
    : > "$gitlog"
    cat > "$shimdir/git" <<SHIM
#!/bin/bash
if [ "\$1" = "config" ] && [ "\$2" = "--get" ]; then
    printf '%s\n' "\$3" >> "$gitlog"
fi
exec /usr/bin/git "\$@"
SHIM
    chmod +x "$shimdir/git"
    a="$(cd "$repo" && PATH="$shimdir:$PATH" "$SCRIPT" EV EV_CYCLE2 2>/dev/null)"; rc=$?
    local lookups
    lookups="$(wc -l < "$gitlog" | tr -d ' ')"
    if [ "$rc" -eq 5 ] && [ -z "$a" ] && [ "$lookups" -lt 5 ]; then pass=$((pass+1)); else
        echo "SELFTEST FAIL: 2-cycle exited $rc, stdout='$a', git-config lookups=$lookups, expected exit 5, empty stdout, <5 lookups (repeat guard, not hop limit)"; fails=$((fails+1)); fi
    ( cd "$repo" && git config --unset branch.workb.incursionBase )
    ( cd "$repo" && git config --unset branch.cyc2_a.incursionBase )
    ( cd "$repo" && git config --unset branch.cyc2_b.incursionBase )
    ( cd "$repo" && git config branch.workb.incursionBase master )

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

# Save the original arguments before any parsing could shift them: the lockf
# wrap below re-execs this script and must hand it the exact same call.
ORIG_ARGS=("$@")

FAMILY="${1:-}"
NAME="${2:-}"

if ! family_known "$FAMILY"; then
    usage >&2
    echo "next_number: FAMILY must be one of: $(known_families | paste -sd, -), got '${FAMILY}'" >&2
    exit 2
fi

case "$NAME" in
    '') usage >&2; echo "next_number: NAME is required" >&2; exit 2 ;;
esac
case "$NAME" in
    *[!A-Z0-9_]*|[!A-Z]*) usage >&2; echo "next_number: NAME '$NAME' must match ^[A-Z][A-Z0-9_]*$" >&2; exit 2 ;;
esac

# Refuse to allocate from the main worktree. Its checkout belongs to no bead,
# so a number picked there would come from the wrong band. The nightly harness
# is the one caller that legitimately runs on a nightly/* branch from main.
cur_branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
git_dir="$(git rev-parse --path-format=absolute --git-dir 2>/dev/null)"
git_common="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"

# Defect 1: fail open. If git gives no answer (cwd outside any repo, or a git
# without --path-format) the worktree is unknown, so refuse rather than guess.
if [ -z "$git_dir" ] || [ -z "$git_common" ]; then
    echo "next_number: no number issued: not inside an Incursion worktree" >&2
    exit 5
fi

# Defect 2: a detached HEAD prints 'HEAD'. The band cannot be proved, so refuse
# in any worktree before the main-worktree check, whose message would otherwise
# name branch 'HEAD'.
if [ "$cur_branch" = "HEAD" ]; then
    echo "next_number: no number issued: detached HEAD; check out the bead's branch" >&2
    exit 5
fi

if [ "$git_dir" = "$git_common" ]; then
    case "$cur_branch" in
        nightly/*) ;;
        *)
            echo "next_number: no number issued: you are in the main worktree on branch '${cur_branch:-?}'; run it from the bead's worktree: tools/worktree.sh <bead-id>, then cd ~/Scripts/Incursion-<bead-id>" >&2
            exit 5
            ;;
    esac
fi

branch_band "$FAMILY"
rc=$?
case "$rc" in
    0) ;;
    1) echo "next_number: no $FAMILY band row for master" >&2; exit 2 ;;
    *) exit "$rc" ;;
esac

STATE_DIR="${INCURSION_NUMBERS_DIR:-$(git rev-parse --git-common-dir)/incursion-numbers}"
case "$STATE_DIR" in
    /*) ;;
    *)
        if ! STATE_DIR="$(cd "$(dirname "$STATE_DIR")" 2>/dev/null && pwd)/$(basename "$STATE_DIR")"; then
            echo "next_number: cannot resolve INCURSION_NUMBERS_DIR '$STATE_DIR': its parent directory does not exist" >&2
            exit 1
        fi
        ;;
esac
mkdir -p "$STATE_DIR" || { echo "next_number: cannot create state dir $STATE_DIR" >&2; exit 1; }

# Serialise the whole critical section with a kernel flock via /usr/bin/lockf.
# The kernel releases the lock when the holder dies, so there is no stale lock to
# break and no window where two waiters can both judge the same dead holder. The
# child (this same script, flagged) does all the work; its stdout and stderr pass
# through unchanged. The existing mkdir lock stays inside the child to exclude
# callers on older branches that still run the old, lockf-less script.
if [ "${INCURSION_NUMBERS_NO_LOCK:-}" = "1" ] && [ "${INCURSION_NUMBERS_SELFTEST:-}" = "1" ]; then
    :
elif [ "${INCURSION_NUMBERS_LOCKED:-}" = "1" ]; then
    # The caller claims to hold the allocation lock for us. It is only truth if
    # the parent lockf really holds it: a nested lockf probe on the same file
    # must block (exit 75) while the lock is held, and succeed (exit 0) when it
    # is free. Any other exit means the lock is not held, so refuse.
    /usr/bin/lockf -k -s -t 0 "$STATE_DIR/alloc.lock" true
    probe=$?
    if [ "$probe" -ne 75 ]; then
        echo "next_number: INCURSION_NUMBERS_LOCKED is set but the allocation lock is not held" >&2
        exit 3
    fi
else
    if [ ! -x /usr/bin/lockf ]; then
        echo "next_number: /usr/bin/lockf is missing or not executable; refusing to issue a number without a lock" >&2
        exit 3
    fi
    /usr/bin/lockf -k -t 30 "$STATE_DIR/alloc.lock" env INCURSION_NUMBERS_LOCKED=1 bash "$0" "${ORIG_ARGS[@]}"
    rc=$?
    if [ "$rc" -eq 75 ]; then
        echo "next_number: lock timeout after 30s" >&2
        exit 3
    fi
    if [ "$rc" -eq 70 ]; then
        echo "next_number: allocation child died" >&2
        exit 3
    fi
    if [ "$rc" -eq 73 ]; then
        echo "next_number: cannot create lock file $STATE_DIR/alloc.lock" >&2
        exit 3
    fi
    exit "$rc"
fi

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
# Defect 4: a numeric counter below the band floor must not issue an out-of-band
# number; clamp it to BAND_LOW - 1 so the next number is in band.
if [ "$counter" -lt "$((BAND_LOW - 1))" ]; then
    counter=$((BAND_LOW - 1))
fi

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

printf 'band: %s %s-%s\n' "$BAND_BRANCH" "$BAND_LOW" "$BAND_HIGH" >&2
printf '%s\n' "$next"
exit 0
