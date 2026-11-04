extends SceneTree

## Battle log upload against fake_supabase.py.

var _fails := 0


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var cloud: Node = root.get_node("Cloud")
	cloud.state_path = "user://blog_cloud.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(cloud.state_path))
	cloud.base_url = OS.get_environment("FAKE_SUPABASE_URL")
	cloud.anon_key = "anon"
	cloud.log_out()
	var p := Profile.new()
	p.region = "us_appalachia"
	p.pet_species = "dog"
	p.pet_name = "Jack"
	p.team.assign(["black_bear", "bobcat"])
	p.unlocked.assign(["black_bear", "bobcat"])
	var b := Battle.new(p, [["shambler"], ["woodbooger"]], 1.0, 1.0, "t", 1)
	b.start_next_wave()
	b._deal_damage(b.party[0], b.enemies[0], 1.0, 0.0)
	var report := b.report()
	report.merge({"legend": "woodbooger", "players": 1})
	cloud.log_battle(report)
	_check(cloud._battle_logs.size() == 1, "signed out: report waits")
	_check(await cloud.log_in("a@b.co", "oldpass") == "", "log in")
	await cloud.sync()
	_check(cloud._battle_logs.is_empty(), "sync sent it")
	var http := HTTPRequest.new()
	root.add_child(http)
	http.request(OS.get_environment("FAKE_SUPABASE_URL") + "/_state")
	var res: Array = await http.request_completed
	var state: Dictionary = JSON.parse_string(res[3].get_string_from_utf8())
	var sent: Array = state.get("battles", [])
	_check(sent.size() == 1 and sent[0].legend == "woodbooger" and sent[0].outcome == "ongoing" and int(sent[0].report.pack[0].dealt) > 0, "server got it: %s" % [sent.map(func(r): return r.legend)])
	for k in 40:
		cloud._battle_logs.append({})
	cloud.log_battle({})
	_check(cloud._battle_logs.size() == cloud.BATTLE_LOG_KEEP, "offline queue is capped")
	cloud._battle_logs.clear()
	cloud._store_state()
	print("%d failure(s)" % _fails)
	quit()
