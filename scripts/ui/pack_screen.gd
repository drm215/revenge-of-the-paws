class_name PackScreen
extends Control

## Swap animals in and out of the team and choose their trinkets. Shows the pack (up to
## PACK_LIMIT animals) as tiles, two per row, with levels and battle-ready stats. The pet always
## leads; it can only be changed from Setup. With `stable_view` it shows the Stable instead:
## reserves can be sent there for free, and bringing one back costs a map turn.
## With `battle_config` set it's the pre-battle screen: it shows the fight ahead, flags who suits
## it, and ends with Fight! (or Back to the map).

signal closed
signal fight
signal bring_back(id: String)  # bring this animal back from the Stable (costs a map turn)
signal open_stable  # switch to the Stable view

var profile: Profile
## Campaign.battle_config() / patrol_config() for the fight about to start; empty outside battle prep.
var battle_config := {}
## The Stable view (map's Stable button): only the Stable and the reserves that could go there.
var stable_view := false

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
	title.text = "Ready the pack" if prep else ("Stable" if stable_view else "Your Pack")
	col.add_child(title)
	var intro := Retro.text(Label.new(), 21 if prep else 22)
	if stable_view:
		intro.text = "Animals here don't fight or earn XP. Sending a reserve here is free; sending one to the pack takes a map turn and a free slot in the pack of %d." % GameData.PACK_LIMIT
	elif prep:
		intro.text = _fight_summary()
	else:
		intro.text = "Pick %d to fight%s. The pack holds %d; reserves earn half the XP and can scout, forage or guard." % [
			profile.locals_needed(), (" beside " + profile.pet_name) if profile.has_pet() else "", GameData.PACK_LIMIT]
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(intro)
	if not stable_view:
		var rows := Retro.text(Label.new(), 19, Retro.FOG)
		rows.text = GameData.row_hint()
		rows.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(rows)
	_roster.add_theme_constant_override("separation", 8)
	_roster.visible = not stable_view
	col.add_child(_roster)
	Retro.text(_bonds, 20, Retro.GOLD)
	_bonds.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bonds.visible = not stable_view
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
		var weak: PackedStringArray = []
		for wave: Array in battle_config.waves:
			for id: String in wave:
				var w: Dictionary = GameData.ZOMBIE_WEAKNESS.get(id, {})
				var line := "%s (%s)" % [GameData.ZOMBIES[id].name, GameData.tag_name(w.tag)] if not w.is_empty() else ""
				if line != "" and line not in weak:
					weak.append(line)
		if not weak.is_empty():
			lines.append("Weak spots: " + ", ".join(weak))
	else:
		lines.append("%d wave%s (put a benched animal on scout duty to see them)" % [battle_config.waves.size(), "" if battle_config.waves.size() == 1 else "s"])
	return "\n".join(lines)


func _refresh() -> void:
	for child in _list.get_children():
		child.queue_free()
	if stable_view:
		_section("In the Stable (%d)" % profile.stable.size(),
			"Nobody yet. Rescued animals wait here when the pack is full." if profile.stable.is_empty() else "")
		var stabled := _grid()
		for id in profile.stable:
			stabled.add_child(_card(id, GameData.ANIMALS[id], false, false, Callable(), true))
		var reserves: Array[String] = []
		for id in profile.active():
			if id not in profile.team:
				reserves.append(id)
		_section("Reserves", "Send one to the Stable to make room. To stable a fighter, take it out of the lineup on Pack first."
			if not reserves.is_empty() else "No reserves: everyone in the pack is fighting.")
		var reserve_grid := _grid()
		for id in reserves:
			reserve_grid.add_child(_card(id, GameData.ANIMALS[id], false, false, Callable()))
		_count.text = "Pack: %d / %d  ·  Stable: %d" % [_pack_count(), GameData.PACK_LIMIT, profile.stable.size()]
		_count.add_theme_color_override("font_color", Retro.GOLD)
		return

	# Fighters first, then reserves; before a fight, animals with a perk here lead the list.
	var order: Array[String] = []
	for id in profile.active():
		if id in profile.team:
			order.append(id)
	for id in profile.active():
		if id not in profile.team:
			order.append(id)
	if not battle_config.is_empty():
		var by_perk: Array[String] = []
		for pass_index in 2:
			for id in order:
				if (0 if _perks_here(id).strong else 1) == pass_index:
					by_perk.append(id)
		order = by_perk
	var grid := _grid()
	if profile.has_pet():
		grid.add_child(_card(profile.pet_species, GameData.PETS[profile.pet_species], true, true, Callable()))
	for id in order:
		grid.add_child(_card(id, GameData.ANIMALS[id], id in profile.team, false, _toggle.bind(id)))
	if battle_config.is_empty():
		var open := Button.new()
		open.text = "Stable (%d)  >" % profile.stable.size()
		open.custom_minimum_size = Vector2(0, 72)
		open.add_theme_font_size_override("font_size", Retro.px(15))
		open.pressed.connect(open_stable.emit)
		_list.add_child(open)
	var names: PackedStringArray = []
	for bond in GameData.active_bonds(profile.pack_ids()):
		names.append("%s (%s)" % [bond.name, bond.desc])
	_bonds.text = ("Bonds: " + ", ".join(names) + " +%d%% ATK/DEF" % roundi(GameData.BOND_BONUS * 100)) if not names.is_empty() \
		else "No bonds. Try 2 canines, 2 birds, 2 night animals, a dog + a cat, or neighbors from one region."
	_count.text = "Fighting: %d / %d  ·  Pack: %d / %d" % [profile.team.size(), profile.locals_needed(),
		_pack_count(), GameData.PACK_LIMIT]
	_count.add_theme_color_override("font_color", Retro.GOLD)
	_done.disabled = profile.team.size() != profile.locals_needed()
	_build_roster()


func _pack_count() -> int:
	return profile.active().size() + (1 if profile.has_pet() else 0)


## A heading (and optional note) in the list.
func _section(heading: String, note: String) -> void:
	var head := Retro.title(Label.new(), 13, Retro.GOLD)
	head.text = heading
	_list.add_child(head)
	if note != "":
		var line := Retro.text(Label.new(), 19, Retro.FOG)
		line.text = note
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_list.add_child(line)


## Two tiles per row.
func _grid() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	_list.add_child(grid)
	return grid


## Fight button tap. A full lineup never silently drops someone: it says to take one out first.
func _toggle(id: String) -> void:
	if id in profile.team:
		profile.team.erase(id)
		profile.auto_fill_duties()  # benched animals pick up any free duty automatically
		_refresh()
		return
	elif profile.team.size() >= profile.locals_needed():
		_count.text = "Lineup full (%d/%d): take someone out first" % [profile.team.size(), profile.locals_needed()]
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
	var head := Retro.title(Label.new(), 12, Retro.FOG)
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


## A compact button for a tile, tall enough to tap.
func _tile_button(label: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = label
	b.clip_text = true
	b.custom_minimum_size = Vector2(0, 52)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", Retro.px(16))
	if on_press.is_valid():
		b.pressed.connect(on_press)
	return b


func _tile_text(text: String, font_size: int, color: Color) -> Label:
	var label := Retro.text(Label.new(), font_size, color)
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


## One animal as a tile (two per row): sprite, name and level, battle-ready stats, then its
## buttons. Gold frame = fighting (or the leader); cyan frame = a perk in the coming fight.
func _card(id: String, data: Dictionary, selected: bool, is_pet: bool, on_press: Callable, stabled := false) -> PanelContainer:
	var level := profile.level_of(id)
	# Build the unit as it would enter battle so the stats shown are the real ones.
	var unit := profile.build_unit(id)
	var worn: String = profile.equipped.get(id, "")
	var perks := _perks_here(id)

	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var border := Retro.GOLD if selected else Retro.NIGHT  # only fighters (and perks) get a colored frame
	var width := Retro.BORDER
	if perks.strong:
		border = Retro.CYAN  # a perk for this fight: cyan border; gold fill still means "fighting"
		width = Retro.BORDER + 3
	card.add_theme_stylebox_override("panel", Retro.box(Retro.DIRT if selected else Retro.NIGHT, border, width, 2, 8))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(col)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(top)
	var sprite := TextureRect.new()
	sprite.custom_minimum_size = Vector2(64, 64)
	sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var path := "res://art/pixel/%s.png" % id
	if ResourceLoader.exists(path):
		sprite.texture = load(path)
	top.add_child(sprite)
	var head := VBoxContainer.new()
	head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_theme_constant_override("separation", 2)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(head)
	# Tapping the picture or name opens the full details.
	top.mouse_filter = Control.MOUSE_FILTER_STOP
	top.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	Retro.on_tap(top, _show_details.bind(id))
	var name_label := Retro.title(Label.new(), 12, Retro.GOLD if selected else Retro.WHITE)
	name_label.text = unit.display_name
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.add_child(name_label)
	var lv := Retro.title(Label.new(), 11, Retro.YELLOW)
	lv.text = "Lv %d" % level
	head.add_child(lv)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 10)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_stylebox_override("fill", Retro.box(Retro.SKY, Retro.SKY, 0, 0, 0))
	var floor_xp := GameData.xp_to_reach(level)
	bar.max_value = maxi(1, GameData.xp_to_reach(level + 1) - floor_xp)
	bar.value = profile.xp.get(id, 0) - floor_xp
	head.add_child(bar)

	var tag: String = ("Leader · %s" % data.name) if is_pet else data.role
	var best: PackedStringArray = []
	for t in GameData.ANIMAL_TAGS.get(id, []):
		if GameData.CONDITIONS.has(t):
			best.append(GameData.CONDITIONS[t].name)
	if not best.is_empty():
		tag += " · " + ", ".join(best)
	col.add_child(_tile_text(tag, 16, Retro.FOG))
	if not perks.good.is_empty():
		col.add_child(_tile_text("PERK: " + ", ".join(perks.good), 16, Retro.CYAN))
	if not perks.bad.is_empty():
		col.add_child(_tile_text("Careful: " + ", ".join(perks.bad), 16, Retro.ORANGE))
	var hurt: PackedStringArray = []
	if profile.injuries.has(id):
		hurt.append("Injured %d (-%d%%)" % [profile.injuries[id], roundi(GameData.INJURY_PENALTY * 100)])
	var tired := profile.fatigue_penalty(id)
	if tired > 0.0:
		hurt.append("Tired -%d%%" % roundi(tired * 100))
	if not hurt.is_empty():
		col.add_child(_tile_text(" · ".join(hurt), 16, Retro.ORANGE))
	col.add_child(_tile_text("HP %d  ATK %d\nDEF %d  SPD %d" % [unit.max_hp, unit.atk, unit.def, unit.spd], 17, Retro.MIST))
	var skill_names: PackedStringArray = []
	for skill_id in unit.skills:
		var n := unit.upgrade_count(skill_id)
		skill_names.append(unit.skill_data(skill_id).name + ((" +%d" % n) if n > 0 else ""))
	col.add_child(_tile_text(", ".join(skill_names), 16, Retro.FOG))

	# Buttons: the lineup (or Stable) action first, then tech tree, duty and trinket.
	if is_pet:
		var lead := _tile_button("LEADER", Callable())
		lead.disabled = true
		col.add_child(lead)
	elif stabled:
		var back := _tile_button("Send to Pack (1 turn)", bring_back.emit.bind(id))
		back.disabled = not profile.can_leave_stable(id)
		if back.disabled:
			back.text = "Pack full"
		col.add_child(back)
	elif not stable_view:
		var pick := _tile_button("FIGHTING" if selected else "+ Fight", on_press)
		if selected:
			pick.add_theme_color_override("font_color", Retro.YELLOW)
		col.add_child(pick)
	if not stabled and not stable_view:
		var row := _tile_button("Row: " + profile.row_of(id).capitalize(), func() -> void:
			profile.toggle_row(id)
			_refresh())
		row.tooltip_text = GameData.row_hint("back")
		col.add_child(row)
	col.add_child(_tile_button("Details", _show_details.bind(id)))
	var points := profile.points_left(id)
	var upgrade := _tile_button(("Tech tree (%d)" % points) if points > 0 else "Tech tree", _show_upgrades.bind(id))
	if points > 0:
		upgrade.add_theme_color_override("font_color", Retro.YELLOW)
	col.add_child(upgrade)
	if not is_pet and not selected and not stabled:
		var duty := profile.duty_of(id)
		var duty_button := _tile_button(("Duty: " + duty.capitalize()) if duty != "" else "Duty: none", func() -> void:
			profile.cycle_duty(id)
			_refresh())
		duty_button.tooltip_text = GameData.DUTY_INFO.get(duty, "")
		if duty != "":
			duty_button.add_theme_color_override("font_color", Retro.CYAN)
		col.add_child(duty_button)
		if battle_config.is_empty():
			col.add_child(_tile_button("To Stable", func() -> void:
				profile.send_to_stable(id)
				_refresh()))
	var slot := _tile_button(GameData.trinket(worn).name if worn != "" else ("+ Trinket" if not profile.trinkets.is_empty() else "No trinkets"),
		_show_picker.bind(id, unit.display_name))
	slot.disabled = profile.trinkets.is_empty()
	col.add_child(slot)
	if worn != "":
		col.add_child(_tile_text(GameData.trinket_effects(worn), 15, Retro.YELLOW))
	return card


## Everything about one animal: where it is, stats, every skill with what it does and its numbers
## (upgrades and Mastery included), trinket, tags, and bonds in the current pack.
func _show_details(unit_id: String) -> void:
	var is_pet := profile.has_pet() and unit_id == profile.pet_species
	var data: Dictionary = GameData.PETS[unit_id] if is_pet else GameData.ANIMALS[unit_id]
	var unit := profile.build_unit(unit_id)
	var level := profile.level_of(unit_id)

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
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	margin.add_child(outer)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	Retro.touch_scroll(scroll)
	outer.add_child(scroll)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 8)
	scroll.add_child(col)
	var heading := func(text: String) -> void:
		var label := Retro.title(Label.new(), 12, Retro.GOLD)
		label.text = text
		col.add_child(label)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	col.add_child(top)
	var sprite := TextureRect.new()
	sprite.custom_minimum_size = Vector2(128, 128)
	sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var path := "res://art/pixel/%s.png" % unit_id
	if ResourceLoader.exists(path):
		sprite.texture = load(path)
	top.add_child(sprite)
	var head := VBoxContainer.new()
	head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_child(head)
	var name_label := Retro.title(Label.new(), 16)
	name_label.text = unit.display_name
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.add_child(name_label)
	head.add_child(_tile_text(("Lv %d · %s · %s" % [level, data.name, data.role]) if is_pet else ("Lv %d · %s" % [level, data.role]), 20, Retro.YELLOW))
	head.add_child(_tile_text("XP %d / %d to Lv %d" % [profile.xp.get(unit_id, 0), GameData.xp_to_reach(level + 1), level + 1]
		if level < GameData.MAX_LEVEL else "Max level", 18, Retro.FOG))
	col.add_child(_tile_text("\"%s\"" % data.desc, 20, Retro.FOG))

	var where := "Leads the pack: allies get +%d%% ATK/DEF while it stands." % roundi(GameData.LEADER_AURA * 100) if is_pet \
		else "In the Stable: no fighting, no XP." if unit_id in profile.stable \
		else "Fighting." if unit_id in profile.team \
		else "Reserve: half XP" + ((", on %s duty." % profile.duty_of(unit_id)) if profile.duty_of(unit_id) != "" else ".")
	col.add_child(_tile_text(where, 20, Retro.CYAN))
	if unit_id not in profile.stable:
		col.add_child(_tile_text(GameData.row_hint(profile.row_of(unit_id), "bird" in profile.build_unit(unit_id).tags), 19, Retro.FOG))
	var hurt: PackedStringArray = []
	if profile.injuries.has(unit_id):
		hurt.append("Injured for %d battle%s: -%d%% HP/ATK." % [profile.injuries[unit_id], "" if profile.injuries[unit_id] == 1 else "s", roundi(GameData.INJURY_PENALTY * 100)])
	if profile.fatigue_penalty(unit_id) > 0.0:
		hurt.append("Tired: -%d%% stats until it sits out a battle." % roundi(profile.fatigue_penalty(unit_id) * 100))
	if not hurt.is_empty():
		col.add_child(_tile_text("\n".join(hurt), 20, Retro.ORANGE))

	heading.call("Stats")
	var stat_lines: PackedStringArray = ["HP %d   ATK %d   DEF %d   SPD %d   Crit %d%%" % [unit.max_hp, unit.atk, unit.def, unit.spd, roundi(unit.crit * 100)]]
	if unit.lifesteal > 0.0:
		stat_lines.append("Heals %d%% of damage dealt" % roundi(unit.lifesteal * 100))
	if unit.thorns > 0.0:
		stat_lines.append("Reflects %d%% of damage taken" % roundi(unit.thorns * 100))
	if unit.regen > 0.0:
		stat_lines.append("Regenerates %d%% HP each turn" % roundi(unit.regen * 100))
	if not unit.immune.is_empty():
		stat_lines.append("Immune to " + ", ".join(unit.immune.map(func(s: String) -> String: return GameData.STATUSES[s].name)))
	col.add_child(_tile_text("\n".join(stat_lines), 20, Retro.MIST))

	heading.call("Skills")
	for skill_id in unit.skills:
		var s := unit.skill_data(skill_id)
		var n := unit.upgrade_count(skill_id)
		var box := PanelContainer.new()
		box.add_theme_stylebox_override("panel", Retro.box(Retro.NIGHT, Retro.SLATE, Retro.BORDER, 2, 10))
		var lines := VBoxContainer.new()
		lines.add_theme_constant_override("separation", 2)
		box.add_child(lines)
		var skill_name := Retro.title(Label.new(), 11, Retro.WHITE)
		skill_name.text = s.name + ((" +%d" % n) if n > 0 else "") + ("  (always ready)" if s.get("cooldown", 0) == 0 else "")
		skill_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lines.add_child(skill_name)
		lines.add_child(_tile_text(s.desc, 19, Retro.FOG))
		lines.add_child(_tile_text(GameData.skill_stats(s) + (" · Cures infection" if s.get("cleanse", false) else ""), 19, Retro.CYAN))
		var combo := GameData.combo_hint(s)
		if combo != "":
			lines.add_child(_tile_text(combo, 19, Retro.GREEN))
		col.add_child(box)
	if unit.mastered:
		col.add_child(_tile_text("Mastery: every skill hits harder and recharges faster.", 19, Retro.YELLOW))
	if profile.points_left(unit_id) > 0:
		col.add_child(_tile_text("%d tech-tree point%s to spend." % [profile.points_left(unit_id), "" if profile.points_left(unit_id) == 1 else "s"], 19, Retro.YELLOW))

	heading.call("Trinket")
	var worn: String = profile.equipped.get(unit_id, "")
	col.add_child(_tile_text(("%s: %s" % [GameData.trinket(worn).name, GameData.trinket_effects(worn)]) if worn != "" else "None", 19,
		Retro.YELLOW if worn != "" else Retro.FOG))

	heading.call("Tags")
	var tags: PackedStringArray = []
	for t in GameData.tags_of(unit_id):
		tags.append(GameData.CONDITIONS[t].name if GameData.CONDITIONS.has(t) else t.capitalize())
	col.add_child(_tile_text(", ".join(tags) + "\nTags decide terrain bonuses, bonds and weak spots.", 19, Retro.FOG))
	var counters := GameData.counters(unit_id)
	heading.call("Zombie weak spots")
	if counters.is_empty():
		col.add_child(_tile_text("None. It hits every zombie type normally.", 19, Retro.FOG))
	for id in GameData.ZOMBIE_WEAKNESS:
		if GameData.ZOMBIES[id].name in counters:
			col.add_child(_tile_text("%s: %s" % [GameData.ZOMBIES[id].name, GameData.weak_text(id)], 20, Retro.CYAN))
	if unit_id in profile.pack_ids():
		var bonds: PackedStringArray = []
		for bond in GameData.active_bonds(profile.pack_ids()):
			if unit_id in bond.members:
				bonds.append("%s (%s)" % [bond.name, bond.desc])
		if not bonds.is_empty():
			col.add_child(_tile_text("Bonds: " + ", ".join(bonds), 19, Retro.GOLD))

	var close := Button.new()
	close.text = "Close"
	close.custom_minimum_size = Vector2(0, 84)
	close.pressed.connect(overlay.queue_free)
	outer.add_child(close)


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
		var t: Dictionary = GameData.trinket(trinket_id)
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
	var fuse := Button.new()
	fuse.text = "Fuse"
	fuse.custom_minimum_size = Vector2(0, 84)
	fuse.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fuse.disabled = profile.trinkets.size() < 2
	fuse.pressed.connect(func() -> void:
		overlay.queue_free()
		_show_fusion())
	row.add_child(fuse)
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.custom_minimum_size = Vector2(0, 84)
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel.pressed.connect(overlay.queue_free)
	row.add_child(cancel)


## Fuse two trinkets into one with both effects (and both drawbacks). Tap two, check the result,
## then Fuse; both are used up.
func _show_fusion(first := "") -> void:
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
	title.text = "Fuse trinkets"
	col.add_child(title)
	col.add_child(_tile_text("Pick two. The fused trinket has both effects and both drawbacks; the two are used up. A fused trinket can't be fused again." if first == ""
		else "Now pick the second one.", 20, Retro.MIST))

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	Retro.touch_scroll(scroll)
	col.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)
	var seen := {}
	for trinket_id in profile.trinkets:
		if seen.has(trinket_id):
			continue
		seen[trinket_id] = true
		var picked := trinket_id == first
		var block := ""
		if first == "" and trinket_id.begins_with(GameData.FUSED_PREFIX):
			block = "Already fused."
		elif first != "":
			block = profile.fuse_block(first, trinket_id)
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", Retro.box(Retro.DIRT if picked else Retro.NIGHT, Retro.GOLD if picked else Retro.NIGHT, Retro.BORDER, 2, 10))
		var box := VBoxContainer.new()
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(box)
		var copies := profile.trinkets.count(trinket_id)
		var name_label := Retro.title(Label.new(), 13, Retro.GOLD if picked else (Retro.FOG if block != "" else Retro.WHITE))
		name_label.text = GameData.trinket(trinket_id).name + ((" x%d" % copies) if copies > 1 else "")
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(name_label)
		box.add_child(_tile_text(GameData.trinket_effects(trinket_id), 19, Retro.YELLOW if block == "" else Retro.FOG))
		if picked:
			box.add_child(_tile_text("Picked." + (" Tap again to fuse it with its twin: " + GameData.trinket_effects(GameData.fused_id(first, first)) if block == "" else ""), 18, Retro.CYAN))
		elif block != "":
			box.add_child(_tile_text(block, 18, Retro.ORANGE))
		elif first != "":
			box.add_child(_tile_text("Fused: " + GameData.trinket_effects(GameData.fused_id(first, trinket_id)), 18, Retro.CYAN))
		if block == "":
			Retro.on_tap(card, func() -> void:
				overlay.queue_free()
				if first == "":
					_show_fusion(trinket_id)
				else:
					_confirm_fusion(first, trinket_id))
		list.add_child(card)

	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.custom_minimum_size = Vector2(0, 84)
	cancel.pressed.connect(overlay.queue_free)
	col.add_child(cancel)


func _confirm_fusion(a: String, b: String) -> void:
	var overlay := ColorRect.new()
	overlay.color = Retro.INK
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(560, 0)
	col.add_theme_constant_override("separation", 14)
	center.add_child(col)
	var fused := GameData.fused_id(a, b)
	var title := Retro.title(Label.new(), 15)
	title.text = GameData.trinket(fused).name
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(title)
	col.add_child(_tile_text(GameData.trinket_effects(fused), 21, Retro.YELLOW))
	var worn: PackedStringArray = []
	for id in [a, b]:
		if profile.trinkets_free(id) <= 0:
			for wearer in profile.equipped:
				if profile.equipped[wearer] == id:
					worn.append(profile.unit_name(wearer))
					break
	col.add_child(_tile_text("Uses up both trinkets." + ((" Taken off: " + ", ".join(worn) + ".") if not worn.is_empty() else ""), 19, Retro.FOG))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	col.add_child(row)
	var go := Button.new()
	go.text = "Fuse"
	go.custom_minimum_size = Vector2(0, 84)
	go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	go.pressed.connect(func() -> void:
		profile.fuse(a, b)
		overlay.queue_free()
		_refresh())
	row.add_child(go)
	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(0, 84)
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back.pressed.connect(func() -> void:
		overlay.queue_free()
		_show_fusion())
	row.add_child(back)



func _show_upgrades(unit_id: String) -> void:
	var screen := TechTreeScreen.new()
	screen.profile = profile
	screen.units.assign([unit_id])
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.done.connect(func() -> void:
		screen.queue_free()
		_refresh())
	add_child(screen)
