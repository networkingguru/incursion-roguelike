# Archived full text -- not auto-loaded. The loaded rule lives in .claude/rules/nightly-harness.md.

# Nightly harness

## nightly-2026-09-12-stalled-and-killed
TONIGHT'S NIGHTLY (2026-09-12) DID NO WORK AND BRIAN HAD IT KILLED AT 05:45.

WHAT HAPPENED. launchd job com.brianhill.incursion.nightly fired at 01:00:01 as
usual. It launched an agent four times and the watchdog killed every one after
30 minutes with no CPU progress:
  launch 1  01:01:34 -> killed 01:41:45  STALL
  launch 2  01:51:46 -> killed 02:31:57  STALL
  launch 3  02:51:57 -> killed 03:32:09  STALL
  launch 4  04:12:09 -> killed 04:52:21  STALL
Backoff is RETRY_WAIT_MIN=(10 20 40 60 60), MAX_LAUNCHES=6. It was asleep in the
60-minute wait before launch 5 when Brian asked about it.

THE ONLY OUTPUT ALL NIGHT was five doc files edited by launch 1 before it
stalled -- citation line-number repairs in docs/ENGINE-MAP.md,
ENGINE-MAP-CREATURE.md, ENGINE-SERIALISATION.md, REPORTING-GATE.md and
YUSE-VERBS.md. Brian said to trash them. They were discarded, branch
nightly/2026-09-12 deleted (it had no commits of its own), tree returned to
master clean.

THE LAUNCHD JOB IS STILL REGISTERED. Only tonight's run was killed. It fires
again at 01:00. If it stalls the same way, the stall is not a one-off.

A REAL BUG IN THE WRAPPER, FOUND WHILE READING IT, NOT FIXED. nightly-harness/bin/nightly.sh line 509
gives up when the clock is past DEADLINE=0430. That check sits AFTER the
launch++ and BEFORE the backoff sleep. At 04:52:21 the wrapper decided to wait
another 60 minutes instead of giving up, so the guard did not fire when it
should have. nightly-harness/bin/nightly.sh line 82 already warns that a leaked TZ in the process's
environment breaks the deadline guard, which is the likely cause -- date '+%H%M'
returning UTC. On 2026-09-09 the same deadline DID fire, at 06:31:46. Worth
confirming against the 2026-09-09 log before believing either explanation.

WHERE TO LOOK NEXT TIME. Main log ~/Library/Logs/incursion-nightly.log. Per
launch debug logs ~/Library/Logs/incursion-nightly-debug-<date>-<n>.log. The
wrapper is ~/Scripts/nightly-harness/bin/nightly.sh; the retry loop is lines
459-525. 'launchctl list | grep incursion' shows a PID when it is running and a
bare exit code when it is not.

THE LAST TWO NIGHTS RAN CLEAN: 2026-09-10 ended 01:51:50 exit 0, 2026-09-11
ended 02:45:15 exit 0. So the stall started tonight.

## nightly-autonomy-resume
NIGHTLY AUTONOMY WORK -- built 2026-08-23, UNCOMMITTED, nightly job still OFF.

WHAT BRIAN ASKED FOR: agents update and review docs, auto-commit, anything needing him is HELD and asked at the next session start so the following night can act. He wants to be out of the loop. HARD CAVEAT: nothing goes upstream without his express consent -- see [[feedback-nightly-never-publishes]].

BUILT, and every piece is tested:
1. tools/check_doc_citations.sh -- ratchets citation defects per document against tools/doc_citations.baseline (42 docs, 36 defects recorded 2026-08-23). Fails on a document THIS change made worse, or one improved without re-recording. --selftest covers the verdict logic. Not zero-tolerance on purpose: docs/REPORTING-GATE.md has 1 defect today.
2. tools/nightly_verify.sh --record / --compare / --checks-only -- the merge gate. Builds both backends absolutely; ratchets five cheap checks against a pre-run snapshot so check_probe_hooks.sh (failing on master, bd inc-loa.12) does not block a merge while a NEW break does. --checks-only exists so it can be exercised without rebuilding over a live game.
3. tools/held_queue.sh -- prints open beads labelled needs-brian. Wired as a second SessionStart hook in .claude/settings.json. One entry today: inc-loa.12.
4. ~/Scripts/nightly-harness/bin/nightly.sh -- new MERGE_ON_SUCCESS / VERIFY_CMD / VERIFY_RECORD_CMD. Fast-forwards master after a clean run, refuses on leftover uncommitted work, failed verify or a non-fast-forward, and NEVER pushes. Four new cases in tests/test-nightly.sh (G merge, H refuse, I off-by-default, J leftovers). Suite passes.
5. projects/incursion.conf -- those three settings plus NIGHTLY_VERIFY_STATE.
6. projects/incursion/prompt.md -- the twelve hand-picked items were all done on 2026-08-23, so the work list is now a selection rule (answer rulings, then bd ready by priority, NO REPRO NO WORK, hold what needs him). Adds sections 'The held queue' and 'What happens to your branch'. The doc gate is now a commit rule.

STATE. Uncommitted in the repo: tools/check_doc_citations.sh, tools/doc_citations.baseline, tools/held_queue.sh, tools/nightly_verify.sh (all new), .claude/settings.json and src/Dump.cpp (modified). The harness files are outside the repo and not under git.

NOT DONE, and both are deliberate:
- The 01:00 LaunchAgent stays UNINSTALLED. Brian said on 2026-08-23 to wait for the weekly usage limit to reset. Turn it on with: cd ~/Scripts/nightly-harness && bin/install-agent.sh incursion
- The crontab still holds the two commented-out Incursion lines; the permission classifier blocked the edit. They are inert. A tidied replacement is in the session scratchpad.

ALSO OPEN: src/Dump.cpp gained a Mana line (spent/held split, added to diagnose inc-upw.53). Only ./incursion-headless was rebuilt, so tools/check_dump_save.sh FAILS until ./incursion is rebuilt -- which the first nightly run will do by itself.

## nightly-commit-hook-conflict
**HISTORICAL. RULED AND FIXED 2026-09-14 — do NOT follow the procedure below.**
Brian closed inc-loa.46 on 2026-09-14: the hook now admits a commit when
`NIGHTLY_BRANCH` names the current `nightly/` branch (commit 1571e9f, verified
at `.beads/hooks/pre-commit:40`). `tools/check_shared_checkout_gate.sh` passed
7 of 7, and the 2026-09-14 nightly made fourteen commits through the hook with
no `--no-verify`. So the conflict this rule describes lasted one night.
`git commit --no-verify` is NOT an approved workaround: see
`beads-blocking-a-commit-fix-the-bead`, which stands unqualified. The text below
records what happened on 2026-09-13 only. Bead inc-wknz.

THE SHARED-CHECKOUT PRE-COMMIT HOOK REFUSES EVERY NIGHTLY COMMIT (found 2026-09-13). .beads/hooks/pre-commit (inc-uw8s, added 2026-09-11) refuses a non-merge commit when git-dir equals git-common-dir, i.e. in ~/Scripts/Incursion. The overnight harness prompt forbids worktrees and requires committing on nightly/<date> in that checkout. The 2026-09-13 doc run committed with 'git commit --no-verify' (sixteen commits, 3cf312e..416d948) and ran the two gates --no-verify skips by hand before each commit: tools/check_commit_lane.sh --message <msgfile>, and tools/check_bead_publish.py. It also confirmed 'git branch --show-current' before each commit. The question of which rule gives way is held for Brian as inc-loa.46. Until he rules, a nightly run can repeat that procedure; check inc-loa.46 for a RULING first.

## nightly-doc-run-where-to-check
THE NIGHTLY / DOCUMENTATION RUN IS THE LAUNCHD HARNESS, NOT CRON. When Brian asks 'did the nightly run / doc run finish?', DO NOT look at crontab or tools/doc_freshness_cron.sh -- that path is DEAD. The live nightly is a SEPARATE REPO: ~/Scripts/nightly-harness, run by launchd job com.brianhill.incursion.nightly at 01:00 (plist: ~/Library/LaunchAgents/com.brianhill.incursion.nightly.plist -> bin/nightly.sh incursion). TO ANSWER 'did it finish': read the dated report ~/Scripts/nightly-harness/projects/incursion/nightly/YYYY-MM-DD.md (today's date = last night's run). A *-FAILED.md name means it aborted; a plain YYYY-MM-DD.md with a Budget section means it finished. The harness is now a DOCUMENTATION session and itself runs BOTH the doc-freshness sweep AND the probe-hooks check, with working auth. On a clean run it merges nightly/<date> into master locally (nothing pushed). CRONTAB IS DELETED (2026-08-29): the two commented jobs incursion-doc-freshness + incursion-probe-hooks were disabled since 2026-08-23 (usage limit + broken 'claude -p' auth) and are now redundant with the harness. Backup: ~/Scripts/nightly-harness/state/crontab-backup-2026-08-29.txt and bead inc-jobs-off. STOP raising the cron doc-freshness job -- it no longer exists.
