class_name HistoryList
extends VBoxContainer

## Older cloud copies of a saved game or a team map (server/history.sql), each with Restore, which
## asks again before it acts. Shown under a "Show older copies" link; loads when first opened.

## A copy was put back.
signal restored

const CONFIRM_DELAY_MS := 400  # a double tap isn't an answer

var _load: Callable  # () -> Array of {id, saved_at (unix), summary}
var _restore: Callable  # (id: int) -> String ("" or an error)
var _sure_text := ""
var _toggle := Button.new()
var _rows := VBoxContainer.new()
var _status := Label.new()
var _open := false


## `title`: the link ("Older copies in the cloud"); `sure`: what Restore says before it acts.
func setup(title: String, sure: String, loader: Callable, restorer: Callable) -> HistoryList:
	_load = loader
	_restore = restorer
	_sure_text = sure
	_toggle.text = title
	return self


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	_toggle.flat = true
	_toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_toggle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toggle.add_theme_color_override("font_color", Retro.CYAN)
	_toggle.add_theme_font_size_override("font_size", Retro.px(15))
	_toggle.pressed.connect(_flip)
	add_child(_toggle)
	_rows.add_theme_constant_override("separation", 8)
	_rows.visible = false
	add_child(_rows)


func _flip() -> void:
	_open = not _open
	_rows.visible = _open
	if _open:
		await reload()


func reload() -> void:
	for child in _rows.get_children():
		if child != _status:
			child.queue_free()
	if not _status.get_parent():
		Retro.text(_status, 17, Retro.FOG)
		_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_rows.add_child(_status)
	_status.text = "Looking..."
	_status.visible = true
	var copies: Array = await _load.call()
	if not is_instance_valid(self):
		return
	_status.text = "No older copies yet: the cloud keeps one every 20 minutes of play, for 30 days." if copies.is_empty() else ""
	_status.visible = copies.is_empty()
	for copy: Dictionary in copies:
		_rows.add_child(_row(copy))


func _row(copy: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var label := Retro.text(Label.new(), 16, Retro.MIST)
	label.text = "%s\n%s" % [SaveScreen._when(int(copy.saved_at)), copy.summary]
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var b := Button.new()
	b.text = "Restore"
	b.custom_minimum_size = Vector2(150, 56)
	b.add_theme_font_size_override("font_size", Retro.px(14))
	var asked := [0]
	b.pressed.connect(func() -> void:
		if b.text == "Restore":
			b.text = "Sure?"
			asked[0] = Time.get_ticks_msec()
			label.text = "%s\n%s" % [SaveScreen._when(int(copy.saved_at)), _sure_text]
			return
		if Time.get_ticks_msec() - asked[0] < CONFIRM_DELAY_MS:
			return
		b.disabled = true
		b.text = "..."
		var error: String = await _restore.call(int(copy.id))
		if not is_instance_valid(self):
			return
		if error != "":
			b.disabled = false
			b.text = "Restore"
			label.text = error
			return
		restored.emit())
	row.add_child(b)
	return row
