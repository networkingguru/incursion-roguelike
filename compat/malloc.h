/* Compatibility shim: Windows/glibc <malloc.h> does not exist on macOS/BSD.
   Provides the same declarations from their POSIX homes. */
#pragma once
#include <stdlib.h>
#if defined(__APPLE__) || defined(__FreeBSD__)
#include <malloc/malloc.h>
#include <alloca.h>
#endif
