class_name LegendCutscene
extends Control

## A legend's cut scenes (story in LegendStory). The entrance: the screen goes black, the legend's
## weather rolls in, the place and its tale are told, footfalls shake the ground, and lightning shows
## the legend with its name. A chapter (at 66% and 33% of its HP): the fight pauses under a dark
## veil, the legend looms in close, and the next part of its story is told before what it does now.
## Real time throughout (slow motion doesn't drag it out); a tap skips to the end.

signal finished

const TYPE_SPEED := 0.024  # seconds per letter of the story
const LETTERBOX := 96.0

var legend: Combatant
var place := ""
var chapter := 0  # 0: the entrance; 1 and 2: the chapters at 66% and 33%

var _weather := "storm"
var _drops: Array[Dictionary] = []  # {pos, speed, size, drift, phase}
var _bolt := 0.0  # lightning: 1 at the strike, fading
var _bolt_path: PackedVector2Array = []
var _next_bolt := 0.0
var _clock := 0.0
var _skipped := false
var _veil := ColorRect.new()
var _portrait: TextureRect
var _fx_layer := Control.new()  # the words and the legend, above the weather


## Plays the entrance over `screen`; returns once it's over or skipped.
static func play_entrance(screen: Control, who: Combatant, where: String) -> void:
	var scene := _make(screen, who)
	scene.place = where
	await scene.finished
	scene.queue_free()


## Plays chapter `index` (1 at 66% HP, 2 at 33%) over `screen`.
static func play_chapter(screen: Control, who: Combatant, index: int) -> void:
	var scene := _make(screen, who)
	scene.chapter = index
	await scene.finished
	scene.queue_free()


static func _make(screen: Control, who: Combatant) -> LegendCutscene:
	var scene := LegendCutscene.new()
	scene.legend = who
	scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scene.z_index = 30
	screen.add_child(scene)
	return scene


## This legend's story.
func story() -> Dictionary:
	return LegendStory.of(legend.id)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	process_mode = Node.PROCESS_MODE_ALWAYS
	_weather = String(story().get("weather", "storm"))
	_veil.color = Color(0, 0, 0, 0)
	_veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_veil.show_behind_parent = true
	add_child(_veil)
	_fx_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fx_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx_layer.z_index = 2
	add_child(_fx_layer)
	_run.call_deferred()


func _gui_input(event: InputEvent) -> void:
	if (event is InputEventMouseButton or event is InputEventScreenTouch) and event.pressed:
		_skipped = true
		accept_event()


func _run() -> void:
	_seed_weather()
	if chapter == 0:
		await _entrance()
	else:
		await _chapter()
	if is_inside_tree():
		var out := _tween()
		out.tween_property(self, "modulate:a", 0.0, 0.18 if _skipped else 0.4)
		await out.finished
	finished.emit()


# --- The entrance --------------------------------------------------------------------------------

func _entrance() -> void:
	var sound := get_node_or_null("/root/Sound")
	if sound:
		sound.music("")
	_tween().tween_property(_veil, "color:a", 1.0, 0.5)
	_bars()
	_skip_hint()
	await _wait(0.6)
	var where := _label(place.to_upper() if place != "" else "SOMEWHERE IN THE DARK", 16, Retro.GOLD, true)
	where.position = Vector2(30, LETTERBOX + 40)
	where.size = Vector2(size.x - 60, 0)
	where.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fade_in(where, 0.6)
	_bolt_soon(0.4)
	await _wait(0.7)
	var tale := _label(String(story().intro), 23, Retro.MIST, false)
	tale.position = Vector2(36, LETTERBOX + 90)
	tale.size = Vector2(size.x - 72, 0)
	tale.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	await _type(tale)
	await _wait(1.0)
	for k in 2:
		_sound("thud")
		_shake(8.0 + k * 8.0)
		await _wait(0.55)
	# Lightning, and there it is.
	_strike()
	_sound("roar")
	_shake(22.0)
	_portrait = _legend_art(Vector2(size.x * 0.12, size.y * 0.36), minf(size.x * 0.76, 520.0))
	if _portrait:
		_portrait.scale = Vector2.ONE * 0.6
		_portrait.modulate = Color(3, 3, 3)
		var t := _tween().set_parallel()
		t.tween_property(_portrait, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.tween_property(_portrait, "modulate", Color(1.5, 1.5, 1.5), 0.6)
	var title := _label(legend.display_name.to_upper(), 34, Retro.RED, true)
	title.position = Vector2(20, size.y * 0.75)
	title.size = Vector2(size.x - 40, 0)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.pivot_offset = Vector2(title.size.x / 2.0, 24)
	title.scale = Vector2.ONE * 1.8
	_tween().tween_property(title, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var epithet := _label(String(GameData.LEGENDS.get(legend.id, {}).get("lore", "")), 20, Retro.FOG, false)
	epithet.position = Vector2(30, size.y * 0.75 + 56)
	epithet.size = Vector2(size.x - 60, 0)
	epithet.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fade_in(epithet, 0.5)
	await _wait(2.6)


# --- A chapter -----------------------------------------------------------------------------------

func _chapter() -> void:
	_sound("thunder", 0.05, -4.0)
	_tween().tween_property(_veil, "color:a", 0.9, 0.35)
	_bars()
	_skip_hint()
	var heading := _label("CHAPTER %s" % ["II", "III"][clampi(chapter - 1, 0, 1)], 16, Retro.GOLD, true)
	heading.position = Vector2(30, LETTERBOX + 40)
	heading.size = Vector2(size.x - 60, 0)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fade_in(heading, 0.4)
	# The legend looms in close, and creeps closer while its story is told.
	var side := minf(size.x * 0.9, 620.0)
	_portrait = _legend_art(Vector2((size.x - side) / 2.0, size.y * 0.3), side)
	if _portrait:
		_portrait.modulate = Color(1.3, 1.3, 1.3, 0.0) if chapter == 1 else Color(1.9, 0.6, 0.55, 0.0)
		var t := _tween().set_parallel()
		t.tween_property(_portrait, "modulate:a", 1.0, 0.5)
		t.tween_property(_portrait, "scale", Vector2.ONE * 1.12, 6.0).from(Vector2.ONE * 0.94)
	var chapters: Array = story().chapters
	var tale := _label(String(chapters[clampi(chapter - 1, 0, chapters.size() - 1)]), 23, Retro.MIST, false)
	tale.position = Vector2(36, LETTERBOX + 86)
	tale.size = Vector2(size.x - 72, 0)
	tale.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	await _wait(0.4)
	await _type(tale)
	await _wait(1.1)
	# What it does now.
	_strike()
	_sound("roar", 0.06)
	_shake(18.0 if chapter == 1 else 26.0)
	var now := _label(what_now(), 26, Retro.PINK if chapter == 1 else Retro.RED, true)
	now.position = Vector2(20, size.y * 0.8)
	now.size = Vector2(size.x - 40, 0)
	now.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	now.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	now.pivot_offset = Vector2(now.size.x / 2.0, 20)
	now.scale = Vector2.ONE * 1.6
	_tween().tween_property(now, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if _portrait and chapter == 2:
		_tween().tween_property(_portrait, "modulate", Color(2.4, 0.5, 0.45), 0.2)
	await _wait(1.6)


## The line that says what the legend does at this chapter.
func what_now() -> String:
	if chapter == 1:
		return "IT CALLS THE HORDE FOR HELP!"
	return "ENRAGED! IT HITS %d%% HARDER!" % roundi((GameData.LEGEND_ENRAGE_ATK - 1.0) * 100)


# --- Weather -------------------------------------------------------------------------------------

func _seed_weather() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(legend.id)
	var count: int = {"storm": 140, "snow": 110, "fog": 14, "swamp": 40, "dust": 90, "embers": 70, "sky": 60}.get(_weather, 100)
	for k in count:
		_drops.append({"pos": Vector2(rng.randf() * size.x, rng.randf() * size.y), "speed": rng.randf_range(0.6, 1.4),
			"size": rng.randf_range(0.6, 1.4), "drift": rng.randf_range(-1.0, 1.0), "phase": rng.randf() * TAU})
	if _weather == "storm":
		_next_bolt = 0.8


func _process(delta: float) -> void:
	_clock += delta
	var w := size.x
	var h := size.y
	for d in _drops:
		var p: Vector2 = d.pos
		var s: float = d.speed
		match _weather:
			"storm":
				p += Vector2(-160, 1500) * s * delta
			"snow":
				p += Vector2(28 * sin(_clock + d.phase) + 20, 90) * s * delta
			"fog":
				p += Vector2(22 * s, 0) * delta
			"swamp":
				p += Vector2(sin(_clock * 0.9 + d.phase) * 22, cos(_clock * 0.7 + d.phase) * 16) * delta
			"dust":
				p += Vector2(700, 60 * d.drift) * s * delta
			"embers":
				p += Vector2(sin(_clock * 2.0 + d.phase) * 30, -120) * s * delta
			"sky":
				p += Vector2(-500, 700) * s * delta
		if p.y > h + 40:
			p = Vector2(randf() * (w + 200), -30)
		elif p.y < -40:
			p = Vector2(randf() * w, h + 30)
		if p.x > w + 260:
			p.x = -250
		elif p.x < -260:
			p.x = w + 250
		d.pos = p
	if _weather == "storm" and _clock >= _next_bolt and not _skipped:
		_strike(false)
		_next_bolt = _clock + randf_range(2.0, 3.5)
	_bolt = maxf(0.0, _bolt - delta * 3.0)
	queue_redraw()


func _draw() -> void:
	var a := clampf(_veil.color.a * 1.2, 0.0, 1.0)  # the weather comes in with the dark
	for d in _drops:
		var p: Vector2 = d.pos
		var s: float = d.size
		match _weather:
			"storm":
				draw_line(p, p + Vector2(-5, 34) * s, Color(0.6, 0.7, 0.9, 0.45 * a), 2.0)
			"snow":
				draw_circle(p, 3.0 * s, Color(1, 1, 1, 0.8 * a))
			"fog":
				draw_circle(p, 140.0 * s, Color(0.6, 0.66, 0.75, 0.05 * a))
			"swamp":
				var glow := 0.5 + 0.5 * sin(_clock * 3.0 + d.phase)
				draw_circle(p, 4.0 * s, Color(0.8, 1.0, 0.4, glow * 0.85 * a))
				draw_circle(p, 12.0 * s, Color(0.8, 1.0, 0.4, glow * 0.12 * a))
			"dust":
				draw_line(p, p + Vector2(26, 1) * s, Color(0.85, 0.7, 0.5, 0.35 * a), 2.0)
			"embers":
				draw_circle(p, 2.6 * s, Color(1.0, 0.55 + 0.3 * sin(_clock * 6.0 + d.phase), 0.15, 0.9 * a))
			"sky":
				draw_line(p, p + Vector2(18, -26) * s, Color(0.9, 0.95, 1.0, 0.5 * a), 1.5)
	if _weather == "swamp" or _weather == "fog":
		draw_rect(Rect2(0, size.y * 0.62, size.x, size.y * 0.38), Color(0.5, 0.6, 0.6, 0.08 * a))
	if _bolt > 0.0:
		if _bolt_path.size() > 1:
			draw_polyline(_bolt_path, Color(0.95, 0.95, 1.0, _bolt), 5.0)
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.85, 0.9, 1.0, _bolt * 0.45))


## A lightning strike: a jagged bolt from the top, a flash, and thunder.
func _strike(loud := true) -> void:
	_bolt = 1.0
	_bolt_path = PackedVector2Array()
	var x := randf_range(size.x * 0.15, size.x * 0.85)
	var y := 0.0
	while y < size.y * 0.55:
		_bolt_path.append(Vector2(x, y))
		x += randf_range(-40, 40)
		y += randf_range(30, 70)
	_sound("thunder", 0.08, 0.0 if loud else -6.0)


func _bolt_soon(seconds: float) -> void:
	if _weather == "storm":
		_next_bolt = _clock + seconds


# --- Bits ----------------------------------------------------------------------------------------

func _bars() -> void:
	for top in [true, false]:
		var bar := ColorRect.new()
		bar.color = Color.BLACK
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE if top else Control.PRESET_BOTTOM_WIDE)
		if top:
			bar.offset_bottom = LETTERBOX
		else:
			bar.offset_top = -LETTERBOX
		bar.z_index = 3
		add_child(bar)


func _skip_hint() -> void:
	var hint := _label("Tap to skip", 14, Retro.FOG, true)
	hint.z_index = 4
	hint.position = Vector2(size.x - 230, size.y - LETTERBOX + 34)
	hint.size = Vector2(206, 0)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT


func _legend_art(at: Vector2, side: float) -> TextureRect:
	var path := "res://art/pixel/%s.png" % legend.id
	if not ResourceLoader.exists(path):
		return null
	var art := TextureRect.new()
	art.texture = load(path)
	art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.flip_h = true
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.position = at
	art.size = Vector2(side, side)
	art.pivot_offset = art.size / 2.0
	_fx_layer.add_child(art)
	return art


func _label(text: String, font_size: int, color: Color, is_title: bool) -> Label:
	var label := Retro.title(Label.new(), font_size, color) if is_title else Retro.text(Label.new(), font_size, color)
	if not is_title:
		label.add_theme_font_override("font", Retro.pixel_font())  # the tale in pixels too, to match the titles
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_outline_color", Retro.INK)
	label.add_theme_constant_override("outline_size", 8)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.z_index = 4
	_fx_layer.add_child(label)
	return label


## Types `label`'s text out letter by letter (all at once if skipped).
func _type(label: Label) -> void:
	label.visible_ratio = 0.0
	var t := _tween()
	t.tween_property(label, "visible_ratio", 1.0, label.text.length() * TYPE_SPEED)
	while t.is_running() and not _skipped and is_inside_tree():
		await get_tree().process_frame
	label.visible_ratio = 1.0


func _fade_in(node: CanvasItem, seconds: float) -> void:
	node.modulate.a = 0.0
	_tween().tween_property(node, "modulate:a", 1.0, seconds)


func _shake(amount: float) -> void:
	var t := _tween()
	for k in 6:
		t.tween_property(_fx_layer, "position", Vector2(randf_range(-amount, amount), randf_range(-amount, amount)), 0.04)
	t.tween_property(_fx_layer, "position", Vector2.ZERO, 0.05)


func _sound(sound_name: String, vary := 0.0, volume_db := 0.0) -> void:
	if _skipped:
		return
	var sound := get_node_or_null("/root/Sound")
	if sound:
		sound.play(sound_name, vary, volume_db)


func _tween() -> Tween:
	return create_tween().set_ignore_time_scale(true)


## Waits `seconds` of real time; a tap cuts it short.
func _wait(seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < until and not _skipped and is_inside_tree():
		await get_tree().process_frame
