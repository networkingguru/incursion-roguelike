/* Compatibility shim: Windows/glibc <malloc.h> does not exist on macOS/BSD.
   Provides the same declarations from their POSIX homes.

   -Icompat precedes the system directories even for angle-bracket includes, so
   on Linux this file SHADOWS glibc's own <malloc.h>. That costs nothing -- no
   caller uses mallinfo, memalign, mallopt, malloc_usable_size or malloc_stats
   -- but alloca() must still be declared, and glibc puts it in <alloca.h>.
   src/Wposix.cpp and src/Registry.cpp both call it. */
#pragma once
#include <stdlib.h>
#if defined(__APPLE__) || defined(__FreeBSD__) || defined(__linux__)
#include <alloca.h>
#endif
#if defined(__APPLE__) || defined(__FreeBSD__)
#include <malloc/malloc.h>
#endif
