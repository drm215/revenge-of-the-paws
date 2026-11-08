extends SceneTree

## Catch-up XP: on a team, a pack below the team's strongest earns +10% XP per level behind (up to
## double) on its own fights and sweeps. Each player's pack level rides on the shared map.

var _fails := 0


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


func _profile(zip: String, pet: String, level: int) -> Profile:
	var p := Profile.new()
	p.region = "us_appalachia"
	p.zip = zip
	p.town = "x"
	p.pet_species = "dog"
	p.pet_name = pet
	p.team.assign(["black_bear", "horned_owl"])
	p.unlocked.assign(p.team)
	for id in ["dog", "black_bear", "horned_owl"]:
		p.xp[id] = GameData.xp_to_reach(level)
	return p


func _init() -> void:
	Profile.save_path = "user://cu_profile.cfg"
	_check(is_equal_approx(GameData.catch_up_mult(0), 1.0) and is_equal_approx(GameData.catch_up_mult(3), 1.3)
		and is_equal_approx(GameData.catch_up_mult(13), 2.0), "+10% per level behind, capped at double")

	var members := [{"user_id": "u1", "name": "Jack · Appalachia", "zip": "24210"},
		{"user_id": "u2", "name": "Biscuit · Appalachia", "zip": "24201"}]
	# Jack (Lv 45) fights: his level goes on the shared map.
	var jack := Campaign.create(_profile("24210", "Jack", 45), {"id": "t1", "state": "", "members": members})
	jack.my_id = "u1"
	_check(jack.levels_behind() == 0 and is_equal_approx(jack.catch_up_mult(), 1.0), "nobody to trail yet: no bonus")
	var i := _attackable(jack)
	jack.under_attack = -1
	jack.resolve_battle(i, true, 100)
	_check(int(jack.pack_levels.get("u1", 0)) == 45, "a fight records the fighter's pack level")
	_check(jack.levels_behind() == 0, "the strongest pack gets no catch-up")

	# Biscuit (Lv 39) loads the shared map: 6 behind, so +60%.
	var biscuit_profile := _profile("24201", "Biscuit", 39)
	var biscuit := Campaign.create(biscuit_profile, {"id": "t1", "state": jack.to_text(), "members": members})
	biscuit.my_id = "u2"
	_check(biscuit.levels_behind() == 6 and is_equal_approx(biscuit.catch_up_mult(), 1.6), "6 levels behind: +60%% (%.2f)" % biscuit.catch_up_mult())
	var far := _profile("24201", "Biscuit", 20)
	var way_behind := Campaign.create(far, {"id": "t1", "state": jack.to_text(), "members": members})
	way_behind.my_id = "u2"
	_check(is_equal_approx(way_behind.catch_up_mult(), 2.0), "25 levels behind: capped at double")

	# Sweep XP shows the bonus; the plain amount is what's shared.
	var s := -1
	for k in biscuit.territories.size():
		if biscuit.can_attack(k) and biscuit.territories[k].boss == "" and biscuit.warlord_at(k).is_empty():
			s = k
			break
	if s >= 0:
		biscuit.under_attack = -1
		biscuit.territories[s].met_level = 1
		biscuit.territories[s].threat = 2
		_check(biscuit.sweep_xp(s) == roundi(biscuit.sweep_xp(s, false) * 1.6) or abs(biscuit.sweep_xp(s) - biscuit.sweep_xp(s, false) * 1.6) <= 1,
			"Sweep pays the catch-up too (%d vs %d plain)" % [biscuit.sweep_xp(s), biscuit.sweep_xp(s, false)])

	# Solo: never any catch-up.
	var solo := Campaign.create(_profile("24201", "Solo", 10))
	_check(solo.levels_behind() == 0 and is_equal_approx(solo.catch_up_mult(), 1.0), "solo games get no catch-up")

	# The battle screen applies it to the pack's XP, and tells the player.
	var screen := BattleScreen.new()
	screen.profile = biscuit_profile
	screen.config = {"waves": [["shambler"]], "catch_up": 1.6, "behind": 6, "place": "x"}
	screen.battle = Battle.new(biscuit_profile, [["shambler"]])
	screen.battle.xp_earned = 100
	var before := int(biscuit_profile.xp.dog)
	var text := screen._award_xp(true)
	_check(int(biscuit_profile.xp.dog) == before + 160, "a won fight pays 160 instead of 100 (+%d)" % (int(biscuit_profile.xp.dog) - before))
	_check(screen.xp_awarded == 100, "teammates' share comes from the plain 100")
	_check(text.begins_with("Catch-up: +60% XP"), "the result says so: " + text.get_slice("\n", 0))
	screen.free()

	print("%d failure(s)" % _fails)
	quit()


func _attackable(c: Campaign) -> int:
	for k in c.territories.size():
		if c.can_attack(k):
			return k
	return -1
