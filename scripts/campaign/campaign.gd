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
var last_liberated := -1  # territory index most recently taken from the horde, or -1
var last_event := ""
var uses_zip_data := false
var legends: Array[String] = []  # legend ids with a lair on this map
var profile: Profile
var claimed: Array[String] = []  # territory ids whose trinket was already taken
var revealed: Array = []  # batches of ZIP codes added beyond the starting map, in order
var base_count := 0  # territories on the starting map
var nests: Array[int] = []  # territories the horde spreads from (GameData.NEST_COUNT)
var cleared_nests: Array[String] = []  # nest ids liberated at least once: they never spread again
var spread := {}  # territory id -> threat the migrating horde has added there
var cut_off := {}  # held territory id -> map turns it has been cut off from home
## Teams (server/teams.sql): every member's home ZIP is on the map. `home` is this player's.
var homes: Array[int] = []
var members: Array = []  # [{user_id, name, zip}] in join order; empty when playing solo
var feed: Array = []  # team: recent moves [{who, text, turn}], newest last
var me := ""  # this player's name in the team feed
var my_id := ""  # this player's account id (team XP shares)
var shared_xp := {}  # team: account id -> XP teammates' battles have earned them, all time
var packs := {}  # team: account id -> their fighting lineup (Profile.snapshot), for legend fights
var replaying := false  # re-applying queued moves to newer team state: no rewards, no recording
var on_action := Callable()  # team: told about each move so it can be sent to the server

## Tests point this somewhere else so they never touch the player's real save.
static var save_path := SAVE_PATH

var _key := ""
var _origin := Vector2.ZERO  # home (lon, lat) for real maps
var _scale := Vector2.ONE  # degrees -> km
var _rng := RandomNumberGenerator.new()
var _fars := {}  # home index -> km to the edge of its starting patch; threat 5 there
var _starter_regions: Array[String] = []  # team: every member's home region
var _home_names := {}  # team: home index -> its member's short name
var _home_of := {}  # team: account id -> home index
var _slot := {}  # ZIP area index -> territory index
var _area_of: Array[int] = []  # territory index -> ZIP area index
var _linked := {}  # cache of supplied(); cleared whenever ownership changes


## The solo campaign, or with `team` (Team.info: {id, members, state}) the team's shared map.
static func create(profile: Profile, team := {}) -> Campaign:
	var c := Campaign.new()
	c.profile = profile
	c.members.assign(team.get("members", []))
	c._key = ("team:" + String(team.id)) if not c.members.is_empty() else profile.home_key()
	c._rng.seed = hash(c._key)
	if not c.members.is_empty():
		c._build_team(profile)
	elif profile.zip != "":
		c._build_from_zips(profile.zip)
	if c.territories.is_empty():
		c._build_generated(profile)
		MapBuilder.spread(c.territories, c.home)
		MapBuilder.build(c.territories)
	c._assign_threat()
	c._place_lairs(profile)
	c._place_nests()
	c._place_recruits(profile)
	c._place_caches()
	for h in c.homes:
		c.territories[h].owned = true
	c.base_count = c.territories.size()
	if c.members.is_empty():
		c._load()
	else:
		c._load_text(team.get("state", ""))
	c._catch_up_frontier()
	return c


func is_team() -> bool:
	return not members.is_empty()


## The horde's clock runs slower on team maps: every member's moves advance it.
func pace() -> int:
	return maxi(1, members.size())


## The teammate whose home is territory `i` ("" if none, or it's this player's).
func home_owner(i: int) -> String:
	return "" if i == home else String(_home_names.get(i, ""))


func _nearest_home(site: Vector2) -> int:
	var best := homes[0]
	for h in homes:
		if site.distance_to(territories[h].site) < site.distance_to(territories[best].site):
			best = h
	return best


## Applies a move queued by Team to (newer) team state, without rewards or recording.
func apply(action: Dictionary) -> void:
	var i := -1
	for k in territories.size():
		if territories[k].id == String(action.get("t", "")):
			i = k
	replaying = true
	match String(action.get("do", "")):
		"battle":
			if i >= 0:
				resolve_battle(i, bool(action.won), int(action.get("xp", 0)), String(action.get("helper", "")))
		"patrol":
			if i >= 0:
				resolve_patrol(i, bool(action.won))
		"rest":
			rest()
		"stable":
			bring_from_stable(String(action.get("id", "")))
		"pack":
			packs[my_id] = String(action.get("snap", ""))
	replaying = false


func _act(action: Dictionary) -> void:
	if is_team() and not replaying and on_action.is_valid():
		on_action.call(action)


## The teammate whose lineup fought beside this player (`helper`) is owed the battle's full XP;
## other teammates whose home links to this player's through held land are owed
## GameData.TEAM_XP_SHARE of it. Each device collects its own (Profile.collect_team_xp).
func _share_xp(xp: int, helper := "") -> void:
	if not is_team() or xp <= 0:
		return
	if helper != "" and helper != my_id:
		shared_xp[helper] = int(shared_xp.get(helper, 0)) + xp
	var amount := roundi(xp * GameData.TEAM_XP_SHARE)
	var linked := _reach([home], -1)
	for id in _home_of:
		if id != my_id and id != helper and amount > 0 and linked.has(_home_of[id]):
			shared_xp[id] = int(shared_xp.get(id, 0)) + amount


## Shares this player's fighting lineup with the team (only when it changed).
func share_pack(snapshot: String) -> void:
	if not is_team() or my_id == "" or packs.get(my_id, "") == snapshot:
		return
	packs[my_id] = snapshot
	_act({"do": "pack", "snap": snapshot})


## Teammates' lineups that can join a legend fight: [{id, name, pack}].
func teammate_packs() -> Array:
	var out := []
	for m: Dictionary in members:
		var id := String(m.get("user_id", ""))
		if id != my_id and packs.has(id):
			out.append({"id": id, "name": String(m.name).get_slice(" · ", 0), "pack": packs[id]})
	return out


## True if this player's home and `other` are joined by an unbroken chain of held land.
func homes_linked(other: int) -> bool:
	return _reach([home], -1).has(other)


## This team map's key, for the XP each player has collected from it.
func team_key() -> String:
	return _key if is_team() else ""


func _feed(text: String) -> void:
	if not is_team():
		return
	feed.append({"who": me, "text": text, "turn": turn})
	feed = feed.slice(-20)


func to_text() -> String:
	return _to_cfg().encode_to_text()


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
	return (GameData.COUNTERATTACK_EVERY + (GameData.GUARD_COUNTER_DELAY if profile.duties.has("guard") else 0)) * pace()


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


## Only territories still linked to home count.
func held_bonus() -> float:
	return minf(GameData.MAX_HELD_BONUS, (supplied().size() - homes.size()) * GameData.HELD_TERRITORY_BONUS)


## Attacks launch from held land that's still linked to home.
func can_attack(i: int) -> bool:
	if territories[i].owned:
		return false
	var linked := supplied()
	for n in territories[i].neighbors:
		if linked.has(n):
			return true
	return false


## Held territories joined to home by an unbroken chain of held land (index -> true).
func supplied() -> Dictionary:
	if _linked.is_empty():
		_linked = _reach_from_home(-1)
	return _linked


func is_cut_off(i: int) -> bool:
	return territories[i].owned and not supplied().has(i)


## Turns before cut-off territory `i` falls to the horde.
func turns_until_lost(i: int) -> int:
	return GameData.CUT_OFF_FALL * pace() - int(cut_off.get(territories[i].id, 0))


func is_nest(i: int) -> bool:
	return i in nests and not territories[i].owned and territories[i].id not in cleared_nests


## Held land reachable from any home without passing through `skip`.
func _reach_from_home(skip: int) -> Dictionary:
	return _reach(homes, skip)


## Held land reachable from `starts` without passing through `skip`.
func _reach(starts: Array[int], skip: int) -> Dictionary:
	var seen := {}
	var queue: Array[int] = []
	for h in starts:
		seen[h] = true
		queue.append(h)
	while not queue.is_empty():
		var i: int = queue.pop_back()
		for n in territories[i].neighbors:
			if n != skip and territories[n].owned and not seen.has(n):
				seen[n] = true
				queue.append(n)
	return seen


## How many held territories would lose their link home if `i` fell.
func cut_by(i: int) -> int:
	return maxi(0, supplied().size() - 1 - _reach_from_home(i).size()) if supplied().has(i) else 0


func _ownership_changed() -> void:
	_linked = {}


## What the player may start a battle on right now. A counterattack must be answered first.
func is_actionable(i: int) -> bool:
	return i == under_attack if under_attack >= 0 else can_attack(i)


## The level the zombies here fight at: the territory's own, or the pack's if it has outgrown it.
func territory_level(i: int) -> int:
	return GameData.territory_level(zombie_strength(territories[i].threat) * territories[i].horde_strength())


## The territory's own level, from threat and attrition alone (what auto mode measures).
func base_level(i: int) -> int:
	return GameData.territory_level(GameData.zombie_mult(territories[i].threat) * territories[i].horde_strength())


## Zombie stat multiplier at `threat`: the threat's own, or caught up with the pack's strongest
## lineup (PACK_LEVEL_GAP levels below it at threat 1, one level closer per threat), whichever is higher.
func zombie_strength(threat: int) -> float:
	var caught_up := profile.strongest_pack_level() - GameData.PACK_LEVEL_GAP + threat - 1
	return maxf(GameData.zombie_mult(threat), GameData.level_strength(caught_up))


## The next fight auto mode takes on its own: a counterattack or neighbor whose own level is at
## least AUTO_LEVEL_GAP below the leader, easiest first. Legend lairs are always left to the
## player. -1 if none.
func auto_target(leader_level: int) -> int:
	var max_level := leader_level - GameData.AUTO_LEVEL_GAP
	if under_attack >= 0:
		return under_attack if base_level(under_attack) <= max_level else -1
	var best := -1
	for i in territories.size():
		if can_attack(i) and territories[i].boss == "" and base_level(i) <= max_level:
			if best < 0 or base_level(i) < base_level(best):
				best = i
	return best


func battle_config(i: int) -> Dictionary:
	var t := territories[i]
	var threat := t.threat + (GameData.CUT_OFF_THREAT if i == under_attack and is_cut_off(i) else 0)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(t.id)  # same zombies every visit, so a retry is a fair rematch
	return {
		"waves": GameData.generate_waves(threat, rng, t.boss),
		"threat": threat,
		"zombie_mult": zombie_strength(threat) * t.horde_strength(),
		"xp_mult": GameData.zombie_mult(threat) * t.horde_strength(),
		"party_mult": 1.0 + held_bonus(),
		"place": territories[i].full_name(),
		"condition": t.condition,
		"region": t.region,
		"boss_hp": GameData.legend_growth(pace()).x if t.boss != "" else 1.0,
		"boss_atk": GameData.legend_growth(pace()).y if t.boss != "" else 1.0,
		"teammates": teammate_packs() if t.boss != "" else [],
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
		"threat": threat,
		"zombie_mult": zombie_strength(threat),
		"xp_mult": GameData.zombie_mult(threat),
		"party_mult": 1.0 + held_bonus(),
		"place": "Patrol: " + t.full_name(),
		"condition": t.condition,
		"region": t.region,
	}


func resolve_patrol(i: int, won: bool) -> void:
	_act({"do": "patrol", "t": territories[i].id, "won": won})
	turn += 1
	last_event = ("Patrol cleared the stragglers around %s." if won else "The patrol around %s fell back.") % territories[i].full_name()
	_end_turn()


## Brings an animal back from the Stable into a free pack slot; it takes the map turn.
func bring_from_stable(id: String) -> void:
	if replaying:
		turn += 1  # the animal already left the Stable on this device; only the turn is shared
		_end_turn()
		return
	if not profile.can_leave_stable(id):
		return
	_act({"do": "stable", "id": id})
	turn += 1
	profile.leave_stable(id)
	last_event = "%s rejoins the pack from the Stable." % profile.unit_name(id)
	_end_turn()


## Rest at home: injuries heal and fatigue clears, but the map turn passes.
func rest() -> void:
	_act({"do": "rest"})
	turn += 1
	if not replaying:
		profile.injuries.clear()
		profile.fatigue.clear()
	last_event = "The pack rests at home. Injuries healed, everyone refreshed."
	_end_turn()


func _end_turn() -> void:
	_update_supply()
	if turn % (GameData.MIGRATE_EVERY * pace()) == 0:
		_migrate()
	if under_attack < 0 and turn % counter_interval() == 0:
		_start_counterattack()
	save()


## Cut-off territories count down; at GameData.CUT_OFF_FALL turns the horde takes them back.
func _update_supply() -> void:
	var newly: PackedStringArray = []
	var fell: PackedStringArray = []
	var linked := supplied()
	for i in territories.size():
		var t := territories[i]
		if not t.owned or linked.has(i):
			cut_off.erase(t.id)
			continue
		cut_off[t.id] = int(cut_off.get(t.id, 0)) + 1
		if cut_off[t.id] == 1:
			newly.append(t.full_name())
		if cut_off[t.id] >= GameData.CUT_OFF_FALL * pace():
			t.owned = false
			cut_off.erase(t.id)
			fell.append(t.full_name())
			if under_attack == i:
				under_attack = -1
	if not fell.is_empty():
		_ownership_changed()
		last_event += "\nCut off too long, the horde overran %s." % ", ".join(fell)
	if not newly.is_empty():
		last_event += "\nCut off from home: %s! Reconnect within %d turns or lose %s." % [
			", ".join(newly), GameData.CUT_OFF_FALL * pace() - 1, "it" if newly.size() == 1 else "them"]


## Nests at the far edge of each home's starting patch (no lairs): the farthest max-threat area,
## then each next one as far from the others as possible. Depends only on the map, so it's stable.
func _place_nests() -> void:
	for h in homes:
		# This home's own patch: max-threat areas (not lairs) nearer to it than to any other home.
		var spots: Array[int] = []
		for i in territories.size():
			var t := territories[i]
			if i not in homes and i not in nests and t.boss == "" and t.threat >= GameData.MAX_THREAT 					and _nearest_home(t.site) == h:
				spots.append(i)
		var mine: Array[int] = []
		while mine.size() < GameData.NEST_COUNT and not spots.is_empty():
			var best := spots[0]
			var best_d := -1.0
			for i in spots:
				var d := territories[i].site.distance_to(territories[h].site) if mine.is_empty() else INF
				for n in mine:
					d = minf(d, territories[i].site.distance_to(territories[n].site))
				if d > best_d:
					best_d = d
					best = i
			mine.append(best)
			spots.erase(best)
		nests.append_array(mine)


## Each standing nest pushes the horde one step: +1 threat to an unheld area next to its infested
## ground (the nest, the areas the horde has spread to, and unheld areas already at the cap) that
## is lower than the ground it borders and hasn't been raised yet: the most infested first, nearest
## home on ties, so the wave creeps outward toward the pack.
func _migrate() -> void:
	for nest in nests:
		if not is_nest(nest):
			continue
		var cap := territories[nest].threat
		var ground := {nest: true}
		var queue: Array[int] = [nest]
		while not queue.is_empty():
			var i: int = queue.pop_back()
			for n in territories[i].neighbors:
				var t := territories[n]
				if not ground.has(n) and not t.owned and (t.threat >= cap or spread.has(t.id)):
					ground[n] = true
					queue.append(n)
		var pick := -1
		for i: int in ground:
			for n in territories[i].neighbors:
				var t := territories[n]
				if t.owned or t.boss != "" or n in nests or t.threat >= cap or t.threat >= territories[i].threat 						or int(spread.get(t.id, 0)) >= GameData.MAX_SPREAD:
					continue
				if pick < 0 or t.threat > territories[pick].threat or (t.threat == territories[pick].threat
						and _home_distance(t.site) < _home_distance(territories[pick].site)):
					pick = n
		if pick < 0:
			continue
		var target := territories[pick]
		target.threat += 1
		spread[target.id] = int(spread.get(target.id, 0)) + 1
		last_event += "\nThe horde spreads from %s into %s (threat %d → %d)." % [
			territories[nest].full_name(), target.full_name(), target.threat - 1, target.threat]


## `xp`: what each of this player's fighters earned; linked teammates get a share of it, and
## `helper` (a teammate whose lineup fought here) all of it.
func resolve_battle(i: int, won: bool, xp := 0, helper := "") -> void:
	_act({"do": "battle", "t": territories[i].id, "won": won, "xp": xp, "helper": helper})
	turn += 1
	var t := territories[i]
	if t.owned and i != under_attack:
		last_event = "%s is already free: a teammate got there first." % t.full_name()
		_end_turn()
		return
	if i == under_attack:
		under_attack = -1
		if won:
			last_event = "%s held! The horde falls back." % t.full_name()
		else:
			t.owned = false
			_ownership_changed()
			last_event = "%s was overrun. Take it back!" % t.full_name()
	elif won:
		t.owned = true
		_ownership_changed()
		last_liberated = i
		last_event = "%s liberated!" % t.full_name()
		if i in nests and t.id not in cleared_nests:
			cleared_nests.append(t.id)
			last_event += "\nThe nest is destroyed: the horde stops spreading from here."
		var relinked := 0
		for id in cut_off:
			for k in territories.size():
				if territories[k].id == id and supplied().has(k):
					relinked += 1
		if relinked > 0:
			last_event += "\nSupply restored to %d cut-off territor%s." % [relinked, "y" if relinked == 1 else "ies"]
		if t.boss != "":
			last_event = "The %s is defeated! %s is free." % [GameData.LEGENDS[t.boss].name, t.full_name()]
		var loot := loot_at(i)
		if loot != "":
			claimed.append(t.id)  # shared: the liberator keeps it, teammates can't take it again
			if not replaying:
				profile.trinkets.append(loot)
				last_event += "\nFound the %s! Equip it from Pack." % GameData.trinket(loot).name
		if t.recruit != "" and not replaying and not profile.unlock([t.recruit]).is_empty():
			var where := "waits in the Stable (the pack is full)" if t.recruit in profile.stable else "joined the pack"
			last_event += "\nRescued: %s %s at Lv %d! Swap it in from Pack." % [
				GameData.ANIMALS[t.recruit].name, where, profile.level_of(t.recruit)]
		last_event += _reveal_beyond(i)
	else:
		t.failed_attacks += 1
		last_event = "The pack retreated from %s, but thinned the horde there." % t.full_name()
	_feed(last_event.get_slice("\n", 0))
	_share_xp(xp, helper)
	_end_turn()


func save() -> void:
	if is_team():
		return  # team maps live on the server; Team keeps this device's moves until they're sent
	_to_cfg().save(save_path)
	if save_path == SAVE_PATH:
		SaveHooks.saved()


func _to_cfg() -> ConfigFile:
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
	cfg.set_value("campaign", "spread", spread)
	cfg.set_value("campaign", "cut_off", cut_off)
	cfg.set_value("campaign", "cleared_nests", Array(cleared_nests))
	cfg.set_value("campaign", "feed", feed)
	cfg.set_value("campaign", "shared_xp", shared_xp)
	cfg.set_value("campaign", "packs", packs)
	cfg.set_value("campaign", "under_attack", territories[under_attack].id if under_attack >= 0 else "")
	cfg.set_value("campaign", "last_liberated", territories[last_liberated].id if last_liberated >= 0 else "")
	return cfg


static func clear_saved() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(save_path) == OK:
		_load_cfg(cfg)


func _load_text(text: String) -> void:
	var cfg := ConfigFile.new()
	if text != "" and cfg.parse(text) == OK:
		_load_cfg(cfg)


func _load_cfg(cfg: ConfigFile) -> void:
	if cfg.get_value("campaign", "key", "") != _key:
		return
	# Rebuild the frontier first: owned ids may include revealed areas.
	for batch: Array in cfg.get_value("campaign", "revealed", []):
		_apply_batch(batch)
		revealed.append(batch)
	var owned_ids: Array = cfg.get_value("campaign", "owned", [])
	var attacked: String = cfg.get_value("campaign", "under_attack", "")
	var latest: String = cfg.get_value("campaign", "last_liberated", "")
	for i in territories.size():
		territories[i].owned = i in homes or territories[i].id in owned_ids
		if territories[i].id == attacked:
			under_attack = i
		if territories[i].id == latest and territories[i].owned:
			last_liberated = i
	turn = cfg.get_value("campaign", "turn", 0)
	claimed.assign(cfg.get_value("campaign", "claimed", []))
	var fails: Dictionary = cfg.get_value("campaign", "failed_attacks", {})
	for t in territories:
		t.failed_attacks = fails.get(t.id, 0)
	spread = cfg.get_value("campaign", "spread", {})
	for t in territories:
		t.threat += int(spread.get(t.id, 0))
	cut_off = cfg.get_value("campaign", "cut_off", {})
	cleared_nests.assign(cfg.get_value("campaign", "cleared_nests", []))
	feed = cfg.get_value("campaign", "feed", [])
	shared_xp = cfg.get_value("campaign", "shared_xp", {})
	packs = cfg.get_value("campaign", "packs", {})
	_ownership_changed()


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
		if i not in homes and territories[i].boss == "" and territories[i].threat >= GameData.MAX_THREAT - 1:
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
	var starters := _starters()
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
		if i in homes or territories[i].boss != "":
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
		if i in homes:
			# A legend from a player's own ZIP lurks just next door instead.
			i = territories[i].neighbors[0] if not territories[i].neighbors.is_empty() else -1
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
## Where rumor distances are measured from: the last territory liberated (if still held), else home.
func rumor_origin() -> int:
	return last_liberated if last_liberated >= 0 and territories[last_liberated].owned else home


func rumors(max_count := 3, max_km := 600.0) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not uses_zip_data:
		return out
	var from := territories[rumor_origin()].lonlat
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
		if i in homes or not territories[i].owned:
			continue
		for n in territories[i].neighbors:
			if not territories[n].owned:
				border.append(i)
				break
	if border.is_empty():
		return
	under_attack = border[_rng.randi_range(0, border.size() - 1)]
	# Usually it goes for the chokepoint: the territory whose loss cuts off the most held land.
	var worst := -1
	for i in border:
		if cut_by(i) > 0 and (worst < 0 or cut_by(i) > cut_by(worst)):
			worst = i
	if worst >= 0 and _rng.randf() < GameData.CHOKEPOINT_CHANCE:
		under_attack = worst
	last_event += "\nThe horde is attacking %s!" % territories[under_attack].full_name()
	if cut_by(under_attack) > 0:
		last_event += " Lose it and %d territor%s will be cut off from home." % [cut_by(under_attack), "y" if cut_by(under_attack) == 1 else "ies"]


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
	homes.assign([home])
	_relabel()


## Team map: every member's home ZIP grows its own patch of the real map (as big as a solo map);
## patches that touch merge into one front. Projected around the first member's home, so every
## teammate builds the identical map.
func _build_team(p: Profile) -> void:
	var mine := -1
	for m: Dictionary in members:
		var zip := String(m.zip)
		var info := ZipDB.lookup(zip)
		var area := ZctaDB.find(zip, info.lat, info.lon) if not info.is_empty() else -1
		if area < 0:
			continue
		var region := ZctaDB.grow(area, TERRITORY_COUNT)
		if not uses_zip_data:
			uses_zip_data = true
			_origin = ZctaDB.label_point(area)
			_scale = Vector2(cos(deg_to_rad(_origin.y)) * KM_PER_DEG_LON, -KM_PER_DEG_LAT)
		var fresh: Array[int] = []
		for idx: int in region.indices:
			if not _slot.has(idx):
				fresh.append(idx)
		_add_areas(fresh)
		for pair in region.links:
			if _slot.has(pair[0]) and _slot.has(pair[1]):
				_link(_slot[pair[0]], _slot[pair[1]])
		var h: int = _slot[area]
		territories[h].name = info.place
		territories[h].label = info.place
		_home_of[String(m.get("user_id", ""))] = h
		if h not in homes:
			homes.append(h)
			_home_names[h] = String(m.name).get_slice(" · ", 0)
		if zip == p.zip and mine < 0:
			mine = h
		_starter_regions.append(String(info.region))
	if homes.is_empty():
		return
	home = mine if mine >= 0 else homes[0]
	_relabel()


## Animals the map's survivors are never drawn from: the home region's (every member's on a team).
func _starters() -> Array:
	if _starter_regions.is_empty():
		return GameData.REGIONS[profile.region].animals
	var out := []
	for r in _starter_regions:
		out.append_array(GameData.REGIONS.get(r, {}).get("animals", []))
	return out


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
		t.label = t.id if name_counts[t.name] > 1 and i not in homes else t.name


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
	var starters := _starters()
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
			var n := territories.size() - 1  # more territories than names: later ones reuse them, numbered
			var label: String = names[n % names.size()] + ("" if n < names.size() else " %d" % (n / names.size() + 1))
			territories.append(Territory.new("d%d" % territories.size(), label, p))
			territories[-1].region = profile.region
			territories[-1].condition = Campaign.condition_for(territories[-1], 0.0)
	home = 0
	homes.assign([home])


## Threat grows with distance from home: 1 next door, MAX_THREAT at the edge of the starting map,
## and higher still as the frontier pushes further out.
func _assign_threat() -> void:
	_fars.clear()
	for h in homes:
		_fars[h] = 0.0
	for t in territories:
		var h := _nearest_home(t.site)
		_fars[h] = maxf(_fars[h], t.site.distance_to(territories[h].site))
	for t in territories:
		t.threat = _threat_at(t.site)


## Measured from the nearest home, against how far that home's own patch reaches.
func _threat_at(site: Vector2) -> int:
	var d := INF
	for h in homes:
		d = minf(d, site.distance_to(territories[h].site) / maxf(_fars.get(h, 1.0), 0.001))
	return maxi(1, ceili(d * GameData.MAX_THREAT))


func _home_distance(site: Vector2) -> float:
	return site.distance_to(territories[_nearest_home(site)].site)
