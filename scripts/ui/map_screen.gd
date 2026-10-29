class_name MapScreen
extends Control

## Campaign map: pick a neighboring territory to attack, or answer a zombie counterattack.
## Lairs open a briefing on their legend before the fight.

signal battle_requested(index: int)
signal patrol_requested(index: int)
signal rest_requested
signal setup_requested
signal pack_requested
signal account_requested

var campaign: Campaign
var profile: Profile

var _map := MapView.new()
var _status := Label.new()
var _event := Label.new()
var _info_title := Label.new()
var _info_body := Label.new()
var _action := Button.new()
var _briefing: Control


func _ready() -> void:
	_build_ui()
	_map.campaign = campaign
	_map.territory_selected.connect(_select)
	_refresh_status()
	_select(campaign.under_attack if campaign.under_attack >= 0 else campaign.home)
	if campaign.under_attack >= 0:
		_map.focus.call_deferred(campaign.under_attack)


func _select(i: int) -> void:
	_map.selected = i
	_map.queue_redraw()
	var t := campaign.territories[i]
	_info_title.text = t.name + (("  " + t.id) if campaign.uses_zip_data else "")
	_action.visible = campaign.is_actionable(i)
	_action.set_meta("mode", "attack")
	if i == campaign.under_attack:
		_info_body.text = "Under attack! Threat %d. Lose this fight and the territory falls." % t.threat
		_action.text = "Defend!"
	elif i == campaign.home:
		_info_body.text = "Home. Where %s began.\nRest here to heal injuries and clear fatigue (takes a turn)." % _pack_name()
		_action.text = "Rest"
		_action.visible = true
		_action.set_meta("mode", "rest")
	elif t.owned:
		_info_body.text = "Liberated. Survivors here reinforce your pack.\nPatrol for an easier fight (threat %d) that earns XP." % maxi(1, t.threat - 1)
		_action.text = "Patrol"
		_action.visible = true
		_action.set_meta("mode", "patrol")
	else:
		var cfg := campaign.battle_config(i)
		var tougher := roundi((GameData.zombie_mult(t.threat) - 1.0) * 100)
		_info_body.text = "Threat %d · %d wave%s%s" % [
			t.threat, cfg.waves.size(), "" if cfg.waves.size() == 1 else "s",
			(" · zombies +%d%%" % tougher) if tougher > 0 else ""]
		if t.failed_attacks > 0:
			_info_body.text += " · horde thinned to %d%%" % roundi(t.horde_strength() * 100)
		if campaign.under_attack >= 0:
			_info_body.text += "\nDeal with the counterattack first."
		elif not campaign.can_attack(i):
			_info_body.text += "\nToo far. Liberate a neighboring territory first."
		if t.boss != "":
			var legend: Dictionary = GameData.LEGENDS[t.boss]
			_info_title.text = "Lair of the %s" % legend.name
			_info_body.text = "%s\n%s" % [legend.lore, _info_body.text]
		_action.text = "Attack!"
		var loot := campaign.loot_at(i)
		if loot != "":
			_info_body.text += "\nDrops: %s (%s)" % [GameData.TRINKETS[loot].name, GameData.trinket_effects(loot)]
		var cond: Dictionary = GameData.CONDITIONS[t.condition]
		_info_body.text += "\n%s: %s +%d%%." % [cond.name, cond.who, roundi(GameData.CONDITION_BONUS * 100)]
		if t.region != "" and GameData.REGIONS.has(t.region):
			_info_body.text += " Home turf for %s animals." % GameData.REGIONS[t.region].name
		if profile.duties.has("scout"):
			_info_body.text += "\nScouted: " + GameData.waves_text(cfg.waves)
		else:
			_info_body.text += "\nWaves unknown: put a benched animal on scout duty."
		if campaign.has_frontier(i):
			_info_body.text += "\nOn the frontier: liberate it to reveal what lies beyond."
		var survivor := campaign.pending_recruit(i)
		if survivor != "":
			var a: Dictionary = GameData.ANIMALS[survivor]
			_info_body.text += "\nSurvivor here: %s (%s). Liberate it to recruit!" % [a.name, a.role]
	_action.set_meta("territory", i)


func _refresh_status() -> void:
	_status.text = "Held %d / %d  ·  Pack strength +%d%%  ·  Counterattack every %d turns" % [
		campaign.owned_count(), campaign.territories.size(), roundi(campaign.held_bonus() * 100), campaign.counter_interval()]
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var event := campaign.last_event
	if campaign.is_liberated():
		event = "Every territory is liberated. Your neighborhood is safe!"
	_event.text = event
	_event.visible = event != ""


func _on_action() -> void:
	var i: int = _action.get_meta("territory")
	match _action.get_meta("mode", "attack"):
		"rest":
			rest_requested.emit()
			return
		"patrol":
			patrol_requested.emit(i)
			return
	var t := campaign.territories[i]
	if t.boss != "" and not t.owned:
		_show_briefing(i)
	else:
		battle_requested.emit(i)


## Everything worth knowing before taking on a legend: stats at this threat, its abilities and
## when it uses them, what escorts it, and how to beat it.
func _show_briefing(i: int) -> void:
	var t := campaign.territories[i]
	var legend: Dictionary = GameData.LEGENDS[t.boss]
	var data := GameData.enemy(t.boss)
	var cfg := campaign.battle_config(i)
	var mult: float = cfg.zombie_mult

	_briefing = ColorRect.new()
	(_briefing as ColorRect).color = Retro.INK
	_briefing.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_briefing)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	margin.add_theme_constant_override("margin_top", 36)
	_briefing.add_child(margin)
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

	var add := func(label: Label, wrap := true) -> void:
		if wrap:
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(label)
	var head := Retro.title(Label.new(), 18, MapView.LAIR)
	head.text = "Lair of the %s" % legend.name
	add.call(head)

	var sprite := TextureRect.new()
	sprite.custom_minimum_size = Vector2(0, 200)
	sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.flip_h = true
	var path := "res://art/pixel/%s.png" % t.boss
	if ResourceLoader.exists(path):
		sprite.texture = load(path)
	col.add_child(sprite)

	var lore := Retro.text(Label.new(), 24, Retro.MIST)
	lore.text = legend.lore
	add.call(lore)
	var stats := Retro.title(Label.new(), 11, Retro.WHITE)
	stats.text = "HP %d  ATK %d  DEF %d  SPD %d" % [roundi(data.hp * mult), roundi(data.atk * mult), data.def, data.spd]
	add.call(stats)

	var abilities := Retro.title(Label.new(), 13, Retro.GOLD)
	abilities.text = "Abilities"
	add.call(abilities)
	for skill_id: String in legend.skills:
		var s := GameData.skill(skill_id)
		var cd: int = s.get("cooldown", 0)
		var line := Retro.text(Label.new(), 21, Retro.MIST)
		var timing := "Its basic attack." if cd == 0 else "First used on its turn %d, then every %d turns." % [cd, cd + 1]
		line.text = "%s: %s %s" % [s.name, s.get("desc", ""), timing]
		add.call(line)

	var weak: Dictionary = GameData.LEGEND_WEAKNESS[legend.build]
	var weak_head := Retro.title(Label.new(), 13, Retro.GOLD)
	weak_head.text = "Weak spots"
	add.call(weak_head)
	var weak_line := Retro.text(Label.new(), 21, Retro.MIST)
	weak_line.text = "Weak to %s animals (+%d%% damage). Resists %s animals (-%d%%). %s" % [
		weak.weak, roundi((GameData.LEGEND_WEAK_MULT - 1.0) * 100), weak.resist,
		roundi((1.0 - GameData.LEGEND_RESIST_MULT) * 100), weak.why]
	add.call(weak_line)
	var cond: Dictionary = GameData.CONDITIONS[t.condition]
	var terrain := Retro.text(Label.new(), 21, Retro.CYAN)
	terrain.text = "%s: %s +%d%%." % [cond.name, cond.who, roundi(GameData.CONDITION_BONUS * 100)]
	add.call(terrain)

	var fight := Retro.title(Label.new(), 13, Retro.GOLD)
	fight.text = "The fight"
	add.call(fight)
	var escorts: PackedStringArray = []
	for id: String in cfg.waves[-1]:
		if id != t.boss:
			escorts.append(GameData.enemy(id).name)
	var plan := Retro.text(Label.new(), 21, Retro.MIST)
	plan.text = "%d waves. The %s waits in the last one%s. Zombies here are +%d%% tougher; your pack is level %d on average." % [
		cfg.waves.size(), legend.name, (" with " + ", ".join(escorts)) if not escorts.is_empty() else "",
		roundi((mult - 1.0) * 100), profile.pack_level()]
	add.call(plan)

	var loot := campaign.loot_at(i)
	if loot != "":
		var drop_head := Retro.title(Label.new(), 13, Retro.GOLD)
		drop_head.text = "Drops"
		add.call(drop_head)
		var drop := Retro.text(Label.new(), 21, Retro.YELLOW)
		drop.text = "%s: %s. \"%s\"" % [GameData.TRINKETS[loot].name, GameData.trinket_effects(loot), GameData.TRINKETS[loot].flavor]
		add.call(drop)

	var tip_head := Retro.title(Label.new(), 13, Retro.GOLD)
	tip_head.text = "Tip"
	add.call(tip_head)
	var tip := Retro.text(Label.new(), 21, Retro.GREEN)
	tip.text = GameData.BOSS_TIPS[legend.build]
	add.call(tip)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	outer.add_child(buttons)
	var back := Button.new()
	back.text = "Not yet"
	back.custom_minimum_size = Vector2(0, 84)
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back.pressed.connect(_briefing.queue_free)
	buttons.add_child(back)
	var go := Button.new()
	go.text = "Fight!"
	go.custom_minimum_size = Vector2(0, 84)
	go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	go.pressed.connect(battle_requested.emit.bind(i))
	buttons.add_child(go)


func _pack_name() -> String:
	return profile.pet_name + "'s pack" if profile.has_pet() else "your pack"


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Retro.INK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	margin.add_theme_constant_override("margin_top", 40)
	add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	margin.add_child(col)

	var title := Label.new()
	title.text = "Liberate %s" % campaign.territories[campaign.home].name
	Retro.title(title, 18)
	title.clip_text = true
	col.add_child(title)
	Retro.text(_status, 22)
	col.add_child(_status)
	var lines: PackedStringArray = []
	if not campaign.legends.is_empty():
		var names: PackedStringArray = []
		for id in campaign.legends:
			names.append(GameData.LEGENDS[id].name)
		lines.append("Lairs in sight: " + ", ".join(names))
	var rumors: PackedStringArray = []
	for r in campaign.rumors():
		rumors.append("%s %d mi %s" % [GameData.LEGENDS[r.id].name, roundi(r.km * 0.621371), r.direction])
	if not rumors.is_empty():
		lines.append("Rumors: " + ", ".join(rumors))
	if not lines.is_empty():
		var legends := Label.new()
		Retro.text(legends, 20, MapView.LAIR)
		legends.text = "\n".join(lines)
		legends.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(legends)
	Retro.text(_event, 22, Retro.ORANGE)
	_event.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_event)

	_map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_map.clip_contents = true
	col.add_child(_map)

	var legend := Label.new()
	legend.text = "Green: yours · Orange: can attack · Purple: legend lair · Red blocks: threat · Drag/pinch to move & zoom"
	Retro.text(legend, 17, Retro.FOG)
	legend.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(legend)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", Retro.box(Retro.NIGHT, Retro.STEEL, Retro.BORDER, 0, 14))
	col.add_child(panel)
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 6)
	panel.add_child(info)
	Retro.title(_info_title, 16, Retro.WHITE)
	_info_title.clip_text = true
	info.add_child(_info_title)
	Retro.text(_info_body, 22)
	_info_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_body.custom_minimum_size = Vector2(0, 52)
	info.add_child(_info_body)
	_action.custom_minimum_size = Vector2(0, 84)
	_action.pressed.connect(_on_action)
	info.add_child(_action)

	var footer := HBoxContainer.new()
	col.add_child(footer)
	var credit := Label.new()
	credit.text = (ZipDB.ATTRIBUTION + "\n" + ZctaDB.ATTRIBUTION) if campaign.uses_zip_data else ""
	Retro.text(credit, 13, Retro.STEEL)
	credit.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	credit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	credit.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	footer.add_child(credit)
	var setup := Button.new()
	var pack := Button.new()
	pack.text = "Pack"
	pack.add_theme_font_size_override("font_size", Retro.px(10))
	pack.pressed.connect(pack_requested.emit)
	footer.add_child(pack)
	var cloud_button := Button.new()
	cloud_button.text = "Cloud"
	cloud_button.add_theme_font_size_override("font_size", Retro.px(10))
	cloud_button.pressed.connect(account_requested.emit)
	footer.add_child(cloud_button)
	setup.text = "Setup"
	setup.add_theme_font_size_override("font_size", Retro.px(10))
	setup.pressed.connect(setup_requested.emit)
	footer.add_child(setup)
