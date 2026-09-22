<!-- citations: this-port -->

# Spec: a pipeline status that lies (inc-mwjc)

## 1. The defect

Every check script in `tools/` sets `set -uo pipefail`. Many ask a yes/no
question with a pipeline whose READER stops at the first match:

    printf '%s' "$MARKED" | grep -qxF "$tp	$oneid"

`grep -q` exits as soon as it matches. The WRITER is then killed by SIGPIPE and
exits 141. `pipefail` makes 141 the status of the whole pipeline. The script
reads that as "no match" for data that does match.

The failure is a race between the writer finishing its last `write()` and the
reader deciding to exit, so it is intermittent, and it is more likely when the
machine is busy.

### 1.1 What it has cost

Two landings on 2026-09-22, roughly forty minutes each. `check_citations.sh`
reported `docs/media/incursion-macos.png is not in HEAD` for a file that is in
HEAD. `check_upstream_marks.sh` reported that `src/Player.cpp` carries no
marker for `inc-azc`, with the marker present at `src/Player.cpp:1698`. Both
passed alone minutes later on an identical tree. `inc-9diw`
(`check_doc_citations.sh`, 2026-09-16) is the same fault reached through
`check_citations.sh`.

### 1.2 The two directions of harm

**A false alarm** stops good work. `tools/check_commit_lane.sh:54` is the
`commit-msg` hook: a spurious 141 there reports that a correct subject line
carries no lane, and refuses the commit.

**A false pass** hides a real defect, and this is the worse half.
`tools/check_error_handling.sh:32` ends `... | grep -q .`, where a match means
an unsafe `sprintf`. The match is what triggers SIGPIPE, so the run that finds
the defect is the run that can report the tree clean.

### 1.3 Measurement

Every number below comes from a machine carrying 14 concurrent pipe-heavy
background processes on 10 cores. On an idle machine the broken shape passes
2,000 of 2,000, so a green result proves nothing unless load is applied. That
constraint is normative for the tests in §5.

One 82,663-byte writer, match on an early line, 1,200 runs each. Spurious
misses on data that is present:

| shape | misses |
|---|---|
| `cat FILE \| grep -qxF P` | 55 / 1200 |
| `echo "$VAR" \| grep -qxF P` | 337 / 1200 |
| `grep -qxF P <<< "$VAR"` | 0 / 1200 |
| `grep -qxF P FILE` | 0 / 1200 |

A faithful replica of `check_upstream_marks.sh` pass 3 -- real tree, real
4,785-byte `MARKED`, 204 membership probes per run, 20 runs per form:

| shape | spurious misses |
|---|---|
| `printf '%s' "$MARKED" \| grep -qxF P` | 1 in 4,080 probes |
| `grep -qxF P <<< "$MARKED"` | 0 in 4,080 |

**There is no safe writer size.** A synthetic sweep at 109, 415, 517, 619,
1,027, 4,019 and 16,021 bytes showed nothing, and only the 65,015-byte case
failed synthetically, yet the real 4,785-byte writer fails. A synthetic sweep
under-reports. Nothing in this spec may scope work by writer size.

## 2. Scope

### 2.1 The inventory

A site is IN SCOPE when a pipeline feeds an early-exit reader AND the
pipeline's exit status is consumed. Counted across `tools/*.sh` files that set
`pipefail`:

| set | sites | scripts |
|---|---|---|
| declared to the gate (`# gate: cheap` or `# gate: live`) | 44 | 15 |
| everything else in `tools/` | measured by `--record` | |

The 44 is hand-verified, site by site, and is normative: the guard MUST flag
exactly those 44 in those 15 scripts. The total over the rest of `tools/` is
whatever `tools/check_sigpipe_status.sh --record` measures. No number for it
appears in this spec, because a number written here and a number the scanner
produces would be two claims about one fact, and the scanner is the one that
runs.

### 2.2 What this change converts

The 44 gate-declared sites, and nothing else. Only a gate-declared check can
cost a landing or refuse a commit. The other 270 go on the guard's baseline in
§4 and are drained later.

The 15 scripts, with their sites:

| script | tier | lines |
|---|---|---|
| `tools/check_upstream_marks.sh` | cheap | 130, 133, 134, 280, 297, 325, 482, 483, 484, 485 |
| `tools/check_readme_checks.sh` | cheap | 107, 109, 111, 113 |
| `tools/check_citations.sh` | cheap | 250, 296, 529 |
| `tools/check_commit_lane.sh` | cheap | 54, 58, 59 |
| `tools/check_error_handling.sh` | cheap | 32, 39, 46 |
| `tools/check_key_directives.sh` | live | 46, 54, 64 |
| `tools/check_reapply_single_grant.sh` | live | 36, 41, 47 |
| `tools/check_prestige_tables.sh` | live | 44, 84 |
| `tools/check_breath_dice.sh` | live | 64 |
| `tools/check_erich_speaks.sh` | cheap | 42 |
| `tools/check_orphan_branches.sh` | cheap | 149 |
| `tools/check_readline_overflow.sh` | live | 71 |
| `tools/check_rules_channel.sh` | cheap | 162 |
| `tools/check_sentinel_live.sh` | live | 55 |
| `tools/check_virtual_override.sh` | cheap | 374 |

### 2.3 The function-final class, and why the guard cannot judge it

A pipeline that is the LAST statement of a function becomes that function's
RETURN STATUS. Whether that is a defect depends on the CALLER, which is not on
the same line.

    path_in_ref() { list_ref "$1" | grep -qxF "$2"; }        # line 242
    ...
    if path_in_ref "$FALLBACK_REF" "$img"; then              # line 584

That is a real site, and it is THE site: it is what reported
`docs/media/incursion-macos.png is not in HEAD` for a file that is in HEAD.

An earlier draft of this spec put the whole class out of scope on the strength
of four cases where the caller reads only the printed VALUE. That reasoning was
wrong, and wrong in the direction that would have shipped this bead without
fixing the failure that opened it.

**Six function-final sites in the gate-declared scripts have their status
consumed by a caller, and all six are converted:**

| site | function | consumed at |
|---|---|---|
| `tools/check_citations.sh:242` | `path_in_ref` | 584, 586 |
| `tools/check_upstream_marks.sh:151` | `hit_is_negated` | 236, 270, 407, 413 |
| `tools/check_commit_lane.sh:120` | `is_exempt` | 128 |
| `tools/check_orphan_branches.sh:66` | `is_grandfathered` | 173 |
| `tools/check_orphan_branches.sh:76` | `has_worktree` | 158 |
| `tools/check_orphan_branches.sh:80` | `is_bead_id` | 113, 119, 172 |

**Four are value-position and stay as they are.**
`tools/check_probe_hooks.sh:81` and `:86`, `tools/check_doc_citations.sh:93`
and `tools/check_gate_membership.sh:38` each end a function with `| head -1`.
SIGPIPE makes the function return 141, but `bead_for` (used at
`check_probe_hooks.sh:140` and `:158`), `status_of` (`:173`), `baseline_for`
(`check_doc_citations.sh:202`) and `marker_of` are each read only through
`$( )`. Converting them would be a change with no defect behind it.

**Game code.** Nothing under `src/`, `inc/` or `lib/` changes. No `upstream:`
marker and no row in the ledger of `docs/REPORTING-GATE.md` is owed, because
this is the harness and not the base code.

## 3. The transform

Five rules. Each is behaviour-preserving, and §3.6 states the one precondition
that makes that true.

### 3.1 R1 -- a variable writer

    echo "$V" | grep FLAGSq PAT          ->   grep FLAGSq PAT <<< "$V"
    printf '%s' "$V" | grep FLAGSq PAT   ->   grep FLAGSq PAT <<< "$V"
    printf '%s\n' "$V" | grep FLAGSq PAT ->   grep FLAGSq PAT <<< "$V"

### 3.2 R2 -- a file writer

    cat FILE | grep FLAGSq PAT           ->   grep FLAGSq PAT FILE

### 3.3 R3 -- a command writer, one stage

    CMD | grep FLAGSq PAT                ->   grep FLAGSq PAT <<< "$(CMD)"

`tools/check_citations.sh:296` and `tools/check_readline_overflow.sh:71` are
this rule.

### 3.4 R4 -- a multi-stage pipeline ending in `grep -q .`

`tools/check_error_handling.sh:32`, `:39` and `:46` are this rule, and it is
the one that removes an early-exit reader rather than moving it. Capture the
writer's output on its own line, then test the string:

    hits="$(grep -n "sprintf(__buff2" src/*.cpp | grep -v "snprintf(__buff2")"
    if [ -n "$hits" ]; then

This also makes the writers' own failure visible, which `grep -q .` hid.

### 3.5 R5 -- the cached listing in `tools/check_citations.sh`

`list_ref` fills a per-run cache file and then `cat`s it. The two status-
consuming readers must read the FILE instead of a copy of it.

Add a sibling function beside `list_ref`:

    ref_list_file <ref>   fills the cache exactly as list_ref does, then prints
                          the cache PATH and nothing else.

`list_ref` keeps its present body and is rewritten to `cat "$(ref_list_file
"$1")"`, so there is one filling implementation. Then:

- `path_in_ref` (line 242) becomes `grep -qxF "$2" "$(ref_list_file "$1")"`.
- Line 250 becomes `grep -qxF "$base" "$(ref_list_file "$ref")"`.
- Line 529 becomes `grep -qE "<pattern>" "$(ref_list_file "$url_ref")"`.

Line 255, `hits=$(list_ref "$ref" | grep -E ...)`, DOES NOT CHANGE. Its reader
is `grep -E` with no `-q`, which reads to the end, and its value -- not its
status -- is used.

### 3.6 The precondition, and where it can actually bite

`<<<` always writes exactly one trailing newline. So:

- Where the old writer was `echo "$V"` or `printf '%s\n' "$V"`, it wrote the
  same one trailing newline. The transform is byte-identical on the wire and
  there is NO precondition to check.
- Where the old writer was `printf '%s' "$V"`, it wrote NONE. The herestring
  adds one, so `grep` sees one extra empty line at the end.

**The precondition therefore applies only to the `printf '%s'` sites: at each
of those the pattern MUST be unable to match an empty line for every reachable
input.** That is eight sites, and each was checked by reading:

| site | pattern | why an empty line cannot match |
|---|---|---|
| `check_upstream_marks.sh:325` | `"$tp<TAB>$oneid"` | a path, a TAB and an id |
| `check_commit_lane.sh:54` | `^($LANES): .` | requires a lane, a colon and a character |
| `check_commit_lane.sh:58` | `^rules: ` | literal |
| `check_commit_lane.sh:59` | `inc-[a-z0-9]+(\.[0-9]+)*` | requires `inc-` |
| `check_commit_lane.sh:120` | `-x "$1"` | `$1` is a commit SHA, and the caller skips an empty one |
| `check_orphan_branches.sh:149` | `$EXEMPT_PATTERN` | a fixed regex over branch names |
| `check_rules_channel.sh:162` | `over the $CHAR_BUDGET budget` | literal prose |
| `check_virtual_override.sh:374` | `-F -- "$2"` | all twelve `_case` calls pass a non-empty literal |

Two sites take a variable pattern and were checked at the caller rather than at
the site: `check_erich_speaks.sh:42` iterates the five literals `MSG_CUSTOM1`
.. `MSG_CUSTOM5`, and `check_prestige_tables.sh:84` takes `$row` from a table
row. Neither is ever empty.

One site changes shape rather than just writer: `check_orphan_branches.sh:66`
was `printf '%s\n' $GRANDFATHERED` with `$GRANDFATHERED` UNQUOTED, so the shell
word-split it. `$GRANDFATHERED` is already written one name per line, so the
quoted herestring preserves the same line structure and differs only by blank
lines, which a non-empty `-x` pattern cannot match.

## 4. The guard

A new check, so the class cannot come back.

**File:** `tools/check_sigpipe_status.sh`. **Marker:** `# gate: cheap`.

### 4.1 What it flags

A file is in scope when it matches `tools/*.sh` and contains `pipefail`.

A LOGICAL LINE is a physical line with backslash continuations joined.

An EARLY-EXIT READER is the command word `grep` carrying `q` in any short-flag
cluster, or `grep` with `-m <n>`, or `head`.

A PIPE INTO A READER is a `|` that is not part of `||`, followed by an optional
`!`, optional `VAR=value` prefixes, and then an early-exit reader.

The STATUS IS CONSUMED when any of these holds for the logical line:

- a. it begins with `if`, `elif`, `while` or `until`;
- b. it ends with `; then` or `; do`;
- c. the pipeline is preceded by `!`;
- d. the pipeline is the left operand of `&&` or `||` on that line.

- e. the pipeline is the LAST STATEMENT OF A FUNCTION, in which case it is the
     function's return status.

It is NOT consumed, and MUST NOT be flagged, when the pipeline sits inside a
command substitution used as a value (`VAR=$(...)`, `local VAR=$(...)`).

Rule (e) deliberately over-reports. Whether a function's return status is read
lives at the CALLER, which a line-local scan cannot see, and §2.3 shows what it
costs to guess wrong: the site that caused this bead was a one-line function.
So the guard flags every function-final early-exit pipeline, and the four
value-position cases named in §2.3 are forgiven by the baseline like any other
backlog entry. A false alarm here costs a reader one minute; a blind spot here
cost two landings.

### 4.2 The ratchet

`tools/sigpipe_status.baseline` holds one line per file, `<count> <path>`, in
`LC_ALL=C` order. The check FAILS when

- a file's count is ABOVE its baseline,
- a file absent from the baseline has a non-zero count,
- a file's count is BELOW its baseline, which forces a re-record so the ratchet
  tightens rather than silently loosening.

`--record` rewrites the baseline. The ratchet shape and the last rule are
copied from `tools/check_doc_citations.sh`, which the project already runs.

### 4.3 The selftest runs in the gate

The no-argument run performs the scan AND THEN the selftest, and fails on
either. A selftest that only runs when somebody remembers to type `--selftest`
is a selftest that rots; this one is pure text over temporary files. Measured on 2026-09-22:
the selftest alone 0.2s, the scan of 264 files alone 1.2s, the combined default
run 2.8s. The cheap tier admits anything that "costs seconds", so it fits. The cases it MUST carry:

1. a file with one new flagged site fails;
2. a file whose count dropped fails until re-recorded;
3. an equal count passes;
4. `||` is not read as a pipe;
5. a `| head` in value position is not flagged;
6. a `| head` in an `if` condition IS flagged;
7. a file with no `pipefail` is not scanned;
8. a backslash continuation splitting a pipeline is still seen;
9. a NEW verdict lists each offending `path:line` with its source text, so the
   author is not left hunting;
10. a pipeline that is the last statement of a function IS flagged, including
    when the whole function is written on one line.

### 4.4 Registration

`tools/check_readme_checks.sh` requires a row for the new check under
`### The regression checks` in `tools/README.md`.
`tools/check_gate_membership.sh` requires the `# gate:` marker. Both are in the
cheap tier and both will refuse the landing without these.

### 4.5 The stress mode

`tools/check_sigpipe_status.sh --stress` reproduces §1.3: it generates load,
runs the broken and the fixed shape N times each, and prints the table. It is
NOT reached by the gate, because the marker carries no arguments, and it MUST
NOT be, since it takes minutes and depends on load. It exists so the evidence
can be re-made rather than believed.

## 5. Tests

All three classes are required. A green result from any of them is worthless
unless the matching red result has been seen first.

### 5.1 Proves the fix works

`--stress` MUST show the shipped shape red and the replacement green IN THE
SAME RUN, under generated load. A run that shows only green is a run that
proves the load generator failed, and it MUST be reported as INCONCLUSIVE
rather than as a pass.

### 5.2 Proves the old behaviour still passes

For each of the nine CHEAP-tier scripts, capture the complete stdout, stderr and
exit status on the unchanged tree BEFORE the edit, and again after, and require
them to be identical.

The six LIVE-tier scripts cannot be compared byte for byte. Each plays a game
session and prints its run directory -- `tools/check_sentinel_live.sh:60` prints
`$SHEET` -- so two runs of the SAME script differ. Compare the exit status and
the output with run-directory paths normalised, one run before and one after,
and treat the full gate in §5.4 as the real live proof, since it runs the whole
live tier anyway. For the seven that carry a `--selftest` -- `check_upstream_marks`,
`check_citations`, `check_readme_checks`, `check_commit_lane`,
`check_orphan_branches`, `check_rules_channel`, `check_virtual_override` --
capture the selftest output too, case by case.

### 5.3 Proves the errors are still caught

Per converted site, a boolean-equivalence proof: the old expression and the new
expression MUST agree on four inputs --

1. an input that matches,
2. an input that does not match,
3. an empty input,
4. an input whose only match is on the LAST line, which is where the added
   trailing newline of `<<<` could change an answer.

The harness lives at `docs/evidence/inc-mwjc/equiv_test.sh` and its output is
recorded in `docs/evidence/inc-mwjc/README.md`. It is untracked, per the rule
that evidence is committed only when a pull request needs it.

In addition, and this is not optional: `tools/check_error_handling.sh` MUST be
proved to still go RED. It is the one converted check whose bug direction is a
false PASS. Add a matching `sprintf(__buff2` line to a scratch copy of a
`src/*.cpp`, run the check, see it red, remove the line, see it green.

### 5.4 The gate

`tools/nightly_verify.sh --compare` MUST pass in the worktree before the
landing, which is what `tools/finish_bead.sh` runs anyway.

## 6. Commit

One lane: `tools:`. The whole change is the harness, the checks and the gate.
`rules:` and `fix:` do not apply -- no player feels this, and the defect is
ours rather than upstream's.

The body states the oracle, the mutation and the checks re-run, as
`docs/VERIFICATION.md` requires.
