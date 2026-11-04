extends SceneTree

## Ping clearing: Unping, and pings that clear themselves once their job is done.

var _fails := 0


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


func _msg(id: int, ping: String, minutes_ago := 1.0) -> Dictionary:
	return {"id": float(id), "user_id": "u1", "name": "Jack · Appalachia", "body": "x", "ping": ping,
		"created_at": Time.get_datetime_string_from_unix_time(int(Time.get_unix_time_from_system() - minutes_ago * 60))}


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var chat: Node = root.get_node("Chat")
	chat.state_path = "user://unping_chat.cfg"
	chat.messages = [_msg(1, "24224@open"), _msg(2, "24202@attack"), _msg(3, "24210@held"), _msg(4, "99999@open", 30.0)]
	var pings: Dictionary = chat.recent_pings()
	_check(pings.size() == 3 and pings["24224"].who == "Jack" and pings["24224"].why == "open", "3 live pings with who and why: %s" % [pings.keys()])
	_check(not pings.has("99999"), "pings older than 10 minutes are gone")
	chat.messages.append(_msg(5, "-24210"))
	_check(not chat.recent_pings().has("24210"), "Unping clears it for everyone")
	chat.messages.append(_msg(6, "24210@held"))
	_check(chat.recent_pings().has("24210"), "and it can be pinged again")

	# The map hides pings whose job is done.
	Profile.save_path = "user://unping_profile.cfg"
	var p := Profile.new()
	p.region = "us_appalachia"
	p.zip = "24201"
	p.town = "Bristol"
	p.pet_species = "dog"
	p.pet_name = "Biscuit"
	p.team.assign(["black_bear", "horned_owl"])
	p.unlocked.assign(p.team)
	var members := [{"user_id": "u1", "name": "Jack · Appalachia", "zip": "24210"},
		{"user_id": "u2", "name": "Biscuit · Appalachia", "zip": "24201"}]
	var c := Campaign.create(p, {"id": "t1", "state": "", "members": members})
	var open_i := -1
	var held_i := -1
	for n in c.territories[c.home].neighbors:
		if not c.territories[n].owned and open_i < 0:
			open_i = n
	for n in c.territories[c.home].neighbors:
		if n != open_i and held_i < 0:
			held_i = n
	c.territories[held_i].owned = true
	c._ownership_changed()
	var open_id := c.territories[open_i].id
	var held_id := c.territories[held_i].id
	chat.messages = [_msg(1, open_id + "@open"), _msg(2, held_id + "@attack")]
	c.under_attack = held_i
	var map := MapScreen.new()
	map.campaign = c
	map.profile = p
	map.size = Vector2(720, 1280)
	root.add_child(map)
	for k in 4:
		await process_frame
	var live: Dictionary = map.call("_live_pings", chat.recent_pings())
	_check(live.has(open_id) and live.has(held_id), "both pings show while their job is open")
	map.call("_select", open_i)
	_check((map.get("_ping") as Button).text == "Unping", "selecting a pinged territory offers Unping")
	c.territories[open_i].owned = true
	c.under_attack = -1
	live = map.call("_live_pings", chat.recent_pings())
	_check(not live.has(open_id), "liberating the pinged horde land clears its ping")
	_check(not live.has(held_id), "beating the counterattack clears its ping")
	chat.messages = [_msg(1, held_id + "@held")]
	_check(map.call("_live_pings", chat.recent_pings()).has(held_id), "a ping on held land stays until unpinged or 10 minutes pass")
	map.call("_select", c.home)
	_check((map.get("_ping") as Button).text == "Ping", "an unpinged territory offers Ping")
	print("%d failure(s)" % _fails)
	quit()
