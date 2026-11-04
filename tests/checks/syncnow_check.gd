extends SceneTree

## Saves sync at once against fake_supabase.py. Uses its own slot and removes only that.

const SLOT := "save_synctest"
var _fails := 0
var _cloud: Node


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


func _init() -> void:
	_run.call_deferred()


func _row() -> Dictionary:
	var http := HTTPRequest.new()
	root.add_child(http)
	http.request(OS.get_environment("FAKE_SUPABASE_URL") + "/_state")
	var res: Array = await http.request_completed
	http.queue_free()
	var st: Dictionary = JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())
	for row: Dictionary in st.saves:
		if row.get("slot", "") == SLOT:
			return row
	return {}


func _settle() -> void:
	await create_timer(0.3).timeout
	while _cloud._busy:
		await process_frame


func _run() -> void:
	_cloud = root.get_node("Cloud")
	_cloud.state_path = "user://syncnow_cloud.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_cloud.state_path))
	_cloud.base_url = OS.get_environment("FAKE_SUPABASE_URL")
	_cloud.anon_key = "anon"
	_cloud.log_out()
	_cloud._synced.clear()
	_cloud._dirty.clear()
	_check(await _cloud.log_in("a@b.co", "oldpass") == "", "log in")
	await _settle()
	Saves.use(SLOT)
	var p := Profile.new()
	p.region = "us_appalachia"
	p.town = "one"
	p.pet_species = "dog"
	p.pet_name = "Jack"
	p.team.assign(["black_bear", "horned_owl"])
	p.unlocked.assign(p.team)

	var start := Time.get_ticks_msec()
	p.save()
	await _settle()
	var row := await _row()
	_check("one" in String(row.get("profile", "")), "a save reaches the cloud at once (%d ms)" % (Time.get_ticks_msec() - start))
	_check(not _cloud._dirty.has(SLOT), "and is no longer waiting")

	# A save while a sync is running isn't dropped.
	p.town = "two"
	p.save()
	await create_timer(0.15).timeout
	_check(_cloud._busy, "sync running")
	p.town = "three"
	p.save()
	await _settle()
	row = await _row()
	_check("three" in String(row.get("profile", "")), "a save during a sync goes up too")
	_check(not _cloud._dirty.has(SLOT), "nothing left waiting")

	# A save while the upload itself is on its way stays marked as changed.
	p.town = "four"
	p.save()
	_cloud._timer.stop()
	var expected: String = _cloud._synced[SLOT]
	var done := [false]
	var upload := func() -> void:
		await _cloud._upload(SLOT, expected)
		done[0] = true
	upload.call()
	p.town = "five"
	p.save()
	_cloud._timer.stop()
	while not done[0]:
		await process_frame
	_check(_cloud._dirty.has(SLOT), "a save during an upload still counts as changed")
	_cloud.sync()
	await _settle()
	row = await _row()
	_check("five" in String(row.get("profile", "")), "and goes up next")

	# Battle report: queued without a sync, sent by the save after the fight.
	_cloud._timer.stop()
	_cloud.log_battle({"legend": "woodbooger", "outcome": "victory", "players": 1})
	_check(_cloud._timer.is_stopped(), "a battle report alone starts no sync")
	p.town = "six"
	p.save()
	await _settle()
	_check(_cloud._battle_logs.is_empty(), "the save after the fight sends the report")

	var dir := ProjectSettings.globalize_path("user://saves/" + SLOT)
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir + "/" + f)
	DirAccess.remove_absolute(dir)
	_cloud._dirty.clear()
	_cloud._store_state()
	print("%d failure(s)" % _fails)
	quit()
