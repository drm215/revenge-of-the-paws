class_name ZctaDB
extends RefCounted

## Real ZIP code area boundaries (US Census ZCTAs, public domain), built by tools/build_zcta.py.
## Records are addressed by index. The index and neighbors (all game rules need) are always in the
## game. Outlines (only the map's drawing needs them, so they may arrive late without changing any
## result) live in one file per ZIP prefix: part of a desktop run, fetched once on the web and then
## kept on the device. See tools/zcta_format.py.

const PATH := "res://data/us_zcta_core.bin"
const SHARDS := "res://data/zcta/"
const ATTRIBUTION := "Boundaries: US Census Bureau"
const VERSION := 2
const HEADER := 12
const RECORD := 24
const Q := 1e-5

## Where outlines are fetched from ("" = next to the web page); tests use a fake server.
static var base_url := ""
static var use_bundled := true  # off in tests of fetching: pretend this is a web build
static var _data: PackedByteArray
static var _count := 0
static var _nbr_base := 0
static var _shards := {}  # ZIP prefix -> that file's outlines, once loaded


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


## The outline file area `i` is in: the first 3 digits of its ZIP.
static func shard_of(i: int) -> String:
	return code(i).left(3)


## True once area `i`'s outline can be read right now.
static func has_parts(i: int) -> bool:
	return not _shard(shard_of(i)).is_empty()


static func _cache_path(shard: String) -> String:
	return "user://zcta/%d/%s.bin" % [VERSION, shard]


## An outline file's contents: already loaded, or from the game or this device's copy; else empty.
static func _shard(shard: String) -> PackedByteArray:
	if _shards.has(shard):
		return _shards[shard]
	for file: String in ([SHARDS + shard + ".bin"] if use_bundled else []) + [_cache_path(shard)]:
		if FileAccess.file_exists(file):
			var body := _unpack(FileAccess.get_file_as_bytes(file))
			if not body.is_empty():
				_shards[shard] = body
				return body
	return PackedByteArray()


## An outline file's blob, or empty if these bytes aren't a whole file of this version.
static func _unpack(packed: PackedByteArray) -> PackedByteArray:
	if packed.size() < 20 or packed[0] != 0x1f or packed[1] != 0x8b:
		return PackedByteArray()
	var body := packed.decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP)
	if body.size() < 12 or body.slice(0, 4).get_string_from_ascii() != "ZSHD" or body.decode_u32(4) != VERSION \
			or body.decode_u32(8) != body.size() - 12:
		return PackedByteArray()
	return body.slice(12)


## Fetches an outline file and keeps it on this device. True once it's readable. `host` is any node
## in the tree, to carry the request.
static func download(shard: String, host: Node) -> bool:
	if not _shard(shard).is_empty():
		return true
	var http := HTTPRequest.new()
	http.timeout = 20.0
	http.accept_gzip = false  # browsers already unpack compressed replies; Godot unpacking again fails
	host.add_child(http)
	if http.request(_shard_url(shard)) != OK:
		http.queue_free()
		return false
	var res: Array = await http.request_completed
	http.queue_free()
	if res[0] != HTTPRequest.RESULT_SUCCESS or res[1] != 200:
		return false
	var body := _unpack(res[3])
	if body.is_empty():
		return false
	_shards[shard] = body
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_cache_path(shard).get_base_dir()))
	var file := FileAccess.open(_cache_path(shard), FileAccess.WRITE)
	if file:
		file.store_buffer(res[3])
	return true


static func _shard_url(shard: String) -> String:
	var base := base_url
	if base == "" and OS.has_feature("web"):
		var page := str(JavaScriptBridge.eval("window.location.origin + window.location.pathname", true))
		base = page.left(page.rfind("/"))
	return "%s/zcta/%s.bin" % [base, shard]


## Outline rings as Vector2(lon, lat) points. Most areas have one ring; islands add more. Empty
## until the area's outline file is here (see has_parts and download).
static func parts(i: int) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	var blob := _shard(shard_of(i))
	if blob.is_empty():
		return out
	var p := _data.decode_u32(HEADER + i * RECORD + 16)
	var n_parts := blob.decode_u16(p)
	p += 2
	for k in n_parts:
		var n := blob.decode_u16(p)
		var lat := blob.decode_s32(p + 2)
		var lon := blob.decode_s32(p + 6)
		p += 10
		var ring := PackedVector2Array()
		ring.resize(n)
		ring[0] = Vector2(lon * Q, lat * Q)
		for j in range(1, n):
			lat += blob.decode_s16(p)
			lon += blob.decode_s16(p + 2)
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
