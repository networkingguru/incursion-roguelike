import glob, re, sys
tot = {"lines":0, "x1":0, "y1":0, "x2":0, "y2":0}
for root in sys.argv[1:]:
    for f in glob.glob(root + "/seed-*/logs/oobprobe.log"):
        for line in open(f, errors="replace"):
            if not line.startswith("PWS_SHORT"):
                continue
            tot["lines"] += 1
            m = re.search(r"fired: x1=(\S+) y1=(\S+) x2=(\S+) y2=(\S+)", line)
            for k, v in zip(("x1","y1","x2","y2"), m.groups()):
                if v == "YES":
                    tot[k] += 1
for k in ("lines","x1","y1","x2","y2"):
    print("%-6s %d" % (k, tot[k]))
