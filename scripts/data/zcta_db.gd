class_name ZctaDB
extends RefCounted

## Real ZIP code area boundaries (US Census ZCTAs, public domain), built by tools/build_zcta.py.
## Records are addressed by index; outlines are decoded only for the handful of areas on a map.

const PATH := "res://data/us_zcta.bin"
const ATTRIBUTION := "Boundaries: US Census Bureau"
const HEADER := 12
const RECORD := 24
const Q := 1e-5

static var _data: PackedByteArray
static var _count := 0
static var _nbr_base := 0
static var _geom_base := 0


static func _ensure_loaded() -> bool:
	if _count > 0:
		return true
	var packed := FileAccess.get_file_as_bytes(PATH)
	if packed.is_empty():
		push_error("ZCTA data missing: " + PATH)
		return false
	_data = packed.decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP)
	if _data.slice(0, 4).get_string_from_ascii() != "ZCTA":
		push_error("ZCTA data is corrupt")
		return false
	_count = _data.decode_u32(8)
	var index_end := HEADER + _count * RECORD
	_nbr_base = index_end + 4
	_geom_base = _nbr_base + _data.decode_u32(index_end)
	return true


static func count() -> int:
	return _count if _ensure_loaded() else 0


static func code(i: int) -> String:
	return "%05d" % _data.decode_u32(HEADER + i * RECORD)


## A point guaranteed to be inside the area (good for labels), as Vector2(lon, lat).
static func label_point(i: int) -> Vector2:
	var r := HEADER + i * RECORD
	return Vector2(_data.decode_float(r + 8), _data.decode_float(r + 4))


static func area(i: int) -> float:
	return _data.decode_float(HEADER + i * RECORD + 12)


static func neighbors(i: int) -> PackedInt32Array:
	var p := _nbr_base + _data.decode_u32(HEADER + i * RECORD + 20)
	var out := PackedInt32Array()
	for k in _data.decode_u16(p):
		out.append(_data.decode_u16(p + 2 + k * 2))
	return out


## Outline rings as Vector2(lon, lat) points. Most areas have one ring; islands add more.
static func parts(i: int) -> Array[PackedVector2Array]:
	var p := _geom_base + _data.decode_u32(HEADER + i * RECORD + 16)
	var out: Array[PackedVector2Array] = []
	var n_parts := _data.decode_u16(p)
	p += 2
	for k in n_parts:
		var n := _data.decode_u16(p)
		var lat := _data.decode_s32(p + 2)
		var lon := _data.decode_s32(p + 6)
		p += 10
		var ring := PackedVector2Array()
		ring.resize(n)
		ring[0] = Vector2(lon * Q, lat * Q)
		for j in range(1, n):
			lat += _data.decode_s16(p)
			lon += _data.decode_s16(p + 2)
			p += 4
			ring[j] = Vector2(lon * Q, lat * Q)
		out.append(ring)
	return out


## Index of the area with exactly this ZIP code, or -1.
static func index_of(zip: String) -> int:
	if not _ensure_loaded():
		return -1
	var target := zip.to_int()
	var lo := 0
	var hi := _count - 1
	while lo <= hi:
		var mid := (lo + hi) / 2
		var c := _data.decode_u32(HEADER + mid * RECORD)
		if c == target:
			return mid
		if c < target:
			lo = mid + 1
		else:
			hi = mid - 1
	return -1


## Index of the area for a ZIP: its own ZCTA if it has one (PO-box ZIPs don't), else the nearest.
static func find(zip: String, lat: float, lon: float) -> int:
	var exact := index_of(zip)
	return exact if exact >= 0 else nearest(lat, lon)


static func nearest(lat: float, lon: float, exclude := {}) -> int:
	var cos_lat := cos(deg_to_rad(lat))
	var best := -1
	var best_d := INF
	for i in _count:
		if exclude.has(i):
			continue
		var r := HEADER + i * RECORD
		var dx := (_data.decode_float(r + 8) - lon) * cos_lat
		var dy := _data.decode_float(r + 4) - lat
		var d := dx * dx + dy * dy
		if d < best_d:
			best_d = d
			best = i
	return best


## Grows a connected region of `count` areas outward from `home`, always taking the closest
## bordering area next. Water and islands can cut a region off; then the nearest area anywhere is
## added and linked to its closest pick (a bridge or ferry). Returns {indices, links} where links
## are extra [a, b] index pairs that aren't real shared borders.
static func grow(home: int, count: int) -> Dictionary:
	var origin := label_point(home)
	var cos_lat := cos(deg_to_rad(origin.y))
	var dist := func(i: int) -> float:
		var d := (label_point(i) - origin) * Vector2(cos_lat, 1.0)
		return d.length_squared()
	var picked := {home: true}
	var order: Array[int] = [home]
	var links: Array = []
	var frontier := {}
	for n in neighbors(home):
		frontier[n] = true
	while order.size() < count:
		var next := -1
		var next_d := INF
		for f in frontier:
			var d: float = dist.call(f)
			if d < next_d:
				next_d = d
				next = f
		if next < 0:
			next = nearest(origin.y, origin.x, picked)
			if next < 0:
				break
			var closest := order[0]
			for o in order:
				if label_point(o).distance_squared_to(label_point(next)) < label_point(closest).distance_squared_to(label_point(next)):
					closest = o
			links.append([closest, next])
		frontier.erase(next)
		picked[next] = true
		order.append(next)
		for n in neighbors(next):
			if not picked.has(n):
				frontier[n] = true
	return {"indices": order, "links": links}
