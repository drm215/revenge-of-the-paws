extends SceneTree

## Legends fight like raid bosses: they match the pack whenever it comes, call for help, enrage, and
## wind up a Cataclysm that has to be answered. On the battle screen too.

var _fails := 0


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


func _init() -> void:
	_run.call_deferred()


func _pack(level := 10) -> Profile:
	var p := Profile.new()
	p.region = "us_appalachia"
	p.zip = "24210"
	p.town = "Abingdon"
	p.pet_species = "dog"
	p.pet_name = "Jack"
	p.team.assign(["black_bear", "bobcat"])
	p.unlocked.assign(["black_bear", "bobcat"])
	for id in ["dog", "black_bear", "bobcat"]:
		p.xp[id] = GameData.xp_to_reach(level)
	return p


func _fight(mates := ["shambler", "runner"]) -> Battle:
	var b := Battle.new(_pack(), [["woodbooger"] + mates], 2.0, 1.0, "lair", 5)
	b.start_next_wave()
	return b


func _hurt_to(b: Battle, legend: Combatant, ratio: float) -> void:
	b._apply_damage(legend, maxi(1, legend.hp - roundi(legend.max_hp * ratio)), false)


func _run() -> void:
	root.theme = Retro.make_theme()
	Profile.save_path = "user://rb_profile.cfg"
	Campaign.save_path = "user://rb_campaign.cfg"

	# They match the pack, unlike the land around them.
	var p := _pack(5)
	var c := Campaign.create(p)
	var lair := c.territories[c.home].neighbors[0]
	for t in c.territories:
		t.boss = ""
	c.territories[lair].boss = "woodbooger"
	c.territories[lair].owned = false
	c.territories[lair].threat = GameData.MAX_THREAT
	var other := c.territories[c.home].neighbors[1]
	c.territories[other].owned = false
	var legend_then := c.territory_level(lair)
	var land_then := c.territory_level(other)
	for id in ["dog", "black_bear", "bobcat"]:
		p.xp[id] = GameData.xp_to_reach(25)
	_check(c.territory_level(lair) > legend_then + 10, "a legend keeps up with the pack (Lv %d to %d)" % [legend_then, c.territory_level(lair)])
	_check(c.territory_level(other) == land_then, "the land around it doesn't")
	_check(c.battle_config(lair).zombie_mult == c.zombie_strength(lair, c.territories[lair].threat), "the fight is at that level")
	_check(c.raid_config(lair, 40).zombie_mult > c.battle_config(lair).zombie_mult, "a raid matches its strongest raider")

	# Calling for help: into a fallen zombie's place, else a free one, 4 at most.
	var b := _fight()
	var legend: Combatant = b.enemies[0]
	var joined: Array = []
	b.reinforced.connect(func(fresh: Combatant, gone: Combatant) -> void: joined.append([fresh, gone]))
	_hurt_to(b, legend, 0.7)
	_check(joined.is_empty(), "at 70%: no help yet")
	b.enemies[1].hp = 0
	_hurt_to(b, legend, 0.6)
	_check(joined.size() == 2, "at 60%: it calls for help")
	_check(b.enemies.size() == GameData.MAX_ENEMIES, "the fight stays at %d zombies" % GameData.MAX_ENEMIES)
	_check(joined[0][1] != null and joined[1][1] == null, "one in a fallen zombie's place, one new")
	_check(joined[0][0].id == "runner" and joined[1][0].id == "shambler", "a Runner and a Shambler")
	_check(joined[0][0].xp_value == 0, "no XP to farm from them")
	_check(joined[0][0].max_hp > GameData.ZOMBIES.runner.hp, "scaled to the fight")
	var xp_before := b.xp_earned
	b._apply_damage(joined[0][0], 99999, false)
	_check(b.xp_earned == xp_before, "killing one earns nothing")
	_hurt_to(b, legend, 0.5)
	_check(joined.size() == 2, "it only calls once")

	# Enraged.
	var atk := legend.atk
	_hurt_to(b, legend, 0.4)
	_check(legend.atk == atk, "at 40%: not enraged yet")
	_hurt_to(b, legend, 0.3)
	_check(legend.hp_ratio() <= 0.31, "enraging doesn't heal it (%.0f%% HP)" % (legend.hp_ratio() * 100))
	_check(absf(float(legend.atk) / atk - GameData.LEGEND_ENRAGE_ATK) < 0.05, "at 30%: enraged (%d to %d attack)" % [atk, legend.atk])
	var enraged := legend.atk
	_hurt_to(b, legend, 0.1)
	_check(legend.atk == enraged, "once only")
	_check(int(b.report().legends[0].phase) == 2, "the battle log records how far it got")

	# One huge hit runs through both, with no error; a killing blow doesn't summon anything.
	b = _fight()
	legend = b.enemies[0]
	joined.clear()
	b.reinforced.connect(func(fresh: Combatant, gone: Combatant) -> void: joined.append([fresh, gone]))
	_hurt_to(b, legend, 0.1)
	_check(joined.size() >= 1 and int(b.report().legends[0].phase) == 2, "one huge hit runs through both phases")
	b = _fight()
	joined.clear()
	b.reinforced.connect(func(fresh: Combatant, gone: Combatant) -> void: joined.append([fresh, gone]))
	b._apply_damage(b.enemies[0], 999999, false)
	_check(joined.is_empty(), "a killing blow calls nobody")

	# Cataclysm: wound up, then lands on everyone; stun cancels it; Guard halves it.
	b = _fight([])
	legend = b.enemies[0]
	_check("cataclysm" in legend.skills, "every legend has Cataclysm")
	legend.cooldowns.clear()  # strong skills start the fight on cooldown
	var plan := b.plan_enemy_action(legend)
	_check(plan.skill == "cataclysm", "it uses it when it's ready")
	b.use_skill(legend, "cataclysm", plan.target)
	_check(legend.winding == "cataclysm", "first it winds up")
	var hp_before: Array = b.party.map(func(a: Combatant) -> int: return a.hp)
	b.party[0].add_status("guard", 2)
	b.rng.seed = 3
	b.use_skill(legend, "cataclysm", b.plan_enemy_action(legend).target)
	var lost: Array = []
	for k in b.party.size():
		lost.append(hp_before[k] - b.party[k].hp)
	_check(lost[1] > 0 and lost[2] > 0, "then it hits the whole pack: %s" % [lost])
	var guarded_share := float(lost[0]) * b.party[1].effective_def() / maxf(1.0, float(lost[1]) * b.party[0].effective_def())
	_check(lost[0] < lost[1] or lost[0] < lost[2], "a guarded animal takes less")
	_check(guarded_share > 0.0, "(guard share %.2f)" % guarded_share)

	b = _fight([])
	legend = b.enemies[0]
	legend.cooldowns.clear()
	b.use_skill(legend, "cataclysm", b.plan_enemy_action(legend).target)
	legend.add_status("stunned", 1)
	hp_before = b.party.map(func(a: Combatant) -> int: return a.hp)
	b._turn_queue.assign([legend])
	var after: Combatant = null
	var safety := 0
	while safety < 3 and after != legend and b.outcome() == Battle.Outcome.ONGOING:
		after = b.next_turn()
		safety += 1
		if after and after.is_player:
			break
	_check(legend.winding == "", "a stun cancels it")
	_check(not legend.can_use("cataclysm"), "and it has to wait for its cooldown")

	# On the screen: reinforcements get cards, and the fallen zombie's card goes.
	var pack := _pack()
	var screen := BattleScreen.new()
	screen.profile = pack
	screen.config = {"waves": [["woodbooger", "shambler", "runner"]], "zombie_mult": 2.0, "party_mult": 1.0, "place": "lair", "condition": "", "region": "us_appalachia"}
	screen.size = Vector2(720, 1280)
	root.add_child(screen)
	await process_frame
	await process_frame
	b = screen.battle
	legend = b.enemies[0]
	var fallen: Combatant = b.enemies[1]
	fallen.hp = 0
	_hurt_to(b, legend, 0.6)
	await process_frame
	_check(not screen.cards.has(fallen), "the fallen zombie's card goes")
	var every := true
	for z in b.enemies:
		every = every and screen.cards.has(z)
	_check(every and b.enemies.size() == 4, "every zombie has a card, 4 in all")
	screen._refresh_cards()
	_check(screen.cards.size() == b.enemies.size() + b.party.size(), "no ghost cards")
	screen.free()
	print("%d failure(s)" % _fails)
	quit()
