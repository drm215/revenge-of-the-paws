extends SceneTree

## A rematch raid: a team can fight a beaten legend together, just for fun. The lobby isn't called
## off because the lair is already free, and the fight pays no XP or trinket and leaves the map alone.

var _fails := 0
var cloud: Node
var team: Node
var raid: Node


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


func _init() -> void:
	_run.call_deferred()


func _frames(count: int) -> void:
	for k in count:
		await process_frame


func _run() -> void:
	cloud = root.get_node("Cloud")
	team = root.get_node("Team")
	raid = root.get_node("Raid")
	cloud.state_path = "user://rrm_cloud.cfg"
	team.state_path = "user://rrm_team.cfg"
	raid.state_path = "user://rrm_raid.cfg"
	cloud.base_url = OS.get_environment("FAKE_SUPABASE_URL")
	cloud.anon_key = "anon"
	cloud.log_out()
	_check(await cloud.log_in("a@b.co", "oldpass") == "", "log in")
	var slot := Saves.new_slot()
	Saves.use(slot)
	var p := Profile.new()
	p.region = "us_appalachia"
	p.zip = "24210"
	p.town = "Abingdon"
	p.pet_species = "dog"
	p.pet_name = "Jack"
	p.team.assign(["black_bear", "horned_owl"])
	p.unlocked.assign(["black_bear", "horned_owl"])
	p.save()
	_check(await team.create(p) == "", "team")

	change_scene_to_file("res://scenes/main.tscn")
	await _frames(8)
	var main: Node = current_scene
	main.get_child(-1).chosen.emit(slot)
	await _frames(6)
	_check(main.get_child(-1) is MapScreen, "the map is up")
	var c: Campaign = main._campaign
	var lair: int = c.territories[c.home].neighbors[0]
	var t: Territory = c.territories[lair]
	t.boss = "woodbooger"
	t.owned = true
	c._ownership_changed()
	_check(c.can_rematch(lair), "a beaten lair can be rematched")

	# Readying a rematch on a team offers the raid.
	main._show_rematch(lair)
	await _frames(2)
	var prep: PackScreen = main.get_child(-1)
	_check(prep.battle_config.get("raidable", false), "the rematch can be fought as a raid")
	prep.raid_requested.emit()
	await _frames(2)
	var lobby: RaidScreen = main.get_child(-1)
	_check(lobby is RaidScreen and lobby.rematch, "it opens a rematch raid lobby")
	var waited := 0.0
	while raid.status() != "lobby" and waited < 10.0:
		await create_timer(0.1).timeout
		waited += 0.1
	_check(raid.is_rematch() and raid.territory_id() == t.id, "the team's raid is a rematch on that lair")
	var said := lobby.find_children("*", "Label", true, false).map(func(l: Label) -> String: return l.text)
	_check("Legend rematch" in said, "the lobby says it's a rematch")

	# Back on the map, the lobby stands even though the lair is free.
	main._show_map(main._profile, false)
	await _frames(3)
	raid.changed.emit()
	await _frames(2)
	_check(raid.status() == "lobby", "a free lair doesn't call off a rematch")
	var map: MapScreen = main.get_child(-1)
	_check(map._raid_button.visible and "rematch" in map._raid_button.text, "the map offers it: " + map._raid_button.text)

	_check(await raid.join("Jack", p.snapshot(), true) == "", "ready up")
	_check(await raid.start(c.raid_config(lair, 5, raid.is_rematch())) == "", "start it")
	_check(raid.config().get("rematch", false) and raid.config().get("loot", "x") == "", "the fight is set up as a rematch")

	var turn := c.turn
	var trinkets: int = main._profile.trinkets.size()
	var xp: int = main._profile.xp.get("dog", 0)
	var screen := BattleScreen.new()
	screen.profile = main._profile
	screen.config = raid.config()
	screen.raid = true
	screen.size = Vector2(720, 1280)
	var recorded := [false]
	screen.raid_done.connect(func(outcome: Dictionary, here: bool) -> void:
		if here:
			main._record_raid(outcome, [raid.my_id()])
			recorded[0] = true)
	root.add_child(screen)
	await _frames(2)
	for z in screen.battle.enemies:
		z.hp = 0
	screen.battle.wave_index = screen.battle.wave_count() - 1
	screen.battle.xp_earned = 90
	await screen._finish_raid()
	_check(recorded[0], "the result came back")
	_check(raid.result().get("rematch", false) and int(raid.result().xp) == 0, "the stored result is a rematch with no XP: %s" % raid.result())
	_check(main._profile.trinkets.size() == trinkets, "no trinket")
	_check(int(main._profile.xp.get("dog", 0)) == xp, "no XP")
	_check(c.turn == turn and c.territories[lair].owned, "the map didn't move")
	_check("just for fun" in screen._overlay_body.text, "and it says so")
	screen.free()
	print("%d failure(s)" % _fails)
	quit()
