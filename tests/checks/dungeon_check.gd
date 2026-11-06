extends SceneTree

## Dungeons: endless waves that climb, Brutes on schedule, rewards once each, checkpoints, no map turn
## and no injuries, the leaderboard, and the whole flow on the real screens.

var _fails := 0


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


func _init() -> void:
	_run.call_deferred()


func _profile() -> Profile:
	var p := Profile.new()
	p.region = "us_florida"
	p.zip = "33139"
	p.town = "Miami"
	p.pet_species = "dog"
	p.pet_name = "Jack"
	p.team.assign(["black_bear", "horned_owl"])
	p.unlocked.assign(["black_bear", "horned_owl"])
	for id in ["dog", "black_bear", "horned_owl"]:
		p.xp[id] = GameData.xp_to_reach(12)
	return p


func _labels(n: Node) -> Array:
	return n.find_children("*", "Label", true, false).map(func(l: Label) -> String: return l.text)


func _buttons(n: Node) -> Array:
	return n.find_children("*", "Button", true, false).filter(func(b: Button) -> bool: return b.is_visible_in_tree()).map(func(b: Button) -> String: return b.text)


func _real_wait(msec: int) -> void:
	var until := Time.get_ticks_msec() + msec
	while Time.get_ticks_msec() < until:
		await process_frame


func _run() -> void:
	root.theme = Retro.make_theme()
	var slot := Saves.new_slot()
	Saves.use(slot)

	# Every region has one, set somewhere real, with its own treasure.
	for region in GameData.REGIONS:
		var d := GameData.dungeon(region)
		if d.is_empty() or not GameData.CONDITIONS.has(d.terrain) or not GameData.TRINKETS.has(d.trinket):
			_check(false, "dungeon for " + region)
	_check(GameData.DUNGEONS.size() == GameData.REGIONS.size(), "every region has a dungeon (%d)" % GameData.DUNGEONS.size())
	_check(GameData.dungeon("us_florida").name == "The Everglades", "Florida's is the Everglades")
	var unique := {}
	for r in GameData.DUNGEONS:
		unique[GameData.DUNGEONS[r].trinket] = true
	_check(unique.size() == GameData.DUNGEONS.size(), "each has a trinket of its own")

	# The waves: the same every run, Brutes on schedule, harder as it goes.
	_check(GameData.dungeon_wave("us_florida", 7) == GameData.dungeon_wave("us_florida", 7), "a wave is the same every run")
	for n in [1, 4, 5, 9, 10, 15, 20, 30]:
		var wave := GameData.dungeon_wave("us_florida", n)
		var brutes := wave.count("brute")
		var expected := mini(n / GameData.DUNGEON_BRUTE_EVERY, GameData.DUNGEON_BRUTES_ON_SCREEN)
		_check(brutes == expected and wave.size() <= GameData.MAX_ENEMIES, "wave %d: %d Brute%s, %d zombies" % [n, brutes, "" if brutes == 1 else "s", wave.size()])
	_check(GameData.dungeon_brute_mult(10) == 1.0 and GameData.dungeon_brute_mult(15) > 1.0 and GameData.dungeon_brute_mult(25) > GameData.dungeon_brute_mult(15),
		"past two Brutes, more Brutes means tougher ones")
	_check(GameData.dungeon_mult(1) <= GameData.dungeon_mult(10) and GameData.dungeon_mult(10) < GameData.dungeon_mult(30), "deeper is stronger")
	_check(GameData.dungeon_wave("us_florida", 1).all(func(z: String) -> bool: return z in ["shambler", "runner"]), "the first wave is the easy kind")

	# A run: endless, numbered from where it started, with its terrain.
	var p := _profile()
	var cfg := {"dungeon": "us_florida", "start": 11, "waves": [GameData.dungeon_wave("us_florida", 11)], "zombie_mult": GameData.dungeon_mult(11),
		"party_mult": 1.0, "place": "The Everglades", "condition": "water", "region": "us_florida"}
	var b := Battle.new(p, cfg.waves, cfg.zombie_mult, 1.0, "The Everglades", 3, "water", "us_florida")
	b.configure(cfg)
	b.start_next_wave()
	_check(b.dungeon_wave() == 11, "a run from the checkpoint starts at wave 11")
	for k in 6:
		for z in b.enemies:
			z.hp = 0
		_check(b.outcome() == Battle.Outcome.WAVE_CLEARED, "a dungeon wave is never the last (wave %d)" % b.dungeon_wave())
		b.start_next_wave()
	_check(b.dungeon_wave() == 17 and b.enemies.size() >= 3, "and the next keeps coming (wave %d)" % b.dungeon_wave())
	var brute_wave := Battle.new(p, [GameData.dungeon_wave("us_florida", 25)], 1.0, 1.0, "x", 1)
	brute_wave.configure({"dungeon": "us_florida", "start": 25})
	brute_wave.start_next_wave()
	var dungeon_brute: Combatant = brute_wave.enemies.filter(func(z: Combatant) -> bool: return z.id == "brute")[0]
	var plain := Battle.new(p, [["brute"]], GameData.dungeon_mult(25), 1.0, "x", 1)
	plain.start_next_wave()
	_check(dungeon_brute.max_hp > plain.enemies[0].max_hp, "its Brutes are tougher that deep (%d vs %d HP)" % [dungeon_brute.max_hp, plain.enemies[0].max_hp])

	# Rewards: each depth once.
	p = _profile()
	p.save()
	var t0 := p.trinkets.size()
	var xp0: int = p.xp.dog
	_check(p.clear_dungeon_wave("us_florida", 4) == "", "wave 4 pays nothing")
	_check(p.clear_dungeon_wave("us_florida", 5) != "" and int(p.xp.dog) > xp0, "wave 5: XP")
	var xp5: int = p.xp.dog
	_check(p.clear_dungeon_wave("us_florida", 5) == "" and int(p.xp.dog) == xp5, "only once")
	_check(p.clear_dungeon_wave("us_florida", 9) == "", "nothing in between")
	_check(p.clear_dungeon_wave("us_florida", 10) != "" and p.trinkets.size() == t0 + 1, "wave 10: a trinket")
	p.clear_dungeon_wave("us_florida", 26)
	_check(GameData.dungeon("us_florida").trinket in p.trinkets, "wave 25: the Everglades' own trinket (%s)" % GameData.trinket(GameData.dungeon("us_florida").trinket).name)
	_check(p.dungeon_best.us_florida == 26, "the deepest is kept")
	var count := p.trinkets.size()
	p.clear_dungeon_wave("us_florida", 26)
	p.clear_dungeon_wave("us_florida", 12)
	_check(p.trinkets.size() == count and p.dungeon_best.us_florida == 26, "a shallower run changes nothing")
	_check(Profile.load_saved().dungeon_paid.us_florida == 26, "saved")
	_check(p.dungeon_best.get("us_appalachia", 0) == 0, "each region keeps its own")

	# Checkpoints every 10.
	var fresh := _profile()
	_check(fresh.dungeon_starts("us_florida") == [1], "a first run starts at wave 1")
	fresh.dungeon_best["us_florida"] = 9
	_check(fresh.dungeon_starts("us_florida") == [1], "wave 9 isn't a checkpoint")
	fresh.dungeon_best["us_florida"] = 23
	_check(fresh.dungeon_starts("us_florida") == [1, 11, 21], "clear 23: start at 1, 11 or 21")

	# Where it is: the real place on the map, or a pointer until it's in reach.
	Campaign.clear_saved()
	var far := Campaign.create(_profile())
	var rumor := far.dungeon_rumor()
	_check(far.dungeon_territory("us_florida") < 0 and rumor.get("name", "") == "The Everglades" and rumor.direction == "SW", "from Miami Beach the Everglades lie out of sight to the SW: %s" % [rumor])
	var near_p := _profile()
	near_p.zip = "33034"
	Campaign.clear_saved()
	var near := Campaign.create(near_p)
	var at := near.dungeon_territory("us_florida")
	_check(at == near.home and near.dungeon_rumor().is_empty(), "Homestead's own ZIP area holds the park, so the entrance is at home (%s)" % (near.territories[at].id if at >= 0 else "none"))
	var abingdon := _profile()
	abingdon.region = "us_appalachia"
	abingdon.zip = "24210"
	Campaign.clear_saved()
	var hills := Campaign.create(abingdon)
	_check(hills.dungeon_rumor().get("name", "") == "The Old Coal Mine", "Abingdon hears of the Old Coal Mine")
	var walked := 0
	var mine: Dictionary = GameData.dungeon("us_appalachia")
	while hills.dungeon_territory("us_appalachia") < 0 and walked < 20:
		walked += 1
		var best := -1
		var best_km := INF
		for i in hills.territories.size():
			if hills.can_attack(i):
				var km := hills._km_between(hills.territories[i].lonlat.y, hills.territories[i].lonlat.x, mine.lat, mine.lon)
				if km < best_km:
					best_km = km
					best = i
		hills.under_attack = -1
		hills.resolve_battle(best, true, 0, [], false)
	var mine_at := hills.dungeon_territory("us_appalachia")
	_check(mine_at >= 0, "and finds it by freeing land that way (%d liberations)" % walked)
	if mine_at >= 0:
		_check(hills._km_between(hills.territories[mine_at].lonlat.y, hills.territories[mine_at].lonlat.x, mine.lat, mine.lon) < 25, "at the real place: " + hills.territories[mine_at].full_name())
		hills.save()
		var again := Campaign.create(abingdon)
		_check(again.dungeon_territory("us_appalachia") == mine_at, "and it's still there after a reload")
	Campaign.clear_saved()

	# The real flow: Delve from the held entrance, the dungeon screen, readying the pack, the run.
	var cloud: Node = root.get_node("Cloud")
	cloud.state_path = "user://dg_cloud.cfg"
	cloud.base_url = OS.get_environment("FAKE_SUPABASE_URL")
	cloud.anon_key = "anon"
	cloud.log_out()
	_check(await cloud.log_in("a@b.co", "oldpass") == "", "log in")
	p = _profile()
	p.save()
	change_scene_to_file("res://scenes/main.tscn")
	for k in 8:
		await process_frame
	var main: Node = current_scene
	main.get_child(-1).chosen.emit(slot)
	for k in 6:
		await process_frame
	var map: MapScreen = main.get_child(-1)
	var c: Campaign = main._campaign
	map._select(c.home)
	_check(not "Delve" in _buttons(map), "home has no Delve")
	_check(_labels(map).any(func(t: String) -> bool: return "Dungeon: The Everglades" in t and "mi SW" in t), "the map points the way")
	# As if the entrance were here: first in the dead's hands, then freed.
	var gate: int = c.territories[c.home].neighbors[0]
	c.territories[gate].dungeon = "us_florida"
	c.territories[gate].owned = false
	map._select(c.home)
	var marker: Rect2 = map._map._dungeon_marker(gate)
	map._map._select_at(Vector2(marker.get_center().x, marker.end.y - 2))
	_check(map._map.selected == gate, "tapping the dungeon's name picks its land, whatever is drawn under it")
	map._map._select_at(marker.position + Vector2(4, 4))
	_check(map._map.selected == gate, "and so does tapping its doorway")
	map._select(gate)
	_check(not "Delve" in _buttons(map) and "DUNGEON: The Everglades" in map._info_body.text and "Free this land" in map._info_body.text, "the entrance shows, but only freed land opens it")
	c.territories[gate].owned = true
	c._ownership_changed()
	map._select(gate)
	_check("Delve" in _buttons(map), "freed, it has Delve")
	var turn: int = c.turn
	var injured: Dictionary = main._profile.injuries.duplicate()
	map._delve.pressed.emit()
	await _real_wait(400)
	var screen: Node = main.get_child(-1)
	_check(screen is DungeonScreen, "Delve opens the dungeon")
	var text := "\n".join(_labels(screen))
	_check("The Everglades" in text and "Wave 25" in text and GameData.trinket(GameData.dungeon("us_florida").trinket).name in text, "with its name and treasure")
	_check("From the top (wave 1)" in _buttons(screen), "a run starts at the top")
	_check("Water animals fight on home ground" in text and not "animals animals" in text, "its terrain reads right")
	screen.start.emit(1)
	await process_frame
	var prep: Node = main.get_child(-1)
	_check(prep is PackScreen and "The Everglades" in prep._fight_summary(), "then the pack gets ready")
	main._profile.team.assign(["black_bear", "horned_owl"])
	prep.fight.emit()
	for k in 4:
		await process_frame
	var fight: BattleScreen = main.get_child(-1)
	_check(fight is BattleScreen and "THE EVERGLADES · WAVE 1" in fight._wave_label.text, "the run begins: " + fight._wave_label.text)

	# Clear five waves for real, then leave.
	for k in 5:
		var waited := 0
		while fight._actor == null and waited < 600:  # strike on the pack's turn, as a player does
			await process_frame
			waited += 1
		for z in fight.battle.enemies:
			fight.battle._apply_damage(z, 9999999, false)
		fight._show_outcome()
		await _real_wait(250)
		if k < 4:
			_check(fight._overlay.visible and "Next wave" in _buttons(fight) and "Leave with what you've won" in _buttons(fight), "wave %d: on or out" % (k + 1))
			fight._overlay_button.pressed.emit()
			await _real_wait(400)
	_check("Wave 5 cleared!" == fight._overlay_title.text, "wave 5 cleared")
	_check("half a level" in fight._overlay_body.text.to_lower() or "reached Lv" in fight._overlay_body.text or "XP" in fight._overlay_body.text, "with its reward: " + fight._overlay_body.text.get_slice("\n", 0))
	_check(main._profile.dungeon_best.us_florida == 5, "recorded")
	fight._overlay_alt.pressed.emit()
	await _real_wait(300)
	_check(main.get_child(-1) is MapScreen, "Leave goes back to the map")
	_check(main._campaign.turn == turn, "no map turn spent")
	_check(main._profile.injuries == injured, "no injuries")

	# The leaderboard.
	await cloud.sync()
	var board: Dictionary = await cloud.dungeon_board("us_florida")
	_check(int(board.get("mine", 0)) == 5 and not (board.get("top", []) as Array).is_empty(), "on the leaderboard: %s" % board)

	# Falling: the run ends, everything won is kept.
	var run := BattleScreen.new()
	run.profile = main._profile
	run.config = {"dungeon": "us_florida", "start": 1, "waves": [GameData.dungeon_wave("us_florida", 1)], "zombie_mult": 1.0, "party_mult": 1.0,
		"place": "The Everglades", "condition": "water", "region": "us_florida"}
	run.size = Vector2(720, 1280)
	root.add_child(run)
	await process_frame
	await process_frame
	for a in run.battle.party:
		run.battle._apply_damage(a, 9999999, false)
	run._show_outcome()
	await _real_wait(200)
	_check(run._overlay_title.text.begins_with("The pack falls at wave"), "falling ends the run: " + run._overlay_title.text)
	_check("keep" in run._overlay_body.text, "and keeps what was won")
	_check(main._profile.dungeon_best.us_florida == 5, "the record stands")
	run.free()
	print("%d failure(s)" % _fails)
	quit()
