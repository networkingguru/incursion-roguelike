# launchd jobs

`com.brianhill.incursion.seed-sweep.plist` runs `tools/nightly_seed_sweep.sh --budget 14400` at 23:00 each night, in the shared checkout.
It sweeps the live and smoke checks over other seeds, in parallel lanes, until the 4-hour budget ends. Its log is `~/Library/Logs/incursion-seed-sweep.log`.
Install: `cp -f tools/launchd/com.brianhill.incursion.seed-sweep.plist ~/Library/LaunchAgents/`, then `launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.brianhill.incursion.seed-sweep.plist`.
Uninstall: `launchctl bootout gui/$(id -u)/com.brianhill.incursion.seed-sweep`, then delete the copied plist.
`com.brianhill.incursion.epic-gate.plist` runs `tools/epic_nightly_gate.sh` at 05:45 each night, in the shared checkout.
It builds the `inc-pu6v` epic tip in a detached worktree, runs the full gate there, and reports checks that turned red since the night before. Its log is `~/Library/Logs/incursion-epic-gate.log`.
Install: `cp -f tools/launchd/com.brianhill.incursion.epic-gate.plist ~/Library/LaunchAgents/`, then `launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.brianhill.incursion.epic-gate.plist`.
Uninstall: `launchctl bootout gui/$(id -u)/com.brianhill.incursion.epic-gate`, then delete the copied plist.
The nightly harness job (`com.brianhill.incursion.nightly`, 01:00) lives in `~/Scripts/nightly-harness`, not here.
