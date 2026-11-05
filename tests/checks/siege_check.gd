extends SceneTree

## Weekly siege against fake_supabase.py.

var _fails := 0


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	Profile.save_path = "user://siege_profile.cfg"
	Campaign.save_path = "user://siege_campaign.cfg"
	var cloud: Node = root.get_node("Cloud")
	cloud.state_path = "user://siege_cloud.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(cloud.state_path))
	cloud.base_url = OS.get_environment("FAKE_SUPABASE_URL")
	cloud.anon_key = "anon"
	cloud.log_out()
	var week := GameData.siege_week(Time.get_unix_time_from_system())

	var p := Profile.new()
	p.region = "us_appalachia"
	p.pet_species = "dog"
	p.pet_name = "Jack"
	p.team.assign(["black_bear", "horned_owl"])
	p.unlocked.assign(["black_bear", "horned_owl", "bobcat"])
	p.save()
	_check(p.siege_name() == "Jack · Appalachia", "leaderboard name hides the town: " + p.siege_name())

	# Kills from a real battle.
	var b := Battle.new(p, [["shambler", "shambler"]], 1.0, 1.0, "t", 1)
	b.start_next_wave()
	for z in b.enemies:
		b._apply_damage(z, 9999, false)
	_check(b.kills == 2, "battle counts 2 kills")

	cloud.siege_add(b.kills * 3, p.siege_name())
	_check(cloud.siege_pending(week) == 6, "signed out: damage is kept (6)")
	_check(await cloud.log_in("a@b.co", "oldpass") == "", "log in")
	await cloud.sync()
	_check(cloud.siege_pending(week) == 0, "logging in sent the waiting damage")
	var board: Dictionary = await cloud.siege_board(week)
	_check(int(board.total) == 6 and int(board.mine) == 6 and int(board.players) == 1, "board: %s" % board)
	_check(GameData.siege_goal(0, 1) == 500 and GameData.siege_goal(3, 2) == 20000, "stages scale with the packs in it")

	var screen := SiegeScreen.new()
	screen.profile = p
	screen.size = Vector2(720, 1280)
	root.add_child(screen)
	await create_timer(1.0).timeout
	screen.queue_free()

	# Another pack breaks the first stage.
	var ok: Variant = await _post_others([{"week": week, "user": "u2", "name": "Biscuit · Gulf Coast", "points": 1200}])
	board = await cloud.siege_board(week)
	var broken := GameData.siege_stage(int(board.total), int(board.players))
	_check(broken == 1, "with a second pack the first stage breaks (%d of %d)" % [int(board.total), GameData.siege_goal(0, int(board.players))])
	screen = SiegeScreen.new()
	screen.profile = p
	screen.size = Vector2(720, 1280)
	root.add_child(screen)
	await create_timer(1.0).timeout
	var buttons: Array[String] = []
	for btn in screen.find_children("*", "Button", true, false):
		buttons.append(btn.text)
	_check("Claim this week's reward (1)" in buttons, "claim button: %s" % [buttons])
	var trinkets := p.trinkets.size()
	var bear_xp: int = p.xp.get("black_bear", 0)
	var got := p.claim_siege(week, broken)
	_check(got != "" and p.trinkets.size() == trinkets + 1 and int(p.xp.get("black_bear", 0)) > bear_xp, "reward: trinket and XP\n" + got)
	_check(p.claim_siege(week, broken) == "", "can't claim twice")
	_check(Profile.load_saved().siege_claimed_stages(week) == 1, "claim is saved")
	print("%d failure(s)" % _fails)
	quit()


func _post_others(rows: Array) -> Variant:
	var http := HTTPRequest.new()
	root.add_child(http)
	http.request(OS.get_environment("FAKE_SUPABASE_URL") + "/_others", ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify(rows))
	await http.request_completed
	http.queue_free()
	return true
