/* LIGHT.H -- See the Incursion LICENSE file for copyright information.

   The runtime light map: coloured light from every source on the displayed
   level, rebuilt once per turn and re-evaluated with noise once per frame.
   It feeds the SDL backend's true-colour drawing and the engine's source-lit
   visibility test (docs/superpowers/plans/2026-08-30-ascii-lighting-brief.md).

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

/* The light map's answer to the engine's Lit flag; reads the steady footprint
   so flicker cannot make vision blink. */
bool LightLitAt(int16 x, int16 y);

/* The backend's 16-colour palette, so a source whose colour comes from its
   glyph lights in the same colour the glyph is drawn in. Defaults to the
   classic libtcod palette until a backend calls this. */
void LightSetPalette(const LightRGB *sixteen);

/* One 16-colour index as the backend's RGB, and that colour shaded and lifted
   by light L, so unlit is the brightness of a cell no light reaches (0..1). */
LightRGB LightPaletteRGB(int idx);
LightRGB LightShade(int idx, LightRGB L, float unlit);
/* A remembered cell is drawn from memory rather than seen, so it keeps its
   shape and loses most of its colour. */
LightRGB LightMemory(int idx, float unlit);
/* Heat sight discards a surface's hue and shows only how bright it is, so
   the picture is monochrome red and cannot be mistaken for torchlight. */
LightRGB LightInfra(int idx, bool warm);
/* Heat sight over a lit colour. 'infra' is the spatial strength,
   0..1, and any light at LIGHT_INFRA_YIELD or above wins outright. */
LightRGB LightInfraMix(LightRGB lit, int idx, bool warm,
                       LightRGB L, float infra);
/* The glow a lit cell paints across its whole square, behind the glyph. */
LightRGB LightGlow(int idx, LightRGB L);

/* How the SDL build should draw, from OPT_ANIMATION: None = the classic
   16-colour path, Fast = steady coloured light, Normal/Player = shimmer. */
enum { LIGHT_LEGACY = 0, LIGHT_STEADY = 1, LIGHT_SHIMMER = 2 };
#define LIGHT_DOMINANCE   1.5f  /* how sharply the stronger colour wins the cell */
#define LIGHT_SOFTEN      2.0f  /* the inverse-square softening distance, in cells */
#define LIGHT_UNLIT_FLOOR 0.15f /* an unlit floor, as a fraction of its own colour */
#define LIGHT_UNLIT_SOLID 0.35f /* an unlit wall: higher, so walls keep their shape at the edge of the light */
#define LIGHT_MEMORY_GREY 0.95f /* how far a remembered surface is drained toward grey */
#define LIGHT_MEMORY_FLAT 0.50f /* how far a remembered surface's brightness is pulled toward mid, so memory reads flat */
#define LIGHT_MEMORY_LIFT 0.22f /* how far a remembered surface is lifted above unlit, so its greyness is visible at all */
#define LIGHT_WASH        0.35f /* how far light beyond a surface's own ceiling blows it toward white */
#define LIGHT_BG_GAIN     0.18f /* the whole-square glow painted into a cell's background */
#define LIGHT_SEE_MIN     48    /* least source light, 0..255, at which the engine counts a cell as lit */
#define LIGHT_INFRA_R     200   /* the heat-sight ramp: a dim red, hue only */
#define LIGHT_INFRA_G      60
#define LIGHT_INFRA_B      60
#define LIGHT_INFRA_FLOOR 0.35f /* the darkest a surface reads under heat sight */
#define LIGHT_INFRA_COLD  0.65f /* cold terrain, against a warm body's full ramp */
#define LIGHT_INFRA_YIELD 0.35f /* the light at which heat sight has wholly given way */
#define LIGHT_INFRA_FADE  2     /* cells over which the edge of heat sight tapers out */
int LightMode(Player *p);

#endif
