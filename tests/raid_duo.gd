extends SceneTree

## One player of a two-device raid test against fake_supabase.py. Args: A|B out_dir.
## Each device runs the real battle screen in raid mode, picking its own moves with the AI; B stalls
## on its first turn so A's device has to play it after the (shortened) timeout.

var role := ""
var out := ""
var cloud: Node
var team: Node
var raid: Node
var screen: BattleScreen
var profile: Profile
var _stalled := false
var _acting := false


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	role = args[0]
	out = args[1]
	LegendCutscene.read_limit = 0.5  # nobody here taps Continue on the legend's cut scenes
	_run.call_deferred()


func _log(text: String) -> void:
	print("[%s] %s" % [role, text])


func _profile() -> Profile:
	var p := Profile.new()
	p.region = "us_appalachia"
	p.zip = "24210" if role == "A" else "24201"
	p.town = "x"
	p.pet_species = "dog" if role == "A" else "cat"
	p.pet_name = "Jack" if role == "A" else "Biscuit"
	p.team.assign(["black_bear", "horned_owl"] if role == "A" else ["whitetail_deer", "bobcat"])
	p.unlocked.assign(p.team)
	for id in p.team + [p.pet_species]:
		p.xp[id] = GameData.xp_to_reach(6)
	p.save()
	return p


func _wait(cond: Callable, what: String, seconds := 60.0) -> bool:
	var since := Time.get_ticks_msec()
	while not cond.call():
		if (Time.get_ticks_msec() - since) / 1000.0 > seconds:
			_log("TIMEOUT waiting for " + what)
			return false
		await create_timer(0.5).timeout
	return true


func _run() -> void:
	Profile.save_path = "user://duo%s_profile.cfg" % role
	Campaign.save_path = "user://duo%s_campaign.cfg" % role
	cloud = root.get_node("Cloud")
	team = root.get_node("Team")
	raid = root.get_node("Raid")
	var chat: Node = root.get_node("Chat")
	cloud.state_path = "user://duo%s_cloud.cfg" % role
	team.state_path = "user://duo%s_team.cfg" % role
	chat.state_path = "user://duo%s_chat.cfg" % role
	cloud.base_url = OS.get_environment("FAKE_SUPABASE_URL")
	cloud.anon_key = "anon"
	raid.turn_timeout = 3.0
	cloud.log_out()
	await cloud.log_in("a@b.co" if role == "A" else "b@b.co", "oldpass" if role == "A" else "bpass")
	profile = _profile()  # this device's own profile (the fake server shares one cloud save)
	var code_file := out + "/duo_code.txt"
	if role == "A":
		DirAccess.remove_absolute(out + "/duo_A.txt")
		_log("create team: " + str(await team.create(profile)))
		FileAccess.open(code_file, FileAccess.WRITE).store_string(String(team.info.code))
		await _wait(func() -> bool:
			team.refresh()
			return team.info.get("members", []).size() == 2, "B to join the team")
		var c := Campaign.create(profile, team.info)
		var lair := c.territories[c.home].neighbors[0]
		c.territories[lair].boss = "woodbooger"
		var t := c.territories[lair]
		_log("open raid: '%s'" % await raid.open(t.id, t.boss, t.full_name(), team.name_for(profile), profile.snapshot()))
		await _wait(func() -> bool:
			raid.refresh()
			return raid.members().size() == 2 and raid.members().all(func(m: Dictionary) -> bool: return m.ready), "B to be ready")
		_log("start: '%s'" % await raid.start(c.raid_config(lair, 6)))
	else:
		DirAccess.remove_absolute(out + "/duo_B.txt")
		await _wait(func() -> bool: return FileAccess.file_exists(code_file), "the team code")
		_log("join team: '%s'" % await team.join(FileAccess.get_file_as_string(code_file), profile))
		await _wait(func() -> bool:
			raid.refresh()
			return raid.status() == "lobby", "a raid lobby")
		_log("join raid: '%s'" % await raid.join(team.name_for(profile), profile.snapshot(), true))
		await _wait(func() -> bool:
			raid.refresh()
			return raid.status() == "fighting", "the raid to start")
	raid.fast = true
	screen = BattleScreen.new()
	screen.profile = profile
	screen.config = raid.config()
	screen.raid = true
	screen.size = Vector2(720, 1280)
	root.add_child(screen)
	var done := [false]
	screen.raid_done.connect(func(result: Dictionary, here: bool) -> void:
		_log("raid done: won=%s recorded_here=%s" % [result.get("won"), here])
		done[0] = true)
	process_frame.connect(_drive)
	await _wait(func() -> bool: return done[0], "the raid to end", 240.0)
	await create_timer(1.0).timeout
	var b := screen.battle
	var state: PackedStringArray = []
	for c in b.party + b.enemies:
		state.append("%s=%d" % [c.display_name, c.hp])
	var lines: PackedStringArray = ["outcome=%d moves=%d xp_earned=%d" % [b.outcome(), screen.get("_seq"), b.xp_earned],
		"state=" + ",".join(state),
		"claimed=%s trinkets=%s dog_xp=%s cat_xp=%s" % [raid.info.id in profile.raids_claimed, profile.trinkets,
			profile.xp.get("dog", 0), profile.xp.get("cat", 0)]]
	FileAccess.open(out + "/duo_%s.txt" % role, FileAccess.WRITE).store_string("\n".join(lines))
	_log("wrote state")
	quit()


## Plays this device's own critters: the AI picks, as a player would tap. B stalls on its first turn.
func _drive() -> void:
	if screen == null or _acting or screen.get("_actor") == null:
		return
	var actor: Combatant = screen.get("_actor")
	_acting = true
	if role == "B" and not _stalled:
		_stalled = true
		_log("stalling on my first turn so A has to play it")
		await create_timer(6.0).timeout
	var plan := AutoBattle.pick_action(screen.battle, actor)
	screen.set("_selected_skill", plan.skill)
	screen.call("_execute", plan.target)
	_acting = false
