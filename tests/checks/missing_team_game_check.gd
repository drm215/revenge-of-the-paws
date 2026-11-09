extends SceneTree

## A team game a member no longer has on this device (deleted, or the browser lost it) shows in
## the save picker: "Bring it back" fetches their copy from the cloud, out of the trash too. With no
## copy left, the card says how to rejoin the team's map.

var _fails := 0
var cloud: Node
var team: Node


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


func _init() -> void:
	_run.call_deferred()


func _game(pet: String) -> Profile:
	Saves.use(Saves.new_slot())
	var p := Profile.new()
	p.region = "us_appalachia"
	p.zip = "24210"
	p.town = "Abingdon"
	p.pet_species = "cat"
	p.pet_name = pet
	p.team.assign(["black_bear", "horned_owl"])
	p.unlocked.assign(p.team)
	p.save()
	return p


func _texts(node: Node) -> String:
	var out := ""
	for child in node.get_children():
		if child is Label or child is Button:
			out += child.text + "\n"
		out += _texts(child)
	return out


func _button(node: Node, text: String) -> Button:
	for child in node.get_children():
		if child is Button and child.text == text:
			return child
		var found := _button(child, text)
		if found:
			return found
	return null


func _wait_for(screen: Node, text: String) -> bool:
	for k in 60:
		if text in _texts(screen):
			return true
		await create_timer(0.1).timeout
	return false


func _run() -> void:
	root.theme = Retro.make_theme()
	cloud = root.get_node("Cloud")
	team = root.get_node("Team")
	cloud.state_path = "user://mt_cloud.cfg"
	team.state_path = "user://mt_team.cfg"
	cloud.base_url = OS.get_environment("FAKE_SUPABASE_URL")
	cloud.anon_key = "anon"
	cloud.log_out()
	_check(await cloud.log_in("a@b.co", "oldpass") == "", "log in")

	# A team game, backed up, then deleted here (it goes to the cloud's trash).
	var p := _game("Lucky")
	var slot := Saves.slot_of(Profile.save_path)
	_check(await team.create(p) == "", "a team game")
	var team_id := p.team_id
	await cloud.sync()
	Saves.delete(slot)
	await cloud.sync()
	team.use("")
	_check(Saves.describe(slot).is_empty(), "the game is gone from this device")

	var screen := SaveScreen.new()
	root.add_child(screen)
	_check(await _wait_for(screen, "Bring it back"), "the save picker offers the team game back:\n" + _texts(screen))
	_check("Lucky" in _texts(screen) and "Team game" in _texts(screen), "it says which game")
	_button(screen, "Bring it back").pressed.emit()
	for k in 60:
		if not Saves.describe(slot).is_empty():
			break
		await create_timer(0.1).timeout
	var back := Saves.describe(slot)
	_check(not back.is_empty() and String(back.team) == team_id, "it's back, on its team: %s" % [back])
	await create_timer(0.5).timeout
	_check(not "Bring it back" in _texts(screen), "and the card is gone")
	screen.queue_free()

	# A team with no copy of this member's pack anywhere: the card says how to rejoin it.
	var q := _game("Ghost")
	var other := Saves.slot_of(Profile.save_path)
	_check(await team.create(q) == "", "a second team")
	Saves.delete(other)  # never reached the cloud
	await cloud.sync()
	team.use("")
	screen = SaveScreen.new()
	root.add_child(screen)
	_check(await _wait_for(screen, "no copy of your pack is left"), "a team with no copy left says to join it again:\n" + _texts(screen))
	Saves.delete(slot)
	await cloud.sync()
	print("%d failure(s)" % _fails)
	quit()
