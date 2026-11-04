extends SceneTree

## Battle reports the server turns down: "too many, for now" keeps them for later; a report it can
## never take is dropped, so one bad report can't hold up the rest forever.

var _fails := 0
var _url := ""


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


func _init() -> void:
	_run.call_deferred()


func _slow(what: Dictionary) -> void:
	var http := HTTPRequest.new()
	root.add_child(http)
	http.request(_url + "/_slow", ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify(what))
	await http.request_completed
	http.queue_free()


func _run() -> void:
	_url = OS.get_environment("FAKE_SUPABASE_URL")
	var cloud: Node = root.get_node("Cloud")
	cloud.state_path = "user://blimit_cloud.cfg"
	cloud.base_url = _url
	cloud.anon_key = "anon"
	cloud.log_out()
	_check(await cloud.log_in("a@b.co", "oldpass") == "", "log in")
	var report := {"legend": "woodbooger", "outcome": "victory", "players": 1}

	await _slow({"battle_status": 429})
	cloud.log_battle(report.duplicate())
	cloud.log_battle(report.duplicate())
	await cloud.sync()
	_check(cloud._battle_logs.size() == 2, "rate limited: both wait")

	await _slow({"battle_status": 400})
	await cloud.sync()
	_check(cloud._battle_logs.is_empty(), "refused for good: dropped, not stuck")

	await _slow({"battle_status": 500})
	cloud.log_battle(report.duplicate())
	await cloud.sync()
	_check(cloud._battle_logs.size() == 1, "a server error: kept for later")

	await _slow({"battle_status": 0})
	await cloud.sync()
	_check(cloud._battle_logs.is_empty(), "then it goes")
	print("%d failure(s)" % _fails)
	quit()
