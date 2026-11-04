extends SceneTree

## The one check-in: it replaces three separate polls, sends the map and raid only when they change,
## slows when idle, stops while hidden, and copes with a server that doesn't have it yet.

var _fails := 0
var _url := ""
var cloud: Node
var team: Node
var chat: Node
var raid: Node
var pulse: Node


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


func _init() -> void:
	_run.call_deferred()


func _post(path: String, what: Dictionary) -> Variant:
	var http := HTTPRequest.new()
	root.add_child(http)
	http.request(_url + path, ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify(what))
	var res: Array = await http.request_completed
	http.queue_free()
	return JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())


func _counts() -> Dictionary:
	var http := HTTPRequest.new()
	root.add_child(http)
	http.request(_url + "/_state")
	var res: Array = await http.request_completed
	http.queue_free()
	var st: Dictionary = JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())
	return {"pulses": int(st.get("pulses", 0)), "full": int(st.get("pulse_team_rows", 0)), "raids": int(st.get("pulse_raid_rows", 0)),
		"polls": int(st.get("old_polls", 0))}


## Seconds pass, as the timer would count them; returns the number of check-ins sent.
func _seconds(count: int) -> int:
	var before: int = (await _counts()).pulses
	for k in count:
		pulse._tick()
		while pulse._busy:
			await process_frame
	return (await _counts()).pulses - before


func _run() -> void:
	_url = OS.get_environment("FAKE_SUPABASE_URL")
	Profile.save_path = "user://pulse_profile.cfg"
	Campaign.save_path = "user://pulse_campaign.cfg"
	cloud = root.get_node("Cloud")
	team = root.get_node("Team")
	chat = root.get_node("Chat")
	raid = root.get_node("Raid")
	pulse = root.get_node("Pulse")
	pulse._timer.stop()
	cloud.state_path = "user://pulse_cloud.cfg"
	team.state_path = "user://pulse_team.cfg"
	chat.state_path = "user://pulse_chat.cfg"
	raid.state_path = "user://pulse_raid.cfg"
	cloud.base_url = _url
	cloud.anon_key = "anon"
	cloud.log_out()
	_check(await cloud.log_in("a@b.co", "oldpass") == "", "log in")
	_check(await _seconds(30) == 0, "no team: no check-ins")

	var p := Profile.new()
	p.region = "us_appalachia"
	p.zip = "24210"
	p.town = "Abingdon"
	p.pet_species = "dog"
	p.pet_name = "Jack"
	p.team.assign(["black_bear", "horned_owl"])
	p.unlocked.assign(["black_bear", "horned_owl"])
	p.save()
	_check(await team.create(p) == "", "team")
	await create_timer(0.3).timeout

	# Pace: 12 s while active.
	pulse._waited = 0
	pulse._quiet = 0
	var before_polls: int = (await _counts()).polls
	_check(await _seconds(60) == 5, "one check-in every 12 s while active")
	_check((await _counts()).polls == before_polls, "and nothing else polls")

	# Only what changed comes back.
	var c0 := await _counts()
	await pulse.check()
	await pulse.check()
	var c1 := await _counts()
	_check(c1.full == c0.full and c1.raids == c0.raids, "a quiet game gets neither the map nor the raid")

	var changed := [0]
	team.changed.connect(func() -> void: changed[0] += 1)
	await _post("/_teammate_move", {"team": team.team_id})
	await pulse.check()
	var c2 := await _counts()
	_check(c2.full == c1.full + 1, "a teammate's move brings the map once")
	_check(changed[0] == 1, "and tells the game")
	var version: float = team.info.version
	await pulse.check()
	_check((await _counts()).full == c2.full and team.info.version == version, "then quiet again")

	# Chat and raids arrive the same way.
	var heard := [0]
	chat.received.connect(func() -> void: heard[0] += 1)
	await _post("/_teammate_says", {"team": team.team_id, "body": "Hi there"})
	await pulse.check()
	_check(heard[0] == 1 and String(chat.messages[-1].body) == "Hi there", "chat arrives")
	var count: int = chat.messages.size()
	await pulse.check()
	_check(chat.messages.size() == count, "once")

	_check(await raid.open("24211", "woodbooger", "Lair", "Jack", p.snapshot()) == "", "a raid opens")
	raid.info = {}  # as if this device hasn't heard yet
	await pulse.check()
	_check(raid.status() == "lobby", "the raid arrives by check-in")
	var c3 := await _counts()
	await pulse.check()
	_check((await _counts()).raids == c3.raids, "once")
	await raid.leave()
	await pulse.check()
	_check(raid.status() == "", "a raid that's gone goes (status '%s')" % raid.status())

	# Idle: every 60 s after 2 minutes without a touch; a touch brings it back.
	pulse._waited = 0
	pulse._quiet = 120
	_check(await _seconds(120) == 2, "idle: one check-in a minute")
	var touch := InputEventScreenTouch.new()
	touch.pressed = true
	pulse._input(touch)
	pulse._waited = 0
	_check(await _seconds(24) == 2, "a touch brings it back to 12 s")

	# Hidden: nothing at all; back: at once.
	pulse.pretend_hidden = true
	_check(await _seconds(300) == 0, "page hidden: nothing for 5 minutes")
	pulse.pretend_hidden = false
	_check(await _seconds(1) == 1, "back: a check-in straight away")

	# An answer that arrives during a save doesn't undo it.
	var mine: float = team.info.version
	_check(not team.take_pulse({"id": team.team_id, "version": mine - 1, "state": "", "members": team.info.members}) and team.info.version == mine,
		"an older map is ignored")

	# Queued moves go with the check-in.
	team.pending.append({"do": "rest"})
	await pulse.check()
	var waited := 0
	while not team.pending.is_empty() and waited < 300:
		await process_frame
		waited += 1
	_check(team.pending.is_empty(), "a queued move is sent")

	# A server without team_pulse yet: the old requests carry on, moves and chat still arrive.
	await _post("/_slow", {"no_pulse": true})
	await pulse.check()
	_check(pulse._old_server, "no team_pulse on the server: it notices")
	var had: float = team.info.version
	await _post("/_teammate_move", {"team": team.team_id})
	await _post("/_teammate_says", {"team": team.team_id, "body": "Still here"})
	await pulse.check()
	await create_timer(0.3).timeout
	_check(team.info.version > had, "a teammate's move still arrives")
	_check(String(chat.messages[-1].body) == "Still here", "and chat")
	pulse._old_server = false
	await _post("/_slow", {"no_pulse": false})

	# Off the team.
	await _post("/_remove_member", {"team": team.team_id})
	await pulse.check()
	_check(team.info.is_empty(), "removed from the team: the game hears")

	print("%d failure(s)" % _fails)
	quit()
