class_name MapScreen
extends Control

## Campaign map: pick a neighboring territory to attack, or answer a zombie counterattack.
## Lairs open a briefing on their legend before the fight.

signal battle_requested(index: int)
signal patrol_requested(index: int)
signal rest_requested
signal setup_requested
signal pack_requested
signal stable_requested
signal account_requested
signal siege_requested
signal chat_requested
signal auto_toggled

var campaign: Campaign
var profile: Profile

var _map := MapView.new()
var _status := Label.new()
var _event := Label.new()
## The latest news and the team feed scroll in a short box, so the map keeps its room.
const NEWS_MAX_HEIGHT := 190.0
var _news := ScrollContainer.new()
var _news_box := VBoxContainer.new()
var _info_title := Label.new()
var _info_body := Label.new()
var _action := Button.new()
var _ping := Button.new()  # team: point teammates at the selected territory
var _chat_button: Button
var _briefing: Control


func _ready() -> void:
	_build_ui()
	_map.campaign = campaign
	var chat := get_node_or_null("/root/Chat")
	if chat and campaign.is_team():
		chat.received.connect(_on_chat)
		_on_chat()
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
		_info_body.text = "Under attack! Lv %d · threat %d. Lose this fight and the territory falls." % [campaign.territory_level(i), t.threat]
		_action.text = "Defend!"
	elif campaign.home_owner(i) != "":
		_info_body.text = "%s's home: your teammate's pack began here.\nIt links your shared land like your own home does." % campaign.home_owner(i)
		_action.visible = false
	elif i == campaign.home:
		_info_body.text = "Home. Where %s began.\nRest here to heal injuries and clear fatigue (takes a turn)." % _pack_name()
		_action.text = "Rest"
		_action.visible = true
		_action.set_meta("mode", "rest")
	elif t.owned and campaign.is_cut_off(i):
		var left := campaign.turns_until_lost(i)
		_info_body.text = "CUT OFF from home: no held bonus, and you can't attack from here. Falls to the horde in %d turn%s unless you retake the land linking it home." % [left, "" if left == 1 else "s"]
		_action.text = "Patrol"
		_action.visible = true
		_action.set_meta("mode", "patrol")
	elif t.owned:
		_info_body.text = "Liberated. Survivors here reinforce your pack.\nPatrol for an easier fight (threat %d) that earns XP." % maxi(1, t.threat - 1)
		var chain := campaign.cut_by(i)
		if chain > 0:
			_info_body.text += "\nChokepoint: lose it and %d territor%s are cut off from home." % [chain, "y" if chain == 1 else "ies"]
		_action.text = "Patrol"
		_action.visible = true
		_action.set_meta("mode", "patrol")
	else:
		var cfg := campaign.battle_config(i)
		var tougher := roundi((campaign.zombie_strength(t.threat) - 1.0) * 100)
		_info_body.text = "Lv %d · threat %d · %d wave%s%s" % [
			campaign.territory_level(i), t.threat, cfg.waves.size(), "" if cfg.waves.size() == 1 else "s",
			(" · zombies +%d%%" % tougher) if tougher > 0 else ""]
		if t.failed_attacks > 0:
			_info_body.text += " · horde thinned to %d%%" % roundi(t.horde_strength() * 100)
		if campaign.territory_level(i) > campaign.base_level(i):
			_info_body.text += "\nThe horde has grown to match your pack (Lv %d here before)." % campaign.base_level(i)
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
			_info_body.text += "\nDrops: %s (%s)" % [GameData.trinket(loot).name, GameData.trinket_effects(loot)]
		var cond: Dictionary = GameData.CONDITIONS[t.condition]
		_info_body.text += "\n%s: %s +%d%%." % [cond.name, cond.who, roundi(GameData.CONDITION_BONUS * 100)]
		if t.region != "" and GameData.REGIONS.has(t.region):
			_info_body.text += " Home turf for %s animals." % GameData.REGIONS[t.region].name
		if profile.duties.has("scout"):
			_info_body.text += "\nScouted: " + GameData.waves_text(cfg.waves)
		else:
			_info_body.text += "\nWaves unknown: put a benched animal on scout duty."
		if GameData.AUTO_MODE_ENABLED and profile.auto_battle and t.boss == "":
			_info_body.text += "\nAuto mode takes this one once your leader is Lv %d." % (campaign.base_level(i) + GameData.AUTO_LEVEL_GAP)
		if campaign.is_nest(i):
			_info_body.text += "\nHORDE NEST: spreads toward you every %d turns until liberated." % GameData.MIGRATE_EVERY
		elif campaign.spread.has(t.id):
			_info_body.text += "\nThe horde has spread here: threat +%d." % campaign.spread[t.id]
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
	_fit_news()


## A line under the latest event, e.g. auto mode saying what it's about to fight.
func announce(text: String) -> void:
	_event.text = (_event.text + "\n" + text) if _event.visible else text
	_event.visible = true
	_fit_news()


## The news box is as tall as its text, up to NEWS_MAX_HEIGHT; past that it scrolls.
func _fit_news() -> void:
	await get_tree().process_frame  # labels know their wrapped height once laid out
	if not is_inside_tree():
		return
	var tall := _news_box.get_combined_minimum_size().y
	_news.custom_minimum_size.y = minf(tall, NEWS_MAX_HEIGHT)
	_news.visible = tall > 1.0
	_news.scroll_vertical = 0


## New team chat: unread count on the Chat button, pings outlined on the map.
func _on_chat() -> void:
	var chat := get_node_or_null("/root/Chat")
	if chat == null:
		return
	var unread: int = chat.unread()
	if _chat_button:
		_chat_button.text = "Chat (%d)" % unread if unread > 0 else "Chat"
	_map.pings = chat.recent_pings()
	_map.queue_redraw()


func _on_ping() -> void:
	var t := campaign.territories[_map.selected]
	_ping.disabled = true
	var error: String = await get_node("/root/Chat").send("pinged " + t.full_name(), t.id)
	if not is_inside_tree():
		return
	_ping.disabled = false
	_event.text = error if error != "" else "Pinged %s for your team." % t.full_name()
	_event.visible = true
	_fit_news()


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
		drop.text = "%s: %s. \"%s\"" % [GameData.trinket(loot).name, GameData.trinket_effects(loot), GameData.trinket(loot).flavor]
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
	if campaign.is_team():
		var towns: PackedStringArray = []
		for h in campaign.homes:
			if campaign.territories[h].name not in towns:  # teammates in the same town show it once
				towns.append(campaign.territories[h].name)
		title.text = "Team: " + " & ".join(towns)
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
		lines.append("Rumors from %s: %s" % [campaign.territories[campaign.rumor_origin()].name, ", ".join(rumors)])
	if not lines.is_empty():
		var legends := Label.new()
		Retro.text(legends, 20, MapView.LAIR)
		legends.text = "\n".join(lines)
		legends.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(legends)
	_news.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	Retro.touch_scroll(_news)
	col.add_child(_news)
	_news_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_news_box.add_theme_constant_override("separation", 4)
	_news.add_child(_news_box)
	_news.resized.connect(_fit_news)  # rewrapped at a new width
	Retro.text(_event, 20, Retro.ORANGE)
	_event.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_news_box.add_child(_event)
	if campaign.is_team() and not campaign.feed.is_empty():
		var recent: PackedStringArray = []
		for k in range(campaign.feed.size() - 1, maxi(-1, campaign.feed.size() - 4), -1):
			var entry: Dictionary = campaign.feed[k]
			recent.append("%s: %s" % [String(entry.who).get_slice(" · ", 0), entry.text])
		var team_feed := Label.new()
		Retro.text(team_feed, 19, Retro.CYAN)
		team_feed.text = "Team: " + "\n".join(recent)
		team_feed.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_news_box.add_child(team_feed)

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
	_action.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_action.pressed.connect(_on_action)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	info.add_child(actions)
	actions.add_child(_action)
	_ping.text = "Ping"
	_ping.custom_minimum_size = Vector2(140, 84)
	_ping.visible = campaign.is_team()
	_ping.pressed.connect(_on_ping)
	actions.add_child(_ping)

	# Buttons share one row evenly; the data credit gets its own full-width line below them.
	var footer := HBoxContainer.new()
	col.add_child(footer)
	var credit := Label.new()
	credit.text = (ZipDB.ATTRIBUTION + " · " + ZctaDB.ATTRIBUTION) if campaign.uses_zip_data else ""
	Retro.text(credit, 13, Retro.STEEL)
	credit.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	credit.visible = credit.text != ""
	var setup := Button.new()
	var pack := Button.new()
	pack.text = "Pack"
	pack.add_theme_font_size_override("font_size", Retro.px(14))
	pack.pressed.connect(pack_requested.emit)
	footer.add_child(pack)
	var stable_button := Button.new()
	stable_button.text = "Stable"
	stable_button.add_theme_font_size_override("font_size", Retro.px(14))
	stable_button.pressed.connect(stable_requested.emit)
	footer.add_child(stable_button)
	var siege_button := Button.new()
	siege_button.text = "Siege"
	siege_button.add_theme_font_size_override("font_size", Retro.px(14))
	siege_button.pressed.connect(siege_requested.emit)
	footer.add_child(siege_button)
	if campaign.is_team():
		_chat_button = Button.new()
		_chat_button.text = "Chat"
		_chat_button.add_theme_font_size_override("font_size", Retro.px(14))
		_chat_button.pressed.connect(chat_requested.emit)
		footer.add_child(_chat_button)
	var cloud_button := Button.new()
	cloud_button.text = "Cloud"
	cloud_button.add_theme_font_size_override("font_size", Retro.px(14))
	cloud_button.pressed.connect(account_requested.emit)
	footer.add_child(cloud_button)
	if GameData.AUTO_MODE_ENABLED:
		var auto := Button.new()
		auto.text = "Auto: " + ("On" if profile.auto_battle else "Off")
		auto.add_theme_font_size_override("font_size", Retro.px(14))
		auto.pressed.connect(auto_toggled.emit)
		footer.add_child(auto)
	setup.text = "Setup"
	setup.add_theme_font_size_override("font_size", Retro.px(14))
	setup.pressed.connect(setup_requested.emit)
	footer.add_child(setup)
	for button in footer.get_children():
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size = Vector2(0, 56)
	col.add_child(credit)
