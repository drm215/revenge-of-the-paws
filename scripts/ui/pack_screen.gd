class_name PackScreen
extends Control

## Swap animals in and out of the team and choose their trinkets. Shows every unlocked animal
## with its level and battle-ready stats. The pet always leads; it can only be changed from Setup.
## With `battle_config` set it's the pre-battle screen: it shows the fight ahead, flags who suits
## it, and ends with Fight! (or Back to the map).

signal closed
signal fight

var profile: Profile
## Campaign.battle_config() / patrol_config() for the fight about to start; empty outside battle prep.
var battle_config := {}

var _list := VBoxContainer.new()
var _count := Label.new()
var _done := Button.new()
var _bonds := Label.new()
var _roster := HBoxContainer.new()  # "Your pack" strip: who is picked right now


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Retro.INK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	margin.add_theme_constant_override("margin_top", 40)
	add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	margin.add_child(col)

	var prep := not battle_config.is_empty()
	var title := Retro.title(Label.new(), 20 if prep else 22)
	title.text = "Ready the pack" if prep else "Your Pack"
	col.add_child(title)
	var intro := Retro.text(Label.new(), 21 if prep else 22)
	intro.text = _fight_summary() if prep else "Pick %d to fight%s. Rotate: injured and tired animals fight worse, the bench earns a quarter of the XP, and benched animals can scout, forage or guard." % [
		profile.locals_needed(), (" beside " + profile.pet_name) if profile.has_pet() else ""]
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(intro)
	_roster.add_theme_constant_override("separation", 8)
	col.add_child(_roster)
	Retro.text(_bonds, 20, Retro.GOLD)
	_bonds.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_bonds)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	Retro.touch_scroll(scroll)
	col.add_child(scroll)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 8)
	scroll.add_child(_list)

	Retro.title(_count, 12, Retro.GOLD)
	col.add_child(_count)
	_done.text = "Fight!" if prep else "Done"
	_done.custom_minimum_size = Vector2(0, 84)
	_done.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_done.pressed.connect(fight.emit if prep else closed.emit)
	if prep:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		col.add_child(row)
		var back := Button.new()
		back.text = "Back"
		back.custom_minimum_size = Vector2(200, 84)
		back.pressed.connect(closed.emit)
		row.add_child(back)
		row.add_child(_done)
	else:
		col.add_child(_done)
	_refresh()


## This fight's perks for an animal: terrain, home turf, and a lair legend's weak spot ({good}),
## plus the legend resisting it ({bad}). `strong` (terrain or legend, not just home turf, which
## most early animals share) decides the highlight. Empty outside battle prep.
func _perks_here(id: String) -> Dictionary:
	var good: PackedStringArray = []
	var bad: PackedStringArray = []
	if battle_config.is_empty():
		return {"good": good, "bad": bad, "strong": false}
	var strong := false
	var tags := GameData.tags_of(id)
	var cond: String = battle_config.get("condition", "")
	if cond != "" and cond in tags:
		good.append("%s +%d%%" % [GameData.CONDITIONS[cond].name, roundi(GameData.CONDITION_BONUS * 100)])
		strong = true
	if battle_config.get("region", "") in GameData.native_regions(id):
		good.append("Home turf +%d%%" % roundi(GameData.HOME_TURF_BONUS * 100))
	for wave: Array in battle_config.waves:
		for enemy_id: String in wave:
			if not GameData.LEGENDS.has(enemy_id):
				continue
			var legend: Dictionary = GameData.LEGENDS[enemy_id]
			var weak: Dictionary = GameData.LEGEND_WEAKNESS[legend.build]
			if weak.weak in tags:
				good.append("vs %s +%d%%" % [legend.name, roundi((GameData.LEGEND_WEAK_MULT - 1.0) * 100)])
				strong = true
			elif weak.resist in tags:
				bad.append("%s resists it (-%d%%)" % [legend.name, roundi((1.0 - GameData.LEGEND_RESIST_MULT) * 100)])
	return {"good": good, "bad": bad, "strong": strong}


## What the pack is walking into: place, terrain, home turf, and the waves if a scout is out.
func _fight_summary() -> String:
	var lines: PackedStringArray = [battle_config.place]
	var cond: String = battle_config.get("condition", "")
	if cond != "":
		var c: Dictionary = GameData.CONDITIONS[cond]
		lines.append("%s: %s +%d%%" % [c.name, c.who, roundi(GameData.CONDITION_BONUS * 100)])
	var region: String = battle_config.get("region", "")
	if GameData.REGIONS.has(region):
		lines.append("Home turf: %s animals +%d%%" % [GameData.REGIONS[region].name, roundi(GameData.HOME_TURF_BONUS * 100)])
	if profile.duties.has("scout"):
		lines.append("Scouted: " + GameData.waves_text(battle_config.waves))
	else:
		lines.append("%d wave%s (put a benched animal on scout duty to see them)" % [battle_config.waves.size(), "" if battle_config.waves.size() == 1 else "s"])
	return "\n".join(lines)


func _refresh() -> void:
	for child in _list.get_children():
		child.queue_free()
	if profile.has_pet():
		_list.add_child(_card(profile.pet_species, GameData.PETS[profile.pet_species], true, true, Callable()))
	var order: Array[String] = profile.unlocked.duplicate()
	if not battle_config.is_empty():
		# Before a fight, animals with a perk here come first (stable otherwise).
		var has_perk := func(id: String) -> int: return 0 if _perks_here(id).strong else 1
		var by_perk: Array[String] = []
		for pass_index in 2:
			for id in order:
				if has_perk.call(id) == pass_index:
					by_perk.append(id)
		order = by_perk
	for id in order:
		_list.add_child(_card(id, GameData.ANIMALS[id], id in profile.team, false, _toggle.bind(id)))
	var names: PackedStringArray = []
	for bond in GameData.active_bonds(profile.pack_ids()):
		names.append("%s (%s)" % [bond.name, bond.desc])
	_bonds.text = ("Bonds: " + ", ".join(names) + " +%d%% ATK/DEF" % roundi(GameData.BOND_BONUS * 100)) if not names.is_empty() \
		else "No bonds. Try 2 canines, 2 birds, 2 night animals, a dog + a cat, or neighbors from one region."
	_count.text = "In the pack: %d / %d" % [profile.team.size(), profile.locals_needed()]
	_count.add_theme_color_override("font_color", Retro.GOLD)
	_done.disabled = profile.team.size() != profile.locals_needed()
	_build_roster()


## Checkbox tap. A full pack never silently drops someone: it says to uncheck one first.
func _toggle(id: String) -> void:
	if id in profile.team:
		profile.team.erase(id)
		profile.auto_fill_duties()  # benched animals pick up any free duty automatically
		_refresh()
		return
	elif profile.team.size() >= profile.locals_needed():
		_count.text = "Pack full (%d/%d): uncheck someone first" % [profile.team.size(), profile.locals_needed()]
		_count.add_theme_color_override("font_color", Retro.ORANGE)
		var tween := _count.create_tween()
		tween.tween_property(_count, "modulate", Color(1.6, 1.6, 1.6), 0.08)
		tween.tween_property(_count, "modulate", Color.WHITE, 0.2)
		return
	else:
		profile.team.append(id)
		profile.clear_duty(id)
	profile.auto_fill_duties()  # a duty left behind passes to someone still on the bench
	_refresh()


## Small sprites + names of the animals picked right now.
func _build_roster() -> void:
	for child in _roster.get_children():
		child.queue_free()
	var head := Retro.title(Label.new(), 10, Retro.FOG)
	head.text = "Your pack:"
	head.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_roster.add_child(head)
	for id in profile.pack_ids():
		var chip := VBoxContainer.new()
		chip.add_theme_constant_override("separation", 0)
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(56, 56)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var path := "res://art/pixel/%s.png" % id
		if ResourceLoader.exists(path):
			icon.texture = load(path)
		chip.add_child(icon)
		var name_label := Retro.text(Label.new(), 15, Retro.GOLD)
		name_label.text = profile.unit_name(id)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		chip.add_child(name_label)
		_roster.add_child(chip)
	for k in profile.locals_needed() - profile.team.size():
		var empty := Retro.text(Label.new(), 15, Retro.STEEL)
		empty.text = "[ empty ]"
		empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_roster.add_child(empty)


## The big pick box at the left of each card: checked = in the pack. The pet's is locked on.
func _pick_box(checked: bool, locked: bool, on_press: Callable) -> Control:
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.custom_minimum_size = Vector2(92, 0)
	column.add_theme_constant_override("separation", 4)
	var box := Control.new()
	box.custom_minimum_size = Vector2(68, 68)
	box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.draw.connect(func() -> void:
		var r := Rect2(Vector2.ZERO, box.size)
		box.draw_rect(r, Retro.DIRT if checked else Retro.INK)
		box.draw_rect(r.grow(-3), Retro.GOLD if checked else Retro.FOG, false, 6.0)
		if checked:
			# A chunky pixel tick.
			var s := box.size
			box.draw_polyline(PackedVector2Array([s * Vector2(0.2, 0.52), s * Vector2(0.42, 0.74), s * Vector2(0.8, 0.28)]),
				Retro.YELLOW if not locked else Retro.FOG, 10.0))
	column.add_child(box)
	var caption := Retro.title(Label.new(), 9, Retro.GOLD if checked else Retro.FOG)
	caption.text = "LEADER" if locked else ("IN PACK" if checked else "TAP TO ADD")
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(caption)
	if not locked:
		column.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		Retro.on_tap(column, on_press)
	return column


func _card(id: String, data: Dictionary, selected: bool, is_pet: bool, on_press: Callable) -> PanelContainer:
	var level := profile.level_of(id)
	# Build the unit as it would enter battle so the stats shown are the real ones.
	var unit := profile.build_unit(id)
	var worn: String = profile.equipped.get(id, "")

	var card := PanelContainer.new()
	var perks := _perks_here(id)
	var border := Retro.GOLD if selected else Retro.SLATE
	var width := Retro.BORDER
	if perks.strong:
		border = Retro.CYAN  # a perk for this fight: cyan border; gold fill still means "in the pack"
		width = Retro.BORDER + 3
	var normal := Retro.box(Retro.DIRT if selected else Retro.NIGHT, border, width, 2, 10)
	card.add_theme_stylebox_override("panel", normal)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(row)
	row.add_child(_pick_box(selected, is_pet, on_press))

	var sprite := TextureRect.new()
	sprite.custom_minimum_size = Vector2(88, 88)
	sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var path := "res://art/pixel/%s.png" % id
	if ResourceLoader.exists(path):
		sprite.texture = load(path)
	row.add_child(sprite)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(info)
	var title_label := Retro.title(Label.new(), 13, Retro.GOLD if selected else Retro.WHITE)
	title_label.text = unit.display_name
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(title_label)
	var tag := Retro.text(Label.new(), 19, Retro.FOG)
	tag.text = ("Leader · %s" % data.name) if is_pet else data.role
	var best: PackedStringArray = []
	for t in GameData.ANIMAL_TAGS.get(id, []):
		if GameData.CONDITIONS.has(t):
			best.append(GameData.CONDITIONS[t].name)
	if not best.is_empty():
		tag.text += " · Best in: " + ", ".join(best)
	tag.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(tag)
	if not perks.good.is_empty():
		var bonus := Retro.text(Label.new(), 18, Retro.CYAN)
		bonus.text = "PERK: " + ", ".join(perks.good)
		bonus.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_child(bonus)
	if not perks.bad.is_empty():
		var warn := Retro.text(Label.new(), 18, Retro.ORANGE)
		warn.text = "Careful: " + ", ".join(perks.bad)
		warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_child(warn)
	var condition_notes: PackedStringArray = []
	if profile.injuries.has(id):
		condition_notes.append("Injured for %d battle%s (-%d%% HP/ATK)" % [profile.injuries[id], "" if profile.injuries[id] == 1 else "s", roundi(GameData.INJURY_PENALTY * 100)])
	var tired := profile.fatigue_penalty(id)
	if tired > 0.0:
		condition_notes.append("Tired -%d%% (rest a battle to recover)" % roundi(tired * 100))
	if not condition_notes.is_empty():
		var hurt := Retro.text(Label.new(), 18, Retro.ORANGE)
		hurt.text = "\n".join(condition_notes)
		hurt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_child(hurt)

	var lv_row := HBoxContainer.new()
	lv_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(lv_row)
	var lv := Retro.title(Label.new(), 11, Retro.YELLOW)
	lv.text = "Lv %d" % level
	lv.custom_minimum_size = Vector2(80, 0)
	lv_row.add_child(lv)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.custom_minimum_size = Vector2(0, 14)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill := Retro.box(Retro.SKY, Retro.SKY, 0, 0, 0)
	bar.add_theme_stylebox_override("fill", fill)
	var floor_xp := GameData.xp_to_reach(level)
	var next_xp := GameData.xp_to_reach(level + 1)
	bar.max_value = maxi(1, next_xp - floor_xp)
	bar.value = profile.xp.get(id, 0) - floor_xp
	lv_row.add_child(bar)

	var stats := Retro.text(Label.new(), 19, Retro.MIST)
	stats.text = "HP %d  ATK %d  DEF %d  SPD %d" % [unit.max_hp, unit.atk, unit.def, unit.spd]
	info.add_child(stats)

	var skill_names: PackedStringArray = []
	for skill_id in unit.skills:
		var n := unit.upgrade_count(skill_id)
		skill_names.append(unit.skill_data(skill_id).name + ((" +%d" % n) if n > 0 else ""))
	var skills_label := Retro.text(Label.new(), 18, Retro.FOG)
	skills_label.text = ", ".join(skill_names)
	skills_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(skills_label)
	var points := profile.points_left(id)
	var upgrade := Button.new()
	upgrade.text = ("Tech tree (%d point%s)" % [points, "" if points == 1 else "s"]) if points > 0 else "Tech tree"
	upgrade.add_theme_font_size_override("font_size", Retro.px(10))
	if points > 0:
		upgrade.add_theme_color_override("font_color", Retro.YELLOW)
	upgrade.pressed.connect(_show_upgrades.bind(id))
	info.add_child(upgrade)

	if not is_pet and not selected:
		var duty := profile.duty_of(id)
		var duty_button := Button.new()
		duty_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		duty_button.add_theme_font_size_override("font_size", Retro.px(10))
		duty_button.text = ("Duty: " + duty.capitalize()) if duty != "" else "Duty: none (tap to assign)"
		duty_button.tooltip_text = GameData.DUTY_INFO.get(duty, "")
		duty_button.pressed.connect(func() -> void:
			profile.cycle_duty(id)
			_refresh())
		info.add_child(duty_button)
		if duty != "":
			var what := Retro.text(Label.new(), 18, Retro.CYAN)
			what.text = GameData.DUTY_INFO[duty]
			what.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			info.add_child(what)

	# Trinket slot: its own button, so tapping it doesn't also toggle the card.
	var slot := Button.new()
	slot.alignment = HORIZONTAL_ALIGNMENT_LEFT
	slot.clip_text = true
	slot.add_theme_font_size_override("font_size", Retro.px(10))
	slot.text = ("Trinket: " + GameData.TRINKETS[worn].name) if worn != "" else ("+ Trinket" if not profile.trinkets.is_empty() else "No trinkets yet")
	slot.disabled = profile.trinkets.is_empty()
	slot.pressed.connect(_show_picker.bind(id, unit.display_name))
	info.add_child(slot)
	if worn != "":
		var effects := Retro.text(Label.new(), 18, Retro.YELLOW)
		effects.text = GameData.trinket_effects(worn)
		effects.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_child(effects)

	return card


## Pick which trinket a unit wears. Trinkets worn by someone else move over.
func _show_picker(unit_id: String, unit_name: String) -> void:
	var overlay := ColorRect.new()
	overlay.color = Retro.INK
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	margin.add_theme_constant_override("margin_top", 40)
	overlay.add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	margin.add_child(col)
	var title := Retro.title(Label.new(), 18)
	title.text = "Trinket for %s" % unit_name
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	Retro.touch_scroll(scroll)
	col.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)

	var choose := func(trinket_id: String) -> void:
		profile.equip(unit_id, trinket_id)
		overlay.queue_free()
		_refresh()
	var seen := {}
	for trinket_id in profile.trinkets:
		if seen.has(trinket_id):
			continue
		seen[trinket_id] = true
		var t: Dictionary = GameData.TRINKETS[trinket_id]
		var wearing: bool = profile.equipped.get(unit_id, "") == trinket_id
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", Retro.box(Retro.DIRT if wearing else Retro.NIGHT, Retro.GOLD if wearing else Retro.SLATE, Retro.BORDER, 2, 10))
		var box := VBoxContainer.new()
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(box)
		var name_label := Retro.title(Label.new(), 13, Retro.GOLD if wearing else Retro.WHITE)
		var copies := profile.trinkets.count(trinket_id)
		name_label.text = t.name + ((" x%d" % copies) if copies > 1 else "")
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(name_label)
		var effects := Retro.text(Label.new(), 20, Retro.YELLOW)
		effects.text = GameData.trinket_effects(trinket_id)
		effects.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(effects)
		var flavor := Retro.text(Label.new(), 18, Retro.FOG)
		flavor.text = "\"%s\"" % t.flavor
		flavor.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(flavor)
		var wearers: PackedStringArray = []
		for other in profile.equipped:
			if other != unit_id and profile.equipped[other] == trinket_id:
				wearers.append(profile.unit_name(other))
		if not wearers.is_empty():
			var worn_by := Retro.text(Label.new(), 18, Retro.ORANGE)
			worn_by.text = "Worn by " + ", ".join(wearers) + ("" if profile.trinkets_free(trinket_id) > 0 else " (picking it moves it here)")
			worn_by.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			box.add_child(worn_by)
		Retro.on_tap(card, choose.bind(trinket_id))
		list.add_child(card)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	col.add_child(row)
	var remove := Button.new()
	remove.text = "Take off"
	remove.custom_minimum_size = Vector2(0, 84)
	remove.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	remove.disabled = not profile.equipped.has(unit_id)
	remove.pressed.connect(choose.bind(""))
	row.add_child(remove)
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.custom_minimum_size = Vector2(0, 84)
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel.pressed.connect(overlay.queue_free)
	row.add_child(cancel)



func _show_upgrades(unit_id: String) -> void:
	var screen := TechTreeScreen.new()
	screen.profile = profile
	screen.units.assign([unit_id])
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.done.connect(func() -> void:
		screen.queue_free()
		_refresh())
	add_child(screen)
