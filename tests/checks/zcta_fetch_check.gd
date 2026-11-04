extends SceneTree

## ZIP outlines on the web: a map starts without them and fetches them, each file only once ever;
## failed or garbled fetches retry; and game results don't depend on them.

var _fails := 0
var _url := ""


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


func _init() -> void:
	_run.call_deferred()


func _post(path: String, what: Dictionary) -> void:
	var http := HTTPRequest.new()
	root.add_child(http)
	http.request(_url + path, ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify(what))
	await http.request_completed
	http.queue_free()


func _gets() -> int:
	var http := HTTPRequest.new()
	root.add_child(http)
	http.request(_url + "/_state")
	var res: Array = await http.request_completed
	http.queue_free()
	var st: Dictionary = JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())
	return int(st.get("zcta_gets", 0))


func _profile() -> Profile:
	var p := Profile.new()
	p.region = "us_appalachia"
	p.zip = "24210"
	p.town = "Abingdon"
	p.pet_species = "dog"
	p.pet_name = "Jack"
	p.team.assign(["black_bear", "horned_owl"])
	p.unlocked.assign(["black_bear", "horned_owl"])
	return p


func _outlined(c: Campaign) -> int:
	var n := 0
	for t in c.territories:
		if not t.parts.is_empty():
			n += 1
	return n


func _map(c: Campaign) -> MapView:
	var view := MapView.new()
	view.campaign = c
	view.size = Vector2(720, 700)
	root.add_child(view)
	return view


func _screen(c: Campaign) -> MapScreen:
	var screen := MapScreen.new()
	screen.campaign = c
	screen.profile = c.profile
	screen.size = Vector2(720, 1280)
	root.add_child(screen)
	return screen


## As on a device that has never fetched any.
func _forget_outlines() -> void:
	ZctaDB._shards.clear()
	var folder := "user://zcta/%d" % ZctaDB.VERSION
	for f in DirAccess.get_files_at(folder):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(folder + "/" + f))


func _wait_loaded(view: MapView, seconds := 10.0) -> void:
	var waited := 0.0
	while view.campaign.missing_outlines().size() > 0 and waited < seconds:
		await create_timer(0.05).timeout
		waited += 0.05


func _run() -> void:
	root.theme = Retro.make_theme()
	_url = OS.get_environment("FAKE_SUPABASE_URL")
	Profile.save_path = "user://zf_profile.cfg"
	Campaign.save_path = "user://zf_campaign.cfg"

	# The same map, with outlines from the start (as on desktop): the reference.
	var whole := Campaign.create(_profile())
	_check(_outlined(whole) > 30, "with the files at hand, a map has its outlines at once")
	var whole_text := whole.to_text()
	var whole_parts: Array = whole.territories.map(func(t: Territory) -> Array: return t.parts)

	# Now as the web build: no files yet.
	ZctaDB.use_bundled = false
	ZctaDB.base_url = _url
	ZctaDB._shards.clear()
	var c := Campaign.create(_profile())
	_check(_outlined(c) == 0, "on the web, a new map starts without outlines")
	var wanted := c.missing_outlines()
	_check(wanted.size() >= 1 and wanted.size() < 30, "it asks for only a few files: %s" % [wanted])
	_check(c.to_text() == whole_text, "the game state is the same without them")
	_check(c.territories.size() == whole.territories.size() and c.territories[c.home].id == whole.territories[whole.home].id, "same territories, same home")

	# A failed fetch retries, with a message.
	await _post("/_slow", {"zcta_fails": true})
	var view := _map(c)
	await create_timer(0.1).timeout
	_check(view._loading.visible, "the map says it's loading: " + view._loading.text)
	await create_timer(0.3).timeout
	_check("Can't load" in view._loading.text, "a failed fetch says so: " + view._loading.text)
	_check(_outlined(c) == 0 and c.missing_outlines().size() == wanted.size(), "still nothing, no crash")
	view.free()

	# Something that isn't an outline file (a captive page, say) isn't believed or kept.
	await _post("/_slow", {"zcta_fails": false, "zcta_garbage": true})
	_check(not await ZctaDB.download(wanted[0], root), "a garbled reply is refused")
	_check(not FileAccess.file_exists("user://zcta/%d/%s.bin" % [ZctaDB.VERSION, wanted[0]]), "and not kept")

	# The fetch works.
	await _post("/_slow", {"zcta_garbage": false})
	var before := await _gets()
	view = _map(c)
	await _wait_loaded(view)
	await process_frame
	_check(c.missing_outlines().is_empty(), "the files arrive")
	_check(await _gets() - before == wanted.size(), "one request per file (%d)" % (await _gets() - before))
	_check(_outlined(c) == whole.territories.size() or _outlined(c) == _outlined(whole), "every territory has its outline")
	_check(not view._loading.visible, "the message goes away")
	var same := true
	for i in c.territories.size():
		same = same and c.territories[i].parts == whole_parts[i]
	_check(same, "outlines match the ones from the game's own files, point for point")
	_check(view._parts.size() == c.territories.size() and not view._parts[c.home].is_empty(), "the map has redrawn with them")
	var picked := [-1]
	view.territory_selected.connect(func(i: int) -> void: picked[0] = i)
	view._select_at(view._to_screen(c.territories[c.home].site))
	_check(picked[0] == c.home, "and taps find territories")
	view.free()

	# Next time, even after a restart: no network at all.
	await _post("/_slow", {"zcta_fails": true})
	ZctaDB._shards.clear()
	before = await _gets()
	var again := Campaign.create(_profile())
	_check(_outlined(again) == _outlined(whole), "a restart reads them from this device")
	_check(again.missing_outlines().is_empty() and await _gets() == before, "without asking the network")

	# A damaged copy on the device is fetched again rather than trusted.
	await _post("/_slow", {"zcta_fails": false})
	var file := FileAccess.open("user://zcta/%d/%s.bin" % [ZctaDB.VERSION, wanted[0]], FileAccess.WRITE)
	file.store_string("broken")
	file = null
	ZctaDB._shards.clear()
	var damaged := Campaign.create(_profile())
	_check(wanted[0] in damaged.missing_outlines(), "a damaged copy counts as missing")
	_check(await ZctaDB.download(wanted[0], root), "and is fetched again")
	# All of it through the real map screen, the way players get there.
	await _post("/_slow", {"zcta_fails": false})
	_forget_outlines()
	var fresh := Campaign.create(_profile())
	_check(_outlined(fresh) == 0, "map screen: a new map starts without outlines")
	var screen := _screen(fresh)
	await process_frame
	await process_frame
	var seen_loading: bool = screen._map._loading.visible
	await _wait_loaded(screen._map)
	await create_timer(0.3).timeout
	_check(seen_loading, "map screen: it says it's loading")
	_check(_outlined(fresh) == _outlined(whole), "map screen: the outlines arrive (%d)" % _outlined(fresh))
	_check(not screen._map._parts[fresh.home].is_empty(), "map screen: and are drawn")
	_check(not screen._map._loading.visible, "map screen: the message goes away")
	screen.free()

	# Leaving a map mid-fetch and coming back to the same one, with every file here by then.
	_forget_outlines()
	var left := Campaign.create(_profile())
	screen = _screen(left)
	await process_frame
	screen.free()
	for shard in left.missing_outlines():
		await ZctaDB.download(shard, root)
	_check(left.missing_outlines().is_empty() and _outlined(left) == 0, "back again: the files are here, the map hasn't read them")
	screen = _screen(left)
	await process_frame
	await process_frame
	await create_timer(0.1).timeout
	_check(_outlined(left) == _outlined(whole), "back again: the map reads them (%d)" % _outlined(left))
	_check(not screen._map._parts[left.home].is_empty(), "back again: and draws them")
	screen.free()
	print("%d failure(s)" % _fails)
	quit()
