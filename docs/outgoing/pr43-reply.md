(c) is right and I will change it. All line numbers are against master. I have split each answer into what I measured and what I only read, because each answer has a measured core and an inferred edge, and you should be able to tell which is which without taking my word for it.

## a) How many times can it call itself.

**Answer.** The chain descends at most `DUN_DEPTH - 1` levels — 9 in The Goblin Caves, 14 if the player selects Challenge difficulty — and the call after the last of those faults on a null resource instead of returning.

**Measured.**

The cycle is real and it fires. Seed 3362 of my dive script, exit 139 ([crash-seed3362.ips](https://github.com/networkingguru/incursion-roguelike/blob/master/docs/evidence/inc-x9i/crash-seed3362.ips)), reproduced twice from a clean run directory:

```
Player::MoveDepth          <- KERN_INVALID_ADDRESS at 0x0
Creature::TerrainEffects
Thing::PlaceAt
Player::MoveDepth
Player::WizardOptions
```

A nested `MoveDepth` entered at depth 10, asked for 11, and took the `BELOW_DUNGEON` branch. **The deepest nesting I have observed is 2**, because my harness descends by wizard command and then falls once; I have not driven a character down a chain of chasms.

The bottom level really does have holes with nothing under them. Eight seeded headless sessions, one run directory each, 60 generated levels ([depthprobe-8seeds.log](https://github.com/networkingguru/incursion-roguelike/blob/master/docs/evidence/inc-x9i/depthprobe-8seeds.log)): all three sessions that reached depth 10 found chasm there — 16, 282 and 21 squares — and on those levels the generator was asked for no down-stairs at all (`stairs_down=0`). Sixteen of the 31 generated levels shallower than depth 5 carry chasm too.

**Read from the source, not run.**

Only `Player` re-enters `MoveDepth`. `Thing::MoveDepth` is a one-line `Remove(true)` ([Feature.cpp:850-852](https://github.com/rmtew/incursion-roguelike/blob/master/src/Feature.cpp#L850-L852)), so a monster that falls is deleted rather than moved, and `Player` is the only override ([Creature.h:1103](https://github.com/rmtew/incursion-roguelike/blob/master/inc/Creature.h#L1103)). The path back into it is a cycle of three functions:

```
Player::MoveDepth        calls PlaceAt          Feature.cpp:935
Thing::PlaceAt           calls TerrainEffects   Display.cpp:219
Creature::TerrainEffects calls MoveDepth        Move.cpp:1380
```

The last step is `MoveDepth(m->Depth + 1)` — always exactly one level down, so the chain is monotonic. It omits the second argument, so `safe` takes the default declared on `Thing` ([Map.h:719](https://github.com/rmtew/incursion-roguelike/blob/master/inc/Map.h#L719)), which is `false`, and the fall-avoidance block at [Feature.cpp:927](https://github.com/rmtew/incursion-roguelike/blob/master/src/Feature.cpp#L927) is guarded by `safe`. So the path that recurses is one of several that run with `safe=false`, and it is the one that does not step the player off a fall square on arrival.

The ceiling is arithmetic on that. `DUN_DEPTH` is data: 10 for The Goblin Caves (`lib/dungeon.irh:17`), and [Annot.cpp:468-470](https://github.com/rmtew/incursion-roguelike/blob/master/src/Annot.cpp#L468-L470) returns 15 for `DUN_DEPTH` on any annotated resource once difficulty is `DIFF_CHALLENGE` or above. Reaching the ceiling needs more than chasm on every level: with `safe=false` the arrival point is the player's own `x,y`, re-rolled only when that is out of bounds, solid or a vault (`Feature.cpp:898`, `:921-925`), so the chain continues where the *same coordinates* are chasm on the level below, or where a re-roll happens to land on chasm — and with 282 of them on seed 3362's depth 10, a re-roll is not a remote possibility. 14 is a bound, not an expectation.

The fault itself: a fall from the bottom level asks for `DUN_DEPTH + 1` and takes the branch at [Feature.cpp:884-887](https://github.com/rmtew/incursion-roguelike/blob/master/src/Feature.cpp#L884-L887). No dungeon in `lib/` defines `BELOW_DUNGEON`, so the id is 0, `Game::Get` returns NULL for a zero id ([Res.cpp:312](https://github.com/rmtew/incursion-roguelike/blob/master/src/Res.cpp#L312)), and the branch reads `RES(mID)->Type` with no test. The up path reads the same kind of constant thirteen lines earlier and does test it ([Feature.cpp:873-875](https://github.com/rmtew/incursion-roguelike/blob/master/src/Feature.cpp#L873-L875)): `if (!mID) return;`.

I had assumed this was unreachable, because [MakeLev.cpp:1452](https://github.com/rmtew/incursion-roguelike/blob/master/src/MakeLev.cpp#L1452) says it is: *"No chasms on the last dungeon level, because there is nowhere to fall to!"*. That test, and the `MIN_CHASM_DEPTH` test above it ([:1449](https://github.com/rmtew/incursion-roguelike/blob/master/src/MakeLev.cpp#L1449), default 5 at [Annot.cpp:539](https://github.com/rmtew/incursion-roguelike/blob/master/src/Annot.cpp#L539)), live in the **streamer** picker. Chasm also arrives as an ordinary **room**, and the room picker applies neither rule. Its gates are the region's `RoomTypes`, then `DepthCR` against the region's own `Depth`, then `MIN_VAULT_DEPTH` for vaults, then `RF_CORRIDOR` ([MakeLev.cpp:2397-2400](https://github.com/rmtew/incursion-roguelike/blob/master/src/MakeLev.cpp#L2397-L2400)) — no last-level test and no `MIN_CHASM_DEPTH`. Three shipped `RF_ROOM` regions place chasm: `"Twisting Chasm"` (`lib/dungeon.irh:3497`, `Depth: 2`), whose `Floor:` is `$"chasm"`; `"Floating Rock;1"` (`lib/dungeon.irh:3660`, `Depth: 3`), whose floor is obsidian but whose grid tiles `'X'` to `$"chasm"`; and `"Jagged Chasm"` (`lib/dungeon.irh:3644`), which sets `* BLOB_WITH $"chasm"` and declares **no `Depth:` at all**, so the picker's depth gate passes for it at every level of every dungeon. Since no dungeon defines `ROOM_WEIGHTS`, `GetList`'s default ([Annot.cpp:365](https://github.com/rmtew/incursion-roguelike/blob/master/src/Annot.cpp#L365)) puts every non-`NOGEN` `RF_ROOM` region into every dungeon's pool. The survey above does not say which picker placed the chasm it counted, but it is what the room-picker reading predicts.

`safe` decides only whether the *cycle* is entered, not whether the fault is reached. The null read is at the top of the function; the `safe` test is forty lines below it, so a call from the bottom level faults before `safe` is ever looked at. That matters for one of the call sites in particular: `Skills.cpp:4181` is the `>` command's *"Climb down the chasm?"* branch, and on the bottom level it calls `MoveDepth(m->Depth + 1, true)` and dereferences `RES(0)` directly. No wizard mode, no script, no trap, no recursion — a character who climbs down a chasm on depth 10 hits it. The wizard command cannot do that, incidentally: `Debug.cpp:803-805` refuses any depth above `DUN_DEPTH`, which is why in my crash report the null read is in the nested call rather than in the wizard call itself.

What `safe=true` does buy is that the arrival point steps off a fall square, so those sites enter the *cycle* only when the landing square and all eight of its neighbours are fall squares. Of the six that pass it, three cannot reach the `BELOW_DUNGEON` branch at all — `Skills.cpp:4008` and `:4066` ascend, and `Prayer.cpp:1482` passes a literal depth of 1 — and three can: `Feature.cpp:260`, `Skills.cpp:4161` and `:4181`.

One site passes nothing at all: wizard-mode Ascend/Descend at `Debug.cpp:810` calls `MoveDepth(i)`, so it runs with `safe=false`. That call site sits in `Player::WizardOptions`, the frame at the bottom of the crash report above — my harness reached depth 10 by that route, so the outer call in the trace is itself an unsafe one.

Nor is `MoveDepth` the only way in. `Thing::PlaceAt` fires `TerrainEffects()` for any live creature on both its paths (`Display.cpp:109` same map, `:219` across maps), and `Creature::Walk` calls it too (`Move.cpp:1122`). So the ordinary case needs no recursion and no wizard command at all: a player who walks onto a chasm square on the bottom level falls — `TerrainEffects` tests `TF_FALL` and `!isAerial()`, prints "You fall...", waits for ENTER and calls `MoveDepth(m->Depth + 1)` — which on that level is `MoveDepth(DUN_DEPTH + 1)` and the null dereference. Flying or levitating avoids it. Walking does not, though it is not silent: chasm carries `TF_WARN` and its `EV_MON_CONSIDER` returns `ABORT` for non-aerials (`lib/dungeon.irh:680-686`), so the player is asked "Confirm enter the chasm?" first (`Move.cpp:476-479`). Answering yes is enough. I have not driven a character there by walking — that is read from the source — but it is the shortest route to the fault, and it does not depend on anything unusual.

The scripted ones are a different matter, and I think a second defect. The script API declares one parameter — `system void T_THING::MoveDepth(int16 NewDepth);` ([Api.h:226](https://github.com/rmtew/incursion-roguelike/blob/master/inc/Api.h#L226)) — and the binding calls the C++ method with one argument ([dispatch.h:680](https://github.com/rmtew/incursion-roguelike/blob/master/lib/dispatch.h#L680)), so every scripted call runs with `safe=false`. Two shipped scripts write `,true)` at the call and get `false` for it: `lib/religion.irh:2992-2993`, where Khasrach casts the player down as far as depth 10, and `lib/wspells.irh:7065`. The first can therefore drop a player onto the bottom level's chasm with no avoidance step, which would be a non-wizard route into the fault above. Two ordinary traps create chasm where the player stands. `"small trapdoor trap"` and `"large trapdoor trap"` are `EA_TERRAFORM` effects with `xval: TERRA_FLOOR; rval: $"chasm"` (`lib/threats.irh:799` and `:1085`), and they are `EF_MUNDANE`, which is to say non-magical rather than optional — they ship in `lib/threats.irh`, so no add-on module is involved. The generator places them itself: `MakeLev.cpp:2171` and `:2184` pick a random `AI_TRAP` effect for the level's `DepthCR` and drop a `Trap` on the square, so the trap is in place from generation and the chasm appears when it fires. One firing on the bottom level writes real chasm where the player stands, with no magic, no module and no wizard command. **None of this paragraph is measured.** I have not run any of these paths.

## b) Provable maximum stack from recursive calls.

**Answer.** 2,400 bytes for each level descended with this patch applied, of which 512 is the array it moves onto the stack. Master as it stands today, with the `static`, costs 1,888 — and that second figure is subtraction, not disassembly: I measured 2,400 and 512 separately and took one from the other.

**Measured, two ways that agree.** A probe recorded the stack pointer on entry to `MoveDepth` and its distance from the frame still open above it: **2,416 bytes**, of which that probe accounted for 16 ([stackprobe-seed3362.log](https://github.com/networkingguru/incursion-roguelike/blob/master/docs/evidence/inc-x9i/stackprobe-seed3362.log)). That log holds one nested entry, not many — the `nest=1` lines have nothing above them to measure against.

The prologues of a build carrying the patch and no probe give the same total independently. One level costs three frames, not one, because the recursion runs through `PlaceAt` and `TerrainEffects` ([frames-arm64.md](https://github.com/networkingguru/incursion-roguelike/blob/master/docs/evidence/inc-upw.15/frames-arm64.md) has the disassembly):

```
Player::MoveDepth          0x60 +  0x230 =  656
Thing::PlaceAt             0x60 +  0x1b0 =  528
Creature::TerrainEffects   0x60 +  0x460 = 1216
                                   total = 2400
```

The patch's own cost is an A/B on one keyword. Two builds of my tree, same command and same flags, both carrying my current diagnostic probes so that they cancel — a fatter set than the 16-byte one above, which is why both frames are large. The only difference is the `static` on `Thing *GoWith[64]`:

```
Thing *GoWith[64]           0x60 + 0x6e0 = 1856
static Thing *GoWith[64]    0x60 + 0x4e0 = 1344
```

The difference is **512 bytes**, which is 64 pointers of 8, and the `static` build carries `__ZZN6Player9MoveDepthEsbE6GoWith` in `.bss` while the other does not.

I should be careful about what those 512 bytes buy, because I nearly claimed too much for them. The obvious worry is that `static` makes one array for the whole process, so a nested call would refill it before the outer call reaches `GoWith[i]->PlaceAt(new_m, nx, ny)` at [Feature.cpp:937-938](https://github.com/rmtew/incursion-roguelike/blob/master/src/Feature.cpp#L937-L938). Following it through, that does not happen in the fall chain: the outer call has already `Remove`d its followers from the old map at `:906-911` and has not yet placed them on the new one, so the nested call's own collection loop finds nothing and writes nothing. `gwc` is a local, so the outer call still places its own entries. I have not found a sequence in which the static array is actually corrupted — the closest is a follower abandoned on the arrival level by an earlier visit, which the nested call would collect and which would then be placed twice. So this remains hardening, as I described it originally, and the figures above are what the hardening costs.

**Arithmetic on those figures, at a depth nobody has reached.** Fourteen levels would cost 33,600 bytes with the patch and 26,432 without it, the array accounting for 7,168 of the first. That counts the recursion's own three frames only: a true peak adds whatever the deepest ordinary callee needs at the innermost level, and `MoveDepth` calls `theGame->SaveGame(*this)` on every entry (`Feature.cpp:858`), which I have not measured. Against the 8 MB main-thread stack on macOS, or the 1 MB Win32 default, 33,600 is about 3% of the smaller figure, so stack is not the constraint here. At 2,400 bytes a level it takes about 437 chained levels to reach 1 MB. A different compiler gives different frames; the method is just the prologue.

## c) Why not allocate it with the number of followers.

**Answer.** Happy to, and I will send it in whatever shape you prefer — it is your call. One thing worth knowing before I do: sizing it from a count has a catch here.

To size the array you must count the followers in a pass of its own, and whenever two followers sit next to each other in `Things` the collecting pass produces **fewer** than the count, so code that trusts the count as its bound reads entries that were never filled. The allocation would be right and the collection would still be wrong. My patch took the cheap route instead and added a `break`, which turns an overflow into a silent drop and leaves the magic number where it was. `GoWith[gwc++]` ([Feature.cpp:909](https://github.com/rmtew/incursion-roguelike/blob/master/src/Feature.cpp#L909)) is not tested against 64 at all today, which is why I touched the function.

**Measured.** The collecting loop is already losing followers. I instrumented it to record each follower's index in `Things` before it ran, what it gathered, and what was still standing on the old level afterwards, then gave a wizard-mode character kobolds and made each one a follower:

```
MoveDepth depth=1 followers_before=3 at=[393,394,395] collected=2 left_behind=1
```

Ten seeds, one run directory each; nine reached a level change. Every session whose followers were consecutive in `Things` lost exactly one, silently. The control is seed 777, whose two followers sat at 395 and **397**, with one index between them: both arrived. The log records where the followers were, how many came and how many stayed, but not which one stayed. Table and logs: [docs/evidence/inc-90u](https://github.com/networkingguru/incursion-roguelike/tree/master/docs/evidence/inc-90u), reproduction keys in [tools/keys/followers.keys](https://github.com/networkingguru/incursion-roguelike/blob/master/tools/keys/followers.keys). Sixty turns after one such descent the same session shows one live kobold, one kobold corpse and a black orc on the same screen. No third kobold appears in either screen (both are in that directory).

**Read from the source, not run.** The loop walks by index ([Feature.cpp:906-911](https://github.com/rmtew/incursion-roguelike/blob/master/src/Feature.cpp#L906-L911)): `MapIterate` advances with `i++` ([Base.h:78-79](https://github.com/rmtew/incursion-roguelike/blob/master/inc/Base.h#L78-L79)), `c->Remove(false)` deletes that creature from `m->Things` ([Display.cpp:1130](https://github.com/rmtew/incursion-roguelike/blob/master/src/Display.cpp#L1130)), and `Array::Remove` memmoves the tail one place left ([Base.cpp:535](https://github.com/rmtew/incursion-roguelike/blob/master/src/Base.cpp#L535)). The entry after a removed one slides into the index just finished with, and `i++` steps over it. Three consecutive followers therefore yield the first and the third; two consecutive yield only the first. Nothing brings the straggler along later either: the turn loop iterates the player's current map only (`Main.cpp:220`), so a creature on another level takes no turns, and a monster that reaches stairs goes through `Thing::MoveDepth`, which deletes it. Other code moves creatures between maps — `Feature.cpp:270` and `:278` for dungeon entry and return, and several spells — but this loop is the only thing that brings a player's followers with him. What it carries is whatever `ts.isLeader(this)` accepts, which is a creature whose *first* leader-type target — leader, summoner, master or mount — is the player (`Target.cpp:903-921`): summoned creatures, animal companions, mounts, and creatures dominated or commanded. A merely charmed creature does not qualify.

**Proposal, not yet written.** Drop the counting pass and grow the list instead. `NArray` is already the container `Map::Things` uses ([Map.h:184](https://github.com/rmtew/incursion-roguelike/blob/master/inc/Map.h#L184)); it grows on `Add` and frees itself in `~Array`, so there is no magic number, no `break` that drops a follower at 64, and no cleanup path to get wrong. I would use `NArray<hObj,5,5>` rather than invent a new size, because `Base.cpp` instantiates the template explicitly and `Array<hObj,5,5>` is already on that list — a fresh `<8,8>` would need a line added there or it will not link. I would store handles rather than `Thing*` as well. Nothing dangles today — `Remove(false)` only unlinks, and the `F_DELETE` flag and the destroy queue are both behind `isDelete` (`Display.cpp:1171-1186`) — so that part is defensive rather than a fix. No STL is involved: the game's own sources use none, and the only `std::` uses in `src/`, `inc/` and `lib/` are two `std::wstring` locals in the platform layer.

One detail I checked before proposing a local: `Array::Array()` returns early while the registry is loading, before it assigns `Items`, so a stack-local `Array` would destruct on an unset pointer if it were ever constructed inside that window. `MoveDepth` is reached only from gameplay and the window is inside `Registry::LoadGroup` (`Registry.cpp:561` to `:705`), so the two cannot overlap.

Fixing the index skip is a separate change from the container, and I would send them separately unless you would rather see one patch. The bottom-level fault in (a) is separate from both, and I am happy to raise it on its own.

This work was done with AI assistance (Claude) — the probes, the seeded runs and the analysis, not only the prose. Everything under a **Measured** heading is reproducible: the seeded runs from the harness and seeds in my fork, the frame figures by disassembling a build, and the 512 by building the pair described above. I can supply any of it, or the raw logs.
