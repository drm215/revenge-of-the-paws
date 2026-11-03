class_name ZombieGuide
extends Control

## The zombie guide: every zombie type with its stats, moves, what makes it dangerous and its weak
## point, plus general tips. Opens over whatever screen is showing; Close goes back to it.


## Shows the guide over `screen`.
static func open(screen: Control) -> void:
	var guide := ZombieGuide.new()
	guide.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.add_child(guide)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP  # nothing underneath reacts while it's open
	var bg := ColorRect.new()
	bg.color = Retro.INK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	margin.add_theme_constant_override("margin_top", 44)
	add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	margin.add_child(col)
	var title := Retro.title(Label.new(), 20)
	title.text = "Zombie guide"
	col.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	Retro.touch_scroll(scroll)
	col.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 12)
	scroll.add_child(list)

	var tips := PanelContainer.new()
	tips.add_theme_stylebox_override("panel", Retro.box(Retro.NIGHT, Retro.SLATE, Retro.BORDER, 0, 12))
	list.add_child(tips)
	var tip_col := VBoxContainer.new()
	tip_col.add_theme_constant_override("separation", 6)
	tips.add_child(tip_col)
	tip_col.add_child(_label("Good to know", 13, Retro.GOLD, true))
	for tip: String in GameData.ZOMBIE_TIPS:
		tip_col.add_child(_label("• " + tip, 18, Retro.MIST))

	var order: Array = GameData.ZOMBIE_GUIDE.keys()
	order.sort_custom(func(a: String, b: String) -> bool:
		return GameData.ZOMBIE_GUIDE[a].from < GameData.ZOMBIE_GUIDE[b].from)
	for id: String in order:
		list.add_child(_entry(id))

	var close := Button.new()
	close.text = "Close"
	close.custom_minimum_size = Vector2(0, 80)
	close.pressed.connect(queue_free)
	col.add_child(close)


## One zombie: sprite, name, where it shows up, stats, moves, what to watch for, weak point.
func _entry(id: String) -> Control:
	var z: Dictionary = GameData.ZOMBIES[id]
	var guide: Dictionary = GameData.ZOMBIE_GUIDE[id]
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", Retro.box(Retro.NIGHT, Retro.STEEL, Retro.BORDER, 0, 12))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)
	var sprite := TextureRect.new()
	sprite.texture = load("res://art/pixel/%s.png" % id)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	sprite.custom_minimum_size = Vector2(96, 96)
	sprite.flip_h = true  # zombies face left, toward the pack
	sprite.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(sprite)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 4)
	row.add_child(text)
	text.add_child(_label(z.name, 14, Retro.GREEN, true))
	var where := "anywhere" if guide.from <= 1 else "threat %d and up" % guide.from
	var row_text := " · back row" if z.get("row", "front") == "back" else ""
	text.add_child(_label("HP %d · ATK %d · DEF %d · SPD %d  ·  Shows up %s%s" % [z.hp, z.atk, z.def, z.spd, where, row_text], 17, Retro.FOG))
	for skill_id: String in z.skills:
		var s := GameData.skill(skill_id)
		text.add_child(_label("%s: %s" % [s.name, GameData.skill_stats(s)], 18, Retro.CYAN))
	text.add_child(_label(guide.note, 18, Retro.MIST))
	text.add_child(_label("Weak point: " + GameData.weak_text(id), 18, Retro.YELLOW))
	return panel


func _label(text: String, font_size: int, color: Color, is_title := false) -> Label:
	var label := Retro.title(Label.new(), font_size, color) if is_title else Retro.text(Label.new(), font_size, color)
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label
