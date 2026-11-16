#!/bin/bash
# Scratch repositories for the AC8 pressure driver (inc-cjos0 phase 8, D2).
#
#   tools/pressure/scratch.sh make <dir> [P.patch]   a fresh git repository at <dir>, holding a snapshot of this
#                                                    working tree, committed on master; branch inc-pu6v from it
#   tools/pressure/scratch.sh clone <dir> <master-rev> [P.patch]
#                                                    a clone of the REAL repository (AC9): local branches inc-pu6v and
#                                                    inc-pu6v.9 from its origin copies, master forced to <master-rev>, no
#                                                    remote left. Reads the real repository; never changes it.
#   tools/pressure/scratch.sh baseline <dir> <out>   build <dir> (posix) and record every fixture's field values in <out>
#   tools/pressure/scratch.sh record <tree> <out>    record every fixture's field values from an already built <tree>
#
# <dir> MUST lie under logs/phase8/d2/ of this worktree: this script refuses any other place, so it can never write
# into ~/Scripts/Incursion, the real beads database or ~/Games/Incursion. All git commands that change state run
# inside <dir> only.
#
# make: P = `git ls-files -co --exclude-standard` of this tree (tracked files plus uncommitted changes plus untracked
# non-ignored files), committed on master. An optional P.patch (shared preparation) is applied and committed as a
# second commit before the repository is configured, so master is P. Then the repository gets what tools/worktree.sh
# and tools/finish_bead.sh need: merge drivers, hooksPath .beads/hooks, a user local to the repo. Next to <dir>
# (in <dir>/../pressure-state) sit a fake `bd` and the fake beads it answers for; the pattern is the throwaway repo of
# tools/finish_bead.sh --selftest. The fake bd answers `show <id> --json`, `update` (claim), `list`/`lint` ([]) and
# `hooks run` (exit 3, which the hook shims read as "skip"); `list --label upstream` names every bead the
# REPORTING-GATE ledger mentions. Beads are written by tools/pressure/route.sh.
#
# Exit: 0 done, 1 failed, 2 could not run.
#
# fact: this working tree -- the snapshot P is whatever the tree holds now; the run records P's commit SHA
# fact: the fake bd -- written by this script, same answers on every run
# fact: build/field values -- BACKEND=posix ./build_macos.sh and tools/pressure/field_values.sh on tools/fixtures/chars/*.sav, frozen bytes; no seed, no key script
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
D2ROOT="${INCURSION_PRESSURE_D2ROOT:-$ROOT/logs/phase8/d2}"   # the override is for tools/pressure/ac9.sh --selftest only
unset INCURSIONPATH INCURSION_LOAD INCURSION_OPTIONS

die() { echo "scratch: $*" >&2; exit "${2:-1}"; }

# Resolve <dir> to an absolute path and refuse anything outside logs/phase8/d2/.
abs_under_d2() { # <path>
    local p d2
    mkdir -p "$D2ROOT" || die "cannot create $D2ROOT" 2
    d2="$(cd "$D2ROOT" && pwd -P)"
    p="$(python3 -c 'import os,sys; print(os.path.abspath(sys.argv[1]))' "$1")" || die "cannot resolve $1" 2
    case "$p" in
        "$d2"/*) printf '%s\n' "$p" ;;
        *) die "REFUSED: $p is not under $d2" 2 ;;
    esac
}

record_values() { # <tree> <outdir>  -> 0, 2 when any fixture could not be measured
    local tree="$1" out="$2" s b n=0 bad=0
    mkdir -p "$out" || return 2
    for s in "$tree"/tools/fixtures/chars/*.sav; do
        b="$(basename "$s" .sav)"
        if "$ROOT/tools/pressure/field_values.sh" "$tree" "$s" "$out/$b.txt" 2> "$out/$b.err"; then
            rm -f "$out/$b.err"; n=$((n + 1))
        else
            bad=$((bad + 1)); echo "scratch: could not record $b: $(head -c 200 "$out/$b.err")" >&2
        fi
    done
    echo "scratch: recorded $n fixture value files in $out ($bad failed)"
    [ "$bad" -eq 0 ] && [ "$n" -gt 0 ]
}

# The identity of a scratch repository: a local user, no signing.
repo_identity() { # run inside the repository
    git config user.name "AC8 pressure driver" && git config user.email pressure@example.invalid \
        && git config commit.gpgsign false
}

# What tools/worktree.sh and tools/finish_bead.sh need: merge drivers and the hooks path. Run inside the repository,
# after the commits that build it (those are not landings).
landing_config() {
    git config merge.landed.name "lib/landed.irc include order (tools/merge_landed.py)"
    git config merge.landed.driver "python3 tools/merge_landed.py landed %O %A %B"
    git config merge.landed-ledger.name "tools/resource_order.ledger is master's (tools/merge_landed.py)"
    git config merge.landed-ledger.driver "python3 tools/merge_landed.py landed-ledger %O %A %B"
    git config core.hooksPath .beads/hooks
}

# The fake bd and the fake beads it answers for, in <state>. <dir> is the repository (its REPORTING-GATE ledger names
# the beads the fake says carry the upstream label).
write_fake_bd() { # <dir> <state>
    local dir="$1" state="$2"
    cat > "$state/bin/bd" <<FAKE
#!/bin/sh
# Fake bd for the AC8 pressure scratch repositories. Answers only what finish_bead.sh, worktree.sh and the hooks ask.
S="$state"
# real bd takes a leading "-C <dir>" (tools/check_mirrored_lane.sh hands its stub's upstream query on that way)
if [ "\$1" = -C ]; then shift 2; fi
case "\$1" in
    show)
        f="\$S/beads/\$2.json"
        if [ "\$3" = --json ] && [ -f "\$f" ]; then exec cat "\$f"; fi
        echo "unknown bead \$2" >&2; exit 1 ;;
    update) exit 0 ;;
    list)
        case "\$*" in
            *"--label upstream"*) exec cat "\$S/upstream-labelled.json" ;;
            *"--all"*"--json"*) exec cat "\$S/beads-all.json" ;;
        esac
        echo '[]'; exit 0 ;;
    lint) echo '[]'; exit 0 ;;
    hooks) exit 3 ;;
    *) echo "fake bd: unsupported: \$*" >&2; exit 1 ;;
esac
FAKE
    chmod +x "$state/bin/bd" || return 2
    # tools/check_upstream_label.sh asks bd which beads carry the `upstream` label. The scratch database says every
    # bead the ledger names does (the check is about the real database, not about a case).
    python3 - "$dir/docs/REPORTING-GATE.md" "$state/upstream-labelled.json" <<'PY2' || return 2
import json, re, sys
ids = sorted(set(re.findall(r"inc-[a-z0-9]+(?:\.[0-9]+)*", open(sys.argv[1], encoding="utf-8").read())))
json.dump([{"id": i} for i in ids], open(sys.argv[2], "w"))
# `bd list --all --json --limit 0` (tools/check_probe_hooks.sh): a list of beads, each with an id and a status. A
# clone has no bead database, so every bead the ledger names is "open"; the check then reads every serving bead as live.
json.dump([{"id": i, "status": "open", "issue_type": "task"} for i in ids], open(sys.argv[2].replace("upstream-labelled", "beads-all"), "w"))
PY2
    printf '[{"id":"inc-pu6v","status":"open","issue_type":"epic","description":"epic","notes":""}]\n' > "$state/beads/inc-pu6v.json"
}

cmd_make() {
    local dir ppatch="${2:-}"
    [ $# -ge 1 ] || die "usage: scratch.sh make <dir> [P.patch]" 2
    dir="$(abs_under_d2 "$1")" || exit $?
    [ ! -e "$dir" ] || [ -z "$(ls -A "$dir" 2>/dev/null)" ] || die "REFUSED: $dir exists and is not empty" 2
    [ -z "$ppatch" ] || [ -f "$ppatch" ] || die "no patch $ppatch" 2
    mkdir -p "$dir" || die "cannot create $dir" 2
    local state; state="$(dirname "$dir")/pressure-state"
    mkdir -p "$state/bin" "$state/beads" "$state/values" "$state/tmp" || die "cannot create $state" 2

    # 1. The snapshot. A tracked file deleted in the working tree is not in P.
    local list="$state/p-files.list"
    ( cd "$ROOT" && git ls-files -co --exclude-standard -z ) > "$list" || die "git ls-files failed" 2
    # drop entries that no longer exist (tracked but deleted), NUL-separated
    python3 - "$ROOT" "$list" <<'PY' || die "could not filter the file list" 2
import os, sys
root, path = sys.argv[1], sys.argv[2]
names = [n for n in open(path, "rb").read().split(b"\0") if n]
keep = [n for n in names if os.path.lexists(os.path.join(root.encode(), n))]
open(path, "wb").write(b"\0".join(keep) + b"\0")
PY
    rsync -a --from0 --files-from="$list" "$ROOT/" "$dir/" || die "rsync of the snapshot failed" 2

    # 2. The repository. The first commits run before hooksPath is set: they build P, they are not a landing.
    (
        cd "$dir" || exit 2
        git init -q -b master || exit 2
        repo_identity || exit 2
        git add -A >/dev/null || exit 2
        git commit -q -m "tools: P snapshot of the inc-cjos0 working tree" || exit 2
        if [ -n "$ppatch" ]; then
            git apply "$ppatch" || { echo "scratch: P.patch does not apply" >&2; exit 1; }
            git add -A >/dev/null || exit 2
            git commit -q -m "tools: P shared preparation" || exit 2
        fi
        git branch inc-pu6v || exit 2
        landing_config
    ) || die "repository setup failed" "$?"
    git -C "$dir" rev-parse master > "$state/P.sha" || die "no master" 2

    # 3. The fake bd.
    write_fake_bd "$dir" "$state" || die "could not write the fake bd" 2
    echo "scratch: $dir ready; P = $(cat "$state/P.sha")"
}

cmd_clone() {
    [ $# -eq 2 ] || [ $# -eq 3 ] || die "usage: scratch.sh clone <dir> <master-rev> [P.patch]" 2
    local dir rev="$2" src state ppatch="${3:-}"
    [ -z "$ppatch" ] || [ -f "$ppatch" ] || die "no patch $ppatch" 2
    [ -z "$ppatch" ] || ppatch="$(cd "$(dirname "$ppatch")" && pwd)/$(basename "$ppatch")"   # the setup runs inside <dir>
    dir="$(abs_under_d2 "$1")" || exit $?
    [ ! -e "$dir" ] || [ -z "$(ls -A "$dir" 2>/dev/null)" ] || die "REFUSED: $dir exists and is not empty" 2
    # The real repository is the one whose common git dir this worktree shares, not this worktree's path.
    src="${INCURSION_AC9_SOURCE:-}"   # the override is for tools/pressure/ac9.sh --selftest only
    [ -n "$src" ] || src="$(git -C "$ROOT" rev-parse --path-format=absolute --git-common-dir)" || die "no common git dir" 2
    [ -e "$src" ] || die "no source repository $src" 2
    mkdir -p "$(dirname "$dir")" || die "cannot create $(dirname "$dir")" 2
    state="$(dirname "$dir")/pressure-state"
    mkdir -p "$state/bin" "$state/beads" "$state/values" "$state/tmp" || die "cannot create $state" 2
    git clone -q --no-local "$src" "$dir" || die "git clone of $src failed" 2
    (
        cd "$dir" || exit 2
        repo_identity || exit 2
        local b
        for b in inc-pu6v inc-pu6v.9 inc-10v7f; do
            if ! git rev-parse -q --verify "refs/remotes/origin/$b" > /dev/null; then
                [ "$b" = inc-10v7f ] && continue   # only the real clone has it; the --selftest source does not
                echo "scratch: the source has no branch $b" >&2; exit 2
            fi
            git branch -q "$b" "origin/$b" || exit 2
        done
        git rev-parse -q --verify "$rev^{commit}" > /dev/null || { echo "scratch: the clone has no commit $rev" >&2; exit 2; }
        git checkout -q -f -B master "$rev" || exit 2
        if [ -n "$ppatch" ]; then   # shared preparation, committed on master before the repository is configured
            git apply "$ppatch" || { echo "scratch: P.patch does not apply" >&2; exit 1; }
            git add -A > /dev/null || exit 2
            git commit -q -m "tools: P shared preparation" || exit 2
        fi
        git remote remove origin || exit 2
        landing_config || exit 2
    ) || die "clone setup failed" 2
    git -C "$dir" rev-parse master > "$state/P.sha" || die "no master" 2
    {
        echo "source $src"
        echo "master $(git -C "$dir" rev-parse master)"
        echo "master-rev $rev"
        [ -z "$ppatch" ] || echo "prep-patch $ppatch"
        echo "inc-pu6v $(git -C "$dir" rev-parse inc-pu6v)"
        echo "inc-pu6v.9 $(git -C "$dir" rev-parse inc-pu6v.9)"
        git -C "$dir" rev-parse -q --verify inc-10v7f > /dev/null && echo "inc-10v7f $(git -C "$dir" rev-parse inc-10v7f)"
    } > "$state/clone.txt"
    write_fake_bd "$dir" "$state" || die "could not write the fake bd" 2
    printf '[{"id":"inc-pu6v.9","status":"open","issue_type":"task","description":"god branch","notes":""}]\n' > "$state/beads/inc-pu6v.9.json"
    echo "scratch: clone $dir ready; master = $(cat "$state/P.sha")"
}

cmd_baseline() {
    [ $# -eq 2 ] || die "usage: scratch.sh baseline <dir> <out>" 2
    local dir; dir="$(abs_under_d2 "$1")" || exit $?
    local out; out="$(abs_under_d2 "$2")" || exit $?
    [ -d "$dir/.git" ] || die "$dir is not a scratch repository" 2
    ( cd "$dir" && BACKEND=posix ./build_macos.sh > "$out.build.log" 2>&1 ) \
        || { tail -8 "$out.build.log" >&2; die "the baseline build failed (log $out.build.log)" 1; }
    # the baseline's binary joins the suite's cache: a later landing whose C++ sources equal P's reuses it (D5)
    if [ -n "${INCURSION_PRESSURE_BINCACHE:-}" ] && [ -x "$dir/incursion-headless" ]; then
        local h; h="$("$ROOT/tools/pressure/srchash.sh" "$dir")" && [ -n "$h" ] && [ ! -x "$INCURSION_PRESSURE_BINCACHE/$h/incursion-headless" ] \
            && mkdir -p "$INCURSION_PRESSURE_BINCACHE/$h.tmp" && cp -f "$dir/incursion-headless" "$INCURSION_PRESSURE_BINCACHE/$h.tmp/" \
            && rm -rf "$INCURSION_PRESSURE_BINCACHE/$h" && mv "$INCURSION_PRESSURE_BINCACHE/$h.tmp" "$INCURSION_PRESSURE_BINCACHE/$h"
    fi
    record_values "$dir" "$out" || exit 2
}

case "${1:-}" in
    make)     shift; cmd_make "$@" ;;
    clone)    shift; cmd_clone "$@" ;;
    baseline) shift; cmd_baseline "$@" ;;
    record)   shift; [ $# -eq 2 ] || die "usage: scratch.sh record <tree> <out>" 2
              out="$(abs_under_d2 "$2")" || exit $?
              record_values "$(cd "$1" && pwd)" "$out" || exit 2 ;;
    *) die "usage: scratch.sh make|clone|baseline|record ..." 2 ;;
esac
