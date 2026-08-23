<!-- citations: this-port -->

# Overnight doc reconciliation — 2026-08-20

Baseline: tree clean at `df3e85b`. Every change is from this run.
`git diff` is the complete delta. `git checkout .` undoes all of it.

**782 claims checked. 358 corrected. 2 deliberately left. 16 files changed, every
one a document. No source file touched. Nothing committed.**

---

## Read these three things first

### 1. A live bug, found by a documentation job

`src/Player.cpp:1460-1461`

```c
&& i != RecentVerbs[4] && i != RecentVerbs[4])
```

`RecentVerbs[3]` is never tested; `[4]` is tested twice. The loop above adds all
five recent verbs, so once you have used five different verbs the fourth-most-recent
is listed twice and the `y` menu shows 64 rows instead of 63. Platform-independent,
so it is upstream's typing slip, not a port artefact.

### 2. The ledger said "not sent" about work rmtew has been reading for a day

Two rows in the `Base-code bugs fixed locally` table claimed the `Rect::PlaceWithin`
repair (inc-65j) and the `Creature::MakeNoise`/`Reveal` crash (inc-upw.37) were
unsent. Both went out on 2026-08-20 as comment `5358799776` on rmtew issue 40,
confirmed live via `gh api`. The table is fixed.

Still wrong, because they are source and not mine to edit:
- `inc/Base.h:307` and `src/Creature.cpp:349` still say NOT SENT.
- `docs/outgoing/README.md` still says `issue40-reply.md` is "Not sent, and not
  yet read by Brian". It was posted 2026-08-19. That file also omits
  `issue40-addendum.md` and `issue8-reply.md`, both posted. Your directory, untouched.

A wrong "not sent" is how the same thing gets sent twice. That is the exact
failure the marking convention exists to prevent.

### 3. Four source comments carry rotted line citations

Nothing gates these. `tools/check_citations.sh` only guards outgoing documents.
Two of the four sit inside `upstream:` blocks, which is text that goes to rmtew.

| Comment at | Cites | Should be |
|---|---|---|
| `src/Target.cpp:1104` (`upstream:`) | `inc/Base.h:577` | `inc/Base.h:734-740` |
| `src/Registry.cpp:159` (`upstream:`) | `src/Registry.cpp:955` | `:1055-1060` |
| `src/Wposix.cpp:698-702` | `Term.cpp:1969`, "three callers" | `:2164`, five callers |
| `src/Debug.cpp:1057-1058` | two `MakeLev.cpp` spans | `:2109-2125`, `:1143-1145` |

The `Debug.cpp` one had propagated: the README was quoting that comment faithfully,
so the comment was the origin of the error.

---

## What was wrong, by cause

**Line-number drift dominates — roughly 300 of the 358.** Three insertions did most
of the damage:

- A 102-line `INC6D5_PROBE` block at the top of `src/Event.cpp` moved every
  citation into that file by 97 or 102.
- `src/Registry.cpp` grew to 1469 lines, moving everything after the header by
  200-400. Two agents found this independently.
- `src/Display.cpp` moved by 705-900 lines across several documents.

**Errors that were never true, and would mislead a reader:**

- `docs/ENGINE-MAP.md` said `Term` declares 183 pure virtuals. 183 is the count for
  the whole header; `Term`'s own body holds 135 and `TextTerm` re-declares 48 to keep
  them pure. **The page's own check command produced the wrong number**, so anyone
  re-running it would have confirmed the error.
- `docs/incursionscript.md` gave `EV_RATETARG` the return values of `EV_ISTARGET`.
  `CANNOT_CAST_IT` is `-1`, call sites test `!= ABORT` and `ABORT` is `2` — so a
  script author following that page would have shown the item they meant to hide.
- The same page called `EV_GODPULSE` "an indication of an angry god". It is the
  opposite: `src/Creature.cpp:1568` throws `EV_ANGER_PULSE` when angry.
- `docs/ENGINE-MAP-CREATURE.md` cited a `#if 0` block (`src/Display.cpp:575-693`)
  holding compiled-out twins of six `…At` accessors. **A citation into dead code
  passes every check a reader would run** — right file, right line, right text —
  while naming code the compiler never emits.
- `docs/ENGINE-EVENTS.md` said an all-`NOTHING` sweep reaches `Fatal`. `src/Event.cpp:454`
  returns first. Two of those three `Fatal` calls are unreachable, and both print
  `PRE_` for a POST event and `POST_` for a PRE event (`PRE(a)` is `a+500`,
  `POST(a)` is `a+1000`, `inc/Defines.h:4392-4393`).
- `docs/YUSE-VERBS.md` said social verbs are hidden from the menu unless their
  conditions hold. The menu hides nothing; those conditions gate the prompt you get
  *after* you Talk.
- `docs/ENGINE-SCRIPT.md` said every macOS binary carries the resource compiler.
  `build_macos.sh:74` now has `COMPILER=no`, so a shippable binary exists.

**Stale counts, all re-run with the command recorded beside them:** `src/` is 61
files and 150,669 lines; `tools/` is 61 files; 47 upstream markers not 45; 44 key
scripts not 28; 40 checks not 28; ruleset 82,382 lines; 15 HexDecimal branches
not 16 (fetched fresh).

---

## Negative results worth having

- **No fix in `FIXED.md` has been reverted or overwritten.** All 24 entries traced
  to a live fix site; six of the named checks re-run and passing.
- **No dead verb came back to life.** All 24 re-checked, all still handler-less.
- **The event-name list is exact.** 183 `#### EV_` headings, 183 `#define EV_`
  macros, identical sets both directions.
- **The architecture claims hold.** No threads at all — zero hits for `pthread`,
  `std::thread`, `CreateThread`, `<thread>`, `<future>`, `std::async`,
  `dispatch_async`, OpenMP. No callback loop: three `atexit()` reporters and one
  `SIGALRM` watchdog, and both graphical backends pass `NULL` where a callback
  would go.
- **The upstream ledger is otherwise sound.** 47 markers, every one has a row, no
  row orphaned, none vanished.
- **Identity sweep clean** on both shipped files — no name, no email, no
  `/Users/brianhill`, no local path. `d5b954c` held.

---

## Code items — nothing was changed, you decide

1. `src/Player.cpp:1460-1461` — the `RecentVerbs[4]` duplicate above.
2. `tools/package_macos_app.sh:83` defaults `VERSION` to `1.0`, so the release 2
   bundle probably identifies itself as 1.0. No document is wrong about this,
   which is why nothing caught it.
3. `Map::Grid` allocated as `sizeX*sizeY + 1` (`src/MakeLev.cpp:1333`, `:1421`)
   but serialized as `sizeX*sizeY` (`inc/Map.h:493`). No live fault found —
   `Map::At` clamps to `Grid[0]` — but the two numbers do not disagree on purpose.
4. `INCURSION_DEPTH_PROBE` is overdue for deletion. Its own comment at
   `src/MakeLev.cpp:2369` says remove it once `inc-x9i` settles; that closed 2026-08-19.
5. `src/AbiCheck.cpp:76` says "these four are bitfield structures" then asserts five.
6. `src/Move.cpp:1353` assigns a bool into an `EvReturn`, so `else if (r == ABORT)`
   at `:1363` is dead.
7. Two ledger rows name a fix site with no `upstream:` marker (already `inc-6s5`).
8. Two markers state a lower evidence tier than their ledger row
   (`src/Creature.cpp:2614`, `src/Create.cpp:3812`). The markers are the stale side.

## Decisions only you can make

- **`docs/PORT-STATUS.md` argues with itself about AppleScript.** The dated
  2026-08-14 block calls System Events broken and a dead end; the exact command it
  quotes now works. The block is marked unedited history, so nobody touched it.
- **Two landed fixes have no `FIXED.md` entry** — the menu handle truncation
  (`df3e85b`) and the twenty prestige-class claims (`f5444e9`). Left unwritten
  because the entries carry your voice.
- **`AGENTS.md` vs `CLAUDE.md`**: one policy line differs. `AGENTS.md:146` tells a
  team-maintainer agent to run `bd dolt push`; `CLAUDE.md` omits it. `bd dolt show`
  reports `Remotes: (none)`, so that command has no remote here today.
- **`docs/DEVTOOLS-AUDIT.md` says "Nine symbols, 672 guarded lines."** Only eight
  symbols still exist — `FLICKER_PROBE` was deleted. Does "nine" mean nine in the
  inventory, or nine present today? Neither number was changed.
- **`lib/program.i` is generated and gitignored.** Documents citing it will go stale
  on every build and its counts are absent on a machine that never ran `-compile`.
  Affects `docs/ENGINE-SCRIPT.md` and `docs/ENGINE-EVENTS.md`.
- **Sixteen `MSG_*` event codes** (`inc/Defines.h:4590-4605`) work with `On Event`
  exactly like `EV_*` codes and are absent from `docs/incursionscript.md`. Listed,
  not added.

---

## The per-document reports

Each holds every change with the old text, the new text, and the command or source
line that proves it, plus that document's unverified list.

`docdelta/` — AGENTS, ENGINE-EVENTS, ENGINE-MAP, ENGINE-MAP-CREATURE, ENGINE-SCRIPT,
ENGINE-SERIALISATION, FIXED, PORT-STATUS, README, REPORTING-GATE, SCRIPT-LANG,
TOOLS, VERBS-HEADLESS.

## For the cron

`docs/doc-deps.tsv` — 591 rows, `source-path <TAB> doc-name`, 235 distinct source
files. Built from what each agent actually cited, not guessed. Given a commit range,
the intersection of its changed paths with column 1 names the documents to re-check.

Hottest files: `inc/Defines.h` feeds 11 documents, `src/Wposix.cpp` and
`src/Registry.cpp` 10 each, `src/Term.cpp` and `src/Display.cpp` 9.

This is the one new file in the repo. It is untracked; delete it if you want it
elsewhere.
