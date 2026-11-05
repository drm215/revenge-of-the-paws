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

var screen: BattleScreen

var _shake := 0.0
var _warp_until := 0  # msec when time runs normally again
var _wound_up: Array[Combatant] = []  # zombies already announced as winding up
var _callouts := 0  # on screen right now, so a second one doesn't land on the first
var _last_tick := 0


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
	b.reinforced.connect(func(_fresh: Combatant, _old: Combatant) -> void:
		_sound("arrive")
		_add_shake(12.0))


func _exit_tree() -> void:
	Engine.time_scale = 1.0  # never leave the whole game in slow motion
	if screen:
		screen.position = Vector2.ZERO
		screen.scale = Vector2.ONE


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
		_wound_up.erase(c)
	elif c not in _wound_up:
		_wound_up.append(c)
		_sound("windup")


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


## Battle music for a wave, or a legend's entrance: its roar and its theme.
func wave_started() -> void:
	for z in screen.battle.enemies:
		if z.is_boss:
			_music("boss")
			_sound("roar")
			_add_shake(18.0)
			return
	_music("battle")


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
