extends SceneTree

## The horde is seen moving: what it did since the map was last up, played on the real screen, once,
## whoever's turn caused it.

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


func _fresh() -> Campaign:
	Campaign.clear_saved()
	return Campaign.create(_profile())


func _real_wait(msec: int) -> void:
	var until := Time.get_ticks_msec() + msec
	while Time.get_ticks_msec() < until:
		await process_frame


func _labels(n: Node) -> Array:
	return n.find_children("*", "Label", true, false).map(func(l: Label) -> String: return l.text)


func _kinds(news: Array) -> Array:
	return news.map(func(n: Dictionary) -> String: return n.kind)


func _unheld_neighbor(c: Campaign) -> int:
	for n in c.territories[c.home].neighbors:
		if not c.territories[n].owned:
			return n
	return -1


func _run() -> void:
	root.theme = Retro.make_theme()
	var slot := Saves.new_slot()
	Saves.use(slot)
	var c := _fresh()

	# Nothing new, nothing to say.
	var seen := c.horde_snapshot()
	_check(c.horde_news(seen).is_empty(), "nothing has happened: no news")
	_check(c.horde_news({}).is_empty(), "no earlier look at this map (a game just opened): no news")
	_check(c.horde_news({"key": "another game", "held": {}, "spread": {}, "attack": ""}).is_empty(), "another game's snapshot: no news")

	# A nest spreading.
	c._migrate()
	var news := c.horde_news(seen)
	_check(not news.is_empty() and news[0].kind == "spread", "a nest spreading is news: %s" % [_kinds(news)])
	_check("threat" in news[0].line, "with the new threat: " + news[0].line)
	seen = c.horde_snapshot()
	_check(c.horde_news(seen).is_empty(), "and only once")

	# A counterattack.
	var i := _unheld_neighbor(c)
	c.under_attack = -1
	c.resolve_battle(i, true, 0, [], false)
	seen = c.horde_snapshot()
	c.under_attack = i
	news = c.horde_news(seen)
	_check(_kinds(news) == ["attack"], "a counterattack is news")
	_check(c.territories[i].name.to_upper() in news[0].banner, "named: " + news[0].banner)
	seen = c.horde_snapshot()
	_check(c.horde_news(seen).is_empty(), "and only once")

	# Holding, then losing.
	c.resolve_battle(i, true, 0, [], false)
	_check(not "fell" in _kinds(c.horde_news(seen)), "a held defense is no news")
	seen = c.horde_snapshot()
	c.under_attack = i
	seen = c.horde_snapshot()
	c.resolve_battle(i, false, 0, [], false)
	news = c.horde_news(seen)
	_check("fell" in _kinds(news), "a lost defense: it fell: %s" % [_kinds(news)])
	var fell: Dictionary = news.filter(func(n: Dictionary) -> bool: return n.kind == "fell")[0]
	_check(c.territories[i].name.to_upper() in fell.banner and "threat %d" % c.territories[i].threat in fell.line, "named, with its threat: %s / %s" % [fell.banner, fell.line])
	_check(news.filter(func(n: Dictionary) -> bool: return n.territory == fell.territory).size() == 1, "and it's not also called a spread")

	# It reads the same when the news arrives by a whole new campaign (a teammate's move).
	var before := c.horde_snapshot()
	c.save()
	var rebuilt := Campaign.create(_profile())
	_check(rebuilt.horde_news(before).is_empty(), "a rebuilt map with nothing new: no news")

	# Played on the real screen.
	c = _fresh()
	seen = c.horde_snapshot()
	c._migrate()
	var at := _unheld_neighbor(c)
	var screen := MapScreen.new()
	screen.campaign = c
	screen.profile = _profile()
	screen.horde_news = c.horde_news(seen)
	screen.size = Vector2(720, 1280)
	var done := [0]
	screen.liberation_done.connect(func() -> void: done[0] += 1)
	root.add_child(screen)
	_check(screen.celebrating, "the screen plays it")
	await _real_wait(700)
	_check("THE HORDE SPREADS!" in _labels(screen), "with a banner")
	var view: MapView = screen._map
	for l in view.find_children("*", "Label", false, false):
		if l.visible and l.text != "":
			_check(l.size.y < view.size.y * 0.25, "a banner doesn't cover the map (%.0f of %.0f px tall)" % [l.size.y, view.size.y])
	_check(view._wave_at >= 0, "a tide rolls in")
	_check(view._wave_front == MapView.HORDE_FRONT, "in red")
	_check(view.find_children("*", "TextureRect", false, false).size() >= 3, "zombies march")
	var stop_at := Time.get_ticks_msec() + 12000  # (the map's nests may each have spread: they play in turn)
	while screen.celebrating and Time.get_ticks_msec() < stop_at:
		await process_frame
	await _real_wait(200)
	_check(view._wave_at == -1, "the tide finishes")
	_check(not screen.celebrating and done[0] == 1, "and it ends")
	await _real_wait(900)
	_check(view.find_children("*", "TextureRect", false, false).is_empty(), "zombies are cleaned up")
	_check(not "THE HORDE SPREADS!" in _labels(screen), "the banner too")
	screen.free()

	# A counterattack: siren, swing over, flash, the Defend button ready.
	c = _fresh()
	i = _unheld_neighbor(c)
	c.resolve_battle(i, true, 0, [], false)
	c.under_attack = -1
	seen = c.horde_snapshot()
	c.under_attack = i
	screen = MapScreen.new()
	screen.campaign = c
	screen.profile = _profile()
	screen.horde_news = c.horde_news(seen)
	screen.size = Vector2(720, 1280)
	root.add_child(screen)
	await process_frame
	await process_frame
	view = screen._map
	var pan_start := view._pan
	await _real_wait(800)
	var centered: float = view._to_screen(c.territories[i].site).distance_to(view.size / 2.0)
	_check(centered < 30.0 or view._pan != pan_start, "the view swings to it (%.0f px from the middle)" % centered)
	_check(view.selected == i, "it's selected, ready to defend")
	_check(screen._action.text == "Defend!", "the button says so")
	_check(view.find_children("*", "ColorRect", false, false).size() >= 1, "the map flashes")
	var attack_banner := "THE HORDE ATTACKS %s!" % c.territories[i].name.to_upper()
	_check(attack_banner in _labels(screen), "named: " + attack_banner)
	await _real_wait(2400)
	_check(view.find_children("*", "ColorRect", false, false).is_empty(), "the flash is cleaned up")
	screen.free()

	# A liberation first, then what the horde did in the same turn.
	c = _fresh()
	i = _unheld_neighbor(c)
	seen = c.horde_snapshot()
	c.resolve_battle(i, true, 0, [], false)
	c._migrate()
	var moment := c.take_liberation()
	screen = MapScreen.new()
	screen.campaign = c
	screen.profile = _profile()
	screen.liberation = moment
	screen.horde_news = c.horde_news(seen)
	screen.size = Vector2(720, 1280)
	root.add_child(screen)
	await _real_wait(600)
	_check(moment.banner in _labels(screen), "the liberation plays first")
	_check(not "THE HORDE SPREADS!" in _labels(screen), "not the horde yet")
	await _real_wait(int(MapView.LIBERATION_SEC * 1000) + 300)
	_check("THE HORDE SPREADS!" in _labels(screen), "then the horde answers")
	screen.free()

	# A long run of moves is capped.
	var many: Array = []
	for k in 9:
		many.append({"kind": "spread", "territory": c.territories[c.home].id, "from": Vector2.ZERO, "banner": "X", "line": "y"})
	screen = MapScreen.new()
	screen.campaign = c
	screen.profile = _profile()
	screen.horde_news = many
	screen.size = Vector2(720, 1280)
	var t0 := Time.get_ticks_msec()
	var ended := [false]
	screen.liberation_done.connect(func() -> void: ended[0] = true)
	root.add_child(screen)
	while not ended[0] and Time.get_ticks_msec() - t0 < 15000:
		await process_frame
	_check(ended[0], "a long run of news is capped (%d ms)" % (Time.get_ticks_msec() - t0))
	screen.free()

	# Leaving part way is safe.
	screen = MapScreen.new()
	screen.campaign = c
	screen.profile = _profile()
	screen.horde_news = many
	screen.size = Vector2(720, 1280)
	root.add_child(screen)
	await _real_wait(800)
	screen.free()
	await _real_wait(1500)
	_check(true, "leaving part way is safe")

	# In the real game: seen once, and opening a game says nothing about the past.
	Campaign.clear_saved()
	var p := _profile()
	p.save()
	change_scene_to_file("res://scenes/main.tscn")
	for k in 8:
		await process_frame
	var main: Node = current_scene
	main.get_child(-1).chosen.emit(slot)
	for k in 6:
		await process_frame
	_check(main.get_child(-1) is MapScreen and main.get_child(-1).horde_news.is_empty(), "opening a game: no news")
	main._campaign._migrate()
	main._show_map(main._profile, false)
	await process_frame
	var shown: MapScreen = main.get_child(-1)
	_check(shown.horde_news.size() >= 1, "back on the map: what the horde did")
	main._show_map(main._profile, false)
	await process_frame
	_check(main.get_child(-1).horde_news.is_empty(), "only once")
	print("%d failure(s)" % _fails)
	quit()
