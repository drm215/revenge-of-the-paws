extends SceneTree

## A game that arrives from the cloud (another device, or put back from the dashboard) on a team:
## choosing it plays the team's map, not a fresh solo one, and a team change during a map moment
## still rebuilds the map once the moment ends.

var _fails := 0
var cloud: Node
var team: Node


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


func _init() -> void:
	_run.call_deferred()


func _frames(count: int) -> void:
	for k in count:
		await process_frame


func _run() -> void:
	cloud = root.get_node("Cloud")
	team = root.get_node("Team")
	cloud.state_path = "user://rt_cloud.cfg"
	team.state_path = "user://rt_team.cfg"
	cloud.base_url = OS.get_environment("FAKE_SUPABASE_URL")
	cloud.anon_key = "anon"
	cloud.log_out()
	_check(await cloud.log_in("a@b.co", "oldpass") == "", "log in")

	# A team game played a while: its map is a few turns in.
	var first := Saves.new_slot()
	Saves.use(first)
	var p := Profile.new()
	p.region = "us_appalachia"
	p.zip = "24210"
	p.town = "Abingdon"
	p.pet_species = "cat"
	p.pet_name = "Mo"
	p.team.assign(["black_bear", "horned_owl"])
	p.unlocked.assign(["black_bear", "horned_owl"])
	p.save()
	_check(await team.create(p) == "", "a team")
	var team_id := p.team_id
	var c := Campaign.create(p, team.info)
	c.my_id = cloud.user_id()
	c.on_action = team.record
	c.rest()
	c.rest()
	await team.flush()
	await team.refresh()
	var turn := c.turn
	_check(turn >= 2, "the team's map is on turn %d" % turn)

	# That game is lost; it comes back from the cloud as a new game with the same team.
	var text := FileAccess.get_file_as_string(Profile.save_path).replace('slot="%s"' % first, 'slot="save_restored"')
	Saves.delete(first)
	team.use("")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(Saves.DIR + "/save_restored"))
	var f := FileAccess.open(Saves.path("save_restored", Saves.PROFILE), FileAccess.WRITE)
	f.store_string(text)
	f.close()

	change_scene_to_file("res://scenes/main.tscn")
	await _frames(8)
	var main: Node = current_scene
	main.get_child(-1).chosen.emit("save_restored")
	var waited := 0.0
	while waited < 8.0 and not (main._campaign and main._campaign.is_team()):
		await create_timer(0.2).timeout
		waited += 0.2
	_check(main._campaign != null and main._campaign.is_team(), "it plays the team's map (team %s, game %s)" % [team.team_id, Profile.load_saved().team_id])
	_check(main._campaign != null and main._campaign.turn == turn, "on its turn (%d, not %d)" % [main._campaign.turn if main._campaign else -1, turn])
	_check(main.get_child(-1) is MapScreen, "the map is up")

	# The team changes while the map is in the middle of a moment (a siege banner, horde news): it's
	# rebuilt once the moment ends, not left as it was.
	var map: MapScreen = main.get_child(-1)
	map.celebrating = true
	team.changed.emit()
	await _frames(5)
	_check(main.get_child(-1) == map, "a moment isn't cut off")
	map.celebrating = false
	await _frames(5)
	_check(main.get_child(-1) is MapScreen and main.get_child(-1) != map and not main._campaign_stale, "then the map is rebuilt")
	print("%d failure(s)" % _fails)
	quit()
