class_name RaidScreen
extends Control

## A legend raid's lobby: who's in, the 3 critters each player brings, ready checks, and Start for
## the player who opened it. Opening it from a lair (`lair` set) opens a new raid there.

signal closed
## The raid started: open the battle.
signal fight

var profile: Profile
var campaign: Campaign
var lair := -1  # a lair to open a new raid on; -1 to join or look at the team's raid

var _content := VBoxContainer.new()
var _status := Label.new()
var _picks: Array[String] = []
var _busy := false


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
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	Retro.touch_scroll(scroll)
	margin.add_child(scroll)
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 10)
	scroll.add_child(_content)
	Retro.text(_status, 19, Retro.ORANGE)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	var r := _raid()
	r.fast = true
	r.changed.connect(_on_changed)
	_picks.assign(_mine_from_raid() if r.is_member() else [])  # nobody starts out picked
	_build()
	if lair >= 0 and r.status() not in ["lobby", "fighting"]:
		_open()


func _exit_tree() -> void:
	_raid().fast = false


func _raid() -> Node:
	return get_node("/root/Raid")


func _on_changed() -> void:
	var r := _raid()
	if r.status() == "fighting" and r.is_member():
		fight.emit()
		return
	_build()


## The critters this player already brought to the lobby.
func _mine_from_raid() -> Array:
	for m: Dictionary in _raid().members():
		if String(m.user_id) == _raid().my_id():
			var p := Profile.from_snapshot(String(m.pack))
			return Array(p.pack_ids()) if p else []
	return []


func _open() -> void:
	var t := campaign.territories[lair]
	_status.text = "Opening the raid..."
	var pack := profile.snapshot(_picks) if _picks.size() == GameData.RAID_PICKS else ""  # picked in the lobby
	var error: String = await _raid().open(t.id, t.boss, t.full_name(), get_node("/root/Team").name_for(profile), pack)
	_status.text = error


func _build() -> void:
	for child in _content.get_children():
		if child != _status:
			child.queue_free()
		else:
			_content.remove_child(child)
	var r := _raid()
	var legend_id := String(r.info.get("legend", campaign.territories[lair].boss if lair >= 0 else ""))
	var legend: Dictionary = GameData.LEGENDS.get(legend_id, {})
	_label("Legend raid", 20, Retro.GOLD, true)
	if not legend.is_empty():
		_label(legend.name, 14, Retro.PURPLE.lightened(0.3), true)
		_label(legend.lore, 19, Retro.FOG)
	_label("Up to %d teammates fight together, %d critters each, each player controlling their own. The legend grows with every player: HP x%.1f / x%.1f / x%.1f for 2 / 3 / 4 players. XP is split; everyone gets the legend's trinket. A player who takes too long has that turn played by the AI." % [
		GameData.RAID_MAX_PLAYERS, GameData.RAID_PICKS, GameData.legend_growth(2).x, GameData.legend_growth(3).x, GameData.legend_growth(4).x], 18, Retro.FOG)

	if r.status() == "fighting":
		_label("This raid is still marked as fighting, but a fight can't be picked up again once it's left. If everyone has left it, call it off so the team can start a new one.", 19, Retro.MIST)
		_content.add_child(_status)
		_content.add_child(_button("Call off this raid", _call_off))
		_content.add_child(_button("Back", closed.emit))
		return
	if r.status() != "lobby":
		_content.add_child(_status)
		if _status.text == "":
			_status.text = "No raid is open right now." if lair < 0 else "Opening the raid..."
		_content.add_child(_button("Back", closed.emit))
		return

	_label("Players (%d / %d)" % [r.members().size(), GameData.RAID_MAX_PLAYERS], 13, Retro.GOLD, true)
	for m: Dictionary in r.members():
		var p := Profile.from_snapshot(String(m.pack))
		var names: PackedStringArray = []
		if p:
			for id in p.pack_ids():
				names.append("%s Lv %d" % [p.unit_name(id), p.level_of(id)])
		var host := " (opened it)" if String(m.user_id) == String(r.info.host) else ""
		_label("%s %s%s: %s" % ["READY" if m.ready else "picking", String(m.name).get_slice(" · ", 0), host, ", ".join(names)],
			19, Retro.GREEN if m.ready else Retro.MIST)

	_label("Bring %d critters (%d / %d)" % [GameData.RAID_PICKS, _picks.size(), GameData.RAID_PICKS], 13, Retro.GOLD, true)
	var cfg := _lair_config()
	var options: Array[String] = []
	if profile.has_pet():
		options.append(profile.pet_species)
	for id in profile.active():
		if id not in options:
			options.append(id)
	for id in options:
		_content.add_child(_pick_tile(id, cfg))
	for line in GameData.bond_lines(_picks, profile.unit_name):
		_label("Bond " + line, 18, Retro.GOLD)

	_content.add_child(_status)
	var me_in: bool = r.is_member()
	var me_ready: bool = me_in and r.members().any(func(m: Dictionary) -> bool: return String(m.user_id) == r.my_id() and m.ready)
	var ready := _button("Not ready" if me_ready else ("I'm ready" if me_in else "Join the raid"), func() -> void:
		_send(not me_ready))
	ready.disabled = _picks.size() != GameData.RAID_PICKS
	_content.add_child(ready)
	if r.is_host():
		var ready_count: int = r.members().filter(func(m: Dictionary) -> bool: return m.ready).size()
		var start := _button("Start the raid (%d player%s)" % [ready_count, "" if ready_count == 1 else "s"], _start)
		start.disabled = not me_ready or _busy  # the opener fights too, so they pick first
		_content.add_child(start)
	else:
		_label("Waiting for the player who opened it to start.", 18, Retro.FOG)
	_content.add_child(_button("Leave the raid" if me_in else "Back", _leave))


## The lair's battle config on this player's map (terrain, region, the waves), for the tiles.
func _lair_config() -> Dictionary:
	var territory := String(_raid().info.get("territory", ""))
	for k in campaign.territories.size():
		if campaign.territories[k].id == territory or (territory == "" and k == lair):
			return campaign.battle_config(k)
	return {}


## One critter that could come: stats, what helps or hurts it in this lair, the zombies it counters,
## and buttons to bring it and to set its row.
func _pick_tile(id: String, cfg: Dictionary) -> Control:
	var on := id in _picks
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", Retro.box(Retro.NIGHT, Retro.GOLD if on else Retro.SLATE, Retro.BORDER, 0, 10))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)
	var sprite := TextureRect.new()
	sprite.texture = load("res://art/pixel/%s.png" % id)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	sprite.custom_minimum_size = Vector2(72, 72)
	sprite.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(sprite)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 3)
	row.add_child(text)
	var unit := profile.build_unit(id)
	var data: Dictionary = GameData.PETS.get(id, GameData.ANIMALS.get(id, {}))
	text.add_child(_line("%s · Lv %d · %s" % [profile.unit_name(id), profile.level_of(id), data.get("role", "")], 12, Retro.GOLD if on else Retro.WHITE, true))
	text.add_child(_line("HP %d  ATK %d  DEF %d  SPD %d" % [unit.max_hp, unit.atk, unit.def, unit.spd], 17, Retro.FOG))
	var perks := GameData.fight_perks(id, cfg)
	if not perks.good.is_empty():
		text.add_child(_line("Here: " + " · ".join(perks.good), 17, Retro.GREEN))
	if not perks.bad.is_empty():
		text.add_child(_line(" · ".join(perks.bad), 17, Retro.PINK))
	var counters := GameData.counters_in(id, cfg.get("waves", []))
	if not counters.is_empty():
		text.add_child(_line("Hits weak spots: " + ", ".join(counters), 17, Retro.CYAN))
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	text.add_child(buttons)
	var bring := Button.new()
	bring.text = "BRINGING" if on else "+ Bring"
	bring.custom_minimum_size = Vector2(0, 52)
	bring.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if on:
		bring.add_theme_color_override("font_color", Retro.YELLOW)
	bring.pressed.connect(_toggle.bind(id))
	buttons.add_child(bring)
	var row_button := Button.new()
	row_button.text = "Row: " + profile.row_of(id).capitalize()
	row_button.custom_minimum_size = Vector2(0, 52)
	row_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row_button.pressed.connect(_switch_row.bind(id))
	buttons.add_child(row_button)
	return panel


## Front or back row for a critter; if this player already readied up, the raid gets the change.
func _switch_row(id: String) -> void:
	profile.toggle_row(id)
	profile.save()
	if _raid().is_member() and _picks.size() == GameData.RAID_PICKS:
		var me_ready: bool = _raid().members().any(func(m: Dictionary) -> bool: return String(m.user_id) == _raid().my_id() and m.ready)
		await _raid().join(get_node("/root/Team").name_for(profile), profile.snapshot(_picks), me_ready)
	_build()


func _line(text: String, font_size: int, color: Color, is_title := false) -> Label:
	var label := Retro.title(Label.new(), font_size, color) if is_title else Retro.text(Label.new(), font_size, color)
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _toggle(id: String) -> void:
	if id in _picks:
		_picks.erase(id)
	elif _picks.size() < GameData.RAID_PICKS:
		_picks.append(id)
	_build()


## Joins (or updates this player's pack and ready state).
func _send(ready: bool) -> void:
	_status.text = "Sending..."
	var error: String = await _raid().join(get_node("/root/Team").name_for(profile), profile.snapshot(_picks), ready)
	_status.text = error


## Fixes the battle for every device: the lair's waves, with zombies caught up to the strongest
## critter any ready raider brings.
func _start() -> void:
	var r := _raid()
	var i := -1
	for k in campaign.territories.size():
		if campaign.territories[k].id == String(r.info.territory):
			i = k
	if i < 0:
		_status.text = "That lair isn't on this map."
		return
	var max_level := 1
	for m: Dictionary in r.members():
		var p := Profile.from_snapshot(String(m.pack))
		if p and m.ready:
			for id in p.pack_ids():
				max_level = maxi(max_level, p.level_of(id))
	_busy = true
	_status.text = "Starting..."
	var error: String = await r.start(campaign.raid_config(i, max_level))
	_busy = false
	_status.text = error


func _call_off() -> void:
	_status.text = "Calling it off..."
	var error: String = await _raid().cancel()
	_status.text = error
	if error == "":
		closed.emit()


func _leave() -> void:
	if _raid().is_member():
		_status.text = "Leaving..."
		var error: String = await _raid().leave()
		_status.text = error
	closed.emit()


func _label(text: String, font_size: int, color: Color, is_title := false) -> Label:
	var label := Retro.title(Label.new(), font_size, color) if is_title else Retro.text(Label.new(), font_size, color)
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(label)
	return label


func _button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 76)
	b.pressed.connect(action)
	return b
