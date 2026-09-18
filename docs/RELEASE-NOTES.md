# Release notes

What each release of this fork changed, as the README described it at the time.

The newest work is first. **Release 4 is the first release where every
download is the same program.** macOS, Windows, Linux and the Steam Deck are all
built from one commit, and no platform is held back while another catches up.

## New in release 4 — in every download

**The map is lit in colour.** Incursion draws its map in the sixteen colours the
character set gives it, and a lit square used to be no more than a brighter
version of its own colour. There is now a light map under the display. Every
torch, lantern, magma pool, glowing creature and light spell casts a coloured
footprint that falls away with distance, and each source flickers on noise of its
own — a torch gutters, a lantern is nearly steady, magma breathes slowly. A lit
cell is a contest between the surface's colour and the light's, so a torch on a
dark floor takes the cell, while the same torch in a vivid purple room gives
purple with a yellow cast. Light loses strength and colour crossing ice or fog,
and it glints off a shiny wall in the colour that struck it. The SDL build
re-shades while you stand still, so the flicker reads as movement. The terminal
builds keep their sixteen colours and are unchanged.

![Coloured light in an ice cavern](media/incursion-lighting-web.png)

*Three archons light this cavern, each at its own radius and colour, and the ice
walls take the light as pale blue. Beyond the last source the floor is black, and
the corridors the character has already walked sit grey and unlit, remembered
rather than seen.*

**Light now decides what you can see, and what can see you.** Twelve creatures and
the flame template light their surroundings by their own nature rather than only
by carrying a torch: a mote glows one square, a magma flow four. A creature can no
longer hide while carrying a lit torch, lantern or glowing weapon, and the Hide
skill refuses with *"You can't hide while carrying a light."* Hiding, light
aversion and what the map actually paints all read the same brightness rule now,
rather than each answering the question its own way.

**The game plays on a gamepad.** The SDL build reads a controller itself. The left
stick moves in eight directions, with a deadzone and a one-flick-one-step feel;
the right stick pans the look cursor; the d-pad carries Kick, Pray, Legend and
Run; and holding a clicked stick rests or exchanges weapons. The `?` screen names
the pad control beside each key whenever a pad is in front of the game. Menus that
needed Tab now page with Left and Right, choice screens answer to the arrow keys
and Enter, and the overview map, the inventory and the Options screen all take the
pad. This is what makes the Steam Deck bundle playable with no keyboard attached.

**A title screen.** The SDL build opens on the launch logo, letterboxed over the
title band so that it keeps its shape at every window size and font. The terminal
and headless builds fall back to the same wordmark redrawn as hard CP437 glyphs in
sixteen colours, and both keep the *Halls of the Goblin King* subtitle and the
credits below it.

**It runs on Windows.** Incursion began as a Windows game, and this fork could
not build it there: `src/ErrorLog.cpp`, added by this port, carried four
unguarded POSIX includes, and nothing had compiled on Windows since the day that
file landed. There is now an `Incursion.exe`, cross-built from the Mac with
mingw-w64, and it has been played through character creation and down into the
dungeon in a Windows 11 virtual machine. Most of what stood in the way was found
by the compiler rather than by any reading of the code, exactly as the Linux port
went: a shim header in `compat/` that shadowed mingw's own `<malloc.h>` and took
`alloca` away with it, at the same call site where the same mistake had already
been made on Linux; a vendored library that needs `-std=gnu17`, because GCC 16
made `bool` a keyword and that library still typedefs it. None of it was visible
from macOS.

**The one the compiler could not find.** This is the first binary this project
has ever built with GCC, and it died moments after character creation on an
invalid object handle. Three binaries were measured in the VM from one source,
differing only in flags: `-O2` crashes, `-O0` is clean, and `-O2
-flifetime-dse=1` is clean. `Object::operator new` zeroes every allocation, and
constructors across the object hierarchy lean on that fill instead of setting
their own members — the same pattern as the `Item` constructor below. C++ says an
object's lifetime has not begun until its constructor runs, so a compiler is
entitled to delete that memset as a dead store, and GCC at its default setting
does. The flag stops it. **It masks the defect rather than removing it:** clang
holds the same licence and merely does not take it, so the macOS and Linux builds
are latent rather than safe. The constructor audit that would actually fix this
is filed and open.

**It runs on Linux and on the Steam Deck, and you can download it.** Six places in
the port assumed Apple's compiler or Apple's C library: a hardcoded `clang`, a
shim header that shadowed glibc's own, three missing standard includes, a
clang-only debug trap, and one double `fclose` the parent project's preprocessor
has always carried. None of the six was visible from macOS, and all six surfaced
by building inside a Debian 11 (bullseye) container — glibc 2.31 on x86-64, chosen
as an old-glibc floor so the binary's versioned symbols resolve on newer
distributions too, and the same floor the Steam Runtime *sniper* uses. Both
backends now compile there under either clang or GCC, and a seeded session plays
through with no errors. There are two tarballs on the Releases page, one for the
Deck and one for any x86-64 Linux; see [Get it](../README.md#get-it). The nightly gate
cross-builds for Linux, so a Linux break stops a merge.

**A quieter palette, and you choose it.** The sixteen colours the game draws in
are vivid, and a vivid surface fights the new light rather than takes it. There
is now a third palette beside the classic and softer ones, picked on the Options
screen and applied without a restart. Its saturation is a third lower while every
colour keeps the brightness of its classic counterpart, so a close torch supplies
62% of a lit cell's hue where the classic table gives it 46%. Darkening it as
well was tried and reverted: rendered through the real shading function, all
sixteen colours collapsed toward the same tan under a close torch, lighting a
green slime and a red imp alike.

**The Combat and Use menus show only what you can actually do.** The Use menu
(`U`) has always filtered itself against the character. The Combat Options menu
(`C`) gated 3 of its 21 rows and the YUse menu (`Y`) gated none of its 63, so
every character was offered every verb whether or not the game could perform it —
Called Shot's own help text read *"Not implemented yet"* and it was still on the
menu. Both menus now hide a row when the verb has no implementation, or when the
character does not meet its prerequisite. Hidden means absent, not greyed.
Nothing is deleted: the 27 unbuilt verbs are Julian Mensch's recorded intent, and
each returns to the menu the day somebody builds it.

**Two archons stop putting each other's lights out.** An archon standing inside a
neighbouring archon's magic circle lost its own light and its own aura for good,
the moment the two drifted apart. Every archon's circle carries the same effect
id, so the archon standing inside held two rows under that one id, and leaving
the neighbour's circle deleted both — the second deletion then reaped the
creature's own light. The same duplication also paid an overlapping circle's
bonus, and its penalty, once per circle. It takes two archons in one place to
show, which is why every single-archon check passed.

**A swallowed creature feels what its swallower walks through.** A creature that
has been swallowed or engulfed rides at its carrier's square and cannot move
itself, and the code that announces crossing a field boundary told only the mover
and the mover's mount. The passenger therefore never gained a status from a field
its carrier walked into, and never lost one either. It now gets the same events
its carrier gets.

**Every Item member is set before it is read.** The item constructor worked out a
new item's hit points from two of its fields — its enchantment id and its plus —
before it assigned either one, and it never assigned five more members at all. It
leaned on the zero-fill that object allocation happens to leave behind. clang
keeps that fill, so the macOS build was never wrong. A GCC build at `-O2` does not
keep it, and there a garbage plus tripped an assertion and a wild parent handle
crashed character creation before the first map ever drew. The constructor now
sets each member before anything reads it, which is the same zero clang already
produced, so the macOS build is unchanged.

**Magic items now do what their own descriptions promise.** Item after item did
less than the text the game already shows for it. The Bloodspear named a bane
creature and wielder bonuses its script never granted; the Sunblade promised cold
resistance, a sixty-foot burst of light and double damage against Negative-Plane
creatures it never delivered; the Dwarven Thrower called itself a throwing hammer
while its base weapon could not be thrown at all; the Holy Avenger dispelled magic
at a fixed level rather than its paladin wielder's; and a god's holy symbol would
not stay out of the autopickup pile. More than twenty items across the Bloodspears,
Sunblades, Staffs, Cloaks, Bracers, Wands, Rods and scrolls were brought into line
with the one standard the game already sets for each — the description it displays.

**Two deliberate rule changes.** These two are design choices rather than repairs.
Every weapon a Paladin wields now strikes as a holy weapon, an extra 2d6 against
evil and undead, even a plain unenchanted blade; it is a 1st-level class feature,
always on, and it is written into the Paladin's own description and level table.
Monkey Grip now one-hands a bastard sword without its exotic proficiency, which
frees the off hand for a shield, swung at the two-handed Strength bonus and -2 to
hit.

**And a run of smaller fixes.** Walls stopped leaking light after a door in them
was removed. Illusory damage no longer leaves you permanently above your maximum
hit points once it wears off.
Permanent glows and magic auras stopped winking out on their own: an archon's
continual light and its magic circle destroyed themselves the moment they were
cast, and every permanent field on a level used to die the first time the in-game
day rolled over. A target prompt accepts a square with a staircase on it. ESC
leaves character generation instead of doing nothing. Tanglefoot catches the
mount, and dismounting no longer drags a stuck mount along.

## New in release 3 — in every download

**Your save survives new content.** Every reference to game content inside a save
used to be a bare number, and that number was a position in a list. The lists sit
end to end in one numbering space, so adding a single monster, spell or effect
anywhere shifted every entry after it, and an existing save then read one
resource off — an orc came back as a lizardfolk, worshipping the wrong god. A
save now carries a manifest: the length of each of the 21 lists and every entry's
name in position order. The reader converts each reference through that manifest
instead of trusting the number, so content added to the end of a list changes
nothing about a save written before it.

**Old saves convert themselves.** Release 3 is deliberately content-identical to
release 2, so a release-2 save loads correctly and is rewritten in the new format
the first time you save. There is no command to run and nothing to click.
**Upgrade through release 3 rather than skipping it** — it is the release that
performs the conversion, and a save that never passes through it will read one
resource off once later content is added.

**A refused save no longer costs you your file.** The engine now checks whether a
save can be written before it touches anything on disk. A refusal leaves the
existing save exactly as it was, instead of a truncated file and a backup.

**A resource inserted in the middle of a list is refused, not guessed at.** If a
future release ever breaks the append-only rule, the load stops and names what
moved, down to the list, the position and both names, rather than silently
handing you different equipment.

**Saves are a fifth of the size.** Tagged records replaced raw structure dumps: a
2.4 MB character file became 360 KB.

## New in release 2

**The game no longer dies at the bottom of a dungeon.** Moving down from the
deepest level dereferenced a null dungeon, on all four routes that reach it:
falling into a chasm there, the plain `>` climb, levitating down, and a scripted
move. The climb needs no wizard mode and no script. Two more crashes went with
it — a hiding monster that could delete itself mid-spell and leave the caller
holding a dangling map pointer, and a room-building rectangle that inverted
itself in a narrow space and put doors in solid rock.

**The target cursor follows a ring, not an axis.** Arrow keys in target mode
scored candidates on one axis only, so RIGHT meant "the nearest column to my
right" and every row in that column tied. The cursor moved sideways while going
up, skipped near creatures for far ones, and reached places from which most
presses did nothing. Candidates now form a ring around you ordered by bearing,
and an arrow steps one place round it. Which things are candidates is unchanged.

**The shop list scrolls.** The store menu never scrolled at all: its redraw
cleared the scroll offset before every draw, so the selection walked off the page
and stayed there. It also read a hardcoded 32 visible rows instead of asking the
window, and its two manual-scroll keys worked only if you had opened the
inventory screen earlier in the same session.

**`<` and `>` work on the overview map, and find the nearest staircase.** Both
keys used to close the map instead of doing anything. The search behind them also
took the next staircase in reading order rather than the near one; each remembered
staircase is now ranked by what it costs to walk there, so the square the cursor
lands on is the square `R` will really reach. Repeated presses step down the
ranked list and wrap.

**Read a save without loading the game.** Point the binary at a save file with
`-dump` and it prints a full character report to the terminal, then exits. No
window opens and nothing is written. See
[Reading a save](../README.md#reading-a-save-without-loading-the-game) in the README.

**A failed save leaves the game standing.** Saving converted every object's
internal pointers to handles and converted them back afterwards. Any failure
part-way skipped the conversion back, and the game then crashed on the way out.
The report now reaches you and play continues. A file the game refuses to load no
longer takes the process with it either — that fix is a hand-port of Eugene
Archibald's work, and the root cause and evidence are his.

**Natural Weapon Speed, a new option.** Every weapon carries a speed rating;
unarmed and natural attacks carried none, so a monk punched at 100% while the
nunchaku in his pack struck at 160%. The option floors a weapon-capable
creature's brawl speed at the fastest weapon in the data. Dragons and oozes are
untouched and keep their own speeds. This is a balance change rather than a
defect fix, so it is a switch: fresh installs get FLOORED, and an existing
`Options.Dat` reads ORIGINAL until you flip it once.

**Twenty prestige-class descriptions are now true.** Each was a place where a
class promised something its own script never did. The Twilight Huntsman shipped
sixty spells nothing could reach, the Blackguard could not use a shield, and the
Master Archer's ranged sneak attack fired with a sling.

## Already there, since release 1

**Your saves survive an update.** Save compatibility is keyed on a digest of the
actual data layout rather than on a version number, so shipping a new release
does not hide your characters. Previously any version change made every save
vanish from the load menu without a word. Neither release 2 nor release 3 moves
that digest, so characters rolled under release 1 still load — and release 3
converts them to the new format as described above.

**Your species' feats are granted.** Eight racial feats across six races were
never reaching players. A Dragonkin never had Mantis Leap, a dwarf never had
Loadbearer. They do now.

**Bare hands are no longer worse than two weapons.** Two empty hands produced one
attack per swing while two weapons produced two, so a monk was better off holding
nunchaku than using his fists. Fixed to match the 3.5 rules.
