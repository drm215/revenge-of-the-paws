extends SceneTree

## A territory's threat and level stay as they were when it was discovered. Only the horde spreading
## or a lost counter defense change them, and teammates all see the same numbers.

var _fails := 0


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


func _init() -> void:
	_run.call_deferred()


func _pack(level: int, zip := "24210") -> Profile:
	var p := Profile.new()
	p.region = "us_appalachia"
	p.zip = zip
	p.town = "x"
	p.pet_species = "dog"
	p.pet_name = "Jack"
	p.team.assign(["black_bear", "horned_owl"])
	p.unlocked.assign(["black_bear", "horned_owl"])
	_set_level(p, level)
	return p


func _set_level(p: Profile, level: int) -> void:
	for id in p.unlocked + ["dog"]:
		p.xp[id] = GameData.xp_to_reach(level)


## Every unheld territory: id -> [threat, level].
func _numbers(c: Campaign) -> Dictionary:
	var out := {}
	for i in c.territories.size():
		if not c.territories[i].owned:
			out[c.territories[i].id] = [c.territories[i].threat, c.territory_level(i)]
	return out


## Unheld territories that were in `before`, with what changed.
func _changes(c: Campaign, before: Dictionary) -> Array:
	var out := []
	var now := _numbers(c)
	for id in before:
		if now.has(id) and now[id] != before[id]:
			out.append("%s %s -> %s" % [id, before[id], now[id]])
	return out


func _attackable(c: Campaign) -> int:
	for i in c.territories.size():
		if c.can_attack(i) and c.territories[i].boss == "":
			return i
	return -1


func _run() -> void:
	Profile.save_path = "user://tl_profile.cfg"
	Campaign.save_path = "user://tl_campaign.cfg"
	var p := _pack(1)
	var c := Campaign.create(p)
	c.nests.clear()  # no spreading while this part checks everything else
	var before := _numbers(c)

	# The pack grows: nothing out there does.
	_set_level(p, 30)
	_check(_changes(c, before).is_empty(), "the pack reaching Lv 30 changes nothing: %s" % [_changes(c, before)])

	# Liberating territories leaves the others as they were (on land already discovered).
	for k in 12:
		var i := _attackable(c)
		c.under_attack = -1
		c.resolve_battle(i, true, 0, [], false)
	var changed := _changes(c, before)
	_check(changed.is_empty(), "12 liberations change nothing on discovered land: %s" % [changed])
	var fight: int = _attackable(c)
	_check(c.battle_config(fight).zombie_mult == c.zombie_strength(fight, c.territories[fight].threat), "the fight is at the level the map shows")

	# Land discovered later matches the pack as it was then, and stays there.
	var found := -1
	for i in range(c.base_count, c.territories.size()):
		if not c.territories[i].owned and c.territories[i].boss == "":
			found = i
			break
	_check(found >= 0, "liberating revealed new ground")
	_check(c.territories[found].met_level == p.strongest_pack_level(), "it's dated to the pack that found it (Lv %d)" % c.territories[found].met_level)
	var level_then := c.territory_level(found)
	_check(level_then > c.base_level(found), "its zombies are matched to that pack (Lv %d, usually %d)" % [level_then, c.base_level(found)])
	_set_level(p, 45)
	_check(c.territory_level(found) == level_then, "and stay that way as the pack grows")

	# Saved and loaded: same numbers, even with a stronger pack.
	var numbers := _numbers(c)
	c.save()
	var reloaded := Campaign.create(p)
	_check(_numbers(reloaded) == numbers, "a reload keeps every number")

	# The shared map: a teammate with a very different pack sees the same numbers.
	var members := [{"user_id": "u1", "name": "A", "zip": "24210"}, {"user_id": "u2", "name": "B", "zip": "24210"}]
	var team_a := Campaign.create(_pack(25), {"id": "t1", "state": "", "members": members})
	var team_b := Campaign.create(_pack(3), {"id": "t1", "state": team_a.to_text(), "members": members})
	_check(_numbers(team_b) == _numbers(team_a), "teammates with Lv 25 and Lv 3 packs see the same numbers")
	var saved_c := team_a.to_text()
	_check("met_levels" in saved_c, "the shared map carries them")

	# A save from before this: frozen at what it shows now.
	var old := ConfigFile.new()
	old.parse(c.to_text())
	old.erase_section_key("campaign", "met_levels")
	old.save(Campaign.save_path)
	var older := Campaign.create(_pack(20))
	for i in older.territories.size():
		if older.territories[i].met_level != 20:
			_check(false, "an old save freezes at today's pack")
			break
	_check(older.territories[0].met_level == 20, "an old save dates everything to today's pack")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Campaign.save_path))

	# The horde spreading raises threat and level.
	p = _pack(10)
	c = Campaign.create(p)
	before = _numbers(c)
	c.turn = GameData.MIGRATE_EVERY - 1
	c.under_attack = -1
	c.turn = 0
	c._migrate()
	changed = _changes(c, before)
	_check(not changed.is_empty(), "a nest spreading changes what it reaches: %s" % [changed])
	var spread_id: String = c.spread.keys()[0]
	var now := _numbers(c)
	_check(now[spread_id][0] == before[spread_id][0] + 1, "+1 threat")
	_check(now[spread_id][1] >= before[spread_id][1], "and its level doesn't drop")

	# A failed attack only thins the horde there.
	var hit := _attackable(c)
	var level_before := c.territory_level(hit)
	var threat_before := c.territories[hit].threat
	c.under_attack = -1
	c.resolve_battle(hit, false, 0, [], false)
	_check(c.territories[hit].threat == threat_before and c.territory_level(hit) <= level_before, "a failed attack doesn't toughen it")

	# Counter defense: winning changes nothing; losing raises threat and level, and stays.
	var held := -1
	for i in c.territories.size():
		if c.territories[i].owned and i != c.home:
			held = i
	if held < 0:
		c.under_attack = -1
		var i0 := _attackable(c)
		c.resolve_battle(i0, true, 0, [], false)
		held = i0
	var threat0 := c.territories[held].threat
	var level0 := c.territory_level(held)
	c.under_attack = held
	c.resolve_battle(held, true, 0, [], false)
	_check(c.territories[held].threat == threat0 and c.territory_level(held) == level0, "a won defense changes nothing")
	c.under_attack = held
	c.resolve_battle(held, false, 0, [], false)
	_check(not c.territories[held].owned and c.territories[held].threat == threat0 + 1, "a lost defense: +1 threat (%d to %d)" % [threat0, c.territories[held].threat])
	_check(c.territory_level(held) > level0, "and a higher level (%d to %d)" % [level0, c.territory_level(held)])
	var lost_id := c.territories[held].id
	var threat1 := c.territories[held].threat
	c.save()
	var after_load := Campaign.create(p)
	var kept := false
	for t in after_load.territories:
		if t.id == lost_id:
			kept = t.threat == threat1
	_check(kept, "which survives a reload")
	print("%d failure(s)" % _fails)
	quit()
