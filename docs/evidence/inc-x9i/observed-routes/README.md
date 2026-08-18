# inc-x9i: the routes, observed rather than reasoned

Captured 2026-08-18. Until now the reply to PR #43 argued most of these from the
source. Every route below has now crashed a real session. The stack separates
them into four shapes; it does NOT resolve which branch of `Creature::Descend`
ran, and the table below says so.

## Method

`to-bottom-level.keys` is the survey's own path to depth 10 -- the dive script
truncated after `w p "10" ENTER`. It must be the same path: **map content is not
a property of the seed alone.** Generation consumes the RNG stream, so a session
that descends straight to 10 gets a different level 10 from one that walked the
nine above it. A straight descent on seed 3362 produced a depth 10 with ZERO
chasm squares where the survey recorded 282.

A temporary probe in `Player::MoveDepth` stands the player beside (or, for the
levitation test, on) a real `TF_FALL` square on the bottom level, and for the
levitation test grants `LEVITATION`. It creates no terrain: it chooses where the
player stands, which is what a wizard teleport would do by hand. Everything
after that is ordinary game code -- the confirmation, the fall, the descent.

## What crashed, and how

Six sessions, all exit 139 with `EXC_BAD_ACCESS`, `KERN_INVALID_ADDRESS at 0x0`
in `Player::MoveDepth`. Grouped by the stack the `.ips` file actually carries,
NOT by which key script was run -- one climb session took a different path
inside `Creature::Descend` from the other, and an earlier version of this table
hid that by listing the script instead of the stack.

| stack above `Player::MoveDepth` | report |
|---|---|
| `TerrainEffects` <- `Creature::Walk` | `...-062022.ips`, `...-062023.ips` |
| `TerrainEffects` <- `Creature::Descend` | `...-062105.ips` |
| `Creature::Descend` | `...-062025.ips`, `...-063306.ips`, `...-063307.ips` |

The walking stack is the important one for severity: no recursion, no
`PlaceAt`, no wizard command. `Creature::Walk` calls `TerrainEffects()` directly
(`Move.cpp:1122`), which tests `TF_FALL`, prints "You fall...", waits for ENTER
and calls `MoveDepth(m->Depth + 1)`. The screen before the crash shows exactly
that.

The bare `Creature::Descend` stack is the important one for `safe`. Upstream's
`Descend` enters `MoveDepth` directly from two places and BOTH pass `true`:

- `Skills.cpp:4161`, the levitation branch, `MoveDepth(m->Depth + 1, true)`;
- `Skills.cpp:4181`, reached only when the Climb check SUCCEEDS,
  `MoveDepth(m->Depth + 1, true)`.

So those three crashes prove a `safe=true` call site reaches the fault.

**Which branch, measured.** A release stack cannot separate the two, so a probe
in each branch reports which one ran. `INCURSION_DESCEND_PROBE=1`, same key
scripts, same seeds, every session still exiting 139:

```
descendprobe-levitate-seed777.log   Descend branch=levitation depth=10 enters_MoveDepth=directly, safe=true
descendprobe-levitate-seed111.log   Descend branch=levitation depth=10 enters_MoveDepth=directly, safe=true
descendprobe-climb-seed111.log      Descend branch=climb-succeeded depth=10 enters_MoveDepth=directly, safe=true
descendprobe-climb-seed777.log      Descend branch=climb-failed depth=10 enters_MoveDepth=via TerrainEffects, safe=false
```

The file name is added here; everything after it is the probe's own line, one per
run. Do not quote the composed form as if the probe printed it.

Four probe lines for four `Descend` reports, one run per report: the two
levitation runs and the successful climb give the three bare `Descend` stacks,
and the failed Climb check gives the stack with the extra `TerrainEffects`
frame. Logs: `descendprobe-levitate-seed777.log`,
`descendprobe-levitate-seed111.log`, `descendprobe-climb-seed111.log`,
`descendprobe-climb-seed777.log`.

An earlier version of this section had three probe lines and claimed the
four-report mapping from them. That was an inference wearing a measurement's
clothes; the fourth run closed it.

An AddressSanitizer build was tried first and was the wrong tool. It never
reached `main`: ASAN's initialiser calls `malloc`, which re-enters the
initialiser, and the process spun on `StaticSpinMutex::LockSlow` at 99% CPU for
53 minutes. Do not reach for ASAN on this platform without checking that the
binary starts.

None of this changes the conclusion about `safe`, which does not depend on the
call site: the null read at `Feature.cpp:887` happens forty lines before the
`safe` test at `:927`.

## inc-tos, the one-element overread, now observed too

The levitation branch asks `GetDungeonMap` for `m->Depth + 1` before it descends
(`Skills.cpp:4158`). On the bottom level that is `DUN_DEPTH + 1`.
`Feature.cpp:988` allocates `min(MAX_DUNGEON_LEVELS, DUN_DEPTH + 1)` handles, so
the last valid index is `DUN_DEPTH`. A probe that reports any request outside
that allocation fires on both levitation runs and on no other
(`dungeonmapprobe-levitate-seed777.log`,
`dungeonmapprobe-levitate-seed111.log`):

```
GetDungeonMap depth=11 allocated=11 last_valid_index=10 reads_index=11
```

Eleven handles, indices 0 to 10, and the function is asked for index 11. The
loop at `:1004` runs `i <= Depth` and the return at `:1017` reads `[Depth]`.
The probe stays silent on both climb runs. That is the control, and it is
narrower than it looks: the probe reports out-of-allocation REQUESTS, not calls,
so the silence shows the climb branch never makes one. That the climb runs call
`GetDungeonMap` at all -- once per wizard depth change -- is read from the code
and the key script, not measured by this probe.

## Why there is no AddressSanitizer report here

There was going to be one. It is not coming, and the reason is worth recording
so nobody spends the time again.

`EXTRA_CXXFLAGS="-fsanitize=address -g" BACKEND=posix ./build_macos.sh` builds
and links fine on macOS 15 arm64, and the binary then hangs before `main`:

```
__asan::AsanInitInternal -> InitializeShadowMemory -> get_dyld_hdr
  -> _Block_copy -> malloc -> __sanitizer_mz_malloc -> AsanInitFromRtl
    -> StaticSpinMutex::LockSlow -> internal_sched_yield
```

ASAN's own initialiser allocates, the allocation routes back into the
initialiser, and it spins on the lock the first call holds. Sampled at 53
minutes and 99% CPU with no file open and no output written. An earlier note in
this file guessed the run was merely slow; it was deadlocked, and that guess
cost an hour.

Both questions ASAN was for are answered above by targeted probes instead, in
about ninety seconds each.
