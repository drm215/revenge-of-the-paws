class_name BonusScreen
extends Control

## A cleared state's or region's bonus: what it is, and which of this player's critters gets it.

signal closed

var profile: Profile
var key := ""  # "state:VA" or "region:us_appalachia"

var _content := VBoxContainer.new()


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
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	Retro.touch_scroll(scroll)
	col.add_child(scroll)
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 12)
	scroll.add_child(_content)
	var later := Button.new()
	later.text = "Decide later"
	later.custom_minimum_size = Vector2(0, 84)
	later.pressed.connect(closed.emit)
	col.add_child(later)

	var bonus := profile.bonus_offer(key)
	var place := GameData.cleared_name(key)
	_label("%s CLEARED!" % place.to_upper(), 20, Retro.GOLD, true)
	_label("Every ZIP area in %s is free of the dead. For that, one of your critters gets this, for good:" % place, 20, Retro.MIST)
	var reward := _label(GameData.bonus_text(bonus), 30, Retro.YELLOW, true)
	reward.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label("Pick who gets it. Teammates each choose their own.", 19, Retro.FOG)
	var everyone: Array[String] = []
	for id in profile.pack_ids() + profile.active() + profile.stable:
		if id not in everyone:
			everyone.append(id)
	for id in everyone:
		var b := Button.new()
		b.text = "%s · Lv %d · %s" % [profile.unit_name(id), profile.level_of(id), _stat_now(id, String(bonus.stat))]
		b.custom_minimum_size = Vector2(0, 76)
		b.clip_text = true
		b.pressed.connect(_give.bind(id))
		_content.add_child(b)


## The stat this bonus raises, as the critter has it now: "ATK 24", "crit 15%".
func _stat_now(id: String, stat: String) -> String:
	var unit := profile.build_unit(id)
	match stat:
		"hp":
			return "HP %d" % unit.max_hp
		"atk":
			return "ATK %d" % unit.atk
		"def":
			return "DEF %d" % unit.def
		"spd":
			return "SPD %d" % unit.spd
	return "crit %d%%" % roundi(unit.crit * 100)


func _give(id: String) -> void:
	var bonus := profile.bonus_offer(key)
	profile.take_bonus(key, id)
	var sound := get_node_or_null("/root/Sound")
	if sound:
		sound.play("loot")
	for child in _content.get_children():
		child.queue_free()
	_label("%s gains %s, for good." % [profile.unit_name(id), GameData.bonus_text(bonus)], 20, Retro.GREEN, true)
	var done := Button.new()
	done.text = "Back to map"
	done.custom_minimum_size = Vector2(0, 84)
	done.pressed.connect(closed.emit)
	_content.add_child(done)


func _label(text: String, font_size: int, color: Color, is_title := false) -> Label:
	var label := Retro.title(Label.new(), font_size, color) if is_title else Retro.text(Label.new(), font_size, color)
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(label)
	return label
