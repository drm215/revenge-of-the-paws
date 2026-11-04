extends SceneTree

## A raid left mid-fight against fake_supabase.py.

var _fails := 0


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


func _init() -> void:
	_run.call_deferred()


func _buttons(n: Node) -> Array:
	return n.find_children("*", "Button", true, false).filter(func(b: Button) -> bool: return b.is_visible_in_tree()).map(func(b: Button) -> String: return b.text)


func _map(c: Campaign, p: Profile) -> MapScreen:
	var map := MapScreen.new()
	map.campaign = c
	map.profile = p
	map.size = Vector2(720, 1280)
	root.add_child(map)
	return map


func _run() -> void:
	root.theme = Retro.make_theme()
	Profile.save_path = "user://stuck_profile.cfg"
	Campaign.save_path = "user://stuck_campaign.cfg"
	var cloud: Node = root.get_node("Cloud")
	var team: Node = root.get_node("Team")
	var raid: Node = root.get_node("Raid")
	cloud.state_path = "user://stuck_cloud.cfg"
	team.state_path = "user://stuck_team.cfg"
	for path in [cloud.state_path, team.state_path]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	cloud.base_url = OS.get_environment("FAKE_SUPABASE_URL")
	cloud.anon_key = "anon"
	cloud.log_out()
	_check(await cloud.log_in("a@b.co", "oldpass") == "", "log in")
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
	var c := Campaign.create(p, team.info)
	c.my_id = cloud.user_id()
	var lair := -1
	for n in c.territories[c.home].neighbors:
		if not c.territories[n].owned:
			lair = n
			break
	c.territories[lair].boss = "woodbooger"
	var t := c.territories[lair]

	_check(await raid.open(t.id, "woodbooger", t.full_name(), "Jack", p.snapshot()) == "", "open a raid")
	_check(await raid.start(c.raid_config(lair, 5)) == "", "start the fight")
	_check(raid.status() == "fighting", "fighting")

	# Everyone left: the map says so, and the raid screen can call it off.
	var map := _map(c, p)
	await process_frame
	await process_frame
	_check("Raid on the Woodbooger was interrupted" in _buttons(map), "map: %s" % [_buttons(map).slice(0, 2)])
	map.visible = false
	var screen := RaidScreen.new()
	screen.profile = p
	screen.campaign = c
	screen.lair = -1
	screen.size = Vector2(720, 1280)
	root.add_child(screen)
	await process_frame
	await process_frame
	_check("Call off this raid" in _buttons(screen), "raid screen: %s" % [_buttons(screen)])
	var closed := [false]
	screen.closed.connect(func() -> void: closed[0] = true)
	await screen._call_off()
	_check(closed[0] and raid.status() == "", "called off (status '%s')" % raid.status())
	screen.free()
	map.visible = true
	await process_frame
	_check(not ("Raid on the Woodbooger was interrupted" in _buttons(map)), "map button gone")
	map.free()

	# The legend fell another way: the map calls the raid off by itself.
	_check(await raid.open(t.id, "woodbooger", t.full_name(), "Jack", p.snapshot()) == "", "a new raid can open")
	_check(await raid.start(c.raid_config(lair, 5)) == "", "start it")
	t.owned = true
	map = _map(c, p)
	await process_frame
	await process_frame
	_check(not _buttons(map).any(func(b: String) -> bool: return "Woodbooger" in b), "no raid button once the lair is free")
	await create_timer(0.5).timeout
	await raid.refresh()
	_check(raid.status() == "", "server: raid called off")
	map.free()

	# A fight on screen plays on when the raid is called off under it.
	t.owned = false
	await raid.open(t.id, "woodbooger", t.full_name(), "Jack", p.snapshot())
	await raid.start(c.raid_config(lair, 5))
	raid.holding = true
	var id: String = raid.info.id
	await raid.cancel()
	_check(String(raid.info.get("id", "")) == id, "the fight keeps its raid")
	var stored: Dictionary = await raid.finish({"won": true, "xp": 10})
	_check(not stored.is_empty() and not stored.mine and stored.result.won, "finishing still works: %s" % stored)
	raid.holding = false
	await raid.refresh()
	_check(raid.status() == "", "then it clears")
	print("%d failure(s)" % _fails)
	quit()
