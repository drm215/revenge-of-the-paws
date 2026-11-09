class_name SaveScreen
extends Control

## Shown after the loading screen: pick a saved game, start a new one, or delete one.

signal chosen(id: String)
signal new_game
## Log in to a cloud save (a new device).
signal account_requested

const CONFIRM_DELAY_MS := 400  # "Sure?" only counts once it can have been read

var _list := VBoxContainer.new()


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Retro.INK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	margin.add_theme_constant_override("margin_top", 56)
	add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	margin.add_child(col)

	var title := Retro.title(Label.new(), 22)
	title.text = "Revenge of the Paws"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(title)
	var sub := Retro.text(Label.new(), 22, Retro.FOG)
	sub.text = "Choose a game"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sub)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	Retro.touch_scroll(scroll)
	col.add_child(scroll)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 12)
	scroll.add_child(_list)

	var start := Button.new()
	start.text = "New game"
	start.custom_minimum_size = Vector2(0, 88)
	start.pressed.connect(new_game.emit)
	col.add_child(start)
	var login := Button.new()
	login.text = "Playing on another device? Log in to your cloud save"
	login.flat = true
	login.add_theme_color_override("font_color", Retro.CYAN)
	login.add_theme_font_size_override("font_size", Retro.px(16))
	login.pressed.connect(account_requested.emit)
	col.add_child(login)
	_build()


func _build() -> void:
	for child in _list.get_children():
		child.queue_free()
	var saves := Saves.list()
	if saves.is_empty():
		var none := Retro.text(Label.new(), 21, Retro.MIST)
		none.text = "No saved games yet. Start a new game: your fight begins in your own neighborhood."
		none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_list.add_child(none)
	for info: Dictionary in saves:
		_list.add_child(_card(info))


## One saved game: tap it to play; Delete asks again before it deletes.
func _card(info: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", Retro.box(Retro.NIGHT, Retro.STEEL, Retro.BORDER, 0, 12))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(text)
	var name_label := Retro.title(Label.new(), 13, Retro.GOLD)
	name_label.text = info.title
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(name_label)
	var detail := Retro.text(Label.new(), 19, Retro.MIST)
	detail.text = info.detail
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(detail)
	var when := Retro.text(Label.new(), 17, Retro.FOG)
	when.text = "Last played " + _when(int(info.played))
	text.add_child(when)
	var backup := Saves.backup_info(String(info.id))
	if not backup.is_empty():
		# A cloud copy replaced this game here: its old copy can come back.
		var undo := Button.new()
		undo.text = "Restore the copy from before the last download (%s, %s)" % [backup.detail, _when(int(backup.when))]
		undo.flat = true
		undo.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		undo.alignment = HORIZONTAL_ALIGNMENT_LEFT
		undo.add_theme_color_override("font_color", Retro.CYAN)
		undo.add_theme_font_size_override("font_size", Retro.px(15))
		undo.pressed.connect(func() -> void:
			if not undo.text.begins_with("Sure?"):
				undo.text = "Sure? This replaces the game above with that copy (and backs it up to the cloud)."
				return
			if Saves.restore_backup(String(info.id)):
				var cloud := get_node_or_null("/root/Cloud")
				if cloud:
					cloud.mark_slot_dirty(String(info.id))
			_build())
		text.add_child(undo)
	var buttons := VBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	row.add_child(buttons)
	var play := Button.new()
	play.text = "Play"
	play.custom_minimum_size = Vector2(150, 64)
	play.pressed.connect(chosen.emit.bind(String(info.id)))
	buttons.add_child(play)
	var delete := Button.new()
	delete.text = "Delete"
	delete.custom_minimum_size = Vector2(150, 48)
	delete.add_theme_font_size_override("font_size", Retro.px(15))
	delete.add_theme_color_override("font_color", Retro.PINK)
	var asked := [0]
	delete.pressed.connect(func() -> void:
		if delete.text == "Delete":
			delete.text = "Sure?"
			asked[0] = Time.get_ticks_msec()
			return
		if Time.get_ticks_msec() - asked[0] < CONFIRM_DELAY_MS:
			return  # a double tap isn't an answer
		Saves.delete(String(info.id))
		_build())
	buttons.add_child(delete)
	return panel


## "Nov 2, 8:14 PM" in local time.
static func _when(unix: int) -> String:
	var t := Time.get_datetime_dict_from_unix_time(unix + Time.get_time_zone_from_system().bias * 60)
	var months := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
	var hour := int(t.hour) % 12
	return "%s %d, %d:%02d %s" % [months[int(t.month) - 1], int(t.day), 12 if hour == 0 else hour, int(t.minute), "AM" if int(t.hour) < 12 else "PM"]
