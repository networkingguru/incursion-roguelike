#!/bin/bash
# gate: live
# inc-jw0hw: a magical effect lights the squares it covers. Case A: a fire
# flash on one square of a dark room lights that square, shows it in the
# player's view in fire color, dims (without hiding it) when its level drops,
# and leaves it dark when removed. Later cases add each effect shape.
# fact: character -- fixture xsummon-priest-seed5-opt0822
# fact: settings -- options-2026-08-22.dat, named in INCURSION_OPTIONS; the probe forces OPT_ANIMATION Normal
# fact: terrain and darkness -- the probe builds the map and clears legacy Lit/Bright
# fact: monsters -- placed by the probe at fixed offsets
# fact: effect radii and colors -- read from the data by the probe (TEFF lval, cval)
# fact: which squares are struck -- no roll decides them (as check_ball_shape.sh)
# fact: player's sight in case C -- the probe makes the player's eight neighbors opaque
# fact: aim square -- the probe aims every cast at (PX+8, PY), a fixed offset from the player's fixed square
# fact: kobold squares -- the probe places each kobold at a fixed offset from the aim square or the player
# fact: a square's age -- the flash's own clock, set by the probe (LightFlashSetClock) or the sum of the ball's ring waits; never the wall clock
# fact: the ruled fire ramp -- the probe's own table (FireRampAt), from logs/ramp-mock/mock.py
# fact: messages a cast prints -- the same seeded run twice, flash on and flash off; the probe records MsgHistory
# fact: T1 kobold squares -- fixed offsets (0,-2) and (0,+2) from the aim square (PX+5, inside the fireball's own range); the probe verifies both are struck
# fact: T2 the touch lands or misses -- the probe forces the attack roll (LOFSetForcedRoll 20 for a hit, 1 for a miss)
# fact: T2 the touch spell and its hand charge -- the probe gives the player the TOUCH_ATTACK status for Chill Touch
# fact: T3 target square -- a kobold at (PX+6, PY), a fixed offset from the player's fixed square
# fact: T cases' light -- no light but the flash: the probe zeroes the player's light, infravision and shadow ranges
# fact: FW1 the fireworks cast square and radius -- the probe aims Pyrotechnics;flash at (PX+8, PY); the radius is the data's lval, read back from the hook's rings
# fact: FW1 which squares the player sees -- an open dark room, no wall inside the radius; the probe computes the expected set from its own LineOfSight call
# fact: FW1 a ring's start and stage clock -- the effect's own clock, the sum of the animation's waits (stage length from the radius); never the wall clock
# fact: FW1 each square's shape and glyph -- computed from the square's offset from the center and its stage; no roll decides them
# fact: FW1 each square's light -- born when its ring starts; the probe reads LightLevelAt and LightLitAt after the frame's refresh
# fact: LM lightning range -- the probe grants +30 caster levels to every school (BONUS_SCHOOL_CASTING_LEVEL), so the range is 5 + level/2 squares whatever the fixture's level
# fact: LM1 kobold squares and hit points -- kobolds placed at (PX+2, PY), (PX+3, PY), (PX+8, PY), fresh each cast, hit points set to 500 so none dies; the probe aims at (PX+10, PY)
# fact: LM1 which squares the stroke leaves the line -- cosmetic_random() picks them; the check reads only invariants every path keeps (distance, on-line at creatures and ends, adjacency, no solid, stroke glyph)
# fact: LM1 the stroke leaves the line in the gap (PX+4..PX+7) in at least 1 of 20 casts -- each of 4 gap squares stays on the line with chance at most 1/2 given any history (3 or 5 open candidates, at least 2), so a cast stays on the line with chance at most 1/16 and 20 casts all do with chance at most 1e-24
# fact: LM1 two casts draw different paths -- a cast repeats a given path with chance at most 1/16 (the 4 gap squares alone), so all 19 later casts repeat the first with chance at most 1e-22
# fact: LM2 corridor -- the probe walls every square of the room off the cast row; the path is the line by rule, no roll decides it
# fact: LM3 chain target -- one kobold at (PX+6, PY) as the chosen victim; the arc ends within 1 square of it, no roll decides that
# fact: LM4 non-meandering casts -- fire breath, Acid Arrow and Magic Missile are not lit electricity, so no hook fires whatever the roll
# fact: LM5 the spell's own squares -- no roll decides them: the spell walks a straight row from the player
# fact: CP1 cast square, radius and kobold -- the probe aims Hypnotic Pattern at (PX+8, PY) with one kobold on that square; the radius is the data's lval (2), the expected squares are those within it that the probe's own LineOfSight call says the player sees
# fact: CP1 picks per square and the gap between picks -- the effect's own clock: the 1500 ms hold runs in steps of 33 ms and a square picks again at the first step 100 ms after its last pick, so 12 picks 132 ms apart; no roll and no wall clock decide them
# fact: CP1 the glyph and color of each pick -- cosmetic_random() picks them; the check reads only invariants every pick keeps (a symbol that is not a letter, digit or @; a palette color that is not black, shadow, grey or white; the light base color equals LightEffectColour of the glyph color)
# fact: CP1 at least 4 distinct colors and 4 distinct glyphs -- 252 picks (21 squares, 12 each) draw each from 8 values, so fewer than 4 distinct of either happen with chance below 1e-90
# fact: CP1 a re-pick changes a square's color -- 231 consecutive pairs of picks each repeat the color with chance 1/8, so none changing it has chance below 1e-200
# fact: CP2 aim, kobolds and range -- the probe aims Colour Spray at (PX+10, PY), kobolds at (PX+3, PY) and (PX+6, PY), 500 hit points each, MM_EXTEND set as the effect reel sets it; the beam walks a straight row, so no roll decides its squares
# fact: CP2 both kobolds are struck -- a beam strikes every creature on its line by design (isMulti); the probe counts the data's strike message "spray of colours strikes" twice, so no saving throw or attack roll decides it
# fact: CP2 a drawn beam picks again -- the first square of a 10-square beam stays up about 315 ms of effect clock at 35 ms a square, so it picks again at least twice; no roll decides it
# fact: CP3 the orb's square list -- Chromatic Orb aimed at a kobold at (PX+6, PY) walks the straight row to it; a hit or a miss roll does not change the walk
# fact: CP3 the orb is the unprompted clear orb -- the probe casts with no caster level bonus, so the fixture's own caster level (below 3) takes the lowest branch and loses 4 mana; the probe grades the 4, so a higher level that would open the color prompt fails the check
# fact: CP4 non-pattern effects -- Nightmare smite;actual blast (a COL_RAINBOW globe without the flag) and Fireball carry no EF_COLOR_PATTERN, so no roll lets the hook fire
# fact: CP5 animation None -- the probe sets OPT_ANIMATION 2 for the cast; no roll decides that no pick fires
# fact: CP6 the gameplay random stream -- the probe re-initializes it with init_genrand just before each of two casts, so both casts start from one state; the check compares the next four draws, whatever the values are
# fact: BH1 cast squares and kobold -- the probe casts Burning Hands east from the player's fixed square with a kobold at (PX+1, PY), 500 hit points; the three squares are the spell's fixed shape for the direction (the probe writes them from the spell text), no roll decides them
# fact: BH1 a square's age -- the effect's own clock: the 500 ms hold runs in 33 ms steps and the probe takes the step nearest 100, 300 and 550 ms; never the wall clock
# fact: BH2 the diagonal squares -- the probe casts northeast (EDir set by the probe); the shape for a diagonal is fixed by the spell's own code, no roll decides it
# fact: BH3 the struck creature -- a kobold on a square of the spell's shape; the spell strikes every creature there with no attack roll or save deciding the flash, which comes before the hit resolves
# fact: BH4 the wall square -- the probe writes a wall on the middle of the three squares; the spell skips a solid square, no roll decides it
# fact: BH5 animation None -- the probe sets OPT_ANIMATION 2 for the cast; no roll decides that nothing lights
# fact: BH6 out of sight -- the probe makes the player's eight neighbors opaque (as case C) and a kobold at (PX+10, PY) casts with the player as its victim, so the script holds; no roll decides the line of sight
# fact: BH8 the terminal's glyph -- the CP437 247 glyph, read with T1->GetGlyph at the three squares of the east shape, a fixed offset from the player's fixed square, at each 33 ms step of the hold; no roll decides it
# fact: BH7 the gameplay random stream -- each cast runs in its own process (INCURSION_BH7_ANIM), from init_genrand(7770002) just before the cast, so no state carries between casts; the check compares the stream position (seed, draws taken) when the script's light ends, before the strike, which re-seeds the stream; whatever the values are
# fact: BH7 the struck kobold -- a kobold at (PX+1, PY), 500 hit points, on the first of the spell's squares; the spell strikes it with no roll deciding that
# fact: BH7 process-to-process determinism -- two runs at the same animation must give equal draws; the check runs animation Normal twice and is INCONCLUSIVE if they differ
# fact: ST1 the skull and its square -- the probe places a skull trap at (PX+4, PY), a fixed offset from the player's fixed square, with the player as its caster (the Skull Trap spell's own stati); a kobold on that square wakes it
# fact: ST1 the waking -- the probe throws the trap's effect as Trap::TriggerTrap does, with the avoid save left out, so no roll decides that the trap fires
# fact: ST1 the glow's color -- the color the script names (COL_CRIMSON) through LightEffectColour; the check reads the mid-rise light's hue against it, each scaled to its brightest channel, within 8 per channel
# fact: ST2 a step's age -- the effect's own clock: the 1000 ms rise runs in 33 ms steps and the probe takes the step nearest 100, 500 and 900 ms; never the wall clock
# fact: ST2 the level at a step -- LightFlashLevel set by the rise from its own clock; no flicker (the rise sets the flash steady), so no cosmetic roll moves it
# fact: ST8 the last rise step -- the effect clock's final 33 ms step of the 1000 ms rise, the frame at the skull square; the level there is 1.0 by the rise's own arithmetic, so no roll decides it
# fact: ST8 the glyph color -- LightEffectGlyphAt at the skull square, the rise level times the base color; crimson hue within 12 per channel, brightest channel at least 230
# fact: ST9 the fire wave's squares -- the squares 1, 3 and 6 east of the skull (the globe's radius is lval 6), a fixed offset from the skull's fixed square; the wave hook reports each in ring order, so no roll decides which is lit first
# fact: ST9 the ramp colors -- the glyph color LightEffectGlyphAt reads at each shown step, green over red at the first step at least 0.8; and the square's light color LightAt reads at every wave hook call, through the cooling after the glyphs go, first lit sample against the last with brightest channel 60+, green over red down at least 0.15; the fire ramp and the wave clock decide both, no roll
# fact: ST10 the fire glyphs gone -- the wave hook's glyph 0 call for each fire square, in call order; the first necromantic call comes after the last fire call
# fact: ST10 the necromantic row -- LightEffectColour(COL_NECRO) read as the table row, the owner's ruled deep purple 80,20,140; a ruled value, no roll
# fact: ST10 the necromantic hue -- LightEffectGlyphAt at each necromantic step, the flash's own dark ramp of LightEffectColour(COL_NECRO); hue within 12 per channel
# fact: ST11 the old highlight -- GlobeGlyphHook calls during the trap's cast; the plain globe is Pyrotechnics;blast (a globe with a cval and no EF_WAVES), cast the way case G3 casts it
# fact: ST9 the ring and hold timing -- the wave clock (the effect's own, never the wall clock) at each wave hook call: ring d is reported at (d+1) x 10 ms, the glyphs hold 60 ms after the last ring; no roll decides it
# fact: ST14 the wave light's cooling -- LightAt green over red at the skull's square and at the square 6 east of it, both read at the fire wave's last ring step (the first wave hook call that shows the square 6 east); skull's square 0.6 or less, 6 squares out 0.85 or more; the wave's light life (1.5 times its glyph time) and the fire ramp decide both, no roll
# fact: ST12 the creature flash's place -- WaveFlashHook (a flash starts as a ring reaches a struck creature) against the count of wave hook calls so far; the kobold on the skull's square is struck by both waves, and its hit points (500) show that no hit came first
# fact: ST12 the kobold's drawn glyph -- T1->GetGlyph at the skull's square (a fixed offset from the player's fixed square) against the kobold's own Image, read at each wave hook call; no roll decides it
# fact: ST12 the kobold's drawn color -- LightEffectGlyphAt at that square, the call the renderer's LitPaint makes; the fire ramp's near-white start and warm tail and the necromantic hue are the ramp tables' own values, no roll decides them
# fact: ST12 the kobold's square within the first hook call at its ring -- the struck set is one kobold at the skull's square with 500 hit points; no roll decides that the waves strike it
# fact: ST12 no struck flash after the last wave -- TargetFlashHook TF_LIT count during the trap's cast, which only the old end-of-globe flash raises
# fact: ST13 the plain globe's order -- GlobeGlyphHook recolors counted before the first TargetFlashHook TF_LIT; Pyrotechnics;blast, with a kobold at (aimX+1, PY+1) inside its radius, cast as case G3 casts it
# fact: ST3 the last frame before the explosion -- the frame the light map holds when the script's light ends; the check reads its level at the skull square against the rise's top level
# fact: ST4 animation None -- the probe sets OPT_ANIMATION 2 for the cast; no roll decides that nothing lights
# fact: ST5 out of sight -- the probe makes the player's eight neighbors opaque (as case C) and places the skull at (PX+10, PY); no roll decides the line of sight
# fact: ST7 the gameplay random stream -- each cast runs in its own process (INCURSION_ST7_ANIM), from init_genrand(7770003) just before the cast, so no state carries between casts; the check compares the stream position (seed, draws taken) when the script's light ends and the next draw, whatever the values are
# fact: ST7 process-to-process determinism -- two runs at the same animation must give equal output; the check runs animation Normal twice and is INCONCLUSIVE if they differ
# fact: DR1 cast square, radius and which squares are seen -- the probe throws Dance of Ruin as a globe at (20, PY) with a 3-square wall at (13, 18..20), fixed offsets from the player's fixed square; the radius is the data's lval; the expected squares are those within it that the probe's own LineOfSight call says the player sees; no roll decides them
# fact: DR1 a square's landing and first-light clocks -- the effect's own clock, 40 ms a step, the hook's clockMs; never the wall clock
# fact: DR2 the drops' start times -- cosmetic_random() picks each from 31 slots; the check reads only that at least one landing differs in clock from the first, and all of about 400 landings sharing one clock has chance below 1e-300
# fact: DR3 the light color -- the cval (COL_DARKRED) through LightEffectColour, read by the probe from the data; the check reads each square's own light (LightEffectGlyphAt) against that row, within 12 per channel in hue, at every step's end and at the square's first sample; the effect's loaded damage type is fire (bead inc-5d7l6) and is not controlled: the check passes only if the cval wins over it
# fact: DR4 the glyphs -- the data's rain glyphs, | (124) falling and * (42) landing; no roll decides them; the above-square rule uses the probe's own LineOfSight, bounds and solid test
# fact: DR5 animation None -- the probe sets OPT_ANIMATION 2 for the cast; no roll decides that nothing lights
# fact: DR6 squares the player cannot see -- the wall's shadow in the globe; the probe counts them from its own LineOfSight call and is INCONCLUSIVE below 3; a second cast with the player's eight neighbors opaque sees none of the globe
# fact: DR7 the struck kobold -- a kobold at (20, 15), 5000 hit points, inside the globe on a seen square; the struck flash comes before any hit and no roll decides it; the hook reads its color at TF_LIT
# fact: DR8 flashes left -- LightFlashCount after each cast; no roll decides it
# fact: DR9 the gameplay random stream -- each cast runs in its own process (INCURSION_DR9_ANIM), from init_genrand(7770004) just before the cast; the check compares the stream position (seed, draws taken) when the rain's light ends and the next draw, whatever the values are
# fact: DR9 process-to-process determinism -- two runs at the same animation must give equal output; the check runs animation Normal twice and is INCONCLUSIVE if they differ
# fact: NS1 the demon, the kobold and the squares -- the probe places a nalfeshnee at (PX+9, PY) and a kobold at (PX+12, PY), fixed offsets from the player's fixed square; the expected 3x3 squares are those the probe's own LineOfSight call says the player sees; no roll decides them
# fact: NS1 the demon's visibility -- the probe removes the INVIS status the nalfeshnee's spell list gives it at creation, so the player perceives it and its own glyph shows; no roll decides it
# fact: NS1 the cast -- EV_EFFECT on the gather effect with the demon as actor and victim, which ignores EV_ISTARGET (as Dance of Ruin's does); no attack roll or saving throw decides that the gather stands
# fact: NS1 each pick's glyph and color -- cosmetic_random() picks them; the check reads only invariants every pick keeps (a symbol that is not a letter, digit or @; a palette color that is not black, shadow, grey or white) and that the terminal shows the pick the engine reports on each of the 8 squares
# fact: NS2 the pattern's clock -- the value the probe passes to StandingPatternFrame (1000, 1050, 1100 ms), never the wall clock; a pick repeats on a square with chance 1/64, so none of 9 squares changing has chance below 1e-16
# fact: NS3 one game tick -- the demon's own UpdateStati(), once; the gather's duration is 2 (EV_CALC_EFFECT), so its stati still holds; no roll decides it
# fact: NS4 the move -- the probe moves the demon one square north with Thing::Move; no roll decides where the 3x3 stands
# fact: NS5 the blast's first lit frame -- the first EL_LIT call of the effect-light hook after the gather's stati elapses; the pattern count and the flash count are read there; no roll decides them
# fact: NS6 the stop -- the probe removes the gather's stati (RemoveEffStati) in one cast and the demon (Remove) in another, then passes the next pattern clock value; no roll decides it
# fact: NS7 out of sight -- the probe makes the player's eight neighbors opaque (as case C); no roll decides the line of sight
# fact: NS8 animation None -- the probe sets OPT_ANIMATION 2 for the cast; no roll decides that nothing draws or lights
# fact: NS9 each square's age -- the flash's own clock, set by the probe's hook to 0, 300, 600 and 850 ms and reset by the effect's next wait; never the wall clock
# fact: NS9 each square's hue -- a hash of its coordinates and the flash's sequence number (src/Light.cpp, the rainbow ramp), no random draw; the check reads that at least one of about 300 squares differs from the first by over 90 in normalized color, which a hash of 300 squares misses with chance below 1e-100
# fact: NS10 the struck kobold -- a kobold at (PX+12, PY), 5000 hit points, inside the blast's radius of 8 from the demon on a seen square; the struck flash comes before any hit and no save or hit roll decides it
# fact: NS11 the end state -- LightFlashCount, StandingPatternCount and the overlay's Active flag after the blast; no roll decides them
# fact: NS12 the gameplay random stream -- each cast runs in its own process (INCURSION_NS12_ANIM), from init_genrand(7770005) just before the demon's setup and cast; the check compares the stream position (seed, draws taken), the next draw, and the kobold's hit points after the gather and blast between an animation-Normal run and an animation-None run, whatever the values are
# fact: NS12 the player's first sight of the demon and the kobold -- the probe marks both MS_SCRUTINIZED, so the player's first-sight roll (Player::ScrutinizeMon, 2 gameplay draws, measured 160 against 162 draws with it unmarked) does not fire when the pattern's light shows the demon in the dark room and animation None shows nothing; light that reveals a creature starts that roll, which is seeing and not drawing
# fact: NS12 process-to-process determinism -- two runs at the same animation must give equal output; the check runs animation Normal twice and is INCONCLUSIVE if they differ
# fact: FF1 which color a cast picks -- random(5) in the spell's script, seeded; the probe reads the color word from the hit message ("limned in flickering <word> light") and passes for any word, over 12 casts; the oracle table (silver, violet, amber, azure, crimson) is the probe's own
# fact: FF1 that the player sees the kobold, so the hit message prints -- the probe gives the player infravision 12 for the cast only (then zeroes it), and the kobold is warm-blooded; no roll decides it
# fact: FF1 two kobolds' squares -- fixed offsets (KX, PY-1) and (KX, PY+1) from the player's fixed square, KX = PX+8, inside the globe's radius 4; the probe aims at (KX, PY)
# fact: AU1/AU2 the room and the fields -- the probe builds a dark room (AU1) or one whose block squares are all legacy .Lit (AU2), and two purple FI_MODIFIER fields of radius 4 at (PX+10, PY) and (PX+5, PY), fixed offsets from the player's fixed square; no roll decides them
# fact: AU1/AU2 the compared light -- LightLevelAt and LightAt over every square, before and after the fields, with the player's light, infravision and shadow ranges zeroed; no flicker enters (an aura casts no footprint), no random draw
# fact: J1/J2/J6 aura light -- the probe's fields are FI_MODIFIER or FI_BLOCKER at (PX+10, PY); the expected light is none, whatever the field's color
# fact: FF2 flicker -- LightTick at the clock values the probe passes (0..3000 ms in steps of 100), never the wall clock; each source's noise is a hash of its square, so no random draw
# fact: FF3 the move -- the probe moves the kobold three squares south with Thing::Move; no roll decides it
# fact: FF4 the neighbors -- the eight squares around the kobold in a dark room; the probe zeroes the ambient light and the player's light ranges
# fact: FF5 the kill -- ThrowDmg of 10000 blunt damage on a kobold with 5000 hit points; no roll decides that it dies
# fact: FF6a Glitterdust's save -- the blindness part allows a Fortitude save, and a kobold that makes it skips the glow part too; the probe casts on fresh kobolds until the glow stands (at most 40; a kobold makes the save with chance at most 0.6, so 40 all made has chance below 1e-8)
# fact: FF6b Mooncloak's save and fatigue -- the probe refills the player's fatigue before each cast and casts until the glow stands (at most 40, as FF6a)
# fact: FF6c whether the power absorbs a blast -- the script rolls 1d20 + Intelligence modifier against 10; the probe repeats the fire damage until the glow stands (at most 60; one try fails with chance at most 0.5, so 60 all failing has chance below 1e-18)
# fact: FF6d the second blast -- the same retry with electricity; the check reads only that the duration grew and the color stayed
# fact: FF6e fey trapping -- the probe grants the status with the same call src/Fight.cpp makes (ILLUMINATED, SS_ATTK, no value, no effect); the real path needs a fey-trapping weapon's hit roll, which the check does not drive
# fact: FF7 that the status value is saved -- the check greps inc/SaveLegacyTags.h for the StatiCollection.Status "val" row and src/SaveV1.cpp for its round-trip comparison of Val; no game state
# fact: FF8 the fallback -- the probe grants the status with value 0, once with Faerie Fire's effect (cval SKYBLUE) and once with none; no roll decides it
# fact: FF9 the gameplay random stream -- init_genrand(7770006) just before each of two casts of Faerie Fire on two kobolds (animation Normal, then animation None, in one process), then the stream position and the next draw are compared; both kobolds are marked MS_SCRUTINIZED so the player's first-sight roll (as NS12) does not fire
# fact: FF11 the glyph color's flicker -- LightTick at the clock values the probe passes (0..3000 ms), never the wall clock; the color word comes from the hit message, so the check passes for any word
# fact: FF12 the background tint -- computed from the glow color and the current flicker by LightLimnAt; the same message-read word as FF11, no roll decides it
# fact: FF13 neighbor and removal -- the squares beside the kobold and the status removal by the probe; no roll decides them
# fact: FF10 the flash count -- LightFlashCount after the probe; no roll decides it
# Cases AU1-AU2 add: two overlapping aura fields change no square's light level or color, in a dark room and in a lit one; J1, J2 and J6 expect no light from an aura (they expected its area lit before Phase 5).
# Cases FF1-FF10 add: every ILLUMINATED creature (Faerie Fire in the color its message names, Glitterdust amber, Mooncloak silver, Energy Containment the absorbed energy's color, a fey-trapping weapon silver) lights its own square only, gently flickering, moving with it and ending with the status; a value of 0 takes the effect's cval, else silver; and no gameplay roll moves.
# Cases NS1-NS12 add (NS12 in separate processes): Nightmare Smite's gather draws a standing rainbow pattern of changing glyphs and light on the demon and the 8 squares around it, for as long as the gather stands, across turns, following the demon, only on squares the player sees; the pattern stops before the blast, when the gather ends early, when the demon goes, and never starts under animation None; the blast lights on the rainbow ramp, each square in its own hue and cooling, and flashes the creatures it strikes; and no gameplay roll moves.
# Cases DR1-DR9 add: Dance of Ruin's dark-red drops fall onto each square the player sees, each square lights on the dark ramp as its drop lands, the struck flash runs last, the cval beats the fire damage type, and no gameplay roll moves.
# Cases ST1-ST14 add: Skull Trap's skull glows crimson after its scream, rising from dim to full over 1000 ms and holding at its peak; its explosion then plays a fire wave and a necromantic wave of glyphs, rings moving out 10 ms apiece, each struck creature flashing as each wave reaches it; a plain globe still runs its struck flash; no old highlight, no light when unseen or under animation None, and no gameplay roll moved.
# Cases BH1-BH8 add (BH7 in separate processes): Burning Hands lights each square it draws on the fire ramp through the hold and the cooling, flashes every creature it hit, and moves no gameplay roll.
# Cases CP1-CP6 add: Hypnotic Pattern, Colour Spray and Chromatic Orb draw random symbols in random colors that re-pick each 100 ms of the effect clock, the light follows each glyph's color, and no gameplay roll moves.
# Cases LM1-LM5 add: a lit lightning stroke is drawn as a jagged path that keeps its rules and never changes the squares the spell walks.
# Case FW1 adds: the fireworks globe (Pyrotechnics;flash) plays dot, star, flower, gone, ring by ring, pointing away from the center.
# Cases T1-T3 add: the target flash (Fireball with two kobolds, a landed and a missed Chill Touch, Call Lightning).
# Cases R1-R3 add: a square's light cools by its own age (fire, then no white stage for dark energy), and a Fireball
# under OPT_ANIMATION None ends with no flash left.
# Cases B (Fireball) and B2 (a globe, Sleep) add: the effect lights while it shows, is gone at its
# end hook and after the cast returns, and a flash on and a flash off print the same set of messages.
# Exit 0 on PASS, 1 on FAIL, 2 on INCONCLUSIVE or no EFFECT_LIGHT line.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=1
KEYS=tools/keys/effect-light.keys
OPTIONS=tools/fixtures/options-2026-08-22.dat
LOAD=xsummon-priest-seed5-opt0822

[ -x ./incursion-headless ] || {
    echo "FAIL: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 2
}

RUN_DIR="$ROOT/logs/runs/$(date +%Y%m%d-%H%M%S)-$$-effect-light"
INCURSION_EFFECT_LIGHT_PROBE=1 INCURSION_LIGHT_PROBE=1 INCURSION_RUN_DIR="$RUN_DIR" \
    INCURSION_OPTIONS="$OPTIONS" INCURSION_LOAD="$LOAD" \
    tools/headless.sh "$KEYS" "$SEED" > /dev/null 2>&1

OFF_DIR="$ROOT/logs/runs/$(date +%Y%m%d-%H%M%S)-$$-effect-light-off"
INCURSION_EFFECT_LIGHT_OFF=1 INCURSION_EFFECT_LIGHT_PROBE=1 INCURSION_LIGHT_PROBE=1 \
    INCURSION_RUN_DIR="$OFF_DIR" \
    INCURSION_OPTIONS="$OPTIONS" INCURSION_LOAD="$LOAD" \
    tools/headless.sh "$KEYS" "$SEED" > /dev/null 2>&1

bh7() {   # one fresh process; prints its four draws
    local d="$ROOT/logs/runs/$(date +%Y%m%d-%H%M%S)-$$-effect-light-bh7-$1"
    INCURSION_BH7_ANIM="$1" INCURSION_EFFECT_LIGHT_PROBE=1 INCURSION_LIGHT_PROBE=1 INCURSION_RUN_DIR="$d" \
        INCURSION_OPTIONS="$OPTIONS" INCURSION_LOAD="$LOAD" \
        tools/headless.sh "$KEYS" "$SEED" > /dev/null 2>&1
    grep -a 'EFFECT_LIGHT: BH7DRAW' "$d/logs/errors.log" 2>/dev/null | sed 's/.*BH7DRAW //'
}
st7() {   # one fresh process; prints its end position and next draw
    local d="$ROOT/logs/runs/$(date +%Y%m%d-%H%M%S)-$$-effect-light-st7-$1-$2"
    INCURSION_ST7_ANIM="$1" INCURSION_EFFECT_LIGHT_PROBE=1 INCURSION_LIGHT_PROBE=1 INCURSION_RUN_DIR="$d" \
        INCURSION_OPTIONS="$OPTIONS" INCURSION_LOAD="$LOAD" \
        tools/headless.sh "$KEYS" "$SEED" > /dev/null 2>&1
    grep -a 'EFFECT_LIGHT: ST7DRAW' "$d/logs/errors.log" 2>/dev/null | sed 's/.*ST7DRAW //'
}
dr9() {   # one fresh process; prints its end position and next draw
    local d="$ROOT/logs/runs/$(date +%Y%m%d-%H%M%S)-$$-effect-light-dr9-$1-$2"
    INCURSION_DR9_ANIM="$1" INCURSION_EFFECT_LIGHT_PROBE=1 INCURSION_LIGHT_PROBE=1 INCURSION_RUN_DIR="$d" \
        INCURSION_OPTIONS="$OPTIONS" INCURSION_LOAD="$LOAD" \
        tools/headless.sh "$KEYS" "$SEED" > /dev/null 2>&1
    grep -a 'EFFECT_LIGHT: DR9DRAW' "$d/logs/errors.log" 2>/dev/null | sed 's/.*DR9DRAW //'
}
ns12() {   # one fresh process; prints its end position, next draw and the kobold's hit points
    local d="$ROOT/logs/runs/$(date +%Y%m%d-%H%M%S)-$$-effect-light-ns12-$1-$2"
    INCURSION_NS12_ANIM="$1" INCURSION_EFFECT_LIGHT_PROBE=1 INCURSION_LIGHT_PROBE=1 INCURSION_RUN_DIR="$d" \
        INCURSION_OPTIONS="$OPTIONS" INCURSION_LOAD="$LOAD" \
        tools/headless.sh "$KEYS" "$SEED" > /dev/null 2>&1
    grep -a 'EFFECT_LIGHT: NS12DRAW' "$d/logs/errors.log" 2>/dev/null | sed 's/.*NS12DRAW //'
}
BH7_N1="$(bh7 0)"; BH7_N2="$(bh7 0)"; BH7_NONE="$(bh7 2)"
ST7_N1="$(st7 0 a)"; ST7_N2="$(st7 0 b)"; ST7_NONE="$(st7 2 c)"
DR9_N1="$(dr9 0 a)"; DR9_N2="$(dr9 0 b)"; DR9_NONE="$(dr9 2 c)"
NS12_N1="$(ns12 0 a)"; NS12_N2="$(ns12 0 b)"; NS12_NONE="$(ns12 2 c)"

log="$RUN_DIR/logs/errors.log"
if [ ! -s "$log" ]; then
    echo "INCONCLUSIVE: no $log. The probe never wrote anything -- is"
    echo "      EffectLightProbe still called from Game::Play()?"
    exit 2
fi

lines="$(grep -a 'EFFECT_LIGHT:' "$log")"
if [ -z "$lines" ]; then
    echo "INCONCLUSIVE: $log has no EFFECT_LIGHT lines."
    exit 2
fi

echo "$lines"
echo "Specimen: $log"

# The light dump must name the flash: F <id> <cells> <reach> <style> <level>.
dump="$RUN_DIR/logs/light.log"
if ! grep -Eq '^F [0-9]+ 1 2 1 ' "$dump" 2>/dev/null; then
    echo "FAIL: $dump has no F line for the one-square fire flash."
    exit 1
fi

last="$(tail -n 1 <<< "$lines")"
case "$last" in
    *"EFFECT_LIGHT: PASS")
        # Review Focus 2: the set of messages a cast prints must not depend on the flash.
        msg_on="$(grep -a 'EFFECT_LIGHT: MSG ' "$log" | sed 's/^[0-9-]* [0-9:]* *//' | sort)"
        msg_off="$(grep -a 'EFFECT_LIGHT: MSG ' "$OFF_DIR/logs/errors.log" 2>/dev/null | sed 's/^[0-9-]* [0-9:]* *//' | sort)"
        if [ -z "$msg_on" ] || [ -z "$msg_off" ]; then
            echo "INCONCLUSIVE: a run recorded no cast messages (on: $(grep -c . <<< "$msg_on"), off: $(grep -c . <<< "$msg_off"))."
            exit 2
        fi
        if [ "$msg_on" != "$msg_off" ]; then
            echo "FAIL: the Fireball's messages differ with the flash on and off."
            diff <(echo "$msg_on") <(echo "$msg_off") | head -10
            exit 1
        fi
        if [ -z "$BH7_N1" ] || [ "$BH7_N1" != "$BH7_N2" ]; then
            echo "INCONCLUSIVE: BH7 two animation-Normal runs gave different draws ('$BH7_N1' / '$BH7_N2')."
            exit 2
        fi
        if [ "$BH7_N1" != "$BH7_NONE" ]; then
            echo "EFFECT_LIGHT: BH7 FAIL stream position when the script's light ends, struck kobold: animation Normal $BH7_N1, animation None $BH7_NONE (need equal)"
            exit 1
        fi
        if [ -z "$ST7_N1" ] || [ "$ST7_N1" != "$ST7_N2" ]; then
            echo "INCONCLUSIVE: ST7 two animation-Normal runs gave different draws ('$ST7_N1' / '$ST7_N2')."
            exit 2
        fi
        if [ "$ST7_N1" != "$ST7_NONE" ]; then
            echo "EFFECT_LIGHT: ST7 FAIL Skull Trap stream position at the end of the script's light and next draw: animation Normal $ST7_N1, animation None $ST7_NONE (need equal)"
            exit 1
        fi
        if [ -z "$DR9_N1" ] || [ "$DR9_N1" != "$DR9_N2" ]; then
            echo "INCONCLUSIVE: DR9 two animation-Normal runs gave different draws ('$DR9_N1' / '$DR9_N2')."
            exit 2
        fi
        if [ "$DR9_N1" != "$DR9_NONE" ]; then
            echo "EFFECT_LIGHT: DR9 FAIL Dance of Ruin stream position when the rain's light ends and next draw: animation Normal $DR9_N1, animation None $DR9_NONE (need equal)"
            exit 1
        fi
        if [ -z "$NS12_N1" ] || [ "$NS12_N1" != "$NS12_N2" ]; then
            echo "INCONCLUSIVE: NS12 two animation-Normal runs gave different draws ('$NS12_N1' / '$NS12_N2')."
            exit 2
        fi
        if [ "$NS12_N1" != "$NS12_NONE" ]; then
            echo "EFFECT_LIGHT: NS12 FAIL Nightmare Smite stream position after the blast and next draw: animation Normal $NS12_N1, animation None $NS12_NONE (need equal)"
            exit 1
        fi
        if ! grep -q '"StatiCollection.Status", 2, "val"' inc/SaveLegacyTags.h || ! grep -q 'sa->Val != sb->Val' src/SaveV1.cpp; then
            echo "EFFECT_LIGHT: FF7 FAIL the status value (an ILLUMINATED glow color) is not a saved Status field"
            exit 1
        fi
        echo "EFFECT_LIGHT: FF7 PASS the status value is a saved Status field (inc/SaveLegacyTags.h row val; src/SaveV1.cpp compares Val on a round trip), so the glow color survives a save"
        echo "EFFECT_LIGHT: NS12 PASS Nightmare Smite stream position after the blast and next draw: animation Normal (twice) $NS12_N1, animation None $NS12_NONE"
        echo "EFFECT_LIGHT: DR9 PASS Dance of Ruin stream position when the rain's light ends and next draw: animation Normal (twice) $DR9_N1, animation None $DR9_NONE"
        echo "EFFECT_LIGHT: ST7 PASS Skull Trap stream position at the end of the script's light and next draw: animation Normal (twice) $ST7_N1, animation None $ST7_NONE"
        echo "EFFECT_LIGHT: BH7 PASS stream position when the script's light ends, struck kobold: animation Normal (twice) $BH7_N1, animation None $BH7_NONE"
        echo "messages: $(grep -c . <<< "$msg_on") line(s), identical with the flash on and off"
        echo "PASS: an effect's squares light, show in its color, dim without hiding, and go dark."
        exit 0 ;;
    *"EFFECT_LIGHT: FAIL")
        echo "FAIL: at least one effect-light rule failed."
        exit 1 ;;
    *)
        echo "INCONCLUSIVE: no verdict, or a case could not be established."
        exit 2 ;;
esac
