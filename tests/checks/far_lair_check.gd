extends SceneTree

## A legend's lair far out on the frontier (threat 40+) is still a fight for the pack of the day:
## its legend is measured at threat 5 at most, solo and in a raid. Other land keeps its threat.

var _fails := 0


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


func _init() -> void:
	Profile.save_path = "user://far_profile.cfg"
	Campaign.save_path = "user://far_campaign.cfg"
	var p := Profile.new()
	p.region = "us_appalachia"
	p.zip = "24210"
	p.town = "Abingdon"
	p.pet_species = "cat"
	p.pet_name = "Mo"
	p.team.assign(["opossum", "red_fox"])
	p.unlocked.assign(p.team)
	for id in ["cat", "opossum", "red_fox"]:
		p.xp[id] = GameData.xp_to_reach(79)
	var c := Campaign.create(p)
	c.under_attack = -1
	var i := c.territories[c.home].neighbors[0]
	var t: Territory = c.territories[i]
	t.boss = "pope_lick_monster"
	t.owned = false
	t.threat = GameData.MAX_THREAT
	var near: float = c.battle_config(i).zombie_mult
	var near_raid: float = c.raid_config(i, 79).zombie_mult
	t.threat = 42
	var far: float = c.battle_config(i).zombie_mult
	var far_raid: float = c.raid_config(i, 79).zombie_mult
	_check(is_equal_approx(far, near), "a threat-42 lair's legend is as strong as at threat 5 (%.1f vs %.1f)" % [far, near])
	_check(is_equal_approx(far_raid, near_raid) and far_raid < 40.0, "in a raid too (%.1f vs %.1f; it was 92.6)" % [far_raid, near_raid])
	_check(c.territory_level(i) <= p.strongest_pack_level() + 2, "about the pack's level: Lv %d for a Lv %d pack" % [c.territory_level(i), p.strongest_pack_level()])
	t.boss = ""
	_check(c.battle_config(i).zombie_mult > far, "ordinary land keeps its own threat")
	print("%d failure(s)" % _fails)
	quit()
