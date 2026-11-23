/* See the Incursion LICENSE file for copyright information.

     This file contains the class definition for Magic.
*/


/* inc-az4d2: one square of a ball's fill. kind 0 is a taken (counted, drawn)
   square, 1 a solid terrain square the fill touched, 2 a square holding a
   solid feature (a closed door). ring is its distance band (rounded true distance from the center). */
struct BallSquare
  {
    int16 x, y, ring;
    int8 kind;
  };

class Magic
	{
    public:
      // inc-az4d2: the squares a ball strikes, in band order. Draws and
      // strikes nothing. count is the volume: the most taken squares,
      // center included.
      static int16 BallDiscCount(int r);
      static int16 BallVolume(EventInfo &e, int16 lval);
      static void BallFill(Map &m, int16 cx, int16 cy, int16 count,
          std::vector<BallSquare> &out);
      // inc-epzc0: the squares a cone strikes, in band order. Nothing is
      // drawn or struck. The aim line runs (sx,sy) to (tx,ty). ConeDiscCount
      // is the cone's square count for a whole length L and aim vector
      // (ax,ay); ConeVolume snaps Enlarge/Focus to such a count.
      static int16 ConeDiscCount(int L, int ax, int ay);
      static int16 ConeVolume(EventInfo &e, int16 lval, int ax = 1, int ay = 0);
      static void ConeFill(Map &m, int16 sx, int16 sy, int16 tx, int16 ty,
          int16 count, std::vector<BallSquare> &out);
      // The Area-Effect Functions
      // ww: folded into one, now ...
      /*
      EvReturn ABolt(EventInfo &e);
      EvReturn ABall(EventInfo &e);
      EvReturn ABeam(EventInfo &e);
      */
      EvReturn ABallBeamBolt(EventInfo &e);

      // used by the monster AI ...
      // manageOverlay (inc-30ps rework, item 7): true (default) toggles the
      // map Overlay itself, as this function always has; MagicStrike's own
      // reentrant call (inside ABallBeamBolt's already-active overlay,
      // mid-animation) passes false so it does not wipe the glyph buffer
      // the outer call is still drawing into. This function draws no
      // glyphs of its own, so skipping the toggle changes nothing else.
      void PredictVictimsOfBallBeamBolt(EventInfo &e,
          bool isBeam, bool isBall, bool isChain, Creature * victim[],
          int16 & numVic, bool manageOverlay = true);


      EvReturn ATouch(EventInfo &e);
      EvReturn AGlobe(EventInfo &e);
      EvReturn AField(EventInfo &e);
      EvReturn ABarrier(EventInfo &e);

      bool isTarget(EventInfo &e, Thing *t);      
      void CalcEffect(EventInfo &e);
      EvReturn MagicEvent(EventInfo &e);
      EvReturn MagicStrike(EventInfo &e);
      EvReturn MagicHit(EventInfo &e);
      EvReturn MagicXY(EventInfo &e,int16 x,int16 y);

      // The Effect Archetypes
      EvReturn Blast(EventInfo &e);
      EvReturn Inflict(EventInfo &e);
      EvReturn Grant(EventInfo &e);
      EvReturn Drain(EventInfo &e);
      EvReturn Terraform(EventInfo &e, bool squareGiven = false);
      EvReturn Travel(EventInfo &e);
      EvReturn Identify(EventInfo &e);
      EvReturn Illusion(EventInfo &e);
      EvReturn Summon(EventInfo &e);
      EvReturn Animate(EventInfo &e);
      EvReturn Creation(EventInfo &e);
      EvReturn Bless(EventInfo &e);
      EvReturn Charm(EventInfo &e);
      EvReturn Poison(EventInfo &e);
      EvReturn TimeStop(EventInfo &e);
      EvReturn Slaying(EventInfo &e);
      EvReturn Telepathy(EventInfo &e);
      EvReturn Detect(EventInfo &e);
      EvReturn Reveal(EventInfo &e);
      EvReturn Override(EventInfo &e);

      EvReturn Vision(EventInfo &e);
      EvReturn Dispel(EventInfo &e);
      EvReturn EConstruct(EventInfo &e);
      EvReturn Banish(EventInfo &e);
      EvReturn Castigate(EventInfo &e);
      EvReturn Healing(EventInfo &e);
      EvReturn Raise(EventInfo &e);
      EvReturn Menu(EventInfo &e);
      EvReturn Cancel(EventInfo &e);
      EvReturn Wonder(EventInfo &e);
      EvReturn ManyThings(EventInfo &e);
      EvReturn Polymorph(EventInfo &e);
      EvReturn Genocide(EventInfo &e);
      EvReturn LevGain(EventInfo &e);
      EvReturn Holding(EventInfo &e);
      EvReturn Warning(EventInfo &e);
      EvReturn Digging(EventInfo &e);
      EvReturn Earthquake(EventInfo &e);
      EvReturn Cure(EventInfo &e);
      EvReturn Restore(EventInfo &e);
      EvReturn Shield(EventInfo &e);

			//General Effects
	};

/* inc-z1ba: the +4 disbelief bonus a watcher earns by identifying an illusion
   with Spellcraft at cast time. GrantIllusionSpotted marks every watcher in the
   current cast's identifier list against this illusion; the terrain form marks
   them against the illusory-terrain field's creator and spell. */
void GrantIllusionSpotted(Thing *illusion, rID eID);
void GrantIllusionSpottedTerrain(Creature *creator, rID eID);

/* inc-z1ba: test-only disbelief probe entry points (src/DisbeliefProbe.cpp). */
void DisbeliefProbeThing(Creature *watcher, Thing *illusion, int16 baseDC,
    bool spotted, int16 usedDC, bool pass, bool removed);
void DisbeliefProbeTerrain(Creature *watcher, int16 baseDC, bool spotted,
    int16 usedDC, bool pass);
void DisbeliefProbeForce(Creature *watcher, int16 baseDC, bool spotted,
    int16 usedDC, bool pass);
void DisbeliefProbeIdentify(Creature *watcher, Creature *caster, rID eID,
    bool identified);

extern int16 ZapX[];
extern int16 ZapY[];
extern Map*  ZapMap;
extern uint16 ZapImage[];

