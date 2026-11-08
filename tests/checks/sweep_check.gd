extends SceneTree

## Sweep: land far below the fighting pack falls without a fight (a turn, no injuries, a share of
## the XP, no fatigue). Lairs, warlords, counterattacks and close fights are always fought.

var _fails := 0


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


func _init() -> void:
	_run.call_deferred()


func _profile(level: int) -> Profile:
	var p := Profile.new()
	p.region = "us_appalachia"
	p.zip = "24210"
	p.town = "Abingdon"
	p.pet_species = "dog"
	p.pet_name = "Jack"
	p.team.assign(["black_bear", "horned_owl"])
	p.unlocked.assign(p.team)
	for id in ["dog", "black_bear", "horned_owl"]:
		p.xp[id] = GameData.xp_to_reach(level)
	return p


func _target(c: Campaign) -> int:
	for i in c.territories.size():
		if c.can_attack(i) and c.territories[i].boss == "" and c.warlord_at(i).is_empty():
			return i
	return -1


func _run() -> void:
	root.theme = Retro.make_theme()
	var slot := Saves.new_slot()
	Saves.use(slot)
	var p := _profile(30)
	Campaign.clear_saved()
	var c := Campaign.create(p)
	c.under_attack = -1
	var i := _target(c)
	c.territories[i].met_level = 5
	c.territories[i].threat = 1
	_check(c.territory_level(i) <= p.pack_level() - GameData.SWEEP_LEVEL_GAP and c.can_sweep(i),
		"Lv %d land before a Lv %d pack can be swept" % [c.territory_level(i), p.pack_level()])
	_check(c.sweep_xp(i) > 0, "for a share of its XP: %d" % c.sweep_xp(i))

	# What's always fought.
	var close := Campaign.create(_profile(c.territory_level(i) + GameData.SWEEP_LEVEL_GAP - 1))
	close.under_attack = -1
	close.territories[i].met_level = 5
	close.territories[i].threat = 1
	_check(not close.can_sweep(i), "not when the pack is less than %d levels above it" % GameData.SWEEP_LEVEL_GAP)
	c.under_attack = i
	_check(not c.can_sweep(i), "not a counterattack")
	c.under_attack = -1
	var lair := -1
	for k in c.territories.size():
		if c.territories[k].boss != "":
			lair = k
	if lair >= 0:
		c.territories[lair].met_level = 1
		_check(not c.can_sweep(lair), "never a legend's lair")
	_check(not c.can_sweep(c.home), "not land you hold")

	# The real map and the real flow.
	p.save()
	c.save()
	change_scene_to_file("res://scenes/main.tscn")
	for k in 8:
		await process_frame
	var main: Node = current_scene
	main.get_child(-1).chosen.emit(slot)
	for k in 6:
		await process_frame
	var map: MapScreen = main.get_child(-1)
	var mc: Campaign = main._campaign
	mc.territories[i].met_level = 5
	mc.territories[i].threat = 1
	mc.under_attack = -1
	map._select(i)
	_check(map._sweep.visible and "Sweep takes it now" in map._info_body.text, "the map offers Sweep beside Attack!")
	var turn: int = mc.turn
	var xp_before: int = main._profile.xp.dog
	main._profile.fatigue["black_bear"] = 1
	main._profile.duties.erase("forage")  # a forager's random find would muddle the XP count
	var expected: int = mc.sweep_xp(i)
	map._sweep.pressed.emit()
	for k in 6:
		await process_frame
	mc = main._campaign
	_check(mc.territories[i].owned, "Sweep frees it")
	_check(mc.turn == turn + 1, "it takes a map turn")
	_check(main._profile.xp.dog == xp_before + expected, "the pack gets the XP (+%d; dog went %d -> %d, turn %d -> %d, event: %s)" % [
		expected, xp_before, main._profile.xp.dog, turn, mc.turn, mc.last_event.replace("
", " | ")])
	_check(main._profile.injuries.is_empty() and int(main._profile.fatigue.get("black_bear", 0)) == 1, "no injuries, and nobody tires")
	_check(main._campaign.last_event.begins_with("Swept "), "the map says so: " + main._campaign.last_event.get_slice("\n", 0))
	print("%d failure(s)" % _fails)
	quit()
