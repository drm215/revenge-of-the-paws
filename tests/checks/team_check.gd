extends SceneTree

## Teams against fake_supabase.py: two players (Abingdon 24210, Bristol 24201) share a map.

var _fails := 0
var cloud: Node
var team: Node


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


func _init() -> void:
	_run.call_deferred()


func _profile(zip: String, town: String, pet: String) -> Profile:
	var p := Profile.new()
	p.region = "us_appalachia"
	p.zip = zip
	p.town = town
	p.pet_species = "dog"
	p.pet_name = pet
	p.team.assign(["black_bear", "horned_owl"])
	p.unlocked.assign(["black_bear", "horned_owl"])
	p.save()
	return p


func _server() -> Dictionary:
	var http := HTTPRequest.new()
	root.add_child(http)
	http.request(OS.get_environment("FAKE_SUPABASE_URL") + "/_teams", ["Content-Type: application/json"], HTTPClient.METHOD_POST, "{}")
	var res: Array = await http.request_completed
	http.queue_free()
	return JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())


func _poke(path: String) -> void:
	var http := HTTPRequest.new()
	root.add_child(http)
	http.request(OS.get_environment("FAKE_SUPABASE_URL") + path, ["Content-Type: application/json"], HTTPClient.METHOD_POST, "{}")
	await http.request_completed
	http.queue_free()


func _campaign(p: Profile) -> Campaign:
	var c := Campaign.create(p, team.info)
	c.me = team.name_for(p)
	for a: Dictionary in team.pending:
		c.apply(a)
	c.on_action = team.record
	return c


## A territory next to `home` the horde holds.
func _next_to(c: Campaign, home: int) -> int:
	for n in c.territories[home].neighbors:
		if not c.territories[n].owned:
			return n
	return -1


func _owned_on_server(id: String) -> bool:
	var st: Dictionary = await _server()
	var t: Dictionary = st.teams.values()[0]
	var cfg := ConfigFile.new()
	cfg.parse(t.state)
	return id in cfg.get_value("campaign", "owned", [])


func _run() -> void:
	Profile.save_path = "user://team_profile.cfg"
	Campaign.save_path = "user://team_campaign.cfg"
	cloud = root.get_node("Cloud")
	team = root.get_node("Team")
	cloud.state_path = "user://team_cloud.cfg"
	team.state_path = "user://team_team.cfg"
	cloud.base_url = OS.get_environment("FAKE_SUPABASE_URL")
	cloud.anon_key = "anon"
	cloud.log_out()

	# --- A creates a team ---
	var pa := _profile("24210", "Abingdon", "Jack")
	_check(await cloud.log_in("a@b.co", "oldpass") == "", "A logs in")
	_check(await team.create(pa) == "" and team.on_team(), "A creates a team: code %s" % team.info.get("code", ""))
	var code: String = team.info.code
	var t_id: String = team.team_id
	var ca := _campaign(pa)
	_check(ca.is_team() and ca.homes.size() == 1 and ca.pace() == 1, "A alone: 1 home, normal pace (%d territories)" % ca.territories.size())

	# --- B joins ---
	cloud.log_out()
	_check(not team.on_team(), "logging out forgets the team on this device")
	var pb := _profile("24201", "Bristol", "Biscuit")
	_check(await cloud.log_in("b@b.co", "bpass") == "", "B logs in")
	pb = _profile("24201", "Bristol", "Biscuit")  # B's own device keeps B's profile (the fake shares one cloud save)
	_check(await team.join("nope", pb) != "", "a wrong code is refused")
	_check(await team.join(code.to_lower(), pb) == "" and team.info.members.size() == 2, "B joins with the code (any case)")
	var cb := _campaign(pb)
	_check(cb.homes.size() == 2 and cb.pace() == 2, "merged map: 2 homes, pace 2")
	_check(cb.territories[cb.home].name.begins_with("Bristol") and cb.home_owner(cb.home) == "", "B's home is Bristol")
	var other := cb.homes[0] if cb.homes[0] != cb.home else cb.homes[1]
	_check(cb.home_owner(other) == "Jack" and cb.territories[other].owned, "Jack's home (Abingdon) is on B's map, held")
	_check(cb.territories.size() < 80, "nearby homes overlap: %d territories, not 80" % cb.territories.size())
	_check(cb.counter_interval() == GameData.COUNTERATTACK_EVERY * 2, "counterattacks every %d turns with 2 players" % cb.counter_interval())

	# --- B liberates next to Bristol: it reaches the server ---
	var tb := _next_to(cb, cb.home)
	cb.resolve_battle(tb, true)
	_check(team.pending.size() == 1, "B's move is queued")
	await team.flush()
	var dbg := Campaign.create(pb, team.info)
	print("     after B: feed=%s me=%s saved profile pet=%s" % [dbg.feed, team.name_for(pb), Profile.load_saved().pet_name])
	_check(team.pending.is_empty() and await _owned_on_server(cb.territories[tb].id), "B's liberation of %s is on the server" % cb.territories[tb].full_name())

	# --- A, on its own device, liberates next to Abingdon while B's move is unseen ---
	cloud.log_out()
	pa = _profile("24210", "Abingdon", "Jack")
	await cloud.log_in("a@b.co", "oldpass")
	pa = _profile("24210", "Abingdon", "Jack")
	team.use(t_id)  # choosing game 1 on the save picker
	await team.refresh()
	ca = _campaign(pa)
	_check(ca.territories[tb].owned, "A sees B's liberation after refreshing")
	var ta := _next_to(ca, ca.home)
	await _poke("/_fail_next_save")  # a teammate saves just before A does
	ca.resolve_battle(ta, true)
	await team.flush()
	_check(team.pending.is_empty() and await _owned_on_server(ca.territories[ta].id) and await _owned_on_server(cb.territories[tb].id),
		"A's save lost a race, replayed on the newer map: both liberations kept")
	var shared := Campaign.create(pa, team.info)
	var entries: PackedStringArray = []
	for e: Dictionary in shared.feed:
		entries.append("%s: %s" % [e.who, e.text])
	_check(entries.size() == 2 and entries[0].begins_with("Biscuit") and entries[1].begins_with("Jack"), "team feed credits each player: " + " | ".join(entries))

	# --- Already liberated by a teammate: no double liberation ---
	var stale := Campaign.create(pa, {"id": team.info.id, "members": team.info.members, "state": ""})
	stale.resolve_battle(stale.territories.map(func(t: Territory) -> String: return t.id).find(cb.territories[tb].id), true)
	var after := Campaign.create(pa, team.info)
	after.apply({"do": "battle", "t": cb.territories[tb].id, "won": true})
	_check("already free" in after.last_event, "replaying onto a territory a teammate already freed: " + after.last_event)

	# --- Leaving ---
	_check(await team.leave(pa) == "" and not team.on_team(), "A leaves the team")
	var st: Dictionary = await _server()
	_check(st.members.filter(func(m: Dictionary) -> bool: return m.team_id == t_id).size() == 1, "B is still on it")
	print("%d failure(s)" % _fails)
	quit()
