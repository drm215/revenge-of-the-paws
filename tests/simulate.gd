extends SceneTree

## Headless balance check: plays many full runs per home region, with and without a pet,
## using random local teams and a simple "decent player" AI.
##   godot --headless --path . --script res://tests/simulate.gd

const RUNS := 300


func _init() -> void:
	# Never touch the player's real saves.
	Profile.save_path = "user://sim_profile.cfg"
	Campaign.save_path = "user://sim_campaign.cfg"
	print("%-22s %10s %10s %10s" % ["region", "no pet", "pet", "random AI"])
	for region_id in GameData.REGIONS:
		var no_pet := _win_rate(region_id, false, true)
		var pet := _win_rate(region_id, true, true)
		var rand := _win_rate(region_id, false, false)
		print("%-22s %9.1f%% %9.1f%% %9.1f%%" % [region_id, no_pet, pet, rand])

	print("\ncampaigns (decent player, random local team):")
	for zip in ["25550", "24273", "10001", "60614", "59001", "96720", "33101", "78201"]:
		var t0 := Time.get_ticks_msec()
		var info := ZipDB.lookup(zip)
		for with_pet in [false, true]:
			var rng := RandomNumberGenerator.new()
			rng.seed = 7
			var p := _random_profile(info.region, with_pet, rng)
			p.zip = zip
			p.unlock(GameData.REGIONS[p.region].animals)
			var r := play_campaign(p, 7)
			print("  %s %-16s pet=%-5s liberated=%-5s turns=%d losses=%d end level=%d recruits=%d trinkets=%d" % [
				zip, info.place, with_pet, r.won, r.turns, r.losses, r.level, r.recruits, r.trinkets])
		print("    (%d ms)" % (Time.get_ticks_msec() - t0))
	quit()


func _win_rate(region_id: String, with_pet: bool, smart: bool) -> float:
	var wins := 0
	for i in RUNS:
		var rng := RandomNumberGenerator.new()
		rng.seed = i
		if _play(_random_profile(region_id, with_pet, rng), i, smart, rng):
			wins += 1
	return 100.0 * wins / RUNS


func _random_profile(region_id: String, with_pet: bool, rng: RandomNumberGenerator) -> Profile:
	var p := Profile.new()
	p.region = region_id
	if with_pet:
		var species: Array = GameData.PETS.keys()
		p.pet_species = species[rng.randi_range(0, species.size() - 1)]
		p.pet_name = "Buddy"
	var pool: Array = GameData.REGIONS[region_id].animals.duplicate()
	while p.team.size() < p.locals_needed():
		p.team.append(pool.pop_at(rng.randi_range(0, pool.size() - 1)))
	return p


func _play(profile: Profile, seed_value: int, smart: bool, rng: RandomNumberGenerator) -> bool:
	var battle := Battle.new(profile, GameData.WAVES, 1.0, 1.0, "", seed_value)
	battle.start_next_wave()
	var turns := 0
	while true:
		var actor := battle.next_turn()
		if actor == null:
			match battle.outcome():
				Battle.Outcome.WAVE_CLEARED:
					battle.start_next_wave()
					continue
				Battle.Outcome.VICTORY:
					return true
				_:
					return false
		var plan: Dictionary
		if not actor.is_player:
			plan = battle.plan_enemy_action(actor)
		elif smart:
			plan = _smart(battle, actor)
		else:
			plan = _random(battle, actor, rng)
		battle.use_skill(actor, plan.skill, plan.target)
		turns += 1
		assert(turns < 5000, "battle never ended")
	return false


func _random(battle: Battle, actor: Combatant, rng: RandomNumberGenerator) -> Dictionary:
	var ready: Array[String] = []
	for id in actor.skills:
		if actor.can_use(id):
			ready.append(id)
	var skill_id := ready[rng.randi_range(0, ready.size() - 1)]
	var targets := battle.valid_targets(actor, skill_id)
	return {"skill": skill_id, "target": targets[rng.randi_range(0, targets.size() - 1)]}


func _smart(battle: Battle, actor: Combatant) -> Dictionary:
	return AutoBattle.pick_action(battle, actor)


## Whole-campaign check: a decent player conquers the map around a ZIP, answering counterattacks.
## Returns {won, turns, losses}.
func play_campaign(profile: Profile, seed_value: int) -> Dictionary:
	Campaign.clear_saved()
	var c := Campaign.create(profile)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var losses := 0
	while not _base_liberated(c) and c.turn < 300:
		var target := c.under_attack
		if target < 0:
			for i in c.territories.size():
				if i < c.base_count and c.can_attack(i) and (target < 0 or c.territories[i].threat < c.territories[target].threat):
					target = i
		_pick_lineup(profile)
		var cfg := c.battle_config(target)
		var result := _play_config(profile, cfg, rng.randi(), rng)
		var won: bool = result.won
		if not won:
			losses += 1
		var amount: int = result.xp if won else roundi(result.xp * GameData.DEFEAT_XP_SHARE)
		var fought: Array[String] = profile.pack_ids()
		var downed: Array[String] = []
		downed.assign(result.downed)
		profile.after_battle(fought, downed, amount, won)
		c.resolve_battle(target, won)
		_spend_picks(profile)
		# Wear any new trinket on the first pack member without one.
		for trinket_id in profile.trinkets:
			if profile.trinkets_free(trinket_id) > 0:
				for id in profile.pack_ids():
					if not profile.equipped.has(id):
						profile.equip(id, trinket_id)
						break
	Campaign.clear_saved()
	return {"won": _base_liberated(c), "turns": c.turn, "losses": losses, "legends": c.legends,
		"level": profile.pack_level(), "trinkets": profile.trinkets.size(), "recruits": profile.unlocked.size() - GameData.REGIONS[profile.region].animals.size()}


## A sensible player's lineup: skip injured animals, rest tired ones, keep the strongest.
func _pick_lineup(profile: Profile) -> void:
	var pool: Array[String] = []
	pool.assign(profile.active())
	pool.sort_custom(func(a: String, b: String) -> bool:
		var sa := profile.level_of(a) * 10 - (30 if profile.injuries.has(a) else 0) - roundi(profile.fatigue_penalty(a) * 100)
		var sb := profile.level_of(b) * 10 - (30 if profile.injuries.has(b) else 0) - roundi(profile.fatigue_penalty(b) * 100)
		return sa > sb)
	profile.team.assign(pool.slice(0, profile.locals_needed()))


## The frontier never runs out, so the sim's campaign is "liberate the starting map".
func _base_liberated(c: Campaign) -> bool:
	for i in c.base_count:
		if not c.territories[i].owned:
			return false
	return true


func _play_config(profile: Profile, cfg: Dictionary, seed_value: int, _rng: RandomNumberGenerator) -> Dictionary:
	return AutoBattle.play(profile, cfg, seed_value)


## Spends tech-tree points like a sensible player: signature and mastery as soon as they open,
## otherwise the branch with the fewest nodes so far.
func _spend_picks(profile: Profile) -> void:
	for id in profile.pack_ids() + profile.unlocked:
		while profile.points_left(id) > 0:
			var best := ""
			var best_rank := 999
			for node in GameData.tech_tree(id):
				if profile.tree_block(id, node.id) != "":
					continue
				var rank: int = node.tier
				if node.branch == "signature":
					rank = -1
				if rank < best_rank:
					best_rank = rank
					best = node.id
			if best == "" or not profile.buy_node(id, best):
				break
