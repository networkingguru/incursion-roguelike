/* Compatibility shim: Windows/glibc <malloc.h> does not exist on macOS/BSD.
   Provides the same declarations from their POSIX homes.

   -Icompat precedes the system directories even for angle-bracket includes, so
   on Linux this file SHADOWS glibc's own <malloc.h>. That costs nothing -- no
   caller uses mallinfo, memalign, mallopt, malloc_usable_size or malloc_stats
   -- but alloca() must still be declared, and glibc puts it in <alloca.h>.
   src/Wposix.cpp and src/Registry.cpp both call it.

   On the mingw cross build the same shadowing hides a header the target really
   has, and mingw is one of the platforms that declares alloca() IN <malloc.h>.
   So there the shim must step aside: #include_next resumes the search after
   compat/ and takes the real header. Without it src/Registry.cpp:1250 fails
   with "'alloca' was not declared in this scope". */
#pragma once
#include <stdlib.h>
#if defined(_WIN32)
#include_next <malloc.h>
#endif
#if defined(__APPLE__) || defined(__FreeBSD__) || defined(__linux__)
#include <alloca.h>
#endif
#if defined(__APPLE__) || defined(__FreeBSD__)
#include <malloc/malloc.h>
#endif
