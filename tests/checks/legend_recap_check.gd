extends SceneTree

## The legend fight replay: the recorder keeps the story (entrance, phases, Last Gasp, knockouts,
## the biggest blows, the end) and the cut scene plays it on the real battle screen, win or lose,
## then moves on by itself (or at a tap).

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
	p.team.assign(["black_bear", "red_fox"])
	p.unlocked.assign(p.team)
	for id in ["dog", "black_bear", "red_fox"]:
		p.xp[id] = GameData.xp_to_reach(20)
	return p


func _run() -> void:
	root.theme = Retro.make_theme()
	Profile.save_path = "user://lr_profile.cfg"

	# The recorder, on a hand-played fight.
	var b := Battle.new(_profile(), [["wampus_cat", "shambler"]], 1.0, 1.0, "Wampus Hollow", 3)
	var r := LegendRecap.new()
	r.watch(b)
	b.start_next_wave()
	var cat: Combatant = b.enemies[0]
	var fox: Combatant = b.party.filter(func(c: Combatant) -> bool: return c.id == "red_fox")[0]
	var bear: Combatant = b.party.filter(func(c: Combatant) -> bool: return c.id == "black_bear")[0]
	_check(r.has_legend(), "it knows this is a legend fight")
	for k in 8:  # blow after blow, down through every phase
		b.current = fox if k % 2 == 0 else bear
		b.use_skill(b.current, b.current.skills[0], cat)
		cat.hp = roundi(cat.max_hp * (1.0 - 0.12 * (k + 1)))
		b._apply_damage(cat, 1, false)
	b.current = cat
	b.use_skill(cat, cat.skills[0], bear)
	b._apply_damage(bear, bear.hp, false)
	b.current = fox
	b.use_skill(fox, fox.skills[0], cat)
	b._apply_damage(cat, cat.hp, false)
	var kinds: Array = r.beats().map(func(e: Dictionary) -> String: return e.kind)
	for k in ["phase1", "phase2", "phase3", "ko", "final"]:
		_check(k in kinds, "the replay keeps %s: %s" % [k, kinds])
	_check(kinds.size() <= LegendRecap.MAX_BEATS and kinds.filter(func(k: String) -> bool: return k == "hit").size() <= LegendRecap.TOP_HITS, "only the biggest blows, a dozen beats at most")
	_check(kinds[-1] == "final", "in order, ending with the final blow")
	_check(r.mvp().get("who") in [fox, bear], "it knows the MVP")

	# The cut scene: plays, ends with the result, moves on at a tap.
	var host := Control.new()
	host.size = Vector2(720, 1280)
	root.add_child(host)
	var done := [false]
	var playing := func() -> void:
		await LegendRecapScene.play(host, r, true)
		done[0] = true
	playing.call()
	await process_frame
	await process_frame
	var scene: LegendRecapScene = host.get_child(0)
	_check(scene._round.text == "THE FINAL BLOW" and scene._caption.text.begins_with("Wave 1, round"), "it opens on the final blow: " + scene._caption.text)
	_check(scene._sprites.size() == 2 and scene._sprites.has(fox) and scene._sprites.has(cat), "just the one who struck it and the legend on stage")
	_check(scene._last_hit().get("src") == fox, "it knows the blow that did it")
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	scene._gui_input(ev)
	for k in 10:
		await process_frame
	_check(done[0] and not is_instance_valid(scene) or scene.is_queued_for_deletion(), "a tap skips it and it goes away")

	# Left alone, it plays the blow and the end card, then moves on by itself.
	done[0] = false
	var lose := [false]
	var watch := func() -> void:
		await LegendRecapScene.play(host, r, false)
		lose[0] = true
	watch.call()
	await process_frame
	var scene2: LegendRecapScene = host.get_child(-1)
	_check(scene2._round.text == "THE LAST STAND" and scene2._sprites.has(bear), "a loss replays the last animal to fall")
	var total := LegendRecapScene.INTRO_TIME + LegendRecapScene.SLOW_RUSH + LegendRecapScene.FREEZE + LegendRecapScene.SLOW_FALL + LegendRecapScene.BEAT_TIME
	await create_timer(total + 0.5).timeout
	_check(scene2._round.text == "DEFEAT" and "drives the pack back" in scene2._caption.text and "MVP" in scene2._caption.text, "the end card: %s / %s" % [scene2._round.text, scene2._caption.text.replace("\n", " | ")])
	await create_timer(LegendRecapScene.END_TIME + 0.5).timeout
	_check(lose[0], "and it moves on by itself")
	print("%d failure(s)" % _fails)
	quit()
