extends SceneTree

## Battle.report(): a full AI lair fight fills in the setup, the critters and the legend.

var _fails := 0


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


func _init() -> void:
	var p := Profile.new()
	p.region = "us_appalachia"
	p.pet_species = "dog"
	p.pet_name = "Rex"
	p.team.assign(["black_bear", "bobcat"])
	p.unlocked.assign(["black_bear", "bobcat"])
	p.xp["dog"] = GameData.xp_to_reach(12)
	p.xp["black_bear"] = GameData.xp_to_reach(10)
	p.xp["bobcat"] = GameData.xp_to_reach(10)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var waves := GameData.generate_waves(GameData.MAX_THREAT, rng, "woodbooger")
	var mult := GameData.level_strength(12 - GameData.PACK_LEVEL_GAP + GameData.MAX_THREAT - 1)
	var b := Battle.new(p, waves, mult, 1.0, "lair", 4)
	b.configure({"legend": "woodbooger"})
	b.start_next_wave()
	var turns := 0
	while turns < 8000:
		var actor := b.next_turn()
		if actor == null:
			if b.outcome() == Battle.Outcome.WAVE_CLEARED:
				b.start_next_wave()
				continue
			break
		var plan := AutoBattle.pick_action(b, actor) if actor.is_player else b.plan_enemy_action(actor)
		b.use_skill(actor, plan.skill, plan.target)
		turns += 1
	var r := b.report()
	_check(r.outcome in ["victory", "defeat"], "outcome: %s" % r.outcome)
	_check(r.pack.size() == 3 and r.legends.size() == 1, "3 critters and 1 legend")
	_check(r.rounds.size() == r.wave, "rounds for each wave reached: %s" % [r.rounds])
	_check(int(r.legends[0].dealt) > 0 and int(r.pack[0].taken) > 0, "damage dealt and taken are tracked")
	_check(int(r.pack[0].lvl) == 12 and r.pack[0].leader, "the pet is level 12 and leads")
	_check(not r.pack[0].has("owner"), "no player names in the log")
	var size := JSON.stringify(r).length()
	_check(size < 65536, "fits the server's size limit (%d bytes)" % size)
	print("%d failure(s)" % _fails)
	quit()
