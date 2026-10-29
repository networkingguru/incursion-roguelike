# launchd jobs

`com.brianhill.incursion.seed-sweep.plist` runs `tools/nightly_seed_sweep.sh --budget 14400` at 23:00 each night, in the shared checkout.
It sweeps the live and smoke checks over other seeds, in parallel lanes, until the 4-hour budget ends. Its log is `~/Library/Logs/incursion-seed-sweep.log`.
Install: `cp -f tools/launchd/com.brianhill.incursion.seed-sweep.plist ~/Library/LaunchAgents/`, then `launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.brianhill.incursion.seed-sweep.plist`.
Uninstall: `launchctl bootout gui/$(id -u)/com.brianhill.incursion.seed-sweep`, then delete the copied plist.
The nightly harness job (`com.brianhill.incursion.nightly`, 01:00) lives in `~/Scripts/nightly-harness`, not here.
