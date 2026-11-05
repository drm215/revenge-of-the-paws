extends SceneTree

## Battle effects: they fire, always clean up after themselves (above all, time returns to normal),
## and never change what happens in a fight. Sound: every file loads, and mute is remembered.

var _fails := 0


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


func _init() -> void:
	_run.call_deferred()


func _pack() -> Profile:
	var p := Profile.new()
	p.region = "us_appalachia"
	p.pet_species = "dog"
	p.pet_name = "Jack"
	p.team.assign(["black_bear", "bobcat"])
	p.unlocked.assign(["black_bear", "bobcat"])
	for id in ["dog", "black_bear", "bobcat"]:
		p.xp[id] = GameData.xp_to_reach(10)
	return p


func _screen(waves: Array) -> BattleScreen:
	var s := BattleScreen.new()
	s.profile = _pack()
	s.config = {"waves": waves, "zombie_mult": 1.0, "party_mult": 1.0, "place": "t", "condition": "", "region": "us_appalachia"}
	s.size = Vector2(720, 1280)
	root.add_child(s)
	return s


func _real_wait(msec: int) -> void:
	var until := Time.get_ticks_msec() + msec
	while Time.get_ticks_msec() < until:
		await process_frame


func _count(s: BattleScreen, type: String) -> int:
	return s.find_children("*", type, false, false).size()


func _run() -> void:
	root.theme = Retro.make_theme()
	Profile.save_path = "user://fx_profile.cfg"
	Campaign.save_path = "user://fx_campaign.cfg"
	var sound: Node = root.get_node("Sound")

	for sound_name: String in ["hit", "crit", "heal", "down", "zombie_die", "groan", "swoosh", "bark", "meow", "combo", "weak", "wave_clear",
			"victory", "defeat", "roar", "arrive", "windup", "finish", "thud", "loot", "liberate", "firework", "alarm", "horde", "music_map", "music_battle", "music_boss"]:
		if not ResourceLoader.exists("res://audio/%s.wav" % sound_name) or sound._stream(sound_name) == null:
			_check(false, "missing sound: " + sound_name)
	_check(sound._stream("hit").get_length() < 0.5, "effects are short")
	_check(sound._stream("music_battle").get_length() > 10.0, "songs are whole loops (%.0f s)" % sound._stream("music_battle").get_length())
	_check((sound._stream("music_map") as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_FORWARD, "songs loop")
	_check((sound._stream("music_boss") as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_FORWARD, "the legend's theme loops")
	_check((sound._stream("hit") as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_DISABLED, "effects don't")

	sound.set_muted(true)
	_check(AudioServer.is_bus_mute(0), "mute mutes")
	var cfg := ConfigFile.new()
	cfg.load(sound.SETTINGS)
	_check(cfg.get_value("sound", "muted", false) == true, "and is remembered")
	sound.set_muted(false)
	_check(not AudioServer.is_bus_mute(0), "unmute unmutes")
	sound.music("battle")
	_check(sound.current_music == "battle", "music starts")
	sound.music("")
	_check(sound.current_music == "", "and stops")

	# A hard hit: freeze, then normal again; shake, then still; bits, then gone.
	var s := _screen([["shambler", "shambler"], ["shambler"]])
	await process_frame
	await process_frame
	var b := s.battle
	var fx: BattleFx = s._fx
	var target: Combatant = b.enemies[0]
	b._apply_damage(target, roundi(target.max_hp * 0.5), true)
	_check(Engine.time_scale < 1.0, "a crit freezes the moment")
	_check(fx._shake > 0.0, "and shakes the screen")
	_check(_count(s, "CPUParticles2D") >= 1, "and throws bits")
	var crit_label: Label = null
	for l in s.find_children("*", "Label", false, false):
		if l.text.begins_with("CRIT"):
			crit_label = l
	_check(crit_label != null, "a crit shows big")
	var field_end: float = s._enemy_col.get_global_rect().end.x
	_check(crit_label.global_position.x + crit_label.get_combined_minimum_size().x <= field_end + 1.0, "and stays on the battlefield")
	await _real_wait(1500)
	_check(Engine.time_scale == 1.0, "time returns to normal")
	_check(fx._shake == 0.0, "the shake dies away (at %s)" % s.position)
	_check(_count(s, "CPUParticles2D") == 0, "the bits are cleaned up")

	# Small hits stay quiet: no constant shaking.
	b._apply_damage(b.party[0], 1, false)
	_check(fx._shake == 0.0 and Engine.time_scale == 1.0, "a scratch doesn't shake or freeze")

	# Combos are called out, and two don't land on each other.
	b.combo.emit(target, "Opening")
	b.combo.emit(target, "Knockdown")
	var seen: Array[String] = []
	var ys: Array[float] = []
	for l in s.find_children("*", "Label", false, false):
		if l.text == "OPENING!" or l.text == "KNOCKDOWN!":
			seen.append(l.text)
			ys.append(l.position.y)
	_check(seen.size() == 2, "combos are called out: %s" % [seen])
	_check(ys.size() == 2 and ys[0] != ys[1], "one below the other")
	await _real_wait(1300)
	_check(s.find_children("*", "Label", false, false).filter(func(l: Label) -> bool: return l.text.ends_with("!") and l.text in ["OPENING!", "KNOCKDOWN!"]).is_empty(), "then they're gone")

	# A wave's last kill isn't the battle's last blow.
	for z in b.enemies:
		b._apply_damage(z, 99999, false)
	_check(b.outcome() == Battle.Outcome.WAVE_CLEARED and s.scale == Vector2.ONE, "clearing a wave doesn't play the finish")
	s.free()
	_check(Engine.time_scale == 1.0, "leaving a battle always restores time")
	await process_frame

	# The last blow: slow motion and a push-in; everything back after.
	s = _screen([["shambler"]])
	await process_frame
	await process_frame
	b = s.battle
	b._apply_damage(b.enemies[0], 99999, false)
	_check(Engine.time_scale < 1.0 and Engine.time_scale >= BattleFx.FREEZE_SCALE, "the last blow slows time (x%.2f)" % Engine.time_scale)
	await _real_wait(300)
	_check(s.scale.x > 1.0, "and pushes in (x%.2f)" % s.scale.x)
	await _real_wait(1000)
	_check(Engine.time_scale == 1.0 and s.scale.is_equal_approx(Vector2.ONE), "then everything is back")

	# Leaving in the middle of slow motion.
	s.free()
	s = _screen([["shambler"]])
	await process_frame
	await process_frame
	s.battle._apply_damage(s.battle.enemies[0], 99999, false)
	_check(Engine.time_scale < 1.0, "slow motion running")
	s.free()
	_check(Engine.time_scale == 1.0, "leaving mid-slow-motion restores time")

	# A legend gets its theme, and its own bigger finish.
	s = _screen([["woodbooger"]])
	await process_frame
	await process_frame
	_check(s._fx._beat != null, "a legend's fight starts")
	await _real_wait(3200)
	_check(sound.current_music == "boss", "a legend brings its theme")
	s.battle._apply_damage(s.battle.enemies[0], 9999999, false)
	await process_frame
	_check(s._fx._warp_until - Time.get_ticks_msec() > int(BattleFx.SLOW_SEC * 1000), "and a longer slow motion")
	s.free()
	s = _screen([["shambler"]])
	await process_frame
	await process_frame
	_check(sound.current_music == "battle", "ordinary fights get the battle theme")
	s.free()

	# Effects never touch the fight: the same seed plays out the same, watched or not.
	var plain := _play(false)
	var watched := await _play_watched()
	_check(plain == watched, "a fight with effects ends exactly like one without\n  %s\n  %s" % [plain, watched])
	print("%d failure(s)" % _fails)
	quit()


func _finish(b: Battle) -> String:
	var turns := 0
	while turns < 3000:
		var actor := b.next_turn()
		if actor == null:
			if b.outcome() == Battle.Outcome.WAVE_CLEARED:
				b.start_next_wave()
				continue
			break
		var plan := AutoBattle.pick_action(b, actor) if actor.is_player else b.plan_enemy_action(actor)
		b.use_skill(actor, plan.skill, plan.target)
		turns += 1
	return str(b.party.map(func(c: Combatant) -> int: return c.hp)) + str(b.enemies.map(func(c: Combatant) -> int: return c.hp)) + " turns %d" % turns


func _play(_with_fx: bool) -> String:
	var b := Battle.new(_pack(), [["shambler", "runner"], ["woodbooger", "brute"]], 1.2, 1.0, "t", 42)
	b.start_next_wave()
	return _finish(b)


func _play_watched() -> String:
	var s := _screen([["shambler"]])
	await process_frame
	var b := Battle.new(_pack(), [["shambler", "runner"], ["woodbooger", "brute"]], 1.2, 1.0, "t", 42)
	var host := BattleScreen.new()
	host.battle = b
	var fx := BattleFx.new()
	s.add_child(fx)
	fx.screen = s
	b.damaged.connect(fx._on_damaged)
	b.healed.connect(fx._on_healed)
	b.died.connect(fx._on_died)
	b.acting.connect(fx._on_acting)
	b.combo.connect(fx._on_combo)
	b.status_changed.connect(fx._on_status)
	b.start_next_wave()
	var out := _finish(b)
	host.free()
	s.free()
	return out
