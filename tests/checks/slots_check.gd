extends SceneTree

## Save slots: migration, the picker, new game / cancel / delete, cloud copies landing in their own
## save.

var _fails := 0


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


func _init() -> void:
	_run.call_deferred()


func _profile(pet: String, town: String) -> Profile:
	var p := Profile.new()
	p.region = "us_appalachia"
	p.zip = "24210"
	p.town = town
	p.pet_species = "dog"
	p.pet_name = pet
	p.team.assign(["black_bear", "horned_owl"])
	p.unlocked.assign(p.team)
	p.xp["dog"] = GameData.xp_to_reach(7)
	return p


func _run() -> void:
	var cloud: Node = root.get_node("Cloud")
	cloud.state_path = "user://slots_cloud.cfg"
	var saved := [0]
	SaveHooks.on_saved = func() -> void: saved[0] += 1

	# The old single save moves into the first slot.
	_profile("Old", "Abingdon").save()
	saved[0] = 0
	_check(FileAccess.file_exists(Profile.SAVE_PATH), "a save from before slots exists")
	Saves.migrate()
	var slots := Saves.list()
	_check(slots.size() == 1 and not FileAccess.file_exists(Profile.SAVE_PATH), "it became the first save: %s" % [slots.map(func(s: Dictionary) -> String: return s.title)])

	await create_timer(1.1).timeout  # "newest first" goes by file times, to the second
	# A new game in its own slot; saving tags the slot and wakes the cloud.
	var a := Saves.new_slot()
	Saves.use(a)
	_profile("Pepper", "Bristol").save()
	var cfg := ConfigFile.new()
	cfg.load(Profile.save_path)
	_check(String(cfg.get_value("profile", "slot", "")) == a and saved[0] == 1, "saving a slot tags it (%s) and triggers cloud sync" % a)
	slots = Saves.list()
	_check(slots.size() == 2 and slots[0].id == a and "Pepper" in slots[0].title and "Lv 7" in slots[0].detail, "newest first: %s / %s" % [slots[0].title, slots[0].detail])

	# Cloud copies land in their own save; only the game being played restarts.
	var restarts := [0]
	cloud.downloaded.connect(func() -> void: restarts[0] += 1)
	var other := _profile("Rex", "Damascus")
	Saves.use("save_elsewhere")
	other.save()
	var other_text := FileAccess.get_file_as_string(Profile.save_path)
	Saves.delete("save_elsewhere")
	Saves.use(a)
	cloud.call("_apply", {"profile": other_text, "campaign": "", "updated_at": "t1"})
	_check(Saves.describe("save_elsewhere").title.begins_with("Rex") and restarts[0] == 0, "another game's cloud copy goes to its own save, without interrupting this one")
	var mine_text := FileAccess.get_file_as_string(Profile.save_path)
	cloud.call("_apply", {"profile": mine_text, "campaign": "", "updated_at": "t2"})
	_check(restarts[0] == 1, "this game's own cloud copy restarts it")
	var legacy := "[profile]\npet_name=\"Old\"\ntown=\"Legacy\"\nzip=\"24210\"\n"
	cloud.call("_apply", {"profile": legacy, "campaign": "", "updated_at": "t3"})
	_check(not Saves.describe("save_cloud").is_empty(), "a cloud copy from before slots gets a save of its own")

	# Tests and other paths never touch the cloud.
	saved[0] = 0
	Profile.save_path = "user://slots_test_profile.cfg"
	_profile("T", "T").save()
	_check(saved[0] == 0, "saving outside a slot doesn't sync")

	# Startup: the save picker; New game, then Cancel, removes the empty save.
	Profile.save_path = Profile.SAVE_PATH
	change_scene_to_file("res://scenes/main.tscn")
	for k in 8:
		await process_frame
	var main: Node = current_scene
	var picker: Node = main.get_child(-1)
	_check(picker is SaveScreen, "the game opens on the save picker")
	var before := Saves.list().size()
	picker.new_game.emit()
	for k in 4:
		await process_frame
	var setup: Node = main.get_child(-1)
	var buttons: PackedStringArray = []
	for btn in setup.find_children("*", "Button", true, false):
		buttons.append(btn.text)
	_check(setup is Onboarding and "Cancel" in buttons, "New game opens setup, with Cancel")
	setup.cancelled.emit()
	for k in 4:
		await process_frame
	_check(main.get_child(-1) is SaveScreen and Saves.list().size() == before, "Cancel goes back to the picker and leaves no empty save")
	(main.get_child(-1) as SaveScreen).chosen.emit(a)
	for k in 6:
		await process_frame
	_check(main.get_child(-1) is MapScreen and Profile.save_path == Saves.path(a, Saves.PROFILE), "choosing a save opens its map")
	var footer_text: PackedStringArray = []
	for btn in main.get_child(-1).find_children("*", "Button", true, false):
		footer_text.append(btn.text)
	_check("Setup" not in footer_text, "no Setup button on the map")
	Saves.delete(a)
	_check(Saves.describe(a).is_empty(), "Delete removes a save")
	print("%d failure(s)" % _fails)
	quit()
