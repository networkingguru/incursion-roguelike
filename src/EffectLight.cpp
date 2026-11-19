/* inc-jw0hw: the light an animated effect casts while it shows. See
   inc/EffectLight.h. */
#include "Incursion.h"

void (*EffectLightHook)(int phase) = NULL;
void (*TargetFlashHook)(int phase) = NULL;

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
    case AD_NECR: case AD_DREX: case AD_DRST: case AD_DRCO: return COL_NECRO;
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
  if (!te)
    return d;
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
    : map(m), id(-1), ended(false), lit(true), target(targetFlash),
      clockMs(0.0f), life(900.0f), glyphsOn(false) {
  if (te) {
    const EffectLightDecision d = EffectLightDecide(te, dtype);
    lit = d.lit;
    if (d.colour)
      blastColour = d.colour;
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

void EffectLight::Light(int16 x, int16 y) {
  if (id >= 0 && !ended && Sees(x, y))
    LightFlashCell(id, x, y);
}

void EffectLight::MoveTo(int16 x, int16 y) {
  if (ended || !lit || LightFlashDisabled())
    return;
  /* An unseen square empties the area; a seen one refills it. */
  if (id >= 0)
    LightFlashRemove(id);
  id = Sees(x, y) ? LightFlashAdd(colour, style, gain, reach, ramp) : -1;
  if (id >= 0) {
    LightFlashSetLife(id, life);
    LightFlashSetClock(id, clockMs);   /* the new square is born now */
    LightFlashGlyphs(id, glyphsOn);
    LightFlashCell(id, x, y);
  }
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

/* A wait of `ms` in steps of about 33 ms. Each step advances the effect clock by
   exactly its own length, so the ramp animates through the wait and the total is
   exactly `ms`. With no flash the wait is one StopWatch, as before. */
void EffectLight::Wait(int16 ms) {
  if (ms <= 0)
    return;
  const int steps = id < 0 ? 1 : (ms + 32) / 33;
  int done = 0;
  for (int i = 1; i <= steps; i++) {
    const int upto = ms * i / steps;
    clockMs += (float)(upto - done);
    if (id >= 0)
      LightFlashSetClock(id, clockMs);
    T1->StopWatch((int16)(upto - done));
    done = upto;
  }
}

/* A globe's glyphs stay up for `glyphMs`; its light lives 1.25 times as long, so
   a long hold never shows black glyphs. */
void EffectLight::SetGlyphTime(int16 glyphMs) {
  const float want = 1.25f * (float)glyphMs;
  life = want > 900.0f ? want : 900.0f;
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
    Show();
  }
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
