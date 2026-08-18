import glob, re, sys
pw = 0; inv = 0; oob = 0; ro = 0; gave = 0; n = 0
for root in sys.argv[1:]:
    for f in glob.glob(root + "/seed-*/logs/oobprobe.log"):
        n += 1
        for line in open(f, errors="replace"):
            if line.startswith("PLACEWITHIN calls="):
                m = re.search(r"calls=(\d+) returned_inverted=(\d+)", line)
                pw += int(m.group(1)); inv += int(m.group(2))
            elif line.startswith("CENSUS "):
                oob += int(re.search(r"out_of_bounds_At_calls=(\d+)", line).group(1))
            elif line.startswith("RECTS "):
                m = re.search(r"random_open_calls=(\d+) inverted=(\d+) gave_up=(\d+)", line)
                ro += int(m.group(1)); gave += int(m.group(3))
print("logs                 %d" % n)
print("PlaceWithinSafely    %d calls, %d returned inverted" % (pw, inv))
print("out-of-bounds reads  %d" % oob)
print("decorator calls      %d, gave up %d" % (ro, gave))
