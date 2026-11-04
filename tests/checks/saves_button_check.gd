extends SceneTree

## The map's Saves button goes back to the picker.

var _fails := 0


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	root.get_node("Cloud").state_path = "user://sb_cloud.cfg"
	Saves.use(Saves.new_slot())
	var p := Profile.new()
	p.region = "us_appalachia"
	p.zip = "24210"
	p.town = "Abingdon"
	p.pet_species = "dog"
	p.pet_name = "Jack"
	p.team.assign(["black_bear", "horned_owl"])
	p.unlocked.assign(["black_bear", "horned_owl"])
	p.save()
	change_scene_to_file("res://scenes/main.tscn")
	for k in 8:
		await process_frame
	var main: Node = current_scene
	var picker: SaveScreen = main.get_child(-1)
	var first: Dictionary = Saves.list()[0]
	picker.chosen.emit(first.id)
	for k in 6:
		await process_frame
	var map: Node = main.get_child(-1)
	var saves_button: Button = null
	for b in map.find_children("*", "Button", true, false):
		if b.text == "Saves":
			saves_button = b
	_check(map is MapScreen and saves_button != null, "the map has a Saves button")
	saves_button.pressed.emit()
	for k in 6:
		await process_frame
	_check(main.get_child(-1) is SaveScreen, "Saves goes back to the picker")
	print("%d failure(s)" % _fails)
	quit()
