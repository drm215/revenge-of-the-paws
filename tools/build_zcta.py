"""Builds the ZIP area data (tools/zcta_format.py) from the US Census ZIP Code Tabulation Areas.

Source (public domain): https://www2.census.gov/geo/tiger/GENZ2020/shp/cb_2020_us_zcta520_500k.zip
Needs: pip install shapely pyshp

    python tools/build_zcta.py path/to/cb_2020_us_zcta520_500k.shp

Coordinates are quantized to 1e-5 degrees (~1 m); long segments are split so deltas fit in i16.
"""
import struct
import sys

import shapefile
from shapely.geometry import MultiPolygon, Polygon, shape
from shapely.strtree import STRtree

import zcta_format

SIMPLIFY_DEG = 0.0008   # ~80 m: invisible at map scale, keeps the file small
TOUCH_DEG = 0.0005      # areas closer than ~50 m count as sharing a border
Q = 1e5                 # quantization: 1e-5 degrees
MAX_DELTA = 32000


def parts_of(geom):
    if isinstance(geom, Polygon):
        return [geom]
    if isinstance(geom, MultiPolygon):
        return list(geom.geoms)
    return []


def encode_ring(coords):
    pts = [(round(lat * Q), round(lon * Q)) for lon, lat in coords[:-1]]  # drop closing point
    out = [pts[0]]
    for lat, lon in pts[1:]:
        plat, plon = out[-1]
        steps = max(1, -(-max(abs(lat - plat), abs(lon - plon)) // MAX_DELTA))
        for k in range(1, steps + 1):
            out.append((plat + (lat - plat) * k // steps, plon + (lon - plon) * k // steps))
    body = struct.pack("<Hii", len(out), *out[0])
    for (alat, alon), (blat, blon) in zip(out, out[1:]):
        body += struct.pack("<hh", blat - alat, blon - alon)
    return body


def main(path):
    reader = shapefile.Reader(path)
    fields = [f[0] for f in reader.fields[1:]]
    code_field = next(f for f in fields if f.startswith("ZCTA5"))
    records = []
    for sr in reader.iterShapeRecords():
        geom = shape(sr.shape.__geo_interface__)
        if geom.is_empty:
            continue
        if not geom.is_valid:
            geom = geom.buffer(0)
        records.append((int(sr.record[code_field]), geom))
    records.sort(key=lambda r: r[0])
    print(f"{len(records)} ZCTAs", file=sys.stderr)

    geoms = [g for _, g in records]
    tree = STRtree(geoms)
    neighbors = [[] for _ in records]
    for i, g in enumerate(geoms):
        for j in tree.query(g.buffer(TOUCH_DEG), predicate="intersects"):
            if j != i:
                neighbors[i].append(int(j))
        if i % 5000 == 0:
            print(f"  adjacency {i}", file=sys.stderr)

    out = []
    total_pts = 0
    for i, (code, g) in enumerate(records):
        label = g.representative_point()
        simple = g.simplify(SIMPLIFY_DEG, preserve_topology=True)
        parts = [p for p in parts_of(simple) if len(p.exterior.coords) >= 4]
        if not parts:
            parts = [p for p in parts_of(g) if len(p.exterior.coords) >= 4]
        geometry = bytearray(struct.pack("<H", len(parts)))
        for p in parts:
            ring = encode_ring(list(p.exterior.coords))
            total_pts += struct.unpack_from("<H", ring)[0]
            geometry += ring
        out.append((code, label.y, label.x, g.area, bytes(geometry), neighbors[i]))
    zcta_format.write(out)
    print(f"{total_pts} points", file=sys.stderr)


if __name__ == "__main__":
    main(sys.argv[1])
