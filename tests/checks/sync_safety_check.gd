extends SceneTree

## When a game can't back up, nobody finds out too late (fake_supabase.py): a refused upload warns on
## the map and is reported to the server; battle logs carry the game and how far behind it is; a
## cloud copy replacing different progress here keeps the old copy, which can be put back.

var _fails := 0
var cloud: Node
var _url := ""


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


func _init() -> void:
	_run.call_deferred()


func _post(path: String, body: Dictionary) -> void:
	var http := HTTPRequest.new()
	root.add_child(http)
	http.request(_url + path, ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify(body))
	await http.request_completed
	http.queue_free()


func _state() -> Dictionary:
	var http := HTTPRequest.new()
	root.add_child(http)
	http.request(_url + "/_state")
	var res: Array = await http.request_completed
	http.queue_free()
	return JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())


func _profile(level: int) -> Profile:
	var p := Profile.new()
	p.region = "us_appalachia"
	p.zip = "24210"
	p.town = "Abingdon"
	p.pet_species = "dog"
	p.pet_name = "Peeper"
	p.team.assign(["black_bear", "horned_owl"])
	p.unlocked.assign(p.team)
	p.xp["dog"] = GameData.xp_to_reach(level)
	return p


func _run() -> void:
	root.theme = Retro.make_theme()
	_url = OS.get_environment("FAKE_SUPABASE_URL")
	cloud = root.get_node("Cloud")
	cloud.state_path = "user://ss_cloud.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(cloud.state_path))
	cloud.base_url = _url
	cloud.anon_key = "anon"
	cloud.log_out()
	await cloud.log_in("a@b.co", "oldpass")
	var slot := Saves.new_slot()
	Saves.use(slot)

	# Backed up: no warning.
	_profile(18).save()
	await cloud.sync()
	_check(cloud.backup_trouble() == "" and cloud.unsynced_minutes() == 0, "a game that's backed up: nothing to warn about")

	# The cloud refuses uploads (reads still work, as they did for Lucas).
	await _post("/_slow", {"save_status": 500})
	_profile(24).save()
	await cloud.sync()
	_check(cloud.backup_trouble().begins_with("Your game isn't backed up:"), "a refused upload warns: " + cloud.backup_trouble())
	var events: Array = (await _state()).get("sync_events", [])
	var upload: Array = events.filter(func(e: Dictionary) -> bool: return e.kind == "upload")
	_check(upload.size() == 1 and int(upload[0].code) == 500 and upload[0].slot == slot and "refused" in String(upload[0].message),
		"and the server hears why: %s" % [upload])
	await cloud.sync()
	events = (await _state()).get("sync_events", [])
	_check(events.filter(func(e: Dictionary) -> bool: return e.kind == "upload").size() == 1, "the same failure isn't reported over and over")

	# Hours without a backup: the battle log says so, and the map warns.
	cloud.get("_dirty_since")[slot] = Time.get_unix_time_from_system() - 3 * 3600
	cloud.get("_upload_failed").erase(slot)
	_check("3 hours" in cloud.backup_trouble(), "a long time without a backup warns too: " + cloud.backup_trouble())
	cloud.get("_upload_failed")[slot] = "refused for the test (500)"
	cloud.log_battle({"legend": "", "outcome": "victory", "players": 1})
	await cloud.sync()
	var battles: Array = (await _state()).get("battles", [])
	var last: Dictionary = battles[-1].report
	_check(last.slot == slot and int(last.unsynced_minutes) >= 180 and last.signed_in and String(last.sync_error) != "",
		"battle logs carry the game, how far behind it is and the error: slot=%s unsynced=%s error=%s" % [last.slot, last.unsynced_minutes, last.sync_error])

	var map := MapScreen.new()
	map.profile = _profile(24)
	Campaign.clear_saved()
	map.campaign = Campaign.create(map.profile)
	map.size = Vector2(720, 1280)
	root.add_child(map)
	await process_frame
	_check(map._backup_warning.visible and "isn't backed up" in map._backup_warning.text, "the map shows it: " + map._backup_warning.text)

	# The cloud takes uploads again: one tap and the warning goes.
	await _post("/_slow", {"save_status": 0})
	map._backup_warning.pressed.emit()
	for k in 30:
		await process_frame
		if not map._backup_warning.visible:
			break
	_check(not map._backup_warning.visible and cloud.backup_trouble() == "", "retrying backs it up and the warning goes")
	map.queue_free()

	# Another device's older copy replaces this one here: the newer copy is kept and can come back.
	var mine := FileAccess.get_file_as_string(Saves.path(slot, Saves.PROFILE))
	var older := mine.replace("\"dog\": %d" % GameData.xp_to_reach(24), "\"dog\": %d" % GameData.xp_to_reach(18))
	_check(older != mine, "(an older copy of the game)")
	await _post("/_bump", {"slot": slot, "profile": older})
	await cloud.sync()
	_check(FileAccess.get_file_as_string(Saves.path(slot, Saves.PROFILE)) == older, "the cloud copy downloads")
	var kept := Saves.backup_info(slot)
	_check(kept.get("detail", "") == "best Lv 24", "the copy it replaced is kept: %s" % [kept])
	events = (await _state()).get("sync_events", [])
	var over: Array = events.filter(func(e: Dictionary) -> bool: return e.kind == "download_over")
	_check(over.size() == 1 and "best Lv 24" in String(over[0].detail.before) and "best Lv 18" in String(over[0].detail.after),
		"and the server hears what was replaced: %s" % [over])

	var picker := SaveScreen.new()
	picker.size = Vector2(720, 1280)
	root.add_child(picker)
	await process_frame
	var undo: Array = picker.find_children("*", "Button", true, false).filter(func(b: Button) -> bool: return b.text.begins_with("Restore the copy"))
	_check(undo.size() == 1 and "best Lv 24" in undo[0].text, "the save picker offers it back")
	undo[0].pressed.emit()
	undo[0].pressed.emit()  # "Sure?"
	_check(FileAccess.get_file_as_string(Saves.path(slot, Saves.PROFILE)) == mine and Saves.backup_info(slot).is_empty(), "restoring puts the newer copy back")
	await cloud.sync()
	var rows: Array = (await _state()).saves.filter(func(r: Dictionary) -> bool: return r.slot == slot)
	_check(rows.size() == 1 and String(rows[0].profile) == mine, "and backs it up to the cloud")
	_check("best Lv 24" in cloud.summary(mine, ""), "the two-saves question shows each copy's level: " + cloud.summary(mine, ""))
	Saves.delete(slot)
	_check(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(Saves.DIR + "/" + slot)), "deleting a game takes its kept copy too")

	print("%d failure(s)" % _fails)
	quit()
