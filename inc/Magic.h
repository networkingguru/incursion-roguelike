/* See the Incursion LICENSE file for copyright information.

     This file contains the class definition for Magic.
*/


class Magic
	{
    public:
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
      EvReturn Terraform(EventInfo &e);
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
extern int16 ZapX[];
extern int16 ZapY[];
extern Map*  ZapMap;
extern uint16 ZapImage[];

