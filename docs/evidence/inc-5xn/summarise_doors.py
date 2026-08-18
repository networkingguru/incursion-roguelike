import glob, os, re, sys
root = sys.argv[1]
tot = dict(sessions=0, calls=0, rawoob=0, silent=0, built=0, blocked=0, outside=0,
           sessions_with_built=0, no_log=0)
for d in sorted(glob.glob(os.path.join(root, "seed-*/"))):
    log = os.path.join(d, "logs", "oobprobe.log")
    tot["sessions"] += 1
    if not os.path.exists(log):
        tot["no_log"] += 1
        continue
    last = None
    for line in open(log, errors="replace"):
        if line.startswith("DOORS "):
            last = line
    if not last:
        continue
    m = dict(re.findall(r"(\w+)=(-?\d+)", last))
    tot["calls"]  += int(m.get("calls", 0))
    tot["rawoob"] += int(m.get("raw_out_of_bounds", 0))
    tot["silent"] += int(m.get("silently_placed_in_bounds", 0))
    b = int(m.get("built", 0))
    tot["built"]   += b
    tot["blocked"] += int(m.get("blocked_by_existing_feature", 0))
    tot["outside"] += int(m.get("outside_intended_room", 0))
    if b:
        tot["sessions_with_built"] += 1
for k in ("sessions","no_log","calls","rawoob","silent","built","blocked","outside","sessions_with_built"):
    print("%-20s %d" % (k, tot[k]))
