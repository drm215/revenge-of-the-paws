class_name Onboarding
extends Control

## First-launch setup: home ZIP code (or region outside the US) → real-life pet → local survivors.
## Emits the finished Profile.

signal finished(profile: Profile)

const GOLD := Retro.GOLD

## Optional existing profile to edit instead of starting blank.
var initial: Profile

var _profile := Profile.new()
var _pet_decided := false
var _detected_region := ""
var _use_zip := true
var _content := VBoxContainer.new()
var _next_button: Button
var _zip_result: Label


func _ready() -> void:
	_detected_region = Profile.detect_region()
	if initial:
		_profile.region = initial.region
		_profile.zip = initial.zip
		_profile.town = initial.town
		_profile.pet_species = initial.pet_species
		_profile.pet_name = initial.pet_name
		_profile.team = initial.team.duplicate()
		_profile.xp = initial.xp.duplicate()
		_profile.unlocked = initial.unlocked.duplicate()
		_profile.trinkets = initial.trinkets.duplicate()
		_profile.equipped = initial.equipped.duplicate()
		_profile.tree = initial.tree.duplicate(true)
		_profile.injuries = initial.injuries.duplicate()
		_profile.fatigue = initial.fatigue.duplicate()
		_profile.duties = initial.duties.duplicate()
		_pet_decided = true
		_use_zip = initial.zip != ""
	else:
		_profile.region = _detected_region
		_use_zip = _detected_region.begins_with("na_")
	_build_frame()
	_show_home()


# --- Steps ------------------------------------------------------------------------------------

func _show_home() -> void:
	if _use_zip:
		_show_zip()
		return
	_clear()
	_profile.zip = ""
	if GameData.REGIONS[_profile.region].get("us", false):
		_profile.region = _detected_region
	_heading("Where do you live?",
		"The world has ended. Your story starts at home, and the animals that survived near you will fight at your side.")
	for region_id in GameData.REGIONS:
		var region: Dictionary = GameData.REGIONS[region_id]
		if region.get("us", false):
			continue
		var sub: String = region.blurb + ("  (detected)" if region_id == _detected_region else "")
		_content.add_child(_choice(region.name, sub, _profile.region == region_id, func() -> void:
			_profile.region = region_id
			_show_home()))

	_label("Your town (optional)", 18, Retro.MIST)
	var town := _line_edit(_profile.town, "e.g. Springfield")
	town.text_changed.connect(func(t: String) -> void: _profile.town = t.strip_edges())
	_content.add_child(_link("In the US? Use your ZIP code instead", func() -> void:
		_use_zip = true
		_show_home()))
	_nav(Callable(), "Next", _show_pet)


func _show_zip() -> void:
	_clear()
	_heading("Where do you live?",
		"The world has ended, and the dead are shambling through your actual neighborhood. Enter your ZIP code: that's where your fight begins.")
	var edit := _line_edit(_profile.zip, "e.g. 10001")
	edit.max_length = 5
	edit.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	edit.add_theme_font_size_override("font_size", Retro.px(26))
	edit.text_changed.connect(_on_zip_changed)
	_zip_result = _label("", 18, GOLD)
	_zip_result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(_link("Not in the US? Choose your region", func() -> void:
		_use_zip = false
		_show_home()))
	_next_button = _nav(Callable(), "Next", _show_pet)
	_on_zip_changed(_profile.zip)
	if _profile.zip == "":
		edit.call_deferred("grab_focus")


func _on_zip_changed(text: String) -> void:
	var zip := text.strip_edges()
	var info := ZipDB.lookup(zip) if zip.length() == 5 else {}
	_next_button.disabled = info.is_empty()
	if info.is_empty():
		_profile.zip = ""
		_zip_result.text = "" if zip.length() < 5 else "We couldn't find that ZIP code."
		_zip_result.add_theme_color_override("font_color", Retro.PINK)
		return
	_profile.zip = zip
	_profile.town = info.place
	_profile.region = info.region
	var region: Dictionary = GameData.REGIONS[info.region]
	var names: PackedStringArray = []
	for id in region.animals:
		names.append(GameData.ANIMALS[id].name)
	_zip_result.text = "%s, %s · %s\nSurvivors nearby: %s" % [info.place, info.state, region.name, ", ".join(names)]
	_zip_result.add_theme_color_override("font_color", GOLD)


func _show_pet() -> void:
	_clear()
	_heading("Do you have a pet at home?",
		"Your real-life pet made it through with you. Pets lead the pack: they're %d%% stronger, and their leadership aura gives every other animal +%d%% ATK and DEF." % [
			roundi((GameData.PET_STAT_MULT - 1.0) * 100), roundi(GameData.LEADER_AURA * 100)])
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	_content.add_child(grid)
	for species in GameData.PETS:
		var pet: Dictionary = GameData.PETS[species]
		grid.add_child(_choice(pet.name, "%s · %s" % [pet.role, pet.desc],
			_pet_decided and _profile.pet_species == species, _pick_pet.bind(species)))
	_content.add_child(_choice("No pet", "Your crew is all locals.",
		_pet_decided and not _profile.has_pet(), _pick_pet.bind("")))

	if _profile.has_pet():
		_label("What's their name?", 18, Retro.MIST)
		var name_edit := _line_edit(_profile.pet_name, "Your pet's name")
		name_edit.text_changed.connect(func(t: String) -> void:
			_profile.pet_name = t.strip_edges()
			_next_button.disabled = not _pet_ready())
		if _profile.pet_name == "":
			name_edit.call_deferred("grab_focus")
	_next_button = _nav(_show_home, "Next", _show_team)
	_next_button.disabled = not _pet_ready()


func _show_team() -> void:
	_clear()
	var region: Dictionary = GameData.REGIONS[_profile.region]
	var needed := _profile.locals_needed()
	# Drop picks that no longer fit (region or pet changed).
	var kept: Array[String] = []
	for id in _profile.team:
		if id in region.animals and kept.size() < needed:
			kept.append(id)
	_profile.team = kept

	var who := "They'll follow %s." % _profile.pet_name if _profile.has_pet() else "There's no one else."
	var where: String = ("around " + _profile.town) if _profile.zip != "" else region.name
	_heading("Who survived nearby?", "Pick %d animals from %s. %s" % [needed, where, who])
	if _profile.has_pet():
		var pet: Dictionary = GameData.PETS[_profile.pet_species]
		_content.add_child(_choice(_profile.pet_name, "Leader · %s · %s" % [pet.name, pet.role], true, Callable()))
	for id in region.animals:
		var a: Dictionary = GameData.ANIMALS[id]
		var stats := "HP %d  ATK %d  DEF %d  SPD %d" % [a.hp, a.atk, a.def, a.spd]
		_content.add_child(_choice("%s — %s" % [a.name, a.role], "%s  %s" % [a.desc, stats],
			id in _profile.team, _toggle_animal.bind(id)))
	_label("Chosen %d / %d" % [_profile.team.size(), needed], 18, GOLD)
	var start := _nav(_show_pet, "Start", _finish)
	start.disabled = _profile.team.size() != needed


func _pick_pet(species: String) -> void:
	_pet_decided = true
	_profile.pet_species = species
	if species == "":
		_profile.pet_name = ""
	_show_pet()


func _toggle_animal(id: String) -> void:
	if id in _profile.team:
		_profile.team.erase(id)
	else:
		if _profile.team.size() >= _profile.locals_needed():
			_profile.team.pop_front()
		_profile.team.append(id)
	_show_team()


func _pet_ready() -> bool:
	return _pet_decided and (not _profile.has_pet() or _profile.pet_name != "")


func _finish() -> void:
	_profile.unlock(GameData.REGIONS[_profile.region].animals)
	_profile.save()
	finished.emit(_profile)


# --- Widgets ----------------------------------------------------------------------------------

func _build_frame() -> void:
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
	_content.add_theme_constant_override("separation", 12)
	scroll.add_child(_content)


func _clear() -> void:
	for child in _content.get_children():
		child.queue_free()


func _heading(title: String, body: String) -> void:
	Retro.title(_label(title, 22, GOLD), 22).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var b := _label(body, 22, Retro.MIST)
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(Control.new())  # spacer


func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", Retro.px(font_size))
	l.add_theme_color_override("font_color", color)
	_content.add_child(l)
	return l


func _line_edit(text: String, placeholder: String) -> LineEdit:
	var e := LineEdit.new()
	e.text = text
	e.placeholder_text = placeholder
	e.max_length = 24
	e.custom_minimum_size = Vector2(0, 64)
	_content.add_child(e)
	return e


## A big tappable card with a title and a subtitle that wraps; the card grows to fit its text.
## Pass an invalid Callable for a read-only card.
func _choice(title: String, subtitle: String, selected: bool, on_press: Callable) -> PanelContainer:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(0, 76)
	var normal := Retro.box(Retro.DIRT if selected else Retro.NIGHT, GOLD if selected else Retro.SLATE, Retro.BORDER, 2, 12)
	var hover := Retro.box(Retro.DIRT if selected else Retro.SLATE, GOLD if selected else Retro.FOG, Retro.BORDER, 2, 12)
	card.add_theme_stylebox_override("panel", normal)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 4)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(box)
	var head := Retro.title(Label.new(), 14, GOLD if selected else Retro.WHITE)
	head.text = title
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(head)
	var sub := Retro.text(Label.new(), 18, Retro.FOG)
	sub.text = subtitle
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(sub)

	if on_press.is_valid():
		card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		card.mouse_entered.connect(func() -> void: card.add_theme_stylebox_override("panel", hover))
		card.mouse_exited.connect(func() -> void: card.add_theme_stylebox_override("panel", normal))
		Retro.on_tap(card, on_press)
	else:
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return card


func _link(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.flat = true
	b.add_theme_font_size_override("font_size", Retro.px(11))
	b.add_theme_color_override("font_color", Retro.CYAN)
	b.add_theme_color_override("font_hover_color", Retro.WHITE)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.pressed.connect(on_press)
	return b


## Back/next row. Returns the next button so callers can enable/disable it.
func _nav(back: Callable, next_text: String, next: Callable) -> Button:
	_content.add_child(Control.new())  # spacer
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_content.add_child(row)
	if back.is_valid():
		var b := Button.new()
		b.text = "Back"
		b.custom_minimum_size = Vector2(200, 84)
		b.pressed.connect(back)
		row.add_child(b)
	var n := Button.new()
	n.text = next_text
	n.custom_minimum_size = Vector2(0, 84)
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	n.pressed.connect(next)
	row.add_child(n)
	return n
