class_name Profile
extends RefCounted

## Who the player is in the world: where they live, their real-life pet, and their starting team.
## Saved locally so first-launch setup only happens once.

const SAVE_PATH := "user://profile.cfg"

const COUNTRY_REGIONS := {
	"europe": ["GB", "IE", "FR", "DE", "ES", "PT", "IT", "NL", "BE", "LU", "CH", "AT", "DK", "NO", "SE",
		"FI", "IS", "PL", "CZ", "SK", "HU", "RO", "BG", "GR", "HR", "SI", "RS", "BA", "ME", "MK", "AL",
		"UA", "BY", "LT", "LV", "EE", "MD", "RU"],
	"latin_america": ["MX", "GT", "BZ", "SV", "HN", "NI", "CR", "PA", "CU", "DO", "HT", "JM", "PR", "CO",
		"VE", "EC", "PE", "BO", "BR", "PY", "UY", "AR", "CL"],
	"africa": ["ZA", "NG", "KE", "EG", "MA", "DZ", "TN", "GH", "ET", "TZ", "UG", "ZW", "ZM", "BW", "NA",
		"SN", "CI", "CM", "AO", "MZ", "RW"],
	"asia": ["JP", "CN", "KR", "TW", "HK", "IN", "PK", "BD", "LK", "NP", "TH", "VN", "MY", "SG", "ID",
		"PH", "KH", "LA", "MM", "MN", "KZ", "TR", "SA", "AE", "IL", "IR", "IQ"],
	"australia": ["AU", "NZ", "FJ", "PG"],
}
const WEST_TIME_ZONE_HINTS := ["Pacific", "Mountain", "Alaska", "Hawaii", "Arizona"]

## Tests point this somewhere else so they never touch the player's real save.
static var save_path := SAVE_PATH

var region := ""
var zip := ""  # US players; "" means they picked a region instead
var town := ""
var pet_species := ""  # "" = no pet
var pet_name := ""
var team: Array[String] = []  # wild animals fighting beside the pet (or alone)
var xp := {}  # unit id (pet species or wild animal id) -> total XP
var unlocked: Array[String] = []  # wild animals that can join the pack
var stable: Array[String] = []  # unlocked animals waiting in the Stable: they don't fight or earn XP
var trinkets: Array[String] = []  # owned trinkets (duplicates allowed)
var equipped := {}  # unit id -> trinket id it wears
var tree := {}  # unit id -> tech-tree node ids bought (one point per level above 1)
var just_leveled: Array[String] = []  # units that gained a level since the last tree visit (not saved)
var injuries := {}  # unit id -> battles left injured
var fatigue := {}  # unit id -> battles fought in a row
var duties := {}  # "scout" / "forage" / "guard" -> benched unit id
var rows := {}  # unit id -> "front" / "back", where it differs from its role's default
var fixes: Array[String] = []  # one-off save fixes already applied
var auto_battle := false  # auto mode: fight territories far below the leader without asking
var siege_claimed: Array[int] = []  # weeks claimed before sieges had stages: the first stage's reward
var siege_rewards := {}  # siege week -> how many of its stages have been claimed
var siege_seen := {}  # siege week -> how many of its stages the map has announced
var dungeon_best := {}  # region -> the deepest dungeon wave cleared
var dungeon_paid := {}  # region -> the deepest wave whose reward has been paid (each pays once)
var team_xp := {}  # team map key -> XP from teammates' battles already collected
var raids_claimed: Array[String] = []  # legend raids whose rewards this player has collected
var team_id := ""  # the team this game is played with ("" = solo); see Team


## Identifies the home map; the saved campaign is thrown away if this changes.
func home_key() -> String:
	return "zip:" + zip if zip != "" else "region:%s:%s" % [region, town]


func has_pet() -> bool:
	return pet_species != ""


func level_of(id: String) -> int:
	return GameData.level_for_xp(xp.get(id, 0))


## Adds XP and returns how many levels that gained.
func add_xp(id: String, amount: int) -> int:
	var before := level_of(id)
	xp[id] = xp.get(id, 0) + amount
	var gained := level_of(id) - before
	if gained > 0 and id not in just_leveled:
		just_leveled.append(id)
	return gained


## --- Tech tree ---

func points_left(unit_id: String) -> int:
	return level_of(unit_id) - 1 - tree.get(unit_id, []).size()


func owns(unit_id: String, node_id: String) -> bool:
	return node_id in tree.get(unit_id, [])


## Why a node can't be bought right now ("" if it can).
func tree_block(unit_id: String, node_id: String) -> String:
	var node := GameData.tree_node(unit_id, node_id)
	if owns(unit_id, node_id):
		return "Owned"
	if level_of(unit_id) < node.min_level:
		return "Needs Lv %d" % node.min_level
	for req in node.requires:
		if not owns(unit_id, req):
			return "Needs the one above" if node.branch != "signature" or req != "sig" else "Needs the signature skill"
	if points_left(unit_id) <= 0:
		return "No points"
	return ""


func buy_node(unit_id: String, node_id: String) -> bool:
	if tree_block(unit_id, node_id) != "":
		return false
	var bought: Array = tree.get_or_add(unit_id, [])
	bought.append(node_id)
	return true


func reset_tree(unit_id: String) -> void:
	tree.erase(unit_id)


## Animals that leveled since the last tree visit and have points to spend, pack first.
func units_with_new_points() -> Array[String]:
	var out: Array[String] = []
	for id in pack_ids() + unlocked:
		if id in just_leveled and points_left(id) > 0 and id not in out:
			out.append(id)
	return out


## A pack animal as it fights: base stats, leader bonus, level, tech tree and trinket.
func build_unit(unit_id: String) -> Combatant:
	var is_pet := has_pet() and unit_id == pet_species
	var c := Combatant.from_data(unit_id, GameData.PETS[unit_id] if is_pet else GameData.ANIMALS[unit_id], true)
	if is_pet:
		c.make_leader(pet_name)
	var skill_steps := {}
	var stats := {}
	for node_id in tree.get(unit_id, []):
		var node := GameData.tree_node(unit_id, node_id)
		match node.get("kind", ""):
			"stat":
				stats[node.stat] = stats.get(node.stat, 0) + 1
			"skill":
				var steps: Dictionary = skill_steps.get_or_add(node.skill, {})
				steps[node.upgrade] = steps.get(node.upgrade, 0) + 1
			"signature":
				c.learn_signature()
			"mastery":
				c.mastered = true
	c.skill_mods = skill_steps
	c.apply_level(level_of(unit_id))
	c.apply_stat_mods(stats)
	if equipped.has(unit_id):
		c.equip(equipped[unit_id])
	c.tags = GameData.tags_of(unit_id)
	return c


func unit_name(unit_id: String) -> String:
	if has_pet() and unit_id == pet_species:
		return pet_name
	return GameData.ANIMALS[unit_id].name if GameData.ANIMALS.has(unit_id) else unit_id


## The pet leads every fight, so it never tires; everyone else does.
func fatigue_penalty(unit_id: String) -> float:
	if has_pet() and unit_id == pet_species:
		return 0.0
	return minf(GameData.MAX_FATIGUE, GameData.FATIGUE_STEP * fatigue.get(unit_id, 0))


func duty_of(unit_id: String) -> String:
	for duty in duties:
		if duties[duty] == unit_id:
			return duty
	return ""


## Cycles a benched animal through no duty -> scout -> forage -> guard. Taking a duty bumps
## whoever held it.
func cycle_duty(unit_id: String) -> void:
	var options: Array = [""] + GameData.DUTIES
	var next: String = options[(options.find(duty_of(unit_id)) + 1) % options.size()]
	clear_duty(unit_id)
	if next != "":
		duties[next] = unit_id


func clear_duty(unit_id: String) -> void:
	var d := duty_of(unit_id)
	if d != "":
		duties.erase(d)


## Fills empty duties from the bench so they don't need re-picking after every lineup change:
## the fastest benched animal scouts, the toughest guards, anyone else forages. Never moves a
## duty that's already held.
func auto_fill_duties() -> void:
	var free: Array[String] = []
	for id in active():
		if id not in team and duty_of(id) == "":
			free.append(id)
	var stat_of := func(id: String, stat: String) -> int: return GameData.ANIMALS[id][stat]
	for duty in GameData.DUTIES:
		if duties.has(duty) or free.is_empty():
			continue
		var best: String = free[0]
		for id in free:
			if duty == "scout" and stat_of.call(id, "spd") > stat_of.call(best, "spd"):
				best = id
			elif duty == "guard" and stat_of.call(id, "def") > stat_of.call(best, "def"):
				best = id
		duties[duty] = best
		free.erase(best)


## After-battle bookkeeping shared by the game and the simulator: XP for fighters and reserves,
## injuries, fatigue and foraging. Returns lines for the results screen. Only a won battle injures
## the animals knocked out in it; on a retreat the pack carries its wounded home.
func after_battle(fought: Array[String], downed: Array[String], amount: int, won := true) -> PackedStringArray:
	var lines: PackedStringArray = ["+%d XP for the pack" % amount]
	for id in fought:
		if add_xp(id, amount) > 0:
			lines.append("%s reached Lv %d!" % [unit_name(id), level_of(id)])
	var bench_amount := roundi(amount * GameData.BENCH_XP_SHARE)
	var benched := 0
	for id in active():
		if id in fought:
			continue
		benched += 1
		if add_xp(id, bench_amount) > 0:
			lines.append("%s (bench) reached Lv %d!" % [unit_name(id), level_of(id)])
	if benched > 0 and bench_amount > 0:
		lines.append("Bench: +%d XP each" % bench_amount)

	for id in injuries.keys():
		injuries[id] -= 1
		if injuries[id] <= 0:
			injuries.erase(id)
	for id in downed if won else []:
		injuries[id] = GameData.INJURY_BATTLES
		lines.append("%s is injured for %d battles." % [unit_name(id), GameData.INJURY_BATTLES])
	for id in fatigue.keys():
		if id not in fought:
			fatigue.erase(id)
	for id in fought:
		fatigue[id] = fatigue.get(id, 0) + 1

	if duties.has("forage"):
		var forager := unit_name(duties.forage)
		if randf() < GameData.FORAGE_TRINKET_CHANCE:
			var found: String = GameData.CACHE_TRINKETS.pick_random()
			trinkets.append(found)
			lines.append("%s foraged a %s!" % [forager, GameData.trinket(found).name])
		elif randf() < GameData.FORAGE_XP_CHANCE:
			for id in pack_ids():
				add_xp(id, GameData.FORAGE_XP)
			lines.append("%s foraged supplies: +%d XP for the pack." % [forager, GameData.FORAGE_XP])
	return lines


## The units that fight: the pet (if any) and the team.
func pack_ids() -> Array[String]:
	var ids: Array[String] = []
	if has_pet():
		ids.append(pet_species)
	ids.append_array(team)
	return ids


## The pack's leader: the pet if there is one, otherwise the highest-level animal in the pack.
func leader_id() -> String:
	if has_pet():
		return pet_species
	var best := ""
	for id in team:
		if best == "" or level_of(id) > level_of(best):
			best = id
	return best


func leader_level() -> int:
	var id := leader_id()
	return level_of(id) if id != "" else 1


func pack_level() -> int:
	var ids := pack_ids()
	if ids.is_empty():
		return 1
	var total := 0
	for id in ids:
		total += level_of(id)
	return total / ids.size()


## Average level of the strongest pack this player could field (the pet plus the highest-level
## animals), whoever is in the lineup right now. Zombies scale to this, so benching doesn't fool them.
func strongest_pack_level() -> int:
	var levels: Array[int] = []
	for id in unlocked:
		levels.append(level_of(id))
	levels.sort()
	levels.reverse()
	levels = levels.slice(0, locals_needed())
	if has_pet():
		levels.append(level_of(pet_species))
	if levels.is_empty():
		return 1
	var total := 0
	for level in levels:
		total += level
	return total / levels.size()


## Lets animals join the pack; returns the ones that are new. A recruit starts at
## RECRUIT_LEVEL_SHARE of the strongest pack's level and waits in the Stable if the pack is full.
func unlock(ids: Array) -> Array[String]:
	var fresh: Array[String] = []
	var start_level := maxi(1, roundi(strongest_pack_level() * GameData.RECRUIT_LEVEL_SHARE))
	for id: String in ids:
		if id in unlocked:
			continue
		unlocked.append(id)
		fresh.append(id)
		xp[id] = maxi(xp.get(id, 0), GameData.xp_to_reach(start_level))
		if active().size() > active_slots():
			stable.append(id)
	if not fresh.is_empty():
		auto_fill_duties()
	return fresh


## --- The Stable ---

## Wild animals in the pack (fighters and reserves), as opposed to the Stable.
func active() -> Array[String]:
	var out: Array[String] = []
	for id in unlocked:
		if id not in stable:
			out.append(id)
	return out


## Wild animals the pack holds besides the pet: PACK_LIMIT counts the pet too.
func active_slots() -> int:
	return GameData.PACK_LIMIT - (1 if has_pet() else 0)


## Sends a reserve to the Stable (free). Fighters have to be benched first.
func send_to_stable(id: String) -> void:
	if id in unlocked and id not in team and id not in stable:
		stable.append(id)
		clear_duty(id)
		auto_fill_duties()


## Brings an animal back from the Stable into a free slot. The campaign charges the map turn.
func can_leave_stable(id: String) -> bool:
	return id in stable and active().size() < active_slots()


func leave_stable(id: String) -> void:
	if can_leave_stable(id):
		stable.erase(id)
		auto_fill_duties()


## Keeps the roster legal: fighters are never stabled, and a pack over PACK_LIMIT (older saves, or a
## pet added in Setup) sends its lowest-level reserves to the Stable.
func normalize_roster() -> void:
	for id in stable.duplicate():
		if id in team or id not in unlocked:
			stable.erase(id)
	var reserves: Array[String] = []
	for id in active():
		if id not in team:
			reserves.append(id)
	reserves.sort_custom(func(a: String, b: String) -> bool: return level_of(a) < level_of(b))
	while active().size() > active_slots() and not reserves.is_empty():
		stable.append(reserves.pop_front())
	for duty in duties.keys():
		if duties[duty] in stable:
			duties.erase(duty)
	auto_fill_duties()


## --- Rows ---

func row_of(unit_id: String) -> String:
	var data: Dictionary = GameData.PETS.get(unit_id, GameData.ANIMALS.get(unit_id, {}))
	return rows.get(unit_id, GameData.default_row(data.get("role", "")))


func toggle_row(unit_id: String) -> void:
	var data: Dictionary = GameData.PETS.get(unit_id, GameData.ANIMALS.get(unit_id, {}))
	var next := "back" if row_of(unit_id) == "front" else "front"
	if next == GameData.default_row(data.get("role", "")):
		rows.erase(unit_id)
	else:
		rows[unit_id] = next


## Why two owned trinkets can't be fused right now ("" if they can).
func fuse_block(a: String, b: String) -> String:
	if a == b and trinkets.count(a) < 2:
		return "You need two of it to fuse it with itself."
	return GameData.fuse_block(a, b)


## Fuses two trinkets into one with both effects; both are used up (taken off whoever wore them
## if no spare copy is lying around). Returns the new trinket's id, or "" if they can't be fused.
func fuse(a: String, b: String) -> String:
	if fuse_block(a, b) != "":
		return ""
	for id in [a, b]:
		if trinkets_free(id) <= 0:
			for wearer in equipped.keys():
				if equipped[wearer] == id:
					equipped.erase(wearer)
					break
		trinkets.erase(id)
	var fused := GameData.fused_id(a, b)
	trinkets.append(fused)
	return fused


## How many copies of a trinket nobody is wearing.
func trinkets_free(trinket_id: String) -> int:
	var worn := 0
	for unit_id in equipped:
		if equipped[unit_id] == trinket_id:
			worn += 1
	return trinkets.count(trinket_id) - worn


## Puts a trinket on a unit ("" takes it off). If every copy is worn, it moves from another wearer.
func equip(unit_id: String, trinket_id: String) -> void:
	if trinket_id == "":
		equipped.erase(unit_id)
		return
	if equipped.get(unit_id, "") == trinket_id:
		return
	if trinkets_free(trinket_id) <= 0:
		for other in equipped.keys():
			if equipped[other] == trinket_id:
				equipped.erase(other)
				break
	equipped[unit_id] = trinket_id


func locals_needed() -> int:
	return GameData.PARTY_SIZE - (1 if has_pet() else 0)


func is_complete() -> bool:
	return GameData.REGIONS.has(region) and team.size() == locals_needed() \
		and (not has_pet() or (GameData.PETS.has(pet_species) and pet_name != ""))


func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("profile", "region", region)
	cfg.set_value("profile", "zip", zip)
	cfg.set_value("profile", "town", town)
	cfg.set_value("profile", "pet_species", pet_species)
	cfg.set_value("profile", "pet_name", pet_name)
	cfg.set_value("profile", "team", Array(team))
	cfg.set_value("profile", "xp", xp)
	cfg.set_value("profile", "unlocked", Array(unlocked))
	cfg.set_value("profile", "stable", Array(stable))
	cfg.set_value("profile", "trinkets", Array(trinkets))
	cfg.set_value("profile", "equipped", equipped)
	cfg.set_value("profile", "tree", tree)
	cfg.set_value("profile", "injuries", injuries)
	cfg.set_value("profile", "fatigue", fatigue)
	cfg.set_value("profile", "duties", duties)
	cfg.set_value("profile", "rows", rows)
	cfg.set_value("profile", "auto_battle", auto_battle)
	cfg.set_value("profile", "fixes", Array(fixes))
	cfg.set_value("profile", "siege_claimed", Array(siege_claimed))
	cfg.set_value("profile", "siege_rewards", siege_rewards)
	cfg.set_value("profile", "siege_seen", siege_seen)
	cfg.set_value("profile", "dungeon_best", dungeon_best)
	cfg.set_value("profile", "dungeon_paid", dungeon_paid)
	cfg.set_value("profile", "team_xp", team_xp)
	cfg.set_value("profile", "raids_claimed", Array(raids_claimed))
	cfg.set_value("profile", "team_id", team_id)
	cfg.set_value("profile", "slot", Saves.slot_of(save_path))  # so a cloud copy comes back to this game
	cfg.save(save_path)
	if Saves.is_slot(save_path):
		SaveHooks.saved()


## The saved profile, or null if there isn't a valid one yet.
static func load_saved() -> Profile:
	var cfg := ConfigFile.new()
	if cfg.load(save_path) != OK:
		return null
	var p := Profile.new()
	p.region = cfg.get_value("profile", "region", "")
	p.zip = cfg.get_value("profile", "zip", "")
	p.town = cfg.get_value("profile", "town", "")
	p.pet_species = cfg.get_value("profile", "pet_species", "")
	p.pet_name = cfg.get_value("profile", "pet_name", "")
	p.team.assign(cfg.get_value("profile", "team", []))
	p.xp = cfg.get_value("profile", "xp", {})
	p.unlocked.assign(cfg.get_value("profile", "unlocked", []))
	p.stable.assign(cfg.get_value("profile", "stable", []))
	p.trinkets.assign(cfg.get_value("profile", "trinkets", []))
	p.equipped = cfg.get_value("profile", "equipped", {})
	# Older saves' level-up picks aren't carried over: every level's point comes back to spend in
	# the tech tree.
	p.tree = cfg.get_value("profile", "tree", {})
	p.injuries = cfg.get_value("profile", "injuries", {})
	p.fatigue = cfg.get_value("profile", "fatigue", {})
	p.duties = cfg.get_value("profile", "duties", {})
	p.rows = cfg.get_value("profile", "rows", {})
	p.auto_battle = cfg.get_value("profile", "auto_battle", false)
	p.fixes.assign(cfg.get_value("profile", "fixes", []))
	p.siege_claimed.assign(cfg.get_value("profile", "siege_claimed", []))
	p.siege_rewards = cfg.get_value("profile", "siege_rewards", {})
	p.siege_seen = cfg.get_value("profile", "siege_seen", {})
	p.dungeon_best = cfg.get_value("profile", "dungeon_best", {})
	p.dungeon_paid = cfg.get_value("profile", "dungeon_paid", {})
	p.team_xp = cfg.get_value("profile", "team_xp", {})
	p.raids_claimed.assign(cfg.get_value("profile", "raids_claimed", []))
	p.team_id = cfg.get_value("profile", "team_id", "")
	for duty in p.duties.keys():
		if p.duties[duty] in p.team:
			p.duties.erase(duty)
	if not p.is_complete():
		return null
	# Saves from before recruiting existed: the home animals and current team are unlocked.
	p.unlock(GameData.REGIONS[p.region].animals)
	p.unlock(p.team)
	p.normalize_roster()
	return p


## How many of `week`'s siege stages this pack has claimed.
func siege_claimed_stages(week: int) -> int:
	return maxi(int(siege_rewards.get(week, 0)), 1 if week in siege_claimed else 0)


## Claims the rewards of `week`'s siege stages up to `broken` (how many have fallen). Returns what was
## gained, or "" if there's nothing new.
func claim_siege(week: int, broken: int) -> String:
	var from := siege_claimed_stages(week)
	if broken <= from:
		return ""
	siege_rewards[week] = broken
	var lines: PackedStringArray = []
	var xp_share := 0.0
	for k in range(from, broken):
		var stage: Dictionary = GameData.SIEGE_STAGES[k]
		xp_share += float(stage.xp)
		var found := ""
		if stage.trinket == "cache":
			found = GameData.CACHE_TRINKETS.pick_random()
		elif stage.trinket == "legendary":
			found = GameData.LEGENDS[GameData.LEGENDS.keys().pick_random()].drop
		if found != "":
			trinkets.append(found)
			lines.append("%s: found the %s! Equip it from Pack." % [stage.name, GameData.trinket(found).name])
	for id in active():
		var level_cost := GameData.xp_to_reach(level_of(id) + 1) - GameData.xp_to_reach(level_of(id))
		if add_xp(id, roundi(level_cost * xp_share)) > 0:
			lines.append("%s reached Lv %d!" % [unit_name(id), level_of(id)])
	lines.append("The pack gains %s level%s of XP." % [str(xp_share), "" if xp_share <= 1.0 else "s"])
	save()
	return "\n".join(lines)


## Collects XP teammates' battles have earned this pack (`owed`: the all-time total on team map
## `key`) for every animal in the pack. Returns the XP each gained (0 if nothing new).
func collect_team_xp(key: String, owed: int) -> int:
	var gained := owed - int(team_xp.get(key, 0))
	if key == "" or gained <= 0:
		return 0
	team_xp[key] = owed
	for id in pack_ids():
		add_xp(id, gained)
	save()
	return gained


## The critters this player brings to a legend raid (`picks`, up to GameData.RAID_PICKS from the
## pack; the fighting lineup if empty), with what every device needs to field them exactly as
## here: levels, tech trees, trinkets, rows, injuries and fatigue. JSON with sorted keys.
func snapshot(picks: Array = []) -> String:
	var ids: Array = picks if not picks.is_empty() else Array(pack_ids())
	var pet_in := has_pet() and pet_species in ids
	var snap := {"pet_species": pet_species if pet_in else "", "pet_name": pet_name if pet_in else "",
		"team": ids.filter(func(id: String) -> bool: return id != pet_species),
		"xp": {}, "tree": {}, "equipped": {}, "rows": {}, "injuries": {}, "fatigue": {}}
	for id: String in ids:
		snap.xp[id] = int(xp.get(id, 0))
		for field in ["tree", "equipped", "rows", "injuries", "fatigue"]:
			var source: Dictionary = get(field)
			if source.has(id):
				snap[field][id] = source[id]
	return JSON.stringify(snap, "", true)


## A player's raid pack from their snapshot(), ready for build_unit(); null if it can't be read.
static func from_snapshot(text: String) -> Profile:
	var d: Variant = JSON.parse_string(text)
	if not d is Dictionary:
		return null
	var p := Profile.new()
	p.pet_species = String(d.get("pet_species", ""))
	p.pet_name = String(d.get("pet_name", ""))
	p.team.assign(d.get("team", []))
	for id in d.get("xp", {}):
		p.xp[id] = int(d.xp[id])
	p.tree = d.get("tree", {})
	p.equipped = d.get("equipped", {})
	p.rows = d.get("rows", {})
	for id in d.get("injuries", {}):
		p.injuries[id] = int(d.injuries[id])
	for id in d.get("fatigue", {}):
		p.fatigue[id] = int(d.fatigue[id])
	return p


## Collects this player's share of a finished legend raid, once: the split XP for the critters
## they brought (and bench XP as usual), injuries for those knocked out, and the legend's trinket
## on a win. `outcome`: {won, xp, knocked: {account id: [ids]}, legend}. Returns lines to show.
func claim_raid(raid_id: String, outcome: Dictionary, brought: Array, account: String) -> PackedStringArray:
	if raid_id == "" or raid_id in raids_claimed:
		return PackedStringArray()
	raids_claimed.append(raid_id)
	var fought: Array[String] = []
	for id: String in brought:
		if id == pet_species or id in unlocked:
			fought.append(id)
	var downed: Array[String] = []
	downed.assign(outcome.get("knocked", {}).get(account, []))
	var won := bool(outcome.get("won", false))
	var lines := after_battle(fought, downed, int(outcome.get("xp", 0)), won)
	var legend := String(outcome.get("legend", ""))
	if won and GameData.LEGENDS.has(legend):
		var drop: String = GameData.LEGENDS[legend].drop
		trinkets.append(drop)
		lines.append("Everyone who fought gets the %s! Equip it from Pack." % GameData.trinket(drop).name)
	save()
	return lines


## The pack cleared dungeon wave `n` in `region`'s dungeon: records it, and pays any reward for a
## depth reached for the first time. Returns what was gained ("" if nothing new).
func clear_dungeon_wave(region: String, n: int) -> String:
	dungeon_best[region] = maxi(int(dungeon_best.get(region, 0)), n)
	var lines: PackedStringArray = []
	var paid := int(dungeon_paid.get(region, 0))
	var xp_share := 0.0
	for depth: int in GameData.DUNGEON_REWARDS:
		if depth <= paid or depth > n:
			continue
		var reward: Dictionary = GameData.DUNGEON_REWARDS[depth]
		xp_share += float(reward.get("xp", 0.0))
		var found := ""
		match reward.get("trinket", ""):
			"cache":
				found = GameData.CACHE_TRINKETS.pick_random()
			"legendary":
				found = GameData.LEGENDS[GameData.LEGENDS.keys().pick_random()].drop
			"dungeon":
				found = GameData.dungeon(region).trinket
		if found != "":
			trinkets.append(found)
			lines.append("Wave %d: found the %s! Equip it from Pack." % [depth, GameData.trinket(found).name])
	if n > paid:
		dungeon_paid[region] = maxi(paid, n)
	if xp_share > 0.0:
		for id in pack_ids() + active().filter(func(a: String) -> bool: return a not in pack_ids()):
			var level_cost := GameData.xp_to_reach(level_of(id) + 1) - GameData.xp_to_reach(level_of(id))
			if add_xp(id, roundi(level_cost * xp_share)) > 0:
				lines.append("%s reached Lv %d!" % [unit_name(id), level_of(id)])
		lines.append("The pack gains %s level%s of XP." % ["half a" if xp_share == 0.5 else str(xp_share), "" if xp_share <= 1.0 else "s"])
	save()
	return "\n".join(lines)


## The waves a dungeon run can start on: the first, and every checkpoint already cleared.
func dungeon_starts(region: String) -> Array[int]:
	var starts: Array[int] = [1]
	var best := int(dungeon_best.get(region, 0))
	var checkpoint := GameData.DUNGEON_CHECKPOINT
	while checkpoint <= best:
		starts.append(checkpoint + 1)
		checkpoint += GameData.DUNGEON_CHECKPOINT
	return starts


## How this pack appears on the siege leaderboard: pet (or lead animal) and region, never the town.
func siege_name() -> String:
	var lead := pet_name if has_pet() else (unit_name(team[0]) + "'s pack" if not team.is_empty() else "A pack")
	return ("%s · %s" % [lead, GameData.REGIONS[region].name]).left(40) if GameData.REGIONS.has(region) else lead.left(40)


static func clear_saved() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))


## Best guess at the player's home region from device locale and time zone (no location permission).
static func detect_region() -> String:
	var country := OS.get_locale().get_slice("_", 1).left(2).to_upper()
	for region_id in COUNTRY_REGIONS:
		if country in COUNTRY_REGIONS[region_id]:
			return region_id
	var tz := Time.get_time_zone_from_system()
	var tz_name: String = tz.get("name", "")
	for hint in WEST_TIME_ZONE_HINTS:
		if hint in tz_name:
			return "na_west"
	return "na_west" if tz.get("bias", 0) <= -420 else "na_east"
