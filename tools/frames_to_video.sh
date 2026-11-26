#!/bin/bash
# inc-jw0hw: turn recorder frames (INCURSION_FRAMES) into an mp4.
#   frames_to_video.sh <clipdir> <out.mp4>
#   frames_to_video.sh --pair <offdir> <ondir> <out.mp4>
# --pair labels default to 'light off' / 'light on'; PAIR_LABELS='Normal|Fast' replaces them. When the two sides differ in length,
# the shorter holds its last frame to the longer's length (hstack with shortest=0 repeats the last frame at end of stream).
# <clipdir> holds f00000.bmp, f00001.bmp, ... at 33 ms each (30 fps).
FFMPEG=/opt/homebrew/bin/ffmpeg
SCALE='scale=trunc(iw/2)*2:trunc(ih/2)*2'
die() { echo "frames_to_video.sh: $*" >&2; exit 1; }
need_dir() { [ -d "$1" ] || die "no such clip dir: $1"; ls "$1"/f*.bmp >/dev/null 2>&1 || die "no frames in: $1"; }
[ -x "$FFMPEG" ] || die "ffmpeg not found at $FFMPEG"
if [ "$1" = "--pair" ]; then
    [ $# -eq 4 ] || die "usage: --pair <offdir> <ondir> <out.mp4>"
    off=$2; on=$3; out=$4
    LL=${PAIR_LABELS%%|*}; RL=${PAIR_LABELS#*|}
    [ -n "${PAIR_LABELS:-}" ] && [ "$LL" != "$PAIR_LABELS" ] || { LL='light off'; RL='light on'; }
    need_dir "$off"; need_dir "$on"
    if "$FFMPEG" -hide_banner -filters 2>/dev/null | grep -q ' drawtext '; then
        fc="[0:v]drawtext=text='$LL':x=10:y=10:fontcolor=white:box=1:boxcolor=black@0.6[a];[1:v]drawtext=text='$RL':x=10:y=10:fontcolor=white:box=1:boxcolor=black@0.6[b];[a][b]hstack=shortest=0,$SCALE"
    else
        echo "frames_to_video.sh: this ffmpeg has no drawtext; the pair has no labels" >&2
        fc="[0:v][1:v]hstack=shortest=0,$SCALE"
    fi
    "$FFMPEG" -loglevel error -y -framerate 30 -i "$off/f%05d.bmp" -framerate 30 -i "$on/f%05d.bmp" \
        -filter_complex "$fc" -c:v libx264 -pix_fmt yuv420p "$out" || die "ffmpeg failed"
else
    [ $# -eq 2 ] || die "usage: <clipdir> <out.mp4>"
    need_dir "$1"
    "$FFMPEG" -loglevel error -y -framerate 30 -i "$1/f%05d.bmp" -vf "$SCALE" \
        -c:v libx264 -pix_fmt yuv420p "$2" || die "ffmpeg failed"
fi
[ -s "${out:-$2}" ] || die "no output written"
