class_name AccountScreen
extends Control

## Cloud save account: log in or create one (email + password), see sync status, sync now, log out.

signal closed

var _content := VBoxContainer.new()
var _status := Label.new()
var _email := LineEdit.new()
var _password := LineEdit.new()


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
	_content.add_theme_constant_override("separation", 12)
	margin.add_child(_content)
	var cloud := _cloud()
	if cloud:
		cloud.status_changed.connect(func(_t: String) -> void: _status.text = cloud.status)
	_build()


func _cloud() -> Node:
	return get_node_or_null("/root/Cloud")


func _build() -> void:
	for child in _content.get_children():
		if child in [_status, _email, _password]:
			_content.remove_child(child)  # reused across rebuilds
		else:
			child.queue_free()
	var cloud := _cloud()
	var title := Retro.title(Label.new(), 20)
	title.text = "Cloud save"
	_content.add_child(title)
	var intro := Retro.text(Label.new(), 21)
	intro.text = "Keep your pack safe and play on any device. Your game uploads automatically after every save; log in on another phone or computer to pick it up."
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(intro)

	Retro.text(_status, 20, Retro.CYAN)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.text = cloud.status if cloud else ""

	if cloud == null or not cloud.enabled():
		var off := Retro.text(Label.new(), 20, Retro.ORANGE)
		off.text = "Cloud saves aren't set up in this build yet."
		off.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_content.add_child(off)
	elif cloud.signed_in():
		var who := Retro.text(Label.new(), 22, Retro.WHITE)
		who.text = "Signed in as %s" % cloud.email
		who.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_content.add_child(who)
		if cloud.last_synced_unix > 0.0:
			var when := Retro.text(Label.new(), 18, Retro.FOG)
			when.text = "Last synced: " + Time.get_datetime_string_from_unix_time(int(cloud.last_synced_unix + Time.get_time_zone_from_system().bias * 60), true)
			_content.add_child(when)
		_content.add_child(_status)
		_content.add_child(_button("Sync now", func() -> void:
			_status.text = "Syncing..."
			await cloud.sync()
			_build()))
		_content.add_child(_button("Log out", func() -> void:
			cloud.log_out()
			_build()))
	else:
		_email.placeholder_text = "Email"
		_email.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_EMAIL_ADDRESS
		_email.custom_minimum_size = Vector2(0, 64)
		_email.add_theme_font_size_override("font_size", Retro.px(14))
		_content.add_child(_email)
		_password.placeholder_text = "Password (6+ characters)"
		_password.secret = true
		_password.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_PASSWORD
		_password.custom_minimum_size = Vector2(0, 64)
		_password.add_theme_font_size_override("font_size", Retro.px(14))
		_content.add_child(_password)
		_content.add_child(_status)
		_content.add_child(_button("Log in", _submit.bind(false)))
		_content.add_child(_button("Create account", _submit.bind(true)))

	_content.add_child(Control.new())
	_content.add_child(_button("Back", closed.emit))


func _submit(create: bool) -> void:
	var cloud := _cloud()
	var user_email := _email.text.strip_edges()
	if user_email == "" or _password.text.length() < 6:
		_status.text = "Enter your email and a password of at least 6 characters."
		return
	_status.text = "Creating your account..." if create else "Logging in..."
	var result: String
	if create:
		result = await cloud.sign_up(user_email, _password.text)
	else:
		result = await cloud.log_in(user_email, _password.text)
	if result == "CONFIRM":
		_status.text = "Check your email to confirm your account, then come back and log in."
	elif result != "":
		_status.text = result
	else:
		_password.text = ""
		_build()


func _button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 76)
	b.pressed.connect(action)
	return b
