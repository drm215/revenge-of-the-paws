class_name AccountScreen
extends Control

## Cloud save account: log in or create one (email + password), see sync status, sync now, log out.

signal closed

var _content := VBoxContainer.new()
var _status := Label.new()
var _email := LineEdit.new()
var _password := LineEdit.new()
var _code := LineEdit.new()
var _team_status := Label.new()


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
	var team := get_node_or_null("/root/Team")
	if team:
		team.changed.connect(_build)
	_build()


func _cloud() -> Node:
	return get_node_or_null("/root/Cloud")


func _build() -> void:
	for child in _content.get_children():
		if child in [_status, _email, _password, _code, _team_status]:
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

	Retro.text(_team_status, 19, Retro.ORANGE)
	_team_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	Retro.text(_status, 20, Retro.CYAN)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.text = cloud.status if cloud else ""

	if cloud == null or not cloud.enabled():
		var off := Retro.text(Label.new(), 20, Retro.ORANGE)
		off.text = "Cloud saves aren't set up in this build yet."
		off.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_content.add_child(off)
	elif cloud.signed_in() and cloud.reset_pending:
		var who := Retro.text(Label.new(), 22, Retro.WHITE)
		who.text = "New password for %s" % cloud.email
		who.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_content.add_child(who)
		_add_password_field("New password (6+ characters)")
		_content.add_child(_status)
		_content.add_child(_button("Save password", _save_password))
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
		_team_section()
	else:
		_email.placeholder_text = "Email"
		_email.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_EMAIL_ADDRESS
		_email.custom_minimum_size = Vector2(0, 64)
		_email.add_theme_font_size_override("font_size", Retro.px(14))
		_content.add_child(_email)
		_add_password_field("Password (6+ characters)")
		_content.add_child(_status)
		_content.add_child(_button("Log in", _submit.bind(false)))
		_content.add_child(_button("Create account", _submit.bind(true)))
		_content.add_child(_button("Forgot password?", _forgot))

	_content.add_child(Control.new())
	_content.add_child(_button("Back", closed.emit))


## Teams: create one, join with a code, or see who's on yours and leave.
func _team_section() -> void:
	var team := get_node_or_null("/root/Team")
	if team == null:
		return
	_content.add_child(Retro.title(Label.new(), 14, Retro.GOLD))
	_content.get_child(-1).text = "Team"
	var profile := Profile.load_saved()
	if profile == null or profile.zip == "":
		_note("Teams play on real ZIP maps: set up a US ZIP code first (Setup on the map).", Retro.FOG)
		return
	if team.on_team():
		_note("Team code: %s  (share it: up to %d players)" % [team.info.code, team.MAX_MEMBERS], Retro.WHITE)
		for m: Dictionary in team.info.get("members", []):
			_note("• %s, %s" % [m.name, ZipDB.lookup(String(m.zip)).get("place", m.zip)], Retro.CYAN)
		_note("You share one map built from all your homes, and each keep your own critters. Liberating is shared; whoever liberates a territory gets its survivor and trinket.", Retro.FOG)
		_content.add_child(_team_status)
		var leave := _button("Leave team", Callable())
		leave.pressed.connect(func() -> void:
			if leave.text == "Leave team":
				leave.text = "Tap again to leave (your solo map comes back)"
				return
			_team_status.text = "Leaving..."
			var error: String = await team.leave()
			_team_status.text = error
			_build())
		_content.add_child(leave)
	else:
		_note("Play with friends: one shared map built from all your homes, each with your own critters. Liberating is shared; whoever liberates a territory gets its survivor and trinket.", Retro.FOG)
		_content.add_child(_team_status)
		_content.add_child(_button("Create a team", func() -> void:
			_team_status.text = "Creating..."
			var error: String = await team.create(profile)
			_team_status.text = error
			_build()))
		_code.placeholder_text = "Team code"
		_code.custom_minimum_size = Vector2(0, 64)
		_code.add_theme_font_size_override("font_size", Retro.px(14))
		_content.add_child(_code)
		_content.add_child(_button("Join team", func() -> void:
			if _code.text.strip_edges() == "":
				_team_status.text = "Enter the code a teammate shared."
				return
			_team_status.text = "Joining..."
			var error: String = await team.join(_code.text, profile)
			_team_status.text = error
			if error == "":
				_code.text = ""
			_build()))


func _note(text: String, color: Color) -> void:
	var label := Retro.text(Label.new(), 19, color)
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(label)


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
		var team := get_node_or_null("/root/Team")
		if team:
			team.refresh()  # this account may already be on a team (made on another device)


func _add_password_field(hint: String) -> void:
	_password.placeholder_text = hint
	_password.secret = true
	_password.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_PASSWORD
	_password.custom_minimum_size = Vector2(0, 64)
	_password.add_theme_font_size_override("font_size", Retro.px(14))
	_content.add_child(_password)


func _forgot() -> void:
	var user_email := _email.text.strip_edges()
	if user_email == "":
		_status.text = "Enter your email above, then tap Forgot password? again."
		return
	_status.text = "Sending..."
	var result: String = await _cloud().send_reset(user_email)
	_status.text = result if result != "" else "If %s has an account, a reset link is on its way. Open it on this device." % user_email


func _save_password() -> void:
	if _password.text.length() < 6:
		_status.text = "Use at least 6 characters."
		return
	_status.text = "Saving..."
	var result: String = await _cloud().set_password(_password.text)
	if result != "":
		_status.text = result
		return
	_password.text = ""
	_build()


func _button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 76)
	b.pressed.connect(action)
	return b
