extends Node

## Critter transfers between teammates (autoload "Transfers", server/transfers.sql). A player offers
## a critter to a teammate as a gift (for good) or a loan; the teammate accepts or declines; a loan
## ends whenever the owner calls it back or the borrower sends it back. The server only records who
## agreed to what: each game applies the outcome to its own save in reconcile(), which the map runs
## whenever the transfers change. A critter leaves its owner's pack as soon as it's offered (so it
## can't fight in two packs), and the owner's save keeps a copy until it's back or gone. A loan
## comes back with the XP it earned (never less than it left with) and the tech tree they last
## picked: both of them can (set_gear, set_tree; the owner's change wins if both change it between
## check-ins). Its trinket is always the owner's pick.

## The team's transfers changed (a check-in, or this player's own answer): the map reconciles.
signal changed

## Tests point this elsewhere.
var state_path := "user://transfers.cfg"
var rows: Array = []  # this player's transfers on the team being played (my_transfers()), oldest first

var _team_id := ""
var _pushed := {}  # transfer id -> the critter data last sent for a loan here
var _news := PackedStringArray()  # what reconcile() did that the player hasn't been told yet
var _sending_tree := {}  # transfer id -> true while this borrower's tree is on its way


func _ready() -> void:
	var team := _team()
	if team:
		team.changed.connect(_on_team_changed)
		_team_id = team.team_id
	var cloud := _cloud()
	if cloud:
		cloud.signed_out.connect(func() -> void:
			rows = []
			_news = PackedStringArray())
	_load_state()


func _team() -> Node:
	return get_node_or_null("/root/Team")


func _cloud() -> Node:
	return get_node_or_null("/root/Cloud")


func _me() -> String:
	var cloud := _cloud()
	return cloud.user_id() if cloud else ""


func _on_team_changed() -> void:
	var team := _team()
	if team.team_id == _team_id:
		return
	_team_id = team.team_id
	rows = []
	_store_state()
	changed.emit()
	refresh()


## Transfers from a check-in (Pulse).
func take_pulse(fresh: Variant) -> void:
	if not fresh is Array or fresh == rows:
		return
	rows = fresh
	_store_state()
	changed.emit()


## Asks the server for this player's transfers on the team (when the check-in doesn't carry them).
func refresh() -> void:
	var cloud := _cloud()
	if _team_id == "" or cloud == null or not cloud.signed_in():
		return
	var asked := _team_id
	var r: Dictionary = await cloud.api(HTTPClient.METHOD_POST, "/rest/v1/rpc/my_transfers", {"p_team": asked})
	if r.ok and r.data is Array and asked == _team_id:
		take_pulse(r.data)


## Offers to this player: [{id, from_name, kind, critter, data, ...}].
func incoming() -> Array:
	return rows.filter(func(t: Dictionary) -> bool: return t.status == "offered" and t.to_user == _me())


## The open transfer of critter `id` that this player is part of ({} if none).
func open_for(id: String) -> Dictionary:
	for t: Dictionary in rows:
		if t.critter == id and t.status in ["offered", "active"] and _me() in [t.from_user, t.to_user]:
			return t
	return {}


## The level a transfer's critter is at (from the data it carries).
static func level_in(t: Dictionary) -> int:
	var d: Variant = JSON.parse_string(String(t.get("data", "")))
	return GameData.level_for_xp(int(d.get("xp", 0))) if d is Dictionary else 1


# --- Actions ------------------------------------------------------------------------------------

## Offers critter `id` to teammate `to_user` as a "gift" or a "loan". It leaves the pack at once.
## "" on success, else why not.
func offer(profile: Profile, id: String, to_user: String, kind: String) -> String:
	var block := profile.transfer_block(id)
	if block != "":
		return block
	var data := profile.critter_data(id)
	var r: Dictionary = await _cloud().api(HTTPClient.METHOD_POST, "/rest/v1/rpc/offer_critter",
		{"p_team": _team_id, "p_to": to_user, "p_kind": kind, "p_critter": id, "p_data": data})
	if not r.ok or not r.data is Dictionary:
		return _error(r)
	_take_row(r.data)
	reconcile(profile)  # takes it out of the pack
	return ""


## Accepts or declines offer `row`. A critter of a kind this pack already has can't be accepted.
## "" on success, else why not.
func answer(profile: Profile, row: Dictionary, accept: bool) -> String:
	if accept:
		var block := profile.receive_block(String(row.critter))
		if block != "":
			return block
	var r: Dictionary = await _cloud().api(HTTPClient.METHOD_POST, "/rest/v1/rpc/answer_transfer", {"p_id": int(row.id), "p_accept": accept})
	if not r.ok or not r.data is Dictionary:
		return _error(r)
	_take_row(r.data)
	reconcile(profile)
	return ""


## Takes back an offer nobody has answered yet. "" or why not.
func cancel(profile: Profile, row: Dictionary) -> String:
	var r: Dictionary = await _cloud().api(HTTPClient.METHOD_POST, "/rest/v1/rpc/cancel_transfer", {"p_id": int(row.id)})
	if not r.ok or not r.data is Dictionary:
		return _error(r)
	_take_row(r.data)
	reconcile(profile)
	return ""


## Ends a loan: the owner calls the critter home, or the borrower sends it back. "" or why not.
func end_loan(profile: Profile, row: Dictionary) -> String:
	if String(row.to_user) == _me():
		await _push(profile, row)  # the XP it earned here goes home with it
	var r: Dictionary = await _cloud().api(HTTPClient.METHOD_POST, "/rest/v1/rpc/end_loan", {"p_id": int(row.id)})
	if not r.ok or not r.data is Dictionary:
		return _error(r)
	_take_row(r.data)
	reconcile(profile)
	return ""


## Before leaving the team: every open offer is withdrawn or declined and every loan ends, so no
## critter is left with a player who can no longer reach the team.
func settle_before_leaving(profile: Profile) -> void:
	var me := _me()
	for t: Dictionary in rows.duplicate():
		var fn := ""
		if t.status == "offered":
			fn = "cancel_transfer" if String(t.from_user) == me else "answer_transfer"
		elif t.status == "active":
			fn = "end_loan"
		if fn == "":
			continue
		if fn == "end_loan" and String(t.to_user) == me:
			await _push(profile, t)
		var body := {"p_id": int(t.id)}
		if fn == "answer_transfer":
			body["p_accept"] = false
		var r: Dictionary = await _cloud().api(HTTPClient.METHOD_POST, "/rest/v1/rpc/" + fn, body)
		if r.ok and r.data is Dictionary:
			_take_row(r.data)
	reconcile(profile)


## The owner's view of a critter out on loan (`row`, active): a Profile holding just that critter at
## the level it has reached, with the tree and trinket the owner picked. For the tech tree screen.
func loan_view(profile: Profile, row: Dictionary) -> Profile:
	var id := String(row.critter)
	var home: Dictionary = _parse(String(profile.lent.get(id, {}).get("data", row.data)))
	var away: Dictionary = _parse(String(row.data))
	var view := Profile.new()
	view.region = profile.region
	view.unlocked.assign([id])
	view.xp[id] = maxi(int(home.get("xp", 0)), int(away.get("xp", 0)))
	var nodes: Variant = _gear_tree(row)
	if nodes == null:
		nodes = home.get("tree", [])
	if not (nodes as Array).is_empty():
		view.tree[id] = (nodes as Array).map(func(n: Variant) -> String: return String(n))
	if String(home.get("trinket", "")) != "":
		view.equipped[id] = String(home.trinket)
		view.trinkets.assign([String(home.trinket)])
	if home.get("bonus", {}) is Dictionary and not (home.bonus as Dictionary).is_empty():
		view.bonuses[id] = home.bonus
	return view


## Tech-tree points a critter out on loan has waiting for its owner.
func loan_points(profile: Profile, row: Dictionary) -> int:
	var view := loan_view(profile, row)
	return view.points_left(String(row.critter))


## The trinket a critter out on loan wears ("" if none).
func loan_trinket(profile: Profile, row: Dictionary) -> String:
	return String(_parse(String(profile.lent.get(String(row.critter), {}).get("data", row.data))).get("trinket", ""))


## The owner picks the tech tree and trinket of their critter out on loan (`row`, active). A new
## trinket comes out of the owner's trinkets (a spare copy) and the old one goes back into them. The
## borrower's game takes it on its next check-in. "" or why not.
func set_gear(profile: Profile, row: Dictionary, nodes: Array, trinket: String) -> String:
	var id := String(row.critter)
	if not profile.lent.has(id):
		return "That critter isn't out on loan."
	var old := loan_trinket(profile, row)
	if trinket != old and trinket != "" and profile.trinkets_free(trinket) <= 0:
		return "No spare %s: take it off whoever wears it first." % GameData.trinket(trinket).name
	var gear := JSON.stringify({"tree": nodes, "trinket": trinket}, "", true)
	var r: Dictionary = await _cloud().api(HTTPClient.METHOD_POST, "/rest/v1/rpc/set_loan_gear", {"p_id": int(row.id), "p_gear": gear})
	if not r.ok or not r.data is Dictionary:
		return _error(r)
	var home := _parse(String(profile.lent[id].get("data", row.data)))
	home["id"] = id
	home["tree"] = nodes
	home["trinket"] = trinket
	profile.lent[id]["data"] = JSON.stringify(home, "", true)
	if trinket != old:
		if old != "":
			profile.trinkets.append(old)
		if trinket != "":
			profile.trinkets.erase(trinket)
	profile.save()
	_take_row(r.data)
	return ""


## The tech tree last picked for a loan (`gear`), or null if nobody has picked one since it left.
static func _gear_tree(row: Dictionary) -> Variant:
	var gear := _parse(String(row.get("gear", "")))
	if not gear.has("tree") or not gear.tree is Array:
		return null
	return (gear.tree as Array).map(func(n: Variant) -> String: return String(n))


## The borrower keeps a borrowed critter's tree and trinket in step with the loan: the owner's trinket
## pick; for the tree, a change the owner made wins, else a change made here is sent. Returns what
## to tell the player ("" if nothing changed here).
func _sync_borrowed(profile: Profile, row: Dictionary) -> String:
	var id := String(row.critter)
	var on_loan: Dictionary = profile.borrowed[id]
	var said := ""
	var gear := _parse(String(row.get("gear", "")))
	if gear.has("trinket"):
		var trinket := String(gear.trinket)
		if trinket != String(profile.equipped.get(id, "")):
			if trinket == "":
				profile.equipped.erase(id)
			else:
				profile.equipped[id] = trinket  # (the owner's copy: never in this player's trinkets)
			said = "%s put %s on their %s." % [row.from_name, GameData.trinket(trinket).name if trinket != "" else "no trinket", _name_of(id)]
	var local: Array = Array(profile.tree.get(id, [])).map(func(n: Variant) -> String: return String(n))
	if not on_loan.has("tree"):
		on_loan["tree"] = local  # (borrowed before trees were shared: what's here is what was agreed)
	var synced: Array = on_loan.tree
	var remote: Variant = _gear_tree(row)
	if remote != null and remote != synced:
		on_loan["tree"] = remote
		if remote != local:
			if (remote as Array).is_empty():
				profile.tree.erase(id)
			else:
				profile.tree[id] = (remote as Array).duplicate()  # (its own copy: buying nodes mustn't change what was agreed)
			said =("%s\n" % said if said != "" else "") + "%s changed their %s's tech tree." % [row.from_name, _name_of(id)]
	elif local != synced and not _sending_tree.has(str(int(row.id))):
		_send_tree(profile, row, local)
	return said


func _send_tree(profile: Profile, row: Dictionary, nodes: Array) -> void:
	var tid := str(int(row.id))
	_sending_tree[tid] = true
	var r: Dictionary = await _cloud().api(HTTPClient.METHOD_POST, "/rest/v1/rpc/set_loan_tree",
		{"p_id": int(row.id), "p_tree": JSON.stringify(nodes)})
	_sending_tree.erase(tid)
	if r.ok and r.data is Dictionary:
		var on_loan: Dictionary = profile.borrowed.get(String(row.critter), {})
		if String(on_loan.get("id", "")) == tid:
			on_loan["tree"] = nodes
			profile.save()
		_take_row(r.data)


func _name_of(id: String) -> String:
	return GameData.ANIMALS[id].name if GameData.ANIMALS.has(id) else id


static func _parse(text: String) -> Dictionary:
	var d: Variant = JSON.parse_string(text)
	return d if d is Dictionary else {}


func _error(r: Dictionary) -> String:
	var cloud := _cloud()
	if cloud == null or not cloud.signed_in():
		return "Log in to trade critters."
	return "Can't reach the cloud. Try again." if r.code == 0 else cloud.error_text(r)


func _take_row(row: Dictionary) -> void:
	for i in rows.size():
		if int(rows[i].id) == int(row.id):
			rows[i] = row
			_store_state()
			changed.emit()
			return
	rows.append(row)
	_store_state()
	changed.emit()


# --- Applying them to the save --------------------------------------------------------------------

## Brings `profile` in line with the transfers: critters offered or lent leave the pack, accepted
## ones join, finished loans go home, and declined or cancelled offers come back. Saves if anything
## changed and returns what to tell the player. Also sends a loaned critter's progress to its owner.
func reconcile(profile: Profile) -> PackedStringArray:
	var lines := PackedStringArray()
	var me := _me()
	if profile == null or me == "":
		return lines
	var changed_save := false
	for t: Dictionary in rows:
		var tid := str(int(t.id))
		if tid in profile.transfers_done:
			continue
		var id := String(t.critter)
		var animal: String = GameData.ANIMALS[id].name if GameData.ANIMALS.has(id) else id
		var status := String(t.status)
		if String(t.from_user) == me:
			var mine: Dictionary = profile.lent.get(id, {})
			var here := String(mine.get("id", "")) == tid
			if status in ["offered", "active"]:
				if not here:  # (offered from this save, but the game closed before it took it out)
					profile.lent[id] = {"id": tid, "to": String(t.to_name), "kind": String(t.kind), "state": status,
						"data": profile.critter_data(id) if id in profile.unlocked else String(t.data)}
					if id in profile.unlocked:
						profile.take_out(id)
					changed_save = true
				elif String(mine.get("state", "")) != status:
					mine["state"] = status
					changed_save = true
					if status == "active":
						lines.append("%s took your %s on loan. Call it home from Pack > Trades any time." % [t.to_name, animal])
			elif status == "done":
				profile.lent.erase(id)
				if id not in profile.given:
					profile.given.append(id)
				profile.transfers_done.append(tid)
				changed_save = true
				if here:
					lines.append("%s accepted your %s. It's theirs now." % [t.to_name, animal])
			else:  # declined, cancelled, recalled: it comes home
				var data := String(mine.get("data", t.data)) if here else String(t.data)
				if status == "recalled":
					data = _with_loan_xp(data, String(t.data), _gear_tree(t))
				profile.lent.erase(id)
				profile.transfers_done.append(tid)
				changed_save = true
				if here or id not in profile.unlocked:
					profile.put_in(data)
					lines.append({"declined": "%s said no thanks: your %s is back.", "cancelled": "Your %s stays with you.",
						"recalled": "Your %s is home from %s (Lv %d)."}[status] % (
						[t.to_name, animal] if status == "declined" else [animal] if status == "cancelled" else [animal, t.to_name, profile.level_of(id)]))
		elif String(t.to_user) == me:
			var on_loan: Dictionary = profile.borrowed.get(id, {})
			var holding := String(on_loan.get("id", "")) == tid
			if status == "active":
				if not holding:
					var block := profile.receive_block(id)
					if block == "":
						profile.put_in(String(t.data), tid, String(t.from_name))
						changed_save = true
						lines.append("%s's %s (Lv %d) joins your pack on loan." % [t.from_name, animal, profile.level_of(id)])
					else:  # (a critter of that kind arrived since it was accepted): it goes home
						_cloud().api(HTTPClient.METHOD_POST, "/rest/v1/rpc/end_loan", {"p_id": int(t.id)})
						lines.append("%s's %s went home: %s" % [t.from_name, animal, block])
				else:
					var said := _sync_borrowed(profile, t)
					if said != "":
						changed_save = true
						lines.append(said)
					_push(profile, t)
			elif status == "done":
				profile.transfers_done.append(tid)
				changed_save = true
				profile.put_in(String(t.data))  # (one of that kind already here: the stronger XP stays)
				lines.append("%s gave you their %s (Lv %d)!" % [t.from_name, animal, profile.level_of(id)])
			elif status == "recalled":
				profile.transfers_done.append(tid)
				changed_save = true
				if holding:
					profile.take_out(id)
					lines.append("%s's %s went home." % [t.from_name, animal])
			elif status in ["declined", "cancelled"]:
				profile.transfers_done.append(tid)
				changed_save = true
	if changed_save:
		profile.save()
	_news.append_array(lines)
	return lines


## What happened to this player's critters since last asked (reconcile()'s lines), once.
func take_news() -> PackedStringArray:
	var out := _news
	_news = PackedStringArray()
	return out


## A loaned critter coming home: the owner's copy as it left, with the XP it earned on loan (never
## less than it left with) and the tech tree last picked for it (`tree`, null if none was).
## Injuries and fatigue come from the loan.
static func _with_loan_xp(home: String, loan: String, tree: Variant = null) -> String:
	var a: Variant = JSON.parse_string(home)
	var b: Variant = JSON.parse_string(loan)
	if not a is Dictionary:
		return loan
	if tree != null:
		a["tree"] = tree
	if b is Dictionary:
		a["xp"] = maxi(int(a.get("xp", 0)), int(b.get("xp", 0)))
		for field in ["injuries", "fatigue", "rested"]:
			a[field] = int(b.get(field, 0))
	return JSON.stringify(a, "", true)


## Sends a borrowed critter's progress to the server, if it changed since the last send.
func _push(profile: Profile, t: Dictionary) -> void:
	var id := String(t.critter)
	if not profile.borrowed.has(id):
		return
	var data := profile.critter_data(id)
	var tid := str(int(t.id))
	if data == String(t.data) or data == String(_pushed.get(tid, "")):
		return
	_pushed[tid] = data
	var r: Dictionary = await _cloud().api(HTTPClient.METHOD_POST, "/rest/v1/rpc/update_loan", {"p_id": int(t.id), "p_data": data})
	if not r.ok:
		_pushed.erase(tid)  # try again next time


func _store_state() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("transfers", "team", _team_id)
	cfg.set_value("transfers", "rows", JSON.stringify(rows))
	cfg.save(state_path)


func _load_state() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(state_path) != OK or String(cfg.get_value("transfers", "team", "")) != _team_id:
		return
	var parsed: Variant = JSON.parse_string(String(cfg.get_value("transfers", "rows", "[]")))
	rows = parsed if parsed is Array else []
