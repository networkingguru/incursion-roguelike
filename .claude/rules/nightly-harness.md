# Nightly harness

## nightly-2026-09-12-stalled-and-killed
Stale incident, no standing instruction. Nightly logs: `~/Library/Logs/incursion-nightly.log` (main), `~/Library/Logs/incursion-nightly-debug-<date>-<n>.log` (per launch). `launchctl list | grep incursion` shows a PID when running.
History: docs/rules-history/nightly-harness.md#nightly-2026-09-12-stalled-and-killed.

## nightly-autonomy-resume
Stale resume note. Nightly harness lives at `~/Scripts/nightly-harness` (outside this repo, not under git); install with `cd ~/Scripts/nightly-harness && bin/install-agent.sh incursion`.
History: docs/rules-history/nightly-harness.md#nightly-autonomy-resume.

## nightly-commit-hook-conflict
**HISTORICAL, fixed 2026-09-14.** Superseded: `.beads/hooks/pre-commit` admits a commit when `NIGHTLY_BRANCH` names the current `nightly/` branch. `git commit --no-verify` is still NOT approved — see `beads-blocking-a-commit-fix-the-bead`.
History: docs/rules-history/nightly-harness.md#nightly-commit-hook-conflict.

## nightly-doc-run-where-to-check
The nightly/doc run is the LAUNCHD HARNESS, NOT cron. Do NOT check crontab or `tools/doc_freshness_cron.sh` — dead, crontab deleted. The harness is a separate repo `~/Scripts/nightly-harness`, run by launchd job `com.brianhill.incursion.nightly` at 01:00 (`bin/nightly.sh incursion`). To check status: read `~/Scripts/nightly-harness/projects/incursion/nightly/YYYY-MM-DD.md` — `*-FAILED.md` means aborted, a plain dated file with a Budget section means finished. On a clean run it merges `nightly/<date>` into master locally (nothing pushed).
Why: crontab and the dead cron script will falsely report "no nightly run".
History: docs/rules-history/nightly-harness.md#nightly-doc-run-where-to-check.
