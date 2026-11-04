extends SceneTree

## One team per saved game, against fake_supabase.py.

var _fails := 0


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


func _init() -> void:
	_run.call_deferred()


func _profile(path: String, zip: String, pet: String) -> Profile:
	Profile.save_path = path
	var p := Profile.new()
	p.region = "us_appalachia"
	p.zip = zip
	p.town = "x"
	p.pet_species = "dog"
	p.pet_name = pet
	p.team.assign(["black_bear", "horned_owl"])
	p.unlocked.assign(p.team)
	p.save()
	return p


func _run() -> void:
	root.theme = Retro.make_theme()
	Campaign.save_path = "user://ps_campaign.cfg"
	Campaign.clear_saved()
	var cloud: Node = root.get_node("Cloud")
	var team: Node = root.get_node("Team")
	cloud.state_path = "user://ps_cloud.cfg"
	team.state_path = "user://ps_team.cfg"
	root.get_node("Chat").state_path = "user://ps_chat.cfg"
	cloud.base_url = OS.get_environment("FAKE_SUPABASE_URL")
	cloud.anon_key = "anon"
	cloud.log_out()
	await cloud.log_in("a@b.co", "oldpass")

	# Game 1 is played with a team, and the teammate has liberated land there.
	var g1 := _profile("user://ps_game1.cfg", "24210", "Jack")
	_check(await team.create(g1) == "" and g1.team_id != "", "game 1 has a team")
	var t1: String = g1.team_id
	var c1 := Campaign.create(g1, team.info)
	c1.my_id = cloud.user_id()
	c1.on_action = team.record
	c1.resolve_battle(c1.territories[c1.home].neighbors[0], true)
	await team.flush()
	_check(Campaign.create(g1, team.info).owned_count() == 2, "game 1's team map has a liberated territory")

	# A new game: solo, from scratch, even though the account is on a team.
	var g2 := _profile("user://ps_game2.cfg", "24201", "Biscuit")
	team.use(g2.team_id)
	_check(g2.team_id == "" and not team.on_team(), "the new game isn't on any team")
	var fresh := Campaign.create(g2)
	_check(fresh.owned_count() == 1 and fresh.homes.size() == 1, "its map is fresh: only home liberated, no teammates")

	# The partner step: Invite gives the new game its own team and a code.
	var screen := PartnerScreen.new()
	screen.profile = g2
	screen.size = Vector2(720, 1280)
	root.add_child(screen)
	await process_frame
	var invite: Button = null
	for b in screen.find_children("*", "Button", true, false):
		if b.text == "Invite a partner":
			invite = b
	invite.pressed.emit()
	for k in 40:
		await process_frame
		if screen.get("_invited") != "":
			break
	_check(g2.team_id != "" and g2.team_id != t1 and screen.get("_invited") != "", "Invite makes a separate team for the new game (code %s)" % screen.get("_invited"))
	for k in 3:
		await process_frame
	screen.queue_free()
	var mine: Array = await team.my_teams()
	_check(mine.size() == 2, "the account is on 2 teams now, one per game")

	# Back to game 1: its own team and map come back.
	team.use(t1)
	await team.refresh()
	_check(team.on_team() and String(team.info.id) == t1 and Campaign.create(g1, team.info).owned_count() == 2, "switching to game 1 brings its team map back")

	# Bring an existing team into another game.
	var g3 := _profile("user://ps_game3.cfg", "24211", "Rex")
	team.use("")
	var first: Dictionary = mine.filter(func(t: Dictionary) -> bool: return String(t.id) == t1)[0]
	_check(await team.bring_back(first, g3) == "" and g3.team_id == t1, "Play it in this game reattaches an existing team")

	# Leaving takes only this game off its team.
	team.use(g2.team_id)
	_check(await team.leave(g2) == "" and g2.team_id == "" and not team.on_team(), "leaving a team only affects this game")
	_check((await team.my_teams()).size() == 1, "the account keeps game 1's team")
	print("%d failure(s)" % _fails)
	quit()
