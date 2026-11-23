#!/bin/bash
# gate: live
# inc-as123: a weapon in a creature's hand gives light; a dropped one does not. Reads the WEAPON_LIGHT lines of
# src/WeaponLightProbe.cpp (INCURSION_WEAPON_LIGHT_PROBE): a dark room, the player stripped of light and weapons, one weapon held
# at a time, the light map's color logged on nine squares east of the holder.
# Cases: flaming long sword (fire color, radius 2); dropped (none); flame blade (2) and produced flame (4); glowing +2 long sword
# (white, radius 6); Sunblade (golden, radius 6); torch plus Sunblade (two sources: torch color near, golden at 5-6); brilliant
# energy (blue, radius 4); frost, shocking, thundering, corrosive, holy, unholy, lawful, chaotic, soul-drinking (none); a monster
# with a flaming weapon (its own square); Nine Lives Stealer (none, then crimson radius 2 while its activation status stands, then none);
# the WQ_ENERGY help sentence.
# Phase 2 (WEAPON_FLASH lines): the light a weapon hit makes on the struck creature. The probe calls Weapon::QualityDmgSingle on a
# victim and samples the light map while the flash shows (TargetFlashHook TF_LIT), then strikes the same victim with a reference
# flash named in the probe by color, reach and flicker, and the check compares the two. Cases: flaming, frost, shocking and
# soul-drinking flash the struck square plus 1 (3x3 squares) and not 2; corrosive and thundering flash nothing; a flaming or frost
# burst crit reaches 2 (21 squares), a flaming burst without a crit reaches 1, a corrosive or thundering burst crit flashes nothing;
# holy, lawful, chaotic, balance and unholy flash 1 in their colors (a holy weapon on a good victim deals no extra damage and flashes
# nothing); a disruption hit that kills an undead flashes 2 in white, a saved one nothing; fire, shocking and chaos flicker and the
# rest stay steady; no square is lit before the hit, none more than 3 from the victim during it, and none after it.
# RED: revert the Light.cpp and Values.cpp change (or make LightHeldRadius return 0); the flaming case finds no light and the check FAILs.
# fact: character -- fixture xsummon-priest-seed5-opt0822
# fact: settings -- options-2026-08-22.dat, named in INCURSION_OPTIONS; the probe forces OPT_ANIMATION Normal
# fact: terrain and darkness -- the probe builds the map and clears legacy Lit/Bright
# fact: every other light -- the probe removes the player's light, weapon and ready-hand items, deletes every other creature, and zeroes infravision and shadow range after each recompute
# fact: the weapons -- the probe makes each item itself (Item::Create; the Sunblade and Nine Lives Stealer through their effect's own Item::Initialize), sets its plus and quality directly, and logs the plus it holds; no roll decides them
# fact: the monster holder -- a hobgoblin the probe places at a fixed square (PX+14, PY) with 500 hit points; no roll decides its light
# fact: the Nine Lives Stealer's activation status -- the probe grants the status the activation grants (EFF_FLAG1 named for the effect, source the sword) and removes it; no prompt, no roll
# fact: flicker -- no LightTick runs, so each source reads its steady value; no clock decides it
# fact: the player's alignment -- alignment weapons are held by the monster, with play mode off, so no level drain and no roll decides it
# fact: the hit and the crit -- the probe calls Weapon::QualityDmgSingle itself with isCrit set per case; no attack roll decides them
# fact: the extra damage -- logged as xdmg and required above 0 where a quality deals it; its dice never enter the light
# fact: the disruption save -- LOFSetForcedSaveThrowRoll in the probe: 1 fails the save, 20 passes it (the catalog's saving-throw control)
# fact: the alignments of actor and victim -- the probe takes the first generated monster, in module order, that the quality's alignment test accepts and that lights no square, and asserts it with Creature::isMType; no roll decides it
# fact: the flash's flicker -- LightTick at 31 fixed times on the victim's square; a steady flash does not change, fire and arc do
# Phase 3 (WEAPON_FLIGHT lines): the light of a thrown or fired weapon. The player throws or fires through Throw(EV_RATTACK) at a
# hobgoblin ten squares east, with the attack roll forced (20 hits, 1 misses); the light map is sampled at each flight step
# (ES_FLIGHT, issued after the light moves) and at the impact flash. Cases: a flaming dagger thrown, and a flaming sheaf arrow fired
# from a short bow, light 9 squares (1 around the missile) in fire color at every step, steady, moving east one square at a time, and
# nothing after they land; a hit adds the phase 2 flame flash (9 squares), a miss none; a plain arrow fired from a flaming bow lights its
# flight; a frost dagger and a plain dagger or arrow light nothing in flight; fire seeds light no flight and flash 21 squares (reach 2)
# in fire color where they strike, land on a creature after a miss, or land on an empty square. A thrown produced flame lights its
# flight like a flaming dagger; a hit flashes 9 squares (reach 1) in fire color, a miss none.
# RED: make LightMissileOf return false (the flaming flight cases find no light); or drop the FlashSquare calls in Creature::RAttack (seeds); or make the produced-flame branch there a no-op (flame-hit finds no flash).
# fact: the thrown and fired shots -- Throw(EV_RATTACK) with LOFSetForcedRoll 20 or 1; no attack roll decides a hit or miss
# fact: the victim and its square -- a hobgoblin at (PX+10, PY) with 500 hit points, fixed by the probe
# fact: the flight path -- a straight row east of the player; the aim square is fixed, no roll decides it
# fact: the flight's clock -- the light's own effect clock (EffectLight::Wait), never the wall clock; the hook reads the light map at each step and 31 LightTick samples at step 3
# fact: the missiles and launcher -- made by the probe (Item::Create), quality set directly through EXTRA_QUALITY, bow wielded through the same path as every other case
# fact: the flash's life -- FlashStruck cools the flash to its end on its own clock before it returns; the probe reads the light map after
# Phase 4 (WEAPON_FLASH flaming-open and flaming-hidden, WEAPON_HIDDEN lines): light from a weapon the player cannot see adds no light the player can see.
# A full-height wall column hides the victim, or a monster that throws, from the player. A flaming hit behind the wall makes no flash (no
# flash call, no lit square anywhere, none the player sees); the same hit in the open flashes and the player sees it. A flaming dagger thrown
# behind the wall lights no flight step; fire seeds landing behind it (on a creature, past a miss, on an empty square) flash nothing; the same
# shots in the open light the flight and flash the player sees. Every hidden case asserts the player has line of sight to none of the area.
# RED: make EffectLight::Sees return true (hit and seeds cases find light); with LOFDrawFlight's PossiblyPause gate also removed the flight case does too.
# fact: the wall and the shooters -- the probe writes the wall column (x PX+7 or PX+3) itself, places the thrower at PX+8 and the victim at PX+16, gives the thrower true sight; no roll decides them
# fact: what the player sees -- Map::LineOfSight from the player's fixed square, asserted by the probe per case (vis); no light or roll decides it
# Exit 0 PASS, 1 FAIL, 2 INCONCLUSIVE.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

KEYS=tools/keys/effect-light.keys
OPTIONS=tools/fixtures/options-2026-08-22.dat
LOAD=xsummon-priest-seed5-opt0822

[ -x ./incursion-headless ] || { echo "INCONCLUSIVE: ./incursion-headless is missing. Run: BACKEND=posix ./build_macos.sh"; exit 2; }

RUN_DIR="$ROOT/logs/runs/$(date +%Y%m%d-%H%M%S)-$$-weapon-light"
INCURSION_WEAPON_LIGHT_PROBE=1 INCURSION_LIGHT_PROBE=1 INCURSION_RUN_DIR="$RUN_DIR" \
    INCURSION_OPTIONS="$OPTIONS" INCURSION_LOAD="$LOAD" \
    tools/headless.sh "$KEYS" 1 > "$RUN_DIR.out" 2>&1
log="$RUN_DIR/logs/errors.log"
grep -aq 'WEAPON_LIGHT: DONE' "$log" 2>/dev/null || { echo "INCONCLUSIVE: no WEAPON_LIGHT: DONE in $log"; exit 2; }
if grep -aq 'WEAPON_LIGHT: INCONCLUSIVE' "$log"; then
    grep -a 'WEAPON_LIGHT: INCONCLUSIVE' "$log"; exit 2
fi

python3 -I - "$log" "$ROOT/src/Tables.cpp" <<'PY'
import re, sys
log = open(sys.argv[1], errors="replace").read()
tables = open(sys.argv[2], errors="replace").read()
cases = {}
for m in re.finditer(r"WEAPON_LIGHT: CASE (\S+) lightrange=(-?\d+) heldradius=(-?\d+) row=((?: \d+,\d+,\d+)+) (.*?) weapon=\[(.*?)\]", log):
    row = [tuple(int(v) for v in t.split(",")) for t in m.group(4).split()]
    cases[m.group(1)] = dict(lr=int(m.group(2)), row=row, extra=m.group(5), weapon=m.group(6))
FIREFLASH = (255, 250, 220)   # the fire flash at age 0 (its ramp starts white-hot), as the struck-creature flash reads
FIRE, WHITE, GOLD, BLUE, CRIMSON, TORCH = (255,140,40), (255,250,235), (255,215,110), (150,180,255), (220,40,60), (255,147,41)
def norm(c):
    m = max(c) or 1
    return tuple(v * 255 // m for v in c)
def d2(a, b): return sum((x - y) ** 2 for x, y in zip(norm(a), norm(b)))
def lit(c): return max(c) > 0
bad = []
def need(name):
    if name not in cases: bad.append("no case " + name); return None
    return cases[name]
def lit_to(name, color, radius, lr=None):
    """squares 0..radius lit in color, radius+1.. dark"""
    c = need(name)
    if not c: return
    if lr is not None and c["lr"] != lr: bad.append("%s: sight range %d, want %d" % (name, c["lr"], lr))
    for d, px in enumerate(c["row"]):
        if d <= radius:
            if not lit(px): bad.append("%s: square %d unlit" % (name, d))
            elif max(px) >= 40 and d2(px, color) > 300:   # a faint edge square rounds its hue, so only squares of value 40 up are graded
                bad.append("%s: square %d is %s, not the hue of %s" % (name, d, px, color))
        elif lit(px): bad.append("%s: square %d lit %s beyond radius %d" % (name, d, px, radius))
def dark(name, weapon=True):
    c = need(name)
    if not c: return
    if c["lr"] != 0: bad.append("%s: sight range %d, want 0" % (name, c["lr"]))
    if any(lit(px) for px in c["row"]): bad.append("%s: some square lit" % name)
    if weapon and c["weapon"] in ("-", ""): bad.append("%s: no weapon held, the case proves nothing" % name)
dark("none", weapon=False); dark("plain")
lit_to("flaming", FIRE, 2, 2)                       # a
dark("flaming-dropped", weapon=False)               # b
lit_to("flame-blade", FIRE, 2, 2); lit_to("produced-flame", FIRE, 4, 4)
lit_to("glowing", WHITE, 6, 6)                      # c: white
c = need("glowing")
if c and "plus=2" not in c["extra"]: bad.append("glowing: the sword's plus is not 2 (%s)" % c["extra"])
lit_to("sunblade", GOLD, 6, 6)                      # c: golden
c = need("sunblade")
if c and "glowing=1" not in c["extra"]: bad.append("sunblade: the item is not glowing (%s)" % c["extra"])
if c and d2(c["row"][0], WHITE) < 300: bad.append("sunblade: color is white, not golden")
# d: a torch plus the Sunblade are two sources
lit_to("torch", TORCH, 4, 4)
ts, tc, sc = need("torch+sunblade"), need("torch"), need("sunblade")
if ts and tc and sc:
    if ts["lr"] != 6: bad.append("torch+sunblade: sight range %d, want the larger, 6" % ts["lr"])
    for d in (5, 6):   # past the torch's 4 squares: the Sunblade alone, golden (square 6 is too faint to grade a hue)
        if not lit(ts["row"][d]): bad.append("torch+sunblade: square %d unlit" % d)
    if d2(ts["row"][5], GOLD) > 600: bad.append("torch+sunblade: square 5 is %s, not golden" % (ts["row"][5],))
    if d2(ts["row"][0], sc["row"][0]) < 400 or d2(ts["row"][0], tc["row"][0]) < 400:
        bad.append("torch+sunblade: square 0 %s is one source's color, not a mix of both (torch %s, sunblade %s)" % (ts["row"][0], tc["row"][0], sc["row"][0]))
lit_to("energy", BLUE, 4, 4)                        # brilliant energy
for n in ("frost", "shocking", "thundering", "corrosive", "holy", "unholy", "lawful", "chaotic", "soul-drinking"):
    dark("dark-" + n)                               # e
lit_to("monster-flaming", FIRE, 2, 2)               # f
dark("nls-inactive"); lit_to("nls-active", CRIMSON, 2, 2); dark("nls-ended")
# phase 2: weapon hit flashes
fl = {}
for m in re.finditer(r"WEAPON_FLASH: CASE (\S+) calls=(\d+) row=((?: \d+,\d+,\d+)+) stray=(\d+) var=(\d+) lit=(\d+) base=(\d+) after=(\d+) xdmg=(-?\d+) died=(\d+) refvar=(\d+) ref=((?: \d+,\d+,\d+)+) seen=(\d+) vis=(\d+)", log):
    rw = lambda t: [tuple(int(v) for v in x.split(",")) for x in t.split()]
    fl[m.group(1)] = dict(calls=int(m.group(2)), row=rw(m.group(3)), stray=int(m.group(4)), var=int(m.group(5)), lit=int(m.group(6)),
                          base=int(m.group(7)), after=int(m.group(8)), xdmg=int(m.group(9)), died=int(m.group(10)), refvar=int(m.group(11)), ref=rw(m.group(12)), seen=int(m.group(13)), vis=int(m.group(14)))
# tag: (reach or None for no flash, flickers, extra damage dealt, died)
SPEC = {
 "flaming": (1, True, True, 0), "frost": (1, False, True, 0), "shocking": (1, True, True, 0), "soul-drinking": (1, False, True, 0),
 "corrosive": (None, False, True, 0), "thundering": (None, False, True, 0),
 "flaming-burst-nocrit": (1, True, True, 0), "flaming-burst-crit": (2, True, True, 0), "frost-burst-crit": (2, False, True, 0),
 "corrosive-burst-crit": (None, False, True, 0), "thundering-burst-crit": (None, False, True, 0),
 "holy": (1, False, True, 0), "holy-mismatch": (None, False, False, 0), "lawful": (1, False, True, 0), "chaotic": (1, True, True, 0),
 "balance": (1, False, True, 0), "unholy": (1, False, True, 0),
 "flaming-open": (1, True, True, 0),
 "disruption-failed-save": (2, False, False, 1), "disruption-saved": (None, False, False, 0),
}
SQUARES = {1: 9, 2: 21}
for tag, (reach, flick, xd, died) in SPEC.items():
    c = fl.get(tag)
    if not c: bad.append("no flash case " + tag); continue
    if c["base"] or c["after"]: bad.append("%s: %d squares lit before the hit, %d after it (need 0 and 0)" % (tag, c["base"], c["after"]))
    if c["stray"]: bad.append("%s: %d squares lit more than 3 from the victim" % (tag, c["stray"]))
    if (c["xdmg"] > 0) != xd: bad.append("%s: extra damage %d, %s" % (tag, c["xdmg"], "want some" if xd else "want none"))
    if c["died"] != died: bad.append("%s: victim died=%d, want %d" % (tag, c["died"], died))
    if reach is None:
        if c["calls"] or c["lit"] or any(lit(px) for px in c["row"]): bad.append("%s: a flash showed (calls %d, lit %d)" % (tag, c["calls"], c["lit"]))
        continue
    if c["calls"] != 1: bad.append("%s: %d flashes, want 1" % (tag, c["calls"])); continue
    if c["lit"] != SQUARES[reach]: bad.append("%s: %d squares lit, want %d (reach %d)" % (tag, c["lit"], SQUARES[reach], reach))
    for d, px in enumerate(c["row"]):
        if d <= reach:
            if not lit(px): bad.append("%s: square %d unlit" % (tag, d))
            elif max(abs(a - b) for a, b in zip(px, c["ref"][d])) > 2:
                bad.append("%s: square %d is %s, the reference flash is %s" % (tag, d, px, c["ref"][d]))
        elif lit(px): bad.append("%s: square %d lit %s beyond reach %d" % (tag, d, px, reach))
    if (c["var"] > 0) != flick: bad.append("%s: flicker range %d, want %s" % (tag, c["var"], "some" if flick else "none"))
    if (c["refvar"] > 0) != flick: bad.append("%s: the reference flickers %d, want %s" % (tag, c["refvar"], "some" if flick else "none"))
# the player cannot see: a flaming hit behind a wall adds no light at all (inc-jw0hw lights only squares the player sees); its control, the same hit in the open, flashes
op, hd = fl.get("flaming-open"), fl.get("flaming-hidden")
if not op or not hd: bad.append("no flaming-open or flaming-hidden case")
else:
    if op["vis"] == 0 or op["seen"] == 0: bad.append("flaming-open: control shows no flash to the player (vis %d, seen %d)" % (op["vis"], op["seen"]))
    if hd["vis"] != 0: bad.append("flaming-hidden: the player sees %d squares around the victim, want 0" % hd["vis"])
    if hd["xdmg"] <= 0: bad.append("flaming-hidden: no hit landed (xdmg %d), the case proves nothing" % hd["xdmg"])
    if hd["calls"] or hd["lit"] or hd["seen"] or any(lit(px) for px in hd["row"]) or hd["base"] or hd["after"]:
        bad.append("flaming-hidden: light from an unseen hit (flashes %d, lit %d, seen %d, before %d, after %d)" % (hd["calls"], hd["lit"], hd["seen"], hd["base"], hd["after"]))
colours = {m.group(1): tuple(int(m.group(i)) for i in (2, 3, 4)) for m in re.finditer(r"WEAPON_FLASH: COLOR (\S+) (\d+),(\d+),(\d+)", log)}
for name, want in (("holy", (255, 250, 235)), ("lawful", (90, 150, 255)), ("chaotic", (220, 40, 60)), ("balance", (220, 225, 240))):
    if colours.get(name) != want: bad.append("color %s is %s, want %s" % (name, colours.get(name), want))
# phase 3: thrown and fired weapons light their flight
fcase = {}
for m in re.finditer(r"WEAPON_FLIGHT: CASE (\S+) hp=\S+ victim=\[.*?\] steps=(\d+) hit=(\d+) var=(\d+) calls=(\d+) flashlit=(\d+) fc=(\d+),(\d+),(\d+) base=(\d+) after=(\d+) path=(.*)", log):
    st = []
    for t in m.group(12).split():
        if t == "none": continue
        x, y, n, sy, c, nc = t.split(":")
        st.append(dict(x=int(x), y=int(y), lit=int(n), stray=int(sy), c=tuple(int(v) for v in c.split(",")), nc=tuple(int(v) for v in nc.split(","))))
    fcase[m.group(1)] = dict(steps=int(m.group(2)), hit=int(m.group(3)), var=int(m.group(4)), calls=int(m.group(5)), flashlit=int(m.group(6)),
                             fc=(int(m.group(7)), int(m.group(8)), int(m.group(9))), base=int(m.group(10)), after=int(m.group(11)), path=st)
def flight(name, lit_flight, hit, calls=None, flashlit=None, flash_fire=False):  # flash_fire: the impact center is the fire flash at age 0
    c = fcase.get(name)
    if not c: bad.append("no flight case " + name); return
    if c["steps"] < 3 or len(c["path"]) != c["steps"]: bad.append("%s: %d flight steps, want 3 or more" % (name, c["steps"])); return
    if c["hit"] != hit: bad.append("%s: hit=%d, want %d" % (name, c["hit"], hit))
    if c["base"] or c["after"]: bad.append("%s: %d squares lit before the shot, %d after it (need 0 and 0)" % (name, c["base"], c["after"]))
    if lit_flight:
        xs = [s["x"] for s in c["path"]]
        if any(b <= a for a, b in zip(xs, xs[1:])): bad.append("%s: the light does not move along the flight: x %s" % (name, xs))
        for i, s in enumerate(c["path"]):
            if s["lit"] != 9: bad.append("%s: step %d lights %d squares, want 9 (1 around the missile)" % (name, i, s["lit"]))
            if s["stray"]: bad.append("%s: step %d lights %d squares more than 1 from the missile" % (name, i, s["stray"]))
            if max(s["nc"]) < 40 or d2(s["nc"], FIRE) > 300: bad.append("%s: step %d square below the missile is %s, not fire" % (name, i, s["nc"]))
        if c["var"]: bad.append("%s: the in-flight light changes by %d over its clock, want steady" % (name, c["var"]))
    else:
        for i, s in enumerate(c["path"]):
            if s["lit"]: bad.append("%s: step %d lights %d squares, want none" % (name, i, s["lit"]))
    if calls is not None and c["calls"] != calls: bad.append("%s: %d impact flashes, want %d" % (name, c["calls"], calls))
    if flashlit is not None and c["flashlit"] != flashlit: bad.append("%s: impact flash lights %d squares, want %d" % (name, c["flashlit"], flashlit))
    if flash_fire and (max(c["fc"]) < 40 or d2(c["fc"], FIREFLASH) > 300): bad.append("%s: impact center is %s, not fire" % (name, c["fc"]))
flight("dagger-flaming-hit", True, 1, 1, 9, True)       # the hit reaches the phase 2 hit flash through QualityDmgSingle
flight("dagger-flaming-miss", True, 0, 0)
flight("arrow-flaming-hit", True, 1, 1, 9, True)
flight("arrow-flaming-miss", True, 0, 0)
flight("arrow-plain-flaming-bow", True, 1)              # a flaming launcher passes its fire to the arrow
flight("dagger-frost-hit", False, 1, 1, 9)
flight("dagger-plain-hit", False, 1, 0)
flight("arrow-plain-hit", False, 1, 0)
flight("flame-hit", True, 1, 1, 9, True)                # a thrown produced flame: the ordinary 1-square fire flash on the creature it hits
flight("flame-miss", True, 0, 0)                        # ...and none on a miss
flight("seeds-hit", False, 1, 1, 21, True)               # fire seeds: the wide fire flash where they strike
flight("seeds-miss", False, 0, 1, 21, True)
flight("seeds-empty", False, 0, 1, 21, True)
# shots out of the player's sight: a monster beyond a wall throws; no flight light, no impact flash, no light on any square the player sees
hid = {m.group(1): dict(hit=int(m.group(2)), steps=int(m.group(3)), calls=int(m.group(4)), flashlit=int(m.group(5)), seen=int(m.group(6)), vis=int(m.group(7)), base=int(m.group(8)), after=int(m.group(9)))
       for m in re.finditer(r"WEAPON_HIDDEN: CASE (\S+) hit=(\d+) steps=(\d+) calls=(\d+) flashlit=(\d+) seen=(\d+) vis=(\d+) base=(\d+) after=(\d+)", log)}
def unseen(name, hit, want_flash):
    c = hid.get(name)
    if not c: bad.append("no hidden case " + name); return
    if c["hit"] != hit: bad.append("%s: hit=%d, want %d" % (name, c["hit"], hit))
    if c["vis"] != 0: bad.append("%s: the player sees %d squares of the shot's area, want 0" % (name, c["vis"]))
    if c["steps"] or c["calls"] or c["flashlit"] or c["seen"] or c["base"] or c["after"]:
        bad.append("%s: light from an unseen shot (flight steps %d, flashes %d, flash squares %d, seen lit %d, before %d, after %d)" % (name, c["steps"], c["calls"], c["flashlit"], c["seen"], c["base"], c["after"]))
def control(name, hit, flash):
    c = hid.get(name)
    if not c: bad.append("no control case " + name); return
    if c["hit"] != hit: bad.append("%s: hit=%d, want %d" % (name, c["hit"], hit))
    if c["vis"] == 0: bad.append("%s: the player sees none of the shot's area, the control proves nothing" % name)
    if flash:
        if c["calls"] != 1 or c["seen"] == 0: bad.append("%s: the impact flash did not show to the player (flashes %d, seen lit %d)" % (name, c["calls"], c["seen"]))
    elif c["steps"] < 3 or c["seen"] == 0: bad.append("%s: the flight light did not show to the player (steps %d, seen lit %d)" % (name, c["steps"], c["seen"]))
control("dagger-open", 1, False); unseen("dagger-hidden", 1, False)
control("seeds-open", 1, True)
unseen("seeds-hidden-hit", 1, False); unseen("seeds-hidden-miss", 0, False); unseen("seeds-hidden-empty", 0, False)
# help text: the WQ_ENERGY entry ends with the ruled sentence
m = re.search(r"\{ WQ_ENERGY,\s*((?:\"[^\"]*\"\s*)+)\}", tables[tables.index("A brilliant energy weapon") - 80:])
sent = "It sheds a steady blue light as bright as a torch."
text = "".join(re.findall(r'"([^"]*)"', m.group(1))) if m else ""
if not text.endswith(sent): bad.append("the WQ_ENERGY help entry does not end with: " + sent)
for n in sorted(cases):
    print("%-20s lr=%d row=%s" % (n, cases[n]["lr"], " ".join("%d,%d,%d" % px for px in cases[n]["row"][:8])))
if bad:
    print("FAIL: " + "; ".join(bad)); sys.exit(1)
print("PASS: held weapons light their holder's squares in the ruled colors and radii; dropped and non-light weapons give none; weapon hits flash the struck creature in the ruled colors, reach and flicker; thrown and fired lit weapons light their flight; fire seeds flash where they strike; a weapon the player cannot see adds no light the player sees.")
PY
