extends SceneTree

## The siege's stages: what breaks them, what they give, what claiming does (old saves included), and
## how the game shows them: the screen, a fight's results, the map's button and its banner.

var _fails := 0


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


func _init() -> void:
	_run.call_deferred()


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


func _labels(n: Node) -> Array:
	return n.find_children("*", "Label", true, false).map(func(l: Label) -> String: return l.text)


func _real_wait(msec: int) -> void:
	var until := Time.get_ticks_msec() + msec
	while Time.get_ticks_msec() < until:
		await process_frame


func _run() -> void:
	root.theme = Retro.make_theme()
	var slot := Saves.new_slot()
	Saves.use(slot)

	# The stages.
	_check(GameData.siege_stage(0, 2) == 0, "no damage: no stages")
	_check(GameData.siege_stage(999, 2) == 0 and GameData.siege_stage(1000, 2) == 1, "the first breaks at 1000 for 2 packs")
	_check(GameData.siege_stage(11321, 2) == 3, "this week's real damage (11321, 2 packs) would reach Routed")
	_check(GameData.siege_stage(9999999, 2) == GameData.SIEGE_STAGES.size(), "it tops out")
	_check(GameData.siege_stage(1000, 1) > GameData.siege_stage(1000, 4), "more packs: tougher")
	for k in GameData.SIEGE_STAGES.size():
		_check(GameData.siege_reward_text(k) != "", "stage %d: %s" % [k, GameData.siege_reward_text(k)])

	# Claiming.
	var p := _profile()
	p.save()
	var week := GameData.siege_week(Time.get_unix_time_from_system())
	_check(p.claim_siege(week, 0) == "", "nothing broken: nothing to claim")
	var t0 := p.trinkets.size()
	var bear_xp: int = p.xp.get("black_bear", 0)
	_check(p.claim_siege(week, 1) != "", "the first stage pays")
	_check(p.trinkets.size() == t0 + 1 and int(p.xp.get("black_bear", 0)) > bear_xp, "a trinket and XP")
	_check(p.claim_siege(week, 1) == "", "only once")
	var t1 := p.trinkets.size()
	var xp1: int = p.xp.get("black_bear", 0)
	_check(p.claim_siege(week, 2) != "" and p.trinkets.size() == t1 and int(p.xp.get("black_bear", 0)) > xp1, "the second: XP alone")
	var t2 := p.trinkets.size()
	var message := p.claim_siege(week, 4)
	_check(p.trinkets.size() == t2 + 2, "two more stages at once: both trinkets: %s" % message)
	var legendary := false
	for id in GameData.LEGENDS:
		legendary = legendary or p.trinkets[-1] == GameData.LEGENDS[id].drop
	_check(legendary, "the last is a legendary drop: " + p.trinkets[-1])
	_check(Profile.load_saved().siege_claimed_stages(week) == 4, "claims are saved")

	# A week claimed before stages counts as the first stage: not paid twice, and the rest still pay.
	var old := _profile()
	old.siege_claimed.assign([week])
	var t3 := old.trinkets.size()
	_check(old.claim_siege(week, 1) == "", "an old claim isn't paid again")
	_check(old.claim_siege(week, 3) != "" and old.trinkets.size() == t3 + 1, "the later stages still pay")

	# A fight's results say what it did.
	var cloud: Node = root.get_node("Cloud")
	cloud.state_path = "user://ss_cloud.cfg"
	cloud.base_url = OS.get_environment("FAKE_SUPABASE_URL")
	cloud.anon_key = "anon"
	cloud.log_out()
	var b := BattleScreen.new()
	b.profile = _profile()
	b.config = {"waves": [["shambler", "shambler"]], "zombie_mult": 1.0, "party_mult": 1.0, "place": "t", "condition": "", "region": "us_appalachia", "threat": 4}
	b.size = Vector2(720, 1280)
	root.add_child(b)
	await process_frame
	for z in b.battle.enemies:
		b.battle._apply_damage(z, 99999, false)
	await process_frame
	b._show_outcome()
	await process_frame
	var name_now: String = GameData.siege_info(week).name
	_check(("+8 damage to " + name_now) in b._overlay_body.text, "results show the siege damage: " + b._overlay_body.text.get_slice("\n", b._overlay_body.text.get_slice_count("\n") - 1))
	b.free()

	# The screen: its ladder, in the real game, against the server.
	_check(await cloud.log_in("a@b.co", "oldpass") == "", "log in")
	var me := _profile()
	me.save()
	cloud.siege_add(600, me.siege_name())
	await cloud.sync()
	var screen := SiegeScreen.new()
	screen.profile = me
	screen.size = Vector2(720, 1280)
	root.add_child(screen)
	await _real_wait(800)
	var text := "\n".join(_labels(screen))
	_check("Breached" in text and "Annihilated" in text, "the screen lists the stages")
	_check("TO BROKEN" in text.to_upper() and "DONE: Breached" in text and "NEXT: Broken" in text, "shows what's broken and what's next")
	var claim := false
	for btn in screen.find_children("*", "Button", true, false):
		claim = claim or btn.text == "Claim this week's reward (1)"
	_check(claim, "offers the reward")
	screen.free()

	# The map: the banner, once; the button.
	var c := Campaign.create(me)
	var map := MapScreen.new()
	map.campaign = c
	map.profile = me
	map.size = Vector2(720, 1280)
	root.add_child(map)
	await process_frame
	var main := load("res://scripts/ui/main.gd").new() as Node
	root.add_child(main)
	await process_frame
	main.set("_profile", me)
	await main._check_siege(map)
	_check(map._siege_button.text == "Siege (1)", "the Siege button shows the reward waiting: " + map._siege_button.text)
	await _real_wait(200)
	var banner := name_now.to_upper() + ": BREACHED!"
	_check(banner in _labels(map), "the map announces the stage: " + banner)
	_check(map.celebrating, "and holds a teammate's rebuild while it does")
	var shown: Array = map._map.find_children("*", "Label", false, false).filter(func(l: Label) -> bool: return l.text != "")
	shown.sort_custom(func(a: Label, b2: Label) -> bool: return a.position.y < b2.position.y)
	_check(shown.size() == 2 and shown[1].position.y >= shown[0].position.y + shown[0].get_combined_minimum_size().y, "its two lines don't overlap")
	_check(GameData.siege_reward_text(1) == "Half a level for the pack", "the wording reads right: " + GameData.siege_reward_text(1))
	_check(int(me.siege_seen.get(week, 0)) == 1, "and remembers")
	await _real_wait(3200)
	_check(not map.celebrating, "then it's done")
	await main._check_siege(map)
	await _real_wait(200)
	_check(not banner in _labels(map), "it says so only once")
	me.claim_siege(week, 1)
	await main._check_siege(map)
	_check(map._siege_button.text == "Siege", "claimed: the button clears")

	# A banner waits its turn behind what's already playing.
	map.celebrating = true
	map.announce_siege("WAITING", "B")
	await _real_wait(150)
	_check(not "WAITING" in _labels(map), "a banner waits for what's playing")
	map.celebrating = false
	await _real_wait(150)
	_check("WAITING" in _labels(map), "then it plays")
	map.free()
	await _real_wait(200)
	_check(true, "leaving during it is safe")
	print("%d failure(s)" % _fails)
	quit()
