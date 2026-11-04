extends SceneTree

## Team chat against fake_supabase.py.

var _fails := 0
var cloud: Node
var team: Node
var chat: Node


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


func _init() -> void:
	_run.call_deferred()


func _profile(zip: String, pet: String) -> Profile:
	var p := Profile.new()
	p.region = "us_appalachia"
	p.zip = zip
	p.town = "x"
	p.pet_species = "dog"
	p.pet_name = pet
	p.team.assign(["black_bear", "horned_owl"])
	p.unlocked.assign(p.team)
	p.save()
	return p


func _as(email: String, password: String, zip: String, pet: String, team_id := "") -> Profile:
	cloud.log_out()
	await cloud.log_in(email, password)
	var p := _profile(zip, pet)
	team.use(team_id)  # choosing that game on the save picker
	await team.refresh()
	return p


func _run() -> void:
	Profile.save_path = "user://chat_profile.cfg"
	Campaign.save_path = "user://chat_campaign.cfg"
	cloud = root.get_node("Cloud")
	team = root.get_node("Team")
	chat = root.get_node("Chat")
	cloud.state_path = "user://chat_cloud.cfg"
	team.state_path = "user://chat_team.cfg"
	chat.state_path = "user://chat_chat.cfg"
	cloud.base_url = OS.get_environment("FAKE_SUPABASE_URL")
	cloud.anon_key = "anon"

	var pa := await _as("a@b.co", "oldpass", "24210", "Jack")
	_check(await chat.send("hi") != "", "no team: can't chat")
	await team.create(pa)
	var code: String = team.info.code
	var pb := await _as("b@b.co", "bpass", "24201", "Biscuit")
	await team.join(code, pb)
	_check(team.on_team() and chat.messages.is_empty(), "B joins; chat starts empty")

	_check(await chat.send("Help!") == "", "B sends a quick message")
	_check(await chat.send("   ") != "", "an empty message is refused")
	_check(await chat.send("x".repeat(260)) == "" and String(chat.messages[-1].body).length() == 200, "long messages are cut to 200")
	_check(chat.unread() == 0, "your own messages aren't unread")
	var c := Campaign.create(pb, team.info)
	var spot := c.territories[c.territories[c.home].neighbors[0]]
	_check(await chat.send("pinged " + spot.full_name(), spot.id + "@open") == "", "B pings %s" % spot.full_name())
	_check(chat.recent_pings().has(spot.id) and chat.recent_pings()[spot.id].who == "Biscuit", "the ping is on the map for 10 minutes: %s" % [chat.recent_pings()])
	var slow := ""
	for k in 4:
		slow = await chat.send("spam %d" % k)
	_check("Slow down" in slow, "rate limit: " + slow)

	# A's device picks it all up.
	pa = await _as("a@b.co", "oldpass", "24210", "Jack", team.team_id)
	await chat.poll()
	_check(chat.messages.size() == 5 and chat.unread() == 5, "A receives 5 messages, all unread (%d)" % chat.unread())
	var screen: Control = load("res://scripts/ui/chat_screen.gd").new()
	screen.size = Vector2(720, 1280)
	root.add_child(screen)
	for i in 8:
		await process_frame
	_check(chat.unread() == 0, "opening the chat marks them read")
	screen.queue_free()

	# Leaving clears the chat on this device.
	await team.leave(pa)
	_check(chat.messages.is_empty(), "leaving the team clears its chat here")
	print("%d failure(s)" % _fails)
	quit()
