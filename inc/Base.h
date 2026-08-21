/* BASE.H -- See the Incursion LICENSE file for copyright information.

     This file contains class definitions for Array, NArray,
   OArray, Dice, String, MVal, Rect, Dictionary, Fraction,
   Object and Registry. 
*/


#define BIT(bitnum) (1 << (bitnum - 1))
#define XBIT(a)     (1 << (a))

#define Check(a,b) { if (!(a)) Fatal(b);  }
#define iswhite(ch) ((ch) == 13 || (ch) == ' ' || (ch) == '\t' || \
                       (ch) == 10)
                       
#define isspace(ch) isspace(max(ch,1))
#define isalpha(ch) isalpha(max(ch,1))
#define isalnum(ch) isalnum(max(ch,1))
#define isdigit(ch) isdigit(max(ch,1))

#define SC(xx) (*tmpstr((const char*)xx))

/* Object::operator new adds HEAP_PAD bytes to every allocation. In an ordinary
   build that is the constant 0 and the compiler removes it: no symbol, no
   call, no cost. In the DIVERGE_PROBE build it asks src/Base.cpp for a number
   that depends on INCURSION_LAYOUT, which moves objects past each other and
   makes an address-dependent decision split a pair of runs on demand. Read the
   long comment on HeapPad before changing this. See inc-1vg. */
#ifdef DIVERGE_PROBE
  size_t HeapPad(void);
  #define HEAP_PAD HeapPad()
#else
  #define HEAP_PAD 0
#endif

template<class S, int32 Initial, int32 Delta>
  class Array
	{
		private:
			S *Items;          
			uint32 Size, Count;
			void Enlarge();
			void Reduce();
    protected:
      S* _Paren(uint32 index);

		public:
			Array();
			~Array() { if (Items) free(Items); }
      void Serialize(hObj myObj);
      void Set(S&,uint32 idx);
			int32 Add(S&);
			int32 Total() { return Count; }
      void Remove(uint32 i);
      S*   NewItem();
      void Serialize(Registry &r);
      void Clear() { Count = 0; }; 
	};

extern long ZeroValue;

template<class S,int32 Initial,int32 Delta>
  class NArray : public Array<S,Initial,Delta>
  {
    public:
      S& operator[](int32 index)
        { S *s = this->_Paren(index);
          ASSERT(!ZeroValue); 
          return s ? (*s) : *((S*)&ZeroValue); }
      void RemoveItem(S s)
        { Restart:
          for (int32 i=0;this->_Paren(i);i++)
            if (*this->_Paren(i) == s)
              { this->Remove(i); goto Restart; } }  
  };

template<class S,int32 Initial,int32 Delta>
  class OArray : public Array<S,Initial,Delta>
  {
    public:
      S* operator[](int32 index)
        { return this->_Paren(index); }
      void RemoveItem(S* s)
        { Restart:
          for (int32 i=0;this->_Paren(i);i++)
            if (this->_Paren(i) == s)
              { this->Remove(i); goto Restart; } }
  };


/* upstream: base-code defect, the fix is ours. The condition tests 'm &&' and
   the increment tests 'm ?', and the initialiser -- which runs before either --
   tested nothing and dereferenced m->Things[0]. Guarding m twice and not a
   third time is not a design: the two guards say plainly that the author
   expected m to be null sometimes, and this is the missing third. It is
   upstream's because it is plain C macro expansion and C++ evaluation order,
   identical on Win32 with the original typedefs. Reachable: src/Fight.cpp runs
   MapIterate two lines after a Reveal(true) that can delete the creature and
   null its m (inc-upw.37).
   Tier Traced: read out of the macro, never observed to fire.
   inc-upw.38. NOT SENT upstream. */
#define MapIterate(m,t,i) \
    for (i = 0, t = m ? (Creature*)oThing(m->Things[0]) : NULL; m && m->Things[i]; i++, (t = m ? (Creature*)oThing(m->Things[i]) : NULL))

void* x_realloc(void *block, size_t unit, size_t sz, size_t osz);

/* A String class similar to the one provided by MFC, and
   likely by most other C++ compilers nowadays as well. We
   rewrite it here to ensure portability. */

class String
  {
    friend String *tmpstr(const char*data, bool newbuff);
    friend void PurgeStrings();
    private:
      int32 Canary;
      char * Buffer;
      int32 Length;
      
    public:
      String();                 
      String(const char*str);
      ~String();
      void Empty();
      operator const char*();
      String & operator +=(const char*add);
      String & operator +=(char ch);
      String & operator =(const char*s);
      String & operator =(String &s)
        { return ((*this) = ((const char*) s)); }
      String & operator +(const char*s);
      bool operator ==(const char* s2);
      bool operator !=(const char* s2);
      bool operator>(const char* s2);
      bool operator<(const char* s2);
      int32 strchr(char ch);
      const char* GetData() { return Buffer; }
      int32 GetLength() { return Length; }
      int32 GetTrueLength();
      String & Left(int32 sz);
      String & TrueLeft(int32 sz);
      String & TrueRight(int32 sz);
      String & Right(int32 sz);
      String & Mid(int32 start, int32 end);
      String & Trim();
            
      String & Upto(const char* chlist);
      String & After(const char* chlist);
      String & Capitalize(bool all = false);
      String & Replace(const char* find, const char* rep);
      String & Upper();
      String & Lower();
      int16 TrueLength();
      String & Decolorize();
      void SetAt(int32 loc,char ch);
      int8 GetAt(int32 loc);
      void Serialize(Registry &r);
  };



extern String & VFormat(const char*fmt,va_list ap);
extern String & Format(const char*fmt,...) __attribute__((format(printf,1,2)));

String & Pluralize(const char* s, rID iID=0);
String & Replace(const char* str, const char* find, const char* rep);

String & Capitalize(const char*s, bool all = false);
String & Left(const char*s, int32 sz);
String & Right(const char*s, int32 sz);
String & Trim(const char*s);
String & Mid(const char*s, int32 start, int32 end);
String & Upto(const char*s, const char* chlist);
String & After(const char*s, const char* chlist);
String & Upper(const char*s);
String & Lower(const char*s);
String & Decolorize(const char*s);

String & EventName(int16 ev);

String * tmpstr(const char*data, bool newbuff=true);

struct TextVal
  {
    int32      Val;
    const char *Text;
  };

struct MVal 
  {
    signed int Value:10;
    unsigned int VType:4;
    signed int Bound:10;
    unsigned int BType:4;
    int16 Adjust(int16 oval) {
      int16 nval;
      switch (VType) {
        case MVAL_NONE:
          nval = oval;
         break;
        case MVAL_ADD:
          nval = (int16)max(0,oval+Value);
         break;
        case MVAL_SET:
          nval = Value;
         break;
        case MVAL_PERCENT:
          nval = (int16)(oval*Value)/100;
         break;
        default:
          Error("MVal::Adjust -- illegal VType!");
        }
      switch (BType) {
        case MBOUND_NONE:
          break;
        case MBOUND_MIN:
          nval = (int16)max(Bound,nval);
         break;
        case MBOUND_MAX:
          nval = (int16)min(Bound,nval);
         break;
        case MBOUND_NEAR:
          if (nval >= oval)
            nval = (int16)max(nval,(nval+Bound*2)/3);
          else
            nval = (int16)max(nval,(nval+Bound*2)/3);
         break;
        default:
          Error("MVal::Adjust -- illegal BType!");
        } 
      return nval;                                
    }
  };


#define oThing(h)     ( theRegistry->GetThing(h) )
#define oPlayer(h)    ( theRegistry->GetPlayer(h) )
#define oCreature(h)  ( theRegistry->GetCreature(h) )
#define oItem(h)      ( theRegistry->GetItem(h) )
#define oMap(h)       ( theRegistry->GetMap(h) )
#define oObject(h)    ( theRegistry->Get(h) )
#define oCharacter(h) ( (Character*) (theRegistry->GetCreature(h)) )
#define oMonster(h)   ( (Monster*)   (theRegistry->GetCreature(h)) )
#define oContain(h)   ( (Container*) (theRegistry->GetItem(h)) )
#define oWeapon(h)    ( (Weapon*)    (theRegistry->GetItem(h)) )
#define oArmour(h)     ( (Armour*)     (theRegistry->GetItem(h)) )
#define oFeature(h)   ( (Feature*)   (theRegistry->GetThing(h)) )
#define oPortal(h)    ( (Portal*)    (theRegistry->GetThing(h)) )
#define oDoor(h)      ( (Door*)      (theRegistry->GetThing(h)) )
#define oTrap(h)      ( (Trap*)      (theRegistry->GetThing(h)) )
#define oGame(h)      ( (Game*)      (theRegistry->Get(h)) )
#define oModule(h)    ( (Module*)    (theRegistry->Get(h)) )

#define isValidHandle(h) ( theRegistry->Exists(h) )
struct RegNode
  {
    Object   *pObj;
    RegNode  *Next;
  };

struct DataNode
  {
    void     *pData;
    int32     Size;
    hObj      hOwner;
    hData     myHandle;
    DataNode *Next;
  };

struct GroupNode
  {
    hObj     hGroup;
    int32    LastUse;
    bool     Loaded;
    bool     Needed;
  };



#ifdef INCURSION_OOB_PROBE
/* inc-5xn / upstream issue #40, diagnostic only. Defined in src/Display.cpp. */
extern void OobProbePlaceWithin(int x1,int y1,int x2,int y2,int sx,int sy,
                                int rx1,int ry1,int rx2,int ry2);
extern void OobProbePlaceWithinPlain(int x1,int y1,int x2,int y2,int sx,int sy,
                                     int rx1,int ry1,int rx2,int ry2);
extern void OobProbePwsGeom(int px1,int py1,int px2,int py2,int sx,int sy,
                            int rx1,int ry1,int rx2,int ry2);
extern void OobProbePwFired(int x1,int y1,int x2,int y2,int sx,int sy,
                            int rx1,int ry1,int rx2,int ry2);
#endif

struct Rect
  {
    uint8 x1,x2,y1,y2;
    Rect() {}
    Rect(uint8 _x1, uint8 _y1, uint8 _x2, uint8 _y2)
      { x1 = min(_x1,_x2); y1 = min(_y1,_y2);
        x2 = max(_x1,_x2); y2 = max(_y1,_y2); }
    void Set(uint8 _x1, uint8 _y1, uint8 _x2, uint8 _y2)
      { x1 = min(_x1,_x2); y1 = min(_y1,_y2);
        x2 = max(_x1,_x2); y2 = max(_y1,_y2); }
     Rect& PlaceWithin(uint8 sx, uint8 sy)
      { 
        static Rect r;
        if (sx>=(x2-x1))
          { r.x1 = x1+1; r.x2 = x2-1;
            /* upstream: base-code defect, the fix is ours. inc-65j, tier
               Observed, SENT 2026-08-20 as rmtew#40 comment 5358799776 -- see
               the provenance note at the end of this comment. The same repair
               is applied to the y branch below; this is the only marker for
               both.

               THE DEFECT. When the wanted size does not fit, this branch insets
               by one on each side instead. With a space two squares across or
               less that puts the far edge BEFORE the near edge, and the
               function has no way to report failure, so it returns an
               inside-out rectangle. Upstream's because it is plain integer
               arithmetic on uint8 fields: it inverts on Win32 with the original
               typedefs exactly as it does here.

               WHAT THE CALLER DOES WITH IT, which is why this matters.
               PlaceWithin has exactly one caller, src/MakeLev.cpp:2948, and the
               rectangle it returns is the WALL RING of a room's inner chamber:
               the caller walks its four edges writing wall, then punches a door
               into one of them. An inside-out ring is walked backwards, and
               that is the birthplace of the 47,954 out-of-bounds Map::At()
               reads measured on seed 3390 (docs/evidence/inc-5xn/).

               WHY WIDEN AND NOT COLLAPSE. Two repairs were built and measured;
               both take that seed's out-of-bounds reads to zero. Collapsing to
               a single row leaves a ring one square thick -- a bare line of
               wall with a door onto nothing -- and it slips past the caller's
               OWN too-thin corrector twelve lines below the call
               ('if (r.y1 + 1 == r.y2)'), which tests for a ring exactly two
               across and so never sees a ring of one. Widening to the whole
               area feeds that corrector a two-row ring, which it recognises and
               expands into a real chamber. Collapsing is also wrong in the
               degenerate case: where the space is a single square it returns a
               row at y1+1, outside the space entirely, while widening stays
               inside. The cost of widening is the one-square margin every other
               path here keeps; the caller has already inset this area by two,
               so that margin is affordable. Brian chose this variant on
               2026-08-20 with both measurements in front of him.

               PROVENANCE OF THE REPORT. The out-of-bounds reads are reported
               upstream as rmtew#40 with a patch in rmtew#41, both open. The
               reply posted on #40 on 2026-08-19 recommends reserving two
               squares in PlaceWithinSafely and ends by asking rmtew which site
               he prefers; he has not answered. The addendum posted on #40 on
               2026-08-20, comment 5358799776, then names THIS repair site and
               describes this fix. So both the defect and this repair are
               public, and rmtew has answered neither.

               Tier Observed: seed 3390 under tools/keys/dive.keys, one file
               between the builds, 47,954 out-of-bounds Map::At() reads before
               and 0 after. Note that changing the rectangle changes which
               levels get generated, so the zero is measured on a different set
               of levels rather than on the same levels minus the defect;
               docs/evidence/inc-5xn/README.md says so at length and no way
               round it has been found. */
            if (r.x2 < r.x1) { r.x1 = x1; r.x2 = x2; }
          }
        else
          {
            r.x1 = (uint8)(x1 + 1 + random(max(0,((x2-x1)-2)-sx)));
            r.x2 = r.x1 + sx;
          }
        if (sy >= (y2-y1)) 
          { r.y1 = y1+1; r.y2 = y2-1;
#ifdef INCURSION_OOB_PROBE
            /* inc-5xn: record the condition BEFORE any repair is applied.
               Putting this after the repair made a fixed build report zero
               firings, which is indistinguishable from "the branch is rare"
               and is how a no-op flag looked like 19 clean runs. */
            if (r.y2 < r.y1)
              OobProbePwFired(x1,y1,x2,y2,sx,sy,r.x1,r.y1,r.x2,r.y2);
#endif
            /* The y half of the inc-65j repair marked on the x branch above.
               Insetting by one on each side inverts the rectangle when the
               area is two squares tall or less. */
            if (r.y2 < r.y1) { r.y1 = y1; r.y2 = y2; }
          }
        else
          {
            r.y1 = (uint8)(y1 + 1 + random(max(0,((y2-y1)-2)-sy)));
            r.y2 = r.y1 + sy;
          }
#ifdef INCURSION_OOB_PROBE
        /* inc-5xn, diagnostic only: the sy >= (y2-y1) branch sets
           y1+1 .. y2-1, which inverts whenever the available height is 2 or
           less. Same shape in x. Delete with the Display.cpp block. */
        OobProbePlaceWithinPlain(x1,y1,x2,y2,sx,sy,r.x1,r.y1,r.x2,r.y2);
#endif
        return r;
      }
    Rect& PlaceWithinSafely(uint8 sx, uint8 sy)
      { 
        static Rect r;
#ifdef INCURSION_OOB_RANGEFIX
        /* inc-5xn experiment: the clamps below demand 2 clear of the border,
           but this range reserves nothing on the near edge, so a rectangle can
           be placed flush and then trimmed by the clamp. Reserve the same 2
           here and the clamps stop having anything to repair. No signature
           change, no caller changes. */
        r.x1 = (uint8)(x1 + 2 + random(max(0,((x2-x1)-3)-sx)));
        r.x2 = r.x1 + sx;
        r.y1 = (uint8)(y1 + 2 + random(max(0,((y2-y1)-3)-sy)));
        r.y2 = r.y1 + sy;
#else
        r.x1 = (uint8)(x1 + random(max(0,((x2-x1)-1)-sx)));
        r.x2 = r.x1 + sx;
        r.y1 = (uint8)(y1 + random(max(0,((y2-y1)-1)-sy)));
        r.y2 = r.y1 + sy;
#endif

#ifdef INCURSION_OOB_PROBE
        /* inc-5xn: the whole geometry, before the four clamps -- the panel we
           are placing into, the size asked for, and where the rectangle landed.
           Without the panel the numbers cannot be checked by a reader. */
        OobProbePwsGeom(x1,y1,x2,y2,sx,sy,r.x1,r.y1,r.x2,r.y2);
#endif
        r.x1 = max(r.x1, x1 + 2);
        r.y1 = max(r.y1, y1 + 2);
        r.x2 = min(r.x2, x2 - 2);
        r.y2 = min(r.y2, y2 - 2);
#ifdef INCURSION_OOB_PROBE
        /* inc-5xn, diagnostic only: does the inverted rectangle leave here,
           or is it inverted later by a caller? The four clamps above are
           applied independently, so the y1 clamp can raise the top past the
           y2 clamp's lowered bottom. Delete with the Display.cpp block. */
        OobProbePlaceWithin(x1,y1,x2,y2,sx,sy,r.x1,r.y1,r.x2,r.y2);
#endif
        return r;
      }
    bool Within(uint8 x,uint8 y)
      { return (x >= x1 && x <= x2 && y >= y1 && y <= y2); }
    uint16 Volume()
      { return (x2 - x1) * (y2 - y1); }
    bool Overlaps(Rect &r)
      {
        if (((x1 >= r.x1) == (x2 <= r.x2)) && 
          ((y1 >= r.y1) == (y2 <= r.y2)))
          return false;
        if (Within(r.x1,r.y1)) return true;
        if (Within(r.x1,r.y2)) return true;
        if (Within(r.x2,r.y1)) return true;
        if (Within(r.x2,r.y2)) return true;
        return false;
      }
  };




struct DictNode
	{
		const char* Word;
		int16 ID;
		DictNode *Lower;
		DictNode *Higher;
	};
class Dictionary
	{
		private:
			DictNode Head;
			int16 Size;
			int16 RealSize;
			const char** IDs;
			bool Loaded;
			void PlaceWord(const char*,int16);
			void Enlarge();
		public:
			Dictionary();
			int16* ProcessName(const char*Name);
			void Parse(const char*line);
			bool Read(const char*filename);
			const char* Word(int16 ID);
			int16 NewID() {return Size+1;}
			int16 ID(const char *);
			int16 InsertWord(char*word);
	};
extern Dictionary Dict;

struct Dice
	{
		int8 Number;
		int8 Sides;
		int8 Bonus;
		const char* Str();
		int16 Roll();
    Dice& LevelAdjust(int16 level,int16 spec=0);
    static int16 Roll(int8 n, int8 s, int8 b=0,int8 e=0);
		void Set(int8 n,int8 s, int8 b)
			{ Number=n; Sides=s; Bonus=b; }
    bool operator==(Dice &d)
      { return Number == d.Number && Sides == d.Sides &&
                             Bonus == d.Bonus; }
	};

struct ParseArch
	{
		int16 Verb[4];
		int16 Noun1f;
		int8 Noun1t;
		int16 Sep[4];
		int16 Noun2f;
		int8 Noun2t;
		int16 Act;
	};
class Player;
class Thing;
class Object;
class Win32Term;
class Term;
class MsDosTerm;

class Parser
	{
		private:
			int16 w[40];
			int16 n[20];
			int16 FoundWith; //Which NF_ flags noun actually fell under.
			Thing* Match;
			int8 MatchScore;
			Dir DirMatch;
			Dictionary* d;
			Player *p;
			Object * P1, * P2;
			char ErrMsg[80];
		public:
      Parser() {}
			Parser(Player*_p,Dictionary*_d)
				{ p=_p; d=_d; }
			void Parse(const char* Line);
			bool CheckMatch(ParseArch&a);
			void RemoveFluff();
			void BadNoun(int16 NF, int8 Type);
			bool Tokenize(const char* Line);
			int8 MatchNoun(Thing*t);
			bool MatchNounWord(Thing*,int16);
			bool HandleNoun(int16 NF, int8 Type);
			bool ValidLoc(int16 Flags, Thing*n);

	};

struct Option
  {
    int16       Val;
    const char* Name;
    const char* Choices;
    int8        Maximum;
    int8        Default;
    int16       Prereq;
    const char* Desc;
  };

class Fraction
  {
    private:
      // Data members
      int32 m_numerator, m_denominator;
    public:
      // Public methods
      Fraction();
      Fraction(int32 numerator, int32 m_denominator);
      Fraction(int32 intVal);
      Fraction(const Fraction &other);

      Fraction& operator=(const Fraction &rhs);


      // Accessors.
      int GetNumerator() const { return m_numerator; }
      int GetDenominator() const { return m_denominator; }

      // Comparison operators.
      friend bool operator==(const Fraction &lhs, const Fraction &rhs);
      friend bool operator!=(const Fraction &lhs, const Fraction &rhs);
      friend bool operator<(const Fraction &lhs, const Fraction &rhs);
      friend bool operator>(const Fraction &lhs, const Fraction &rhs);

    private:
      // Private methods
      void Normalize();
      static const inline int GCD(int32 a, int32 b);
      static void EqualizeDenominators(Fraction &a, Fraction &b);
    public:
      inline void Set(int32 num, int32 denom) {
        m_numerator = num; m_denominator = denom;
        Normalize(); }
  };





class Archive;

class Object 
  {
    public:
    Object(int16 _Type); 
    Object(Registry *) {}
    ~Object();
    virtual String & Name(int16 Flags=0) { return *tmpstr("<object>"); }
    int16 Type;
    hObj myHandle;
    bool isCreature() { return Type == T_MONSTER || Type == T_NPC
                         || Type == T_PLAYER; }
    bool isFeature()  { return Type == T_DOOR || Type == T_PORTAL
                         || Type == T_TRAP || Type == T_FEATURE; }
    bool isItem()     { return Type>=T_FIRSTITEM && Type<=T_LASTITEM; }
    virtual bool isWeapon() { return false; } 
    virtual bool isArmour() { return false; } 
    bool isPlayer()   { return Type == T_PLAYER; }
    bool isMonster()  { return Type == T_MONSTER; }
    bool isCharacter(){ return Type == T_PLAYER || Type == T_NPC; }
    bool isContainer() { return Type == T_CONTAIN || Type == T_CHEST; }
    bool isType(int16 t) { return (t == T_THING) || (t == T_OBJECT) ||
                                 (t == T_ITEM && isItem()) ||
                                 (t == T_FEATURE && isFeature()) ||
                                 (t == T_CREATURE && isCreature()) ||
                                 (t == T_CHARACTER && isCharacter()) ||
                                 (t == T_CONTAIN && isContainer()) ||
                                 (t == Type); }

    virtual void Serialize(Registry &r, bool isSave) {}
    virtual String & Describe(Player *p)
      { return *tmpstr("[Object::Describe] A strange, undefined thing."); }
    virtual void Dump();
    void* operator new(size_t sz)
      {
        void *vp;
        size_t pad = HEAP_PAD;
        vp = malloc(sz + pad);
        if (!vp)
          Fatal("Memory allocation error!");
        memset(vp,0,sz + pad);
        return vp;
      }
    void* operator new[](size_t sz)
      {
        void *vp;
        size_t pad = HEAP_PAD;
        vp = malloc(sz + pad);
        if (!vp)
          Fatal("Memory allocation error!");
        memset(vp,0,sz + pad);
        return vp;
      }
    void* operator new(size_t sz,Object *o)
      {
        /* A means to initialize the vptr without actually
         * allocating the object.
         */
        return (void*)o;
      }
    void operator delete(void* vp)
      { free(vp); }
    void operator delete[](void* vp)
      { free(vp); }
    virtual bool inGroup(hObj h)
      { return (h == 0); }

  };

#define ARCHIVE_CLASS(ClassName,Base,r)                         \
  friend class Registry; protected:                             \
  ClassName(Registry*r) : Base(r) {}                            \
  virtual size_t ObjectSize() { return sizeof(ClassName); }     \
  virtual void Serialize(Registry &r, bool isSave) {            \
  Base::Serialize(r,isSave);

#define END_ARCHIVE }
   
  

class Registry
  {
    RegNode  ObjTable[OBJ_TABLE_SIZE];
    DataNode DataTable[DATA_TABLE_SIZE];
    OArray<GroupNode,20,2> Groups;
    int32 TimeCounter;
    bool saveMode, loadMode;
    hObj hCurrent;
    FILE *fp;
    /* DECLARED UNCONDITIONALLY, AND IT MUST STAY THAT WAY. This member used to
       sit inside #ifdef DEBUG, which made sizeof(Registry) 8 bytes smaller in a
       shipping build -- and sizeof(Registry) is an input to SaveLayoutDigest()
       (src/AbiCheck.cpp), which stamps every module and save file. So the
       developer binary wrote Incursion.Mod stamped SF0F7B6EDC and the shipping
       binary demanded SFD3A51B74, and the released package could not load its
       own module: "Error loading module 'Incursion.Mod' (File Version
       Mismatch)". Reported by an outside user as networkingguru#6, tracked as
       inc-tm4.

       Note the guards never even agreed: every USE of reg_log is under
       DEBUG_OBJECTS (src/Registry.cpp:102,118), not DEBUG, so a plain DEBUG
       build carried the field and never touched it.

       Any member added here changes the save format's identity. If a member
       must be conditional, take it out of the digest deliberately rather than
       letting a build flag move it by accident. */
    FILE *reg_log;
    public:
    hObj LastUsedHandle, hModule;

    Registry();
    ~Registry();
    void Empty();
    bool Saving()  { return saveMode; }
    bool Loading()  { return loadMode; }
    void Block(void **Block, size_t sz);
    hData RegisterBlock(void *o, hObj Owner, size_t sz, hData h = 0);
    void ClearDataTable();
    hObj  RegisterObject(Object*o,bool loaded=false);
    void  RemoveObject(Object*);
    Object * Get(hObj h);
    /* Get() without the complaint. Identical lookup and identical result; the
       only difference is that a handle whose object is gone returns NULL in
       silence instead of logging "invalid object handle". For a caller that
       keeps a handle across the object's lifetime -- a monster's target list
       above all -- a dead handle is the ordinary state and not a fault. See
       Target::GetThingOrNULL in src/Target.cpp, and inc-upw.39. Do NOT reach
       for Exists()-then-Get() instead: both walk the same hash chain, and
       Registry::Get is upstream's second-hottest function -- see the note
       above OBJ_TABLE_SIZE in inc/Defines.h. */
    Object * GetQuiet(hObj h);
    /* Self-check for the split above. Off unless INCURSION_QUIET_PROBE is set.
       Driven by tools/check_quiet_lookup.sh. */
    void  QuietProbe();
    bool   Exists(hObj h);
    void * GetData(hData h);
    hObj   GetModuleHandle() { return hModule; }

    inline Thing* GetThing(hObj h)
      { ASSERT((!h) || (h > 0 && h < 128) || Get(h));
        return (Thing*)Get(h); }
    inline Player* GetPlayer(hObj h)
      { ASSERT((!h) || (h > 0 && h < 128) || (!Get(h)) || Get(h)->isPlayer());
        return (Player*)Get(h); }
    inline Creature* GetCreature(hObj h)
      { ASSERT((!h) || (h > 0 && h < 128) || (!Get(h)) || Get(h)->isCreature());
        return (Creature*)Get(h); }
    inline Item* GetItem(hObj h)
      { ASSERT((!h) || (h > 0 && h < 128) || (!Get(h)) || Get(h)->isItem());
        return (Item*)Get(h); }
    inline Annotation* GetAnnot(hObj h)
      { ASSERT((!h) || (h > 0 && h < 128) || (!Get(h)) || Get(h)->Type == T_ANNOT);
        return (Annotation*)Get(h); }
    inline Map* GetMap(hObj h)
      { ASSERT((!h) || (h > 0 && h < 128) || (!Get(h)) || Get(h)->Type == T_MAP);
        return (Map*)Get(h); }                  
    
    int16 SaveGroup(Term &t, hObj hGroup, bool use_lz, bool newFile=false);
    int16 LoadGroup(Term &t, hObj hGroup, bool use_lz);

  };



