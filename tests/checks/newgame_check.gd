extends SceneTree

## Starting a new game from Setup wipes the critters' progress and the map.

var _fails := 0


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	Profile.save_path = "user://ng_profile.cfg"
	Campaign.save_path = "user://ng_campaign.cfg"
	var p := Profile.new()
	p.region = "us_appalachia"
	p.zip = "24210"
	p.town = "Abingdon"
	p.pet_species = "cat"
	p.pet_name = "Puss in Boots"
	p.team.assign(["whitetail_deer", "alligator"])  # a recruit from another region in the lineup
	p.unlocked.assign(["whitetail_deer", "horned_owl", "bobcat", "alligator", "moose"])
	p.stable.assign(["moose"])
	for id in p.unlocked + [p.pet_species]:
		p.xp[id] = GameData.xp_to_reach(9)
	p.trinkets.assign(["lake_pearl", "frogman_crown"])
	p.equipped = {"cat": "lake_pearl"}
	p.tree = {"cat": ["a"]}
	p.injuries = {"bobcat": 2}
	p.duties = {"scout": "bobcat"}
	p.rows = {"horned_owl": "front"}
	p.siege_claimed.assign([2900])
	p.team_xp = {"team:x": 40}
	p.save()
	var c := Campaign.create(p)
	c.territories[c.territories[c.home].neighbors[0]].owned = true
	c.turn = 30
	c.save()
	_check(FileAccess.file_exists(Campaign.save_path), "an old map is saved")

	var screen := Onboarding.new()
	screen.initial = Profile.load_saved()
	screen.size = Vector2(720, 1280)
	root.add_child(screen)
	var done := []
	screen.finished.connect(func(np: Profile) -> void: done.append(np))
	var cancelled := [false]
	screen.cancelled.connect(func() -> void: cancelled[0] = true)
	for i in 6:
		await process_frame
	var buttons: PackedStringArray = []
	for b in screen.find_children("*", "Button", true, false):
		buttons.append(b.text)
	_check("Cancel" in buttons, "the first setup step offers Cancel: %s" % [buttons])
	screen.call("_show_team")  # the team step drops the out-of-region pick; the player picks again
	var picked: Profile = screen.get("_profile")
	_check(picked.team.is_empty(), "nobody is preselected for the new game")
	screen.call("_toggle_animal", "whitetail_deer")
	screen.call("_toggle_animal", "horned_owl")
	screen.call("_finish")
	var np: Profile = done[0]
	_check(np.zip == "24210" and np.pet_name == "Puss in Boots", "home and pet carry over as suggestions")
	var natives: Array = GameData.REGIONS["us_appalachia"].animals
	_check(np.team.size() == np.locals_needed() and np.team.all(func(id: String) -> bool: return id in natives), "lineup is home animals only: %s" % [np.team])
	_check(np.unlocked.all(func(id: String) -> bool: return id in natives) and "alligator" not in np.unlocked and "moose" not in np.unlocked, "recruits are gone")
	_check(np.stable.is_empty(), "the Stable is empty")
	var max_level := 1
	for id in np.xp:
		max_level = maxi(max_level, np.level_of(id))
	_check(max_level == 1, "everyone is back to Lv 1")
	_check(np.trinkets.is_empty() and np.equipped.is_empty() and np.tree.is_empty(), "no trinkets or tech-tree picks")
	_check(np.injuries.is_empty() and np.rows.is_empty(), "no injuries or row changes (duties: %s, filled fresh)" % [np.duties])
	_check(np.siege_claimed == [2900] and np.team_xp == {"team:x": 40}, "claimed rewards stay claimed")
	_check(not FileAccess.file_exists(Campaign.save_path), "the old map is deleted")
	var fresh := Campaign.create(np)
	_check(fresh.turn == 0 and fresh.owned_count() == 1, "a fresh map: turn 0, only home held")
	var saved := Profile.load_saved()
	_check(saved.stable.is_empty() and saved.trinkets.is_empty(), "the reset is saved")
	print("%d failure(s)" % _fails)
	quit()
