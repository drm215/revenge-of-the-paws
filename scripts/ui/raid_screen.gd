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

	_label("Bring %d critters" % GameData.RAID_PICKS, 13, Retro.GOLD, true)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	_content.add_child(grid)
	var options: Array[String] = []
	if profile.has_pet():
		options.append(profile.pet_species)
	for id in profile.active():
		if id not in options:
			options.append(id)
	for id in options:
		var b := Button.new()
		var on := id in _picks
		b.text = "%s Lv %d" % [profile.unit_name(id), profile.level_of(id)]
		b.toggle_mode = true
		b.button_pressed = on
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 64)
		b.add_theme_font_size_override("font_size", Retro.px(16))
		b.toggled.connect(func(_pressed: bool) -> void: _toggle(id))
		grid.add_child(b)

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
