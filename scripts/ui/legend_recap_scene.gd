class_name LegendRecapScene
extends Control

## The legend fight's last moment, replayed: a short, dramatic cut scene after it's over. On a win the
## animal that struck the final blow rushes the legend in slow motion, the frame freezes on the hit
## and the legend drops; on a loss the legend fells the last animal standing. Then an end card names
## the result, the rounds and the pack's MVP. It moves on by itself; a tap skips it.

signal finished

const INTRO_TIME := 0.8  # the title, before the blow
const SLOW_RUSH := 1.1  # the attacker closing in, slowed
const FREEZE := 0.5  # the frame held on the hit
const SLOW_FALL := 1.0  # the loser going down
const BEAT_TIME := 1.2  # the caption after
const END_TIME := 3.0  # seconds the end card stays up

var recap: LegendRecap
var won := false

var _stage := Control.new()
var _round := Label.new()
var _caption := Label.new()
var _sprites := {}  # Combatant -> TextureRect
var _home := {}  # Combatant -> its resting position
var _skipped := false
var _done := false


## Plays the replay over `screen` and waits until it's over (or skipped).
static func play(screen: Control, r: LegendRecap, victory: bool) -> void:
	var scene := LegendRecapScene.new()
	scene.recap = r
	scene.won = victory
	scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scene.z_index = 40
	screen.add_child(scene)
	await scene.finished
	scene.queue_free()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.02, 0.06, 0.96)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	for top in [true, false]:  # letterbox bars: it's a movie now
		var bar := ColorRect.new()
		bar.color = Color.BLACK
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE if top else Control.PRESET_BOTTOM_WIDE)
		bar.custom_minimum_size = Vector2(0, 110)
		add_child(bar)
	var title := _label("REPLAY", 14, Retro.FOG)
	title.position = Vector2(24, 40)
	var skip := _label("Tap to skip", 14, Retro.FOG)
	skip.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	skip.offset_left = -220
	skip.offset_right = -24
	skip.offset_top = 40
	skip.offset_bottom = 70
	skip.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_stage)
	_round = _label("", 18, Retro.GOLD)
	_round.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_round.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_round.position.y = 150
	_caption = _label("", 22, Retro.WHITE, false)
	_caption.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_caption.offset_left = 30
	_caption.offset_right = -30
	_caption.offset_top = -300
	_caption.offset_bottom = -130
	_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_place_cast.call_deferred()
	_run.call_deferred()


func _gui_input(event: InputEvent) -> void:
	if (event is InputEventMouseButton or event is InputEventScreenTouch) and event.pressed:
		_skipped = true
		accept_event()


## The two who matter: whoever struck the last blow (or, in a loss, the last animal to fall) on the
## left, the legend big on the right.
func _place_cast() -> void:
	var b := recap.battle
	var top := 230.0
	var height := size.y - top - 340.0
	var field_color: Color = GameData.CONDITION_FIELD.get(b.condition, Retro.SWAMP)
	var field := Panel.new()
	field.add_theme_stylebox_override("panel", Retro.box(field_color, field_color.lightened(0.2), Retro.BORDER, 0, 0))
	field.position = Vector2(14, top - 10)
	field.size = Vector2(size.x - 28, height + 20)
	field.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(field)
	var legend := recap.legend
	var big := minf(size.x * 0.52, height)
	_add_sprite(legend, Vector2(size.x - big - 30, top + (height - big) / 2.0), Vector2(big, big))
	var hero := _hero()
	if hero:
		var small := minf(size.x * 0.3, height * 0.6)
		_add_sprite(hero, Vector2(40, top + height - small - 20), Vector2(small, small))
		var tag := _label(_name(hero), 16, Retro.MIST, false)
		tag.position = _home[hero] + Vector2(0, small)
		tag.size = Vector2(small, 22)
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tag.clip_text = true


func _add_sprite(c: Combatant, at: Vector2, box: Vector2) -> void:
	var s := TextureRect.new()
	var pixel := "res://art/pixel/%s.png" % c.id
	var vector := "res://art/units/%s.svg" % c.id
	if ResourceLoader.exists(pixel):
		s.texture = load(pixel)
		s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	elif ResourceLoader.exists(vector):
		s.texture = load(vector)
	s.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	s.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	s.flip_h = not c.is_player
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	s.position = at
	s.size = box
	s.pivot_offset = box / 2.0
	_stage.add_child(s)
	_sprites[c] = s
	_home[c] = at


## The moment replayed: the legend's death on a win, the last knockout on a loss ({} if none).
func moment() -> Dictionary:
	for k in range(recap.events.size() - 1, -1, -1):
		var e: Dictionary = recap.events[k]
		if (won and e.kind == "final") or (not won and e.kind == "ko"):
			return e
	return {}


## Whoever is on the left: the animal that struck the last blow, or the last one to fall.
func _hero() -> Combatant:
	var e := moment()
	if e.is_empty():
		return null
	var who: Combatant = e.src if won else e.dst
	return who if who and who.is_player else null


## How hard the last blow hit (0 if it isn't known).
func _last_hit() -> Dictionary:
	var e := moment()
	for k in range(recap.events.size() - 1, -1, -1):
		var h: Dictionary = recap.events[k]
		if int(h.seq) > int(e.get("seq", 0)):
			continue
		if (won and h.kind == "hit") or (not won and h.kind == "smash" and h.dst == e.get("dst")):
			return h
	return {}


func _run() -> void:
	var legend := recap.legend
	var e := moment()
	var hero := _hero()
	var hit := _last_hit()
	_round.text = "THE FINAL BLOW" if won else "THE LAST STAND"
	_round.add_theme_color_override("font_color", Retro.GOLD if won else Retro.RED)
	_caption.text = ("Wave %d, round %d..." % [int(e.wave) + 1, maxi(1, int(e.round))]) if not e.is_empty() else ""
	_pop(_sprites[legend], 1.15)
	await _wait(INTRO_TIME)
	if not _skipped:
		await _strike(legend, hero, hit)
	if not _skipped:
		if won:
			_caption.text = ("%s's %s fells the %s!" % [_name(hero), e.skill, legend.display_name]) if hero else "The %s falls!" % legend.display_name
		else:
			_caption.text = ("%s is the last to fall." % _name(hero)) if hero else "The pack falls."
		await _wait(BEAT_TIME)
	if not _skipped:
		_ending()
		await _wait(END_TIME)
	_done = true
	finished.emit()


## The blow itself, in slow motion: the attacker closes in, everything freezes on the hit in a white
## flash, then the loser drops.
func _strike(legend: Combatant, hero: Combatant, hit: Dictionary) -> void:
	var src: Combatant = hero if won else legend
	var dst: Combatant = legend if won else hero
	var sound := get_node_or_null("/root/Sound")
	if src and _sprites.has(src):
		var s: TextureRect = _sprites[src]
		var aim: Vector2 = _home[dst] if dst and _home.has(dst) else s.position + Vector2(200 if src.is_player else -200, 0)
		var close: Vector2 = s.position.lerp(aim, 0.55)
		if sound:
			sound.play("swoosh", 0.0, -2.0)
		var t := _tween()
		t.tween_property(s, "position", close, SLOW_RUSH).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		t.parallel().tween_property(s, "scale", Vector2.ONE * 1.25, SLOW_RUSH)
		await _wait(SLOW_RUSH)
	if _skipped:
		return
	if sound:
		sound.play("finish")
		sound.play("roar" if won else "down")
	_burn(Color(1, 1, 1, 0.85))
	_shake(28.0)
	var amount := int(hit.get("amount", 0))
	if amount > 0:
		_number(dst, ("CRIT %d!" if hit.get("crit", false) else "%d!") % amount, Retro.YELLOW if hit.get("crit", false) else Retro.PINK, 40)
	await _wait(FREEZE)
	if dst and _sprites.has(dst):
		var d: TextureRect = _sprites[dst]
		var t := _tween().set_parallel()
		t.tween_property(d, "rotation", deg_to_rad(90.0 if not dst.is_player else -90.0), SLOW_FALL).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		t.tween_property(d, "modulate", Color(0.4, 0.4, 0.45, 0.6), SLOW_FALL)
		t.tween_property(d, "position:y", d.position.y + 40, SLOW_FALL)
	if src and _sprites.has(src):
		_tween().tween_property(_sprites[src], "scale", Vector2.ONE, 0.5)
	await _wait(SLOW_FALL)


## The last card: who won, how long it took, and who carried the pack.
func _ending() -> void:
	var legend := recap.legend
	var b := recap.battle
	var rounds := 0
	for e in recap.events:
		if int(e.wave) == b.wave_index:
			rounds = maxi(rounds, int(e.round))
	_round.text = "VICTORY!" if won else "DEFEAT"
	_round.add_theme_color_override("font_color", Retro.GOLD if won else Retro.RED)
	_pop(_round, 1.5)
	var lines: PackedStringArray = []
	lines.append(("The %s is dead." if won else "The %s drives the pack back.") % legend.display_name)
	if rounds > 0:
		lines.append("%d rounds against it, %d of its HP taken." % [rounds, legend.max_hp - legend.hp] if not won else "%d rounds against it." % rounds)
	var best := recap.mvp()
	if not best.is_empty():
		lines.append("MVP: %s · %d damage to the %s" % [_name(best.who), best.damage, legend.display_name])
	_caption.text = "\n".join(lines)


func _name(c: Combatant) -> String:
	if c == null:
		return "Someone"
	return ("%s's %s" % [c.ally_of, c.display_name]) if c.ally_of != "" else c.display_name


# --- Animation ------------------------------------------------------------------------------

func _tween() -> Tween:
	return create_tween().set_ignore_time_scale(true)


func _lunge(src: Combatant, dst: Combatant) -> void:
	if src == null or not _sprites.has(src):
		return
	var s: TextureRect = _sprites[src]
	var home: Vector2 = _home[src]
	var aim := Vector2(-90, 0) if not src.is_player else Vector2(90, 0)
	if dst and _sprites.has(dst):
		aim = (_sprites[dst].position - home).normalized() * 70.0
	var t := _tween()
	t.tween_property(s, "position", home + aim, 0.14).set_ease(Tween.EASE_OUT)
	t.tween_property(s, "position", home, 0.25).set_ease(Tween.EASE_IN)


func _flash(c: Combatant, color: Color) -> void:
	if c == null or not _sprites.has(c):
		return
	var s: TextureRect = _sprites[c]
	var rest := s.modulate
	var t := _tween()
	t.tween_property(s, "self_modulate", color, 0.08)
	t.tween_property(s, "self_modulate", Color.WHITE, 0.3)
	s.modulate = rest


func _fall(c: Combatant) -> void:
	if c == null or not _sprites.has(c):
		return
	var s: TextureRect = _sprites[c]
	var t := _tween().set_parallel()
	t.tween_property(s, "rotation", deg_to_rad(-90.0 if c.is_player else 90.0), 0.35).set_ease(Tween.EASE_IN)
	t.tween_property(s, "modulate", Color(0.4, 0.4, 0.45, 0.55), 0.35)


func _pop(node: Control, by: float) -> void:
	node.pivot_offset = node.size / 2.0
	node.scale = Vector2.ONE * by
	_tween().tween_property(node, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _number(c: Combatant, text: String, color: Color, font_size: int) -> void:
	if c == null or not _sprites.has(c):
		return
	var s: TextureRect = _sprites[c]
	var label := _label(text, font_size, color)
	label.add_theme_color_override("font_outline_color", Retro.INK)
	label.add_theme_constant_override("outline_size", 10)
	label.position = s.position + Vector2(s.size.x / 2.0 - 40, s.size.y * 0.2)
	label.position.x = clampf(label.position.x, 10.0, size.x - label.get_combined_minimum_size().x - 10.0)  # on screen
	var t := _tween().set_parallel()
	t.tween_property(label, "position:y", label.position.y - 80, 1.0).set_ease(Tween.EASE_OUT)
	t.tween_property(label, "modulate:a", 0.0, 0.6).set_delay(0.6)
	t.chain().tween_callback(label.queue_free)


func _burn(color: Color) -> void:
	var cover := ColorRect.new()
	cover.color = color
	cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cover)
	var t := _tween()
	t.tween_property(cover, "color:a", 0.0, 0.6)
	t.tween_callback(cover.queue_free)
	for c: Combatant in _sprites:
		if c.is_player and c.is_alive():
			_flash(c, Color(1.8, 0.5, 0.5))


func _shake(amount: float) -> void:
	var t := _tween()
	for k in 6:
		t.tween_property(_stage, "position", Vector2(randf_range(-amount, amount), randf_range(-amount, amount)), 0.04)
	t.tween_property(_stage, "position", Vector2.ZERO, 0.05)


## Waits `seconds` of real time; a tap cuts it short.
func _wait(seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < until and not _skipped and is_inside_tree():
		await get_tree().process_frame


func _label(text: String, font_size: int, color: Color, is_title := true) -> Label:
	var label := Retro.title(Label.new(), font_size, color) if is_title else Retro.text(Label.new(), font_size, color)
	if not is_title:
		label.add_theme_font_override("font", Retro.pixel_font())  # pixels throughout, like the cut scenes
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label
