/* EFFECTLIGHT.H -- inc-jw0hw. One animated effect's light: a flash in the light
   map (inc/Light.h) that spell code lights, holds, cools and ends. The effect
   keeps its own clock: every wait it issues advances the clock by that wait. The light
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
/* inc-epzc0: test hook, called with each positive wait the effect clock takes. */
extern void (*EffectWaitHook)(int ms);

/* inc-jw0hw (Phase 2): test hook for the pieces an effect draws. kind says which, x,y the square, g the glyph with its color
   (0 when none). ES_TRAVEL: a projectile starts to fly (x,y the caster). ES_STEP: it shows on a square. ES_PILLAR: a falling
   pillar shows on a square. ES_DART: a trap's dart shows on a square. ES_THROWN: a thrown item shows on a square.
   ES_BURST: a burst glyph shows on a square. */
// family: effect-step-kind internal
enum { ES_TRAVEL = 0, ES_STEP = 1, ES_PILLAR = 2, ES_DART = 3, ES_THROWN = 4, ES_BURST = 5 };
// end family: effect-step-kind
extern void (*EffectStepHook)(int kind, int16 x, int16 y, Glyph g);

/* inc-jw0hw: test hook for the target flash (FlashStruck). Called at TF_LIT
   once the struck squares show at age 0, and at TF_END after the flash is
   removed. The target flash never calls EffectLightHook. */
// family: target-flash-phase internal
enum { TF_LIT = 0, TF_END = 1 };
// end family: target-flash-phase
extern void (*TargetFlashHook)(int phase);

/* inc-jw0hw: test hook for the script light (EventInfo::Light*). Called with
   the effect clock after each step of its hold. */
extern void (*ScriptLightTickHook)(float clockMs);
/* Called when EventInfo::LightEnd returns, whether or not a light ran. */
extern void (*ScriptLightEndHook)();

/* inc-jw0hw: where a trap's dart comes from: the flight's squares (source first, the square next to the victim last), 1 to 3,
   from the nearest wall. Returns the count. dxs, dys (may be NULL) get the flight's direction. */
int DartFlightPlan(Map *m, int16 vx, int16 vy, int16 *px, int16 *py, int max_n, int16 *dxs, int16 *dys);

/* inc-jw0hw: whether an effect glows, and the light color row (COL_* or a
   plain palette color, 0 for none). te NULL: lit, no color. */
struct EffectLightDecision { bool lit; int16 colour; int grade; };   /* grade 0..3: extra lights above the basic grade (EF_GRADE_n) */
EffectLightDecision EffectLightDecide(TEffect *te, int16 dtype);

struct EffectLight {
  /* dtype: the effect's damage type (AD_*), or 0. With te, EffectLightDecide
     decides whether the effect glows and its color; the blast color is the
     fallback. Without te, the type's color wins. Glyph colors are the caller's. */
  EffectLight(Map *m, int16 blastColour, uint8 shape, int16 dtype = 0,
              TEffect *te = NULL, bool targetFlash = false);
  ~EffectLight();
  bool Light(int16 x, int16 y);   /* only if the player has line of sight to it; true when lit */
  bool Sees(int16 x, int16 y);    /* the player has line of sight to the square on this light's map */
  void MoveTo(int16 x, int16 y);  /* missile: the area becomes this square */
  float Clock() const { return clockMs; }   /* the effect clock, ms */
  /* inc-jw0hw: a lit square takes the light color of palette color `glyphColour`;
     its age on the ramp keeps running. A square not lit by Light() is ignored. */
  void SetCellColour(int16 x, int16 y, int16 glyphColour);
  /* inc-jw0hw: a target flash lights one struck creature's square as a wave reaches it; its glyph follows the ramp. */
  bool LightStruck(int16 x, int16 y);
  void Recolour(int16 col);       /* the whole flash takes light color `col` (a COL_* row or palette color) */
  void Redraw();                  /* repaint the map without a hook call */
  void Refresh();                 /* light, vision, memory and overlay */
  void Hold(int16 ms);
  /* inc-jw0hw: a rise. The light climbs from dim to full over ms on the effect
     clock, steady and without aging, so it stays at its peak and never starts
     the cooling ramp. A light that has risen ends at once, with no repaint:
     the next effect's light shows in the same frame. */
  void Rise(int16 ms);
  bool Risen() const { return risen; }
  float Life() const { return life; }       /* a square's light life, ms */
  void GlyphsOff();               /* glyphs gone, light keeps cooling: Age() it, then Tail() */
  void Age(int16 ms);             /* advance this light's clock alone: it cools while another light plays */
  void Wait(int16 ms);            /* a wait that advances the effect clock */
  void SetGlyphTime(int16 glyphMs); /* a globe: its light outlives its glyphs */
  void SetLife(float ms);         /* a square's light life, ms (the default is 900) */
  void Tail(bool keepGlyphs = false);                    /* glyphs gone: cool every square, then call End() */
  void End();
  /* inc-jw0hw: the last stage of a glowing effect: light the square of every
     creature in list (a reach of 1 square), cool it on the effect's own clock
     and end it. Call it before any hit resolves. Lights nothing for an unlit
     effect, under OPT_ANIMATION None, or for a square the player cannot see. */
  static void FlashStruck(Map *m, int16 blastColour, uint8 shape, int16 dtype,
                          TEffect *te, Thing *const *list, int n);
  /* inc-jw0hw: a standing light for a standing pattern (see StandingPatternStart). It holds each lit square at the peak of its own
     color and never cools. Stand() makes it so; ClearCells() drops every square, to be lit again with Light(). A standing light
     ends without a repaint: the caller repaints, because End() may run inside a repaint. */
  void Stand(bool keepFlicker = false);   /* keepFlicker: the style the effect chose (fire flickers) stays; the light still holds its peak */
  void ClearCells();
private:
  void Show();
  LightRGB colour;
  uint8 style;
  float gain;
  int16 reach;
  int grade;   /* extra lights over the same squares, from EffectLightDecide */
  Map *map;
  int32 id;
  bool ended;
  bool lit;
  bool target;   /* a target flash: it calls TargetFlashHook, not EffectLightHook */
  uint8 ramp;
  float clockMs, life;   /* the effect clock and a square's light life, ms */
  bool glyphsOn;
  bool risen;
  bool standing;
};

/* inc-jw0hw: a standing pattern. Random glyphs in random colors, with the light of each square following its glyph's color,
   drawn on the squares within `radius` of an anchor creature that the player sees, and kept changing (a new pick each 100 ms)
   until it stops. It is general: a script starts it on any creature and stops it, its colors come from `col` (a COL_* set, a
   palette color, or 0 and COL_RAINBOW for the full pool), and nothing in it names a spell. It stops by itself when the anchor
   dies or leaves the player's map, when OPT_ANIMATION is None, or when `stati` is not 0 and the anchor no longer holds that
   status from effect `owner`. Only cosmetic_random() chooses, so no gameplay roll moves. Returns false when nothing started. */
/* inc-jw0hw (Phase 5): a standing wall light. A wall of terrain whose effect glows (EffectLightDecide) lights each of its squares,
   at the effect's color and flicker, for as long as the terrain stands on that square. It rides the standing light of a pattern
   (Stand, ClearCells, Light, redone at each repaint in StandingPatternPrepare). It ends when no wall square is left, when the
   player leaves the map, or under OPT_ANIMATION None. Nothing is saved: on entering a map (SetMap, which a load calls too) the next
   repaint finds the squares that hold the terrain of a glowing barrier effect and starts the light again. Returns false when
   nothing started. */
bool StandingWallStart(Map *m, rID terrain, const int16 *xs, const int16 *ys, int n, TEffect *te);
int  StandingWallCount();
void StandingWallStopAll();

bool StandingPatternStart(Thing *anchor, int16 radius, int16 col, rID owner, int16 stati);
void StandingPatternStop(Thing *anchor, rID owner);   /* every pattern the anchor holds for owner (0: for any owner) */
void StandingPatternStopAll();
int  StandingPatternCount();
/* The squares the patterns drew at the last repaint: their glyph and palette color. Returns how many (at most max). */
int  StandingPatternSquares(int16 *x, int16 *y, Glyph *g, int16 *col, int max);
/* ShowMap calls Prepare before it builds the light map (so the light is in it) and Done after it paints. */
void StandingPatternPrepare(Map *m);
void StandingPatternDone(Map *m);
/* True when g is the glyph a pattern draws at (x, y): the terminal then keeps it over a field's glyph (a big creature's body). */
bool StandingPatternDrawsAt(int16 x, int16 y, Glyph g);
/* A terminal's wait loop calls Frame with its clock in ms: it drops a pattern that must stop and picks again each 100 ms.
   True when the map needs a repaint. Repick picks again at once (a terminal with no timed redraw calls it once a repaint). */
bool StandingPatternFrame(uint32 nowMs);
void StandingPatternRepick();

/* inc-jw0hw (Phase 5): motion. The SDL build moves the pixels of some squares for a while: a shake (each glyph moves 1 to 3 pixels
   in a new random direction every frame, inside its own square) and a dance (a shake, with mirrors and spins). The text terminal
   draws none. Only the drawing moves; the game's rolls and results do not. MotionStart names the squares and MotionStop ends
   them. A frame is 33 ms of the terminal's clock (the recorder's virtual clock when it records). A frame's picks come from a hash
   of the start's salt, the frame and the square: no game RNG, and the same frame always gives the same picks. */
// family: motion-mode internal
enum { MOT_SHAKE = 1, MOT_DANCE = 2 };
// end family: motion-mode
struct MotionXf { int dx, dy; bool flipX, flipY; };   /* dx, dy: pixels, each within 1..3 either way; flipX mirrors left-right, flipY upside-down */
/* Test hook, NULL unless a probe sets it: called by MotionStart (start 1) and MotionStop (start 0) with the squares and modes. */
extern void (*MotionHook)(int start, int n, const int16 *xs, const int16 *ys, const uint8 *modes);
void MotionStart(const int16 *xs, const int16 *ys, const uint8 *modes, int n);
void MotionStop();
/* The squares of the creatures that hold the Dancing status, found at each repaint (StandingPatternPrepare). They dance (mode
   MOT_DANCE) for as long as the status lasts, beside the cast's hold set, and are counted in MotionCount and MotionSquare. */
void MotionDancers(const int16 *xs, const int16 *ys, int n);
bool MotionActive();
int  MotionCount();
bool MotionSquare(int i, int16 &x, int16 &y, uint8 &mode);
/* The transform of square i (0 <= i < MotionCount()) on frame `frame`. */
MotionXf MotionPick(uint32 frame, int i);
/* The pixels of one cell after xf: dst gets src moved by (dx, dy) and mirrored, and the strip the move uncovers takes `bg`.
   src and dst hold cw * ch pixels each and MUST NOT overlap. Nothing outside dst[0 .. cw*ch) is written. */
void MotionTransform(const uint32 *src, uint32 *dst, int cw, int ch, const MotionXf &xf, uint32 bg);
/* Spores: a spreader blasts them in every direction, like arrows, each drawn with the glyph of its flight's direction (src/Magic.cpp). */
void SporeBlast(Map &m, Thing *from, Thing *victim);
/* The SDL terminal clears what it drew when the motion stops. Posix: no-op. */
void TermMotionClear();

#endif
