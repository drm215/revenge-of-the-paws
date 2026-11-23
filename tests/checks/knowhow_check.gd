extends SceneTree

## Know-how and ground training in the tech tree (GameData.KNOWHOW, GROUND_*): which critters can
## learn what, that the nodes reach the battle unit, and what each does in a fight: longer taunts,
## a stronger guard, stuns shaken off, and extra ATK/DEF on trained terrain.

var _fails := 0


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


func _profile(nodes: Array = []) -> Profile:
	var p := Profile.new()
	p.region = "us_appalachia"
	p.team.assign(["black_bear", "bobcat", "horned_owl"])
	p.unlocked.assign(p.team)
	p.xp["black_bear"] = GameData.xp_to_reach(40)
	for id in nodes:
		_check(p.buy_node("black_bear", id), "(buys %s)" % id)
	return p


func _init() -> void:
	# Who can learn what.
	var bear := GameData.knowhow_kinds("black_bear")
	_check("taunt" in bear and "guard" in bear, "the bear's Roar taunts and guards: it can learn both: %s" % [bear])
	_check("stun_resist" in bear and "infect_resist" in bear, "everyone can learn to shake off stuns and infection")
	var everyone_resists := true
	var someone_lacks_taunt := false
	for id in GameData.ANIMALS:
		var kinds := GameData.knowhow_kinds(id)
		everyone_resists = everyone_resists and "stun_resist" in kinds and "infect_resist" in kinds
		someone_lacks_taunt = someone_lacks_taunt or "taunt" not in kinds
	_check(everyone_resists and someone_lacks_taunt, "only critters whose skills taunt get taunt know-how")
	var node := GameData.tree_node("black_bear", "ground_forest3")
	_check(node.get("requires", []) == ["ground_forest2"] and node.kind == "ground", "ground training is bought one step after another")

	# The nodes reach the fighting unit.
	var nodes := ["know_taunt1", "know_taunt2", "know_guard1", "know_guard2", "know_guard3", "know_guard4",
		"know_stun_resist1", "know_stun_resist2", "know_stun_resist3", "know_stun_resist4",
		"ground_forest1", "ground_forest2", "ground_forest3"]
	var p := _profile(nodes)
	_check(not p.buy_node("black_bear", "know_taunt3"), "taunt know-how stops at its limit")
	var u := p.build_unit("black_bear")
	_check(u.knowhow == {"taunt": 2, "guard": 4, "stun_resist": 4} and u.ground == {"forest": 3}, "the unit carries it: %s %s" % [u.knowhow, u.ground])

	# Guard: x1.6 DEF becomes x2.0.
	u.add_status("guard", 2)
	var plain := _profile().build_unit("black_bear")
	plain.add_status("guard", 2)
	_check(is_equal_approx(u.effective_def() / u.def, 2.0) and is_equal_approx(plain.effective_def() / plain.def, 1.6),
		"guard know-how: x%.1f DEF instead of x%.1f" % [u.effective_def() / u.def, plain.effective_def() / plain.def])

	# Taunt lasts 2 turns longer.
	var b := Battle.new(p, [["shambler"]], 1.0, 1.0, "test", 7)
	b.start_next_wave()
	var trained_bear: Combatant = b.party.filter(func(c: Combatant) -> bool: return c.id == "black_bear")[0]
	b.use_skill(trained_bear, "roar", trained_bear)
	var pb := Battle.new(_profile(), [["shambler"]], 1.0, 1.0, "test", 7)
	pb.start_next_wave()
	var plain_bear: Combatant = pb.party.filter(func(c: Combatant) -> bool: return c.id == "black_bear")[0]
	pb.use_skill(plain_bear, "roar", plain_bear)
	var longer := int(trained_bear.statuses.get("taunt", 0)) - int(plain_bear.statuses.get("taunt", 0))
	_check(longer == 2, "Roar taunts 2 turns longer (%d vs %d)" % [int(trained_bear.statuses.get("taunt", 0)), int(plain_bear.statuses.get("taunt", 0))])

	# Ground training: +15% ATK and DEF in the forest only, on top of anything else.
	var forest := Battle.new(p, [["shambler"]], 1.0, 1.0, "test", 7, "desert")
	var trained_forest := Battle.new(p, [["shambler"]], 1.0, 1.0, "test", 7, "forest")
	var untrained_forest := Battle.new(_profile(), [["shambler"]], 1.0, 1.0, "test", 7, "forest")
	var atk_in := func(battle: Battle) -> int:
		return battle.party.filter(func(c: Combatant) -> bool: return c.id == "black_bear")[0].atk
	var ratio := float(atk_in.call(trained_forest)) / float(atk_in.call(untrained_forest))
	_check(absf(ratio - 1.15) < 0.02, "trained for the forest: +15%% ATK there (x%.3f)" % ratio)
	var untrained_desert := Battle.new(_profile(), [["shambler"]], 1.0, 1.0, "test", 7, "desert")
	_check(atk_in.call(forest) == atk_in.call(untrained_desert), "and nothing on other ground")

	# Shaking off stuns: a Screamer's 40% stun lands about 40% x 60% = 24% of the time.
	var landed := {"trained": 0, "plain": 0}
	for k in 400:
		for who in ["trained", "plain"]:
			var fight := Battle.new(p if who == "trained" else _profile(), [["screamer"]], 1.0, 1.0, "test", 1000 + k)
			fight.start_next_wave()
			var target: Combatant = fight.party.filter(func(c: Combatant) -> bool: return c.id == "black_bear")[0]
			fight.use_skill(fight.enemies[0], "scream", target)
			if target.has_status("stunned"):
				landed[who] += 1
	print("     stunned by Scream: trained %d / 400, untrained %d / 400" % [landed.trained, landed.plain])
	_check(landed.plain > 130 and landed.plain < 190 and landed.trained > 70 and landed.trained < 125,
		"stun know-how shakes off about 40% of stuns")

	print("%d failure(s)" % _fails)
	quit(1 if _fails else 0)
