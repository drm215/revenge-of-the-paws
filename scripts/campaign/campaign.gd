class_name Campaign
extends RefCounted

## Risk-style conquest of the area around the player's home: which territories you hold, how
## dangerous the rest are, zombie counterattacks, and saving progress. On real (ZIP) maps the
## frontier grows: liberating an edge territory reveals the real ZIP areas beyond it.

const SAVE_PATH := "user://campaign.cfg"
const TERRITORY_COUNT := 40
const MAX_RECRUITS := 8
const TRINKET_SOURCES := 3  # lairs + caches per map
const FRONTIER_RECRUIT_CHANCE := 0.25
const FRONTIER_CACHE_CHANCE := 0.12
const KM_PER_DEG := 111.2
const KM_PER_DEG_LAT := 110.57
const KM_PER_DEG_LON := 111.32

## District names for players outside the US (no ZIP data).
const DISTRICT_NAMES := [
	"Old Town", "Riverside", "Hilltop", "Market Square", "Rail Yard", "Northgate", "Mill Creek",
	"Harbor", "Oak Park", "Stadium", "Fairgrounds", "Pine Hollow", "Industrial Park", "Lakeview",
	"University", "Cedar Heights", "Water Works", "Old Quarry", "Southside", "Orchard Lane",
	"Hospital Hill", "Junkyard", "Bridgewater", "Eastwood", "Chapel Green", "Westfield",
]

var territories: Array[Territory] = []
var home := 0
var turn := 0
var under_attack := -1  # territory index the horde is attacking, or -1
var last_event := ""
var uses_zip_data := false
var legends: Array[String] = []  # legend ids with a lair on this map
var profile: Profile
var claimed: Array[String] = []  # territory ids whose trinket was already taken
var revealed: Array = []  # batches of ZIP codes added beyond the starting map, in order
var base_count := 0  # territories on the starting map

## Tests point this somewhere else so they never touch the player's real save.
static var save_path := SAVE_PATH

var _key := ""
var _origin := Vector2.ZERO  # home (lon, lat) for real maps
var _scale := Vector2.ONE  # degrees -> km
var _rng := RandomNumberGenerator.new()
var _base_far := 1.0  # km from home to the edge of the starting map; threat 5 there
var _slot := {}  # ZIP area index -> territory index
var _area_of: Array[int] = []  # territory index -> ZIP area index


static func create(profile: Profile) -> Campaign:
	var c := Campaign.new()
	c.profile = profile
	c._key = profile.home_key()
	c._rng.seed = hash(c._key)
	if profile.zip != "":
		c._build_from_zips(profile.zip)
	if c.territories.is_empty():
		c._build_generated(profile)
		MapBuilder.spread(c.territories, c.home)
		MapBuilder.build(c.territories)
	c._assign_threat()
	c._place_lairs(profile)
	c._place_recruits(profile)
	c._place_caches()
	c.territories[c.home].owned = true
	c.base_count = c.territories.size()
	c._load()
	c._catch_up_frontier()
	return c


func owned_count() -> int:
	var n := 0
	for t in territories:
		if t.owned:
			n += 1
	return n


func is_liberated() -> bool:
	return owned_count() == territories.size()


## Map turns between zombie counterattacks; a guard on bench duty buys time.
func counter_interval() -> int:
	return GameData.COUNTERATTACK_EVERY + (GameData.GUARD_COUNTER_DELAY if profile.duties.has("guard") else 0)


## A territory's condition: night raids now and then, city ZIPs are streets, otherwise the
## region's terrain mix. Seeded by the territory, so it never changes.
static func condition_for(t: Territory, area_km2: float) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(t.id + ":condition")
	if rng.randf() < GameData.NIGHT_RAID_CHANCE:
		return "night"
	if area_km2 > 0.0 and area_km2 < GameData.URBAN_MAX_KM2:
		return "urban"
	var weights: Dictionary = GameData.REGION_TERRAIN.get(t.region, {"forest": 1})
	var total := 0
	for k in weights:
		total += weights[k]
	var roll := rng.randi_range(1, total)
	for k in weights:
		roll -= weights[k]
		if roll <= 0:
			return k
	return "forest"


## True if liberating territory `i` would reveal more of the map.
func has_frontier(i: int) -> bool:
	if not uses_zip_data:
		return false
	for n in ZctaDB.neighbors(_area_of[i]):
		if not _slot.has(n):
			return true
	return false


func held_bonus() -> float:
	return minf(GameData.MAX_HELD_BONUS, (owned_count() - 1) * GameData.HELD_TERRITORY_BONUS)


func can_attack(i: int) -> bool:
	if territories[i].owned:
		return false
	for n in territories[i].neighbors:
		if territories[n].owned:
			return true
	return false


## What the player may start a battle on right now. A counterattack must be answered first.
func is_actionable(i: int) -> bool:
	return i == under_attack if under_attack >= 0 else can_attack(i)


func territory_level(i: int) -> int:
	return GameData.territory_level(GameData.zombie_mult(territories[i].threat) * territories[i].horde_strength())


## The next fight auto mode takes on its own: a counterattack or neighbor at least AUTO_LEVEL_GAP
## levels below the leader, easiest first. Legend lairs are always left to the player. -1 if none.
func auto_target(leader_level: int) -> int:
	var max_level := leader_level - GameData.AUTO_LEVEL_GAP
	if under_attack >= 0:
		return under_attack if territory_level(under_attack) <= max_level else -1
	var best := -1
	for i in territories.size():
		if can_attack(i) and territories[i].boss == "" and territory_level(i) <= max_level:
			if best < 0 or territory_level(i) < territory_level(best):
				best = i
	return best


func battle_config(i: int) -> Dictionary:
	var t := territories[i]
	var threat := t.threat
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(t.id)  # same zombies every visit, so a retry is a fair rematch
	return {
		"waves": GameData.generate_waves(threat, rng, t.boss),
		"zombie_mult": GameData.zombie_mult(threat) * t.horde_strength(),
		"party_mult": 1.0 + held_bonus(),
		"place": territories[i].full_name(),
		"condition": t.condition,
		"region": t.region,
	}


## An easier fight in a territory you already hold, for XP: one threat level below the territory,
## fresh zombies each time. Nothing on the map changes.
func patrol_config(i: int) -> Dictionary:
	var t := territories[i]
	var threat := maxi(1, t.threat - 1)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(t.id + ":patrol:%d" % turn)
	return {
		"waves": GameData.generate_waves(threat, rng),
		"zombie_mult": GameData.zombie_mult(threat),
		"party_mult": 1.0 + held_bonus(),
		"place": "Patrol: " + t.full_name(),
		"condition": t.condition,
		"region": t.region,
	}


func resolve_patrol(i: int, won: bool) -> void:
	turn += 1
	last_event = ("Patrol cleared the stragglers around %s." if won else "The patrol around %s fell back.") % territories[i].full_name()
	_end_turn()


## Rest at home: injuries heal and fatigue clears, but the map turn passes.
func rest() -> void:
	turn += 1
	profile.injuries.clear()
	profile.fatigue.clear()
	last_event = "The pack rests at home. Injuries healed, everyone refreshed."
	_end_turn()


func _end_turn() -> void:
	if under_attack < 0 and turn % counter_interval() == 0:
		_start_counterattack()
	save()


func resolve_battle(i: int, won: bool) -> void:
	turn += 1
	var t := territories[i]
	if i == under_attack:
		under_attack = -1
		if won:
			last_event = "%s held! The horde falls back." % t.full_name()
		else:
			t.owned = false
			last_event = "%s was overrun. Take it back!" % t.full_name()
	elif won:
		t.owned = true
		last_event = "%s liberated!" % t.full_name()
		if t.boss != "":
			last_event = "The %s is defeated! %s is free." % [GameData.LEGENDS[t.boss].name, t.full_name()]
		var loot := loot_at(i)
		if loot != "":
			profile.trinkets.append(loot)
			claimed.append(t.id)
			last_event += "\nFound the %s! Equip it from Pack." % GameData.TRINKETS[loot].name
		if t.recruit != "" and not profile.unlock([t.recruit]).is_empty():
			last_event += "\nRescued: %s joined the pack at Lv %d! Swap it in from Pack." % [
				GameData.ANIMALS[t.recruit].name, profile.level_of(t.recruit)]
		last_event += _reveal_beyond(i)
	else:
		t.failed_attacks += 1
		last_event = "The pack retreated from %s, but thinned the horde there." % t.full_name()
	if under_attack < 0 and turn % counter_interval() == 0:
		_start_counterattack()
	save()


func save() -> void:
	var cfg := ConfigFile.new()
	var owned_ids: Array[String] = []
	for t in territories:
		if t.owned:
			owned_ids.append(t.id)
	cfg.set_value("campaign", "key", _key)
	cfg.set_value("campaign", "owned", Array(owned_ids))
	cfg.set_value("campaign", "turn", turn)
	cfg.set_value("campaign", "claimed", Array(claimed))
	cfg.set_value("campaign", "revealed", revealed)
	var fails := {}
	for t in territories:
		if t.failed_attacks > 0:
			fails[t.id] = t.failed_attacks
	cfg.set_value("campaign", "failed_attacks", fails)
	cfg.set_value("campaign", "under_attack", territories[under_attack].id if under_attack >= 0 else "")
	cfg.save(save_path)
	if save_path == SAVE_PATH:
		SaveHooks.saved()


static func clear_saved() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(save_path) != OK or cfg.get_value("campaign", "key", "") != _key:
		return
	# Rebuild the frontier first: owned ids may include revealed areas.
	for batch: Array in cfg.get_value("campaign", "revealed", []):
		_apply_batch(batch)
		revealed.append(batch)
	var owned_ids: Array = cfg.get_value("campaign", "owned", [])
	var attacked: String = cfg.get_value("campaign", "under_attack", "")
	for i in territories.size():
		territories[i].owned = i == home or territories[i].id in owned_ids
		if territories[i].id == attacked:
			under_attack = i
	turn = cfg.get_value("campaign", "turn", 0)
	claimed.assign(cfg.get_value("campaign", "claimed", []))
	var fails: Dictionary = cfg.get_value("campaign", "failed_attacks", {})
	for t in territories:
		t.failed_attacks = fails.get(t.id, 0)


## Legends that belong to a non-US player's world region.
static func region_legends(p: Profile) -> Array[String]:
	var found: Array[String] = []
	for id in GameData.LEGENDS:
		if p.region in GameData.LEGENDS[id].get("regions", []):
			found.append(id)
	return found


static func _km_between(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
	var dx := (lon2 - lon1) * cos(deg_to_rad((lat1 + lat2) / 2.0))
	return Vector2(dx, lat2 - lat1).length() * KM_PER_DEG


## The trinket still waiting in territory `i` (a lair's legend drop or a cache), or "".
func loot_at(i: int) -> String:
	var t := territories[i]
	if t.id in claimed:
		return ""
	if t.boss != "":
		return GameData.LEGENDS[t.boss].drop
	return t.cache


## Caches of plain trinkets in the most dangerous non-lair territories, so maps with few or no
## legends nearby still give the pack something to wear.
func _place_caches() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(_key + ":caches")
	var spots: Array[int] = []
	for i in territories.size():
		if i != home and territories[i].boss == "" and territories[i].threat >= GameData.MAX_THREAT - 1:
			spots.append(i)
	spots.sort_custom(func(a: int, b: int) -> bool:
		return territories[a].site.length_squared() > territories[b].site.length_squared())
	var count := maxi(1, TRINKET_SOURCES - legends.size())
	for k in mini(count, spots.size()):
		territories[spots[k]].cache = GameData.CACHE_TRINKETS[rng.randi_range(0, GameData.CACHE_TRINKETS.size() - 1)]


## A rescued survivor still waiting in territory `i`, or "" (none, or already in the pack).
func pending_recruit(i: int) -> String:
	var id := territories[i].recruit
	return id if id != "" and id not in profile.unlocked else ""


## Survivors waiting to be rescued: liberate the territory and they join the pack. Candidates are
## native to *that territory's* region, so pushing into a new region brings new animals. Placement
## depends only on the map, not on who's already recruited, so it's stable between launches.
func _place_recruits(p: Profile) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(_key + ":recruits")
	var starters: Array = GameData.REGIONS[p.region].animals
	var order := range(territories.size())
	for k in range(order.size() - 1, 0, -1):
		var j := rng.randi_range(0, k)
		var tmp = order[k]
		order[k] = order[j]
		order[j] = tmp
	var placed := {}
	for i: int in order:
		if placed.size() >= MAX_RECRUITS:
			break
		if i == home or territories[i].boss != "":
			continue
		var region: Dictionary = GameData.REGIONS.get(territories[i].region, {})
		var options := []
		for id in region.get("animals", []) + region.get("recruits", []):
			if id not in starters and not placed.has(id):
				options.append(id)
		if options.is_empty():
			continue
		var pick: String = options[rng.randi_range(0, options.size() - 1)]
		territories[i].recruit = pick
		placed[pick] = true


## ZIP maps: a legend's lair is the real ZIP area of its hometown, and only once the map reaches
## it, so the pack has to expand to find it. Generated (non-US) maps put their region's legend
## on the far edge.
func _place_lairs(p: Profile) -> void:
	if uses_zip_data:
		_place_real_lairs(0)
		return
	var origin := territories[home].site
	for legend_id in Campaign.region_legends(p):
		var best := -1
		var best_d := -1.0
		for i in territories.size():
			var d := territories[i].site.distance_to(origin)
			if i != home and territories[i].boss == "" and d > best_d:
				best_d = d
				best = i
		if best >= 0:
			territories[best].boss = legend_id
			territories[best].threat = GameData.MAX_THREAT
			legends.append(legend_id)


## Puts a lair on any territory (from `first` on) that is a legend's real home ZIP area.
## Returns the legends that just came onto the map.
func _place_real_lairs(first: int) -> Array[String]:
	var added: Array[String] = []
	for legend_id in GameData.LEGENDS:
		if legend_id in legends:
			continue
		var area := Campaign.legend_area(legend_id)
		if area < 0 or not _slot.has(area) or _slot[area] < first:
			continue
		var i: int = _slot[area]
		if i == home:
			# A legend from the player's own ZIP lurks just next door instead.
			i = territories[home].neighbors[0] if not territories[home].neighbors.is_empty() else -1
		if i < 0 or territories[i].boss != "":
			continue
		territories[i].boss = legend_id
		territories[i].threat = maxi(territories[i].threat, GameData.MAX_THREAT)
		legends.append(legend_id)
		added.append(legend_id)
	return added


static var _legend_areas := {}


## The ZIP area containing (nearest to) a legend's real hometown, or -1 if it has none.
static func legend_area(legend_id: String) -> int:
	if not _legend_areas.has(legend_id):
		var legend: Dictionary = GameData.LEGENDS[legend_id]
		_legend_areas[legend_id] = ZctaDB.nearest(legend.lat, legend.lon) if legend.has("lat") and ZctaDB.count() > 0 else -1
	return _legend_areas[legend_id]


## Legends not on the map yet, nearest first: [{id, km, direction}]. Points the pack at them.
func rumors(max_count := 3, max_km := 600.0) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not uses_zip_data:
		return out
	var from := territories[home].lonlat
	for legend_id in GameData.LEGENDS:
		var legend: Dictionary = GameData.LEGENDS[legend_id]
		if legend_id in legends or not legend.has("lat"):
			continue
		var km := _km_between(from.y, from.x, legend.lat, legend.lon)
		if km <= max_km:
			var bearing := Vector2((legend.lon - from.x) * cos(deg_to_rad(from.y)), legend.lat - from.y)
			out.append({"id": legend_id, "km": km, "direction": _compass(bearing)})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.km < b.km)
	return out.slice(0, max_count)


static func _compass(v: Vector2) -> String:
	var names := ["E", "NE", "N", "NW", "W", "SW", "S", "SE"]
	var a := fposmod(atan2(v.y, v.x), TAU)
	return names[int(round(a / (TAU / 8.0))) % 8]


func _start_counterattack() -> void:
	var border: Array[int] = []
	for i in territories.size():
		if i == home or not territories[i].owned:
			continue
		for n in territories[i].neighbors:
			if not territories[n].owned:
				border.append(i)
				break
	if border.is_empty():
		return
	under_attack = border[_rng.randi_range(0, border.size() - 1)]
	last_event += "\nThe horde is attacking %s!" % territories[under_attack].full_name()


## Real map: the player's ZIP area plus the nearest connected ZIP areas, with their true outlines.
func _build_from_zips(zip: String) -> void:
	var info := ZipDB.lookup(zip)
	if info.is_empty():
		return
	var home_area := ZctaDB.find(zip, info.lat, info.lon)
	if home_area < 0:
		return
	var region := ZctaDB.grow(home_area, TERRITORY_COUNT)
	uses_zip_data = true
	_origin = ZctaDB.label_point(home_area)
	_scale = Vector2(cos(deg_to_rad(_origin.y)) * KM_PER_DEG_LON, -KM_PER_DEG_LAT)
	var indices: Array[int] = []
	indices.assign(region.indices)
	_add_areas(indices)
	territories[0].name = info.place  # the player's own town, even for a PO-box ZIP
	territories[0].label = info.place
	for pair in region.links:
		_link(_slot[pair[0]], _slot[pair[1]])
	home = 0
	_relabel()


## Adds ZIP areas as territories (projected around home) and links them to everything on the map.
func _add_areas(indices: Array[int]) -> void:
	for idx in indices:
		var code := ZctaDB.code(idx)
		var at := ZctaDB.label_point(idx)
		var row := ZipDB.lookup(code)
		if row.is_empty():
			row = ZipDB.row_near(at.y, at.x)
		var t := Territory.new(code, row.place, (at - _origin) * _scale)
		t.lonlat = at
		t.region = row.region
		for ring in ZctaDB.parts(idx):
			var projected := PackedVector2Array()
			for p in ring:
				var q := (p - _origin) * _scale
				if projected.is_empty() or not projected[-1].is_equal_approx(q):
					projected.append(q)
			if projected.size() >= 3:
				t.parts.append(projected)
		t.area = ZctaDB.area(idx)
		t.condition = Campaign.condition_for(t, t.area * KM_PER_DEG_LON * KM_PER_DEG_LAT * cos(deg_to_rad(at.y)))
		_slot[idx] = territories.size()
		_area_of.append(idx)
		territories.append(t)
	for idx in indices:
		for n in ZctaDB.neighbors(idx):
			if _slot.has(n):
				_link(_slot[idx], _slot[n])


## Big cities have many ZIPs with the same town name; label those by ZIP instead.
func _relabel() -> void:
	var name_counts := {}
	for t in territories:
		name_counts[t.name] = name_counts.get(t.name, 0) + 1
	for i in territories.size():
		var t := territories[i]
		t.label = t.id if name_counts[t.name] > 1 and i != home else t.name


## Liberating an edge territory reveals the ZIP areas beyond it. Returns text for the event log.
func _reveal_beyond(i: int) -> String:
	if not has_frontier(i):
		return ""
	var codes: Array[String] = []
	for n in ZctaDB.neighbors(_area_of[i]):
		if not _slot.has(n):
			codes.append(ZctaDB.code(n))
	var first_new := territories.size()
	var new_legends := _apply_batch(codes)
	revealed.append(codes)
	var text := "\nBeyond %s: %d new area%s revealed." % [territories[i].full_name(), codes.size(), "" if codes.size() == 1 else "s"]
	for legend_id in new_legends:
		text += "\nThe %s's lair is now in sight!" % GameData.LEGENDS[legend_id].name
	return text


## Adds one batch of revealed areas and fills them in: threat, lairs for legends now in range,
## survivors and the odd cache. Deterministic, so replaying saved batches rebuilds the same map.
func _apply_batch(codes: Array) -> Array[String]:
	var indices: Array[int] = []
	for code: String in codes:
		var idx := ZctaDB.index_of(code)
		if idx >= 0 and not _slot.has(idx):
			indices.append(idx)
	var first_new := territories.size()
	_add_areas(indices)
	_relabel()
	for i in range(first_new, territories.size()):
		territories[i].threat = _threat_at(territories[i].site)
	var new_legends := _place_frontier_lairs(first_new)
	_place_frontier_extras(first_new)
	return new_legends


func _place_frontier_lairs(first_new: int) -> Array[String]:
	return _place_real_lairs(first_new)


func _place_frontier_extras(first_new: int) -> void:
	var placed := {}
	for t in territories:
		if t.recruit != "":
			placed[t.recruit] = true
	var starters: Array = GameData.REGIONS[profile.region].animals
	for i in range(first_new, territories.size()):
		var t := territories[i]
		if t.boss != "":
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(t.id + ":frontier")
		if rng.randf() < FRONTIER_RECRUIT_CHANCE:
			var region: Dictionary = GameData.REGIONS.get(t.region, {})
			var options := []
			for id in region.get("animals", []) + region.get("recruits", []):
				if id not in starters and not placed.has(id):
					options.append(id)
			if not options.is_empty():
				t.recruit = options[rng.randi_range(0, options.size() - 1)]
				placed[t.recruit] = true
				continue
		if t.threat >= GameData.MAX_THREAT and rng.randf() < FRONTIER_CACHE_CHANCE:
			t.cache = GameData.CACHE_TRINKETS[rng.randi_range(0, GameData.CACHE_TRINKETS.size() - 1)]


## Edge territories liberated before the frontier existed (or retaken) still open up the map.
func _catch_up_frontier() -> void:
	if not uses_zip_data:
		return
	var grew := false
	var i := 0
	while i < territories.size():
		if territories[i].owned and has_frontier(i):
			_reveal_beyond(i)
			grew = true
		i += 1
	if grew:
		save()


func _link(a: int, b: int) -> void:
	if b not in territories[a].neighbors:
		territories[a].neighbors.append(b)
	if a not in territories[b].neighbors:
		territories[b].neighbors.append(a)


func _build_generated(profile: Profile) -> void:
	var names := DISTRICT_NAMES.duplicate()
	for k in range(names.size() - 1, 0, -1):
		var j := _rng.randi_range(0, k)
		var tmp = names[k]
		names[k] = names[j]
		names[j] = tmp
	territories.append(Territory.new("home", profile.town if profile.town != "" else "Home", Vector2.ZERO))
	territories[0].region = profile.region
	territories[0].condition = Campaign.condition_for(territories[0], 0.0)
	var tries := 0
	while territories.size() < TERRITORY_COUNT and tries < 5000:
		tries += 1
		var p := Vector2.from_angle(_rng.randf() * TAU) * sqrt(_rng.randf()) * 10.0
		var ok := true
		for t in territories:
			if t.site.distance_to(p) < 2.6:
				ok = false
				break
		if ok:
			territories.append(Territory.new("d%d" % territories.size(), names[territories.size() - 1], p))
			territories[-1].region = profile.region
			territories[-1].condition = Campaign.condition_for(territories[-1], 0.0)
	home = 0


## Threat grows with distance from home: 1 next door, MAX_THREAT at the edge of the starting map,
## and higher still as the frontier pushes further out.
func _assign_threat() -> void:
	var origin := territories[home].site
	_base_far = 0.0
	for t in territories:
		_base_far = maxf(_base_far, t.site.distance_to(origin))
	for t in territories:
		t.threat = _threat_at(t.site)


func _threat_at(site: Vector2) -> int:
	var d := site.distance_to(territories[home].site) / maxf(_base_far, 0.001)
	return maxi(1, ceili(d * GameData.MAX_THREAT))
