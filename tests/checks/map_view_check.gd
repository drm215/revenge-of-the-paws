extends SceneTree

## The map only draws what changed: an idle map redraws nothing unless something glows, glowing is
## capped well under the frame rate, and panning leaves the territory shapes alone.

var _fails := 0
var _view: MapView
var _c: Campaign
var _draws := {"shapes": 0, "pulse": 0, "labels": 0}


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


func _init() -> void:
	_run.call_deferred()


## Draw counts while `seconds` pass, and how many frames that was.
func _watch(seconds: float) -> Dictionary:
	await process_frame
	await process_frame
	for key in _draws:
		_draws[key] = 0
	var frames := 0
	var until := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < until:
		await process_frame
		frames += 1
	return _draws.merged({"frames": frames}, true)


func _run() -> void:
	Profile.save_path = "user://mapview_profile.cfg"
	Campaign.save_path = "user://mapview_campaign.cfg"
	var p := Profile.new()
	p.region = "us_appalachia"
	p.zip = "24210"
	p.town = "Abingdon"
	p.pet_species = "dog"
	p.pet_name = "Jack"
	p.team.assign(["black_bear", "horned_owl"])
	p.unlocked.assign(["black_bear", "horned_owl"])
	_c = Campaign.create(p)
	for t in _c.territories:
		t.boss = ""
	_c.nests.clear()

	_view = MapView.new()
	_view.campaign = _c
	_view.size = Vector2(720, 700)
	root.add_child(_view)
	_view._shapes.draw.connect(func() -> void: _draws.shapes += 1)
	_view._pulse.draw.connect(func() -> void: _draws.pulse += 1)
	_view._labels.draw.connect(func() -> void: _draws.labels += 1)
	await process_frame
	await process_frame

	var seen := await _watch(0.5)
	_check(seen.frames > 5, "the clock ran %d frames" % seen.frames)
	_check(seen.shapes == 0 and seen.pulse == 0 and seen.labels == 0, "nothing glowing, nothing redrawn: %s" % seen)

	var lair: Territory = _c.territories[_c.territories[_c.home].neighbors[0]]
	lair.boss = "woodbooger"
	lair.owned = false
	_view.refresh()
	seen = await _watch(1.0)
	_check(seen.pulse >= 5 and seen.pulse <= 25, "a lair glows at about 20 fps: %d in 1 s, %d frames" % [seen.pulse, seen.frames])
	_check(seen.shapes == 0 and seen.labels == 0, "and leaves shapes and labels alone: %s" % seen)

	var at := _view._shapes.position
	_view._pan += Vector2(25, 10)
	_view._clamp_pan()
	seen = await _watch(0.2)
	_check(_view._shapes.position != at, "panning moves the shapes")
	_check(seen.labels == 0 or seen.shapes == 0, "(watching after the pan settled)")
	for key in _draws:
		_draws[key] = 0
	_view._pan += Vector2(-25, -10)
	_view._clamp_pan()
	await process_frame
	await process_frame
	_check(_draws.shapes == 0 and _draws.labels >= 1, "a pan redraws labels, not shapes: %s" % _draws)

	for key in _draws:
		_draws[key] = 0
	_view._zoom_at(Vector2(300, 300), 1.5)
	await process_frame
	await process_frame
	_check(_draws.shapes >= 1, "a zoom redraws the shapes, so borders keep their width")
	var screen := _view._to_screen(_c.territories[_c.home].site)
	var via_layer: Vector2 = _view._shapes.position + _c.territories[_c.home].site * _view._shapes.scale
	_check(screen.distance_to(via_layer) < 0.01, "the shapes line up with labels and taps")

	_c.under_attack = _c.home
	_view.refresh()
	seen = await _watch(0.5)
	_check(seen.shapes >= 3, "a counterattack makes the fills glow: %d" % seen.shapes)
	_c.under_attack = -1
	_view.refresh()

	# Tapping still finds the territory under the finger, at any zoom.
	var picked := [-1]
	_view.territory_selected.connect(func(i: int) -> void: picked[0] = i)
	var target: Territory = _c.territories[_c.home]
	_view._select_at(_view._to_screen(target.site))
	_check(picked[0] == _c.home, "a tap on home selects home (got %d)" % picked[0])

	var parts_before: Array = _view._parts
	_view.size = Vector2(700, 680)
	await process_frame
	await process_frame
	_check(is_same(parts_before, _view._parts), "a resize doesn't rebuild the geometry")
	print("%d failure(s)" % _fails)
	quit()
