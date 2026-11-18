/* inc-jw0hw: the light an animated effect casts while it shows. See
   inc/EffectLight.h. */
#include "Incursion.h"

void (*EffectLightHook)(int phase) = NULL;

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
                         TEffect *te)
    : map(m), id(-1), ended(false), lit(true) {
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
    reach = 2;
    if (blastColour == COL_FIRE) style = LF_FIRE;
    else if (blastColour == COL_ELEC) style = LF_ARC;
  }
  if (blastColour == COL_RAINBOW) style = LF_RAINBOW;
  gain = blastColour == COL_SONIC ? 0.6f : 1.0f;
  colour = LightEffectColour(blastColour);
  if (lit)
    id = LightFlashAdd(colour, style, gain, reach);
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
  id = Sees(x, y) ? LightFlashAdd(colour, style, gain, reach) : -1;
  if (id >= 0)
    LightFlashCell(id, x, y);
}

void EffectLight::Show() {
  Player *p = theGame->GetPlayer(0);
  if (p) p->UpdateMap = 1;
  T1->ShowMap();
}

void EffectLight::Refresh() {
  Show();
  if (EffectLightHook) EffectLightHook(EL_LIT);
}

void EffectLight::Hold(int16 ms) {
  if (EffectLightHook) EffectLightHook(EL_HOLD);
  T1->StopWatch(ms);
}

void EffectLight::Ramp(int16 ms, float from, float to) {
  if (id < 0)
    return;
  const int steps = ms / 33 > 0 ? ms / 33 : 1;
  for (int i = 1; i < steps; i++) {
    LightFlashLevel(id, from + (to - from) * (float)i / (float)steps);
    T1->StopWatch(33);
  }
  LightFlashLevel(id, to);
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
  if (EffectLightHook) EffectLightHook(EL_END);
}
