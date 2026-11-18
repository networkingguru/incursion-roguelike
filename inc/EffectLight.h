/* EFFECTLIGHT.H -- inc-jw0hw. One animated effect's light: a flash in the light
   map (inc/Light.h) that spell code lights, holds, fades and ends. The light
   MUST end (End()) before any hit of the effect is resolved: vision and hiding
   read the light map. The destructor only covers early exits. */

#ifndef EFFECTLIGHT_H
#define EFFECTLIGHT_H

#include "Light.h"

// family: effect-light-phase internal
enum { EL_LIT = 0, EL_HOLD = 1, EL_END = 2 };
// end family: effect-light-phase

// family: effect-light-shape internal
enum { EL_AREA = 0, EL_BEAM = 1, EL_MISSILE = 2 };
// end family: effect-light-shape

/* Test hook, NULL unless a probe sets it. Called at EL_LIT after each Refresh,
   at EL_HOLD before the hold, and at EL_END after the flash is removed. */
extern void (*EffectLightHook)(int phase);

/* inc-jw0hw: whether an effect glows, and the light color row (COL_* or a
   plain palette color, 0 for none). te NULL: lit, no color. */
struct EffectLightDecision { bool lit; int16 colour; };
EffectLightDecision EffectLightDecide(TEffect *te, int16 dtype);

struct EffectLight {
  /* dtype: the effect's damage type (AD_*), or 0. With te, EffectLightDecide
     decides whether the effect glows and its color; the blast color is the
     fallback. Without te, the type's color wins. Glyph colors are the caller's. */
  EffectLight(Map *m, int16 blastColour, uint8 shape, int16 dtype = 0,
              TEffect *te = NULL);
  ~EffectLight();
  void Light(int16 x, int16 y);   /* only if the player has line of sight to it */
  void MoveTo(int16 x, int16 y);  /* missile: the area becomes this square */
  void Refresh();                 /* light, vision, memory and overlay */
  void Hold(int16 ms);
  void Ramp(int16 ms, float from, float to);
  void End();
private:
  bool Sees(int16 x, int16 y);
  void Show();
  LightRGB colour;
  uint8 style;
  float gain;
  int16 reach;
  Map *map;
  int32 id;
  bool ended;
  bool lit;
};

#endif
