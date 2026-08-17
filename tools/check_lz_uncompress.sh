#!/bin/bash
# Regression check for the LZ77/RLE decoder hardening (src/lz.c, src/rle.c,
# src/Term.cpp, src/Registry.cpp -- bd inc-l0t).
#
# What it protects. Before inc-l0t, loading a save or module ran a
# decompressor that was told the size of its INPUT but never the capacity of
# its OUTPUT buffer: how many bytes it wrote was decided entirely by the
# content of the (possibly corrupt or hostile) compressed stream. A save file
# and a .Mod are files on disk the game merely trusts -- this is input
# validation at a trust boundary. If that protection ever regresses -- a
# refactor drops the outsize parameter, a bound check gets "simplified" away,
# a future change to lz.c/rle.c forgets to carry it forward -- this must fail
# loudly, not quietly start overflowing again.
#
# How it checks. Compiles tools/lz_uncompress_selftest.c together with the
# real src/lz.c and src/rle.c (not a copy, not a reimplementation) under
# UBSan, and runs it. That harness allocates each output buffer with a guard
# region right after the declared capacity, fills the whole thing with a
# canary byte, and asserts the guard is untouched after feeding the decoder a
# stream engineered to write past capacity -- proof nothing was written past
# the buffer, not just that an error code came back. See the harness's own
# header comment for why this doesn't depend on AddressSanitizer (it deadlocks
# in its own initializer on this machine; bd notes, 2026-08-16).
#
# This is the unit-level half of inc-l0t's verification: it proves the two
# decoder primitives are safe in isolation. tools/check_load_corrupt.sh is the
# integration-level half -- it drives the real game binary against hand-
# corrupted save files (bad compSize/groupSize headers, truncation) to prove
# the whole load path rejects them cleanly.
#
# Usage: tools/check_lz_uncompress.sh              (exits 0 on pass, 1 on fail)
#        tools/check_lz_uncompress.sh --selftest    (proves the harness can fail)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/incursion-lzcheck.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

BIN="$WORK/lz_uncompress_selftest"

CC="${CC:-cc}"
# -fsanitize=undefined: the sanitizer this project can actually use on this
# machine (see tools/lz_uncompress_selftest.c's header comment). -g so a
# failure's stack trace is readable.
if ! "$CC" -std=c99 -Wall -fsanitize=undefined -g -o "$BIN" \
        tools/lz_uncompress_selftest.c src/lz.c src/rle.c 2> "$WORK/build.log"; then
    echo "FAIL: could not build the LZ/RLE selftest harness" >&2
    cat "$WORK/build.log" >&2
    exit 1
fi

if [ "${1:-}" = "--selftest" ]; then
    if "$BIN" --selftest > "$WORK/selftest.out" 2>&1; then
        echo "FAIL: --selftest's deliberately-false assertion did not make the harness fail"
        cat "$WORK/selftest.out"
        exit 1
    fi
    if ! grep -q "deliberately-false assertion" "$WORK/selftest.out"; then
        echo "FAIL: harness failed for the wrong reason:"
        cat "$WORK/selftest.out"
        exit 1
    fi
    echo "PASS: the harness's own FAIL path fires on a known-bad assertion."
    exit 0
fi

if "$BIN"; then
    echo "PASS: LZ_Uncompress/RLE_Uncompress reject every corrupt/overflow"
    echo "      stream tried, without writing past their declared output"
    echo "      capacity, and still decompress ordinary data correctly."
    exit 0
else
    echo "FAIL: see above -- a decoder either accepted a corrupt/overflow"
    echo "      stream it should have rejected, or wrote past its declared"
    echo "      output capacity. This is the defect inc-l0t fixed."
    exit 1
fi
