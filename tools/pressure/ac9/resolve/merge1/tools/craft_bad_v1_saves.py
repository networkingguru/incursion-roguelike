# Fields are located by (scope, name) through the file's own name table
# (revision 7; docs/superpowers/specs/2026-11-07-names-in-the-file-design.md
# 5.2), never by a number: an id is a row of THAT file's table. The names
# below are the writer's contract (inc/*.h, src/SaveV1.cpp).
SEG_SCOPE = "Game.MDataSeg.Segment"
THING_STATI = ("Thing", "__Stati")                  # inc/Map.h
MAP_GRID = ("Map", "Grid")                          # inc/Map.h
GRID_GX = ("MapGrid", "gx")                         # src/SaveV1.cpp
GAME_MDATASEG = ("Game", "MDataSeg")                # inc/Res.h
CREATURE_TS = ("Creature", "ts")                    # inc/Creature.h
TS_TCOUNT = ("TargetSystem", "tCount")              # src/Target.cpp
CHAR_NOTIFIEDLEVEL = ("Character", "NotifiedLevel")   # inc/Creature.h
PLAYER_CAUTOBUFF = ("Player", "cAutoBuff")          # inc/Creature.h
CHAR_FAVOURLEV = ("Character", "FavourLev")         # inc/Creature.h
MAX_GODS = 25                     # inc/Defines.h
MAX_FAVOUR_LEV = 10               # the rise loop's cap, src/Prayer.cpp:747
# LAST_STATI is read from inc/Defines.h, so no copy of the number can drift.
_DEFINES = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                        "..", "inc", "Defines.h")
LAST_STATI = int(re.search(r"^#define\s+LAST_STATI\s+(\d+)",
                           open(_DEFINES).read(), re.M).group(1))
@@@ next hunk
        die("expected exactly one \"__Stati\" K_EMBED field (Thing::__Stati) "
            "in the first record")
    if not 1 <= LAST_STATI <= 0xFFFF:
        die("stati_nature_oob: LAST_STATI moved out of the uint16 range "
            "the mutant's nature must exceed")
    # Nature is 16 bits (inc-pu6v.210): "nature" is the low byte and
    # "natureHi" the high byte, so 0xFFFF is out of range for any LAST_STATI.
    status = struct.pack("<HBB", v1.tag("StatiCollection.Status", "nature"),
                         K_U8, 255)
    status += struct.pack("<HBB", v1.tag("StatiCollection.Status", "natureHi"),
                          K_U8, 255) + struct.pack("<H", 0)
    inner = struct.pack("<HBh", v1.tag("StatiCollection", "Last"), K_I16, 1)
    inner += struct.pack("<HBh", v1.tag("StatiCollection", "Allocated"),
                         K_I16, 1)
    inner += struct.pack("<HBI", v1.tag("StatiCollection", "Status#0"),
                         K_EMBED, len(status)) + status
