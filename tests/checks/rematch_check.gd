extends SceneTree

## Rematches: a beaten legend's lair can be fought again just for fun. No XP, no trinket, no
## injuries, and the map doesn't move.

var _fails := 0


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


func _pack() -> Profile:
	var p := Profile.new()
	p.region = "us_appalachia"
	p.zip = "24210"
	p.town = "Abingdon"
	p.pet_species = "dog"
	p.pet_name = "Jack"
	p.team.assign(["black_bear", "horned_owl"])
	p.unlocked.assign(["black_bear", "horned_owl"])
	for id in ["dog", "black_bear", "horned_owl"]:
		p.xp[id] = GameData.xp_to_reach(20)
	return p


func _real_wait(msec: int) -> void:
	var until := Time.get_ticks_msec() + msec
	while Time.get_ticks_msec() < until:
		await process_frame


func _tap(s: Control) -> void:
	for c in s.get_children():
		if c is ColorRect and c.z_index == 16:
			var press := InputEventMouseButton.new()
			press.pressed = true
			press.button_index = MOUSE_BUTTON_LEFT
			c.gui_input.emit(press)


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	root.theme = Retro.make_theme()
	BattleScreen.play_recaps = false
	Profile.save_path = "user://rematch_profile.cfg"
	Campaign.save_path = "user://rematch_campaign.cfg"
	var p := _pack()
	var c := Campaign.create(p)
	for t in c.territories:
		t.boss = ""
	var i: int = c.territories[c.home].neighbors[0]
	var lair: Territory = c.territories[i]
	lair.boss = "woodbooger"
	lair.owned = false
	_check(not c.can_rematch(i), "an unbeaten legend can't be rematched (it's a real attack)")
	var map := MapScreen.new()
	map.campaign = c
	map.profile = p
	root.add_child(map)
	await process_frame
	map._select(i)
	_check(not map._rematch.visible, "no Rematch button on an unbeaten lair")

	lair.owned = true
	c._ownership_changed()
	_check(c.can_rematch(i), "a beaten legend can be rematched")
	map._select(i)
	_check(map._rematch.visible and "Rematch it any time" in map._info_body.text, "the lair offers a Rematch: " + map._info_body.text.get_slice("\n", 1))
	var asked := [-1]
	map.rematch_requested.connect(func(k: int) -> void: asked[0] = k)
	map._rematch.pressed.emit()
	_check(asked[0] == i, "pressing it asks for the rematch")
	map.free()

	var turn := c.turn
	var cfg := c.rematch_config(i)
	var has_legend := false
	for wave: Array in cfg.waves:
		has_legend = has_legend or "woodbooger" in wave
	_check(has_legend and cfg.legend == "woodbooger" and cfg.loot == "" and cfg.rematch, "the same legend fight, with nothing to drop")
	_check(c.turn == turn and lair.owned, "setting it up changes nothing on the map")

	# Win it: no XP, no trinket, no injuries.
	var xp_before := p.xp.duplicate()
	var trinkets_before := p.trinkets.duplicate()
	var s := BattleScreen.new()
	s.profile = p
	s.config = cfg.merged({"waves": [cfg.waves[-1]]}, true)  # straight to the legend's wave
	s.size = Vector2(720, 1280)
	root.add_child(s)
	await process_frame
	await process_frame
	_tap(s)
	await _real_wait(150)
	var b := s.battle
	b.downed.append(b.party[0].id)  # someone got knocked out along the way
	var guard := 0
	while not b.living(b.enemies).is_empty() and guard < 20:
		guard += 1
		for e in b.living(b.enemies):
			e.hp = 1
			b._apply_damage(e, 50, false)
	_check(b.outcome() == Battle.Outcome.VICTORY, "the legend is down")
	s._show_outcome()
	await _real_wait(300)
	_check(s._overlay.visible and s._overlay_title.text == "The legend falls again!", "winning: " + s._overlay_title.text)
	_check("just for fun" in s._overlay_body.text, "the results say it was for fun")
	_check(p.xp == xp_before and s.xp_awarded == 0, "no XP")
	_check(p.trinkets == trinkets_before, "no trinket")
	_check(p.injuries.is_empty(), "no injuries, even for the one knocked out")
	var done := [false]
	s.finished.connect(func(_won: bool) -> void: done[0] = true)
	s._overlay_button.pressed.emit()
	_check(done[0], "Back to map")
	s.free()
	print("%d failure(s)" % _fails)
	quit()
