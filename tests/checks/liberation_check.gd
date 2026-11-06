extends SceneTree

## Freeing a territory plays on the map, once, with its real name and what it means. Only this
## player's own liberations do, and a teammate's move can't cut it short.

var _fails := 0


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


func _init() -> void:
	_run.call_deferred()


func _profile() -> Profile:
	var p := Profile.new()
	p.region = "us_appalachia"
	p.zip = "24210"
	p.town = "Abingdon"
	p.pet_species = "dog"
	p.pet_name = "Jack"
	p.team.assign(["black_bear", "horned_owl"])
	p.unlocked.assign(["black_bear", "horned_owl"])
	return p


## A new map, not the last one's save.
func _fresh(p: Profile) -> Campaign:
	Campaign.clear_saved()
	return Campaign.create(p)


func _free_one(c: Campaign, in_state := "") -> int:
	for i in c.territories.size():
		if c.can_attack(i) and c.territories[i].boss == "" and (in_state == "" or c._state_of(i) == in_state):
			c.under_attack = -1
			c.resolve_battle(i, true, 0, [], false)
			return i
	return -1


func _real_wait(msec: int) -> void:
	var until := Time.get_ticks_msec() + msec
	while Time.get_ticks_msec() < until:
		await process_frame


func _texts(n: Node) -> Array:
	return n.find_children("*", "Label", true, false).map(func(l: Label) -> String: return l.text)


func _run() -> void:
	root.theme = Retro.make_theme()
	var slot := Saves.new_slot()
	Saves.use(slot)
	var p := _profile()
	var c := _fresh(p)

	_check(c.take_liberation().is_empty(), "nothing to play at the start")

	# A liberation: its real name, where it came from.
	var i := _free_one(c)
	var t: Territory = c.territories[i]
	var moment := c.take_liberation()
	_check(moment.territory == t.id and moment.banner == t.name.to_upper() + " IS FREE!", "the banner names the place: " + moment.banner)
	var near_home := false
	for n in t.neighbors:
		near_home = near_home or c.territories[n].site == moment.from
	_check(near_home, "the wave starts from the held land next door")
	_check(c.take_liberation().is_empty(), "and it plays once")
	_check(not "territories" in moment.milestone, "no count of what's free or left: '%s'" % moment.milestone)

	# What doesn't count.
	c.resolve_battle(i, true, 0, [], false)
	_check(c.take_liberation().is_empty(), "already free: nothing")
	var other := -1
	for k in c.territories.size():
		if c.can_attack(k):
			other = k
			break
	c.under_attack = -1
	c.resolve_battle(other, false, 0, [], false)
	_check(c.take_liberation().is_empty(), "a lost battle: nothing")
	c.resolve_patrol(i, true)
	_check(c.take_liberation().is_empty(), "a patrol: nothing")
	c.under_attack = i
	c.resolve_battle(i, true, 0, [], false)
	_check(c.take_liberation().is_empty(), "a defense held: nothing")
	c.under_attack = -1
	c.replaying = true
	c.resolve_battle(other, true, 0, [], false)
	c.replaying = false
	_check(c.take_liberation().is_empty(), "a move being replayed: nothing")

	# No counts, even on round numbers.
	c = _fresh(p)
	var counted := false
	for k in 12:
		_free_one(c)
		counted = counted or "territories" in String(c.take_liberation().milestone)
	_check(not counted, "a round number isn't counted out either")

	# Milestones: crossing a state line. 24210 is Virginia; Tennessee is next door.
	c = _fresh(_profile())
	var home_state := c._state_of(c.home)
	_check(home_state == "VA", "home is in Virginia")
	var crossed := ""
	var seen_state := {home_state: true}
	var guard := 0
	while crossed == "" and guard < 80:
		guard += 1
		var f := _free_one(c)
		if f < 0:
			break
		var m := c.take_liberation()
		var st := c._state_of(f)
		if not seen_state.has(st):
			seen_state[st] = true
			crossed = m.milestone
	_check(crossed.begins_with("The pack has reached") and crossed.ends_with("!"), "crossing a state line is a moment: " + crossed)
	_check(GameData.STATE_NAMES.values().any(func(name: String) -> bool: return name in crossed), "with the state's real name")

	# Milestones: a legend, with its name.
	c = _fresh(_profile())
	var lair := -1
	for k in c.territories[c.home].neighbors:
		if not c.territories[k].owned:
			lair = k
			break
	for tt in c.territories:
		tt.boss = ""
	c.territories[lair].boss = "woodbooger"
	c.resolve_battle(lair, true, 0, [], false)
	var boss_moment := c.take_liberation()
	_check(boss_moment.milestone == "The Woodbooger is dead!" or boss_moment.milestone.begins_with("The pack has reached"), "a legend's lair says so: " + boss_moment.milestone)

	# Someone rescued comes along.
	c = _fresh(_profile())
	var with_recruit := -1
	for k in c.territories.size():
		if c.can_attack(k) and c.territories[k].boss == "":
			with_recruit = k
			break
	c.territories[with_recruit].recruit = "bobcat"
	c.resolve_battle(with_recruit, true, 0, [], false)
	_check(c.take_liberation().rescued == "bobcat", "the rescued animal is part of it")

	# Played on the real map screen, all the way through.
	c = _fresh(_profile())
	i = _free_one(c)
	moment = c.take_liberation()
	var screen := MapScreen.new()
	screen.campaign = c
	screen.profile = p
	screen.liberation = moment
	screen.size = Vector2(720, 1280)
	var done := [0]
	screen.liberation_done.connect(func() -> void: done[0] += 1)
	root.add_child(screen)
	_check(screen.celebrating, "the map screen plays it")
	await process_frame
	await process_frame
	await process_frame
	var view: MapView = screen._map
	_check(view._wave_at == i, "the wave is rolling")
	_check(view._fill(i) == MapView.ATTACKABLE, "over the land as it was")
	_check(moment.banner in _texts(screen), "the banner is up")
	_check(view.find_children("*", "TextureRect", false, false).size() >= 1, "the pet runs across")
	var sel: int = view.selected
	_check(sel == i, "the info box is on the freed land")
	await _real_wait(int(MapView.WAVE_SEC * 1000) + 200)
	_check(view._wave_at == -1, "the wave finishes")
	_check(view._fill(i) != MapView.ATTACKABLE, "and the land is held")
	var fired := view.find_children("*", "CPUParticles2D", false, false).size()
	_check(fired >= 1, "fireworks go off (%d)" % fired)
	await _real_wait(int(MapView.LIBERATION_SEC * 1000))
	_check(not screen.celebrating and done[0] == 1, "it ends")
	await _real_wait(1500)
	_check(not moment.banner in _texts(screen), "the banner is gone")
	_check(view.find_children("*", "CPUParticles2D", false, false).is_empty(), "the fireworks are cleaned up")
	_check(view.find_children("*", "TextureRect", false, false).is_empty(), "and the runners")
	screen.free()

	# Leaving mid-way is safe.
	c = _fresh(_profile())
	_free_one(c)
	screen = MapScreen.new()
	screen.campaign = c
	screen.profile = p
	screen.liberation = c.take_liberation()
	screen.size = Vector2(720, 1280)
	root.add_child(screen)
	await _real_wait(300)
	screen.free()
	await _real_wait(1800)
	_check(true, "leaving while it plays is safe")

	# In the real game: it plays once on return to the map, and a teammate's move waits for it.
	change_scene_to_file("res://scenes/main.tscn")
	for k in 8:
		await process_frame
	var main: Node = current_scene
	main.get_child(-1).chosen.emit(slot) if FileAccess.file_exists(Saves.path(slot, Saves.PROFILE)) else null
	if not FileAccess.file_exists(Saves.path(slot, Saves.PROFILE)):
		p.save()
		main._show_saves()
		for k in 3:
			await process_frame
		main.get_child(-1).chosen.emit(slot)
	for k in 6:
		await process_frame
	_check(main.get_child(-1) is MapScreen, "the map is up")
	var live: Campaign = main._campaign
	_free_one(live)
	main._show_map(main._profile, false)
	for k in 4:
		await process_frame
	var first: MapScreen = main.get_child(-1)
	_check(first.celebrating, "coming back to the map plays it")
	main._on_team_changed()
	await process_frame
	_check(main.get_child(-1) == first and first.celebrating, "a teammate's move doesn't cut it short")
	await _real_wait(int(MapView.LIBERATION_SEC * 1000) + 300)
	var after: Node = main.get_child(-1)
	_check(after is MapScreen and after != first, "it rebuilds the map when the moment ends")
	_check(not after.celebrating, "without playing it again")
	print("%d failure(s)" % _fails)
	quit()
