class_name SiegeScreen
extends Control

## The weekly siege (GameData.SIEGES): this week's horde, its stages and their rewards, and the top
## packs. Last week's rewards stay claimable for a week.

signal closed

var profile: Profile

var _content := VBoxContainer.new()
var _week := 0
var _boards := {}  # week -> siege_board() result ({} = couldn't reach the cloud)
var _loaded := false
var _message := ""  # what the last claimed reward gave


func _ready() -> void:
	_week = GameData.siege_week(Time.get_unix_time_from_system())
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
	var cloud := _cloud()
	if cloud == null or not cloud.enabled():
		_loaded = true
		_build()
		return
	cloud.sync()  # sends any damage still waiting
	_boards[_week] = await cloud.siege_board(_week)
	if cloud.signed_in():
		_boards[_week - 1] = await cloud.siege_board(_week - 1)
	_loaded = true
	if is_inside_tree():
		_build()


func _cloud() -> Node:
	return get_node_or_null("/root/Cloud")


func _build() -> void:
	for child in _content.get_children():
		child.queue_free()
	var siege := GameData.siege_info(_week)
	_label("Weekly siege", 20, Retro.GOLD, true)
	_label(siege.name, 14, Retro.ORANGE, true)
	_label(siege.lore, 20, Retro.FOG)
	var left := GameData.siege_left(_week, Time.get_unix_time_from_system())
	_label("Ends in %d day%s %d h. A new horde comes every Monday." % [left / 86400, "" if left / 86400 == 1 else "s", left % 86400 / 3600], 19, Retro.FOG)

	var cloud := _cloud()
	var board: Dictionary = _boards.get(_week, {})
	if cloud == null or not cloud.enabled():
		_label("The siege needs cloud saves, which aren't set up in this build.", 20, Retro.ORANGE)
	elif not _loaded:
		_label("Scouting the horde...", 20, Retro.CYAN)
	elif board.is_empty():
		_label("Can't reach the siege right now. Your pack's damage is kept and sent later.", 20, Retro.ORANGE)
	else:
		var total := int(board.total)
		var players := int(board.players)
		var broken := GameData.siege_stage(total, players)
		var last := GameData.SIEGE_STAGES.size() - 1
		var goal := GameData.siege_goal(mini(broken, last), players)
		var floor_at := GameData.siege_goal(broken - 1, players) if broken > 0 else 0
		var bar := ProgressBar.new()
		bar.max_value = maxi(1, goal - floor_at)
		bar.value = clampi(total - floor_at, 0, goal - floor_at)
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 34)
		bar.add_theme_stylebox_override("fill", Retro.box(Retro.RED, Retro.RED, 0, 0, 0))
		bar.add_theme_stylebox_override("background", Retro.box(Retro.NIGHT, Retro.SLATE, 2, 0, 0))
		_content.add_child(bar)
		if broken > last:
			_label("ANNIHILATED! %d damage" % total, 14, Retro.GOLD, true)
		else:
			_label("%d / %d to %s" % [total, goal, String(GameData.SIEGE_STAGES[broken].name).to_upper()], 22, Retro.WHITE)
		for k in GameData.SIEGE_STAGES.size():
			var stage: Dictionary = GameData.SIEGE_STAGES[k]
			var done := k < broken
			_label("%s %s, %d: %s" % ["DONE:" if done else "NEXT:" if k == broken else "Later:", stage.name, GameData.siege_goal(k, players), GameData.siege_reward_text(k)],
				19, Retro.GREEN if done else Retro.WHITE if k == broken else Retro.FOG)
		var waiting: int = cloud.siege_pending(_week)
		_label("%d pack%s fighting · your pack: %d damage%s" % [int(board.players), "" if int(board.players) == 1 else "s",
			int(board.mine), (" (+%d sending)" % waiting) if waiting > 0 else ""], 20, Retro.CYAN)
	_label("Every zombie your pack destroys hits the horde for the territory's threat, in battles and patrols. More packs make it tougher. Everyone who helped claims the rewards of every stage it breaks.", 19, Retro.FOG)
	if cloud and cloud.enabled() and not cloud.signed_in():
		_label("Log in from Cloud on the map to join. Damage your pack deals now is kept and counts once you log in this week.", 20, Retro.YELLOW)

	for week in [_week, _week - 1]:
		_reward_row(week)
	if _message != "":
		_label(_message, 20, Retro.GREEN)

	var top: Array = board.get("top", [])
	if not top.is_empty():
		_label("Top packs", 12, Retro.GOLD, true)
		var mine := profile.siege_name()
		for i in top.size():
			var row: Dictionary = top[i]
			_label("%d. %s  %d" % [i + 1, row.name, int(row.points)], 20, Retro.YELLOW if row.name == mine else Retro.MIST)


## Claim button (or status) for a week with stages broken.
func _reward_row(week: int) -> void:
	var board: Dictionary = _boards.get(week, {})
	if board.is_empty():
		return
	var broken := GameData.siege_stage(int(board.total), int(board.players))
	if broken == 0:
		return
	var which := "this week's" if week == _week else "last week's"
	var unclaimed := broken - profile.siege_claimed_stages(week)
	if unclaimed <= 0:
		_label("Rewards for %s stages broken so far: claimed." % which, 19, Retro.FOG)
	elif int(board.mine) <= 0:
		if week == _week:
			_label("It broke without your pack. Destroy a zombie this week to share the rewards!", 19, Retro.FOG)
	else:
		var b := Button.new()
		b.text = "Claim %s reward%s (%d)" % [which, "" if unclaimed == 1 else "s", unclaimed]
		b.custom_minimum_size = Vector2(0, 80)
		b.pressed.connect(func() -> void:
			_message = profile.claim_siege(week, broken)
			_build())
		_content.add_child(b)


func _label(text: String, font_size: int, color: Color, is_title := false) -> Label:
	var label := Retro.title(Label.new(), font_size, color) if is_title else Retro.text(Label.new(), font_size, color)
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(label)
	return label
