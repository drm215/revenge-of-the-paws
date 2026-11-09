extends SceneTree

## Every saved game syncs on its own (fake_supabase.py): the new-game-then-switch-devices case.

var _fails := 0
var cloud: Node


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


func _init() -> void:
	_run.call_deferred()


func _game(slot: String, pet: String, town: String, turn_note := "") -> void:
	Saves.use(slot)
	var p := Profile.new()
	p.region = "us_appalachia"
	p.zip = "24210"
	p.town = town
	p.pet_species = "dog"
	p.pet_name = pet
	p.team.assign(["black_bear", "horned_owl"])
	p.unlocked.assign(p.team)
	if turn_note != "":
		p.fixes.append(turn_note)  # a visible change in the save text
	p.save()


func _cloud_rows() -> Array:
	var http := HTTPRequest.new()
	root.add_child(http)
	http.request(OS.get_environment("FAKE_SUPABASE_URL") + "/_state")
	var res: Array = await http.request_completed
	http.queue_free()
	return JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8()).saves


func _bump(slot: String, text: String) -> void:
	var http := HTTPRequest.new()
	root.add_child(http)
	http.request(OS.get_environment("FAKE_SUPABASE_URL") + "/_bump", ["Content-Type: application/json"], HTTPClient.METHOD_POST,
		JSON.stringify({"slot": slot, "profile": text}))
	await http.request_completed
	http.queue_free()


func _run() -> void:
	cloud = root.get_node("Cloud")
	cloud.state_path = "user://cg_cloud.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(cloud.state_path))
	cloud.base_url = OS.get_environment("FAKE_SUPABASE_URL")
	cloud.anon_key = "anon"
	cloud.log_out()
	await cloud.log_in("a@b.co", "oldpass")

	# Device 1: an old game and a brand new one; the old one is played last.
	_game("save_old", "Jack", "Abingdon")
	_game("save_new", "Biscuit", "Bristol")
	_game("save_old", "Jack", "Abingdon", "played-last")
	await cloud.sync()
	var rows: Array = await _cloud_rows()
	for r: Dictionary in rows:
		print("     row %s device=%s profile starts: %s" % [r.slot, r.get("device", "?"), String(r.profile).substr(0, 60).replace("
", " ")])
	_check(rows.size() == 2 and rows.map(func(r: Dictionary) -> String: return r.slot).has("save_new"), "both games are in the cloud: %s" % [rows.map(func(r: Dictionary) -> String: return r.slot)])

	# Device 2: nothing local, same account.
	Saves.delete("save_old")
	Saves.delete("save_new")
	cloud.set("_deleted", [])  # (the wipe above stands in for a different device, not a deletion)
	cloud.set("_synced", {})
	cloud.set("_dirty", {})
	Profile.save_path = Profile.SAVE_PATH
	await cloud.sync()
	_check(Saves.describe("save_new").title == "Biscuit's pack · Bristol", "the new game downloads on the other device: " + Saves.describe("save_new").get("title", "missing"))
	_check(Saves.describe("save_old").title == "Jack's pack · Abingdon", "and so does the old one, separately")

	# Play the new game on device 2: only its cloud copy changes.
	var old_stamp: String = (await _cloud_rows()).filter(func(r: Dictionary) -> bool: return r.slot == "save_old")[0].updated_at
	_game("save_new", "Biscuit", "Bristol", "turn-2")
	await cloud.sync()
	rows = await _cloud_rows()
	var new_row: Dictionary = rows.filter(func(r: Dictionary) -> bool: return r.slot == "save_new")[0]
	var old_row: Dictionary = rows.filter(func(r: Dictionary) -> bool: return r.slot == "save_old")[0]
	_check("turn-2" in new_row.profile and old_row.updated_at == old_stamp, "playing one game updates only its cloud copy")

	# The same game changed on both devices: the player chooses, for that game only.
	_game("save_old", "Jack", "Abingdon", "device-2-move")
	cloud.get("_timer").stop()
	await _bump("save_old", old_row.profile.replace("Abingdon", "Abingdon (other device)"))
	await cloud.sync()
	var pending: Dictionary = cloud.get("_pending")
	_check(cloud.get("_conflict_ui") != null and String(pending.get("slot", "")) == "save_old", "a conflict on one game asks about that game")
	await cloud.call("_resolve_conflict", false)
	for k in 10:
		await process_frame
	rows = await _cloud_rows()
	_check("device-2-move" in rows.filter(func(r: Dictionary) -> bool: return r.slot == "save_old")[0].profile, "Keep this device replaces just that game's cloud copy")

	# Deleting a game takes its cloud copy out of sync, into the cloud's trash (kept, to put back).
	Saves.delete("save_new")
	await cloud.sync()
	rows = await _cloud_rows()
	var live := rows.filter(func(r: Dictionary) -> bool: return not String(r.slot).begins_with(cloud.TRASH))
	var binned := rows.filter(func(r: Dictionary) -> bool: return String(r.slot).begins_with(cloud.TRASH))
	_check(live.size() == 1 and live[0].slot == "save_old", "deleting a game removes it from the cloud's games")
	_check(binned.size() == 1 and String(binned[0].slot).ends_with("_save_new"), "and keeps it in the trash: %s" % [binned.map(func(r: Dictionary) -> String: return r.slot)])
	await cloud.sync()
	_check(Saves.describe("save_new").is_empty() and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(Saves.DIR + "/" + String(binned[0].slot))), "a trashed game never syncs back")
	Saves.delete("save_old")
	await cloud.sync()
	print("%d failure(s)" % _fails)
	quit()
