class_name TransferScreen
extends Control

## Trades with teammates (Transfers): offers to answer, offers waiting on a teammate, critters out on
## loan (call them home any time) and critters borrowed (send them back any time). With `offer_id`
## set it starts with sending that critter to a teammate, as a loan or a gift.

signal closed

const CONFIRM_DELAY_MS := 400  # a double tap isn't an answer

var profile: Profile
var offer_id := ""  # a critter to send (from its Details in Pack)

var _list := VBoxContainer.new()
var _status := Label.new()
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
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	margin.add_child(col)
	var title := Retro.title(Label.new(), 20)
	title.text = "Trades"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	Retro.text(_status, 19, Retro.YELLOW)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.visible = false
	col.add_child(_status)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	Retro.touch_scroll(scroll)
	col.add_child(scroll)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 12)
	scroll.add_child(_list)
	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(0, 80)
	back.pressed.connect(closed.emit)
	col.add_child(back)
	var transfers := _transfers()
	if transfers:
		transfers.changed.connect(_on_changed)
		transfers.refresh()
	_on_changed()


func _transfers() -> Node:
	return get_node_or_null("/root/Transfers")


func _me() -> String:
	var cloud := get_node_or_null("/root/Cloud")
	return cloud.user_id() if cloud else ""


## The transfers changed: apply them to the save (this screen has the game's pack), then redraw.
func _on_changed() -> void:
	var transfers := _transfers()
	if transfers and not _busy:
		transfers.reconcile(profile)
	if transfers:
		_say("\n".join(transfers.take_news()))
	_build()


func _say(text: String) -> void:
	if text == "":
		return
	_status.text = text
	_status.visible = true


func _build() -> void:
	for child in _list.get_children():
		child.queue_free()
	var transfers := _transfers()
	if transfers == null:
		return
	var me := _me()
	var any := false
	if offer_id != "" and offer_id in profile.unlocked:
		_offer_section()
		any = true
	var incoming: Array = transfers.incoming()
	var waiting: Array = transfers.rows.filter(func(t: Dictionary) -> bool: return t.status == "offered" and t.from_user == me)
	var lent: Array = transfers.rows.filter(func(t: Dictionary) -> bool: return t.status == "active" and t.from_user == me)
	var borrowed: Array = transfers.rows.filter(func(t: Dictionary) -> bool: return t.status == "active" and t.to_user == me)
	if not incoming.is_empty():
		_heading("Offers for you")
		for t: Dictionary in incoming:
			var block := profile.receive_block(String(t.critter))
			var row := _row("%s offers you their %s (Lv %d) %s." % [t.from_name, _animal(t), transfers.level_in(t),
				"to keep" if t.kind == "gift" else "on loan: they can call it home any time"] + ("\n" + block if block != "" else ""))
			var accept := _action(row, "Accept", func() -> String: return await transfers.answer(profile, t, true))
			accept.disabled = block != ""
			_action(row, "Decline", func() -> String: return await transfers.answer(profile, t, false))
	if not waiting.is_empty():
		_heading("Waiting for an answer")
		for t: Dictionary in waiting:
			var row := _row("Your %s (Lv %d), offered to %s %s." % [_animal(t), transfers.level_in(t), t.to_name,
				"to keep" if t.kind == "gift" else "on loan"])
			_action(row, "Take back", func() -> String: return await transfers.cancel(profile, t))
	if not lent.is_empty():
		_heading("On loan to teammates")
		for t: Dictionary in lent:
			var row := _row("Your %s is with %s: Lv %d now. It comes home with every level it earns." % [_animal(t), t.to_name, transfers.level_in(t)])
			_action(row, "Call home", func() -> String: return await transfers.end_loan(profile, t))
	if not borrowed.is_empty():
		_heading("Borrowed")
		for t: Dictionary in borrowed:
			var row := _row("%s's %s (Lv %d). Its owner keeps its tech tree and trinket." % [t.from_name, _animal(t), profile.level_of(String(t.critter))])
			_action(row, "Send back", func() -> String: return await transfers.end_loan(profile, t))
	any = any or not (incoming.is_empty() and waiting.is_empty() and lent.is_empty() and borrowed.is_empty())
	if not any:
		var none := Retro.text(Label.new(), 20, Retro.FOG)
		none.text = "No trades yet. To lend or give a critter to a teammate, open its Details in Pack."
		none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_list.add_child(none)


## Sending `offer_id`: pick a teammate, then Lend or Give.
func _offer_section() -> void:
	var animal: String = GameData.ANIMALS[offer_id].name
	_heading("Send your %s (Lv %d)" % [animal, profile.level_of(offer_id)])
	var block := profile.transfer_block(offer_id)
	var note := Retro.text(Label.new(), 18, Retro.ORANGE if block != "" else Retro.FOG)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.text = block if block != "" else "Lend: it fights for them, and comes home with the levels it earns whenever you call it. Give: it's theirs for good. Either way they accept first, and its trinket goes with it."
	_list.add_child(note)
	if block != "":
		return
	var team := get_node_or_null("/root/Team")
	var mates: Array = team.info.get("members", []).filter(func(m: Dictionary) -> bool: return String(m.user_id) != _me()) if team else []
	if mates.is_empty():
		var alone := Retro.text(Label.new(), 18, Retro.FOG)
		alone.text = "Nobody else is on your team yet."
		_list.add_child(alone)
	var transfers := _transfers()
	for m: Dictionary in mates:
		var who := String(m.name)
		var row := _row(who)
		for kind: String in ["loan", "gift"]:
			var send := func() -> String:
				var error: String = await transfers.offer(profile, offer_id, String(m.user_id), kind)
				if error == "":
					offer_id = ""
					transfers.take_news()
					_say("%s offered to %s%s. It's out of your pack until they answer." % [animal, who, " on loan" if kind == "loan" else " to keep"])
				return error
			_action(row, "Lend" if kind == "loan" else "Give", send, kind == "gift")


func _heading(text: String) -> void:
	var label := Retro.title(Label.new(), 13, Retro.GOLD)
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_list.add_child(label)


func _animal(t: Dictionary) -> String:
	var id := String(t.critter)
	return GameData.ANIMALS[id].name if GameData.ANIMALS.has(id) else id


## A panel with text and room for buttons; returns the buttons' box.
func _row(text: String) -> HBoxContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", Retro.box(Retro.NIGHT, Retro.STEEL, Retro.BORDER, 0, 10))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	panel.add_child(col)
	var label := Retro.text(Label.new(), 19, Retro.MIST)
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(label)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	col.add_child(buttons)
	_list.add_child(panel)
	return buttons


## A button that runs `act` (returns "" or an error). `sure`: it asks again first.
func _action(row: HBoxContainer, text: String, act: Callable, sure := false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 64)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var asked := [0]
	b.pressed.connect(func() -> void:
		if sure and b.text == text:
			b.text = "Sure? For good"
			asked[0] = Time.get_ticks_msec()
			return
		if sure and Time.get_ticks_msec() - asked[0] < CONFIRM_DELAY_MS:
			return
		if _busy:
			return
		_busy = true
		b.disabled = true
		var error: String = await act.call()
		_busy = false
		if not is_inside_tree():
			return
		if error != "":
			_say(error)
			b.disabled = false
			b.text = text
			return
		_on_changed())
	row.add_child(b)
	return b
