extends SceneTree

## The end of a raid with no connection: the player can leave, and once back online the result goes
## up and the team map and their rewards catch up. Also: a refresh waits for one already running.

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
	var url := OS.get_environment("FAKE_SUPABASE_URL")
	cloud = root.get_node("Cloud")
	team = root.get_node("Team")
	raid = root.get_node("Raid")
	cloud.state_path = "user://rend_cloud.cfg"
	team.state_path = "user://rend_team.cfg"
	raid.state_path = "user://rend_raid.cfg"
	cloud.base_url = url
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

	# A refresh while one is running gives the newest answer, not an early return.
	var first_done := [false]
	var first := func() -> void:
		await raid.refresh()
		first_done[0] = true
	first.call()
	await raid.refresh()
	_check(first_done[0], "a second refresh waited for the first")

	# The game, on the team map.
	change_scene_to_file("res://scenes/main.tscn")
	await _frames(8)
	var main: Node = current_scene
	main.get_child(-1).chosen.emit(slot)
	await _frames(6)
	_check(main.get_child(-1) is MapScreen, "the map is up")
	var c: Campaign = main._campaign
	var lair := -1
	for n in c.territories[c.home].neighbors:
		if not c.territories[n].owned:
			lair = n
			break
	c.territories[lair].boss = "woodbooger"
	var t: Territory = c.territories[lair]
	_check(await raid.open(t.id, "woodbooger", t.full_name(), "Jack", p.snapshot()) == "", "open a raid")
	_check(await raid.start(c.raid_config(lair, 5)) == "", "start it")

	# The fight ends with the connection gone.
	var screen := BattleScreen.new()
	screen.profile = main._profile
	screen.config = raid.config()
	screen.raid = true
	screen.size = Vector2(720, 1280)
	root.add_child(screen)
	await _frames(2)
	_check(raid.holding, "the fight keeps its raid")
	for z in screen.battle.enemies:
		z.hp = 0
	screen.battle.wave_index = screen.battle.wave_count() - 1
	screen.battle.xp_earned = 90
	cloud.base_url = "http://127.0.0.1:9"
	var left := [false]
	screen.finished.connect(func(_won: bool) -> void: left[0] = true)
	screen._finish_raid()
	_check(screen._overlay_button.disabled, "while reporting, the button waits")
	var waited := 0.0
	while screen._overlay_button.disabled and waited < 30.0:
		await create_timer(0.1).timeout
		waited += 0.1
	_check(not screen._overlay_button.disabled and "Can't reach" in screen._overlay_body.text, "with no connection, the player can leave: " + screen._overlay_body.text.get_slice("\n", 0))
	screen._overlay_button.pressed.emit()
	_check(left[0], "and they do")
	_check(raid.has_late(), "the result is kept")
	screen.free()
	_check(not raid.holding, "the raid is let go")
	var saved := ConfigFile.new()
	_check(saved.load(raid.state_path) == OK and not (saved.get_value("raid", "late", {}) as Dictionary).is_empty(), "and it's on disk, for a reload")

	await raid.send_late()
	_check(raid.has_late(), "still offline: it keeps waiting")

	# Back online.
	cloud.base_url = url
	var trinkets: int = main._profile.trinkets.size()
	var xp: int = main._profile.xp.get("dog", 0)
	await raid.send_late()
	await _frames(4)
	_check(not raid.has_late(), "back online: it went up")
	_check(raid.status() == "done", "the raid is done (%s)" % raid.status())
	c = main._campaign
	_check(c.territories[lair].owned, "the lair is free on the team map")
	_check(main._profile.trinkets.size() == trinkets + 1, "the legend's trinket arrived (%d to %d: %s; result %s)" % [trinkets, main._profile.trinkets.size(), main._profile.trinkets, raid.result()])
	_check(int(main._profile.xp.get("dog", 0)) > xp, "and the XP")
	_check(String(raid.info.id) in main._profile.raids_claimed, "claimed once")
	_check(main.get_child(-1) is MapScreen, "the map shows it")
	print("%d failure(s)" % _fails)
	quit()
