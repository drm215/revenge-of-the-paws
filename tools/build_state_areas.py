"""Counts the ZIP areas (ZCTAs) in each US state into data/state_areas.json, for "clear a state".

    python tools/build_state_areas.py

A ZIP area's state is decided exactly as the game decides it (Campaign._state_of): its own ZIP's row
in the ZIP table, or else the nearest ZIP's row to its label point (ZipDB.row_near).
"""
import gzip
import json
import math
import struct
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def main() -> None:
    rows = []
    by_zip = {}
    for line in gzip.open(ROOT / "data" / "us_zips.gz").read().decode("utf-8").splitlines():
        if not line or line.startswith("#"):
            continue
        z, _place, state, lat, lon = line.split(",")[:5]
        by_zip.setdefault(z, state)
        rows.append((struct.unpack("f", struct.pack("f", float(lat)))[0], struct.unpack("f", struct.pack("f", float(lon)))[0], state))
    core = gzip.open(ROOT / "data" / "us_zcta_core.bin").read()
    count = struct.unpack_from("<I", core, 8)[0]
    states = Counter()
    for i in range(count):
        code, lat, lon = struct.unpack_from("<Iff", core, 12 + i * 24)
        state = by_zip.get("%05d" % code)
        if state is None:
            cos_lat = math.cos(math.radians(lat))
            best, best_d = None, math.inf
            for zlat, zlon, zstate in rows:
                dx = (zlon - lon) * cos_lat
                dy = zlat - lat
                d = dx * dx + dy * dy
                if d < best_d:
                    best_d, best = d, zstate
            state = best
        states[state] += 1
    out = ROOT / "data" / "state_areas.json"
    out.write_text(json.dumps(dict(sorted(states.items())), indent=0) + "\n", encoding="utf-8")
    print(f"{sum(states.values())} ZIP areas in {len(states)} states -> {out}")
    print(", ".join(f"{s} {n}" for s, n in sorted(states.items())))


if __name__ == "__main__":
    main()
