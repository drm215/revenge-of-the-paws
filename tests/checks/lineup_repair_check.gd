extends SceneTree

## A played game saved with a half-picked lineup (the pre-fight pack screen empties it) still
## opens: loading fills the lineup instead of treating the game as unfinished setup, which could
## lead to Cancel deleting it.

var _fails := 0


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


func _init() -> void:
	Saves.use(Saves.new_slot())
	var p := Profile.new()
	p.region = "us_appalachia"
	p.zip = "24210"
	p.town = "Abingdon"
	p.pet_species = "cat"
	p.pet_name = "Peeper"
	p.unlocked.assign(["black_bear", "horned_owl", "red_fox", "opossum"])
	for id in p.unlocked:
		p.xp[id] = GameData.xp_to_reach(10)
	p.xp["red_fox"] = GameData.xp_to_reach(30)
	p.xp["cat"] = GameData.xp_to_reach(12)

	for lineup: Array in [[], ["opossum"], ["opossum", "opossum"], ["black_bear", "horned_owl", "red_fox", "opossum"], ["no_such_animal"]]:
		p.team.assign(lineup)
		p.save()
		var raw := ConfigFile.new()
		raw.load(Profile.save_path)
		_check((raw.get_value("profile", "team", []) as Array).size() == p.locals_needed(),
			"saving lineup %s writes a full one: %s (the game keeps %s while picking)" % [lineup, raw.get_value("profile", "team"), p.team])
		var back := Profile.load_saved()
		_check(back != null and back.team.size() == back.locals_needed() and back.is_complete(),
			"a played game saved with lineup %s opens with %s" % [lineup, back.team if back else "nothing"])
		if back and lineup.size() < back.locals_needed():
			_check("red_fox" in back.team, "the gap filled with the strongest (%s)" % [back.team])

	# A game that never got past setup (no XP yet) still counts as unfinished.
	var fresh := Profile.new()
	fresh.region = "us_appalachia"
	fresh.pet_species = "cat"
	fresh.pet_name = "New"
	fresh.save()
	_check(Profile.load_saved() == null, "an unfinished setup is still unfinished")
	print("%d failure(s)" % _fails)
	quit()
