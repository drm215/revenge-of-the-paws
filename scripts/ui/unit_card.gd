class_name UnitCard
extends PanelContainer

## Tappable unit on the battlefield: sprite on the side facing the enemy, then name, HP and statuses.
## Art: res://art/pixel/<id>.png (8-bit), else res://art/units/<id>.svg; enemies are mirrored to face left.

signal pressed(unit: Combatant)

enum Highlight { NONE, ACTIVE, TARGET }

const LEADER_COLOR := Retro.GOLD
const BOSS_COLOR := Color("f6a0e0")
const RING_COLORS := {
	Highlight.NONE: Color(Retro.INK, 0.6),
	Highlight.ACTIVE: Retro.GOLD,
	Highlight.TARGET: Retro.CYAN,
}
const BORDER_COLORS := {
	Highlight.NONE: Retro.PINE,
	Highlight.ACTIVE: Retro.GOLD,
	Highlight.TARGET: Retro.CYAN,
}
const LUNGE := 26.0

var unit: Combatant

var _style := StyleBoxFlat.new()
var _stage := Control.new()  # holds the sprite; draws the ground ring
var _sprite := TextureRect.new()
var _name_label := Label.new()
var _hp_bar := ProgressBar.new()
var _hp_label := Label.new()
var _status_label := Label.new()
var _ring := Color(0, 0, 0, 0.35)
var _time := 0.0
var _mode := Highlight.NONE


func setup(c: Combatant, sprite_size: float) -> void:
	unit = c
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style.bg_color = Color(Retro.INK, 0.45)
	_style.set_border_width_all(Retro.BORDER)
	_style.set_corner_radius_all(0)
	_style.anti_aliasing = false
	_style.set_content_margin_all(6)
	add_theme_stylebox_override("panel", _style)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)

	_stage.custom_minimum_size = Vector2(sprite_size, sprite_size)
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.draw.connect(_draw_ring)
	_sprite.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_sprite.flip_h = not c.is_player
	_sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 8-bit sprites (tools/pixelate.gd) scaled up with hard pixels; vector art as a fallback.
	var pixel := "res://art/pixel/%s.png" % c.id
	var vector := "res://art/units/%s.svg" % c.id
	if ResourceLoader.exists(pixel):
		_sprite.texture = load(pixel)
		_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	elif ResourceLoader.exists(vector):
		_sprite.texture = load(vector)
	else:
		var block := ColorRect.new()
		block.color = c.color
		block.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		block.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_stage.add_child(block)
	_stage.add_child(_sprite)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	info.add_theme_constant_override("separation", 3)
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Sprites face each other across the middle of the battlefield.
	if c.is_player:
		row.add_child(info)
		row.add_child(_stage)
	else:
		row.add_child(_stage)
		row.add_child(info)

	_name_label.text = c.display_name
	Retro.text(_name_label, 23, Retro.WHITE)
	_name_label.clip_text = true
	_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	info.add_child(_name_label)

	var tag := Label.new()
	Retro.title(tag, 10, Retro.FOG)
	tag.clip_text = true
	tag.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if c.is_boss:
		tag.text = "LEGEND"
		tag.add_theme_color_override("font_color", BOSS_COLOR)
	elif c.is_leader:
		tag.text = "Lv %d Leader" % c.level
		tag.add_theme_color_override("font_color", LEADER_COLOR)
	elif c.is_player:
		tag.text = "Lv %d %s" % [c.level, c.role]
		tag.add_theme_color_override("font_color", Retro.FOG)
	if tag.text != "":
		info.add_child(tag)

	var fill := StyleBoxFlat.new()
	fill.bg_color = Retro.GREEN if c.is_player else Retro.RED
	fill.border_color = Retro.FOREST if c.is_player else Retro.DARK_RED
	fill.border_width_bottom = 4
	var bg := Retro.box(Retro.INK, Retro.INK, 2, 0, 0)
	_hp_bar.add_theme_stylebox_override("fill", fill)
	_hp_bar.add_theme_stylebox_override("background", bg)
	_hp_bar.show_percentage = false
	_hp_bar.custom_minimum_size = Vector2(0, 26)
	_hp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(_hp_bar)
	_hp_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	Retro.text(_hp_label, 18, Retro.WHITE)
	_hp_label.add_theme_color_override("font_outline_color", Retro.INK)
	_hp_label.add_theme_constant_override("outline_size", 4)
	_hp_bar.add_child(_hp_label)

	Retro.text(_status_label, 18, Retro.YELLOW)
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(_status_label)

	set_highlight(Highlight.NONE)
	refresh()


func _process(delta: float) -> void:
	if _mode == Highlight.TARGET:
		_time += delta
		_style.border_color = BORDER_COLORS[Highlight.TARGET].lerp(Color.WHITE, 0.35 + 0.35 * sin(_time * 6.0))
		_stage.queue_redraw()


func refresh() -> void:
	_hp_bar.max_value = unit.max_hp
	_hp_bar.value = unit.hp
	_hp_label.text = "%d / %d" % [unit.hp, unit.max_hp]
	# Lineup notes: problems by name, bonuses as a count (the battle log spells them out).
	var parts: PackedStringArray = []
	var perks := 0
	for note in unit.notes:
		if note.begins_with("Injured") or note.begins_with("Tired"):
			parts.append(note)
		else:
			perks += 1
	if perks > 0:
		parts.append("+%d perk%s" % [perks, "" if perks == 1 else "s"])
	for status in unit.statuses:
		parts.append("%s %d" % [GameData.STATUSES[status].name, unit.statuses[status]])
	_status_label.text = " · ".join(parts)
	_status_label.visible = not parts.is_empty()
	modulate = _rest_modulate()


func set_highlight(mode: Highlight) -> void:
	_mode = mode
	_style.border_color = BORDER_COLORS[mode]
	_ring = RING_COLORS[mode]
	if mode == Highlight.NONE and unit.is_leader:
		_ring = LEADER_COLOR.darkened(0.4)
	elif mode == Highlight.NONE and unit.is_boss:
		_ring = BOSS_COLOR.darkened(0.4)
	_stage.queue_redraw()


func flash(color: Color) -> void:
	var tween := create_tween()
	tween.tween_property(self, "modulate", color, 0.08)
	tween.tween_property(self, "modulate", _rest_modulate(), 0.25)


## Quick hop toward the other side when this unit acts.
func lunge() -> void:
	var dir := LUNGE if unit.is_player else -LUNGE
	var tween := create_tween()
	tween.tween_property(_sprite, "position:x", dir, 0.12).set_ease(Tween.EASE_OUT)
	tween.tween_property(_sprite, "position:x", 0.0, 0.18).set_ease(Tween.EASE_IN)


func _draw_ring() -> void:
	# A stepped "pixel" ellipse: stacked bars snapped to a 4px grid.
	var s := _stage.size
	var center := Vector2(s.x / 2.0, s.y * 0.92)
	var rx := s.x * 0.42
	var ry := rx * 0.28
	var step := 4.0
	var y := -ry
	while y < ry:
		var half := snappedf(rx * sqrt(maxf(0.0, 1.0 - pow((y + step / 2.0) / ry, 2.0))), step)
		if half > 0.0:
			_stage.draw_rect(Rect2(center + Vector2(-half, y), Vector2(half * 2.0, step)), _ring)
		y += step


func _rest_modulate() -> Color:
	return Color.WHITE if unit.is_alive() else Color(1, 1, 1, 0.3)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pressed.emit(unit)
		accept_event()
