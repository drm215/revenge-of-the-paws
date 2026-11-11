class_name Prologue
extends Control

## The game's backstory in four short cards: the legends hid, made a pact and loosed the horde, but
## never watched the animals, who now hunt them in packs. Plays over setup the first time a new game
## is started on this device (seen()); the Guide's Story button plays it again. A tap finishes the
## line being typed, or moves on; Skip ends it.

signal finished

const SEEN_PATH := "user://seen.cfg"
const TYPE_SPEED := 0.03  # seconds per letter
const CARDS := [
	{"art": ["mothman", "bigfoot", "jersey_devil"], "flip": true, "sky": Color("1b1f3a"), "sound": "thunder",
		"text": "The legends were real. For centuries they hid in the hollows and the swamps, while people paved over their homes and laughed at their stories."},
	{"art": ["shambler", "runner", "brute"], "flip": true, "sky": Color("3a1418"), "sound": "groan",
		"text": "So the legends made a pact. They raised the dead and sent the horde across the land. In one season, humanity fell."},
	{"art": ["dog", "cat", "horned_owl"], "flip": false, "sky": Color("2a2140"), "sound": "bark",
		"text": "But the legends only ever watched the people. They never watched the dog on the porch, the cat in the alley, or the owl on the wire."},
	{"art": ["red_fox", "black_bear", "raccoon"], "flip": false, "sky": Color("3e2731"), "sound": "roar",
		"text": "Now the animals hunt in packs. And they're coming for the legends.", "title": "REVENGE OF THE PAWS"},
]

var index := -1  # the card showing
var _bg := ColorRect.new()
var _stage: VBoxContainer
var _line: Label
var _typing: Tween
var _hint: Label
var _done := false
var _ash: Array[Vector3] = []  # x, y, speed: grey ash drifting down


## Whether this device has seen the story.
static func seen() -> bool:
	var cfg := ConfigFile.new()
	return cfg.load(SEEN_PATH) == OK and bool(cfg.get_value("story", "prologue", false))


static func _mark_seen() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SEEN_PATH)
	cfg.set_value("story", "prologue", true)
	cfg.save(SEEN_PATH)


## Plays the story over `screen`.
static func play(screen: Control) -> Prologue:
	var scene := Prologue.new()
	scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scene.z_index = 40
	screen.add_child(scene)
	return scene


func _ready() -> void:
	_mark_seen()  # once started, it's seen: a reload never makes anyone sit through it again
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	_bg.color = Color.BLACK
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg.show_behind_parent = true
	add_child(_bg)
	for k in 50:
		_ash.append(Vector3(randf(), randf(), randf_range(0.02, 0.06)))

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 36)
	margin.add_theme_constant_override("margin_top", 120)
	margin.add_theme_constant_override("margin_bottom", 140)
	add_child(margin)
	_stage = VBoxContainer.new()
	_stage.alignment = BoxContainer.ALIGNMENT_CENTER
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_theme_constant_override("separation", 36)
	margin.add_child(_stage)

	var skip := Button.new()
	skip.text = "Skip"
	skip.custom_minimum_size = Vector2(140, 60)
	skip.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	skip.position = Vector2(-160, 40)
	skip.pressed.connect(_finish)
	add_child(skip)
	_hint = Retro.title(Label.new(), 13, Retro.FOG)
	_hint.text = "Tap to continue"
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_hint.offset_top = -90
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hint)
	_next()


func _gui_input(event: InputEvent) -> void:
	if (event is InputEventMouseButton or event is InputEventScreenTouch) and event.pressed:
		accept_event()
		tap()


## A tap: finishes the line being typed, or moves to the next card (or ends after the last).
func tap() -> void:
	if _typing and _typing.is_running():
		_typing.kill()
		_line.visible_ratio = 1.0
		return
	_next()


## The text on the card showing (with its title, if any).
func card_text() -> String:
	var card: Dictionary = CARDS[clampi(index, 0, CARDS.size() - 1)]
	return (String(card.title) + "\n" if card.has("title") else "") + String(card.text)


func _next() -> void:
	if index + 1 >= CARDS.size():
		_finish()
		return
	index += 1
	var card: Dictionary = CARDS[index]
	for child in _stage.get_children():
		child.queue_free()
	create_tween().tween_property(_bg, "color", card.sky, 0.6)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(row)
	var side := minf((size.x - 96) / 3.0, 180.0)
	for k in card.art.size():
		var path := "res://art/pixel/%s.png" % card.art[k]
		if not ResourceLoader.exists(path):
			continue
		var art := TextureRect.new()
		art.texture = load(path)
		art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.flip_h = card.flip
		art.custom_minimum_size = Vector2(side, side)
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art.modulate.a = 0.0
		row.add_child(art)
		create_tween().tween_property(art, "modulate:a", 1.0, 0.5).set_delay(0.15 * k)
	if card.has("title"):
		var title := Retro.title(Label.new(), 30, Retro.GOLD)
		title.text = card.title
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		title.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_stage.add_child(title)
		title.modulate.a = 0.0
		create_tween().tween_property(title, "modulate:a", 1.0, 0.8).set_delay(0.4)
	_line = Retro.text(Label.new(), 24, Retro.MIST)
	_line.add_theme_font_override("font", Retro.pixel_font())
	_line.text = card.text
	_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_line.visible_ratio = 0.0
	_stage.add_child(_line)
	_typing = create_tween()
	_typing.tween_property(_line, "visible_ratio", 1.0, _line.text.length() * TYPE_SPEED).set_delay(0.4)
	_hint.text = "Tap to begin" if index == CARDS.size() - 1 else "Tap to continue"
	var sound := get_node_or_null("/root/Sound")
	if sound:
		sound.play(card.sound, 0.05, -4.0)


func _finish() -> void:
	if _done:
		return
	_done = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var out := create_tween()
	out.tween_property(self, "modulate:a", 0.0, 0.4)
	await out.finished
	finished.emit()
	queue_free()


func _process(delta: float) -> void:
	for k in _ash.size():
		var a := _ash[k]
		a.y += a.z * delta
		a.x += sin(a.y * 9.0 + k) * 0.01 * delta
		if a.y > 1.02:
			a = Vector3(randf(), -0.02, a.z)
		_ash[k] = a
	queue_redraw()


func _draw() -> void:
	for a in _ash:
		draw_circle(Vector2(a.x * size.x, a.y * size.y), 2.0 + a.z * 30.0, Color(0.75, 0.75, 0.8, 0.25))
