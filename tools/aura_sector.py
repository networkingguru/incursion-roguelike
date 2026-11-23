#!/usr/bin/env python3
import sys, math
sys.path.insert(0, "tools")
import bmp_pixel as B
# tools/aura_sector.py <before.bmp> <after.bmp> <cx> <cy> <r0> <r1> [<a0> <a1>]: mean purpleness (red+blue)/2 - green, after minus before, over the
# pixels with r0 <= distance < r1 from (cx,cy) and angle a0..a1 degrees (default -30..10: east, away from aura B on the west and the wall in the south-east).
# Used by tools/check_aura_circle.sh. Stdlib only; exit 2 when the sector holds no pixel.
bf, af = sys.argv[1:3]
cx, cy = int(sys.argv[3]), int(sys.argv[4])
r0, r1 = float(sys.argv[5]), float(sys.argv[6])
a0, a1 = (float(sys.argv[7]), float(sys.argv[8])) if len(sys.argv) > 8 else (-30.0, 10.0)
w, h, gb = B.read_bmp(bf); _, _, ga = B.read_bmp(af)
p = lambda c: (c[0] + c[2]) / 2.0 - c[1]
s = n = 0
for y in range(int(cy - r1) - 1, int(cy + r1) + 2):
    for x in range(int(cx - r1) - 1, int(cx + r1) + 2):
        if not (0 <= x < w and 0 <= y < h): continue
        d = math.hypot(x - cx, y - cy)
        if not (r0 <= d < r1): continue
        ang = math.degrees(math.atan2(y - cy, x - cx))
        if not (a0 <= ang <= a1): continue
        s += p(ga(x, y)) - p(gb(x, y)); n += 1
if n == 0: sys.exit(2)
print(round(s / n, 1))
