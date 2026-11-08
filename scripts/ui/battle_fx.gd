class_name BattleFx
extends Node

## What makes a battle feel like one: shake, a beat's freeze on big hits, flying gore, slow motion
## on the last blow, combos slammed across the screen, and sound. It only watches the battle and
## changes nothing in it, so raid devices can't drift apart however their effects play out.

const BIG_HIT := 0.3  # of the target's max HP
const GOOD_HIT := 0.12
const SHAKE_DECAY := 40.0  # pixels of shake lost per second
const MAX_SHAKE := 26.0
const FREEZE_SCALE := 0.05
const FREEZE_SEC := 0.06
const SLOW_SCALE := 0.25
const SLOW_SEC := 0.85
const LEGEND_SLOW_SEC := 1.5
const CALLOUT_GAP := 64.0
const ENRAGE_MUSIC_SPEED := 1.12
const LAST_GASP_MUSIC_SPEED := 1.25  # the race is on
const SURVIVED_DELAY := 0.8

var screen: BattleScreen

var _shake := 0.0
var _warp_until := 0  # msec when time runs normally again
var _wound_up: Array[Combatant] = []  # zombies already announced as winding up
var _callouts := 0  # on screen right now, so a second one doesn't land on the first
var _last_tick := 0
var _warning: Array[Control] = []  # Cataclysm's banner and the dark behind it, while it's coming
var _cataclysm_landing := false
var _warned_card: Control  # the legend's card, lifted above the dark
var _gasp_banner: Label  # "LAST GASP IN 2!" while a legend's Last Gasp counts down


## Watches `of`'s battle.
func watch(of: BattleScreen) -> void:
	screen = of
	var b := screen.battle
	b.damaged.connect(_on_damaged)
	b.healed.connect(_on_healed)
	b.died.connect(_on_died)
	b.acting.connect(_on_acting)
	b.combo.connect(_on_combo)
	b.weak_hit.connect(func(_c: Combatant) -> void: _sound("weak"))
	b.status_changed.connect(_on_status)
	b.legend_phase.connect(_on_legend_phase)
	b.last_gasp.connect(_on_last_gasp)
	b.died.connect(func(c: Combatant) -> void:
		if c.is_boss:
			_clear_gasp())
	b.perfect_changed.connect(_on_perfect)
	b.reinforced.connect(func(_fresh: Combatant, _old: Combatant) -> void:
		_sound("arrive")
		_add_shake(12.0))


func _exit_tree() -> void:
	Engine.time_scale = 1.0  # never leave the whole game in slow motion
	if screen:
		screen.position = Vector2.ZERO
		screen.scale = Vector2.ONE
	var sound := get_node_or_null("/root/Sound")
	if sound:
		sound.music_speed(1.0)


## Real time, not game time: slow motion mustn't slow its own ending.
func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	var real := (now - _last_tick) / 1000.0
	_last_tick = now
	if _warp_until > 0 and now >= _warp_until:
		_warp_until = 0
		Engine.time_scale = 1.0
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - SHAKE_DECAY * minf(real, 0.1))
		screen.position = Vector2(randf_range(-_shake, _shake), randf_range(-_shake, _shake))


func _sound(sound_name: String, vary := 0.0, volume_db := 0.0) -> void:
	var sound := get_node_or_null("/root/Sound")
	if sound:
		sound.play(sound_name, vary, volume_db)


func _add_shake(amount: float) -> void:
	_shake = minf(MAX_SHAKE, maxf(_shake, amount))


## Time runs at `time_scale` for `seconds` of real time. The stronger effect wins while both run.
func _warp(time_scale: float, seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000)
	if _warp_until > 0 and Engine.time_scale < time_scale and _warp_until >= until:
		return
	Engine.time_scale = time_scale
	_warp_until = until


func _on_damaged(target: Combatant, amount: int, crit: bool) -> void:
	var share := float(amount) / maxf(1.0, target.max_hp)
	_sound("crit" if crit else "hit", 0.0 if crit else 0.08)
	_burst(target, Color("c8323c") if target.is_player else Retro.GREEN, 6 + roundi(minf(share * 60.0, 22.0)))
	if crit or share >= BIG_HIT:
		_add_shake(13.0)
		_warp(FREEZE_SCALE, FREEZE_SEC)
	elif share >= GOOD_HIT:
		_add_shake(5.0)


func _on_healed(target: Combatant, amount: int) -> void:
	if amount > 0:
		_sound("heal", 0.03)
		_burst(target, Retro.YELLOW, 8, -200.0)


func _on_died(target: Combatant) -> void:
	_sound("down" if target.is_player else "zombie_die", 0.06)
	_burst(target, Color("c8323c") if target.is_player else Retro.GREEN, 26)
	if target.is_player:
		_add_shake(10.0)
	if screen.battle.outcome() == Battle.Outcome.VICTORY:
		_last_blow(target)


## The fight's last blow: slow motion, a white flash, and the view pushing in on the kill.
func _last_blow(target: Combatant) -> void:
	var seconds := LEGEND_SLOW_SEC if target.is_boss else SLOW_SEC
	_sound("finish")
	if target.is_boss:
		_sound("roar")
	_add_shake(MAX_SHAKE if target.is_boss else 16.0)
	_warp(SLOW_SCALE, seconds)
	var flash := ColorRect.new()
	flash.color = Color(1, 1, 1, 0.55)
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.z_index = 15
	screen.add_child(flash)
	var fade := flash.create_tween().set_ignore_time_scale(true)
	fade.tween_property(flash, "color:a", 0.0, 0.35)
	fade.tween_callback(flash.queue_free)
	var card: Control = screen.cards.get(target)
	if card and card.is_inside_tree():
		screen.pivot_offset = card.get_global_rect().get_center()
	var push := screen.create_tween().set_ignore_time_scale(true)
	push.tween_property(screen, "scale", Vector2.ONE * (1.14 if target.is_boss else 1.08), seconds * 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	push.tween_property(screen, "scale", Vector2.ONE, seconds * 0.5).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)


func _on_acting(actor: Combatant) -> void:
	if actor.winding != "":  # a wound-up attack landing
		_wound_up.erase(actor)
		if actor.winding == "cataclysm":
			_cataclysm_lands()
			return
	if not actor.is_player:
		_sound("groan", 0.12, -3.0)
	elif actor.is_leader:
		_sound("meow" if actor.id == "cat" else "bark", 0.05, -2.0)
	else:
		_sound("swoosh", 0.1)


## A combo slams across the screen.
func _on_combo(_target: Combatant, combo_name: String) -> void:
	_sound("combo")
	callout(combo_name.to_upper() + "!", Retro.CYAN)
	_add_shake(4.0)


## A perfect wave earns a gold callout; losing the streak gets a sour one.
func _on_perfect(stacks: int) -> void:
	if stacks > 0:
		_sound("combo")
		callout("PERFECT WAVE! ATK +%d%%" % roundi(screen.battle.perfect_atk_bonus() * 100), Retro.GOLD)
	else:
		callout("STREAK LOST", Retro.ORANGE)


## Big text slammed across the middle of the field, then gone.
func callout(text: String, color: Color) -> void:
	var label := Label.new()
	label.text = text
	Retro.title(label, 22, color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_outline_color", Retro.INK)
	label.add_theme_constant_override("outline_size", 12)
	label.z_index = 14
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(label)
	label.size = Vector2(screen.size.x, 60)
	label.position = Vector2(0, screen.size.y * 0.34 + _callouts * CALLOUT_GAP)
	label.pivot_offset = label.size / 2.0
	label.scale = Vector2.ONE * 2.6
	_callouts += 1
	var tween := label.create_tween().set_ignore_time_scale(true)
	tween.tween_property(label, "scale", Vector2.ONE, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_interval(0.55)
	tween.tween_property(label, "modulate:a", 0.0, 0.25)
	tween.tween_callback(func() -> void:
		_callouts -= 1
		label.queue_free())


## A zombie starting to wind up sounds the alarm, once.
func _on_status(c: Combatant) -> void:
	if c.winding == "":
		if c in _wound_up:
			_wound_up.erase(c)
			if c.is_boss:
				_clear_warning()
				_sound("combo")
				callout("INTERRUPTED!", Retro.GREEN)
	elif c not in _wound_up:
		_wound_up.append(c)
		_sound("windup")
		if c.winding == "cataclysm":
			_warn_cataclysm(c)


# --- Legends -----------------------------------------------------------------------------------

## A cover over the whole screen, overshooting it so a shake never shows its edge.
func _cover(color: Color, z: int, blocks_taps := false) -> ColorRect:
	var cover := ColorRect.new()
	cover.color = color
	cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cover.offset_left = -120
	cover.offset_top = -120
	cover.offset_right = 120
	cover.offset_bottom = 120
	cover.z_index = z
	cover.mouse_filter = Control.MOUSE_FILTER_STOP if blocks_taps else Control.MOUSE_FILTER_IGNORE
	screen.add_child(cover)
	return cover


## Waits `seconds` of real time; a tap on a skippable moment ends it early.
func _beat(seconds: float, skipped: Array) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < until and not skipped[0]:
		await get_tree().process_frame


func _make_skippable(cover: Control) -> Array:
	var skipped := [false]
	cover.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			skipped[0] = true)
	return skipped


func _center_label(parent: Control, text: String, font_size: int, color: Color, y_share: float, title := true) -> Label:
	var label := Label.new()
	if title:
		Retro.title(label, font_size, color)
	else:
		Retro.text(label, font_size, color)
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_outline_color", Retro.INK)
	label.add_theme_constant_override("outline_size", 8)
	label.z_index = parent.z_index + 1
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(label)
	label.position = Vector2(24, screen.size.y * y_share)
	label.size = Vector2(screen.size.x - 48, 0)
	label.pivot_offset = Vector2(label.size.x / 2.0, 30)
	return label


## Battle music for a wave, or a legend's entrance. Waits for the entrance to finish.
func wave_started() -> void:
	for z in screen.battle.enemies:
		if z.is_boss:
			await _legend_entrance(z)
			_music("boss")
			return
		if z.id == "warlord":
			_sound("roar")
			_add_shake(16.0)
			callout(z.display_name.to_upper() + "!", Retro.RED)
			_music("boss")
			return
	_music("battle")


## The lights go out and the music dies. Footfalls shake the ground, then the legend roars into view
## with its name. A tap skips it. Only the screen waits: the fight itself is untouched.
func _legend_entrance(legend: Combatant) -> void:
	if BattleScreen.play_recaps:
		await LegendCutscene.play_entrance(screen, legend, screen.battle.place)
		_add_shake(10.0)
		return
	_music("")
	var dark := _cover(Color(0, 0, 0, 0), 16, true)
	var skipped := _make_skippable(dark)
	var shown: Array[Control] = [dark]
	var fade := dark.create_tween()
	fade.tween_property(dark, "color:a", 0.94, 0.3)
	await _beat(0.35, skipped)
	for k in 2:
		if not skipped[0]:
			_sound("thud")
			_add_shake(9.0 + k * 7.0)
		await _beat(0.5, skipped)
	if not skipped[0]:
		_sound("roar")
		_add_shake(MAX_SHAKE)
		var art := "res://art/pixel/%s.png" % legend.id
		if ResourceLoader.exists(art):
			var portrait := TextureRect.new()
			portrait.texture = load(art)
			portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			portrait.flip_h = true
			portrait.modulate = Color(1.6, 1.6, 1.6)  # many legends are dark, and this is on black
			portrait.z_index = 17
			portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
			screen.add_child(portrait)
			var side := minf(screen.size.x * 0.7, 460.0)
			portrait.size = Vector2(side, side)
			portrait.position = Vector2((screen.size.x - side) / 2.0, screen.size.y * 0.16)
			portrait.pivot_offset = portrait.size / 2.0
			portrait.scale = Vector2.ONE * 0.5
			portrait.create_tween().tween_property(portrait, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			shown.append(portrait)
		var title := _center_label(dark, legend.display_name.to_upper(), 30, Retro.RED, 0.6)
		title.scale = Vector2.ONE * 1.8
		title.create_tween().tween_property(title, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		shown.append(title)
		shown.append(_center_label(dark, GameData.LEGENDS[legend.id].lore, 21, Retro.MIST, 0.69, false))
		await _beat(1.7, skipped)
	for item in shown:
		if is_instance_valid(item):
			item.queue_free()
	_add_shake(10.0)


func _on_legend_phase(legend: Combatant, phase: int) -> void:
	if phase in [1, 2] and BattleScreen.play_recaps:
		# The fight waits while the next chapter of the legend's story is told.
		screen.cutscene_holds += 1
		await LegendCutscene.play_chapter(screen, legend, phase)
		screen.cutscene_holds -= 1
		if not is_inside_tree():
			return
	_sound("roar", 0.08, -3.0)
	if phase == 3:
		_add_shake(MAX_SHAKE)
		callout("LAST GASP!", Retro.RED)
		var sound := get_node_or_null("/root/Sound")
		if sound:
			sound.music_speed(LAST_GASP_MUSIC_SPEED)
		return
	if phase == 1:
		_add_shake(16.0)
		callout("REINFORCEMENTS!", Retro.PINK)
		return
	_add_shake(MAX_SHAKE * 0.85)
	callout("ENRAGED!", Retro.RED)
	var card: UnitCard = screen.cards.get(legend)
	if card:
		card.enrage()
	var sound := get_node_or_null("/root/Sound")
	if sound:
		sound.music_speed(ENRAGE_MUSIC_SPEED)
	# The screen's edges pulse red for the rest of the fight.
	var glow := _cover(Color(Retro.RED, 0.0), 13)
	var pulse := glow.create_tween().set_loops()
	pulse.tween_property(glow, "color:a", 0.16, 0.5).set_trans(Tween.TRANS_SINE)
	pulse.tween_property(glow, "color:a", 0.03, 0.5).set_trans(Tween.TRANS_SINE)


## The Last Gasp countdown: a banner pinned at the top of the field, ticking down on each of the
## legend's turns; at 0 the screen burns and heaves.
func _on_last_gasp(_legend: Combatant, turns_left: int) -> void:
	if turns_left <= 0:
		_clear_gasp()
		_sound("finish")
		_sound("roar")
		_add_shake(MAX_SHAKE)
		_warp(0.3, 0.4)
		var burn := _cover(Color(Retro.RED, 0.75), 15)
		var fade := burn.create_tween().set_ignore_time_scale(true)
		fade.tween_property(burn, "color:a", 0.0, 0.6)
		fade.tween_callback(burn.queue_free)
		callout("LAST GASP!", Retro.RED)
		return
	if _gasp_banner == null or not is_instance_valid(_gasp_banner):
		_gasp_banner = Label.new()
		Retro.title(_gasp_banner, 24, Retro.RED)
		_gasp_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_gasp_banner.add_theme_color_override("font_outline_color", Retro.INK)
		_gasp_banner.add_theme_constant_override("outline_size", 12)
		_gasp_banner.z_index = 18
		_gasp_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		screen.add_child(_gasp_banner)
		_gasp_banner.size = Vector2(screen.size.x, 60)
		_gasp_banner.position = Vector2(0, screen.size.y * 0.2)
		_gasp_banner.pivot_offset = _gasp_banner.size / 2.0
		var pulse := _gasp_banner.create_tween().set_loops()
		pulse.tween_property(_gasp_banner, "modulate", Color(1.6, 1.6, 1.6), 0.25)
		pulse.tween_property(_gasp_banner, "modulate", Color.WHITE, 0.25)
	_gasp_banner.text = "LAST GASP IN %d!" % turns_left
	_gasp_banner.scale = Vector2.ONE * 1.6
	_gasp_banner.create_tween().set_ignore_time_scale(true).tween_property(_gasp_banner, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_sound("windup")
	_add_shake(8.0)


func _clear_gasp() -> void:
	if _gasp_banner and is_instance_valid(_gasp_banner):
		_gasp_banner.queue_free()
	_gasp_banner = null


## Cataclysm is coming: the screen darkens around the legend, and a banner says what to do about it.
func _warn_cataclysm(legend: Combatant) -> void:
	_clear_warning()
	var dark := _cover(Color(0, 0, 0, 0.38), 10)
	_warning.append(dark)
	_warned_card = screen.cards.get(legend)
	if _warned_card:
		_warned_card.z_index = 11
	var banner := _center_label(dark, "CATACLYSM NEXT TURN!", 24, Retro.RED, 0.135)
	banner.z_index = 18
	var hint := _center_label(dark, "Stun it to cancel. Guard to halve it.", 20, Retro.WHITE, 0.185, false)
	hint.z_index = 18
	_warning.append(banner)
	_warning.append(hint)
	var pulse := banner.create_tween().set_loops()
	pulse.tween_property(banner, "modulate", Color(1.5, 1.5, 1.5), 0.25)
	pulse.tween_property(banner, "modulate", Color.WHITE, 0.25)


func _clear_warning() -> void:
	for item in _warning:
		if is_instance_valid(item):
			item.queue_free()
	_warning.clear()
	if is_instance_valid(_warned_card):
		_warned_card.z_index = 0
	_warned_card = null


## It lands: the screen burns red and heaves. Anyone left standing has earned the word.
func _cataclysm_lands() -> void:
	_clear_warning()
	_sound("finish")
	_sound("roar")
	_add_shake(MAX_SHAKE)
	_warp(0.35, 0.35)
	var burn := _cover(Color(Retro.RED, 0.6), 15)
	var fade := burn.create_tween().set_ignore_time_scale(true)
	fade.tween_property(burn, "color:a", 0.0, 0.45)
	fade.tween_callback(burn.queue_free)
	await _beat(SURVIVED_DELAY, [false])
	if screen.battle.outcome() == Battle.Outcome.ONGOING:
		_sound("heal")
		callout("SURVIVED!", Retro.YELLOW)


## The legend's treasure: a chest bursts open in a shower of gold. A tap moves on.
func legend_loot(trinket_id: String) -> void:
	await _beat(0.7, [false])  # let the last blow finish
	var dark := _cover(Color(0, 0, 0, 0), 16, true)
	var skipped := _make_skippable(dark)
	var fade := dark.create_tween()
	fade.tween_property(dark, "color:a", 0.88, 0.25)
	var shown: Array[Control] = [dark]
	var at := Vector2(screen.size.x / 2.0, screen.size.y * 0.36)
	for part: Array in [[Vector2(-90, -20), Vector2(180, 100), Color("8a5a2b")], [Vector2(-90, 18), Vector2(180, 12), Retro.GOLD], [Vector2(-14, 8), Vector2(28, 34), Retro.YELLOW]]:
		var piece := ColorRect.new()
		piece.color = part[2]
		piece.position = at + part[0]
		piece.size = part[1]
		piece.z_index = 17
		piece.mouse_filter = Control.MOUSE_FILTER_IGNORE
		screen.add_child(piece)
		shown.append(piece)
	var lid := ColorRect.new()
	lid.color = Color("a86f35")
	lid.position = at + Vector2(-96, -64)
	lid.size = Vector2(192, 46)
	lid.z_index = 18
	lid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(lid)
	shown.append(lid)
	await _beat(0.3, skipped)
	_sound("loot")
	_add_shake(8.0)
	var open := lid.create_tween().set_parallel()
	open.tween_property(lid, "position:y", lid.position.y - 90.0, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	open.tween_property(lid, "rotation", -0.35, 0.22)
	var gold := CPUParticles2D.new()
	gold.one_shot = true
	gold.explosiveness = 0.75
	gold.amount = 70
	gold.lifetime = 1.4
	gold.direction = Vector2.UP
	gold.spread = 42.0
	gold.gravity = Vector2(0, 620)
	gold.initial_velocity_min = 260.0
	gold.initial_velocity_max = 640.0
	gold.scale_amount_min = 5.0
	gold.scale_amount_max = 11.0
	gold.color = Retro.YELLOW
	gold.z_index = 19
	gold.position = at + Vector2(0, -20)
	gold.finished.connect(gold.queue_free)
	screen.add_child(gold)
	gold.emitting = true
	var data := GameData.trinket(trinket_id)
	shown.append(_center_label(dark, "LEGENDARY DROP!", 18, Retro.CYAN, 0.5))
	var name_label := _center_label(dark, String(data.name), 26, Retro.GOLD, 0.55)
	name_label.scale = Vector2.ONE * 1.7
	name_label.create_tween().tween_property(name_label, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	shown.append(name_label)
	shown.append(_center_label(dark, GameData.trinket_effects(trinket_id), 21, Retro.MIST, 0.63, false))
	await _beat(2.4, skipped)
	for item in shown:
		if is_instance_valid(item):
			item.queue_free()


## The end of a wave or fight.
func outcome(result: Battle.Outcome) -> void:
	match result:
		Battle.Outcome.WAVE_CLEARED:
			_sound("wave_clear")
		Battle.Outcome.VICTORY:
			_sound("victory")
			_music("")
		Battle.Outcome.DEFEAT:
			_sound("defeat")
			_music("")


func _music(song: String) -> void:
	var sound := get_node_or_null("/root/Sound")
	if sound:
		sound.music(song)


## A spray of square bits from a unit's card. `gravity` below 0 floats them up.
func _burst(unit: Combatant, color: Color, amount: int, gravity := 700.0) -> void:
	var card: Control = screen.cards.get(unit)
	if card == null or not card.is_inside_tree():
		return
	var bits := CPUParticles2D.new()
	bits.one_shot = true
	bits.explosiveness = 1.0
	bits.amount = maxi(1, amount)
	bits.lifetime = 0.55
	bits.direction = Vector2.UP
	bits.spread = 180.0
	bits.gravity = Vector2(0, gravity)
	bits.initial_velocity_min = 70.0
	bits.initial_velocity_max = 260.0
	bits.scale_amount_min = 4.0
	bits.scale_amount_max = 9.0
	bits.color = color
	bits.z_index = 12
	bits.position = card.get_global_rect().get_center()
	bits.finished.connect(bits.queue_free)
	screen.add_child(bits)
	bits.emitting = true
