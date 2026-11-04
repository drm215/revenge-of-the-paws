extends SceneTree

## An expired login is refreshed once, however many parts of the game ask at the same moment:
## Supabase replaces the token on each refresh and can end the session if an old one is reused.

var _fails := 0
var cloud: Node


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


func _init() -> void:
	_run.call_deferred()


func _post(path: String, what: Dictionary) -> Dictionary:
	var http := HTTPRequest.new()
	root.add_child(http)
	http.request(OS.get_environment("FAKE_SUPABASE_URL") + path, ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify(what))
	var res: Array = await http.request_completed
	http.queue_free()
	var parsed: Variant = JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())
	return parsed if parsed is Dictionary else {}


func _refreshes() -> int:
	var http := HTTPRequest.new()
	root.add_child(http)
	http.request(OS.get_environment("FAKE_SUPABASE_URL") + "/_state")
	var res: Array = await http.request_completed
	http.queue_free()
	var st: Dictionary = JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())
	return int(st.get("refreshes", 0))


## Starts `count` callers at once; returns [how many got true] when all have answered.
func _ask(count: int) -> Array:
	var running := [count]
	var granted := [0]
	for k in count:
		var one := func() -> void:
			if await cloud.call("_ensure_token"):
				granted[0] += 1
			running[0] -= 1
		one.call()
	while running[0] > 0:
		await process_frame
	return granted


func _run() -> void:
	cloud = root.get_node("Cloud")
	cloud.state_path = "user://token_cloud.cfg"
	cloud.base_url = OS.get_environment("FAKE_SUPABASE_URL")
	cloud.anon_key = "anon"
	cloud.log_out()
	_check(await cloud.log_in("a@b.co", "oldpass") == "", "log in")

	var before := await _refreshes()
	var granted: Array = await _ask(4)
	_check(await _refreshes() == before and granted[0] == 4, "a valid login needs no refresh")

	cloud.set("_expires_at", 0.0)
	await _post("/_slow", {"refresh": 0.2})
	granted = await _ask(4)
	var made := await _refreshes() - before
	_check(made == 1, "4 callers at once make 1 refresh (made %d)" % made)
	_check(granted[0] == 4, "and all 4 get the new login (%d)" % granted[0])
	_check(cloud.get("_refresh") == "r3" and cloud.signed_in(), "the new token is kept")

	# The next expiry refreshes again: the lock doesn't stick.
	cloud.set("_expires_at", 0.0)
	before = await _refreshes()
	granted = await _ask(1)
	_check(await _refreshes() == before + 1 and granted[0] == 1, "a later expiry refreshes again")

	# Logging out while a refresh is on its way stays logged out.
	cloud.set("_expires_at", 0.0)
	var running := [true]
	var answer := [true]
	var one := func() -> void:
		answer[0] = await cloud.call("_ensure_token")
		running[0] = false
	one.call()
	await create_timer(0.05).timeout
	cloud.log_out()
	while running[0]:
		await process_frame
	_check(not cloud.signed_in() and not answer[0], "logging out mid-refresh isn't undone by its answer")

	# A login that really is dead logs out, and every waiting caller hears no.
	_check(await cloud.log_in("a@b.co", "oldpass") == "", "log in again")
	cloud.set("_expires_at", 0.0)
	await _post("/_slow", {"refresh": 0.2, "refresh_fails": true})
	granted = await _ask(3)
	_check(granted[0] == 0 and not cloud.signed_in(), "a rejected refresh signs out, and all 3 hear it")
	print("%d failure(s)" % _fails)
	quit()
