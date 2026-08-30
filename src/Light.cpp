/* LIGHT.CPP -- See the Incursion LICENSE file for copyright information.

   The runtime light map. See inc/Light.h for the contract and the plan
   (docs/superpowers/plans/2026-08-30-ascii-lighting-brief.md) for the
   design. Nothing here may include a backend header: the posix build
   compiles this file too. */

#include "Incursion.h"
#include "Light.h"
#include <math.h>
#include <stdlib.h>
#include <string.h>

#define LIGHT_MAX_RADIUS 12

enum LightKind { LK_TORCH, LK_LANTERN, LK_GLOW, LK_FIELD, LK_MAGMA,
                 LK_WALLTORCH, LK_KINDS };

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
};

struct FootCell { int32 idx; uint8 w; };

static Map    *lmMap = NULL;
static int16   lmW = 0, lmH = 0;
static int32   lmCells = 0;
static LightRGB *Steady = NULL, *Frame = NULL;   /* per cell */
static uint8 *SrcLit = NULL;                     /* strongest source light, 0..255 */
static LightSource *Src = NULL; static int32 nSrc = 0, capSrc = 0;
static FootCell    *Foot = NULL; static int32 nFoot = 0, capFoot = 0;
static bool        anyFlicker = false;

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

LightRGB LightShade(int idx, LightRGB L, float unlit) {
  LightRGB b = Palette[idx & COLOUR_MASK], o;
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
  delete[] Steady; delete[] Frame; delete[] SrcLit;
  Steady = NULL; Frame = NULL; SrcLit = NULL;
  lmW = m->SizeX(); lmH = m->SizeY(); lmCells = (int32)lmW * lmH;
  Steady = new LightRGB[lmCells];
  Frame  = new LightRGB[lmCells];
  SrcLit = new uint8[lmCells];
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

static void AddFoot(int32 idx, uint8 w) {
  if (nFoot == capFoot) {
    capFoot = capFoot ? capFoot * 2 : 1024;
    FootCell *n = new FootCell[capFoot];
    if (Foot) memcpy(n, Foot, sizeof(FootCell) * nFoot);
    delete[] Foot; Foot = n;
  }
  Foot[nFoot].idx = idx; Foot[nFoot].w = w; nFoot++;
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

/* A wall torch stands in an opaque cell, and LineOfVisualSight refuses a
   path that starts in one, so the ray is cast from the lit cell back to the
   source unless the lit cell is itself a wall face. */
static bool Reaches(Map *m, int16 sx, int16 sy, int16 tx, int16 ty) {
  if (sx == tx && sy == ty) return true;
  if (m->OpaqueAt(tx, ty))
    return m->LineOfVisualSight(sx, sy, tx, ty, NULL);
  return m->LineOfVisualSight(tx, ty, sx, sy, NULL);
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
      /* Window the curve so it reaches exactly zero at the cutoff: a hard
         edge on an inverse square would leave a visible seam. */
      float w = (RawFall(d) - edge) / (1.0f - edge) * s.gain;
      if (w <= 0.0f) continue;
      if (!Reaches(m, s.x, s.y, x, y)) continue;
      AddFoot((int32)y * lmW + x, (uint8)(w * 255.0f + 0.5f));
    }
  s.count = nFoot - s.first;
}

static LightRGB GlyphColour(Glyph g) {
  return Palette[GLYPH_FORE_VALUE(g) & COLOUR_MASK];
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

static void SumSteady(Map *m) {
  static const LightRGB Skylight = { 170, 185, 210 };
  for (int16 y = 0; y < lmH; y++)
    for (int16 x = 0; x < lmW; x++) {
      LightRGB &d = Steady[(int32)y * lmW + x];
      d.r = d.g = d.b = 0;
      const LocationInfo &at = m->At(x, y);
      if (at.isSkylight) AddScaled(d, Skylight, 1.0f);
      /* Lit ambient double-counted wall torches, which are sources in their own right. */
    }
  for (int32 i = 0; i < nSrc; i++) {
    const LightSource &s = Src[i];
    if (s.amp > 0.0f) continue;
    for (int32 k = s.first; k < s.first + s.count; k++)
      AddScaled(Steady[Foot[k].idx], s.c, Foot[k].w / 255.0f);
  }
}

static void ComposeFrame() {
  memcpy(Frame, Steady, sizeof(LightRGB) * lmCells);
  for (int32 i = 0; i < nSrc; i++) {
    const LightSource &s = Src[i];
    if (s.amp <= 0.0f) continue;
    for (int32 k = s.first; k < s.first + s.count; k++)
      AddScaled(Frame[Foot[k].idx], s.c, Foot[k].w / 255.0f * s.noise);
  }
}

static void ProbeDump(Map *m, Player *p);

void LightRebuild(Map *m, Player *p) {
  if (!m || !p) { lmMap = NULL; nSrc = 0; nFoot = 0; return; }
  EnsureCells(m);
  lmMap = m; nSrc = 0; nFoot = 0; anyFlicker = false;
  ScanCreatures(m);
  ScanFields(m);
  ScanTerrain(m);
  for (int32 i = 0; i < nSrc; i++)
    CastFootprint(m, Src[i]);
  memset(SrcLit, 0, sizeof(uint8) * lmCells);
  for (int32 i = 0; i < nSrc; i++)
    for (int32 k = Src[i].first; k < Src[i].first + Src[i].count; k++)
      if (Foot[k].w > SrcLit[Foot[k].idx])
        SrcLit[Foot[k].idx] = Foot[k].w;
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

bool LightLitAt(int16 x, int16 y) {
  if (!lmMap || !SrcLit || x < 0 || y < 0 || x >= lmW || y >= lmH) return false;
  return SrcLit[(int32)y * lmW + x] >= LIGHT_SEE_MIN;
}

/* INCURSION_LIGHT_PROBE=1 appends one block per change to logs/light.log:
   a header, one S line per source, then the source-light grid with ambient
   left out. '#' opaque unlit, '%' opaque lit, '.' unlit, 0-9 brightness.
   tools/check_lightmap.sh reads it. */
static void ProbeDump(Map *m, Player *p) {
  static FILE *fp = NULL;
  static Map *lastMap = NULL; static int16 lastX = -1, lastY = -1;
  static int32 lastSrc = -1;
  if (m == lastMap && p->x == lastX && p->y == lastY && nSrc == lastSrc)
    return;
  lastMap = m; lastX = p->x; lastY = p->y; lastSrc = nSrc;
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
            { AddScaled(v, s.c, Foot[k].w / 255.0f); break; }
      }
      int mx = v.r > v.g ? v.r : v.g; if (v.b > mx) mx = v.b;
      bool opaque = m->OpaqueAt(x, y);
      char ch = opaque ? (mx ? '%' : '#') : (mx ? (char)('0' + mx * 10 / 256) : '.');
      fputc(ch, fp);
    }
    fputc('\n', fp);
  }
  fflush(fp);
}
