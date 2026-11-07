class_name LegendRecapScene
extends Control

## The legend fight, replayed: a short cut scene after it's over, win or lose. The pack stands on the
## left and the legend on the right; each big moment (LegendRecap.beats) plays out with a lunge, the
## damage, and a caption, and the fallen stay down. An end card names the result, the rounds and the
## pack's MVP. It plays by itself and moves on by itself; a tap skips it.

signal finished

const BEAT_TIME := 1.7  # seconds per moment
const END_TIME := 4.0  # seconds the end card stays up
const INTRO_TIME := 2.0

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


## The pack in a column on the left (two columns if it's a big raid), the legend big on the right.
func _place_cast() -> void:
	var b := recap.battle
	var pack := b.party
	var columns := 1 if pack.size() <= 6 else 2
	var rows := ceili(pack.size() / float(columns))
	var top := 210.0
	var height := size.y - top - 320.0
	# The battlefield, lit, so dark sprites still read.
	var field_color: Color = GameData.CONDITION_FIELD.get(b.condition, Retro.SWAMP)
	var field := Panel.new()
	field.add_theme_stylebox_override("panel", Retro.box(field_color, field_color.lightened(0.2), Retro.BORDER, 0, 0))
	field.position = Vector2(14, top - 10)
	field.size = Vector2(size.x - 28, height + 20)
	field.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(field)
	var cell := minf(height / maxf(rows, 1), 170.0)
	var column_w := minf((size.x * 0.48) / columns, cell * 1.6)
	for k in pack.size():
		var c: Combatant = pack[k]
		var at := Vector2(24 + (k % columns) * column_w, top + (k / columns) * cell + (height - rows * cell) / 2.0)
		_add_sprite(c, at, Vector2(column_w, cell * 0.78))
		var tag := _label(_name(c), 14, Retro.MIST, false)
		tag.position = at + Vector2(0, cell * 0.74)
		tag.size = Vector2(column_w, 20)
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tag.clip_text = true
	var legend := recap.legend
	var big := minf(size.x * 0.5, height)
	_add_sprite(legend, Vector2(size.x - big - 30, top + (height - big) / 2.0), Vector2(big, big))


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


func _run() -> void:
	var legend := recap.legend
	var place := recap.battle.place if recap.battle.place != "" else "its lair"
	_round.text = "THE BATTLE OF " + place.to_upper()
	_caption.text = "The %s rises to meet the pack." % legend.display_name
	_pop(_sprites[legend], 1.25)
	await _wait(INTRO_TIME)
	for beat in recap.beats():
		if _skipped:
			break
		_play_beat(beat)
		await _wait(BEAT_TIME)
	if not _skipped:
		_ending()
		await _wait(END_TIME)
	_done = true
	finished.emit()


func _play_beat(e: Dictionary) -> void:
	var src: Combatant = e.src
	var dst: Combatant = e.dst
	var legend := recap.legend
	_round.text = "WAVE %d · ROUND %d" % [int(e.wave) + 1, maxi(1, int(e.round))]
	match String(e.kind):
		"hit":
			_lunge(src, legend)
			_flash(legend, Color(1.8, 1.8, 1.8))
			_number(legend, ("CRIT %d!" if e.crit else "%d") % e.amount, Retro.YELLOW if e.crit else Retro.PINK, 30 if e.crit else 24)
			_caption.text = "%s's %s hits the %s for %d%s" % [_name(src), e.skill, legend.display_name, e.amount, "!" if e.crit else "."]
		"smash":
			_lunge(legend, dst)
			_flash(dst, Color(1.8, 0.5, 0.5))
			_number(dst, "%d" % e.amount, Retro.RED, 26)
			_caption.text = "The %s's %s slams %s for %d." % [legend.display_name, e.skill, _name(dst), e.amount]
		"ko":
			_fall(dst)
			_caption.text = "%s is knocked out%s." % [_name(dst), (" by the " + _name(src)) if src and not src.is_player else ""]
		"phase1":
			_shake(14.0)
			_caption.text = "Worn down, the %s calls the horde for help!" % legend.display_name
		"phase2":
			_shake(20.0)
			_sprites[legend].modulate = Color(1.7, 0.55, 0.5)
			_pop(_sprites[legend], 1.2)
			_caption.text = "The %s is ENRAGED!" % legend.display_name
		"phase3":
			_shake(24.0)
			_caption.text = "At its last 10%%, the %s begins its LAST GASP..." % legend.display_name
		"cataclysm":
			_lunge(legend, null)
			_burn(Color(Retro.RED, 0.5))
			_caption.text = "CATACLYSM! The %s's fury sweeps the whole pack." % legend.display_name
		"interrupt":
			_number(legend, "INTERRUPTED!", Retro.GREEN, 26)
			_caption.text = "The pack stuns the %s mid-Cataclysm!" % legend.display_name
		"gasp":
			_lunge(legend, null)
			_burn(Color(Retro.RED, 0.75))
			_shake(26.0)
			_caption.text = "The LAST GASP tears through the pack!"
		"final":
			_lunge(src, legend)
			_flash(legend, Color(2.5, 2.5, 2.5))
			_fall(legend)
			_caption.text = "%s's %s fells the %s!" % [_name(src), e.skill, legend.display_name] if src else "The %s falls!" % legend.display_name


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
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label
