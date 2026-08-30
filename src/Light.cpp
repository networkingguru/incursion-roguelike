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
#define LIGHT_FLOOR_PCT  0

enum LightKind { LK_TORCH, LK_LANTERN, LK_GLOW, LK_FIELD, LK_MAGMA,
                 LK_WALLTORCH, LK_KINDS };

/* ponytail: a source's colour comes from this table, or from its own glyph
   when the table row is black. The upgrade path is a "Light Colour:" field in
   the .irh grammar (lang/Grammar.acc, the LIGHT RANGE rule), which needs the
   generated parser rebuilt. Amplitude is the flicker depth; f1 and f2 are the
   two sine frequencies in Hz that LightTick mixes. */
struct LightKindRow { LightRGB c; float amp, f1, f2; };
static const LightKindRow KindTable[LK_KINDS] = {
  /* LK_TORCH     */ { { 255, 147,  41 }, 0.18f, 2.1f, 7.3f },
  /* LK_LANTERN   */ { { 255, 214, 150 }, 0.05f, 1.3f, 4.1f },
  /* LK_GLOW      */ { { 150, 180, 255 }, 0.00f, 0.0f, 0.0f },
  /* LK_FIELD     */ { {   0,   0,   0 }, 0.04f, 0.7f, 2.9f },
  /* LK_MAGMA     */ { { 255,  80,  20 }, 0.25f, 1.7f, 5.9f },
  /* LK_WALLTORCH */ { { 255, 160,  60 }, 0.18f, 2.4f, 6.7f },
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
  float amp, w1, w2, p1, p2;   /* flicker: depth, angular speeds, phases */
  float noise;                 /* current multiplier, 1.0 when steady */
  int32 first, count;          /* slice of Foot[] */
};

struct FootCell { int32 idx; uint8 w; };

static Map    *lmMap = NULL;
static int16   lmW = 0, lmH = 0;
static int32   lmCells = 0;
static LightRGB *Steady = NULL, *Frame = NULL;   /* per cell */
static LightSource *Src = NULL; static int32 nSrc = 0, capSrc = 0;
static FootCell    *Foot = NULL; static int32 nFoot = 0, capFoot = 0;
static bool        anyFlicker = false;

void LightSetPalette(const LightRGB *sixteen) {
  memcpy(Palette, sixteen, sizeof(Palette));
}

static void EnsureCells(Map *m) {
  if (m->SizeX() == lmW && m->SizeY() == lmH && Steady)
    return;
  delete[] Steady; delete[] Frame;
  lmW = m->SizeX(); lmH = m->SizeY(); lmCells = (int32)lmW * lmH;
  Steady = new LightRGB[lmCells];
  Frame  = new LightRGB[lmCells];
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
  int32 r = d.r + (int32)(c.r * k), g = d.g + (int32)(c.g * k),
        b = d.b + (int32)(c.b * k);
  d.r = (uint8)(r > 255 ? 255 : r);
  d.g = (uint8)(g > 255 ? 255 : g);
  d.b = (uint8)(b > 255 ? 255 : b);
}

/* Phase and speed come from a hash of where the source stands, so a rebuild
   every turn does not restart every flame. */
static void AddSource(int16 x, int16 y, int16 r, uint8 kind, LightRGB glyphColour) {
  if (r <= 0) return;
  if (r > LIGHT_MAX_RADIUS) r = LIGHT_MAX_RADIUS;
  const LightKindRow &row = KindTable[kind];
  LightSource &s = NewSource();
  s.x = x; s.y = y; s.r = r; s.kind = kind;
  s.c = (row.c.r | row.c.g | row.c.b) ? row.c : glyphColour;
  uint32 h = (uint32)x * 73856093u ^ (uint32)y * 19349663u ^ (uint32)kind * 83492791u;
  s.amp = row.amp;
  s.w1 = 2.0f * (float)M_PI * row.f1 * (0.85f + ((h >> 0) & 255) / 850.0f);
  s.w2 = 2.0f * (float)M_PI * row.f2 * (0.85f + ((h >> 8) & 255) / 850.0f);
  s.p1 = ((h >> 16) & 255) / 255.0f * 6.2832f;
  s.p2 = ((h >> 24) & 255) / 255.0f * 6.2832f;
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

static void CastFootprint(Map *m, LightSource &s) {
  s.first = nFoot;
  for (int16 y = s.y - s.r; y <= s.y + s.r; y++)
    for (int16 x = s.x - s.r; x <= s.x + s.r; x++) {
      if (!m->InBounds(x, y)) continue;
      int16 d = dist(x, y, s.x, s.y);
      if (d > s.r) continue;
      float f = (float)d / (float)(s.r + 1);
      float w = 1.0f - f * f;
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
  static const LightRGB LitRoom = { 36, 32, 26 }, Skylight = { 30, 36, 48 };
  for (int16 y = 0; y < lmH; y++)
    for (int16 x = 0; x < lmW; x++) {
      LightRGB &d = Steady[(int32)y * lmW + x];
      d.r = d.g = d.b = 0;
      const LocationInfo &at = m->At(x, y);
      if (at.isSkylight) AddScaled(d, Skylight, 1.0f);
      else if (at.Lit)   AddScaled(d, LitRoom, 1.0f);
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
  SumSteady(m);
  ComposeFrame();
  /* INCURSION_LIGHT_PROBE: the dump tools/check_lightmap.sh reads. Bead inc-bjgh. */
  if (getenv("INCURSION_LIGHT_PROBE"))
    ProbeDump(m, p);
}

void LightTick(uint32 ms) {
  if (!lmMap || !anyFlicker) return;
  float t = ms / 1000.0f;
  for (int32 i = 0; i < nSrc; i++) {
    LightSource &s = Src[i];
    if (s.amp <= 0.0f) continue;
    s.noise = 1.0f + s.amp * (0.6f * sinf(s.w1 * t + s.p1)
                            + 0.4f * sinf(s.w2 * t + s.p2));
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
