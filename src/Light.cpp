/* LIGHT.CPP -- See the Incursion LICENSE file for copyright information.

   The runtime light map. See inc/Light.h for the contract and the plan
   (docs/superpowers/plans/2026-08-30-ascii-lighting-brief.md) for the
   design. Nothing here may include a backend header: the posix build
   compiles this file too. */

/* Incursion.h defines min and max as macros, so system headers must precede
   them because libstdc++ declares std::min/std::max through <math.h>. */
#include <math.h>
#include <stdlib.h>
#include <string.h>

#include "Incursion.h"
#include "Light.h"

#define LIGHT_MAX_RADIUS 12

enum LightKind { LK_TORCH, LK_LANTERN, LK_GLOW, LK_FIELD, LK_MAGMA,
                 LK_WALLTORCH, LK_REFLECT, LK_KINDS };

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
};

struct FootCell { int32 idx; uint8 w; uint8 fr, fg, fb; };

static Map    *lmMap = NULL;
static bool    lmLegacy = false;    /* the option turned the lighting off */
static int16   lmW = 0, lmH = 0;
static int32   lmCells = 0;
static LightRGB *Steady = NULL, *Frame = NULL;   /* per cell */
static LightRGB *SrcCol = NULL;                  /* summed primary source colour */
static uint8 *SrcLit = NULL;                     /* strongest source light, 0..255 */
static uint8 *FogCol = NULL;                     /* fog palette index plus one, or zero */
static LightSource *Src = NULL; static int32 nSrc = 0, capSrc = 0;
static FootCell    *Foot = NULL; static int32 nFoot = 0, capFoot = 0;
static bool        anyFlicker = false;

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

LightRGB LightMemoryBase(LightRGB base, float unlit) {
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
  float mem = unlit + (1.0f - unlit) * LIGHT_MEMORY_LIFT;
  o.r = LightChannel((hr + (g - hr) * LIGHT_MEMORY_GREY) * mem);
  o.g = LightChannel((hg + (g - hg) * LIGHT_MEMORY_GREY) * mem);
  o.b = LightChannel((hb + (g - hb) * LIGHT_MEMORY_GREY) * mem);
  return o;
}

LightRGB LightMemory(int idx, float unlit) {
  return LightMemoryBase(Palette[idx & COLOUR_MASK], unlit);
}

LightRGB LightInfra(int idx, bool warm) {
  LightRGB b = Palette[idx & COLOUR_MASK], o;
  float v = ColValue(b);
  float s = (LIGHT_INFRA_FLOOR + (1.0f - LIGHT_INFRA_FLOOR) * v)
            * (warm ? 1.0f : LIGHT_INFRA_COLD);
  o.r = LightChannel(LIGHT_INFRA_R * s);
  o.g = LightChannel(LIGHT_INFRA_G * s);
  o.b = LightChannel(LIGHT_INFRA_B * s);
  return o;
}

LightRGB LightInfraMix(LightRGB lit, int idx, bool warm,
                       LightRGB L, float infra) {
  if (infra <= 0.0f) return lit;
  float i = ColValue(L) / LIGHT_INFRA_YIELD;
  if (i > 1.0f) i = 1.0f;
  float k = infra * (1.0f - i);      /* how much red survives */
  if (k <= 0.0f) return lit;
  LightRGB h = LightInfra(idx, warm), o;
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
  delete[] Steady; delete[] Frame; delete[] SrcCol; delete[] SrcLit; delete[] FogCol;
  Steady = NULL; Frame = NULL; SrcCol = NULL; SrcLit = NULL; FogCol = NULL;
  lmW = m->SizeX(); lmH = m->SizeY(); lmCells = (int32)lmW * lmH;
  Steady = new LightRGB[lmCells];
  Frame  = new LightRGB[lmCells];
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

static void AddFoot(int32 idx, uint8 w, uint8 fr, uint8 fg, uint8 fb) {
  if (nFoot == capFoot) {
    capFoot = capFoot ? capFoot * 2 : 1024;
    FootCell *n = new FootCell[capFoot];
    if (Foot) memcpy(n, Foot, sizeof(FootCell) * nFoot);
    delete[] Foot; Foot = n;
  }
  Foot[nFoot].idx = idx; Foot[nFoot].w = w;
  Foot[nFoot].fr = fr; Foot[nFoot].fg = fg; Foot[nFoot].fb = fb; nFoot++;
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

static void ScanFields(Map *m) {
  for (int32 i = 0; i < m->Fields.Total(); i++) {
    Field *f = m->Fields[i];
    if (!f || !(f->FType & FI_LIGHT)) continue;
    LightRGB col = (f->Color > 0 && f->Color < MAX_COLOURS)
      ? Palette[f->Color] : GlyphColour(f->Image);
    AddSource(f->cx, f->cy, f->rad, LK_FIELD, col);
  }
}

static void ScanTerrain(Map *m) {
  for (int16 y = 0; y < lmH; y++)
    for (int16 x = 0; x < lmW; x++) {
      TTerrain *tt = TTER(m->TerrainAt(x, y));
      if (!tt) continue;
      if (tt->HasFlag(TF_LOCAL_LIGHT))
        AddSource(x, y, 2, LK_MAGMA, GlyphColour(tt->Image));
      else if (tt->HasFlag(TF_TORCH))
        AddSource(x, y, 3, LK_WALLTORCH, GlyphColour(tt->Image));
    }
}

static void ScanFog(Map *m) {
  memset(FogCol, 0, sizeof(uint8) * lmCells);
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
      const LocationInfo &at = m->At(x, y);
      /* Legacy static light contributes only outside live footprints and dark fields. inc-jcg4 */
      if (!SrcLit[idx] && !m->FieldAt(x, y, FI_DARKNESS | FI_SHADOW)) {
        if (at.Bright)
          AddScaled(d, LIGHT_LEGACY_COLOUR, LIGHT_LEGACY_BRIGHT / 255.0f);
        else if (at.Lit)
          AddScaled(d, LIGHT_LEGACY_COLOUR, LIGHT_LEGACY_LIT / 255.0f);
      }
    }
  for (int32 i = 0; i < nSrc; i++) {
    const LightSource &s = Src[i];
    if (s.amp > 0.0f) continue;
    for (int32 k = s.first; k < s.first + s.count; k++)
      AddScaledF(Steady[Foot[k].idx], s.c, Foot[k].w / 255.0f, Foot[k]);
  }
}

static void ComposeFrame() {
  memcpy(Frame, Steady, sizeof(LightRGB) * lmCells);
  for (int32 i = 0; i < nSrc; i++) {
    const LightSource &s = Src[i];
    if (s.amp <= 0.0f) continue;
    for (int32 k = s.first; k < s.first + s.count; k++)
      AddScaledF(Frame[Foot[k].idx], s.c,
                 Foot[k].w / 255.0f * s.noise, Foot[k]);
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
  ScanTerrain(m);
  ScanFog(m);
  int32 nPrimary = nSrc;
  for (int32 i = 0; i < nSrc; i++)
    CastFootprint(m, Src[i]);
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

void LightTick(uint32 ms) {
  if (!lmMap || !anyFlicker) return;
  float t = ms / 1000.0f;
  for (int32 i = 0; i < nSrc; i++) {
    LightSource &s = Src[i];
    if (s.amp <= 0.0f) continue;
    float n = Fbm(s.seed, t * s.freq, s.oct);          /* 0 .. 1 */
    /* Hold the peak at 1.0 so the swing is never clipped by the 255 ceiling. */
    s.noise = 1.0f - s.amp + s.amp * powf(n, s.bias);  /* 1-amp .. 1 */
  }
  ComposeFrame();
}

bool LightAt(int16 x, int16 y, LightRGB &out) {
  if (!lmMap || x < 0 || y < 0 || x >= lmW || y >= lmH) return false;
  const LightRGB &f = Frame[(int32)y * lmW + x];
  if (!(f.r | f.g | f.b)) return false;
  out = f;
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
    fprintf(fp, "S %d %d %d %d %d %d %d %d\n", (int)Src[i].x, (int)Src[i].y,
      (int)Src[i].r, Src[i].c.r, Src[i].c.g, Src[i].c.b, (int)Src[i].kind,
      (int)Src[i].count);
  for (int16 y = 0; y < lmH; y++) {
    for (int16 x = 0; x < lmW; x++) {
      LightRGB v = { 0, 0, 0 };
      for (int32 i = 0; i < nSrc; i++) {
        const LightSource &s = Src[i];
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
  fprintf(fp, "P plight=%d pbright=%d psource=%d punified=%d\n",
    (int)p->LightRange, m->At(p->x, p->y).Bright ? 1 : 0,
    (int)SrcLit[(int32)p->y * lmW + p->x], LightBrightAt(p->x, p->y) ? 1 : 0);
  fflush(fp);
}
