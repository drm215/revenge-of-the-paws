class_name ZipDB
extends RefCounted

## Offline US ZIP code lookup (GeoNames data, CC BY 4.0). Loaded once on first use.

const PATH := "res://data/us_zips.csv"
const ATTRIBUTION := "ZIP code data © GeoNames (geonames.org), CC BY 4.0"

const STATE_REGIONS := {
	"us_new_england": ["ME", "NH", "VT", "MA", "RI", "CT"],
	"us_mid_atlantic": ["NY", "NJ", "PA", "DE", "MD", "DC"],
	"us_appalachia": ["VA", "WV", "KY", "TN"],
	"us_carolinas": ["NC", "SC", "GA"],
	"us_florida": ["FL"],
	"us_gulf_south": ["AL", "MS", "LA", "AR"],
	"us_great_lakes": ["OH", "MI", "IN", "IL", "WI", "MN"],
	"us_plains": ["IA", "MO", "ND", "SD", "NE", "KS"],
	"us_texas": ["TX", "OK"],
	"us_desert": ["AZ", "NM", "NV"],
	"us_rockies": ["CO", "UT", "WY", "MT", "ID"],
	"us_pacific_nw": ["WA", "OR"],
	"us_california": ["CA"],
	"us_alaska": ["AK"],
	"us_hawaii": ["HI", "MH"],
}

static var _zips: PackedStringArray
static var _places: PackedStringArray
static var _states: PackedStringArray
static var _lat: PackedFloat32Array
static var _lon: PackedFloat32Array
static var _index := {}  # zip -> row


static func _ensure_loaded() -> void:
	if not _index.is_empty():
		return
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		push_error("ZIP data missing: " + PATH)
		return
	while not f.eof_reached():
		var line := f.get_line()
		if line.is_empty() or line.begins_with("#"):
			continue
		var p := line.split(",")
		_index[p[0]] = _zips.size()
		_zips.append(p[0])
		_places.append(p[1])
		_states.append(p[2])
		_lat.append(p[3].to_float())
		_lon.append(p[4].to_float())


## {zip, place, state, lat, lon, region} or {} if unknown.
static func lookup(zip: String) -> Dictionary:
	_ensure_loaded()
	if not _index.has(zip):
		return {}
	return _row(_index[zip])


static func region_for_state(state: String) -> String:
	for region_id in STATE_REGIONS:
		if state in STATE_REGIONS[region_id]:
			return region_id
	return "us_mid_atlantic"


## The `count` ZIPs closest to `zip` (including it), skipping ones that sit on the same spot.
static func nearest(zip: String, count: int) -> Array[Dictionary]:
	_ensure_loaded()
	var home := lookup(zip)
	if home.is_empty():
		return []
	var cos_lat := cos(deg_to_rad(home.lat))
	var dist := PackedFloat32Array()
	dist.resize(_zips.size())
	for i in _zips.size():
		var dx: float = (_lon[i] - home.lon) * cos_lat
		var dy: float = _lat[i] - home.lat
		dist[i] = dx * dx + dy * dy
	var order := range(_zips.size())
	order.sort_custom(func(a: int, b: int) -> bool: return dist[a] < dist[b])

	var out: Array[Dictionary] = [home]
	var min_gap := 0.004  # ~400 m; PO-box ZIPs often share a point with a real one
	for i: int in order:
		if out.size() >= count:
			break
		if _zips[i] == zip:
			continue
		var ok := true
		for o in out:
			var dx: float = (_lon[i] - o.lon) * cos_lat
			var dy: float = _lat[i] - o.lat
			if dx * dx + dy * dy < min_gap * min_gap:
				ok = false
				break
		if ok:
			out.append(_row(i))
	return out


## The closest known ZIP row to a point (for ZIP areas missing from the GeoNames list).
static func row_near(lat: float, lon: float) -> Dictionary:
	_ensure_loaded()
	var cos_lat := cos(deg_to_rad(lat))
	var best := 0
	var best_d := INF
	for i in _zips.size():
		var dx := (_lon[i] - lon) * cos_lat
		var dy := _lat[i] - lat
		if dx * dx + dy * dy < best_d:
			best_d = dx * dx + dy * dy
			best = i
	return _row(best)


static func _row(i: int) -> Dictionary:
	return {
		"zip": _zips[i], "place": _places[i].capitalize() if _places[i] == _places[i].to_upper() else _places[i],
		"state": _states[i], "lat": _lat[i], "lon": _lon[i], "region": region_for_state(_states[i]),
	}
