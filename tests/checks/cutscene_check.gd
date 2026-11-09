extends SceneTree

## Legend cut scenes: every legend has a story; its entrance tells it, and at 66% and 33% HP the fight
## pauses for the next chapter, then carries on.

var _fails := 0


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


func _init() -> void:
	_run.call_deferred()


func _real_wait(msec: int) -> void:
	var until := Time.get_ticks_msec() + msec
	while Time.get_ticks_msec() < until:
		await process_frame


func _tap(s: Control) -> void:
	var tap := InputEventMouseButton.new()
	tap.button_index = MOUSE_BUTTON_LEFT
	tap.pressed = true
	for c in s.find_children("*", "LegendCutscene", false, false):
		c._gui_input(tap)


## Skips to the end, then taps Continue.
func _skip(s: Control) -> void:
	_tap(s)
	await _real_wait(300)
	_tap(s)


func _cut(s: Control) -> LegendCutscene:
	var found := s.find_children("*", "LegendCutscene", false, false)
	return null if found.is_empty() else found[0]


func _run() -> void:
	root.theme = Retro.make_theme()
	Profile.save_path = "user://cut_profile.cfg"
	var missing: Array = []
	var weathers := ["storm", "fog", "snow", "swamp", "dust", "embers", "sky"]
	for id in GameData.LEGENDS:
		var st: Dictionary = LegendStory.STORIES.get(id, {})
		if st.is_empty() or String(st.intro) == "" or st.chapters.size() != 2 or not st.weather in weathers:
			missing.append(id)
	_check(missing.is_empty(), "every legend has a story: weather, intro and two chapters %s" % [missing])

	var p := Profile.new()
	p.region = "us_appalachia"
	p.pet_species = "dog"
	p.pet_name = "Jack"
	p.team.assign(["black_bear", "horned_owl"])
	p.unlocked.assign(p.team)
	var s := BattleScreen.new()
	s.profile = p
	s.config = {"waves": [["mothman"]], "zombie_mult": 1.0, "party_mult": 1.0, "place": "Point Pleasant", "condition": "", "region": "us_appalachia", "legend": "mothman"}
	s.size = Vector2(720, 1280)
	root.add_child(s)
	await process_frame
	await process_frame
	var entrance := _cut(s)
	_check(entrance != null and entrance.chapter == 0, "the legend's entrance plays")
	await _real_wait(2500)
	var told := entrance.find_children("*", "Label", true, false).map(func(l: Label) -> String: return l.text)
	_check("POINT PLEASANT" in told and String(LegendStory.of("mothman").intro) in told, "it names the place and tells the tale")
	_tap(s)
	await _real_wait(1500)
	var buttons := entrance.find_children("*", "Button", true, false) if is_instance_valid(entrance) else []
	_check(_cut(s) == entrance and buttons.size() == 1 and buttons[0].text == "Continue",
		"a tap skips to the end, which stays up for reading with Continue")
	_tap(s)
	await _real_wait(700)
	_check(_cut(s) == null, "Continue closes it")

	var b := s.battle
	var mothman: Combatant = b.enemies[0]
	b._apply_damage(mothman, mothman.hp - roundi(mothman.max_hp * 0.6), false)
	await process_frame
	var chapter := _cut(s)
	_check(chapter != null and chapter.chapter == 1 and s.cutscene_holds == 1, "at 66%% the next chapter plays and the turns wait")
	var acting := [0]
	b.acting.connect(func(_c: Combatant) -> void: acting[0] += 1)
	await _real_wait(1500)
	_check(acting[0] == 0, "nobody moves while it's told")
	await _skip(s)
	await _real_wait(700)
	_check(_cut(s) == null and s.cutscene_holds == 0, "then the fight carries on")
	b._apply_damage(mothman, mothman.hp - roundi(mothman.max_hp * 0.3), false)
	await process_frame
	chapter = _cut(s)
	_check(chapter != null and chapter.chapter == 2 and "ENRAGED" in chapter.what_now(), "at 33%%: chapter III, and it enrages")
	await _skip(s)
	await _real_wait(600)
	s.queue_free()
	print("%d failure(s)" % _fails)
	quit()
