/* Standalone memory-safety test for LZ_Uncompress() and RLE_Uncompress()
 * (src/lz.c, src/rle.c), written for bd inc-l0t.
 *
 * THE DEFECT THIS PROVES FIXED. Before inc-l0t, neither decoder was told
 * how big its output buffer was: how many bytes it wrote was decided
 * entirely by the content of the (possibly corrupt or hostile) compressed
 * stream, with nothing to stop it writing past the end of a heap block
 * sized for the *claimed* uncompressed size. This harness allocates each
 * output buffer with a guard region immediately after the declared
 * capacity, fills the whole allocation -- capacity AND guard -- with a
 * canary byte, and asserts the guard is still untouched after feeding the
 * decoder a stream engineered to write past that capacity. That is
 * stronger evidence than "the call returned an error code": it shows no
 * write ever reached past the buffer, which is the actual property being
 * fixed. AddressSanitizer would prove this more directly still, but it
 * deadlocks in its own initializer on this machine (bd notes, 2026-08-16);
 * this check does not depend on it and is exercised under UBSan instead by
 * tools/check_lz_uncompress.sh.
 *
 * Build & run: tools/check_lz_uncompress.sh compiles this file together
 * with src/lz.c and src/rle.c and runs it. Exit 0 = every check passed,
 * exit 1 = at least one did not (message on stderr says which).
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "../inc/lz.h"
#include "../inc/rle.h"

static int g_failed = 0;

#define CHECK(cond, msg) do { \
    if (!(cond)) { \
        fprintf(stderr, "FAIL: %s (%s:%d)\n", msg, __FILE__, __LINE__); \
        g_failed = 1; \
    } \
} while (0)

#define GUARD_SIZE 256
#define CANARY 0xAA

/* Allocate a buffer of exactly 'cap' usable bytes followed by GUARD_SIZE
   guard bytes, all pre-filled with the canary. The decoder is told its
   capacity is 'cap' -- it must never touch the guard region. */
static unsigned char *guarded_alloc(unsigned int cap) {
    unsigned char *buf = (unsigned char *) malloc((size_t) cap + GUARD_SIZE);
    if (!buf) { fprintf(stderr, "malloc failed\n"); exit(2); }
    memset(buf, CANARY, (size_t) cap + GUARD_SIZE);
    return buf;
}

static int guard_intact(unsigned char *buf, unsigned int cap) {
    unsigned int i;
    for (i = 0; i < GUARD_SIZE; ++i)
        if (buf[cap + i] != CANARY)
            return 0;
    return 1;
}

/* Encode 'x' as an LZ varint: matches src/lz.c's _LZ_ReadVarSize (7 bits
   per byte, most-significant group first, continuation bit set on every
   byte but the last). Returns the number of bytes written. */
static int enc_varint(unsigned int x, unsigned char *buf) {
    unsigned char tmp[8];
    int n = 0, i;
    do { tmp[n++] = (unsigned char)(x & 0x7f); x >>= 7; } while (x);
    for (i = 0; i < n; ++i)
        buf[i] = (unsigned char)(tmp[n - 1 - i] | (i < n - 1 ? 0x80 : 0x00));
    return n;
}

/* ---- LZ_Uncompress ------------------------------------------------- */

static void test_lz_roundtrip(void) {
    /* Ordinary use must still work: compress real data, decompress it back
       into a buffer sized exactly to fit, and get back exactly what went
       in. This is the "must not regress ordinary loading" requirement. */
    unsigned char in[2000], comp[2100], *out;
    unsigned int i, compsize, actual;
    int rc;

    for (i = 0; i < sizeof(in); ++i)
        in[i] = (unsigned char)((i * 37 + (i % 13)) & 0xff);

    compsize = (unsigned int) LZ_Compress(in, comp, sizeof(in));
    CHECK(compsize > 0, "lz roundtrip: compress produced nothing");

    out = guarded_alloc(sizeof(in));
    rc = LZ_Uncompress(comp, out, compsize, sizeof(in), &actual);
    CHECK(rc == 0, "lz roundtrip: valid stream was rejected");
    CHECK(actual == sizeof(in), "lz roundtrip: actual size wrong");
    CHECK(memcmp(in, out, sizeof(in)) == 0, "lz roundtrip: data mismatch");
    CHECK(guard_intact(out, sizeof(in)), "lz roundtrip: guard touched");
    free(out);
}

static void test_lz_reports_short_output(void) {
    /* A stream that legitimately decodes to FEWER bytes than the caller
       expects must still succeed (LZ_Uncompress itself does not know what
       the caller expected) but must report the true count, so the caller
       (CFile::LoadCompressed) can catch the mismatch itself. */
    unsigned char in[10], comp[32], *out;
    unsigned int i, compsize, actual;
    int rc;

    for (i = 0; i < sizeof(in); ++i) in[i] = (unsigned char)(i + 1);
    compsize = (unsigned int) LZ_Compress(in, comp, sizeof(in));

    out = guarded_alloc(1000);
    rc = LZ_Uncompress(comp, out, compsize, 1000, &actual);
    CHECK(rc == 0, "lz short-output: call should still succeed");
    CHECK(actual == sizeof(in), "lz short-output: actual should be the true (small) count, not the capacity");
    CHECK(guard_intact(out, 1000), "lz short-output: guard touched");
    free(out);
}

static void test_lz_overflow_attempt(void) {
    /* The core defect: a back-reference with a legitimate small offset but
       a huge length, which -- if the decoder did not know its own output
       capacity -- would copy far past the end of the buffer. Emits a few
       literal bytes first so the back-reference has something valid to
       point at, then asks for a length no real caller could ever want. */
    unsigned char stream[64], *out;
    unsigned int cap = 64, actual, pos = 0, i;
    int rc;

    stream[pos++] = 0x00;               /* marker */
    for (i = 0; i < 10; ++i)            /* 10 literal bytes -> outpos == 10 */
        stream[pos++] = (unsigned char)(0x41 + i);
    stream[pos++] = 0x00;               /* marker byte again: start a token */
    stream[pos++] = 0x01;               /* not 0 -> length/offset follow */
    pos += (unsigned int) enc_varint(5000000u, &stream[pos]); /* length: absurd */
    pos += (unsigned int) enc_varint(1u, &stream[pos]);       /* offset: valid (1) */

    out = guarded_alloc(cap);
    rc = LZ_Uncompress(stream, out, pos, cap, &actual);
    CHECK(rc == -1, "lz overflow: absurd-length back-reference was not rejected");
    CHECK(guard_intact(out, cap), "lz overflow: WROTE PAST THE DECLARED CAPACITY");
    free(out);
}

static void test_lz_offset_underflow(void) {
    /* A back-reference whose offset reaches before anything has been
       produced yet (offset > outpos). No legitimate encoder emits this;
       unchecked, out[outpos-offset] reads/writes before the buffer. */
    unsigned char stream[8], *out;
    unsigned int cap = 64, actual, pos = 0;
    int rc;

    stream[pos++] = 0x00;   /* marker */
    stream[pos++] = 0x00;   /* token: marker byte */
    stream[pos++] = 0x01;   /* not 0 -> length/offset follow */
    pos += (unsigned int) enc_varint(1u, &stream[pos]);  /* length 1 */
    pos += (unsigned int) enc_varint(1u, &stream[pos]);  /* offset 1, but outpos is 0 */

    out = guarded_alloc(cap);
    rc = LZ_Uncompress(stream, out, pos, cap, &actual);
    CHECK(rc == -1, "lz offset-underflow: was not rejected");
    CHECK(actual == 0, "lz offset-underflow: should not have written anything");
    CHECK(guard_intact(out, cap), "lz offset-underflow: guard touched");
    free(out);
}

static void test_lz_truncated_stream(void) {
    /* A length/offset varint whose continuation bit is set on the very
       last byte of the buffer: reading it must stop at 'insize', not walk
       off the end of the compressed-data allocation. */
    unsigned char stream[4], *out;
    unsigned int cap = 64, actual;
    int rc;

    stream[0] = 0x00;  /* marker */
    stream[1] = 0x00;  /* token: marker byte */
    stream[2] = 0x01;  /* not 0 -> length/offset follow */
    stream[3] = 0x80;  /* first byte of a varint, continuation bit set, and nothing after it */

    out = guarded_alloc(cap);
    rc = LZ_Uncompress(stream, out, sizeof(stream), cap, &actual);
    CHECK(rc == -1, "lz truncated-stream: was not rejected");
    CHECK(guard_intact(out, cap), "lz truncated-stream: guard touched");
    free(out);
}

/* ---- RLE_Uncompress -------------------------------------------------- */

static void test_rle_roundtrip(void) {
    unsigned char in[2000], comp[2100], *out;
    unsigned int i, compsize, actual;
    int rc;

    for (i = 0; i < sizeof(in); ++i)
        in[i] = (unsigned char)((i < 1000) ? 7 : (i * 3) & 0xff); /* runs + noise */

    compsize = (unsigned int) RLE_Compress(in, comp, sizeof(in));
    CHECK(compsize > 0, "rle roundtrip: compress produced nothing");

    out = guarded_alloc(sizeof(in));
    rc = RLE_Uncompress(comp, out, compsize, sizeof(in), &actual);
    CHECK(rc == 0, "rle roundtrip: valid stream was rejected");
    CHECK(actual == sizeof(in), "rle roundtrip: actual size wrong");
    CHECK(memcmp(in, out, sizeof(in)) == 0, "rle roundtrip: data mismatch");
    CHECK(guard_intact(out, sizeof(in)), "rle roundtrip: guard touched");
    free(out);
}

static void test_rle_overflow_attempt(void) {
    /* This is the decoder Registry::LoadGroup's default (use_lz=false)
       load path actually runs -- the more exposed of the two. A maximum
       (32768-byte) repeat run into a buffer far too small for it. */
    unsigned char stream[8], *out;
    unsigned int cap = 64, actual;
    int rc;

    stream[0] = 0x00;  /* marker */
    stream[1] = 0x00;  /* token: marker byte */
    stream[2] = 0xFF;  /* count hi, continuation bit set */
    stream[3] = 0xFF;  /* count lo -> count = 32767, run length 32768 */
    stream[4] = 0x41;  /* symbol to repeat */

    out = guarded_alloc(cap);
    rc = RLE_Uncompress(stream, out, 5, cap, &actual);
    CHECK(rc == -1, "rle overflow: 32768-byte run into a 64-byte buffer was not rejected");
    CHECK(guard_intact(out, cap), "rle overflow: WROTE PAST THE DECLARED CAPACITY");
    free(out);
}

static void test_rle_truncated_stream(void) {
    /* count's continuation bit is set (0x80) but the byte after it, and
       the symbol byte after that, are both missing. */
    unsigned char stream[3], *out;
    unsigned int cap = 64, actual;
    int rc;

    stream[0] = 0x00;  /* marker */
    stream[1] = 0x00;  /* token: marker byte */
    stream[2] = 0x80;  /* count hi, continuation bit set, nothing follows */

    out = guarded_alloc(cap);
    rc = RLE_Uncompress(stream, out, sizeof(stream), cap, &actual);
    CHECK(rc == -1, "rle truncated-stream: was not rejected");
    CHECK(guard_intact(out, cap), "rle truncated-stream: guard touched");
    free(out);
}

static void test_rle_reports_short_output(void) {
    unsigned char in[10], comp[32], *out;
    unsigned int i, compsize, actual;
    int rc;

    for (i = 0; i < sizeof(in); ++i) in[i] = (unsigned char)(i + 1);
    compsize = (unsigned int) RLE_Compress(in, comp, sizeof(in));

    out = guarded_alloc(1000);
    rc = RLE_Uncompress(comp, out, compsize, 1000, &actual);
    CHECK(rc == 0, "rle short-output: call should still succeed");
    CHECK(actual == sizeof(in), "rle short-output: actual should be the true (small) count, not the capacity");
    CHECK(guard_intact(out, 1000), "rle short-output: guard touched");
    free(out);
}

int main(int argc, char **argv) {
    if (argc > 1 && strcmp(argv[1], "--selftest") == 0) {
        /* Proves the CHECK()/g_failed machinery itself can fail, the same
           way tools/check_headless.sh's --selftest feeds known-bad input to
           its own assertions. A deliberately wrong expectation: it MUST
           print FAIL and this program MUST exit 1. */
        CHECK(1 == 2, "selftest: deliberately-false assertion (proves the harness can report a failure)");
        return g_failed ? 1 : 0;
    }

    test_lz_roundtrip();
    test_lz_reports_short_output();
    test_lz_overflow_attempt();
    test_lz_offset_underflow();
    test_lz_truncated_stream();

    test_rle_roundtrip();
    test_rle_overflow_attempt();
    test_rle_truncated_stream();
    test_rle_reports_short_output();

    if (g_failed) {
        fprintf(stderr, "\nFAIL: one or more LZ/RLE decoder checks failed -- see above.\n");
        return 1;
    }
    printf("PASS: all LZ_Uncompress/RLE_Uncompress memory-safety checks passed.\n");
    return 0;
}
