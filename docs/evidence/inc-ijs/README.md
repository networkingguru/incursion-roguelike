# inc-ijs -- segfault on turn 1 of a new game

Captured 2026-08-21/22. The defect is NOT fixed and NOT reproduced; these are
the three artefacts that survive the session that found it. Read the bead
first: `bd show inc-ijs`.

| file | what it is |
| --- | --- |
| `crash-2026-08-21-172658.ips` | the macOS crash report, copied out of `~/Library/Logs/DiagnosticReports/` before it ages out. `Thing::RemoveStatiFrom + 220`, `KERN_INVALID_ADDRESS at 0xc`. |
| `errors-at-crash.log` | `logs/errors.log` as it stood at the crash. Three entries name handle 34929 and keep the `Thing::NotifyGone` frame the .ips backtrace lost to a tail call. |
| `destroy-probe.patch` | the instrumented build. Applies to `inc/Inline.h`, `src/Display.cpp`, `src/Main.cpp`, `src/Res.cpp`. |

## Rebuilding the probe

```sh
git apply docs/evidence/inc-ijs/destroy-probe.patch
EXTRA_CXXFLAGS="-DDESTROY_PROBE -g" BACKEND=posix OUT=incursion-destroyprobe ./build_macos.sh
DESTROY_PROBE_LOG=/absolute/path/probe.log INCURSION_BIN=./incursion-destroyprobe \
    tools/headless.sh tools/keys/explore.keys 1
```

`DESTROY_PROBE_LOG` must be ABSOLUTE. The game changes its working directory,
so a relative path writes nowhere and the first version of this probe produced
an empty file and looked like a clean run.

To drive the reincarnate path, pre-create the run directory, copy
`save/gallery.dat` into its `save/`, and pass `INCURSION_RUN_DIR`. Without a
gallery the game refuses reincarnation before doing anything, and the run
measures nothing while still exiting 0.

The probe writes four kinds of line: `Play entry` and `Cleanup ENTRY`/`EXIT`
dump the queue, and `DANGLING`, `REQUEUE` and `STALE` each fire on one way an
entry can go bad. None of the three fired in any run so far.
