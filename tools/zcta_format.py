"""Writes the ZIP area data the game reads (scripts/data/zcta_db.gd).

data/us_zcta_core.bin (gzip, little-endian), always in the game:
    "ZCTA" u32 version u32 count
    count x index record (24 bytes, sorted by code):
        u32 code, f32 label_lat, f32 label_lon, f32 area_deg2, u32 geom_offset, u32 nbr_offset
    u32 neighbor blob size, neighbor blob:  u16 n, n x u16 record index

data/zcta/<first 3 digits of the ZIP>.bin (gzip), fetched when a map needs it:
    "ZSHD" u32 version u32 size, geometry blob:
        u16 parts, per part: u16 points, i32 lat, i32 lon, (points-1) x (i16 dlat, i16 dlon)
    geom_offset counts from the start of that file's blob.

Bump VERSION (and ZctaDB.VERSION) when the data changes, so devices fetch the new outlines.
"""
import gzip
import struct
from collections import defaultdict
from pathlib import Path

VERSION = 2
ROOT = Path(__file__).resolve().parent.parent


def write(records) -> None:
    """`records`: sorted by code; each (code, lat, lon, area, geometry bytes, neighbor list)."""
    index = bytearray()
    neighbors = bytearray()
    shards = defaultdict(bytearray)
    for code, lat, lon, area, geometry, near in records:
        shard = shards[("%05d" % code)[:3]]
        index += struct.pack("<IfffII", code, lat, lon, area, len(shard), len(neighbors))
        shard += geometry
        neighbors += struct.pack("<H", len(near)) + b"".join(struct.pack("<H", n) for n in near)
    core = b"ZCTA" + struct.pack("<II", VERSION, len(records)) + bytes(index)
    core += struct.pack("<I", len(neighbors)) + bytes(neighbors)
    # mtime=0: the same data makes the same bytes, so unchanged files don't look new to git or browsers.
    (ROOT / "data" / "us_zcta_core.bin").write_bytes(gzip.compress(core, 9, mtime=0))
    folder = ROOT / "data" / "zcta"
    folder.mkdir(exist_ok=True)
    for old in folder.glob("*.bin"):
        old.unlink()
    for name, blob in shards.items():
        body = b"ZSHD" + struct.pack("<II", VERSION, len(blob)) + bytes(blob)
        (folder / f"{name}.bin").write_bytes(gzip.compress(body, 9, mtime=0))
