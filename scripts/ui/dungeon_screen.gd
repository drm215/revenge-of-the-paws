class_name DungeonScreen
extends Control

## The region's dungeon: where it is, the depths that pay and what they pay, where a run can start,
## and the deepest packs.

signal closed
## Start a run on this wave.
signal start(wave: int)

var profile: Profile
var region := ""  # whose dungeon (a GameData.DUNGEONS key)

var _content := VBoxContainer.new()
var _board := {}
var _loaded := false


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
	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(0, 84)
	back.pressed.connect(closed.emit)
	col.add_child(back)
	_build()
	var cloud := get_node_or_null("/root/Cloud")
	if cloud and cloud.enabled():
		cloud.sync()  # sends a new record still waiting
		_board = await cloud.dungeon_board(region)
	_loaded = true
	if is_inside_tree():
		_build()


func _build() -> void:
	for child in _content.get_children():
		child.queue_free()
	var dungeon := GameData.dungeon(region)
	if dungeon.is_empty():
		_label("There's no dungeon here.", 20, Retro.ORANGE)
		return
	_label("Dungeon", 20, Retro.GOLD, true)
	_label(dungeon.name, 14, Retro.CYAN, true)
	_label(dungeon.lore, 20, Retro.FOG)
	_label("Endless waves, each tougher than the last; every %d waves another Brute joins. Clear a depth for the first time to claim what it holds. Leave between waves or fall: you keep everything you won. Free: no map turn, no injuries. %s fight on home ground here." % [
		GameData.DUNGEON_BRUTE_EVERY, _first_upper(GameData.CONDITIONS[dungeon.terrain].who)], 19, Retro.FOG)
	var best := int(profile.dungeon_best.get(region, 0))
	_label("Your deepest: wave %d" % best if best > 0 else "Not explored yet", 16, Retro.WHITE, true)

	_label("Treasure", 13, Retro.GOLD, true)
	var paid := int(profile.dungeon_paid.get(region, 0))
	var depths: Array = GameData.DUNGEON_REWARDS.keys()
	depths.sort()
	for depth: int in depths:
		var done := depth <= paid
		_label("%s Wave %d: %s" % ["CLAIMED" if done else "", depth, GameData.dungeon_reward_text(region, depth)],
			19, Retro.FOG if done else Retro.GREEN if depth == _next_reward(paid) else Retro.WHITE)

	_label("Start a run", 13, Retro.GOLD, true)
	for wave in profile.dungeon_starts(region):
		var b := Button.new()
		b.text = "From wave %d" % wave if wave > 1 else "From the top (wave 1)"
		b.custom_minimum_size = Vector2(0, 76)
		b.pressed.connect(start.emit.bind(wave))
		_content.add_child(b)
	if profile.dungeon_starts(region).size() == 1:
		_label("Clear wave %d to start from there next time." % GameData.DUNGEON_CHECKPOINT, 18, Retro.FOG)

	_label("Deepest packs", 13, Retro.GOLD, true)
	var top: Array = _board.get("top", [])
	if not _loaded:
		_label("Asking around...", 19, Retro.CYAN)
	elif top.is_empty():
		_label("Nobody yet. Log in from Cloud to get on the board." if _board.is_empty() else "Nobody yet. Be the first!", 19, Retro.FOG)
	var mine := profile.siege_name()
	for i in top.size():
		var row: Dictionary = top[i]
		_label("%d. %s  wave %d" % [i + 1, row.name, int(row.best)], 20, Retro.YELLOW if row.name == mine else Retro.MIST)


func _first_upper(text: String) -> String:
	return text.left(1).to_upper() + text.substr(1)


func _next_reward(paid: int) -> int:
	var depths: Array = GameData.DUNGEON_REWARDS.keys()
	depths.sort()
	for depth: int in depths:
		if depth > paid:
			return depth
	return -1


func _label(text: String, font_size: int, color: Color, is_title := false) -> Label:
	var label := Retro.title(Label.new(), font_size, color) if is_title else Retro.text(Label.new(), font_size, color)
	label.text = text.strip_edges()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(label)
	return label
