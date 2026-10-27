class_name TechTreeScreen
extends Control

## An animal's tech tree: Training (stats any time), three branches (Fang, Hide, Instinct) and a
## level-gated signature row.
## Tap a bright node to spend a point; Reset refunds everything for free. With several animals to
## look at (after a battle), tabs switch between them.

signal done

var profile: Profile
var units: Array[String] = []

var _current := ""
var _tabs := HBoxContainer.new()
var _content := VBoxContainer.new()


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Retro.INK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	margin.add_theme_constant_override("margin_top", 36)
	add_child(margin)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	margin.add_child(outer)

	_tabs.add_theme_constant_override("separation", 6)
	outer.add_child(_tabs)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	Retro.touch_scroll(scroll)
	outer.add_child(scroll)
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 8)
	scroll.add_child(_content)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	outer.add_child(buttons)
	var reset := Button.new()
	reset.text = "Reset (free)"
	reset.custom_minimum_size = Vector2(0, 76)
	reset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reset.pressed.connect(func() -> void:
		profile.reset_tree(_current)
		_show(_current))
	buttons.add_child(reset)
	var finish := Button.new()
	finish.text = "Done"
	finish.custom_minimum_size = Vector2(0, 76)
	finish.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	finish.pressed.connect(done.emit)
	buttons.add_child(finish)

	if units.is_empty():
		done.emit.call_deferred()
		return
	_show(units[0])


func _show(unit_id: String) -> void:
	_current = unit_id
	_build_tabs()
	for child in _content.get_children():
		child.queue_free()
	var unit := profile.build_unit(unit_id)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	_content.add_child(head)
	var sprite := TextureRect.new()
	sprite.custom_minimum_size = Vector2(110, 110)
	sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var path := "res://art/pixel/%s.png" % unit_id
	if ResourceLoader.exists(path):
		sprite.texture = load(path)
	head.add_child(sprite)
	var titles := VBoxContainer.new()
	titles.alignment = BoxContainer.ALIGNMENT_CENTER
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(titles)
	var title := Retro.title(Label.new(), 16)
	title.text = "%s · Lv %d" % [unit.display_name, unit.level]
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	titles.add_child(title)
	var points := Retro.title(Label.new(), 12, Retro.YELLOW if profile.points_left(unit_id) > 0 else Retro.FOG)
	points.text = "%d point%s to spend" % [profile.points_left(unit_id), "" if profile.points_left(unit_id) == 1 else "s"]
	titles.add_child(points)
	var stats := Retro.text(Label.new(), 18)
	stats.text = "HP %d · ATK %d · DEF %d · SPD %d · Crit %d%%" % [unit.max_hp, unit.atk, unit.def, unit.spd, roundi(unit.crit * 100)]
	stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	titles.add_child(stats)

	var tree := GameData.tech_tree(unit_id)
	var train_head := Retro.title(Label.new(), 12, Retro.GOLD)
	train_head.text = "Training"
	_content.add_child(train_head)
	var training := GridContainer.new()
	training.columns = 3
	training.add_theme_constant_override("h_separation", 6)
	training.add_theme_constant_override("v_separation", 6)
	_content.add_child(training)
	for stat in GameData.TRAINING_LIMITS:
		training.add_child(_training_card(unit_id, stat))

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 8)
	_content.add_child(columns)
	for branch: Dictionary in GameData.TREE_BRANCHES:
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", 0)
		columns.add_child(col)
		var name_label := Retro.title(Label.new(), 12, Retro.GOLD)
		name_label.text = branch.name
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(name_label)
		var focus := Retro.text(Label.new(), 16, Retro.FOG)
		focus.text = unit.skill_data(GameData.ANIMALS.get(unit_id, GameData.PETS.get(unit_id, {})).skills[branch.skill]).name
		focus.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		focus.clip_text = true
		col.add_child(focus)
		var prev := ""
		for node in tree:
			if node.branch != branch.id:
				continue
			if prev != "":
				col.add_child(_connector(profile.owns(unit_id, prev) and profile.owns(unit_id, node.id)))
			col.add_child(_node(unit_id, node))
			prev = node.id

	var sig_head := Retro.title(Label.new(), 12, Retro.GOLD)
	sig_head.text = "Signature"
	_content.add_child(sig_head)
	var sig_row := HBoxContainer.new()
	sig_row.add_theme_constant_override("separation", 6)
	_content.add_child(sig_row)
	for node in tree:
		if node.branch == "signature":
			var cell := _node(unit_id, node)
			cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			sig_row.add_child(cell)

	var help := Retro.text(Label.new(), 17, Retro.STEEL)
	help.text = "One point per level. Training can be bought any time; in a branch each node needs the one above it; the signature skill unlocks at Lv %d and Mastery at Lv %d. Reset is free." % [GameData.SIGNATURE_LEVEL, GameData.MASTERY_LEVEL]
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(help)


func _build_tabs() -> void:
	for child in _tabs.get_children():
		child.queue_free()
	_tabs.visible = units.size() > 1
	for id in units:
		var tab := Button.new()
		tab.toggle_mode = true
		tab.button_pressed = id == _current
		tab.text = profile.unit_name(id) + (" (%d)" % profile.points_left(id) if profile.points_left(id) > 0 else "")
		tab.add_theme_font_size_override("font_size", Retro.px(9))
		tab.clip_text = true
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.pressed.connect(_show.bind(id))
		_tabs.add_child(tab)


## One node card: owned (gold), available to buy (cyan, tap it), or locked (dim, with the reason).
func _node(unit_id: String, node: Dictionary) -> PanelContainer:
	var block := profile.tree_block(unit_id, node.id)
	var owned := block == "Owned"
	var open := block == ""
	var card := PanelContainer.new()
	var bg := Retro.DIRT if owned else (Retro.NIGHT if open else Retro.INK)
	var border := Retro.GOLD if owned else (Retro.CYAN if open else Retro.SLATE)
	card.add_theme_stylebox_override("panel", Retro.box(bg, border, 3, 0, 8))
	if not owned and not open:
		card.modulate = Color(1, 1, 1, 0.6)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(box)
	var title := Retro.text(Label.new(), 18, Retro.GOLD if owned else Retro.WHITE)
	title.text = node.title
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(title)
	var detail_text: String = node.get("detail", "")
	if node.kind == "signature":
		detail_text = GameData.skill(node.skill).desc
	var state := Retro.text(Label.new(), 15, Retro.CYAN if open else (Retro.GOLD if owned else Retro.FOG))
	state.text = ("Tap to learn" if open else block) + (("\n" + detail_text) if detail_text != "" else "")
	state.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(state)
	if open:
		Retro.on_tap(card, func() -> void:
			profile.buy_node(unit_id, node.id)
			_show(unit_id))
	return card


## A repeatable stat: shows how many are bought and buys the next one on tap.
func _training_card(unit_id: String, stat: String) -> PanelContainer:
	var limit: int = GameData.TRAINING_LIMITS[stat]
	var bought := 0
	for k in limit:
		if profile.owns(unit_id, "train_%s%d" % [stat, k + 1]):
			bought += 1
	var next_id := "train_%s%d" % [stat, bought + 1]
	var block := "Maxed" if bought >= limit else profile.tree_block(unit_id, next_id)
	var open := block == ""
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", Retro.box(Retro.NIGHT if open else Retro.INK,
		Retro.CYAN if open else (Retro.GOLD if bought > 0 else Retro.SLATE), 3, 0, 8))
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(box)
	var title := Retro.text(Label.new(), 18, Retro.WHITE)
	title.text = GameData.STAT_LABELS[stat]
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(title)
	var count := Retro.text(Label.new(), 15, Retro.GOLD if bought > 0 else Retro.FOG)
	count.text = "%d / %d" % [bought, limit]
	box.add_child(count)
	var state := Retro.text(Label.new(), 15, Retro.CYAN if open else Retro.FOG)
	state.text = "Tap to train" if open else block
	box.add_child(state)
	if open:
		Retro.on_tap(card, func() -> void:
			profile.buy_node(unit_id, next_id)
			_show(unit_id))
	return card


func _connector(lit: bool) -> Control:
	var holder := CenterContainer.new()
	var line := ColorRect.new()
	line.custom_minimum_size = Vector2(6, 12)
	line.color = Retro.GOLD if lit else Retro.SLATE
	holder.add_child(line)
	return holder
