extends SceneTree

## Legend fights as events, on the real battle screen: entrance, phases, Cataclysm's warning and what
## follows it, and the treasure. None of it may hold up or change the fight.

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


func _screen(waves: Array, extra := {}) -> BattleScreen:
	var s := BattleScreen.new()
	s.profile = _pack()
	s.config = {"waves": waves, "zombie_mult": 1.0, "party_mult": 1.0, "place": "t", "condition": "", "region": "us_appalachia"}.merged(extra)
	s.size = Vector2(720, 1280)
	root.add_child(s)
	return s


func _real_wait(msec: int) -> void:
	var until := Time.get_ticks_msec() + msec
	while Time.get_ticks_msec() < until:
		await process_frame


func _texts(s: Control) -> Array:
	return s.find_children("*", "Label", false, false).map(func(l: Label) -> String: return l.text)


func _tap(s: Control) -> void:
	var cover: Control = null
	for c in s.get_children():
		if c is ColorRect and c.z_index == 16:
			cover = c
	var press := InputEventMouseButton.new()
	press.pressed = true
	press.button_index = MOUSE_BUTTON_LEFT
	cover.gui_input.emit(press)


func _hurt_to(b: Battle, legend: Combatant, ratio: float) -> void:
	b._apply_damage(legend, maxi(1, legend.hp - roundi(legend.max_hp * ratio)), false)


## Past the entrance, on a screen where the legend is up.
func _past_entrance(waves: Array, extra := {}) -> BattleScreen:
	var s := _screen(waves, extra)
	await process_frame
	await process_frame
	_tap(s)
	await _real_wait(150)
	return s


func _run() -> void:
	root.theme = Retro.make_theme()
	Profile.save_path = "user://le_profile.cfg"
	Campaign.save_path = "user://le_campaign.cfg"
	var sound: Node = root.get_node("Sound")

	# Ordinary fights have no entrance.
	var s := _screen([["shambler"]])
	await process_frame
	await process_frame
	_check(s.find_children("*", "ColorRect", false, false).all(func(c: ColorRect) -> bool: return c.z_index != 16), "an ordinary fight has no entrance")
	_check(sound.current_music == "battle", "and its music starts at once")
	s.free()

	# The entrance: dark and silent, then the name.
	s = _screen([["woodbooger", "shambler"]])
	await process_frame
	await process_frame
	_check(sound.current_music == "", "a legend's entrance: the music dies")
	_check(s.battle.current == null, "and nobody's turn has started")
	await _real_wait(1700)
	_check("WOODBOOGER" in _texts(s), "then its name: %s" % [_texts(s)])
	_check(s.battle.current == null, "still waiting")
	await _real_wait(2000)
	_check(not "WOODBOOGER" in _texts(s), "the entrance ends")
	_check(sound.current_music == "boss", "its theme starts")
	_check(s.battle.current != null or s._actor != null, "and the fight goes on")
	s.free()

	# Skipping.
	s = _screen([["woodbooger"]])
	await process_frame
	await process_frame
	var t0 := Time.get_ticks_msec()
	_tap(s)
	await _real_wait(200)
	_check(s.find_children("*", "ColorRect", false, false).all(func(c: ColorRect) -> bool: return c.z_index != 16), "a tap skips it")
	_check(Time.get_ticks_msec() - t0 < 1000 and sound.current_music == "boss", "straight to the fight")
	s.free()

	# Leaving during it is safe.
	s = _screen([["woodbooger"]])
	await process_frame
	s.free()
	await _real_wait(1200)
	_check(true, "leaving during the entrance is safe")

	# Phases.
	s = await _past_entrance([["woodbooger", "shambler"]])
	var b := s.battle
	var legend: Combatant = b.enemies[0]
	_hurt_to(b, legend, 0.6)
	_check("REINFORCEMENTS!" in _texts(s), "66%: reinforcements are called out")
	_check(s._fx._shake > 0.0, "and the ground shakes")
	_hurt_to(b, legend, 0.3)
	_check("ENRAGED!" in _texts(s), "33%: enraged")
	await _real_wait(400)
	_check(s.cards[legend]._sprite.scale.x > 1.1, "the legend swells (x%.2f)" % s.cards[legend]._sprite.scale.x)
	_check(is_equal_approx(sound._music.pitch_scale, BattleFx.ENRAGE_MUSIC_SPEED), "the music speeds up")
	_check(s.find_children("*", "ColorRect", false, false).any(func(c: ColorRect) -> bool: return c.z_index == 13), "the screen pulses red")
	s.free()
	_check(is_equal_approx(sound._music.pitch_scale, 1.0), "leaving puts the music back to speed")

	# Cataclysm's warning, stunned.
	s = await _past_entrance([["woodbooger"]])
	b = s.battle
	legend = b.enemies[0]
	legend.cooldowns.clear()
	b.use_skill(legend, "cataclysm", b.plan_enemy_action(legend).target)
	_check("CATACLYSM NEXT TURN!" in _texts(s), "Cataclysm winding up: the banner goes up")
	_check(s.cards[legend].z_index > 0, "the legend stands out of the dark")
	_check(s.find_children("*", "ColorRect", false, false).any(func(c: ColorRect) -> bool: return c.z_index == 10), "the screen darkens")
	_check(s.find_children("*", "ColorRect", false, false).all(func(c: ColorRect) -> bool: return c.z_index != 10 or c.mouse_filter == Control.MOUSE_FILTER_IGNORE), "and the player can still tap through it")
	legend.add_status("stunned", 1)
	b._turn_queue.assign([legend])
	b.next_turn()
	await process_frame
	_check(not "CATACLYSM NEXT TURN!" in _texts(s), "a stun takes the banner down")
	_check("INTERRUPTED!" in _texts(s), "and calls it out")
	_check(s.cards[legend].z_index == 0, "and the card settles back")
	s.free()

	# Cataclysm landing, survived; the alarm can sound again next time.
	s = await _past_entrance([["woodbooger"]])
	b = s.battle
	legend = b.enemies[0]
	legend.cooldowns.clear()
	var target: Combatant = b.plan_enemy_action(legend).target
	b.use_skill(legend, "cataclysm", target)
	b.use_skill(legend, "cataclysm", target)
	await process_frame
	_check(not "CATACLYSM NEXT TURN!" in _texts(s), "when it lands the banner goes")
	_check(not legend in s._fx._wound_up, "and next time warns again")
	_check(Engine.time_scale < 1.0, "the blast slows time")
	await _real_wait(1000)
	_check(Engine.time_scale == 1.0, "only for a moment")
	_check("SURVIVED!" in _texts(s), "those left standing survived it")
	s.free()

	# A Cataclysm that wipes the pack doesn't claim otherwise.
	s = await _past_entrance([["woodbooger"]])
	b = s.battle
	legend = b.enemies[0]
	legend.cooldowns.clear()
	legend.atk = 999999
	target = b.plan_enemy_action(legend).target
	b.use_skill(legend, "cataclysm", target)
	b.use_skill(legend, "cataclysm", target)
	await _real_wait(1000)
	_check(b.outcome() == Battle.Outcome.DEFEAT and not "SURVIVED!" in _texts(s), "wiped out: no \"SURVIVED!\"")
	s.free()

	# The treasure, then the results, waiting for neither more than a moment.
	s = await _past_entrance([["woodbooger"]], {"legend": "woodbooger", "loot": "hollow_bark_armor"})
	b = s.battle
	b.enemies[0].hp = 1
	b._apply_damage(b.enemies[0], 50, false)
	s._show_outcome()
	await _real_wait(1100)
	var drop_name: String = GameData.trinket("hollow_bark_armor").name
	_check(drop_name in _texts(s), "the chest shows its treasure: %s" % drop_name)
	_check(not s._overlay.visible, "before the results")
	await _real_wait(2600)
	_check(s._overlay.visible and "Liberated!" == s._overlay_title.text, "then the results")
	_check(not drop_name in _texts(s), "and the treasure screen is gone")
	s.free()

	# A legend that has nothing left to give: straight to the results.
	s = await _past_entrance([["woodbooger"]], {"legend": "woodbooger", "loot": ""})
	b = s.battle
	b.enemies[0].hp = 1
	b._apply_damage(b.enemies[0], 50, false)
	s._show_outcome()
	await process_frame
	_check(s._overlay.visible, "no drop left: straight to the results")
	s.free()

	# What the fight offers matches the map.
	var p := _pack()
	p.zip = "24210"
	p.town = "Abingdon"
	var c := Campaign.create(p)
	var lair: int = c.territories[c.home].neighbors[0]
	for t in c.territories:
		t.boss = ""
	c.territories[lair].boss = "woodbooger"
	_check(c.battle_config(lair).loot == GameData.LEGENDS.woodbooger.drop, "the map offers its drop")
	c.claimed.append(c.territories[lair].id)
	_check(c.battle_config(lair).loot == "", "until it's been taken")
	_check(Engine.time_scale == 1.0, "time is normal at the end of it all")
	print("%d failure(s)" % _fails)
	quit()
