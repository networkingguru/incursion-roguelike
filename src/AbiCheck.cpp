/* ABICHECK.CPP -- See the Incursion LICENSE file for copyright information.

     Compile-time gate on the type widths and structure layouts that the save
   format depends on. This file contains no code. It fails the build on any
   target whose ABI would silently change what SaveGroup() writes to disk.

     It exists because of a bug that cost a set of save files. int32 was
   `typedef signed long`. Windows is LLP64, so long is 4 bytes there; macOS and
   Linux are LP64, where it is 8. Every "32-bit" type in the codebase was
   therefore 64-bit off Windows. Narrowing the typedefs in inc/Defines.h fixed
   that, but it turned an existing `*((long*)&hm)` in inc/Map.h into an 8-byte
   write over a 4-byte field. The overrun covered the int16 x,y declared right
   after it, so every save zeroed the player's position. Nothing complained.

     The lesson is that a width change is invisible at run time until it
   corrupts data. So assert the widths at compile time instead. If one of these
   fires on a new target, do NOT relax the assertion. Find what the ABI changed,
   then decide whether the save format has to change with it -- and if it does,
   bump VERSION_STRING so old files are rejected rather than misread.

     Registry::SaveGroup() writes whole objects as raw bytes, so a save file is
   already specific to one ABI. It is not portable between Windows and POSIX and
   was never meant to be. These assertions do not make it portable. They make a
   silent change loud.
*/

#include "Incursion.h"
#include <climits>

/* ---------------------------------------------------------------- widths ---
   The typedefs in inc/Defines.h. These sizes are part of the save format:
   every one of them appears as a field inside an object written by
   Registry::SaveGroup(), or as a handle written by it directly.            */

static_assert(CHAR_BIT == 8,
    "AbiCheck: a byte is not 8 bits; the whole save format assumes it is.");

static_assert(sizeof(int8)   == 1, "AbiCheck: int8 is not 1 byte.");
static_assert(sizeof(int16)  == 2, "AbiCheck: int16 is not 2 bytes.");
static_assert(sizeof(int32)  == 4, "AbiCheck: int32 is not 4 bytes. This is the exact defect that zeroed player positions -- read the header of this file before changing anything.");
static_assert(sizeof(uint8)  == 1, "AbiCheck: uint8 is not 1 byte.");
static_assert(sizeof(uint16) == 2, "AbiCheck: uint16 is not 2 bytes.");
static_assert(sizeof(uint32) == 4, "AbiCheck: uint32 is not 4 bytes.");
static_assert(sizeof(Dir)    == 1, "AbiCheck: Dir is not 1 byte.");
static_assert(sizeof(Glyph)  == 4, "AbiCheck: Glyph is not 4 bytes.");

/* The handle family. Registry::SaveGroup() writes these with a literal 4, not
   with sizeof, so a change here desynchronises the writer from the reader. */

static_assert(sizeof(rID)   == 4, "AbiCheck: rID is not 4 bytes.");
static_assert(sizeof(hObj)  == 4, "AbiCheck: hObj is not 4 bytes; Registry::SaveGroup writes it as a literal 4.");
static_assert(sizeof(hText) == 4, "AbiCheck: hText is not 4 bytes.");
static_assert(sizeof(hCode) == 4, "AbiCheck: hCode is not 4 bytes.");
static_assert(sizeof(hData) == 4, "AbiCheck: hData is not 4 bytes; Registry::SaveGroup writes it as a literal 4.");

/* The code treats these as one interchangeable width. oThing(h) accepts an
   hObj, resource lookups accept an rID, and the VM passes both as int32.   */

static_assert(sizeof(hObj) == sizeof(int32) && sizeof(rID) == sizeof(int32),
    "AbiCheck: the handle types no longer share int32's width.");

/* ------------------------------------------------------------ signedness ---
   Plain `char` is signed on x86 and unsigned on ARM. int8 and Dir are used as
   small signed integers -- Dir holds -1 for "no direction" -- so they must not
   pick up the platform default by accident.                                */

static_assert(int8(-1)  < 0, "AbiCheck: int8 is not signed.");
static_assert(int16(-1) < 0, "AbiCheck: int16 is not signed.");
static_assert(int32(-1) < 0, "AbiCheck: int32 is not signed.");
static_assert(Dir(-1)   < 0, "AbiCheck: Dir is not signed, but -1 means 'no direction'.");
static_assert(uint8(-1)  > 0, "AbiCheck: uint8 is not unsigned.");
static_assert(uint16(-1) > 0, "AbiCheck: uint16 is not unsigned.");
static_assert(uint32(-1) > 0, "AbiCheck: uint32 is not unsigned.");

/* ------------------------------------------------- bitfield wire formats ---
   These four are bitfield structures, so their size depends on how the ABI
   packs bitfields, not only on the width of their members. All of them are
   written to disk as raw bytes. Verified identical on arm64 and x86_64.    */

static_assert(sizeof(VCode) == sizeof(int32),
    "AbiCheck: VCode is no longer int32-sized. VBlock::GenDWord (inc/RComp.h) writes an int32 straight over one VCode slot, and the resource compiler emits one for every opcode.");
static_assert(sizeof(Status) == 20,
    "AbiCheck: Status changed size. It is written raw inside every Thing and inside TMonster's Stati[] array.");
static_assert(sizeof(MVal) == 4,
    "AbiCheck: MVal changed size. It is written raw inside the module resource tables.");
static_assert(sizeof(LocationInfo) == 20,
    "AbiCheck: LocationInfo changed size. Map::Serialize writes the whole Grid as sizeof(LocationInfo)*sizeX*sizeY raw bytes.");
static_assert(sizeof(TAttack) == 8,
    "AbiCheck: TAttack changed size. It is written raw inside TMonster.");

/* --------------------------------------------------- pointer-slot reuse ----
   Registry::Block() parks a data handle in the object's pointer field while
   the object is written out, then swaps the real pointer back afterwards.
   The pointer slot must be wide enough to hold the handle without truncating
   it. This assertion is what makes that reuse safe rather than lucky.      */

static_assert(sizeof(void*) >= sizeof(hData),
    "AbiCheck: a pointer is too narrow to hold a data handle; Registry::Block would truncate it.");

/* ------------------------------------------------------------------------ */
/* Deliberately NOT asserted: sizeof(Player), sizeof(Map), sizeof(Game) and the
   other whole-object sizes. Those change whenever anyone adds a field, which is
   a normal and expected edit. Pinning them would produce a failing build for
   ordinary work and teach everyone to edit the number instead of reading it.
   What matters here is the width of the primitives, which must never move. */
