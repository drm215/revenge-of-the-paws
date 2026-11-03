class_name PartnerScreen
extends Control

## After a new game's setup: invite a partner (a team for this game, with a code to share), join a
## partner's game with their code, or play solo. A team can still be set up later from Cloud.

signal done
## Log in or create an account first.
signal account_requested

var profile: Profile

var _content := VBoxContainer.new()
var _status := Label.new()
var _code := LineEdit.new()
var _invited := ""  # the code to share once a team was made


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
	_content.add_theme_constant_override("separation", 14)
	margin.add_child(_content)
	Retro.text(_status, 19, Retro.ORANGE)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_code.placeholder_text = "Partner's team code"
	_code.custom_minimum_size = Vector2(0, 72)
	_build()


func _team() -> Node:
	return get_node("/root/Team")


func _build() -> void:
	for child in _content.get_children():
		if child in [_status, _code]:
			_content.remove_child(child)
		else:
			child.queue_free()
	var title := Retro.title(Label.new(), 18)
	title.text = "Play with a partner?"
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(title)

	if _invited != "":
		_note("Your team code:", Retro.MIST)
		var code := Retro.title(Label.new(), 26, Retro.GOLD)
		code.text = _invited
		code.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_content.add_child(code)
		_note("Share it with up to 3 friends. They start a new game, choose Join a partner, and enter it: their homes join your map and you liberate it together. You can find the code again under Cloud.", Retro.FOG)
		_content.add_child(_button("Start playing", done.emit))
		return

	_note("Share this new game's map with up to 3 friends: you liberate it together, each with your own critters. Or play solo; you can invite someone later from Cloud.", Retro.FOG)
	var cloud := get_node_or_null("/root/Cloud")
	if profile.zip == "":
		_note("Partners play on real ZIP maps: this game uses a region, so it's solo.", Retro.FOG)
	elif cloud == null or not cloud.enabled():
		_note("Playing with a partner needs cloud saves, which aren't set up in this build.", Retro.FOG)
	elif not cloud.signed_in():
		_note("Log in (or create a free account) to play with a partner.", Retro.MIST)
		_content.add_child(_button("Log in or create an account", account_requested.emit))
	else:
		_content.add_child(_button("Invite a partner", func() -> void:
			_status.text = "Making your team..."
			var error: String = await _team().create(profile)
			_status.text = error
			if error == "":
				_invited = String(_team().info.code)
			_build()))
		_content.add_child(_code)
		_content.add_child(_button("Join a partner", func() -> void:
			if _code.text.strip_edges() == "":
				_status.text = "Enter the code your partner shared."
				return
			_status.text = "Joining..."
			var error: String = await _team().join(_code.text, profile)
			_status.text = error
			if error == "":
				done.emit()))
	_content.add_child(_status)
	_content.add_child(Control.new())
	_content.add_child(_button("Play solo", done.emit))


func _note(text: String, color: Color) -> void:
	var label := Retro.text(Label.new(), 20, color)
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(label)


func _button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 80)
	b.pressed.connect(action)
	return b
