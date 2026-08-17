/*************************************************************************
* Name:        lz.h
* Author:      Marcus Geelnard
* Description: LZ77 coder/decoder interface.
* Reentrant:   Yes
*-------------------------------------------------------------------------
* Copyright (c) 2003-2006 Marcus Geelnard
*
* This software is provided 'as-is', without any express or implied
* warranty. In no event will the authors be held liable for any damages
* arising from the use of this software.
*
* Permission is granted to anyone to use this software for any purpose,
* including commercial applications, and to alter it and redistribute it
* freely, subject to the following restrictions:
*
* 1. The origin of this software must not be misrepresented; you must not
*    claim that you wrote the original software. If you use this software
*    in a product, an acknowledgment in the product documentation would
*    be appreciated but is not required.
*
* 2. Altered source versions must be plainly marked as such, and must not
*    be misrepresented as being the original software.
*
* 3. This notice may not be removed or altered from any source
*    distribution.
*
* Marcus Geelnard
* marcus.geelnard at home.se
*************************************************************************/

#ifndef _lz_h_
#define _lz_h_

#ifdef __cplusplus
extern "C" {
#endif


/*************************************************************************
* Function prototypes
*************************************************************************/

int LZ_Compress( unsigned char *in, unsigned char *out,
                 unsigned int insize );
int LZ_CompressFast( unsigned char *in, unsigned char *out,
                     unsigned int insize, unsigned int *work );

/* upstream: the original LZ_Uncompress() took no output-buffer size, so how
   many bytes it wrote was decided entirely by the (possibly corrupt or
   hostile) compressed stream, with nothing to stop a heap overflow if the
   stream claimed to expand past what the caller allocated. It also read
   past 'insize' with no bound if a length/offset field or a marker's second
   byte was truncated. Traced (src/lz.c, called from CFile::LoadCompressed).
   Tracking: inc-l0t. Not sent.
   outsize  - capacity of 'out', in bytes. Decompression stops the instant
              it would write past this many bytes.
   outposp  - if non-NULL, receives the number of bytes actually written,
              whether or not decompression succeeded.
   Returns 0 on success, or -1 if the stream is corrupt: it tries to read
   past insize, tries to write past outsize, or contains a back-reference
   whose offset reaches before the output produced so far. */
int LZ_Uncompress( unsigned char *in, unsigned char *out,
                   unsigned int insize, unsigned int outsize,
                   unsigned int *outposp );


#ifdef __cplusplus
}
#endif

#endif /* _lz_h_ */
