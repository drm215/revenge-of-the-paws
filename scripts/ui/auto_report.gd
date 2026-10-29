class_name AutoReport
extends Control

## What auto mode just did on its own: one line per fight, then back to the map (or turn it off).

signal closed
signal stop_requested

var lines: PackedStringArray = []


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Retro.INK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	margin.add_theme_constant_override("margin_top", 48)
	add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	margin.add_child(col)

	var title := Retro.title(Label.new(), 20)
	title.text = "Auto battles"
	col.add_child(title)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	Retro.touch_scroll(scroll)
	col.add_child(scroll)
	var body := Retro.text(Label.new(), 20)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.text = "\n\n".join(lines)
	scroll.add_child(body)

	for choice in [["Back to map", closed], ["Turn auto off", stop_requested]]:
		var b := Button.new()
		b.text = choice[0]
		b.custom_minimum_size = Vector2(0, 76)
		b.pressed.connect((choice[1] as Signal).emit)
		col.add_child(b)
