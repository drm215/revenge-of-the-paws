extends SceneTree

## Brute targets (shown, kept, broken by a taunt), well-rested animals, the week's zombie mutation and
## the week's goal.

var _fails := 0


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


func _profile() -> Profile:
	var p := Profile.new()
	p.region = "us_appalachia"
	p.zip = "24210"
	p.town = "Abingdon"
	p.pet_species = "dog"
	p.pet_name = "Jack"
	p.team.assign(["black_bear", "horned_owl"])
	p.unlocked.assign(["black_bear", "horned_owl", "red_fox"])
	for id in ["dog", "black_bear", "horned_owl", "red_fox"]:
		p.xp[id] = GameData.xp_to_reach(15)
	return p


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	root.theme = Retro.make_theme()
	Saves.use(Saves.new_slot())
	_brute()
	_rested()
	_mutations()
	_goal()
	print("%d failure(s)" % _fails)
	quit()


func _brute() -> void:
	var p := _profile()
	var b := Battle.new(p, [["brute"]], 1.0, 1.0, "x", 7)
	b.start_next_wave()
	var brute: Combatant = b.enemies[0]
	brute.cooldowns["rampage"] = 9  # single-target hits only, for this check
	_check(brute.eyeing != null and brute.eyeing in b.party, "the Brute picks a target as its wave starts: %s" % (brute.eyeing.display_name if brute.eyeing else "none"))
	var hurt: Combatant = null
	for c in b.reachable(brute):
		if c != brute.eyeing:
			hurt = c
			break
	hurt.hp = 5
	b._end_turn(brute)
	_check(brute.eyeing == hurt and b.eyed_by(hurt) == brute, "after its turn it eyes the most hurt animal it can reach (%s)" % hurt.display_name)
	var hits := 0
	for k in 20:
		if b.plan_enemy_action(brute).target == hurt:
			hits += 1
	_check(hits == 20, "it goes for that animal every time (%d/20)" % hits)
	var tank: Combatant = b.party[0] if b.party[0] != hurt else b.party[1]
	tank.add_status("taunt", 2)
	_check(b.plan_enemy_action(brute).target == tank, "a taunt pulls it away")
	var card := UnitCard.new()
	card.battle = b
	root.add_child(card)
	card.setup(hurt, 60)
	card.refresh()
	_check("BRUTE'S TARGET" in card.status_text(), "the target's card says so: " + card.status_text())
	card.queue_free()


func _rested() -> void:
	var p := _profile()
	for k in GameData.RESTED_AFTER - 1:
		p.after_battle(p.pack_ids(), [], 10)
	_check(not p.rested.has("red_fox"), "not rested after %d fights on the bench" % (GameData.RESTED_AFTER - 1))
	var lines := p.after_battle(p.pack_ids(), [], 10)
	_check(int(p.rested.get("red_fox", 0)) == GameData.RESTED_BATTLES and "\n".join(lines).contains("well rested"),
		"well rested after sitting out %d in a row" % GameData.RESTED_AFTER)
	_check(not p.rested.has("black_bear"), "fighters don't get it")
	p.team.assign(["red_fox", "horned_owl"])
	var b := Battle.new(p, [["shambler"]])
	var fox: Combatant = b.party.filter(func(c: Combatant) -> bool: return c.id == "red_fox")[0]
	var plain_profile := _profile()
	plain_profile.team.assign(["red_fox", "horned_owl"])
	var plain_fox: Combatant = Battle.new(plain_profile, [["shambler"]]).party.filter(func(c: Combatant) -> bool: return c.id == "red_fox")[0]
	_check(fox.atk > plain_fox.atk and "Well rested" in fox.notes, "a rested animal fights harder (%d vs %d ATK)" % [fox.atk, plain_fox.atk])
	var before := int(p.xp.red_fox)
	p.after_battle(p.pack_ids(), [], 100)
	_check(int(p.xp.red_fox) - before == roundi(100 * GameData.RESTED_XP), "and earns more XP (+%d)" % (int(p.xp.red_fox) - before))
	for k in GameData.RESTED_BATTLES - 1:
		p.after_battle(p.pack_ids(), [], 10)
	_check(not p.rested.has("red_fox"), "it wears off after %d fights" % GameData.RESTED_BATTLES)


func _mutations() -> void:
	GameData.mutations_off = false
	var by_id := {}
	for m: Dictionary in GameData.MUTATIONS:
		by_id[m.id] = m
	var p := _profile()
	# Frost: zombies slower and tougher.
	var plain := Battle.new(p, [["shambler"]])
	plain.start_next_wave()
	var frost := Battle.new(p, [["shambler"]])
	frost.configure({"mutation": by_id.frost})
	frost.start_next_wave()
	_check(frost.enemies[0].spd < plain.enemies[0].spd and frost.enemies[0].max_hp > plain.enemies[0].max_hp,
		"Frost Week: slower (%d vs %d SPD), tougher zombies" % [frost.enemies[0].spd, plain.enemies[0].spd])
	# Blood Moon: night animals hit harder; the owl is one, the bear isn't.
	var moon := Battle.new(p, [["shambler"]])
	moon.configure({"mutation": by_id.blood_moon})
	var owl := func(b: Battle, id: String) -> Combatant: return b.party.filter(func(c: Combatant) -> bool: return c.id == id)[0]
	_check(owl.call(moon, "horned_owl").atk > owl.call(plain, "horned_owl").atk and owl.call(moon, "black_bear").atk == owl.call(plain, "black_bear").atk,
		"Blood Moon: the owl (night) gets +ATK, the bear doesn't")
	# Swarm: an extra Shambler in each wave that has room, and more XP.
	var c := Campaign.create(p)
	var i := -1
	for k in c.territories.size():
		if c.can_attack(k) and c.territories[k].boss == "":
			i = k
			break
	var before: Array = c.battle_config(i).waves.map(func(w: Array) -> int: return w.size())
	GameData.mutation_override = by_id.swarm
	var cfg := c.battle_config(i)
	var after: Array = cfg.waves.map(func(w: Array) -> int: return w.size())
	var grew := true
	for k in before.size():
		grew = grew and after[k] == mini(GameData.MAX_ENEMIES, int(before[k]) + 1)
	_check(grew and cfg.mutation.id == "swarm", "Swarm Week: an extra zombie per wave (%s -> %s)" % [before, after])
	var swarm := Battle.new(p, cfg.waves)
	swarm.configure(cfg)
	_check(is_equal_approx(swarm.xp_mult, float(cfg.xp_mult) * 1.25), "and +25% XP")
	# Legends are never mutated.
	for k in c.territories.size():
		if c.territories[k].boss != "":
			_check(c.battle_config(k).mutation.is_empty(), "legend fights have no mutation")
			break
	GameData.mutation_override = {}
	GameData.mutations_off = true
	_check(Battle.new(p, [["shambler"]]).mutation.is_empty() and GameData.mutation(GameData.week_now()).is_empty(), "switched off for tests")


func _goal() -> void:
	var p := _profile()
	var c := Campaign.create(p)
	var goal := c.week_goal()
	var kind := String(GameData.week_goal(goal.week).kind)
	_check(goal.done == 0 and goal.target == int(GameData.week_goal(goal.week).per_player), "solo goal: %s (0/%d)" % [goal.text, goal.target])
	var guard := 0
	while not c.week_goal().finished and guard < 200:
		guard += 1
		if kind == "hold":
			c.under_attack = c.home
			c.resolve_battle(c.home, true, 0)
		else:
			c.under_attack = -1
			for k in c.territories.size():
				if c.can_attack(k) and c.territories[k].boss == "" and c.warlord_at(k).is_empty():
					c.resolve_battle(k, true, 0)
					break
	_check(c.week_goal().finished, "%s fills the goal (%d/%d)" % [kind, c.week_goal().done, c.week_goal().target])
	var trinkets := p.trinkets.size()
	var xp_before := int(p.xp.dog)
	var text := p.claim_week_goal(int(goal.week))
	_check(text.begins_with("Week goal complete!") and p.trinkets.size() == trinkets + 1 and int(p.xp.dog) > xp_before, "the reward: a trinket and XP")
	_check(p.claim_week_goal(int(goal.week)) == "", "only once a week")
	var back := Campaign.create(p, {"id": "t", "state": c.to_text(), "members": [{"user_id": "a", "name": "A", "zip": "24210"}, {"user_id": "b", "name": "B", "zip": "24201"}]})
	_check(back.week_goal().target == 2 * goal.target, "a team of 2 has twice the goal (%d)" % back.week_goal().target)
