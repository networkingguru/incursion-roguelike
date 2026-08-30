/* LIGHT.H -- See the Incursion LICENSE file for copyright information.

   The runtime light map: coloured light from every source on the displayed
   level, rebuilt once per turn and re-evaluated with noise once per frame.
   It feeds the SDL backend's true-colour drawing and nothing else -- no game
   rule reads it (docs/superpowers/plans/2026-08-30-ascii-lighting-brief.md).

   It lives in file-scope storage in src/Light.cpp, not in Map, because Map,
   Term and LocationInfo are in SaveLayoutDigest() (src/AbiCheck.cpp) and a
   new member there orphans every save. */

#ifndef LIGHT_H
#define LIGHT_H

struct LightRGB { uint8 r, g, b; };

class Map;
class Player;

/* Per turn. Scans the level for sources, casts each one's footprint through
   line of sight, and sums the steady light. Cheap enough to call from every
   ShowMap. Pass the same map twice and it rebuilds anyway. */
void LightRebuild(Map *m, Player *p);

/* Per frame. Advances each flickering source's noise to wall-clock time
   `ms` and recomputes the frame buffer LightAt reads. */
void LightTick(uint32 ms);

/* The light on one map cell, source light plus ambient, after the last
   LightTick (or the steady value if no tick has run since the rebuild).
   Returns false, and leaves `out` alone, when the cell is off the map or
   receives no light at all. */
bool LightAt(int16 x, int16 y, LightRGB &out);

/* The backend's 16-colour palette, so a source whose colour comes from its
   glyph lights in the same colour the glyph is drawn in. Defaults to the
   classic libtcod palette until a backend calls this. */
void LightSetPalette(const LightRGB *sixteen);

/* One 16-colour index as the backend's RGB, and that colour under light L:
   each channel is base * (floor + (1 - floor) * L / 255), so floor is the
   brightness of a cell no light reaches (0..1). */
LightRGB LightPaletteRGB(int idx);
LightRGB LightShade(int idx, LightRGB L, float floor);

/* How the SDL build should draw, from OPT_ANIMATION: None = the classic
   16-colour path, Fast = steady coloured light, Normal/Player = shimmer. */
enum { LIGHT_LEGACY = 0, LIGHT_STEADY = 1, LIGHT_SHIMMER = 2 };
#define LIGHT_FLOOR_SHADE 0.35f
#define LIGHT_FLOOR_SOLID 0.75f
int LightMode(Player *p);

#endif
