/* inc-jw0hw: the light an animated effect casts while it shows. See
   inc/EffectLight.h. */
#include "Incursion.h"
#include <vector>

static EffectLight *ScriptFx = NULL;

void (*EffectLightHook)(int phase) = NULL;
void (*EffectWaitHook)(int ms) = NULL;
void (*TargetFlashHook)(int phase) = NULL;
void (*EffectStepHook)(int kind, int16 x, int16 y, Glyph g) = NULL;
void (*ScriptLightTickHook)(float clockMs) = NULL;
void (*ScriptLightEndHook)() = NULL;

/* The light color row for a damage type, or 0 when the type has none. */
static int16 DTypeLightColour(int16 dtype) {
  switch (dtype) {
    case AD_FIRE: return COL_FIRE;
    case AD_COLD: return COL_COLD;
    case AD_ELEC: return COL_ELEC;
    case AD_ACID: return COL_ACID;
    case AD_DISN: return COL_DISINT;
    case AD_SONI: return COL_SONIC;
    case AD_TOXI: case AD_POIS: return COL_POISON;
    case AD_NECR: case AD_DREX: case AD_DRST: case AD_DRCO: case AD_EVIL: return COL_NECRO;
    case AD_SUNL: return COL_LIGHT;
    case AD_MAGC: return COL_MAGIC;
    case AD_STON: return COL_PETRI;
    case AD_POLY: return COL_POLY;
  }
  return 0;
}

/* True for a damage type that is visible energy: fire, cold, electricity,
   light, magic, necromantic, disintegration, holy, law, chaos. Material,
   force, sonic, wind, mental, drain and evil types do not glow. */
static bool TypeGlows(int16 dtype) {
  switch (dtype) {
    case AD_FIRE: case AD_COLD: case AD_ELEC: case AD_SUNL: case AD_MAGC:
    case AD_NECR: case AD_DREX: case AD_DISN:
    case AD_HOLY: case AD_LAWF: case AD_CHAO:
      return true;
  }
  return false;
}

/* inc-jw0hw: the one place that decides whether an effect glows and in what
   color. The damage type decides by default; EF_GLOW and EF_NO_GLOW override
   it in data. A COL_* set in cval beats the type's row. Otherwise the type's
   row gives the color; an EF_GLOW effect whose own type is not energy takes
   the row of the first energy type among its later components; else the plain
   cval, lightened, is the color. */
EffectLightDecision EffectLightDecide(TEffect *te, int16 dtype) {
  EffectLightDecision d;
  d.lit = true;
  d.colour = 0;
  d.grade = 0;
  if (!te)
    return d;
  d.grade = te->HasFlag(EF_GRADE_3) ? 3 : te->HasFlag(EF_GRADE_2) ? 2 : te->HasFlag(EF_GRADE_1) ? 1 : 0;
  if (te->HasFlag(EF_GLOW)) d.lit = true;
  else if (te->HasFlag(EF_NO_GLOW)) d.lit = false;
  else d.lit = TypeGlows(dtype);
  const int16 cv = te->ef.cval;
  if (cv >= COL_FIRE && cv <= COL_SUNYELLOW) {
    d.colour = cv;
    return d;
  }
  int16 row = DTypeLightColour(dtype);
  if (te->HasFlag(EF_GLOW) && !TypeGlows(dtype))
    for (int8 n = 1; te->Vals(n); n++) {
      const EffectValues *ev = te->Vals(n);
      if (ev->eval == EA_BLAST && TypeGlows(ev->xval)) {
        row = DTypeLightColour(ev->xval);
        break;
      }
    }
  d.colour = row ? row : cv;
  /* A plain SHADOW cval is the negative-energy color (NECRO_C, lib/threats.irh). */
  if (te->HasFlag(EF_GLOW) && !row && cv == SHADOW)
    d.colour = COL_NECRO;
  return d;
}

EffectLight::EffectLight(Map *m, int16 blastColour, uint8 shape, int16 dtype,
                         TEffect *te, bool targetFlash)
    : grade(0), map(m), id(-1), ended(false), lit(true), target(targetFlash),
      clockMs(0.0f), life(900.0f), glyphsOn(false), risen(false), standing(false) {
  if (te) {
    const EffectLightDecision d = EffectLightDecide(te, dtype);
    lit = d.lit || (targetFlash && te->HasFlag(EF_FLASH_STRUCK));   /* inc-jw0hw: an unlit effect may still flash what it strikes */
    if (d.colour)
      blastColour = d.colour;
    grade = d.grade;
  } else if (const int16 dc = DTypeLightColour(dtype))
    blastColour = dc;
  style = LF_STEADY;
  reach = 1;
  if (shape == EL_AREA) {
    reach = targetFlash ? 1 : 2;
    if (blastColour == COL_FIRE) style = LF_FIRE;
    else if (blastColour == COL_ELEC) style = LF_ARC;
  }
  if (blastColour == COL_RAINBOW) style = LF_RAINBOW;
  gain = blastColour == COL_SONIC ? 0.6f : 1.0f;
  colour = LightEffectColour(blastColour);
  ramp = LightFlashRampFor(blastColour);
  if (shape == EL_BEAM) life = 300.0f;   /* beams rise fast and fade just as fast */
  if (lit) {
    id = LightFlashAdd(colour, style, gain, reach, ramp);
    LightFlashSetGrade(id, grade);
    LightFlashSetLife(id, life);
  }
}

EffectLight::~EffectLight() {
  End();
}

bool EffectLight::Sees(int16 x, int16 y) {
  Player *p = theGame->GetPlayer(0);
  if (!p || !p->m || p->m != map || map->isGenerating())
    return false;
  if (!map->InBounds(p->x, p->y) || !map->InBounds(x, y))
    return false;
  return map->LineOfSight(p->x, p->y, x, y, p);
}

bool EffectLight::Light(int16 x, int16 y) {
  if (id >= 0 && !ended && Sees(x, y)) {
    LightFlashCell(id, x, y);
    return true;
  }
  return false;
}

bool EffectLight::LightStruck(int16 x, int16 y) {
  if (!Light(x, y))
    return false;
  if (!glyphsOn) {
    glyphsOn = true;
    LightFlashGlyphs(id, true);
  }
  return true;
}

void EffectLight::MoveTo(int16 x, int16 y) {
  if (ended || !lit || LightFlashDisabled())
    return;
  /* An unseen square empties the area; a seen one refills it. */
  if (id >= 0)
    LightFlashRemove(id);
  id = Sees(x, y) ? LightFlashAdd(colour, style, gain, reach, ramp) : -1;
  if (id >= 0) {
    LightFlashSetGrade(id, grade);
    LightFlashSetLife(id, life);
    LightFlashSetClock(id, clockMs);   /* the new square is born now */
    LightFlashGlyphs(id, glyphsOn);
    LightFlashCell(id, x, y);
  }
}

/* inc-jw0hw: the whole flash takes the color of light row or palette color `col`. */
void EffectLight::Recolour(int16 col) {
  colour = LightEffectColour(col);
  ramp = LightFlashRampFor(col);
  style = col == COL_FIRE ? LF_FIRE : col == COL_ELEC ? LF_ARC : col == COL_RAINBOW ? LF_RAINBOW : LF_STEADY;
  gain = col == COL_SONIC ? 0.6f : 1.0f;
  if (id >= 0 && !ended)
    LightFlashRecolour(id, colour, style, gain, ramp);
}

void EffectLight::SetCellColour(int16 x, int16 y, int16 glyphColour) {
  if (id >= 0 && !ended)
    LightFlashCellColour(id, x, y, LightEffectColour(glyphColour));
}

/* inc-jw0hw: a standing light. Each square keeps its own color at full brightness and never ages (the rise's render path at its
   top level); the light's glyphs are the caller's, drawn in the overlay, so the light leaves every glyph's color alone. */
void EffectLight::Stand(bool keepFlicker) {
  standing = true;
  if (id >= 0 && !ended) {
    if (!keepFlicker)
      LightFlashSetStyle(id, LF_STEADY);
    LightFlashSetRise(id, true);
    LightFlashLevel(id, 1.0f);
  }
}

void EffectLight::ClearCells() {
  if (id >= 0 && !ended)
    LightFlashClearCells(id);
}

void EffectLight::Redraw() {
  Show();
}

void EffectLight::Show() {
  Player *p = theGame->GetPlayer(0);
  if (p) p->UpdateMap = 1;
  T1->ShowMap();
}

void EffectLight::Refresh() {
  glyphsOn = true;   /* the caller's glyphs are on screen from here until Tail() */
  if (id >= 0) LightFlashGlyphs(id, true);
  Show();
  if (EffectLightHook) EffectLightHook(EL_LIT);
}

void EffectLight::Hold(int16 ms) {
  if (EffectLightHook) EffectLightHook(EL_HOLD);
  Wait(ms);
}

/* The rise's first level: dim, not dark. A rise has no ramp: its squares show the flash's base color at the flash level. */
static const float RISE_START = 0.1f;

void EffectLight::Rise(int16 ms) {
  if (ms <= 0)
    return;
  risen = true;
  if (id >= 0) {
    LightFlashSetStyle(id, LF_STEADY);
    LightFlashSetRise(id, true);
    LightFlashLevel(id, RISE_START);
  }
  Refresh();
  if (EffectLightHook) EffectLightHook(EL_HOLD);
  const int steps = id < 0 ? 1 : (ms + 32) / 33;
  int done = 0;
  for (int i = 1; i <= steps; i++) {
    const int upto = ms * i / steps;
    clockMs += (float)(upto - done);
    if (id >= 0)
      LightFlashLevel(id, RISE_START + (1.0f - RISE_START) * (float)upto / (float)ms);
    T1->StopWatch((int16)(upto - done));
    if (ScriptLightTickHook && this == ScriptFx)
      ScriptLightTickHook(clockMs);
    done = upto;
  }
}

/* A wait of `ms` in steps of about 33 ms. Each step advances the effect clock by
   exactly its own length, so the ramp animates through the wait and the total is
   exactly `ms`. With no flash the wait is one StopWatch, as before. */
void EffectLight::Wait(int16 ms) {
  if (ms <= 0)
    return;
  if (EffectWaitHook) EffectWaitHook(ms);
  const int steps = id < 0 ? 1 : (ms + 32) / 33;
  int done = 0;
  for (int i = 1; i <= steps; i++) {
    const int upto = ms * i / steps;
    clockMs += (float)(upto - done);
    if (id >= 0)
      LightFlashSetClock(id, clockMs);
    T1->StopWatch((int16)(upto - done));
    if (ScriptLightTickHook && this == ScriptFx)
      ScriptLightTickHook(clockMs);
    done = upto;
  }
}

/* inc-jw0hw: this light's glyphs are gone but its squares keep cooling; Age() runs
   the cooling while another light plays, Tail() finishes it. */
void EffectLight::GlyphsOff() {
  glyphsOn = false;
  if (id >= 0 && !ended) LightFlashGlyphs(id, false);
}

void EffectLight::Age(int16 ms) {
  if (ms <= 0 || id < 0 || ended)
    return;
  clockMs += (float)ms;
  LightFlashSetClock(id, clockMs);
}

/* A globe's glyphs stay up for `glyphMs`; its light lives 1.25 times as long, so
   a long hold never shows black glyphs. */
void EffectLight::SetGlyphTime(int16 glyphMs) {
  const float want = 1.25f * (float)glyphMs;
  life = want > 900.0f ? want : 900.0f;
  if (id >= 0)
    LightFlashSetLife(id, life);
}

void EffectLight::SetLife(float ms) {
  if (ms <= 0.0f)
    return;
  life = ms;
  if (id >= 0)
    LightFlashSetLife(id, life);
}

/* The glyphs are gone: let each square finish cooling, 33 ms at a time. */
void EffectLight::Tail(bool keepGlyphs) {
  glyphsOn = keepGlyphs;
  if (id < 0 || ended)
    return;
  LightFlashGlyphs(id, keepGlyphs);
  Player *p = theGame->GetPlayer(0);
  if (p && p->Opt(OPT_ANIMATION) == 2)   /* None: no animation to finish */
    return;
  const int most = (int)(life / 33.0f) + 3;
  for (int i = 0; i < most && !LightFlashSpent(id); i++) {
    clockMs += 33.0f;
    LightFlashSetClock(id, clockMs);
    Show();
    T1->StopWatch(33);
  }
}

void EffectLight::End() {
  if (ended)
    return;
  ended = true;
  const bool had = id >= 0;
  if (had) {
    LightFlashRemove(id);
    id = -1;
    if (standing) {   /* End() may run inside a repaint: the caller repaints */
      Player *p = theGame->GetPlayer(0);
      if (p) p->UpdateMap = 1;
    } else if (risen) {   /* no dark frame between the rise and the next light */
      Player *p = theGame->GetPlayer(0);
      if (p) p->UpdateMap = 1;
    } else
      Show();
  }
  if (standing)   /* a standing light is no effect: no test hook hears it */
    return;
  if (target) {
    if (TargetFlashHook) TargetFlashHook(TF_END);
  } else if (EffectLightHook)
    EffectLightHook(EL_END);
}

void EffectLight::FlashStruck(Map *m, int16 blastColour, uint8 shape,
                              int16 dtype, TEffect *te, Thing *const *list,
                              int n) {
  Player *p = theGame->GetPlayer(0);
  if (!m || !list || n <= 0 || !p || p->Opt(OPT_ANIMATION) == 2)
    return;
  EffectLight fx(m, blastColour, shape, dtype, te, true);
  if (!fx.lit || fx.id < 0)
    return;
  int shown = 0;
  for (int i = 0; i < n; i++) {
    Thing *t = list[i];
    if (!t || !t->isCreature() || t->m != m || !fx.Sees(t->x, t->y))
      continue;
    fx.Light(t->x, t->y);
    shown++;
  }
  if (!shown)
    return;
  /* the struck creatures' glyphs follow the ramp for the whole flash */
  fx.glyphsOn = true;
  LightFlashGlyphs(fx.id, true);
  fx.Show();
  if (TargetFlashHook) TargetFlashHook(TF_LIT);
  fx.Tail(true);
  fx.End();
}

/* inc-jw0hw: the script light. A script lights squares it draws itself, holds,
   then ends the light; the engine owns one EffectLight for that span. */
static std::vector<Thing *> ScriptStruck;
struct ScriptSq { int16 x, y; Glyph g; };
static std::vector<ScriptSq> ScriptSquares;   /* lit squares and the glyph the script drew on each */
static bool ScriptOverlay = false;
static Map *ScriptMap = NULL;
static int16 ScriptColour = 0, ScriptDType = 0;
static TEffect *ScriptTe = NULL;
static bool ScriptColourSet = false;   /* the script named its light's color */

void EventInfo::LightBegin() {
  if (ScriptFx) {   /* a script that never ended its light */
    delete ScriptFx;
    ScriptFx = NULL;
  }
  ScriptStruck.clear();
  ScriptSquares.clear();
  ScriptColourSet = false;
  Player *p = theGame->GetPlayer(0);
  if (!EMap || !p || p->Opt(OPT_ANIMATION) == 2)
    return;
  ScriptMap = EMap;
  ScriptTe = eID ? TEFF(eID) : NULL;
  ScriptDType = DType;
  ScriptColour = EMagic ? EMagic->cval : 0;
  ScriptFx = new EffectLight(EMap, ScriptColour, EL_AREA, ScriptDType, ScriptTe);
}

void EventInfo::LightSquare(int16 x, int16 y, Glyph g) {
  if (ScriptFx && ScriptFx->Light(x, y)) {
    const ScriptSq q = { x, y, g };
    ScriptSquares.push_back(q);
  }
}

/* a repaint erases what the script put on the terminal: keep each lit square's glyph in the map overlay */
static bool ScriptGlyphsOn() {
  Overlay &o = ScriptMap->ov;
  const bool own = !o.Active;
  if (own) o.Activate();
  for (size_t i = 0; i < ScriptSquares.size(); i++)
    o.AddGlyph(ScriptSquares[i].x, ScriptSquares[i].y, ScriptSquares[i].g);
  return own;
}

/* inc-jw0hw: the light takes this color for the rest of the script's light. */
void EventInfo::LightColour(int16 col) {
  if (!ScriptFx || col <= 0)
    return;
  ScriptFx->Recolour(col);
  ScriptColourSet = true;
}

void EventInfo::LightHold(int16 ms) {
  if (!ScriptFx) {
    T1->StopWatch(ms);
    return;
  }
  ScriptOverlay = ScriptGlyphsOn();
  ScriptFx->Refresh();
  ScriptFx->Hold(ms);
  if (ScriptOverlay) ScriptMap->ov.DeActivate();
  ScriptOverlay = false;
}

/* inc-jw0hw: like LightHold, but the light climbs from dim to full over ms and
   LightEnd then ends it at once. Nothing lit (animation None, or an unseen
   square): no light and no wait. A palette cval colors the squares. */
void EventInfo::LightRise(int16 ms) {
  if (!ScriptFx || ScriptSquares.empty())
    return;
  const int16 cv = ScriptTe ? ScriptTe->ef.cval : 0;
  if (!ScriptColourSet && cv > 0 && cv < COL_FIRE)
    for (size_t i = 0; i < ScriptSquares.size(); i++)
      ScriptFx->SetCellColour(ScriptSquares[i].x, ScriptSquares[i].y, cv);
  ScriptOverlay = ScriptGlyphsOn();
  ScriptFx->Rise(ms);
  if (ScriptOverlay) ScriptMap->ov.DeActivate();
  ScriptOverlay = false;
}

void EventInfo::LightStruck(Thing *t) {
  if (ScriptFx && t)
    ScriptStruck.push_back(t);
}

void EventInfo::LightEnd() {
  if (ScriptFx) {
    EffectLight *fx = ScriptFx;
    ScriptFx = NULL;
    if (!fx->Risen())
      fx->Tail(false);   /* a rise ends at its peak: no cooling before the next light */
    fx->End();
    delete fx;
    if (!ScriptStruck.empty())
      EffectLight::FlashStruck(ScriptMap, ScriptColour, EL_AREA, ScriptDType,
                               ScriptTe, &ScriptStruck[0], (int)ScriptStruck.size());
    ScriptStruck.clear();
  }
  if (ScriptLightEndHook)
    ScriptLightEndHook();
}

/* inc-jw0hw: the script's standing pattern. The effect that calls it owns the pattern. */
void EventInfo::PatternStand(Thing *t, int16 radius, int16 col, int16 stati) {
  if (!col && EMagic)
    col = EMagic->cval;
  StandingPatternStart(t, radius, col, eID, stati);
}

void EventInfo::PatternStop(Thing *t) {
  StandingPatternStop(t, eID);
}

/* inc-jw0hw (Phase 5): motion. See inc/EffectLight.h. */
void (*MotionHook)(int start, int n, const int16 *xs, const int16 *ys, const uint8 *modes) = NULL;
struct MotionSq { int16 x, y; uint8 mode; };
static std::vector<MotionSq> MotionSet;   /* the cast's hold: a shake, or a dance for the hold only */
static std::vector<MotionSq> DanceSet;    /* the creatures that hold the Dancing status: set at each repaint, kept while the game waits */
static uint32 MotionSalt = 0;

static const MotionSq *MotionAt(int i)
  {
    if (i < 0) return NULL;
    if (i < (int)MotionSet.size()) return &MotionSet[i];
    i -= (int)MotionSet.size();
    return i < (int)DanceSet.size() ? &DanceSet[i] : NULL;
  }

static uint32 MotionHash(uint32 a, uint32 b, uint32 c)
  {
    uint32 h = a * 2654435761u ^ (b + 0x9e3779b9u) * 2246822519u ^ (c + 0x85ebca6bu) * 3266489917u;
    h ^= h >> 15; h *= 2246822519u; h ^= h >> 13; h *= 3266489917u; h ^= h >> 16;
    return h;
  }

void MotionStart(const int16 *xs, const int16 *ys, const uint8 *modes, int n)
  {
    Player *pl = theGame->GetPlayer(0);
    MotionSet.clear();
    if (!pl || pl->Opt(OPT_ANIMATION) == 2)
      n = 0;
    for (int i = 0; i < n; i++) {
      MotionSq q = { xs[i], ys[i], modes[i] };
      MotionSet.push_back(q);
      }
    for (size_t d = 0; d < DanceSet.size(); ) {   /* a dancer in the hold moves once, as the hold's square */
      bool dup = false;
      for (size_t h = 0; h < MotionSet.size(); h++)
        if (MotionSet[h].x == DanceSet[d].x && MotionSet[h].y == DanceSet[d].y) dup = true;
      if (dup) DanceSet.erase(DanceSet.begin() + d); else d++;
      }
    MotionSalt = (uint32)cosmetic_random(32000) * 65537u + (uint32)cosmetic_random(32000);
    if (MotionHook && n)
      MotionHook(1, n, xs, ys, modes);
  }

void MotionStop()
  {
    if (MotionSet.empty())
      return;
    if (MotionHook) {
      std::vector<int16> xs, ys; std::vector<uint8> md;
      for (size_t i = 0; i < MotionSet.size(); i++) {
        xs.push_back(MotionSet[i].x); ys.push_back(MotionSet[i].y); md.push_back(MotionSet[i].mode);
        }
      MotionHook(0, (int)MotionSet.size(), &xs[0], &ys[0], &md[0]);
      }
    MotionSet.clear();
    TermMotionClear();
  }

bool MotionActive() { return !MotionSet.empty() || !DanceSet.empty(); }
int  MotionCount() { return (int)(MotionSet.size() + DanceSet.size()); }

bool MotionSquare(int i, int16 &x, int16 &y, uint8 &mode)
  {
    const MotionSq *q = MotionAt(i);
    if (!q)
      return false;
    x = q->x; y = q->y; mode = q->mode;
    return true;
  }

void MotionDancers(const int16 *xs, const int16 *ys, int n)
  {
    Player *pl = theGame->GetPlayer(0);
    std::vector<MotionSq> nw;
    if (pl && pl->Opt(OPT_ANIMATION) != 2)
      for (int i = 0; i < n; i++) {
        bool dup = false;
        for (size_t h = 0; h < MotionSet.size(); h++)
          if (MotionSet[h].x == xs[i] && MotionSet[h].y == ys[i]) dup = true;
        if (!dup) { MotionSq q = { xs[i], ys[i], MOT_DANCE }; nw.push_back(q); }
        }
    bool same = nw.size() == DanceSet.size();
    for (size_t i = 0; same && i < nw.size(); i++)
      same = nw[i].x == DanceSet[i].x && nw[i].y == DanceSet[i].y;
    if (same)
      return;
    const bool had = !DanceSet.empty();
    if (!had && MotionSet.empty())
      MotionSalt = (uint32)cosmetic_random(32000) * 65537u + (uint32)cosmetic_random(32000);
    DanceSet = nw;
    if (had && DanceSet.empty() && MotionSet.empty())
      TermMotionClear();   /* the last dancer stopped: repaint its square */
  }

/* A dance moves in periods of 3 frames (100 ms). Each period has a raw pick of 4 mirror states (none, left-right, upside-down,
   both); in some groups of 4 periods the states instead step in order, which reads as a spin. Two periods in a row never both
   hold no mirror, so a dancer shows a mirror at least every other period. */
static int DanceState(uint32 salt, int i, uint32 period)
  {
    const uint32 grp = period / 4;
    const bool spin = (MotionHash(salt, (uint32)i, grp + 7777u) & 1u) != 0;
    const uint32 h0 = MotionHash(salt, (uint32)i, period);
    const int raw = spin ? (int)((MotionHash(salt, (uint32)i, grp + 1234u) + period) & 3u) : (int)(h0 & 3u);
    if (raw != 0 || period == 0)
      return raw;
    const uint32 pp = period - 1, pg = pp / 4;
    const bool pspin = (MotionHash(salt, (uint32)i, pg + 7777u) & 1u) != 0;
    const int praw = pspin ? (int)((MotionHash(salt, (uint32)i, pg + 1234u) + pp) & 3u) : (int)(MotionHash(salt, (uint32)i, pp) & 3u);
    return praw == 0 ? 1 + (int)((h0 >> 8) % 3u) : 0;
  }

MotionXf MotionPick(uint32 frame, int i)
  {
    MotionXf xf = { 0, 0, false, false };
    const MotionSq *q = MotionAt(i);
    if (!q)
      return xf;
    const uint32 h = MotionHash(MotionSalt, (uint32)i, frame);
    const int mag = 1 + (int)((h >> 3) % 3u);          /* 1..3 pixels */
    const int dir = (int)(h % 8u);                      /* one of 8 directions */
    static const int DX[8] = { 1, 1, 0, -1, -1, -1, 0, 1 }, DY[8] = { 0, 1, 1, 1, 0, -1, -1, -1 };
    xf.dx = DX[dir] * mag; xf.dy = DY[dir] * mag;
    if (q->mode & MOT_DANCE) {
      const int st = DanceState(MotionSalt, i, frame / 3u);
      xf.flipX = (st & 1) != 0; xf.flipY = (st & 2) != 0;
      }
    return xf;
  }

void MotionTransform(const uint32 *src, uint32 *dst, int cw, int ch, const MotionXf &xf, uint32 bg)
  {
    for (int y = 0; y < ch; y++)
      for (int x = 0; x < cw; x++) {
        int sx = x - xf.dx, sy = y - xf.dy;   /* the pixel of the moved image that lands on (x, y) */
        if (sx < 0 || sx >= cw || sy < 0 || sy >= ch) {
          dst[y * cw + x] = bg;
          continue;
          }
        if (xf.flipX) sx = cw - 1 - sx;
        if (xf.flipY) sy = ch - 1 - sy;
        dst[y * cw + x] = src[sy * cw + sx];
        }
  }
