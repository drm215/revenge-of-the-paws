extends SceneTree

## Ready the pack starts with nobody picked; Back restores the old lineup; Fight keeps the new one.

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
	p.pet_species = "dog"
	p.pet_name = "Jack"
	p.team.assign(["black_bear", "horned_owl"])
	p.unlocked.assign(["black_bear", "horned_owl", "bobcat", "whitetail_deer"])
	p.auto_fill_duties()
	return p


func _screen(p: Profile) -> PackScreen:
	var s := PackScreen.new()
	s.profile = p
	s.battle_config = {"place": "Bristol", "waves": [["shambler"]], "zombie_mult": 1.0, "condition": "forest", "region": "us_appalachia"}
	s.size = Vector2(720, 1280)
	root.add_child(s)
	return s


func _run() -> void:
	var p := _profile()
	var duties_before := p.duties.duplicate()
	var s := _screen(p)
	for k in 3:
		await process_frame
	var fight: Button = s.get("_done")
	_check(p.team.is_empty(), "nobody starts out picked")
	_check(fight.disabled, "Fight! is locked until 2 are picked")
	s.call("_toggle", "bobcat")
	s.call("_back")
	_check(Array(p.team) == ["black_bear", "horned_owl"] and p.duties == duties_before, "Back with half a lineup restores the old lineup and duties")
	s.queue_free()

	p = _profile()
	s = _screen(p)
	for k in 3:
		await process_frame
	s.call("_toggle", "bobcat")
	s.call("_toggle", "whitetail_deer")
	fight = s.get("_done")
	_check(not fight.disabled and Array(p.team) == ["bobcat", "whitetail_deer"], "picking 2 unlocks Fight! with the new lineup")

	var map_pack := PackScreen.new()
	var q := _profile()
	map_pack.profile = q
	root.add_child(map_pack)
	await process_frame
	_check(q.team.size() == 2, "the Pack screen from the map still shows the current lineup")
	print("%d failure(s)" % _fails)
	quit()
