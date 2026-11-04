extends SceneTree

## Checks combos, rows and trinket fusion.

var _fails := 0


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


func _profile(team: Array) -> Profile:
	var p := Profile.new()
	p.region = "us_appalachia"
	p.team.assign(team)
	p.unlocked.assign(team)
	return p


func _init() -> void:
	# --- Rows ---
	var p := _profile(["black_bear", "bobcat", "horned_owl"])
	_check(p.row_of("black_bear") == "front" and p.row_of("horned_owl") == "back", "default rows: Tank front, Support back")
	p.toggle_row("bobcat")
	_check(p.row_of("bobcat") == "back" and p.rows.has("bobcat"), "toggling moves the Bobcat to the back")
	p.toggle_row("bobcat")
	_check(p.row_of("bobcat") == "front" and not p.rows.has("bobcat"), "toggling back to its default clears the override")

	var b := Battle.new(_profile(["black_bear", "bobcat", "opossum"]), [["shambler", "runner", "medic", "screamer"]], 1.0, 1.0, "t", 1)
	b.start_next_wave()
	var bear: Combatant = b.party[0]
	var shambler: Combatant = b.enemies[0]
	var medic: Combatant = b.enemies[2]
	var hits := b.valid_targets(bear, "scratch")
	_check(hits.size() == 2 and medic not in hits, "two zombies in front screen the back row (bear has %d targets)" % hits.size())
	_check(b.valid_targets(bear, "frenzy").size() == 4, "area attacks still hit all 4 zombies")
	var owl_b := Battle.new(_profile(["horned_owl", "bobcat", "opossum"]), [["shambler", "medic"]], 1.0, 1.0, "t", 1)
	owl_b.start_next_wave()
	_check(owl_b.valid_targets(owl_b.party[0], "peck").size() == 2, "a bird reaches the back row")
	b._apply_damage(shambler, 9999, false)
	_check(b.valid_targets(bear, "scratch").size() == 3, "one front-row zombie left: the back row is exposed")
	var r := Battle.new(_profile(["horned_owl", "bobcat", "opossum"]), [["runner"]], 1.0, 1.0, "t", 1)
	r.start_next_wave()
	var owl: Combatant = r.party[0]
	_check(owl.row == "back", "owl stands in the back")
	_check(owl in r.valid_targets(r.enemies[0], "lunge"), "a Runner reaches the back row")
	var s := Battle.new(_profile(["black_bear", "horned_owl", "opossum"]), [["shambler"]], 1.0, 1.0, "t", 1)
	_check(s.party[0].row == "front" and s.party[2].row == "front", "bear and opossum (Tanks) screen the owl")
	s.start_next_wave()
	_check(s.party[1] not in s.valid_targets(s.enemies[0], "claw"), "a Shambler can't reach the back-row owl")
	s.party[1].add_status("taunt", 2)
	_check(s.party[1] in s.valid_targets(s.enemies[0], "claw"), "unless the owl is taunting")
	# Back-row penalty: bobcat moved back hits softer (seeded rolls compared).
	var front_p := _profile(["black_bear", "bobcat", "opossum"])
	var back_p := _profile(["black_bear", "bobcat", "opossum"])
	back_p.toggle_row("bobcat")
	var dmg := []
	for prof in [front_p, back_p]:
		var bb := Battle.new(prof, [["brute"]], 1.0, 1.0, "t", 7)
		bb.start_next_wave()
		var brute: Combatant = bb.enemies[0]
		var before := brute.hp
		bb._deal_damage(bb.party[1], brute, 1.0, 0.0, true)
		dmg.append(before - brute.hp)
	print("     bobcat front %d vs back %d" % dmg)
	_check(dmg[1] < dmg[0], "back-row single-target hits are softer")

	# --- Combos ---
	var c := Battle.new(_profile(["black_bear", "bobcat", "opossum"]), [["brute"]], 1.0, 1.0, "t", 3)
	var combos: Array[String] = []
	c.combo.connect(func(_t: Combatant, n: String) -> void: combos.append(n))
	c.start_next_wave()
	var brute: Combatant = c.enemies[0]
	brute.add_status("stunned", 1)
	var crit := [false]
	c.damaged.connect(func(t: Combatant, _a: int, is_crit: bool) -> void:
		if t == brute:
			crit[0] = is_crit)
	c.use_skill(c.party[1], "pounce", brute)
	_check(crit[0] and "Opening" in combos, "Opening: Pounce always crits a stunned zombie")
	brute.statuses.clear()
	brute.add_status("weakened", 2)
	c.use_skill(c.party[0], "maul", brute)
	_check(brute.has_status("stunned") and "Knockdown" in combos, "Knockdown: Maul stuns a weakened zombie")
	_check("Follow-up" in combos, "Follow-up: the bear hit the zombie the bobcat just hit")
	combos.clear()
	c.use_skill(c.party[0], "scratch", brute)
	_check("Follow-up" not in combos, "no Follow-up when the same animal hits again")
	_check(GameData.combo_hint(GameData.skill("pounce")).contains("stunned"), "Pounce's description names its combo")
	_check(GameData.combo_hint(GameData.skill("dirty_trick")).contains("weaken"), "Dirty Trick's description names its setup")

	# --- Fusion ---
	var f := _profile(["black_bear", "bobcat", "opossum"])
	f.trinkets.assign(["moth_wing_charm", "hollow_bark_armor", "lake_pearl"])
	f.equip("black_bear", "hollow_bark_armor")
	var id := f.fuse("moth_wing_charm", "hollow_bark_armor")
	var t := GameData.trinket(id)
	_check(id != "" and f.trinkets.size() == 2 and id in f.trinkets, "fusing uses up both and adds one (%s)" % t.get("name", ""))
	_check(not f.equipped.has("black_bear"), "the bear's worn copy was taken off")
	_check(is_equal_approx(t.spd, 0.1) and is_equal_approx(t.def, 0.2), "effects add up: SPD %+.2f, DEF %+.2f" % [t.spd, t.def])
	print("     " + GameData.trinket_effects(id))
	_check(f.fuse(id, "lake_pearl") == "", "a fused trinket can't be fused again")
	_check(f.fuse("lake_pearl", "lake_pearl") == "", "can't fuse a single copy with itself")
	f.trinkets.append("lake_pearl")
	_check(f.fuse("lake_pearl", "lake_pearl") != "", "two copies fuse into a double")
	f.equip("bobcat", id)
	var unit := f.build_unit("bobcat")
	_check(unit.trinket == id, "a fused trinket equips and builds")
	_check(GameData.fuse_block("frogman_crown", "lake_pearl") == "", "ordinary trinkets fuse")

	print("%d failure(s)" % _fails)
	quit(1 if _fails > 0 else 0)
