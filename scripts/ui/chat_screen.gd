class_name ChatScreen
extends Control

## Team chat: messages (newest at the bottom), one-tap quick-chat phrases, and a text box.

signal closed

var _list := VBoxContainer.new()
var _scroll := ScrollContainer.new()
var _input := Retro.typing(LineEdit.new())
var _status := Label.new()
var _chat: Node


func _ready() -> void:
	_chat = get_node("/root/Chat")
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
	col.add_theme_constant_override("separation", 10)
	margin.add_child(col)

	var title := Retro.title(Label.new(), 20)
	title.text = "Team chat"
	col.add_child(title)

	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	Retro.touch_scroll(_scroll)
	col.add_child(_scroll)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	_scroll.add_child(_list)

	var quick := GridContainer.new()
	quick.columns = 3
	quick.add_theme_constant_override("h_separation", 8)
	quick.add_theme_constant_override("v_separation", 8)
	col.add_child(quick)
	for phrase: String in _chat.QUICK:
		var b := Button.new()
		b.text = phrase
		b.custom_minimum_size = Vector2(0, 64)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", Retro.px(14))
		b.pressed.connect(_send.bind(phrase))
		quick.add_child(b)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	col.add_child(row)
	_input.placeholder_text = "Message your team"
	_input.max_length = _chat.MAX_LENGTH
	_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input.custom_minimum_size = Vector2(0, 72)
	_input.add_theme_font_size_override("font_size", Retro.px(16))
	_input.text_submitted.connect(func(_t: String) -> void: _send(_input.text))
	row.add_child(_input)
	var send := Button.new()
	send.text = "Send"
	send.custom_minimum_size = Vector2(150, 72)
	send.pressed.connect(func() -> void: _send(_input.text))
	row.add_child(send)

	Retro.text(_status, 19, Retro.ORANGE)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_status)
	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(0, 76)
	back.pressed.connect(closed.emit)
	col.add_child(back)

	_chat.received.connect(_show_messages)
	_show_messages()
	_chat.poll()


func _show_messages() -> void:
	for child in _list.get_children():
		child.queue_free()
	if _chat.messages.is_empty():
		var hint := Retro.text(Label.new(), 20, Retro.FOG)
		hint.text = "No messages yet. Say hi, or tap a quick message below. Ping a territory from the map to point your team at it."
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_list.add_child(hint)
	var mine: String = get_node("/root/Cloud").user_id()
	for m: Dictionary in _chat.messages:
		var who := String(m.name).get_slice(" · ", 0).replace("[", "[lb]")
		var line := RichTextLabel.new()
		line.bbcode_enabled = true
		line.fit_content = true
		line.scroll_active = false
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_theme_font_override("normal_font", Retro.body_font())
		line.add_theme_font_override("bold_font", Retro.body_font())
		line.add_theme_font_size_override("normal_font_size", Retro.px(16))
		line.add_theme_font_size_override("bold_font_size", Retro.px(16))
		var color := Retro.GOLD if String(m.user_id) == mine else Retro.CYAN
		var body := String(m.body).replace("[", "[lb]")  # show typed brackets as text, not markup
		if String(m.get("ping", "")) != "":
			line.text = "[color=#%s]%s %s[/color]" % [Retro.CYAN.to_html(false), who, body]
		else:
			line.text = "[color=#%s][b]%s:[/b][/color] %s" % [color.to_html(false), who, body]
		_list.add_child(line)
	_chat.mark_read()
	_scroll_to_end.call_deferred()


func _scroll_to_end() -> void:
	await get_tree().process_frame
	_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)


func _send(text: String) -> void:
	_status.text = "Sending..."
	var error: String = await _chat.send(text)
	_status.text = error
	if error == "" and text == _input.text:
		_input.text = ""
