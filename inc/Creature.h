/* See the Incursion LICENSE file for copyright information.

     This file contains class definitions for Creature,
   Character, Player and Monster. 
*/

#include <time.h>

struct ActionInfo 
  {
    int8 Act;
    int32 Val;
    Thing *Tar;
    int8 Pri;
  };

struct EffectInfo
  {
    rID   eID;
    Item* Source; /* hObj or CA_XXX constant */
    uint16 Rating;
    uint32 Purpose; 
    #ifdef DEBUG
    const char*EffectName;
    #endif

  };

struct YuseCommand
  {
    int16 Event;
    const char *Verb, *Verbed;
    int16 QTarget;
    const char* TMsg;
    int16 QItem1;
    const char* I1Msg;
    int16 QItem2;
    const char* I2Msg;
    uint32 Flags;
  };

struct SkillInfoStruct
  {
    uint8 sk;   // SK_SPOT
    const char * name; 
    bool  imp;  // implemented?  
    bool  active;
    const char * desc; 
    int8  attr1, attr2; // A_INT, A_DEX
    bool  take_min;     // take min of those attrs, or max? 
    int8   armour_penalty; 
  } ; 

struct AbilityInfoStruct 
  {
    uint8 ab;
    const char * name; 
    const char * desc; 
    // ww: we might put a "cost" or "balance factor" here at some point
  } ;

struct AlignmentInfoStruct
  {
    const char * name;
    const char * desc;
    uint16 align;
  } ; 
  
struct LearnableSpell
  {
    rID   spID;
    uint8 Type;
    uint8 Level;
  } ;

/* ww: Feat Structure Information */
#define FP_MAX_DISJUNCTS        3
#define FP_MAX_CONJUNCTS        5

// Feat Conjunct Elements
#define FP_ALWAYS               0
#define FP_FEAT                 1       
#define FP_ABILITY              2
#define FP_BAB                  3
#define FP_SKILL                4
#define FP_CR                   5
#define FP_ATTR                 6
#define FP_CASTER_LEVEL         7
#define FP_WEP_SKILL            8       // HasStati(WEP_SKILL,X)
#define FP_NOT_PROF             9       // !(Proficiencies & X)
#define FP_PROF                 10      //  (Proficiencies & X)
#define FP_ATTACK               11
#define FP_MTYPE                12

// Feat Flags
#define FF_UNIMP                0x0001
#define FF_META                 0x0002 // metamagic feat
#define FF_MULTIPLE             0x0004 // like Skill Focus, School Focus
#define FF_MONSTER              0x0008 // monster feat
#define FF_MIGHTY               0x0010
#define FF_AGILE                0x0020
#define FF_TOUGH                0x0040
#define FF_SMART                0x0080
#define FF_INTUITIVE            0x0100
#define FF_COMMANDING           0x0200
#define FF_WARRIOR              0x0400
#define FF_RANGER               0x0800
#define FF_WIZARD               0x1000
#define FF_CHANNEL              0x2000
#define FF_PUNCH                0x4000
#define FF_KICK                 0x8000

struct FeatConjunct { 
  int32     elt;            // element  -- e.g., BAB,       IAttr
  int32     arg;            // argument -- e.g., S_MELEE,   A_STR
  int32     val;            // value    -- e.g., 5,         13
} ;

typedef struct FeatPrereq {
  struct FeatDisjunct {
    struct FeatConjunct And[FP_MAX_CONJUNCTS]; 
  } Or[FP_MAX_DISJUNCTS]; 
} FeatPrereq ;  

struct FeatInfoStruct {
  int16 feat;
  int32 flags; 
  const char * name;
  const char * desc;
  FeatPrereq pre;
} ;

class Weapon;
class Item;

struct Counterspeller
  {
    Creature *cr;
    int16 Check;
  };

/* Mana Values:

   mMana    -- total calculated *inherent* mana
   uMana    -- mana spent on normal spells and such
   hMana    -- mana "held" that does not regenerate
   tMana()  -- total mana, including A_MAN adjustments
   cMana()  -- mana currently available for use
   nhMana() -- total *unheld* mana pool

   kcMana() -- *known* current mana
   ktMana() -- *known* total mana

   tMana() == nhMana() + hMana == cMana() + hMana + uMana 

*/

inline int16 XCRtoCR(int32 XCR);

class Creature: public Thing, public Magic
  {
    ARCHIVE_CLASS(Creature,Thing,r)
      /* v1 tags 256-383, in the declaration order of the members below.
         FIELD_OBJ's v0 branch IS ts.Serialize(r) -- the call this line
         replaces -- so the v0 path does exactly what it did before, and only
         v1 routes into TargetSystem::FieldsV1 (src/Target.cpp). */
      FIELD_OBJ(256, ts);
      FIELD_RID(257, mID);
      FIELD_RID(258, tmID);
      FIELD_I16(259, PartyID);
      FIELD_I16(260, cHP);
      FIELD_I16(261, mHP);
      FIELD_I16(262, Subdual);
      FIELD_I16(263, cFP);
      FIELD_I32(264, uMana);
      FIELD_I32(265, mMana);
      FIELD_I32(266, hMana);
      FIELD_I32(267, ManaPulse);
      FIELD_I8 (268, concentUsed);
      FIELD_ARRAY(269, Attr, sizeof(int16), ATTR_LAST);
      /* Dir is `typedef signed char` (inc/Defines.h:55), so it is one byte
         and needs no staging temporary. */
      FIELD_I8 (270, LastMoveDir);
      FIELD_I8 (271, AoO);
      FIELD_I8 (272, FFCount);
      FIELD_I8 (273, HideVal);
      FIELD_I16(274, StateFlags);
      FIELD_I8 (275, AttrDeath);
      /* The ten perception precalcs below are STORED, not FIELD_SKIPped.
         They are derived state, and the rule is to skip derived state that
         the load path rebuilds -- but the load path rebuilds it for the
         PLAYER only: Game::LoadGame calls CalcValues() and CalcVision() on
         oPlayer(p[0]) and on nothing else (src/Registry.cpp:1364-1365).
         Nothing recalculates a monster's, so skipping them would load every
         monster in the game blind, deaf and scentless until something else
         happened to call CalcValues() on it. */
      FIELD_U8 (276, TremorRange);
      FIELD_U8 (277, SightRange);
      FIELD_U8 (278, LightRange);
      FIELD_U8 (279, BlindRange);
      FIELD_U8 (280, InfraRange);
      FIELD_U8 (281, PercepRange);
      FIELD_U8 (282, TelepRange);
      FIELD_U8 (283, ScentRange);
      FIELD_U8 (284, ShadowRange);
      FIELD_U8 (285, NatureSight);
    END_ARCHIVE

	  public:
      TargetSystem ts; 
	    rID mID, tmID; int16 PartyID;
	    int16 cHP, mHP, Subdual, cFP;
	    int32 uMana, mMana, hMana, ManaPulse;

	    int8  concentUsed;
      /* ww: Attr[A_MOV], for example, can easily wrap around if you're
       * charging or sprinting and have some magical items or a mount:
       * int8 is just not big enough */ 
      int16  Attr[ATTR_LAST]; 
      Dir LastMoveDir;
      int8 AoO, FFCount, HideVal;
	    int16 StateFlags; int8 AttrDeath;
	    int8 AttackMode();
	    Dice &DmgVal(int16 mode, bool is_large);
      void SetImage();
      static int8 AttrAdj[ATTR_LAST][BONUS_LAST];
      static Item *meleeWep, *offhandWep, 
                    *missileWep, *thrownWep, *myShield;
      /* These precalcs are used to speed up Perceives() */
      uint8 TremorRange, SightRange, LightRange, BlindRange,
           InfraRange, PercepRange, TelepRange,
           ScentRange, ShadowRange,
           NatureSight; // ww: also used
    public:
      /* General Stuff */
		  Creature(rID mID,int16 _Type);
		  int32 cMana() { return max(0,(mMana+(GetAttr(A_MAN)*5)-(uMana+hMana))); }
	    int32 tMana() { return mMana + GetAttr(A_MAN)*5; }
      void  LoseMana(int32 amt, bool hold=false)
        { if (hold)
            hMana += amt;
          else
            uMana = min(tMana() - hMana,uMana + amt); }
      void GainMana(int32 amt)
        { uMana = max(0,uMana - amt); } 
      bool hasMana(int32 amt)
        { return cMana() > amt; }
      int32 nhMana()
        { return max(0,tMana() - hMana); }
      void GainStatiFromBody(rID _mID);
      void GainStatiFromTemplate(rID _tID, bool turn_on);
      /* Use of an attribute can lead to gains. */
      virtual void Exercise(int16 at, int16 amt, int16 col, int16 cap) { }
      virtual void Abuse(int16 at, int16 amt) {
          Exercise(at, -amt, 0, 0);
      }
      virtual void RecalcStaffSpells() { }
      virtual int16 LevelAs(rID clID) { return 0; }
      virtual int16 GetStaffFatigueCost(rID xID);
      virtual int16 getSocialMod(Creature *cr, bool inc_str);
      virtual bool  hasAccessToSpell(rID spID);
      virtual bool  canChargeInDir(Dir d);
      virtual int16 getFavEnemyBonus(Creature *cr);
      virtual void AddJournalEntry(const char* s) { }
      virtual String & Describe(Player *p);
      virtual void Dump();
      virtual String & Name(int16 Flags = 0);
      int16 GetAttr(int8 at) { return Attr[at]; }
      virtual int16 IAttr(int8 at) {
          return at > A_CON ? TMON(tmID)->Attr[at] : TMON(tmID)->Attr[at];
      }
      virtual int16 KnownAttr(int8 at) { return Attr[at]; }
      virtual int16 getDef() {
          if (StateFlags & MS_STILL_CAST) {
              CalcValues();
              return Attr[A_CDEF] + max(0, AttrAdj[A_DEF][BONUS_WEAPON]);
          }
          return (StateFlags & MS_CASTING) ? Attr[A_CDEF] : Attr[A_DEF];
      }
      bool isBoosted(int8 at);
      bool isDrained(int8 at);
      bool isBlind() {
          return HasMFlag(M_BLIND) || HasStati(BLIND);
      } 

      /* yields a number like 130% or 90% */
      int32 MoveAttr(int from_x, int from_y);

      int32 MoveTimeout(int from_x, int from_y) {
        int32 Mov = MoveAttr(from_x,from_y);
        int32 normal_timeout = max(1,1000 / max(Mov,1));
        return normal_timeout;
      } 

      // WW: this counts everything except being off-guard, surprised by
      // unseen attackers, etc. Those are checked inside fight.cpp
      bool noDexDefense();

      EvReturn TryToDestroyThing(Thing *f); // ww: kick down doors, etc.
      void DoAttrDeath();
		  EvReturn Event(EventInfo &e);
		  virtual void QPrint() {}
      virtual void IPrint(const char * msg, ...); 
      virtual const char* Him() { 
        if (HasMFlag(M_NEUTER)) return "It";
        return StateFlags & MS_FEMALE ? "Her" : "Him"; }
      virtual const char* him() { 
        if (HasMFlag(M_NEUTER)) return "it";
        return StateFlags & MS_FEMALE ? "her" : "him"; }
      virtual const char* His() { 
        if (HasMFlag(M_NEUTER)) return "Its";
        return StateFlags & MS_FEMALE ? "Her" : "His"; }
      virtual const char* his() { 
        if (HasMFlag(M_NEUTER)) return "its";
        return StateFlags & MS_FEMALE ? "her" : "his"; }
      virtual const char* He() {
        if (HasMFlag(M_NEUTER)) return "It";
        return StateFlags & MS_FEMALE ? "She" : "He"; }
      virtual const char* he() {
        if (HasMFlag(M_NEUTER)) return "it";
        return StateFlags & MS_FEMALE ? "she" : "he"; }
		  virtual void DoTurn();
		  virtual void DiseasePulse(bool force, bool rest);
      String & BonusBreakdown(int8 at, int16 maxlen=250);
      virtual void ChooseAction()=0;
      virtual void AccessTime(Item *it);
      virtual void ExtendedAction();
      virtual void HaltAction(const char *why, bool force_halt=true);
      virtual int16 ChallengeRating(bool allow_neg = false);
      virtual void GainXP(uint32 XP) { return; }
      virtual int32 TotalXP() { return 0; }
      virtual void KillXP(Creature*kill, int16 percent=100);
      virtual void AlignedAct(uint16 type, int16 mag,const char*reason=NULL,
                                                     Creature *victim=NULL);
      virtual uint32 GetXP() { return 0; }
      virtual void ThiefXP(rID regID);
      virtual uint32 XPDrained() { return 0; }
      virtual void RestoreXP(uint32 xp) { return; }
      uint16 Perceives(Thing*, bool assertLOS);
      uint16 Perceives(Thing* t) { return Perceives(t, false); } 
      virtual bool isThreatened(bool perceived_only=true);
      virtual rID getGod() { return 0; }
      virtual const char* ActingVerb();

      bool PerceivesField(int x, int y, Field *f) {
        if (!this || !this->m || !this->m->InBounds(x,y) ||
            !(this->m->At(x,y).Visibility & VI_VISIBLE) ||
            !f->inArea(x,y))
          return false; 
        bool need_to_see = (f->FType & (FI_SIZE|FI_SHADOW|FI_ITERRAIN)) != 0;
        if (!need_to_see || 
            !f->Creator || this->Perceives(oThing(f->Creator))) 
          return true;
        else 
          return false; 
      } 

      bool   XPerceives(Thing *t)
        { return (Perceives(t) & (~(PER_SHADOW|PER_SCENT|PER_DETECT))) != 0; }
      virtual bool isShadowShape() { return TMON(mID)->Size >= SZ_SMALL; }
      bool isBeside(Thing *t, int extra_dist = 0);
      bool isAerial();
      bool isInvisTo(Creature*);
      bool isSmallRace()
        { return TMON(tmID)->Size <= SZ_SMALL &&
                 TMON(mID)->Size <= SZ_SMALL &&
                 TMON(tmID)->HasFlag(M_HUMANOID) &&
                 TMON(mID)->HasFlag(M_HUMANOID); }
      virtual bool yn(const char* msg,bool def=true)
        { return def; }
      virtual int8 ChoicePrompt(const char*msg, const char*choices, char def=0, 
                     int8 col1=BROWN,int8 col2=YELLOW,bool preprompt=true)
        { if (def == 0) // ww: pass 0 for 'random default'
            return choices[random(strlen(choices))];
          else
            return def; } 
      virtual bool canTalk(Creature *to=NULL);
      int32 ChargeBonus();
      uint32 getArmourType(bool count_shield);
      virtual bool HasInnateSpell(rID spID);
      virtual void LoseMoneyTo(int32 amt, Creature *cr);
      virtual bool doSocialSanity(int16 ev, Creature *cr);
      virtual int32 getTotalMoney();
      virtual Item* ConsumeRope(uint32 feet);

      /* Inventory and Stati */
      uint32 ArmourType();
      uint8 Encumbrance();
      int32 Weight(bool includeEquipment);
      int32 MaxPress();
      void  wieldSoulblade(Item *blade);
      virtual uint16 getSoulbladeConfig() { return 0xFFFF; }
      int16 getAlignment();
      
      public:
      int ListAttacks(TAttack * buf, int numEltsInBuf);
      bool TwoFistFighting();
      bool MartialTwoWeapon();
      /* Monsters are built by hand rather than by buying feats, so whatever a
         monster is written as having simply works. Character overrides this. */
      virtual bool TwoWeaponFeatWorks() { return true; }

      bool     HasAttk(int8 typ) { return GetAttk(typ) != NULL; }
                                  
      TAttack* GetAttk(int8 typ);
      bool  HasMFlag(int16 fl);
      rID   Race_mID();

      bool InherentCreatureReach();

      virtual void StatiOn(Status s);
      virtual void StatiOff(Status s, bool elapsed = false);
      virtual void StatiMessage(int16 n,int16 val,bool ending);

      /* Trait Management Functions */
      void AddBonus(int8 btype, int8 attr, int16 bonus);
      void StackBonus(int8 btype, int8 attr, int16 bonus);
      virtual void CalcValues(bool KnownOnly=false, Item *thrown=NULL);
      virtual void CalcHP();
      virtual void CalcSP() { }
      int16 Mod(int8 a);
      int16 Mod2(int8 a);
      virtual int16 KMod(int8 a);
      virtual int16 KMod2(int8 a);

      virtual bool HasFeat(int16 n, bool inh=false, bool list=false);
      virtual bool IHasFeat(int16 n) { return HasFeat(n,true); }
      virtual bool HasAbility(int16 n, bool inh=false);
      virtual bool IHasAbility(int16 n) { return HasAbility(n,true); }
      int16 SkillAttr(int16 sk);

      virtual int16 AbilityLevel(int16 n); 
      virtual bool  HasSkill(int16 sk, bool check_allies=false);
      virtual bool HasSkillKit(int16 sk);
      virtual int8 SkillKitMod(int16 sk);
      virtual int16 ISkillLevel(int16 n);
      virtual int16 SkillLevel(int16 n);
      virtual int16 ConcentBuffer() {
          int16 cc = SkillLevel(SK_CONCENT);
          return max(cc-5,0);
      }
      virtual int8 WepSkill(rID wep, bool ignore_str=false);
      int8 WepSkill(Item * it) ;
      bool SavingThrow(int16 type, int16 DC, uint32 Subtype=0,
                         int16 cmod=0, const char*cmod_desc=NULL);
      virtual bool SkillCheck(int16 sk, int16 DC, bool show = true,
                                 int16 mod1=0, const char *mod1Str=NULL,
                                 int16 mod2=0, const char *mod2Str=NULL);
      virtual Creature * MostSkilledAlly(int16 sk);
      virtual void TrainAs(rID cID) { }
      virtual int16 HungerState();
      virtual bool LoseFatigue(int16 amt, bool avoid=false);
      virtual void Planeshift();
      virtual void Shapeshift(rID mD, bool merge, Item*PolySource=NULL);
      virtual bool CanAddTemplate(rID tID);
      virtual void AddTemplate(rID tID);
      virtual void Multiply(int16 a, bool b, bool msg=true);
      virtual void DoEngulf(Creature *engulfer);
      virtual void DropEngulfed(Creature *droponly = NULL);
      virtual void RippleCheck(int16 range);
      virtual int16 GetPower(int16);
      
      virtual int16 GetBAB(int16 mode);
      /* NatIgnored and WornIgnored are how many points of armour this attack
         has found a way past, counted separately for natural armour and for a
         worn suit because the two sit behind different Coverage values. See
         Fight.cpp. Both default to 0, which is "nothing was penetrated". */
      int16 ResistLevel(int16 DType, int16 NatIgnored = 0, int16 WornIgnored = 0);
      virtual int16 WeaponSaveDC(Item *wp, int16 at);



      /* Spell and Innate Ability Functions */
      virtual int16 SpellRating(rID eID,uint32 mm=0,bool perceived=false);
      virtual int16 getSpellDC(rID spID, bool isTrick, bool isHeight);
      virtual int16 getSpellMana(rID spID, uint32 MM, int16 *specMod2);
      virtual uint32 getStoredMM(rID spID);
      virtual uint16 getSpellFlags(rID spID) // horrid kludge used for counterspells
         { return CasterLev() >= SAL(TEFF(spID)->Level) ? SP_KNOWN : 0; }
      virtual int16 CasterLev()
        { return max(ChallengeRating(),1); }
      virtual uint32 MMFeats(uint32 sp) { return 0; }
      virtual void getBuffInfo(int16 *pBuffCount, int16 *pManaCost, rID **pBuffList);
      virtual bool isSpecialistIn(uint32 School);
      virtual int16 GetAgeCatagory();
      /* Functions For Handling Actions */
		  virtual EvReturn NAttack(EventInfo &e); //Natural Attack Sequence
      virtual EvReturn WAttack(EventInfo &e); //Melee/Char. Attack
      virtual EvReturn RAttack(EventInfo &e); //Ranged/Throwing Attack
      virtual EvReturn SAttack(EventInfo &e); //Special Attack
		  virtual EvReturn OAttack(EventInfo &e); //Attack of Opportunity
      bool canMakeAoO(Creature *victim); // not stunned, sleeping, etc. 
		  
      virtual EvReturn PreStrike(EventInfo &e);
      virtual EvReturn Strike(EventInfo &e);
      virtual bool     ManeuverCheck(EventInfo &e);     
		  virtual EvReturn Hit(EventInfo &e);
		  virtual EvReturn Miss(EventInfo &e);
		  virtual EvReturn BullRush(EventInfo &e);
			virtual EvReturn HandleNegate(EventInfo &e);
      virtual EvReturn Damage(EventInfo &e);
      virtual EvReturn PDamage(EventInfo &e);
		  virtual EvReturn Death(EventInfo &e);
		  virtual EvReturn AttackMsg(EventInfo &e);
		  virtual void     UnGrapple();
		  virtual void     PlaceSomewhereSafe();

		  virtual EvReturn PickUp(EventInfo &e) = 0;
		  virtual EvReturn Drop(EventInfo &e) = 0;
      virtual EvReturn Wield(EventInfo &e) = 0;
      virtual EvReturn TakeOff(EventInfo &e) = 0;
      virtual void     DropAll() = 0;
		  virtual Item*    InSlot(int8 slot, bool effective=false) = 0;
		  virtual Item*    EInSlot(int8 slot) { return InSlot(slot,true); }
      Thing** GetEnumeratedInv();
      virtual Item*    GetInv(bool first) = 0;
      Item* FirstInv() { return GetInv(true); }
      Item* NextInv()  { return GetInv(false); }
      Item* RandInv();
      Item* RandGoodInv(int32 minval);
      virtual Item*    FindBestItemOrCreate(rID iID);
      virtual void GainItem(Item *it, bool starting=false)=0;
      virtual EvReturn HandleVerb(EventInfo &e);
      virtual EvReturn Walk(EventInfo &e);
      virtual EvReturn PreTalk(EventInfo &e);
      virtual EvReturn Barter(EventInfo &e);
      virtual EvReturn Cow(EventInfo &e);
      virtual EvReturn Dismiss(EventInfo &e);
      virtual EvReturn Distract(EventInfo &e);
      virtual EvReturn Enlist(EventInfo &e);
      virtual EvReturn FastTalk(EventInfo &e);
      virtual EvReturn Greet(EventInfo &e);
      virtual EvReturn Order(EventInfo &e);
      virtual EvReturn OfferTerms(EventInfo &e);
      virtual EvReturn Quell(EventInfo &e);
      virtual EvReturn Request(EventInfo &e);
      virtual EvReturn Surrender(EventInfo &e);
      virtual EvReturn Taunt(EventInfo &e);     
      virtual EvReturn Cast(EventInfo &e);
      virtual EvReturn Invoke(EventInfo &e);
      virtual EvReturn Counterspell (EventInfo &e, Counterspeller *cs);
 			virtual EvReturn Hide(EventInfo &e);
      virtual EvReturn Turn(EventInfo &e);
      virtual EvReturn Search(EventInfo &e);
      virtual EvReturn DonDisguise(EventInfo &e);
      virtual EvReturn Research(EventInfo &e);
      virtual EvReturn PickPocket(EventInfo &e);
      virtual EvReturn Phase(EventInfo &e);
      virtual EvReturn Ascend(EventInfo &e);
      virtual EvReturn Descend(EventInfo &e);
      virtual void Devour(Corpse *c);
      virtual void DevourMonster(Monster *c);
      virtual EvReturn Mount(EventInfo &e);
      virtual EvReturn Dismount(EventInfo &e);
      virtual EvReturn FieldOn(EventInfo &e);
			virtual EvReturn FieldOff(EventInfo &e);
      virtual EvReturn LoadCrossbow(EventInfo &e);
      virtual EvReturn Dig(EventInfo &e);
      virtual void     SetupDig(Dir d);
      virtual void MakeNoise(int16 radius);
      virtual void IdentByTrial(Item *it,int16 Quality=0) {}
      virtual bool ItemPrereq(rID xID, int16 ReqLevel, int16 TrickDC);
      virtual void GainInherentBonus(int16 at, int16 mag, bool msg=true);
      virtual void GetHungrier(int16 amt);
      virtual int16 getBestKnowSkill(Creature *cr, bool isCombat);

      void Reveal(bool intentional = false);
      void Awaken(int32 sleepType = -1);
      bool UseLimitedFA();
      void ProvokeAoO(Creature* c = NULL, bool from_move=false);
      void DoGazeAttack();
      void DoProxAttack();
      void TerrainEffects();
      void ClimbFall();
      void FocusCheck(Creature *killer);
      virtual int16 onPlane();
      virtual bool isHostileTo(Creature*c);
      virtual bool isFriendlyTo(Creature*c);
      virtual bool isHostileToPartyOf(Creature *c);
      bool isLedBy(Creature*c) { return (ts.getLeader() == c); }
      Creature * getLeader() { return ts.getLeader(); }
      Creature * getLeaderOrFirst() {
        Creature *cr; hObj h; int16 i;
        if (cr = ts.getLeader())
          return cr;
        if (!m)
          return this;
        h = 60000000L;
        MapIterate(m,cr,i)
          if (cr->isCreature() && !cr->isDead())
            if (cr->isFriendlyTo(this))
              if (cr->myHandle < h)
                h = cr->myHandle;
        return h == 60000000L ? this : oCreature(h);
        }
      virtual int16 getComparativeStrengthMod(Creature *cr);
      int16 StunAttackDC() 
        { return 10 + AbilityLevel(CA_STUN_ATTACK)/2
                    + Mod(A_WIS) + (HasFeat(FT_BREAK_THE_BREATH) ? 2 : 0); }
      virtual int16 worstTrouble();
      virtual int16* getTroubles();    
      virtual void IdentifyMon();
      virtual void IdentifyTemp(rID tID);
      virtual void Initialize(bool in_play = false) {}
      virtual void Transgress(rID gID, int16 mag, bool doWrath=false, const char*reason=NULL) { }
      virtual void gainFavour(rID gID, int16 amt, bool advance=false, bool stack=true) { }
      bool isMType(int32 MType);
      bool isPMType(int32 MType, Creature *cr);

      bool okWildShape(int16 lev, rID mID, rID tID);
      bool okAnimalComp(int16 lev, rID mID, rID tID);
      bool okBondedMount(int16 lev, rID mID, rID tID);

      bool isFlatFooted()
        { return FFCount > min(5,10+Mod(A_WIS)); }
      bool isFlanking(Creature *c);
      int8 BestHDType(); // ww: includes all types, templates, etc. 
      virtual int16 SpellDmgBonus(rID eID);
      Term * ShowCombatNumbers();  // ww: players, druid animals ...

      // ww: 'e' can be null, blocked_by is set in some cases when
      // 'false' is returned. 
      bool canMoveThrough(EventInfo *e, int16 tx, int16 ty, 
          Thing * &blocked_by);
      // ww: This convenience function is used by Walk() and also
      // MoveField() for big creatures. Basically, you can move through
      // on-solid squares in general, but if you are out of phase you can
      // move through a lot and if you are Earthmeld you can move through
      // stone solid things, etc. 
      
      int8 rateMeleeWeapon();
      int8 rateRangedWeapon();
      Item * getPrimaryMelee();
      Item * getPrimaryRanged();
      
  };

class Character: public Creature
  {
    friend class Term;
    friend class TextTerm;
    friend class GUITerm;
    friend class Creature;
    friend class Item;
    friend class Weapon;
    friend class Magic;
    friend class VMachine;
    friend class Player;
    protected:
	    hObj Inv[NUM_SLOTS];
      hObj defMelee, defRanged, defAmmo, defOffhand;
      int16 BAttr[7], KAttr[ATTR_LAST]; //Base Attributes
      int8 SkillRanks[SK_LASTSKILL];
      uint16 Feats[(FT_LAST/8)+1];
      uint8 Abilities[CA_LAST];
      uint16 SpentSP[6], BonusSP[6], TotalSP[6];       
      uint8 TurnTypes[4],TurnLevels[4];
      uint8 FavTypes[12],FavLevels[12];
      uint8 IntStudy[STUDY_LAST];
      int16 FocusWCount, FocusSCount, ExoticCount;
      int16 aStoryPluses, tStoryPluses;
      uint8 RageCount; int32 xpTicks;
      uint32 Personality; int16 polyTicks;
      int16 alignGE, alignLC; 
      int32 LastRest; int16 fracFatigue;
      bool isFallenPaladin;
	    int8 Level[3]; 
      int8 hpRolls[3][MAX_CHAR_LEVEL];
      int8 manaRolls[3][MAX_CHAR_LEVEL];

      int8 SaveBonus[16];
      int16 GainAttr[7][15];
      int8 NotifiedLevel;
    public:
      rID ClassID[6];
      rID RaceID, GodID;
    protected:
      hObj Mount;
	    uint32 XP, XP_Drained;
      uint8 SpellsLearned[10];
      uint8 SpellSlots[10];
      uint8 BonusSlots[10];
      uint16 RecentSpells[10];
      uint16 RecentSkills[5];
      uint16 RecentItems[5];
      uint16 Spells[MAX_SPELLS+1];
      rID    Tattoos[10];
      int16  resChance;
      
      /* Religion Stuff */
      int16 FavourLev[MAX_GODS];
      int32 TempFavour[MAX_GODS];
      int16 Anger[MAX_GODS];
      int32 SacVals[MAX_GODS][MAX_SAC_CATS + 2];
      int16 FavPenalty[MAX_GODS];
      int16 PrayerTimeout[MAX_GODS];
      int16 AngerThisTurn[MAX_GODS];
      int32 lastPulse[MAX_GODS];
      uint16 godFlags[MAX_GODS];
      
    public:
      uint16 desiredAlign;
      uint32 Proficiencies;
      /* General Stuff */
	    Character(rID mID,int16 _Type);
      virtual String & Describe(Player* p);
      virtual void Dump();
      virtual void CalcValues(bool KnownOnly=false, Item *thrown=NULL);
      uint32 SpellKnown(int16 spNum) { return Spells[spNum]; }
      virtual void RecalcStaffSpells();
      virtual void RecalcCraftFormulas();
      int32 kcMana() { return max(0,(mMana+(KAttr[A_MAN]*5)-(uMana+hMana))); }
	    int32 ktMana() { return mMana + KAttr[A_MAN]*5; }
	    int16 UnspentSP(int16 cl) { return max(0,TotalSP[cl] - SpentSP[cl]); }
	    int16 UnspentCSP(rID clID) { for (int16 i=0;i!=6;i++)
	                                  if (clID == ClassID[i])
	                                    return UnspentSP(i);
	                                 return 0; }
      virtual int16 ChallengeRating()
        {
          // ww: taking the Creature challenge rating ends up having
          // undesired effects with wild shaped druids
          return // max(Creature::ChallengeRating()-1,0) + 
            ((int16)(Level[0]+Level[1]+Level[2]));
        }
	    EvReturn Event(EventInfo &ev);

      /* Inventory & Stati */
		  virtual EvReturn PickUp(EventInfo &e);
		  virtual EvReturn Drop(EventInfo &e);
      virtual EvReturn Wield(EventInfo &e);
      virtual EvReturn TakeOff(EventInfo &e);
		  virtual Item*    InSlot(int8 slot, bool eff=false);
		  void     SetInvSlot(int16 sl, Thing *it) { Inv[sl] = it ? it->myHandle : 0; }
      virtual void     DropAll();
      virtual Item*    GetInv(bool first);
      virtual void     Exchange();

      bool Swap(int8 Slot);
      virtual void GainItem(Item *it, bool starting=false);
      virtual void TrainAs(rID cID);
      /* Trait Management Functions */
      public:
      void AddAbilities(rID,int16);
      void CorrectStackedAbilities();
      virtual void AdvanceLevel()=0;
      virtual void GainFeat(int16 list, int32 param=0)=0;
      virtual void GainAbility(int16 ab, uint32 pa, rID sourceID,int16 statiSource)=0;
      bool FeatPrereq(int16 n, bool fail_if_feat_requires_a_feat = false);
      virtual bool HasFeat(int16 n, bool inh=false, bool list=false);
      virtual bool TwoWeaponFeatWorks();
      virtual void GainXP(uint32);
      virtual int32 TotalXP() { return XP; }
      virtual void KillXP(Creature*,int16 percent=100);
      virtual void LoseXP(uint32);
      virtual int16 KnownAttr(int8 a) { return KAttr[a]; }
      uint32 NextLevXP();
      virtual uint32 XPDrained() { return XP_Drained; }
      virtual uint32 GetXP() { return XP; }
      virtual void RestoreXP(uint32 xp)
        { if (xp > XP_Drained) 
                xp = XP_Drained;
          XP_Drained -= xp; 
          XP += xp; 
          // ww: must remove all ADJUST_DMG A_AID statis, otherwise we 
          // continue to suffer "neglev" penalties forever!
          if (XP_Drained == 0) 
             RemoveStati(ADJUST_DMG,-1,A_AID);
        }
      int16 XPPenalty();
      void DrainXP(int32 xp);
      void PaladinFall();
      void PaladinAtone();
      void SwapAttributes(int16 n);
      int32 TotalExploreFavour();
      
      public:
      virtual int16 IAttr(int8 a);
      int16 MaxRanks(int16 sk);
      uint16 getEligableStudies();
      virtual bool  HasSkill(int16 sk, bool check_allies=false);
      virtual int8 WepSkill(rID wep, bool ignore_str=false);
      int8 WepSkill(Item * it) ;
      virtual int16 LevelAs(rID cID);
      rID GetRaceID() { return RaceID; }
      rID GetClassID(int16 cl) { return ClassID[max(0,min(cl,2))]; }
      int16 TotalLevel() { return Level[0] + Level[1] + Level[2]; }
      virtual int16 CasterLev();
      int16 PsionicLev() { return Abilities[CA_PSIONICS]; }
      virtual int16 KMod(int8 a);
      virtual int16 KMod2(int8 a);
      virtual void Exercise(int16 at, int16 amt, int16 col, int16 cap);
      /* Spell and Innate Ability Functions */
      virtual int16 SpellRating(rID eID, uint32 mm=0,bool perceived=false);
      virtual uint16 getSpellFlags(rID spID) 
                       { return Spells[theGame->SpellNum(spID)]; }
      virtual void   setSpellFlags(rID spID, uint16 fl) 
                       { Spells[theGame->SpellNum(spID)] = fl; }
      virtual int16  GetSkillRanks(int16 sk)
                       { return SkillRanks[sk]; }
      virtual int16  GetBAB(int16 mode);

      /* Functions for Performing Actions */
      //virtual EvReturn AttackMsg(EventInfo&e);
      void UseSkill(uint8 sk);
      void UseFeat(uint16 ft);
      void UseAbility(uint8 ab,int16 pa);
      bool DisarmTrap(Trap * tr, bool active); 
      void LegendIdent(Item *it);
      void RestEncounterChance(int16 maxDist, int16 &posseID, Creature * &in_sight, int16 &Chance);
      void GainBonusSkills(rID cID, int16 sp);
      virtual void CalcSP();
      virtual EvReturn CraftItem(int16 abil);
      LearnableSpell* CalcSpellAccess();
      void UpdateTattoos();

      /* Religion Stuff */
      EvReturn PrePray(EventInfo &e);
      EvReturn Pray(EventInfo &e);
      EvReturn Sacrifice(EventInfo &e);
      EvReturn Convert(EventInfo &e);
      EvReturn ConvertAltar(EventInfo &e);
      EvReturn Insight(EventInfo &e);
      EvReturn Jealousy(EventInfo &e);
      EvReturn GiveAid(EventInfo &e);
      EvReturn Retribution(EventInfo &e);
      EvReturn IBlessing(EventInfo &e);
      EvReturn GodDeflect(EventInfo &e);
      
      void GrantSymbol(rID gID);
      void GodMessage(rID gID, int16 msgnum,...);
      int32 calcFavour(rID gID);
      void  gainedFavour(rID gID);
      virtual void gainFavour(rID gID, int32 amt, bool advance=false, bool stack=true);
      virtual rID getGod() { return GodID; }
      
      EvReturn AlignedAct(EventInfo &e);
      EvReturn ChangeAlign(EventInfo &e);
      virtual void AlignedAct(uint16 type, int16 mag, const char *reason=NULL,
                                                     Creature *victim=NULL);
      virtual void Transgress(rID gID, int16 mag, bool doWrath=false, const char*reason=NULL);
      void Forsake();
      void lowerAnger(rID gID, int16 amt);
      int16 getAnger(rID gID)
        { return Anger[theGame->GodNum(gID)]; }
      bool isWorthyOf(rID gID, bool penanceOK);
        
      uint16 getGodFlags(rID gID)
        { return godFlags[theGame->GodNum(gID)]; }
      void   setGodFlags(rID gID, uint16 fl)
        { godFlags[theGame->GodNum(gID)] |= fl; }
      void resetGodFlags(rID gID, uint16 fl)
        { godFlags[theGame->GodNum(gID)] &= ~fl; }
      int16 getGodLevel(rID gID)
        { return FavourLev[theGame->GodNum(gID)]; }
      int16 getGodAnger(rID gID) /* HACKFIX */
        { int16 ang = Anger[theGame->GodNum(gID)];
          ang -= (int16)TGOD(gID)->GetConst(TOLERANCE_VAL);
          return max(0,ang); }
      

    ARCHIVE_CLASS(Character,Creature,r)
      /* v1 tags 384-511, in the declaration order of the members above
         (inc/Creature.h, `hObj Inv[NUM_SLOTS]` down to `uint32
         Proficiencies`). Widths measured on arm64/LP64, 2026-08-24; the
         static_asserts fail the build if a compiler or an upstream edit
         moves one, because the coverage pin row in src/SaveV1.cpp lists
         this class's padding by absolute offset.

         Handle arrays and scalar arrays travel as K_ARRAY. rID arrays do
         NOT: a K_ARRAY payload is raw bytes and would bypass the name
         table, which is the one thing the schema exists to prevent (spec,
         "Why"). Each rID array is therefore an embed of per-element
         FIELD_RID lines.

         ponytail: several arrays here are indexed BY resource position and
         not by rID -- Spells[] by theGame->SpellNum(), and the nine
         MAX_GODS religion arrays by theGame->GodNum(). Their contents
         travel correctly, but the meaning of a slot moves if the module is
         recompiled with a spell or a god added or removed. Ceiling: favour
         and spell knowledge follow the wrong god or spell after such a
         recompile -- never a crash, and never a wrong ClassID/RaceID/GodID,
         which are real rIDs and are named. Upgrade path: write these as
         rows keyed through the name table, the way the spec's "resource
         memory segment" section already requires for MonMem/EffMem. */
      static_assert(sizeof(Character) == 8552,
                    "Character's coverage pin row pads assume this");
      static_assert(sizeof(hObj) == 4, "handles are one 32-bit word");
      static_assert(sizeof(rID) == 4, "rIDs are one 32-bit word");
      static_assert(sizeof(bool) == 1, "isFallenPaladin travels as K_U8");
      int i;
      FIELD_ARRAY(384, Inv, sizeof(hObj), NUM_SLOTS);
      FIELD_H  (385, defMelee);
      FIELD_H  (386, defRanged);
      FIELD_H  (387, defAmmo);
      FIELD_H  (388, defOffhand);
      FIELD_ARRAY(389, BAttr, sizeof(int16), 7);
      FIELD_ARRAY(390, KAttr, sizeof(int16), ATTR_LAST);
      FIELD_ARRAY(391, SkillRanks, sizeof(int8), SK_LASTSKILL);
      FIELD_ARRAY(392, Feats, sizeof(uint16), (FT_LAST/8)+1);
      FIELD_ARRAY(393, Abilities, sizeof(uint8), CA_LAST);
      FIELD_ARRAY(394, SpentSP, sizeof(uint16), 6);
      FIELD_ARRAY(395, BonusSP, sizeof(uint16), 6);
      FIELD_ARRAY(396, TotalSP, sizeof(uint16), 6);
      FIELD_ARRAY(397, TurnTypes, sizeof(uint8), 4);
      FIELD_ARRAY(398, TurnLevels, sizeof(uint8), 4);
      FIELD_ARRAY(399, FavTypes, sizeof(uint8), 12);
      FIELD_ARRAY(400, FavLevels, sizeof(uint8), 12);
      FIELD_ARRAY(401, IntStudy, sizeof(uint8), STUDY_LAST);
      FIELD_I16(402, FocusWCount);
      FIELD_I16(403, FocusSCount);
      FIELD_I16(404, ExoticCount);
      FIELD_I16(405, aStoryPluses);
      FIELD_I16(406, tStoryPluses);
      FIELD_U8 (407, RageCount);
      FIELD_I32(408, xpTicks);
      FIELD_U32(409, Personality);
      FIELD_I16(410, polyTicks);
      FIELD_I16(411, alignGE);
      FIELD_I16(412, alignLC);
      FIELD_I32(413, LastRest);
      FIELD_I16(414, fracFatigue);
      /* Staged through a uint8, as TargetSystem::shouldRetarget is
         (src/Target.cpp): a byte off a crafted file is any of 256 values,
         and a bool holding one of the other 254 is undefined behaviour the
         moment anything reads it. The restore is guarded by V1Active()
         because this body also runs on the v0 path, where FIELD_U8 is a
         no-op, `fallen` would still be 0, and the raw dump already carried
         the real byte. */
      uint8 fallen = 0;
      if (isSave)
        fallen = isFallenPaladin ? 1 : 0;
      FIELD_U8 (415, fallen);
      FIELD_SKIP(isFallenPaladin);   /* travels as `fallen` above */
      FIELD_ARRAY(416, Level, sizeof(int8), 3);
      FIELD_ARRAY(417, hpRolls, sizeof(int8), 3 * MAX_CHAR_LEVEL);
      FIELD_ARRAY(418, manaRolls, sizeof(int8), 3 * MAX_CHAR_LEVEL);
      FIELD_ARRAY(419, SaveBonus, sizeof(int8), 16);
      FIELD_ARRAY(420, GainAttr, sizeof(int16), 7 * 15);
      FIELD_I8 (421, NotifiedLevel);
      r.V1EmbedBegin(422, ClassID, sizeof(ClassID));
      for (i = 0; i != 6; i++)
        FIELD_RID((uint16)(1 + i), ClassID[i]);
      r.V1EmbedEnd();
      FIELD_RID(423, RaceID);
      FIELD_RID(424, GodID);
      FIELD_H  (425, Mount);
      FIELD_U32(426, XP);
      FIELD_U32(427, XP_Drained);
      FIELD_ARRAY(428, SpellsLearned, sizeof(uint8), 10);
      FIELD_ARRAY(429, SpellSlots, sizeof(uint8), 10);
      FIELD_ARRAY(430, BonusSlots, sizeof(uint8), 10);
      FIELD_ARRAY(431, RecentSpells, sizeof(uint16), 10);
      FIELD_ARRAY(432, RecentSkills, sizeof(uint16), 5);
      FIELD_ARRAY(433, RecentItems, sizeof(uint16), 5);
      FIELD_ARRAY(434, Spells, sizeof(uint16), MAX_SPELLS+1);
      r.V1EmbedBegin(435, Tattoos, sizeof(Tattoos));
      for (i = 0; i != 10; i++)
        FIELD_RID((uint16)(1 + i), Tattoos[i]);
      r.V1EmbedEnd();
      FIELD_I16(436, resChance);
      FIELD_ARRAY(437, FavourLev, sizeof(int16), MAX_GODS);
      FIELD_ARRAY(438, TempFavour, sizeof(int32), MAX_GODS);
      FIELD_ARRAY(439, Anger, sizeof(int16), MAX_GODS);
      FIELD_ARRAY(440, SacVals, sizeof(int32), MAX_GODS * (MAX_SAC_CATS + 2));
      FIELD_ARRAY(441, FavPenalty, sizeof(int16), MAX_GODS);
      FIELD_ARRAY(442, PrayerTimeout, sizeof(int16), MAX_GODS);
      FIELD_ARRAY(443, AngerThisTurn, sizeof(int16), MAX_GODS);
      FIELD_ARRAY(444, lastPulse, sizeof(int32), MAX_GODS);
      FIELD_ARRAY(445, godFlags, sizeof(uint16), MAX_GODS);
      FIELD_U16(446, desiredAlign);
      FIELD_U32(447, Proficiencies);
      /* Load-direction fixups, below every field they read (wire format,
         load-direction ordering). Both are guarded by V1Active(): on the v0
         path the raw dump supplies these bytes and rejecting a v0 save this
         binary used to read is not this task's business. */
      if (!isSave && r.V1Active())
        {
          isFallenPaladin = fallen != 0;
          /* Level[c] is a loop bound over hpRolls[c][MAX_CHAR_LEVEL] and
             manaRolls[c][MAX_CHAR_LEVEL] (`for (j=0;j!=Level[i];j++)`,
             src/Values.cpp:1785 and :1841). It is an int8, so the wire can
             offer -128..127: a negative value makes that loop run away, and
             anything past MAX_CHAR_LEVEL reads off the end of the roll
             array. A value the reader cannot honour is corruption, per the
             wire format's reader rules -- the same rule TargetSystem
             applies to tCount. */
          for (i = 0; i != 3; i++)
            if (Level[i] < 0 || Level[i] > MAX_CHAR_LEVEL)
              throw ECORRUPT;
        }
    END_ARCHIVE
	};

class Parser;

class History
  {
	  protected:
		  int8 *Hist;
      int8 Race, Class, Align;
      int8 Curr;
      bool Gen;
      char *Buff;
      char *Line;
      const char* Select(int16 n,...);
      const char* Mom, *Dad, *Sis, *Bro, *Mentor, *Nemesis, *SO,*Home;
      void Orphan();
      void Peasant();
      int8 Elem(int16);
      void Set(int16,int16);
    public:
      History();
      void Compose();
      void Create(Player*p,Term*t);
  };

// ww: more Journal information 
typedef struct JournalInfoType
  {
    String bestMonster;
    int    bestMonsterVal;
    String bestItem;
    int    bestItemVal;
    int    numMonSeen;
    int    numMonOfType[MA_LAST_REAL];
  } JournalInfo;

// ww: I want to keep track of how much time we spend on each level, using
// various metrics
typedef struct LevelTimeInfo
  {
    uint32      turns;          // game time
    uint32      actions;        // game actions (ChooseAction)
    uint32      keystrokes;     // keypresses
    time_t      seconds;        // wall clock real world time
    int32       xp;             // xp gained
  } LevelTimeInfo;

typedef struct GameTimeInfoType
  {
    LevelTimeInfo       LTI[11];
    uint32              start_turn;          // on this level
    uint32              actions; 
    uint32              keystrokes;
    time_t              start_second;
    int32               start_xp; 
  } GameTimeInfo;

struct PerkAbil 
  {
    int16 ca_ability;
    int32 ability_value;
  };

typedef enum {
  PERK_NONE,
  PERK_ITEM,
  PERK_FEAT,
  PERK_ABILITY,
  PERK_SPELL,
  PERK_RESIST,
  PERK_IMMUNE,
  PERK_TALENT, /* Wild Talent... when we do psi */
  } PerkType; 

typedef struct {
  PerkType type; 
  union { 
    int16 feat;
    PerkAbil ability;
    rID spell; 
    int32 resist; 
    int32 immune; 
    struct {
      rID iID, eID;
      int16 Plus, Bane;
      int16 q[8];
      } i;
  } p;
} Perk; 

#define NUM_PERKS_PER_SET 3
typedef struct {
  Perk elt[NUM_PERKS_PER_SET];
} PerkSet;


/* This structure can store the result to the following:
   * Turn or command undead? [tc] -- stores 't'
   * LMenu questions (favoured enemies, weapon focus,
       feat choice, etc).
   * yes/no prompts
*/
struct Response
  {
    char Question[32];
    int32 Answer;
  };

struct ReincarnationInfo
  {
    /* Meta Stuff */
    time_t Created,
           Touched; /* Last time this char was played,
                         so we can keep only the 16 most
                         recently used chars in the gallery */
    
    int16 Count;   /* so name == "Samisa Tauth IV" */
    bool Active, Disabled, WizMode, ExpMode;

    char Name[32];

    /* Basic Choices */
    rID RaceID, ClassID;

    /* Attribute Set */
    int8 Attr[8];
    PerkSet Perks;
   
    /* Equipment Random Rolls */
    int8 EquipRolls[256];
    int16 cEquipRolls, nEquipRolls;
    int32 rerollCount, statMethod;
    bool rerolledPerks, usedPerks;
    int8 SkillRanks[100];
    int8 CharGenOpts[100];

    /* Awnsers to Scripted Chargen Questions */
    Response Rsp[128];
    int16    cRsp, nRsp;
    int32    formulaSeed, storeSeed;
  };

struct QuickKey
  {
    uint32 Value;
    int16  Type;
    hObj   hItem;
    uint32 MM;
  };

class Player: public Character
  {
    friend void Map::VisionThing(int16 p, Creature *c, bool do_clear);
    friend bool Game::SaveGame(Player &p);
    friend bool Game::LoadGame(bool backup);
    friend void HelpCustom(String &helpText, Player *p);
    friend class TextTerm; 
    private:
	 	  /* Parser Par; */
      /* History Hist; */
	 	  int16 MapMemoryMask;
	 	  int16 GallerySlot;
      int8  MapSP;
      int16 MaxDepths[MAX_DUNGEONS];
      uint32 MMArray[MAX_SPELLS];
      rID      Macros[MAX_MACROS];    /* F1-F12, CTRL+F1-F12, ALT+F1-F12, SHIFT+F1-F12 */
      QuickKey QuickKeys[MAX_QKEYS]; /* '1'-'0', CTRL+'1'-'0', etc. */
      String MessageQueue[8];
      int16  AutoBuffs[64], cAutoBuff;
      String GraveText;
	    int16 HungerShown;
      String Journal; /* record interesting things that happened */
      JournalInfoType JournalInfo; 
      int16 RecentVerbs[5];
    public:
      GameTimeInfoType GameTimeInfo;
      bool statiChanged;
      int32 formulaSeed, storeSeed;
      int16 SpellKeys[12];
      int8  Options[OPT_LAST];
      Term* MyTerm;
      bool shownFF;
      bool VictoryFlag, QuitFlag;
      bool UpdateMap;
      bool DigMode;
      bool WizardMode, ExploreMode,
             rerolledPerks;  
      int32 deathCount, rerollCount;
      int16 statMethod;
      /* General Functions */
      Player(Term *t,int16 _Type=T_PLAYER);
      ~Player();
      void UpdateOptions(bool specific_game);
      void LoadOptions(bool new_game);
      void ResetOptions();

      virtual void Dump();
      virtual void NotifyGone(hObj h);
	 	  virtual void ChooseAction();
	 	  virtual void UseItemMenu(const char*msg, const char*haveno, int16 ty);
      bool RunTo(int16 x, int16 y);
      void RunDir(Dir d);
      void CalcVision();
      virtual void DumpQueue(int16 Queue);
      virtual void EmptyQueue(int16 Queue);
      

      /* Journal Functions */
      virtual void JournalNoteItem(Item *i);
      virtual void JournalNoteMonster(Monster *m);
      virtual void AddJournalEntry(const char* s);
      virtual String & GetJournal(); 
      virtual const char* GetMonstersEncountered(); 
      virtual void StoreLevelStats(uint8 depth); 
      virtual void ResetLevelStats(); 
      virtual String & GetLevelStats(); 
      virtual void NoteArrival();
      virtual int16 getMaxDepth(rID dID);

      virtual void AutoPickupFloor(); 
      void ChooseGod(bool required = true); 

      /* Display a formatted message in the player's message window. */
      virtual void IPrint(const char*, ...);
      /* [Varargs] Display a formatted message in the player's message window. */
      virtual void __IPrint(const char*, va_list ap);
      /* Display one message to the given player, and another to any players who xperceive the given player. */
      virtual void IDPrint(const char*, const char*, ...);
      EvReturn Death(EventInfo &e);
      void Gravestone();
	 	  EvReturn Event(EventInfo &e);
      virtual bool yn(const char* msg,bool def=true);
      virtual int8 ChoicePrompt(const char*msg, const char*choices, char def, 
                                  int8 col1=BROWN,int8 col2=YELLOW,bool preprompt=true);
      int16 Opt(int16 op);

      /* Inventory and Stati */
	 	  Item* SelectItem(char* AllowedClasses, char* SuggestedClasses);
	 	  Item* SelectItem() { return SelectItem(NULL,NULL); }
	 	  void ShowStati();
                  void IntuitItem(Item *it); 

      /* Trait Management Functions */
	 	  void Create(bool reincarnate=false);
      bool Reincarnate();
      void DisableReincarnation();
      void TouchGallery(bool active);
      void RollAttributes();
      void ChooseDomains();
	 	  void MapTurn();
	 	  int8 ManageInv();
      void Tactical();
      virtual void AdvanceLevel();
      virtual void GainFeat(int16 list, int32 param=0);
      virtual void GainAbility(int16 ab, uint32 pa, rID sourceID,int16 statiSource);
      void LearnSpell(bool left = false);
      void InitCompanions();
      void SummonAnimalCompanion(bool mount);
      void WildShape();
      
      int32 GetGroupXCR(int16 CompType, int16 AddCR=0);
      int16 GetGroupCR(int16 CompType, int16 AddCR=0)
        { return XCRtoCR(GetGroupXCR(CompType,AddCR)); }
      int16 MaxGroupCR(int16 CompType);
      int32 MaxGroupXCR(int16 CompType);
      int16 FixSummonCR(int16 enCR, int16 CompType=PHD_MAGIC);
      void GainSpell(rID sID,int16 Flags)
        { Spells[theGame->SpellNum(sID)] |= Flags; }
      virtual void IdentByTrial(Item *it, int16 Quality=0);
      void ShowStats();
      //String BonusBreakdown(int8 at, int16 maxlen=250);
	    String & SkillBreakdown(int8 sk, int16 maxlen=250);
      String & SpellBreakdown(int8 sp, int16 maxlen=250);
      String & ResistBreakdown(int8 dt, int16 maxlen=250);



	    bool Seen(int16 x,int16 y);
      void ToggleMM(uint32 mm,int16 sp);
      bool HasMM(uint32 mm,int16 sp)
        { return (MMArray[sp] & mm) != 0; }
      virtual uint32 MMFeats(uint32 sp) { return MMArray[sp]; }

      /* Functions for Performing Actions */
      void UseMenu(int32 QKeyIndex = 0);
      void CancelMenu();
      void YuseMenu(int32 QKeyIndex = 0);
      bool YusePrompt(int16 qval, const char *msg, EventInfo &e, int8 p);
      void CursorKeys(Dir d, uint8 ControlKeys);
      virtual EvReturn SpendHours(int16 minHours, int16 maxHours, 
                     int16 &hoursSpent=__spentHours, bool isHeal=false);
      virtual EvReturn Rest(EventInfo &e);        
      virtual EvReturn GodRaise(EventInfo &e);
      virtual void MoveDepth(int16 NewDepth, bool safe=false);
      int16 FirstAutoBuff() { cAutoBuff = 0; return AutoBuffs[cAutoBuff++]; }
      int16 NextAutoBuff()  { return AutoBuffs[cAutoBuff++]; }
      void ScrutinizeMon(Creature *cr);

      /* Debug Mode Functions */
 	 	  void WizardOptions();
	 	  void BrowseThings(bool nearby);
	 	  void ListLevelTreasure();
	 	  void ListChestContents();
    ARCHIVE_CLASS(Player,Character,r)
      /* v1 tags 512-639, in the declaration order of the members above
         (`int16 MapMemoryMask` down to `int16 statMethod`). Widths measured
         on arm64/LP64, 2026-08-24.

         THE THREE FIELD_STR LINES MUST KEEP THEIR RELATIVE ORDER. FIELD_STR
         is the only macro here whose v0 branch writes to the stream: it
         calls String::Serialize, which is exactly what these three lines
         used to be. So Journal, then JournalInfo.bestItem, then
         JournalInfo.bestMonster is the v0 wire order, and reordering them
         would make this binary unable to read a save it wrote yesterday.
         That is why bestItem's line comes before bestMonster's even though
         bestMonster is declared first. Every other macro in this body is a
         no-op on the v0 path.

         ponytail: MMArray[] is indexed by spell number and AutoBuffs[],
         SpellKeys[] and QuickKeys[].Value hold spell and ability numbers,
         not rIDs. Same ceiling and same upgrade path as the note in
         Character's list above. */
      static_assert(sizeof(Player) == 19616,
                    "Player's coverage pin row pads assume this");
      static_assert(sizeof(JournalInfoType) == 360, "JournalInfo embed range");
      static_assert(sizeof(GameTimeInfoType) == 384, "GameTimeInfo embed range");
      static_assert(sizeof(QuickKey) == 16, "one embed per quick key");
      static_assert(sizeof(String) == 24, "V1Str covers a whole String");
      static_assert(sizeof(time_t) == 8, "start_second travels as 8 raw bytes");
      /* Order-independent: MyTerm is the process's one terminal, not saved
         state, and nothing below reads it. It stays where it has always
         been. */
      if (!isSave)
        MyTerm = T1;
      int i;
      FIELD_I16(512, MapMemoryMask);
      FIELD_I16(513, GallerySlot);
      FIELD_I8 (514, MapSP);
      FIELD_ARRAY(515, MaxDepths, sizeof(int16), MAX_DUNGEONS);
      FIELD_ARRAY(516, MMArray, sizeof(uint32), MAX_SPELLS);
      /* An rID array: per-element FIELD_RID inside an embed, never
         FIELD_ARRAY -- see the note in Character's list. */
      r.V1EmbedBegin(517, Macros, sizeof(Macros));
      for (i = 0; i != MAX_MACROS; i++)
        FIELD_RID((uint16)(1 + i), Macros[i]);
      r.V1EmbedEnd();
      /* One embed per quick key. QuickKey carries an hObj, which must be a
         named K_H field rather than four raw bytes, and the embed also
         takes the struct's interior padding with it. */
      r.V1EmbedBegin(518, QuickKeys, sizeof(QuickKeys));
      for (i = 0; i != MAX_QKEYS; i++)
        {
          r.V1EmbedBegin((uint16)(1 + i), &QuickKeys[i], sizeof(QuickKey));
          FIELD_U32(1, QuickKeys[i].Value);
          FIELD_I16(2, QuickKeys[i].Type);
          FIELD_H  (3, QuickKeys[i].hItem);
          FIELD_U32(4, QuickKeys[i].MM);
          r.V1EmbedEnd();
        }
      r.V1EmbedEnd();
      /* MessageQueue and GraveText below are Strings that v0 never
         serialized -- it dumped the String struct raw, so a v0 load
         restores a Buffer pointer into the writing process's dead heap.
         FIELD_STR cannot be used for them, because its v0 branch would ADD
         a Serialize call to the v0 stream and break every existing save.
         Calling V1Str behind V1Active() stores the text on the v1 path and
         leaves the v0 path exactly as it was. */
      if (r.V1Active())
        {
          r.V1EmbedBegin(519, MessageQueue, sizeof(MessageQueue));
          for (i = 0; i != 8; i++)
            r.V1Str((uint16)(1 + i), MessageQueue[i]);
          r.V1EmbedEnd();
        }
      FIELD_ARRAY(520, AutoBuffs, sizeof(int16), 64);
      FIELD_I16(521, cAutoBuff);
      if (r.V1Active())
        r.V1Str(522, GraveText);
      FIELD_I16(523, HungerShown);
      FIELD_STR(524, Journal);                    /* v0 order: first */
      r.V1EmbedBegin(525, &JournalInfo, sizeof(JournalInfo));
      FIELD_STR(1, JournalInfo.bestItem);         /* v0 order: second */
      FIELD_STR(2, JournalInfo.bestMonster);      /* v0 order: third */
      FIELD_I32(3, JournalInfo.bestMonsterVal);
      FIELD_I32(4, JournalInfo.bestItemVal);
      FIELD_I32(5, JournalInfo.numMonSeen);
      FIELD_ARRAY(6, JournalInfo.numMonOfType, sizeof(int), MA_LAST_REAL);
      r.V1EmbedEnd();
      FIELD_ARRAY(526, RecentVerbs, sizeof(int16), 5);
      r.V1EmbedBegin(527, &GameTimeInfo, sizeof(GameTimeInfo));
      /* LevelTimeInfo is five plain numbers with no handle and no rID, so
         the per-level array travels as raw elements; the embed above takes
         its interior padding. */
      FIELD_ARRAY(1, GameTimeInfo.LTI, sizeof(LevelTimeInfo), 11);
      FIELD_U32(2, GameTimeInfo.start_turn);
      FIELD_U32(3, GameTimeInfo.actions);
      FIELD_U32(4, GameTimeInfo.keystrokes);
      /* time_t is 8 bytes here and no kind is that wide, so it travels as
         its own bytes -- the same treatment TargetWhy::data gets. */
      FIELD_ARRAY(5, &GameTimeInfo.start_second, 1, sizeof(time_t));
      FIELD_I32(6, GameTimeInfo.start_xp);
      r.V1EmbedEnd();
      /* The nine bools below are staged through uint8s for the reason
         Character's isFallenPaladin is. */
      uint8 bStati = 0, bShownFF = 0, bVictory = 0, bQuit = 0, bUpdMap = 0,
            bDig = 0, bWiz = 0, bExplore = 0, bReroll = 0;
      if (isSave)
        {
          bStati   = statiChanged ? 1 : 0;
          bShownFF = shownFF ? 1 : 0;
          bVictory = VictoryFlag ? 1 : 0;
          bQuit    = QuitFlag ? 1 : 0;
          bUpdMap  = UpdateMap ? 1 : 0;
          bDig     = DigMode ? 1 : 0;
          bWiz     = WizardMode ? 1 : 0;
          bExplore = ExploreMode ? 1 : 0;
          bReroll  = rerolledPerks ? 1 : 0;
        }
      FIELD_U8 (528, bStati);       FIELD_SKIP(statiChanged);
      FIELD_I32(529, formulaSeed);
      FIELD_I32(530, storeSeed);
      FIELD_ARRAY(531, SpellKeys, sizeof(int16), 12);
      FIELD_ARRAY(532, Options, sizeof(int8), OPT_LAST);
      FIELD_SKIP(MyTerm);           /* a live pointer; rebuilt to T1 above */
      FIELD_U8 (533, bShownFF);     FIELD_SKIP(shownFF);
      FIELD_U8 (534, bVictory);     FIELD_SKIP(VictoryFlag);
      FIELD_U8 (535, bQuit);        FIELD_SKIP(QuitFlag);
      FIELD_U8 (536, bUpdMap);      FIELD_SKIP(UpdateMap);
      FIELD_U8 (537, bDig);         FIELD_SKIP(DigMode);
      FIELD_U8 (538, bWiz);         FIELD_SKIP(WizardMode);
      FIELD_U8 (539, bExplore);     FIELD_SKIP(ExploreMode);
      FIELD_U8 (540, bReroll);      FIELD_SKIP(rerolledPerks);
      FIELD_I32(541, deathCount);
      FIELD_I32(542, rerollCount);
      FIELD_I16(543, statMethod);
      /* Load-direction fixups, below every field they read. V1Active()
         guards them for the reason Character's list gives. */
      if (!isSave && r.V1Active())
        {
          statiChanged  = bStati != 0;
          shownFF       = bShownFF != 0;
          VictoryFlag   = bVictory != 0;
          QuitFlag      = bQuit != 0;
          UpdateMap     = bUpdMap != 0;
          DigMode       = bDig != 0;
          WizardMode    = bWiz != 0;
          ExploreMode   = bExplore != 0;
          rerolledPerks = bReroll != 0;
          /* cAutoBuff is the cursor NextAutoBuff() reads AutoBuffs[64]
             through, and NextAutoBuff is a script-callable API
             (inc/Api.h:506) that does not reset it. A value off the wire
             that is negative or past the array is corruption. */
          if (cAutoBuff < 0 || cAutoBuff > 64)
            throw ECORRUPT;
        }
    END_ARCHIVE

	};


class Monster: public Creature
	{
    friend class Item;
    friend uint16 Creature::Perceives(Thing*, bool);
		protected:
			hObj Inv;
      int8 BuffCount, FoilCount;
      uint8 Recent[6];
		  static ActionInfo Acts[64];
      static int16 nAct, nEff, nStati;
      static uint32 hasEffFor;
      static Creature *mtarg, *rtarg, *CurrAI;
      static EffectInfo Effs[1024];
      static bool isAfraid, isSick, isBlind, isPoisoned, isParalyzed,
             hasHunger, isDiseased, isBleeding, inMelee, targVis,
             isNatBlind, isTAfraid, hasTarget, isHiding, isStoning,
             isDrained, isEnraged, isGrabbed, isAvoiding,
             hasInnateSpellStati, isMount; 
    public:
			hObj GetInvHead() { return Inv; }
      Monster(rID mID,int16 _Type=T_MONSTER);
			EvReturn Event(EventInfo &e);
      virtual void Dump();
      virtual String & Describe(Player *p);


      virtual void ChooseAction();
      inline void AddAct(int8 act, int8 pri, Thing *tar=NULL, int32 subval = 0)
        { ASSERT((!tar) || (tar->x != 1600))
          if (act == ACT_SATTACK) ASSERT(subval);
          ASSERT(nAct < 63);
          Acts[nAct].Act = act; Acts[nAct].Pri = pri;
          Acts[nAct].Tar = tar; Acts[nAct].Val = subval; nAct++;
        }
      int16 RateAsTarget(Thing *t);

      virtual void Initialize(bool in_play = false);
      void ReactToAttack(EventInfo &e);
      EvReturn Movement();
      Dir      SmartDirTo(int16 tx, int16 ty, bool is_pet=false);
      EvReturn OpenDoor(Door *d);
      EvReturn Inventory();
      void Retarget();   /* Anything nearby to pick up? */
      void ListEffects();
      void PreBuff(); /* ww */
      uint32 SetMetamagic(rID eID, Thing *tar, uint16 Pur);
      void AddEffect(TEffect *te, rID eID, Item *src);
      static void AlertNew(Thing *t);
      uint32 BadFields();
      
 		  virtual EvReturn PickUp(EventInfo &e);
		  virtual EvReturn Drop(EventInfo &e);
      virtual EvReturn Wield(EventInfo &e);
      virtual EvReturn TakeOff(EventInfo &e);
		  virtual Item*    InSlot(int8 slot, bool eff=false);
      virtual void     DropAll();
      virtual Item*    GetInv(bool first);
      void MonsterGear();
      virtual void GainItem(Item *it, bool starting=false);
      bool MakeCompanion(Player *p, int16 CompType);
      
      // Target System Wrappers
      void    TurnHostileTo(Creature *cr) { ts.TurnHostileTo(this,cr); }
      void    TurnNeutralTo(Creature *cr) { ts.TurnNeutralTo(this,cr); }
      void    Pacify(Creature *cr)        { ts.Pacify(this,cr); }
      void    ForgetOrders(int ofType=-1) { ts.ForgetOrders(this,ofType); }
      void    Consider(Thing *t)          { ts.Consider(this, t); }
      bool    hasTargetOfType(TargetType type) { ts.hasTargetOfType(type); }
      bool    hasTargetThing(Thing *t)    { ts.hasTargetThing(t); } 
      
    ARCHIVE_CLASS(Monster,Creature,r)
      /* v1 tags 640-671, in the declaration order of the four own members
         above. The statics beside them (Acts, Effs, nAct, the AI flags)
         belong to the class and not to the object, so they are outside the
         record entirely -- they are not members of any Monster and the
         coverage map never sees them. */
      static_assert(sizeof(Monster) == 1696,
                    "Monster's coverage pin row pads assume this");
      FIELD_H  (640, Inv);
      FIELD_I8 (641, BuffCount);
      FIELD_I8 (642, FoilCount);
      FIELD_ARRAY(643, Recent, sizeof(uint8), 6);
    END_ARCHIVE
	};


