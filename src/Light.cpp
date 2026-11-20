/* LIGHT.CPP -- See the Incursion LICENSE file for copyright information.

   The runtime light map. See inc/Light.h for the contract and the plan
   (docs/superpowers/plans/2026-08-30-ascii-lighting-brief.md) for the
   design. Nothing here may include a backend header: the posix build
   compiles this file too. */

/* Incursion.h defines min and max as macros, so system headers must precede
   them because libstdc++ declares std::min/std::max through <math.h>. */
#include <math.h>
#include <vector>
#include <stdlib.h>
#include <string.h>

#include "Incursion.h"
#include "Light.h"

#define LIGHT_MAX_RADIUS 12

// family: light-kind internal
enum LightKind { LK_TORCH, LK_LANTERN, LK_GLOW, LK_FIELD, LK_MAGMA,
                 LK_WALLTORCH, LK_REFLECT, LK_FLASH, LK_AURA, LK_KINDS };
// end family: light-kind

/* ponytail: a source's colour comes from this table, or from its own glyph
   when the table row is black. The upgrade path is a "Light Colour:" field in
   the .irh grammar (lang/Grammar.acc, the LIGHT RANGE rule), which needs the
   generated parser rebuilt. Gain is how bright that kind of source is,
   independent of how far it reaches. Amplitude is the flicker depth; freq is
   the base rate in Hz, oct is the number of noise octaves, and bias is the
   shaping exponent. */
struct LightKindRow { LightRGB c; float gain, amp, freq; int16 oct; float bias; };
static const LightKindRow KindTable[LK_KINDS] = {
  /* LK_TORCH     */ { { 255, 147,  41 }, 1.00f, 0.35f, 11.0f, 4, 0.60f },
  /* LK_LANTERN   */ { { 255, 214, 150 }, 1.00f, 0.06f,  1.5f, 2, 0.70f },
  /* LK_GLOW      */ { { 150, 180, 255 }, 0.80f, 0.10f,  0.6f, 2, 0.80f },
  /* LK_FIELD     */ { {   0,   0,   0 }, 1.00f, 0.30f,  1.2f, 3, 4.00f },
  /* LK_MAGMA     */ { { 255,  80,  20 }, 0.70f, 0.35f,  0.6f, 2, 0.80f },
  /* LK_WALLTORCH */ { { 255, 160,  60 }, 1.00f, 0.30f,  9.0f, 4, 0.60f },
  /* LK_REFLECT   */ { {   0,   0,   0 }, 1.00f, 0.00f,  1.0f, 1, 1.00f },
  /* LK_FLASH     */ { {   0,   0,   0 }, 1.00f, 0.00f,  1.0f, 1, 1.00f },
  /* LK_AURA      */ { {   0,   0,   0 }, 0.50f, 0.30f,  1.2f, 3, 4.00f },
};

static LightRGB Palette[MAX_COLOURS] = {
  {   0,   0,   0 }, {   0,   0, 192 }, {   0, 128,   0 }, {   0, 128, 128 },
  { 128,   0,   0 }, { 128,   0, 128 }, { 128, 128,   0 }, { 192, 192, 192 },
  { 128, 128, 128 }, {  64,  64, 255 }, {   0, 255,   0 }, {   0, 255, 255 },
  { 255,   0,   0 }, { 255,   0, 255 }, { 255, 255,   0 }, { 255, 255, 255 },
};

struct LightSource {
  int16 x, y, r;
  uint8 kind;
  LightRGB c;
  uint32 seed;
  float gain, amp, freq, bias; /* brightness, flicker depth, rate, shaping exponent */
  int16 oct;                   /* number of noise octaves */
  float noise;                 /* current multiplier, 1.0 when steady */
  int32 first, count;          /* slice of Foot[] */
  int8 rdx, rdy;               /* reflected source only: the hemisphere it lights,
                                  toward the light that lit it; 0,0 = all round */
  int32 fid;                   /* LK_FLASH: index into Flashes; LK_AURA: into AuraCells */
};

struct FootCell { int32 idx; uint8 w; uint8 fr, fg, fb; int16 ci; }; /* ci: a flash footprint's nearest effect square (index into Flash::cells), else -1 */

static Map    *lmMap = NULL;
static bool    lmLegacy = false;    /* the option turned the lighting off */
static int16   lmW = 0, lmH = 0;
static int32   lmCells = 0;
static LightRGB *Steady = NULL, *Frame = NULL;   /* per cell */
static LightRGB *Ambient = NULL;                 /* per cell: static room light */
static LightRGB *SrcCol = NULL;                  /* summed primary source colour */
static uint8 *SrcLit = NULL;                     /* strongest source light, 0..255 */
static uint8 *FogCol = NULL;                     /* fog palette index plus one, or zero */
static LightSource *Src = NULL; static int32 nSrc = 0, capSrc = 0;
static FootCell    *Foot = NULL; static int32 nFoot = 0, capFoot = 0;
static bool        anyFlicker = false;

/* inc-jw0hw: a flash lives outside Src so it survives LightRebuild. Its level
   and noise are read by ComposeFrame; its footprint is rebuilt with the rest. */
struct FlashCell { int16 x, y; float birth; bool tinted; LightRGB tint; };  /* birth: the flash clock when the square lit, ms; tint: its own base color, when set */
struct Flash {
  bool live;
  LightRGB c;                  /* base colour; the ramp is built from it */
  uint8 style, ramp;
  float gain, level, noise;
  float clock, life;           /* the flash's own clock and a square's light life, ms */
  bool glyphs;                 /* the effect's glyphs are on screen */
  bool rise;                   /* a rise: every square shows its base color, brightest channel 255, at the flash level */
  int16 reach;
  uint32 seed;
  std::vector<FlashCell> cells;
};
static std::vector<Flash> Flashes;
static int32 nFlashLive = 0;
static uint32 flashSeq = 0;

static uint8 LegacyLevel(int16 x, int16 y) {
  const LocationInfo &at = lmMap->At(x, y);
  if (at.Bright) return LIGHT_LEGACY_BRIGHT;
  if (at.Lit) return LIGHT_LEGACY_LIT;
  return 0;
}

void LightSetPalette(const LightRGB *sixteen) {
  memcpy(Palette, sixteen, sizeof(Palette));
}

LightRGB LightPaletteRGB(int idx) {
  return Palette[idx & COLOUR_MASK];
}

/* A colour's value: how bright it is, 0..1. */
static float ColValue(LightRGB c) {
  uint8 m = c.r > c.g ? c.r : c.g;
  if (c.b > m) m = c.b;
  return m / 255.0f;
}

/* A colour's saturation: how far from grey it is, 0..1. */
static float ColSat(LightRGB c) {
  uint8 mx = c.r > c.g ? c.r : c.g;
  uint8 mn = c.r < c.g ? c.r : c.g;
  if (c.b > mx) mx = c.b;
  if (c.b < mn) mn = c.b;
  return mx ? (mx - mn) / (float)mx : 0.0f;
}

static uint8 LightChannel(float v) {
  if (v < 0.0f) v = 0.0f;
  if (v > 255.0f) v = 255.0f;
  return (uint8)(v + 0.5f);
}

LightRGB LightShadeBase(LightRGB base, LightRGB L, float unlit) {
  LightRGB b = base, o;
  float i = ColValue(L);
  if (i <= 0.0f) {
    o.r = LightChannel(b.r * unlit);
    o.g = LightChannel(b.g * unlit);
    o.b = LightChannel(b.b * unlit);
    return o;
  }

  float claimB = ColValue(b) * ColSat(b), claimL = i * ColSat(L);
  float pl = powf(claimL, LIGHT_DOMINANCE);
  float pb = powf(claimB, LIGHT_DOMINANCE);
  float mix = pl / (pl + pb + 1e-6f) * i;
  float maxB = ColValue(b) * 255.0f, maxL = i * 255.0f;
  float lnr = L.r * 255.0f / maxL;
  float lng = L.g * 255.0f / maxL;
  float lnb = L.b * 255.0f / maxL;
  float bnr = maxB > 0.0f ? b.r * 255.0f / maxB : lnr;
  float bng = maxB > 0.0f ? b.g * 255.0f / maxB : lng;
  float bnb = maxB > 0.0f ? b.b * 255.0f / maxB : lnb;
  float hr = bnr + (lnr - bnr) * mix;
  float hg = bng + (lng - bng) * mix;
  float hb = bnb + (lnb - bnb) * mix;
  float cap = ColValue(b);
  float val = cap * (unlit + (1.0f - unlit) * i);
  /* Light the surface cannot carry in its own colour blows it toward white. */
  float excess = i > cap ? (i - cap) / (1.0f - cap + 1e-6f) : 0.0f;
  if (excess > 1.0f) excess = 1.0f;
  float over = excess * LIGHT_WASH;
  val += over * (1.0f - val);
  float white = 255.0f * val;
  o.r = LightChannel(hr * val + (white - hr * val) * over);
  o.g = LightChannel(hg * val + (white - hg * val) * over);
  o.b = LightChannel(hb * val + (white - hb * val) * over);
  return o;
}

LightRGB LightShade(int idx, LightRGB L, float unlit) {
  return LightShadeBase(Palette[idx & COLOUR_MASK], L, unlit);
}

/* The two by-eye trims (OPT_LIGHT_EXPLORED, OPT_LIGHT_BRIGHT) share one
   five-step scale, running darkest to brightest as the menu reads it.
   LIGHT_STEP_NORMAL sits in the middle and is the identity in both tables:
   at that step the game draws exactly what it drew before either option
   existed. A file written before they existed reads 0 here, which is Dimmest
   and not Normal -- MigrateOptions (src/Player.cpp) is what corrects that, so
   neither table may be reordered without reading OPT_SETTINGS_GEN first. */
static int StepIndex(int step) {
  if (step < 0 || step > LIGHT_STEP_MAX)
    return LIGHT_STEP_NORMAL;
  return step;
}

/* What the step does to a remembered surface's brightness, as a multiple of
   the brightness it had before this option existed.

   It scales the FINISHED memory level rather than LIGHT_MEMORY_LIFT, and that
   is the whole point of the option. `unlit` sits under the lift as a floor, so
   scaling the lift can never take a remembered wall below unlit x its own
   colour -- about 77 of 255 for a white wall, which is far too present to read
   as "barely there". Scaling the level itself has no such floor and reaches
   the dark. It also keeps the ratio between a remembered wall and a remembered
   floor fixed at every step, because both are scaled by the same number; the
   old form pulled them together as it brightened and flattened the map just
   when the player asked to see more of it. */
static const float MemoryStep[LIGHT_STEP_MAX + 1] = {
  0.20f,   /* Darkest   -- walls barely there, floors fainter still */
  0.50f,   /* Darker    */
  1.00f,   /* Normal    -- exactly the pre-option brightness */
  1.45f,   /* Brighter  */
  1.95f    /* Brightest */
};

/* The display gain each step asks LightGain for. */
static const float GainStep[LIGHT_STEP_MAX + 1] = {
  0.65f,   /* Dimmest   */
  0.80f,   /* Dimmer    */
  1.00f,   /* Normal    -- returns the colour untouched */
  1.30f,   /* Brighter  */
  1.70f    /* Brightest */
};

LightRGB LightGain(LightRGB c, int step) {
  const float g = GainStep[StepIndex(step)];
  if (g == 1.0f)
    return c;                    /* bit-exact identity, the frozen fixtures */
  const float v = ColValue(c);   /* the colour's own brightness, 0..1 */
  if (v <= 0.0f)
    return c;                    /* black has no brightness to scale */
  /* The two directions are not symmetric, because the screen is not.
     DOWN (g < 1) is a plain scale: there is always room below, so every
     channel takes the same factor and the ratios stay exact.
     UP (g > 1) cannot be a plain scale, because a channel already at 255 has
     no room and a multiply would clip it -- and clipping is precisely what
     shifts a lit surface's hue toward white. g/(1+(g-1)v) instead approaches
     1 as v approaches 1: a dim cell takes nearly the full g, a cell already
     at full brightness is left where it is, and nothing can pass 255.
     Both branches scale all three channels by one factor, so a cell's hue and
     its channel ratios survive either way. */
  const float k = g < 1.0f ? g : g / (1.0f + (g - 1.0f) * v);
  LightRGB o;
  o.r = LightChannel(c.r * k);
  o.g = LightChannel(c.g * k);
  o.b = LightChannel(c.b * k);
  return o;
}

LightRGB LightMemoryBase(LightRGB base, float unlit, int step) {
  LightRGB b = base, o;
  /* Grey by VALUE, not luminance: a saturated blue has almost no
     luminance and greying it that way would crush it to black. */
  float v = ColValue(b);
  /* Washed out is low contrast as well as low colour, so pull the
     surface's own brightness toward the middle before draining it. */
  float vf = v + (0.5f - v) * LIGHT_MEMORY_FLAT;
  float k  = v > 0.0f ? vf / v : 0.0f;      /* same hue, flattened brightness */
  float g  = vf * 255.0f;                   /* the neutral of that brightness */
  float hr = b.r * k, hg = b.g * k, hb = b.b * k;
  /* Memory has its own brightness: at the unlit level the grey is too
     dark to read as grey at all. Floors stay below walls, so a remembered
     room keeps its shape. */
  float mem = (unlit + (1.0f - unlit) * LIGHT_MEMORY_LIFT)
              * MemoryStep[StepIndex(step)];
  if (mem > 1.0f) mem = 1.0f;     /* full brightness is the lit ceiling */
  o.r = LightChannel((hr + (g - hr) * LIGHT_MEMORY_GREY) * mem);
  o.g = LightChannel((hg + (g - hg) * LIGHT_MEMORY_GREY) * mem);
  o.b = LightChannel((hb + (g - hb) * LIGHT_MEMORY_GREY) * mem);
  return o;
}

LightRGB LightMemory(int idx, float unlit, int step) {
  return LightMemoryBase(Palette[idx & COLOUR_MASK], unlit, step);
}

LightRGB LightInfra(int idx) {
  LightRGB b = Palette[idx & COLOUR_MASK], o;
  float v = ColValue(b);
  float s = LIGHT_INFRA_FLOOR + (1.0f - LIGHT_INFRA_FLOOR) * v;
  o.r = LightChannel(LIGHT_INFRA_R * s);
  o.g = LightChannel(LIGHT_INFRA_G * s);
  o.b = LightChannel(LIGHT_INFRA_B * s);
  return o;
}

LightRGB LightInfraMix(LightRGB lit, int idx,
                       LightRGB L, float infra) {
  if (infra <= 0.0f) return lit;
  float i = ColValue(L) / LIGHT_INFRA_YIELD;
  if (i > 1.0f) i = 1.0f;
  float k = infra * (1.0f - i);      /* how much darkvision survives */
  if (k <= 0.0f) return lit;
  LightRGB h = LightInfra(idx), o;
  o.r = LightChannel(lit.r + (h.r - lit.r) * k);
  o.g = LightChannel(lit.g + (h.g - lit.g) * k);
  o.b = LightChannel(lit.b + (h.b - lit.b) * k);
  return o;
}

LightRGB LightGlow(int idx, LightRGB L) {
  LightRGB b = Palette[idx & COLOUR_MASK], o;
  float i = ColValue(L);
  o.r = LightChannel(b.r * LIGHT_UNLIT_FLOOR + LIGHT_BG_GAIN * L.r * i);
  o.g = LightChannel(b.g * LIGHT_UNLIT_FLOOR + LIGHT_BG_GAIN * L.g * i);
  o.b = LightChannel(b.b * LIGHT_UNLIT_FLOOR + LIGHT_BG_GAIN * L.b * i);
  return o;
}

/* Fog scatters the light that reaches it: a lit cloud glows in its own colour
   and an unlit one stays exactly as dark as it was. */
LightRGB LightFogMix(LightRGB c, LightRGB fog, LightRGB L) {
  float i = ColValue(L), k = LIGHT_FOG_GLOW * i;
  LightRGB o;
  o.r = LightChannel(c.r * (1.0f - k) + fog.r * i * k);
  o.g = LightChannel(c.g * (1.0f - k) + fog.g * i * k);
  o.b = LightChannel(c.b * (1.0f - k) + fog.b * i * k);
  return o;
}

int LightMode(Player *p) {
  switch (p ? p->Opt(OPT_ANIMATION) : 0) {
    case 2:  return LIGHT_LEGACY;    /* None */
    case 1:  return LIGHT_STEADY;    /* Fast */
    default: return LIGHT_SHIMMER;   /* Normal, Player */
  }
}

static void EnsureCells(Map *m) {
  if (m->SizeX() == lmW && m->SizeY() == lmH && Steady)
    return;
  delete[] Steady; delete[] Frame; delete[] Ambient; delete[] SrcCol; delete[] SrcLit; delete[] FogCol;
  Steady = NULL; Frame = NULL; Ambient = NULL; SrcCol = NULL; SrcLit = NULL; FogCol = NULL;
  lmW = m->SizeX(); lmH = m->SizeY(); lmCells = (int32)lmW * lmH;
  Steady = new LightRGB[lmCells];
  Frame  = new LightRGB[lmCells];
  Ambient = new LightRGB[lmCells];
  SrcCol = new LightRGB[lmCells];
  SrcLit = new uint8[lmCells];
  FogCol = new uint8[lmCells];
}

static LightSource &NewSource() {
  if (nSrc == capSrc) {
    capSrc = capSrc ? capSrc * 2 : 32;
    LightSource *n = new LightSource[capSrc];
    if (Src) memcpy(n, Src, sizeof(LightSource) * nSrc);
    delete[] Src; Src = n;
  }
  memset(&Src[nSrc], 0, sizeof(LightSource));
  return Src[nSrc++];
}

static void AddFoot(int32 idx, uint8 w, uint8 fr, uint8 fg, uint8 fb, int16 ci = -1) {
  if (nFoot == capFoot) {
    capFoot = capFoot ? capFoot * 2 : 1024;
    FootCell *n = new FootCell[capFoot];
    if (Foot) memcpy(n, Foot, sizeof(FootCell) * nFoot);
    delete[] Foot; Foot = n;
  }
  Foot[nFoot].idx = idx; Foot[nFoot].w = w;
  Foot[nFoot].fr = fr; Foot[nFoot].fg = fg; Foot[nFoot].fb = fb;
  Foot[nFoot].ci = ci; nFoot++;
}

static inline void AddScaled(LightRGB &d, LightRGB c, float k) {
  int32 r = (int32)(c.r * k), g = (int32)(c.g * k),
        b = (int32)(c.b * k);
  r = r < 0 ? 0 : (r > 255 ? 255 : r);
  g = g < 0 ? 0 : (g > 255 ? 255 : g);
  b = b < 0 ? 0 : (b > 255 ? 255 : b);
  /* Screen blending preserves hue where a hard clamp collapsed overlaps to white. */
  d.r = (uint8)(255 - (255 - d.r) * (255 - r) / 255);
  d.g = (uint8)(255 - (255 - d.g) * (255 - g) / 255);
  d.b = (uint8)(255 - (255 - d.b) * (255 - b) / 255);
}

static inline void AddScaledF(LightRGB &d, LightRGB c, float k,
                              const FootCell &fc) {
  c.r = (uint8)((int32)c.r * fc.fr / 255);
  c.g = (uint8)((int32)c.g * fc.fg / 255);
  c.b = (uint8)((int32)c.b * fc.fb / 255);
  AddScaled(d, c, k);
}

/* Seed and speed come from a hash of where the source stands, so a rebuild
   every turn does not restart every flame. */
static void AddSource(int16 x, int16 y, int16 r, uint8 kind, LightRGB glyphColour) {
  if (r <= 0) return;
  if (r > LIGHT_MAX_RADIUS) r = LIGHT_MAX_RADIUS;
  const LightKindRow &row = KindTable[kind];
  LightSource &s = NewSource();
  s.x = x; s.y = y; s.r = r; s.kind = kind;
  s.c = (row.c.r | row.c.g | row.c.b) ? row.c : glyphColour;
  uint32 h = (uint32)x * 73856093u ^ (uint32)y * 19349663u ^ (uint32)kind * 83492791u;
  s.seed = h;
  s.gain = row.gain;
  s.amp = row.amp;
  s.freq = row.freq * (0.85f + ((h >> 0) & 255) / 850.0f);
  s.oct = row.oct;
  s.bias = row.bias;
  s.noise = 1.0f;
  if (s.amp > 0.0f) anyFlicker = true;
}

/* A reflected source: a lit reflective wall re-emits a weak, steady, wall-
   coloured light. gain already carries the incident light, so it is not read
   from KindTable. It never flickers, so it adds no per-frame cost and does not
   double the flicker of the torch it reflects. */
static void AddReflectedSource(int16 x, int16 y, int16 r, LightRGB col, float gain,
                               int8 rdx, int8 rdy) {
  if (r <= 0 || gain <= 0.0f) return;
  if (r > LIGHT_MAX_RADIUS) r = LIGHT_MAX_RADIUS;
  LightSource &s = NewSource();
  s.x = x; s.y = y; s.r = r; s.kind = LK_REFLECT;
  s.c = col;
  s.seed = (uint32)x * 73856093u ^ (uint32)y * 19349663u ^ 0x9e3779b9u;
  s.gain = gain;
  s.amp = 0.0f; s.freq = 1.0f; s.oct = 1; s.bias = 1.0f;
  s.noise = 1.0f;
  s.rdx = rdx; s.rdy = rdy;
}

/* A wall torch stands in an opaque cell, and LineOfLight refuses a
   path that starts in one, so the ray is cast from the lit cell back to the
   source unless the lit cell is itself a wall face. LineOfLight, not the
   eye's LineOfVisualSight: fog and magical darkness stop sight, not a
   photon, and asking the eye's question left fog blocking light outright
   so the transmittance walk below never ran. inc-qh0w */
static bool Reaches(Map *m, int16 sx, int16 sy, int16 tx, int16 ty) {
  if (sx == tx && sy == ty) return true;
  if (m->OpaqueAt(tx, ty))
    return m->LineOfLight(sx, sy, tx, ty);
  return m->LineOfLight(tx, ty, sx, sy);
}

static LightRGB GlyphColour(Glyph g) {
  return Palette[GLYPH_FORE_VALUE(g) & COLOUR_MASK];
}

static bool CellFilter(Map *m, int16 x, int16 y, LightRGB &f) {
  LightRGB out = { 255, 255, 255 };
  bool filtered = false;
  TTerrain *tt = TTER(m->TerrainAt(x, y));
  LightRGB colours[2];
  float passes[2];
  int16 count = 0;
  if (tt && tt->Material == MAT_ICE && !tt->HasFlag(TF_OPAQUE)) {
    colours[count] = GlyphColour(tt->Image); passes[count++] = LIGHT_ICE_PASS;
  }
  int32 idx = (int32)y * lmW + x;
  if (FogCol[idx]) {
    colours[count] = Palette[FogCol[idx] - 1]; passes[count++] = LIGHT_FOG_PASS;
  }
  for (int16 i = 0; i < count; i++) {
    uint8 mx = colours[i].r > colours[i].g ? colours[i].r : colours[i].g;
    if (colours[i].b > mx) mx = colours[i].b;
    float nr = mx ? colours[i].r / (float)mx : 1.0f;
    float ng = mx ? colours[i].g / (float)mx : 1.0f;
    float nb = mx ? colours[i].b / (float)mx : 1.0f;
    LightRGB mult = {
      LightChannel(255.0f * passes[i] * (1.0f - LIGHT_FILTER_TINT + LIGHT_FILTER_TINT * nr)),
      LightChannel(255.0f * passes[i] * (1.0f - LIGHT_FILTER_TINT + LIGHT_FILTER_TINT * ng)),
      LightChannel(255.0f * passes[i] * (1.0f - LIGHT_FILTER_TINT + LIGHT_FILTER_TINT * nb))
    };
    out.r = (uint8)(((int32)out.r * mult.r + 127) / 255);
    out.g = (uint8)(((int32)out.g * mult.g + 127) / 255);
    out.b = (uint8)(((int32)out.b * mult.b + 127) / 255);
    filtered = true;
  }
  if (filtered) f = out;
  return filtered;
}

static int16 DDARound(int32 v, int16 n) {
  int16 sign = v < 0 ? -1 : 1;
  uint32 a = v < 0 ? (uint32)-v : (uint32)v;
  uint32 q = a / n, rem = a % n;
  if (rem * 2 > (uint32)n || (rem * 2 == (uint32)n && (q & 1))) q++;
  return (int16)(sign * (int32)q);
}

/* Visibility remains Reaches' decision; this second walk only gathers the
   colour and strength lost through cells that do not block sight. */
static bool FilterAlong(Map *m, int16 sx, int16 sy, int16 tx, int16 ty,
                        LightRGB &out) {
  out.r = out.g = out.b = 255;
  int16 dx = tx - sx, dy = ty - sy;
  int16 n = abs(dx) > abs(dy) ? abs(dx) : abs(dy);
  for (int16 k = 1; k < n; k++) {
    int16 x = sx + DDARound((int32)dx * k, n);
    int16 y = sy + DDARound((int32)dy * k, n);
    if (!m->InBounds(x, y)) continue;
    LightRGB mult;
    if (!CellFilter(m, x, y, mult)) continue;
    out.r = (uint8)(((int32)out.r * mult.r + 127) / 255);
    out.g = (uint8)(((int32)out.g * mult.g + 127) / 255);
    out.b = (uint8)(((int32)out.b * mult.b + 127) / 255);
  }
  uint8 mx = out.r > out.g ? out.r : out.g;
  if (out.b > mx) mx = out.b;
  return mx >= LIGHT_FILTER_MIN;
}

/* Inverse square, softened at the source so the centre cell does not
   diverge. Absolute in d, so a source's radius no longer sets how
   bright it is. */
static float RawFall(int16 d) {
  float k = LIGHT_SOFTEN;
  return k * k / (k * k + (float)d * (float)d);
}

static void CastFootprint(Map *m, LightSource &s) {
  s.first = nFoot;
  float edge = RawFall(s.r + 1);
  for (int16 y = s.y - s.r; y <= s.y + s.r; y++)
    for (int16 x = s.x - s.r; x <= s.x + s.r; x++) {
      if (!m->InBounds(x, y)) continue;
      int16 d = dist(x, y, s.x, s.y);
      if (d > s.r) continue;
      /* A reflected source lights only the hemisphere toward the light that lit
         it, so a wall never re-emits through itself to the dark side. Without
         this, ice makes the cell behind it brighter than the open, which is
         exactly what the filter must prevent. inc-qh0w */
      if ((s.rdx || s.rdy) &&
          (int32)(x - s.x) * s.rdx + (int32)(y - s.y) * s.rdy < 0)
        continue;
      /* Window the curve so it reaches exactly zero at the cutoff: a hard
         edge on an inverse square would leave a visible seam. */
      float w = (RawFall(d) - edge) / (1.0f - edge) * s.gain;
      if (w <= 0.0f) continue;
      if (!Reaches(m, s.x, s.y, x, y)) continue;
      LightRGB filter;
      if (!FilterAlong(m, s.x, s.y, x, y, filter)) continue;
      AddFoot((int32)y * lmW + x, (uint8)(w * 255.0f + 0.5f),
              filter.r, filter.g, filter.b);
    }
  s.count = nFoot - s.first;
}

/* A flash's footprint: every effect square at full gain, and every other cell
   within `reach` of the nearest effect square at the falloff from that square.
   A cell takes the MAX over the area (its nearest square), never a sum, so a
   big ball keeps its color and dims with distance. inc-jw0hw */
struct AreaSpec { const std::vector<FlashCell> &cells; int16 reach; float gain;
                  AreaSpec(const std::vector<FlashCell> &c, int16 r, float g)
                    : cells(c), reach(r), gain(g) {} };
static void CastAreaFootprint(Map *m, LightSource &s, const AreaSpec &fl) {
  s.first = nFoot;
  if (fl.cells.empty()) { s.count = 0; return; }
  int16 x0 = fl.cells[0].x, x1 = x0, y0 = fl.cells[0].y, y1 = y0;
  for (size_t i = 1; i < fl.cells.size(); i++) {
    if (fl.cells[i].x < x0) x0 = fl.cells[i].x;
    if (fl.cells[i].x > x1) x1 = fl.cells[i].x;
    if (fl.cells[i].y < y0) y0 = fl.cells[i].y;
    if (fl.cells[i].y > y1) y1 = fl.cells[i].y;
  }
  const int16 bw = x1 - x0 + 1, bh = y1 - y0 + 1;
  std::vector<int32> mark((size_t)bw * bh, 0);   /* effect square index + 1 */
  for (size_t i = 0; i < fl.cells.size(); i++)
    mark[(size_t)(fl.cells[i].y - y0) * bw + (fl.cells[i].x - x0)] = (int32)i + 1;
  const float g = fl.gain > 1.0f ? 1.0f : fl.gain;
  for (int16 y = y0 - fl.reach; y <= y1 + fl.reach; y++)
    for (int16 x = x0 - fl.reach; x <= x1 + fl.reach; x++) {
      if (!m->InBounds(x, y)) continue;
      int16 best = 0x7fff, bx = 0, by = 0, bi = -1;
      for (int16 ny = y - fl.reach; ny <= y + fl.reach; ny++)
        for (int16 nx = x - fl.reach; nx <= x + fl.reach; nx++) {
          if (nx < x0 || nx > x1 || ny < y0 || ny > y1) continue;
          if (!mark[(size_t)(ny - y0) * bw + (nx - x0)]) continue;
          int16 d = dist(x, y, nx, ny);
          if (d < best) { best = d; bx = nx; by = ny; bi = (int16)(mark[(size_t)(ny - y0) * bw + (nx - x0)] - 1); }
        }
      if (best > fl.reach) continue;
      if (best == 0) {
        AddFoot((int32)y * lmW + x, (uint8)(g * 255.0f + 0.5f), 255, 255, 255, bi);
        continue;
      }
      /* spill: 0.75 of the gain one square out, 0.45 two out (inc-jw0hw ruling) */
      float w = g * 0.75f * (1.0f - 0.4f * (float)(best - 1));
      if (w <= 0.0f) continue;
      if (!Reaches(m, bx, by, x, y)) continue;
      LightRGB filter;
      if (!FilterAlong(m, bx, by, x, y, filter)) continue;
      AddFoot((int32)y * lmW + x, (uint8)(w * 255.0f + 0.5f),
              filter.r, filter.g, filter.b, bi);
    }
  s.count = nFoot - s.first;
}

static void CastFlashFootprint(Map *m, LightSource &s) {
  const Flash &fl = Flashes[s.fid];
  CastAreaFootprint(m, s, AreaSpec(fl.cells, fl.reach, fl.gain));
}

static void ScanFlashes() {
  for (size_t i = 0; i < Flashes.size(); i++) {
    if (!Flashes[i].live) continue;
    LightSource &s = NewSource();
    s.kind = LK_FLASH; s.fid = (int32)i; s.c = Flashes[i].c;
    s.gain = Flashes[i].gain; s.noise = 1.0f;
    if (!Flashes[i].cells.empty()) {
      s.x = Flashes[i].cells[0].x; s.y = Flashes[i].cells[0].y;
    }
    anyFlicker = true;
  }
}

static void ScanCreatures(Map *m) {
  for (Thing *t = m->FirstThing(); t; t = m->NextThing()) {
    if (!t->isCreature()) continue;
    Creature *c = (Creature *)t;
    if (c->isDead() || c->LightRange == 0) continue;
    if (!m->InBounds(c->x, c->y)) continue;
    Item *li = c->EInSlot(SL_LIGHT);
    uint8 kind = LK_GLOW;
    LightRGB col = KindTable[LK_GLOW].c;
    if (li) {
      kind = li->GetLightRange() <= 4 ? LK_TORCH : LK_LANTERN;
      col = GlyphColour(li->Image);
    }
    AddSource(c->x, c->y, c->LightRange, kind, col);
  }
}

/* inc-jw0hw: a modifier or blocker field that gives no light of its own (a
   globe, a magic circle) glows faintly over its area plus one square. Fields
   carry no damage type, so the color is the field's own, lightened. */
static std::vector< std::vector<FlashCell> > AuraCells;

static void ScanFields(Map *m) {
  AuraCells.clear();
  for (int32 i = 0; i < m->Fields.Total(); i++) {
    Field *f = m->Fields[i];
    if (!f) continue;
    const bool plain = (f->Color > 0 && f->Color < MAX_COLOURS);
    if (f->FType & FI_LIGHT) {
      LightRGB col = plain ? Palette[f->Color] : GlyphColour(f->Image);
      AddSource(f->cx, f->cy, f->rad, LK_FIELD, col);
    } else if (f->FType & (FI_MODIFIER | FI_BLOCKER)) {
      LightRGB col = LightEffectColour(plain ? f->Color
        : (int16)(GLYPH_FORE_VALUE(f->Image) & COLOUR_MASK));
      AddSource(f->cx, f->cy, f->rad + 1, LK_AURA, col);
      /* The aura lights its own area evenly, plus a one-square spill. */
      std::vector<FlashCell> cells;
      for (int16 y = f->cy - f->rad; y <= f->cy + f->rad; y++)
        for (int16 x = f->cx - f->rad; x <= f->cx + f->rad; x++)
          if (m->InBounds(x, y) && f->inArea(x, y)) {
            FlashCell fc; fc.x = x; fc.y = y; fc.birth = 0.0f; fc.tinted = false; cells.push_back(fc);
          }
      Src[nSrc - 1].fid = (int32)AuraCells.size();
      AuraCells.push_back(cells);
    }
  }
}

/* Read terrain once for light sources and fog, clearing the fog map first. */
static void ScanTerrain(Map *m) {
  memset(FogCol, 0, sizeof(uint8) * lmCells);
  for (int16 y = 0; y < lmH; y++)
    for (int16 x = 0; x < lmW; x++) {
      TTerrain *tt = TTER(m->TerrainAt(x, y));
      if (!tt) continue;
      if (tt->HasFlag(TF_LOCAL_LIGHT))
        AddSource(x, y, 2, LK_MAGMA, GlyphColour(tt->Image));
      else if (tt->HasFlag(TF_TORCH))
        AddSource(x, y, 3, LK_WALLTORCH, GlyphColour(tt->Image));
      if (tt->HasFlag(TF_OBSCURE) &&
          (tt->Material == MAT_EMPTYNESS || tt->Material == MAT_FORCE))
        FogCol[(int32)y * lmW + x] =
          (GLYPH_FORE_VALUE(tt->Image) & COLOUR_MASK) + 1;
    }
}

/* Read fog fields after terrain so a cast cloud wins a shared cell. */
static void ScanFog(Map *m) {
  for (int32 i = 0; i < m->Fields.Total(); i++) {
    Field *f = m->Fields[i];
    if (!f || !(f->FType & FI_FOG)) continue;
    uint8 colour = (f->Color > 0 && f->Color < MAX_COLOURS)
      ? f->Color : (GLYPH_FORE_VALUE(f->Image) & COLOUR_MASK);
    for (int16 y = f->cy - f->rad; y <= f->cy + f->rad; y++)
      for (int16 x = f->cx - f->rad; x <= f->cx + f->rad; x++)
        if (m->InBounds(x, y) && f->inArea(x, y))
          FogCol[(int32)y * lmW + x] = colour + 1;
  }
}

/* One bounce off shiny walls. A solid wall of ice, glass or metal that the
   primary sources have lit becomes a weak secondary source coloured by the
   incoming light and, when selected, the material. It reads primary-only
   SrcLit and SrcCol, so a reflection can never seed another reflection. */
static void ScanReflections(Map *m) {
  for (int16 y = 0; y < lmH; y++)
    for (int16 x = 0; x < lmW; x++) {
      TTerrain *tt = TTER(m->TerrainAt(x, y));
      if (!tt || !tt->HasFlag(TF_WALL)) continue;
      int16 mat = tt->Material;
      if (mat != MAT_ICE && mat != MAT_GLASS && mat != MAT_METAL) continue;
      uint8 lit = SrcLit[(int32)y * lmW + x];
      if (lit < LIGHT_REFLECT_MIN) continue;
      /* Which way did the light come from? The brightest lit neighbour. The
         reflection emits into that hemisphere, so the wall glints back into the
         room and never through itself to the dark side behind it. */
      int8 rdx = 0, rdy = 0; uint8 best = 0;
      for (int16 oy = -1; oy <= 1; oy++)
        for (int16 ox = -1; ox <= 1; ox++) {
          if (!ox && !oy) continue;
          int16 nx = x + ox, ny = y + oy;
          if (!m->InBounds(nx, ny)) continue;
          uint8 nl = SrcLit[(int32)ny * lmW + nx];
          if (nl > best) { best = nl; rdx = (int8)ox; rdy = (int8)oy; }
        }
      LightRGB incoming = SrcCol[(int32)y * lmW + x];
      uint8 lm = incoming.r > incoming.g ? incoming.r : incoming.g;
      if (incoming.b > lm) lm = incoming.b;
      if (!lm) continue;
      float lr = incoming.r / (float)lm;
      float lg = incoming.g / (float)lm;
      float lb = incoming.b / (float)lm;
      LightRGB material = mat == MAT_ICE ? LIGHT_ICE_BASE : GlyphColour(tt->Image);
      uint8 mm = material.r > material.g ? material.r : material.g;
      if (material.b > mm) mm = material.b;
      float mr = mm ? material.r / (float)mm : 1.0f;
      float mg = mm ? material.g / (float)mm : 1.0f;
      float mb = mm ? material.b / (float)mm : 1.0f;
      float gr = lr, gg = lg, gb = lb;
#if LIGHT_GLINT_MODE == 1
      gr *= mr; gg *= mg; gb *= mb;
      float gm = gr > gg ? gr : gg;
      if (gb > gm) gm = gb;
      if (gm > 0.0f) {
        gr /= gm; gg /= gm; gb /= gm;
      } else {
        gr = lr; gg = lg; gb = lb;
      }
#endif
      float sat = LIGHT_REFLECT_SAT, white = 255.0f * (1.0f - sat);
      LightRGB glint = { LightChannel(white + 255.0f * gr * sat),
                         LightChannel(white + 255.0f * gg * sat),
                         LightChannel(white + 255.0f * gb * sat) };
      AddReflectedSource(x, y, LIGHT_REFLECT_RADIUS, glint,
                         lit / 255.0f * LIGHT_REFLECT, rdx, rdy);
    }
}

static void FoldSrcLit(int32 from, int32 to) {
  for (int32 i = from; i < to; i++)
    for (int32 k = Src[i].first; k < Src[i].first + Src[i].count; k++)
      if (Foot[k].w > SrcLit[Foot[k].idx])
        SrcLit[Foot[k].idx] = Foot[k].w;
}

static void SumSteady(Map *m) {
  for (int16 y = 0; y < lmH; y++)
    for (int16 x = 0; x < lmW; x++) {
      int32 idx = (int32)y * lmW + x;
      LightRGB &d = Steady[idx];
      d.r = d.g = d.b = 0;
      LightRGB &a = Ambient[idx];
      a.r = a.g = a.b = 0;
      const LocationInfo &at = m->At(x, y);
      /* Static light is kept per cell and joined to source light by a per-channel
         max in ComposeFrame, so a source neither double-counts it nor removes it. inc-7x99 */
      if (!m->FieldAt(x, y, FI_DARKNESS | FI_SHADOW)) {
        if (at.Bright)
          AddScaled(a, LIGHT_LEGACY_COLOUR, LIGHT_LEGACY_BRIGHT / 255.0f);
        else if (at.Lit)
          AddScaled(a, LIGHT_LEGACY_COLOUR, LIGHT_LEGACY_LIT / 255.0f);
      }
    }
  for (int32 i = 0; i < nSrc; i++) {
    const LightSource &s = Src[i];
    if (s.kind == LK_FLASH || s.amp > 0.0f) continue;
    for (int32 k = s.first; k < s.first + s.count; k++)
      AddScaledF(Steady[Foot[k].idx], s.c, Foot[k].w / 255.0f, Foot[k]);
  }
}

/* inc-jw0hw: the cooling ramp. A square's light follows (age ms, color, level)
   stops, linear between them, by that square's own age. The stops are written
   for a 900 ms life; a flash's life L scales every stop time by L/900. */
struct RampStop { float t; float r, g, b; float lv; };
struct RampSet { RampStop s[6]; int n; };
static inline float Hash01(uint32 h);
static LightRGB HueSat(float h, float sat);

static void RampPut(RampSet &rs, float t, float r, float g, float b, float lv) {
  RampStop &st = rs.s[rs.n++];
  st.t = t; st.r = r; st.g = g; st.b = b; st.lv = lv;
}
static void RampMix(RampSet &rs, float t, LightRGB c, float white, float lv) {
  RampPut(rs, t, c.r + (255.0f - c.r) * white, c.g + (255.0f - c.g) * white,
          c.b + (255.0f - c.b) * white, lv);
}
static void RampDarken(RampSet &rs, float t, LightRGB c, float k, float lv) {
  RampPut(rs, t, c.r * k, c.g * k, c.b * k, lv);
}
static void BuildRamp(uint8 kind, LightRGB c, RampSet &rs) {
  rs.n = 0;
  if (kind == LR_FIRE) {
    RampPut(rs,   0.0f, 255, 250, 220, 1.0f);
    RampPut(rs, 120.0f, 255, 220,  80, 1.0f);
    RampPut(rs, 300.0f, 255, 140,  30, 0.8f);
    RampPut(rs, 550.0f, 200,  40,  10, 0.5f);
    RampPut(rs, 800.0f,   0,   0,   0, 0.0f);
    RampPut(rs, 900.0f,   0,   0,   0, 0.0f);
  } else if (kind == LR_DARK) {
    RampDarken(rs,   0.0f, c, 1.0f, 1.0f);
    RampDarken(rs, 300.0f, c, 1.0f, 0.8f);
    RampDarken(rs, 550.0f, c, 0.6f, 0.5f);
    RampDarken(rs, 800.0f, c, 0.0f, 0.0f);
    RampDarken(rs, 900.0f, c, 0.0f, 0.0f);
  } else {
    RampMix(rs,   0.0f, c, 0.85f, 1.0f);
    RampMix(rs, 120.0f, c, 0.40f, 1.0f);
    RampMix(rs, 300.0f, c, 0.00f, 0.8f);
    RampDarken(rs, 550.0f, c, 0.6f, 0.5f);
    RampDarken(rs, 800.0f, c, 0.0f, 0.0f);
    RampDarken(rs, 900.0f, c, 0.0f, 0.0f);
  }
}
static void RampAtAge(const RampSet &rs, float age, LightRGB &rgb, float &lv) {
  int i = 0;
  while (i + 1 < rs.n && age >= rs.s[i + 1].t) i++;
  const RampStop &a = rs.s[i];
  float r = a.r, g = a.g, b = a.b, l = a.lv;
  if (i + 1 < rs.n) {
    const RampStop &z = rs.s[i + 1];
    const float f = (age - a.t) / (z.t - a.t);
    r += (z.r - a.r) * f; g += (z.g - a.g) * f; b += (z.b - a.b) * f;
    l += (z.lv - a.lv) * f;
  }
  rgb.r = LightChannel(r); rgb.g = LightChannel(g); rgb.b = LightChannel(b);
  lv = l;
}

/* One effect square's ramp color and level. A spill square passes its nearest
   effect square's index. A stale index (the flash's squares were replaced since
   the footprint was cast) reads as a square born now. `pre` is the flash's ramp
   when it does not depend on the square (every ramp but the rainbow's). */
static void FlashStage(const Flash &fl, const RampSet *pre, int ci,
                       LightRGB &rgb, float &lv) {
  float birth = fl.clock;
  int16 cx = 0, cy = 0;
  bool tinted = false; LightRGB tint = { 0, 0, 0 };
  if (ci >= 0 && ci < (int)fl.cells.size()) {
    birth = fl.cells[ci].birth; cx = fl.cells[ci].x; cy = fl.cells[ci].y;
    tinted = fl.cells[ci].tinted; tint = fl.cells[ci].tint;
  }
  if (fl.rise) {   /* inc-jw0hw: a rise has no ramp; its brightness is the flash level */
    const LightRGB b = tinted ? tint : fl.c;
    const float mx = (float)(b.r > b.g ? (b.r > b.b ? b.r : b.b) : (b.g > b.b ? b.g : b.b));
    const float k = mx > 0.0f ? 255.0f / mx : 1.0f;
    rgb.r = LightChannel(b.r * k); rgb.g = LightChannel(b.g * k); rgb.b = LightChannel(b.b * k);
    lv = 1.0f;
    return;
  }
  float age = fl.clock - birth;
  if (age < 0.0f) age = 0.0f;
  age *= 900.0f / (fl.life > 0.0f ? fl.life : 900.0f);
  RampSet own;
  if (tinted) {   /* inc-jw0hw: a square with its own base color (a color pattern) */
    BuildRamp(LR_GENERIC, tint, own);
    pre = &own;
  } else if (!pre) {   /* the rainbow: each square keeps its own hue for the effect's life */
    const float h = Hash01((uint32)cx * 73856093u ^ (uint32)cy * 19349663u ^ fl.seed);
    BuildRamp(LR_GENERIC, HueSat(h, 0.8f), own);
    pre = &own;
  }
  RampAtAge(*pre, age, rgb, lv);
}

static void ComposeFrame() {
  memcpy(Frame, Steady, sizeof(LightRGB) * lmCells);
  for (int32 i = 0; i < nSrc; i++) {
    const LightSource &s = Src[i];
    if (s.kind == LK_FLASH) {
      const Flash &fl = Flashes[s.fid];
      RampSet set;
      if (fl.ramp != LR_RAINBOW) BuildRamp(fl.ramp, fl.c, set);
      for (int32 k = s.first; k < s.first + s.count; k++) {
        LightRGB rgb; float lv;
        FlashStage(fl, fl.ramp != LR_RAINBOW ? &set : NULL, Foot[k].ci, rgb, lv);
        AddScaledF(Frame[Foot[k].idx], rgb,
                   Foot[k].w / 255.0f * lv * fl.level * fl.noise, Foot[k]);
      }
      continue;
    }
    if (s.amp <= 0.0f) continue;
    for (int32 k = s.first; k < s.first + s.count; k++)
      AddScaledF(Frame[Foot[k].idx], s.c,
                 Foot[k].w / 255.0f * s.noise, Foot[k]);
  }
  for (int32 i = 0; i < lmCells; i++) {
    if (Ambient[i].r > Frame[i].r) Frame[i].r = Ambient[i].r;
    if (Ambient[i].g > Frame[i].g) Frame[i].g = Ambient[i].g;
    if (Ambient[i].b > Frame[i].b) Frame[i].b = Ambient[i].b;
  }
}

static void ProbeDump(Map *m, Player *p);

void LightRebuild(Map *m, Player *p) {
  if (!m || !p) { lmMap = NULL; lmLegacy = true; nSrc = 0; nFoot = 0; return; }
  EnsureCells(m);
  lmLegacy = LightMode(p) == LIGHT_LEGACY;
  lmMap = m; nSrc = 0; nFoot = 0; anyFlicker = false;
  ScanCreatures(m);
  ScanFields(m);
  ScanFlashes();
  ScanTerrain(m);
  ScanFog(m);
  int32 nPrimary = nSrc;
  for (int32 i = 0; i < nSrc; i++) {
    if (Src[i].kind == LK_FLASH) CastFlashFootprint(m, Src[i]);
    else if (Src[i].kind == LK_AURA)
      CastAreaFootprint(m, Src[i], AreaSpec(AuraCells[Src[i].fid], 1, Src[i].gain));
    else CastFootprint(m, Src[i]);
  }
  memset(SrcLit, 0, sizeof(uint8) * lmCells);
  memset(SrcCol, 0, sizeof(LightRGB) * lmCells);
  FoldSrcLit(0, nPrimary);
  for (int32 i = 0; i < nPrimary; i++)
    for (int32 k = Src[i].first; k < Src[i].first + Src[i].count; k++)
      AddScaledF(SrcCol[Foot[k].idx], Src[i].c,
                 Foot[k].w / 255.0f, Foot[k]);
  /* Second pass: one bounce off shiny walls. ScanReflections reads the SrcLit
     just built from the primaries, then appends reflected sources. NewSource
     may realloc Src, so this MUST run between the two cast loops, never inside
     one -- the first loop is finished and the second has not begun, so no
     LightSource& is live across the realloc. inc-qh0w */
  ScanReflections(m);
  for (int32 i = nPrimary; i < nSrc; i++)
    CastFootprint(m, Src[i]);
  FoldSrcLit(nPrimary, nSrc);
  SumSteady(m);
  ComposeFrame();
  /* INCURSION_LIGHT_PROBE: the dump tools/check_lightmap.sh reads. Bead inc-bjgh. */
  if (getenv("INCURSION_LIGHT_PROBE"))
    ProbeDump(m, p);
}

static inline float Hash01(uint32 h) {
  h ^= h >> 16; h *= 0x7feb352du; h ^= h >> 15; h *= 0x846ca68bu; h ^= h >> 16;
  return (h & 0xffffffu) / (float)0x1000000;
}

/* Value noise: a hashed random value at each whole step, smoothstepped
   between them, so the result is continuous. */
static float ValueNoise(uint32 seed, float t) {
  float fl = floorf(t);
  int32 i = (int32)fl;
  float f = t - fl;
  float a = Hash01(seed ^ ((uint32)i * 2654435761u));
  float b = Hash01(seed ^ ((uint32)(i + 1) * 2654435761u));
  float u = f * f * (3.0f - 2.0f * f);
  return a + (b - a) * u;
}

/* Fractional Brownian motion: octaves at doubling frequency and halving
   amplitude, normalised back to 0..1. Two octaves breathe, four flicker. */
static float Fbm(uint32 seed, float t, int16 octaves) {
  float sum = 0.0f, amp = 0.5f, norm = 0.0f, freq = 1.0f;
  for (int16 o = 0; o < octaves; o++) {
    sum += amp * ValueNoise(seed + (uint32)o * 1013u, t * freq);
    norm += amp; amp *= 0.5f; freq *= 2.0f;
  }
  return norm > 0.0f ? sum / norm : 0.5f;
}

/* A hue (0..1) at saturation `sat`, full value, for the rainbow flash. */
static LightRGB HueSat(float h, float sat) {
  h -= floorf(h); h *= 6.0f;
  int i = (int)h; float f = h - i;
  float p = 1.0f - sat, q = 1.0f - sat * f, tt = 1.0f - sat * (1.0f - f);
  float r, g, b;
  switch (i % 6) {
    case 0: r = 1; g = tt; b = p; break;
    case 1: r = q; g = 1; b = p; break;
    case 2: r = p; g = 1; b = tt; break;
    case 3: r = p; g = q; b = 1; break;
    case 4: r = tt; g = p; b = 1; break;
    default: r = 1; g = p; b = q; break;
  }
  LightRGB o = { LightChannel(r * 255.0f), LightChannel(g * 255.0f),
                 LightChannel(b * 255.0f) };
  return o;
}

static void TickFlashes(float t) {
  for (size_t i = 0; i < Flashes.size(); i++) {
    Flash &fl = Flashes[i];
    if (!fl.live) continue;
    fl.noise = 1.0f;
    switch (fl.style) {
      case LF_FIRE: {
        float n = Fbm(fl.seed, t * 11.0f, 4);
        fl.noise = 1.0f - 0.45f + 0.45f * powf(n, 0.6f);
        break;
      }
      case LF_ARC:   /* a hashed step, not smooth noise */
        fl.noise = Hash01(fl.seed ^ ((uint32)floorf(t * 15.0f) * 2654435761u)) < 0.5f
                   ? 1.0f : 0.5f;
        break;
      default: break;
    }
  }
}

void LightTick(uint32 ms) {
  if (!lmMap || !anyFlicker) return;
  float t = ms / 1000.0f;
  TickFlashes(t);
  for (int32 i = 0; i < nSrc; i++) {
    LightSource &s = Src[i];
    if (s.amp <= 0.0f) continue;
    float n = Fbm(s.seed, t * s.freq, s.oct);          /* 0 .. 1 */
    /* Hold the peak at 1.0 so the swing is never clipped by the 255 ceiling. */
    s.noise = 1.0f - s.amp + s.amp * powf(n, s.bias);  /* 1-amp .. 1 */
  }
  ComposeFrame();
}

LightRGB LightEffectColour(int16 blastColour) {
  /* Fire 255,140,40; Cold 170,210,255; ... Rainbow starts at hue 0. */
  static const LightRGB T[COL_SUNYELLOW - COL_FIRE + 1] = {
    { 255, 140,  40 },  /* COL_FIRE    */
    { 170, 210, 255 },  /* COL_COLD    */
    { 210, 190, 255 },  /* COL_MAGIC   */
    {  80,  20, 140 },  /* COL_NECRO   */
    { 210, 225, 255 },  /* COL_ELEC    */
    { 255, 166, 166 },  /* COL_RAINBOW */
    { 255, 250, 235 },  /* COL_LIGHT   */
    { 170, 210,  90 },  /* COL_POISON  */
    { 120, 230, 100 },  /* COL_ACID    */
    {  80, 240, 160 },  /* COL_DISINT  */
    { 200, 180, 140 },  /* COL_PETRI   */
    { 240, 130, 220 },  /* COL_POLY    */
    { 200, 200, 200 },  /* COL_SONIC   */
    { 220, 225, 240 },  /* COL_SILVERY */
    { 220,  40,  60 },  /* COL_CRIMSON */
    { 170,  30,  30 },  /* COL_DARKRED */
    { 255, 215, 110 },  /* COL_SUNYELLOW */
  };
  if (blastColour >= COL_FIRE && blastColour <= COL_SUNYELLOW)
    return T[blastColour - COL_FIRE];
  LightRGB p = Palette[blastColour & COLOUR_MASK], o;
  o.r = (uint8)((p.r + 255) / 2);
  o.g = (uint8)((p.g + 255) / 2);
  o.b = (uint8)((p.b + 255) / 2);
  return o;
}

/* The aura circles the SDL build draws: one per LK_AURA source. rad is the
   field's own radius, so the circle marks the field's area. */
int32 LightAuraCount() {
  if (lmLegacy || !lmMap) return 0;
  int32 n = 0;
  for (int32 i = 0; i < nSrc; i++) if (Src[i].kind == LK_AURA) n++;
  return n;
}

bool LightAuraAt(int32 i, int16 &cx, int16 &cy, int16 &rad, LightRGB &c, float &noise) {
  if (lmLegacy || !lmMap) return false;
  for (int32 k = 0; k < nSrc; k++) {
    if (Src[k].kind != LK_AURA || i-- != 0) continue;
    cx = Src[k].x; cy = Src[k].y; rad = Src[k].r - 1;
    c = Src[k].c; noise = Src[k].noise;
    return true;
  }
  return false;
}

bool LightFlashDisabled() {
  return getenv("INCURSION_EFFECT_LIGHT_OFF") != NULL;
}

uint8 LightFlashRampFor(int16 blastColour) {
  switch (blastColour) {
    case COL_FIRE: return LR_FIRE;
    case COL_NECRO: case COL_DARKRED: return LR_DARK;
    case COL_RAINBOW: return LR_RAINBOW;
  }
  return LR_GENERIC;
}

int32 LightFlashAdd(LightRGB c, uint8 style, float gain, int16 reach, uint8 ramp) {
  if (LightFlashDisabled()) return -1;
  size_t id = 0;
  while (id < Flashes.size() && Flashes[id].live) id++;
  if (id == Flashes.size()) Flashes.push_back(Flash());
  Flash &fl = Flashes[id];
  fl.live = true; fl.c = c; fl.style = style; fl.ramp = ramp; fl.gain = gain;
  fl.clock = 0.0f; fl.life = 900.0f; fl.glyphs = false; fl.rise = false;
  fl.level = 1.0f; fl.noise = 1.0f; fl.reach = reach < 0 ? 0 : reach;
  fl.seed = (++flashSeq) * 2654435761u ^ (uint32)id * 40503u;
  fl.cells.clear();
  nFlashLive++;
  return (int32)id;
}

static Flash *FlashById(int32 id) {
  if (id < 0 || id >= (int32)Flashes.size() || !Flashes[id].live) return NULL;
  return &Flashes[id];
}

void LightFlashCell(int32 id, int16 x, int16 y) {
  Flash *fl = FlashById(id);
  if (!fl) return;
  for (size_t i = 0; i < fl->cells.size(); i++)
    if (fl->cells[i].x == x && fl->cells[i].y == y) return;
  FlashCell fc = { x, y, fl->clock };
  fl->cells.push_back(fc);
}

void LightFlashCellColour(int32 id, int16 x, int16 y, LightRGB c) {
  Flash *fl = FlashById(id);
  if (!fl) return;
  for (size_t i = 0; i < fl->cells.size(); i++)
    if (fl->cells[i].x == x && fl->cells[i].y == y) {
      fl->cells[i].tinted = true; fl->cells[i].tint = c;   /* the square's birth is untouched */
      if (lmMap && Frame) ComposeFrame();
      return;
    }
}

bool LightFlashTintAt(int16 x, int16 y, LightRGB &c) {
  for (size_t i = 0; i < Flashes.size(); i++) {
    if (!Flashes[i].live) continue;
    for (size_t k = 0; k < Flashes[i].cells.size(); k++) {
      const FlashCell &fc = Flashes[i].cells[k];
      if (fc.x == x && fc.y == y && fc.tinted) { c = fc.tint; return true; }
    }
  }
  return false;
}

void LightFlashMoveTo(int32 id, int16 x, int16 y) {
  Flash *fl = FlashById(id);
  if (!fl) return;
  fl->cells.clear();
  FlashCell fc = { x, y, fl->clock };
  fl->cells.push_back(fc);
}

void LightFlashClearCells(int32 id) {
  Flash *fl = FlashById(id);
  if (fl) fl->cells.clear();
}

void LightFlashLevel(int32 id, float level) {
  Flash *fl = FlashById(id);
  if (!fl) return;
  fl->level = level < 0.0f ? 0.0f : (level > 1.0f ? 1.0f : level);
  if (lmMap && Frame) ComposeFrame();
}

void LightFlashSetStyle(int32 id, uint8 style) {
  Flash *fl = FlashById(id);
  if (fl) fl->style = style;
}

void LightFlashSetRise(int32 id, bool on) {
  Flash *fl = FlashById(id);
  if (fl) fl->rise = on;
}

void LightFlashRecolour(int32 id, LightRGB c, uint8 style, float gain, uint8 ramp) {
  Flash *fl = FlashById(id);
  if (!fl) return;
  fl->c = c; fl->style = style; fl->gain = gain; fl->ramp = ramp;
  if (lmMap && Frame) ComposeFrame();
}

void LightFlashSetClock(int32 id, float ms) {
  Flash *fl = FlashById(id);
  if (!fl) return;
  fl->clock = ms < 0.0f ? 0.0f : ms;
  if (lmMap && Frame) ComposeFrame();
}

void LightFlashSetLife(int32 id, float ms) {
  Flash *fl = FlashById(id);
  if (fl && ms > 0.0f) fl->life = ms;
}

void LightFlashGlyphs(int32 id, bool shown) {
  Flash *fl = FlashById(id);
  if (fl) fl->glyphs = shown;
}

bool LightFlashSpent(int32 id) {
  const Flash *fl = FlashById(id);
  if (!fl) return true;
  for (size_t i = 0; i < fl->cells.size(); i++)
    if (fl->clock - fl->cells[i].birth < fl->life) return false;
  return true;
}

bool LightEffectGlyphAt(int16 x, int16 y, LightRGB &rgb) {
  if (lmLegacy || !lmMap) return false;
  /* inc-jw0hw: where several flashes light one square with their glyphs on, the youngest cell's color wins, so a creature's glow hands over to the next wave's. */
  int bf = -1, bk = -1; float bestAge = 0.0f;
  for (size_t i = 0; i < Flashes.size(); i++) {
    const Flash &fl = Flashes[i];
    if (!fl.live || !fl.glyphs) continue;
    for (size_t k = 0; k < fl.cells.size(); k++) {
      if (fl.cells[k].x != x || fl.cells[k].y != y) continue;
      const float age = fl.clock - fl.cells[k].birth;
      if (bf < 0 || age < bestAge) { bf = (int)i; bk = (int)k; bestAge = age; }
    }
  }
  if (bf < 0) return false;
  const Flash &fl = Flashes[bf];
  RampSet set;
  BuildRamp(fl.ramp, fl.c, set);
  LightRGB c; float lv;
  FlashStage(fl, fl.ramp != LR_RAINBOW ? &set : NULL, bk, c, lv);
  if (lv <= 0.0f) return false;
  if (fl.rise) { c.r = LightChannel(c.r * fl.level); c.g = LightChannel(c.g * fl.level); c.b = LightChannel(c.b * fl.level); }
  rgb = c;
  return true;
}

void LightFlashRemove(int32 id) {
  Flash *fl = FlashById(id);
  if (!fl) return;
  fl->live = false; fl->cells.clear();
  nFlashLive--;
}

void LightFlashClearAll() {
  Flashes.clear();
  nFlashLive = 0;
}

int32 LightFlashCount() {
  return nFlashLive;
}

bool LightAt(int16 x, int16 y, LightRGB &out) {
  if (!lmMap || x < 0 || y < 0 || x >= lmW || y >= lmH) return false;
  const LightRGB &f = Frame[(int32)y * lmW + x];
  if (!(f.r | f.g | f.b)) return false;
  out = f;
  return true;
}

/* The fog on one map cell as its palette colour, for the renderer's scatter
   tint. False, and `out` untouched, when the cell carries no fog. Reads the
   file-static FogCol, which ScanTerrain and ScanFog fill from fog terrain and
   from cast FI_FOG fields alike. */
bool LightFogAt(int16 x, int16 y, LightRGB &out) {
  if (!lmMap || !FogCol || x < 0 || y < 0 || x >= lmW || y >= lmH) return false;
  uint8 c = FogCol[(int32)y * lmW + x];
  if (!c) return false;
  out = Palette[(c - 1) & COLOUR_MASK];
  return true;
}

uint8 LightLevelAt(int16 x, int16 y) {
  if (!lmMap || !SrcLit || x < 0 || y < 0 || x >= lmW || y >= lmH) return 0;
  if (lmMap->FieldAt(x, y, FI_DARKNESS | FI_SHADOW)) return 0;
  uint8 source = SrcLit[(int32)y * lmW + x];
  uint8 legacy = LegacyLevel(x, y);
  /* max, not sum: a scalar cannot double-count a cell that is both a live source and legacy-.Bright; the render's additive path handles that. inc-jcg4 */
  return source > legacy ? source : legacy;
}

bool LightBrightAt(int16 x, int16 y) {
  /* upstream: source-blind hiding is upstream's because Win32 BrightAt/FI_LIGHT also omits dynamic external sources; Traced, inc-jcg4, not sent. */
  return LightLevelAt(x, y) >= LIGHT_HIDE_MIN;
}

bool LightLitAt(int16 x, int16 y) {
  /* With the option off, vision must be exactly what it was before the
     light map existed, so a before-and-after recording compares two real
     builds. */
  if (lmLegacy) return false;
  if (!lmMap || !SrcLit || x < 0 || y < 0 || x >= lmW || y >= lmH) return false;
  return LightLevelAt(x, y) >= LIGHT_SEE_MIN;
}

bool LightMapIsFor(Map *m) {
  /* Not authoritative in legacy mode: classic light must match the pre-light-map game, as LightLitAt's lmLegacy guard does. inc-jcg4 */
  return lmMap == m && !lmLegacy;
}

bool LightMapActive() {
  return lmMap && !lmLegacy;
}

/* INCURSION_LIGHT_PROBE=1 appends one block per change to logs/light.log:
   a header, one S line per source, then the source-light grid with ambient
   left out. '#' opaque unlit, '%' opaque lit, '.' unlit, 0-9 brightness.
   A FILTER grid follows: 'b' both ice and fog, 'i' ice, 'f' fog, '-' neither.
   tools/check_lightmap.sh reads it. */
static char FilterMark(Map *m, int16 x, int16 y) {
  TTerrain *tt = TTER(m->TerrainAt(x, y));
  bool ice = tt && tt->Material == MAT_ICE && !tt->HasFlag(TF_OPAQUE);
  bool fog = FogCol[(int32)y * lmW + x] != 0;
  return ice ? (fog ? 'b' : 'i') : (fog ? 'f' : '-');
}

static void ProbeDump(Map *m, Player *p) {
  static FILE *fp = NULL;
  static Map *lastMap = NULL; static int16 lastX = -1, lastY = -1;
  static int32 lastSrc = -1; static uint32 lastSig = 0;
  /* A fog cast and a terrain edit move neither the player, the map nor the
     source count, so without the filter signature the dump never records
     either and fog transmittance cannot be observed at all. inc-qh0w */
  uint32 sig = 2166136261u;
  for (int16 y = 0; y < lmH; y++)
    for (int16 x = 0; x < lmW; x++)
      { sig ^= (uint32)(uint8)FilterMark(m, x, y); sig *= 16777619u; }
  for (size_t i = 0; i < Flashes.size(); i++)
    if (Flashes[i].live) {
      sig ^= (uint32)Flashes[i].cells.size() * 31u + Flashes[i].style + 7u;
      sig *= 16777619u;
    }
  if (m == lastMap && p->x == lastX && p->y == lastY && nSrc == lastSrc
      && sig == lastSig)
    return;
  lastMap = m; lastX = p->x; lastY = p->y; lastSrc = nSrc; lastSig = sig;
  if (!fp) {
    char path[1024];
    snprintf(path, sizeof(path), "%slogs/light.log",
      (const char *)T1->IncursionDirectory);
    fp = fopen(path, "a");
    if (!fp) return;
  }
  fprintf(fp, "LIGHT map=%d %d player=%d %d plight=%d sources=%d\n",
    (int)lmW, (int)lmH, (int)p->x, (int)p->y, (int)p->LightRange, (int)nSrc);
  for (int32 i = 0; i < nSrc; i++)
    if (Src[i].kind != LK_FLASH)
    fprintf(fp, "S %d %d %d %d %d %d %d %d\n", (int)Src[i].x, (int)Src[i].y,
      (int)Src[i].r, Src[i].c.r, Src[i].c.g, Src[i].c.b, (int)Src[i].kind,
      (int)Src[i].count);
  for (size_t i = 0; i < Flashes.size(); i++)
    if (Flashes[i].live)
      fprintf(fp, "F %d %d %d %d %.3f\n", (int)i, (int)Flashes[i].cells.size(),
        (int)Flashes[i].reach, (int)Flashes[i].style, Flashes[i].level);
  for (int16 y = 0; y < lmH; y++) {
    for (int16 x = 0; x < lmW; x++) {
      LightRGB v = { 0, 0, 0 };
      for (int32 i = 0; i < nSrc; i++) {
        const LightSource &s = Src[i];
        if (s.kind == LK_FLASH) continue;
        if (dist(x, y, s.x, s.y) > s.r) continue;
        for (int32 k = s.first; k < s.first + s.count; k++)
          if (Foot[k].idx == (int32)y * lmW + x)
            { AddScaledF(v, s.c, Foot[k].w / 255.0f, Foot[k]); break; }
      }
      int mx = v.r > v.g ? v.r : v.g; if (v.b > mx) mx = v.b;
      bool opaque = m->OpaqueAt(x, y);
      char ch = opaque ? (mx ? '%' : '#') : (mx ? (char)('0' + mx * 10 / 256) : '.');
      fputc(ch, fp);
    }
    fputc('\n', fp);
  }
  fprintf(fp, "FILTER\n");
  for (int16 y = 0; y < lmH; y++) {
    for (int16 x = 0; x < lmW; x++)
      fputc(FilterMark(m, x, y), fp);
    fputc('\n', fp);
  }
  fprintf(fp, "AMBIENT\n");
  for (int16 y = 0; y < lmH; y++) {
    for (int16 x = 0; x < lmW; x++) {
      int32 idx = (int32)y * lmW + x;
      const LightRGB &a = Ambient[idx];
      const LightRGB &f = Frame[idx];
      char ch;
      if (!a.r && !a.g && !a.b)
        ch = '-';
      else if (f.r < a.r || f.g < a.g || f.b < a.b)
        ch = 'X';
      else if (SrcLit[idx] > 0)
        ch = 'A';
      else
        ch = 'a';
      fputc(ch, fp);
    }
    fputc('\n', fp);
  }
  fprintf(fp, "P plight=%d pbright=%d psource=%d punified=%d\n",
    (int)p->LightRange, m->At(p->x, p->y).Bright ? 1 : 0,
    (int)SrcLit[(int32)p->y * lmW + p->x], LightBrightAt(p->x, p->y) ? 1 : 0);
  fflush(fp);
}
