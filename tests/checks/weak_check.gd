extends SceneTree

## Zombie weak points: damage, armor, defuse, immunity, log, card and Details.

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


## Damage `attacker` (index in the party) deals to the first zombie with a fixed seed.
func _hit(team: Array, attacker: int, zombie: String, armored_check := false) -> int:
	var b := Battle.new(_profile(team), [[zombie]], 1.0, 1.0, "t", 5)
	b.start_next_wave()
	var z: Combatant = b.enemies[0]
	z.max_hp = 99999
	z.hp = 99999
	b._deal_damage(b.party[attacker], z, 1.0, -1.0, true)
	return 99999 - z.hp


func _init() -> void:
	# Same attacker stats compared on a zombie with and without its weak point (gray wolf is canine).
	var wolf_vs_shambler := _hit(["gray_wolf", "bobcat", "opossum"], 0, "shambler")
	var wolf_vs_runner := _hit(["gray_wolf", "bobcat", "opossum"], 0, "runner")
	print("     wolf: shambler %d, runner %d" % [wolf_vs_shambler, wolf_vs_runner])
	_check(GameData.ZOMBIE_WEAKNESS.shambler.tag in GameData.tags_of("gray_wolf"), "gray wolf is canine")
	var b := Battle.new(_profile(["gray_wolf", "bobcat", "opossum"]), [["shambler"]], 1.0, 1.0, "t", 5)
	b.start_next_wave()
	_check(b._weak_point(b.party[0], b.enemies[0]) == "damage" and b._weak_point(b.party[1], b.enemies[0]) == "", "wolf hits the Shambler's weak point, bobcat doesn't")
	_check(b._weak_point(b.enemies[0], b.party[0]) == "", "zombies never get weak-point bonuses")

	# The same bobcat (feline) against a Runner vs. a Shambler: about 1.5x after DEF differences.
	var log: PackedStringArray = []
	b = Battle.new(_profile(["bobcat", "gray_wolf", "opossum"]), [["runner", "shambler"]], 1.0, 1.0, "t", 5)
	b.log_message.connect(func(t: String) -> void: log.append(t))
	var floats := [0]
	b.weak_hit.connect(func(_c: Combatant) -> void: floats[0] += 1)
	b.start_next_wave()
	var runner: Combatant = b.enemies[0]
	runner.max_hp = 9999
	runner.hp = 9999
	b._deal_damage(b.party[0], runner, 1.0, -1.0, true)
	b._deal_damage(b.party[0], runner, 1.0, -1.0, true)
	var told := 0
	for l in log:
		if "Weak spot!" in l:
			told += 1
	_check(told == 1 and floats[0] == 2, "log explains once (%d), WEAK SPOT! floats every hit (%d)" % [told, floats[0]])

	# Riot: a Bruiser (whitetail deer) ignores the armor.
	var deer_b := Battle.new(_profile(["whitetail_deer", "bobcat", "opossum"]), [["riot"]], 1.0, 1.0, "t", 9)
	deer_b.start_next_wave()
	_check(deer_b._weak_point(deer_b.party[0], deer_b.enemies[0]) == "armor", "deer (Bruiser) gets the armor trick on Riot")

	# Bloater: a water animal finishing it stops the blast.
	for who in [["capybara", "bobcat", "opossum"], ["bobcat", "capybara", "opossum"]]:
		var bb := Battle.new(_profile(who), [["bloater"]], 1.0, 1.0, "t", 3)
		bb.start_next_wave()
		var hp_before: Array[int] = []
		for c in bb.party:
			hp_before.append(c.hp)
		bb.enemies[0].hp = 1
		bb._deal_damage(bb.party[0], bb.enemies[0], 1.0, 0.0, true)
		var blasted := false
		for i in bb.party.size():
			if bb.party[i].hp < hp_before[i]:
				blasted = true
		print("     %s finishes the Bloater: blast %s" % [who[0], blasted])
		_check(blasted == (who[0] != "capybara"), "%s: blast %s" % [who[0], "stopped" if who[0] == "capybara" else "goes off"])

	# Plague: scavengers aren't infected by its spit.
	var pb := Battle.new(_profile(["raccoon", "bobcat", "opossum"]), [["plague"]], 1.0, 1.0, "t", 3)
	pb.start_next_wave()
	for c in pb.party:
		c.max_hp = 9999
		c.hp = 9999
	for i in 6:
		pb.use_skill(pb.enemies[0], "plague_spit", pb.party[0])  # winds up
		pb.use_skill(pb.enemies[0], "plague_spit", pb.party[0])  # lands on the whole pack
		pb.enemies[0].cooldowns.clear()
	_check(not pb.party[0].has_status("infected") and not pb.party[2].has_status("infected"), "raccoon and opossum (scavengers) never infected")
	_check(pb.party[1].has_status("infected"), "the bobcat was infected")

	# Details screen counters.
	_check(GameData.counters("gray_wolf") == PackedStringArray(["Shambler", "Warlord", "Brute", "Screamer"]), "wolf counters: %s" % [GameData.counters("gray_wolf")])
	print("     " + GameData.weak_text("riot"))
	print("%d failure(s)" % _fails)
	quit()
