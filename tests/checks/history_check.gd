extends SceneTree

## Version history (server/history.sql, mirrored by fake_supabase.py): the cloud keeps older copies
## of a saved game and of a team's shared map, and players put them back from the game. A restored
## game comes back here and in the cloud (and the copy it replaced is kept, so it can be undone);
## a restored team map reaches the whole team, with a note in the team chat.

var _fails := 0
var cloud: Node
var team: Node
var _url := ""


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


func _init() -> void:
	_run.call_deferred()


func _history() -> Dictionary:
	var http := HTTPRequest.new()
	root.add_child(http)
	http.request(_url + "/_history")
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


func _level(slot: String) -> int:
	var p := ConfigFile.new()
	p.load(Saves.path(slot, Saves.PROFILE))
	return GameData.level_for_xp(int((p.get_value("profile", "xp", {}) as Dictionary).get("dog", 0)))


func _run() -> void:
	root.theme = Retro.make_theme()
	_url = OS.get_environment("FAKE_SUPABASE_URL")
	cloud = root.get_node("Cloud")
	team = root.get_node("Team")
	cloud.state_path = "user://hist_cloud.cfg"
	team.state_path = "user://hist_team.cfg"
	cloud.base_url = _url
	cloud.anon_key = "anon"
	cloud.log_out()
	_check(await cloud.log_in("a@b.co", "oldpass") == "", "log in")

	# --- A saved game ---------------------------------------------------------------------------
	var slot := Saves.new_slot()
	Saves.use(slot)
	_profile(18).save()
	await cloud.sync()
	_check((await cloud.versions(slot)).is_empty(), "a game uploaded once has no older copies")
	_profile(30).save()
	await cloud.sync()
	_profile(5).save()  # progress lost on some device, and uploaded
	await cloud.sync()
	var copies: Array = await cloud.versions(slot)
	_check(copies.size() == 2, "two older copies kept: %s" % [copies])
	_check(copies.size() == 2 and "best Lv 30" in String(copies[0].summary) and "best Lv 18" in String(copies[1].summary),
		"newest first, each described: %s" % [copies.map(func(c: Dictionary) -> String: return c.summary)])
	_check(copies.size() > 0 and int(copies[0].saved_at) > 1700000000, "each has its time")
	_check((await cloud.versions("save_someone_else")).is_empty(), "another game's history isn't mixed in")

	_check(await cloud.restore_version(int(copies[0].id)) == "", "restore the Lv 30 copy")
	_check(_level(slot) == 30, "it's back on this device (Lv %d)" % _level(slot))
	var kept: Array = (await _history()).saves.filter(func(h: Dictionary) -> bool: return h.slot == slot)
	_check(kept.size() == 3 and "best Lv 5" in cloud.summary(String(kept.back().profile), ""),
		"the copy it replaced (Lv 5) is kept in the cloud too")
	_check(not Saves.backup_info(slot).is_empty(), "and on this device, so the save picker can undo it")
	await cloud.sync()
	_check(cloud.status == "Up to date." and cloud.get("_pending").is_empty(), "the next sync agrees with the cloud: " + cloud.status)
	_check(await cloud.restore_version(999999) != "", "a copy that isn't there says so")

	# The save picker shows the history under each game, and restoring rebuilds the list.
	var picker := SaveScreen.new()
	picker.size = Vector2(720, 1280)
	root.add_child(picker)
	await process_frame
	var lists := picker.find_children("*", "HistoryList", true, false)
	_check(lists.size() == 1, "the save picker offers older copies for the game")
	if lists.size() == 1:
		var list: HistoryList = lists[0]
		list._toggle.pressed.emit()
		for k in 60:
			await process_frame
			if list._rows.get_child_count() > 1:
				break
		var buttons := list._rows.find_children("*", "Button", true, false)
		_check(buttons.size() >= 2, "it lists them with Restore (%d)" % buttons.size())
		if buttons.size() >= 2:
			var b: Button = buttons.back()  # the oldest: Lv 18
			b.pressed.emit()
			_check(b.text == "Sure?", "Restore asks first")
			b.pressed.emit()
			_check(_level(slot) == 30, "a tap straight after isn't an answer")
			await create_timer(0.5).timeout
			b.pressed.emit()
			for k in 60:
				await process_frame
				if _level(slot) == 18:
					break
			_check(_level(slot) == 18, "then it restores (Lv %d)" % _level(slot))
	picker.queue_free()

	# --- A team map -----------------------------------------------------------------------------
	var p := _profile(10)
	p.save()
	_check(await team.create(p) == "", "team")
	var c := Campaign.create(p, team.info)
	var first := c.to_text()
	var w: Dictionary = await cloud.api(HTTPClient.METHOD_POST, "/rest/v1/rpc/save_team_state",
		{"p_team": team.team_id, "p_state": first, "p_version": int(team.info.version)})
	_check(w.ok and int(w.data) > 0, "the shared map is saved")
	team.refresh()
	for k in 60:
		await process_frame
		if int(team.info.get("version", 0)) == int(w.data):
			break
	var broken := first.replace("turn=%d" % c.turn, "turn=%d" % (c.turn + 7))
	broken = broken.replace(broken.get_slice("owned=", 1).get_slice("\n", 0), "Array[String]([])")
	w = await cloud.api(HTTPClient.METHOD_POST, "/rest/v1/rpc/save_team_state",
		{"p_team": team.team_id, "p_state": broken, "p_version": int(team.info.version)})
	_check(w.ok and int(w.data) > 0, "a bad map replaces it")
	team.refresh()
	for k in 60:
		await process_frame
		if int(team.info.get("version", 0)) == int(w.data):
			break
	var maps: Array = await team.versions()
	_check(maps.size() == 1 and "%d territor" % c.owned_count() in String(maps[0].summary),
		"the good map is kept: %s" % [maps])
	var before := int(team.info.version)
	_check(maps.size() == 1 and await team.restore(int(maps[0].id)) == "", "restore it")
	_check(String(team.info.state) == first and int(team.info.version) == before + 1,
		"the team's map is the good one again, as a new version (v%d)" % int(team.info.version))
	_check(Campaign.create(p, team.info).owned_count() == c.owned_count(), "and the map holds the land again")
	var chat: Array = (await _history()).chat
	_check(not chat.is_empty() and "Put the team map back" in String(chat.back().body), "the team chat says so")
	maps = await team.versions()
	_check(maps.size() == 2 and "0 territories held" in String(maps[0].summary), "the bad map is kept too, in case: %s" % [maps])

	print("%d failure(s)" % _fails)
	quit(1 if _fails else 0)
