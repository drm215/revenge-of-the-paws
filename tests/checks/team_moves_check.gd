extends SceneTree

## A move made while the last one is on its way to the server must not be lost. The fake server
## holds the save open, so the second move always lands in that window.

var _fails := 0
var cloud: Node
var team: Node


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


func _init() -> void:
	_run.call_deferred()


func _slow(what: Dictionary) -> void:
	var http := HTTPRequest.new()
	root.add_child(http)
	http.request(OS.get_environment("FAKE_SUPABASE_URL") + "/_slow", ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify(what))
	await http.request_completed
	http.queue_free()


func _turn(p: Profile) -> int:
	return Campaign.create(p, team.info).turn


func _settle() -> void:
	var waited := 0
	while (team.get("_busy") or not team.pending.is_empty()) and waited < 2000:
		await process_frame
		waited += 1


func _run() -> void:
	Profile.save_path = "user://moves_profile.cfg"
	Campaign.save_path = "user://moves_campaign.cfg"
	cloud = root.get_node("Cloud")
	team = root.get_node("Team")
	cloud.state_path = "user://moves_cloud.cfg"
	team.state_path = "user://moves_team.cfg"
	cloud.base_url = OS.get_environment("FAKE_SUPABASE_URL")
	cloud.anon_key = "anon"
	cloud.log_out()
	_check(await cloud.log_in("a@b.co", "oldpass") == "", "log in")
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

	var start := _turn(p)
	team.record({"do": "rest"})
	await _settle()
	_check(_turn(p) == start + 1 and team.pending.is_empty(), "a move on its own lands")

	await _slow({"save_team_state": 0.5})
	start = _turn(p)
	team.record({"do": "rest"})
	await create_timer(0.25).timeout  # the map has been built and the save is on its way
	_check(team.get("_busy"), "the first move is being sent")
	team.record({"do": "rest"})
	team.record({"do": "rest"})
	_check(team.pending.size() == 3, "two more are queued behind it")
	await _settle()
	await _slow({"save_team_state": 0.0})
	await team.refresh()
	_check(_turn(p) == start + 3, "all three reached the server (turn +%d)" % (_turn(p) - start))
	_check(team.pending.is_empty(), "nothing left waiting")

	# What's still queued survives a reload.
	await _slow({"save_team_state": 0.5})
	team.record({"do": "rest"})
	await create_timer(0.25).timeout
	team.record({"do": "rest"})
	await create_timer(0.4).timeout  # the first save has answered; the second is under way
	var stored := ConfigFile.new()
	stored.load(team.state_path)
	var teams: Dictionary = JSON.parse_string(stored.get_value("team", "teams", "{}"))
	_check(team.pending.size() == 1 and (teams[team.team_id].pending as Array).size() == 1,
		"the move still waiting is on disk, so a reload can't lose it")
	start = _turn(p)
	await _settle()
	await _slow({"save_team_state": 0.0})
	await team.refresh()
	_check(_turn(p) == start + 1 and team.pending.is_empty(), "and it lands")
	print("%d failure(s)" % _fails)
	quit()
