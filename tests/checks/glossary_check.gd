extends SceneTree

## The guide: every core term is defined, with the game's real numbers, and the map opens it.

var _fails := 0


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	root.theme = Retro.make_theme()
	var terms := {}
	for section: Array in Glossary.sections():
		for entry: Array in section[1]:
			terms[entry[0]] = entry[1]
	for term in ["HP", "ATK (attack)", "DEF (defense)", "SPD (speed)", "Crit", "Power", "Front row", "Back row", "Stunned", "Infected", "Perfect wave", "Level", "Threat", "Pack strength", "Dungeon"]:
		_check(terms.has(term) and String(terms[term]).length() > 20, "defines %s" % term)
	_check("50" in terms["DEF (defense)"], "with the real numbers: " + terms["DEF (defense)"])
	_check(not terms.values().any(func(t: String) -> bool: return "%" in t.replace("%%", "") and t.contains("%d")), "every number is filled in")

	var p := Profile.new()
	p.region = "us_appalachia"
	p.zip = "24210"
	p.town = "Abingdon"
	p.pet_species = "dog"
	p.pet_name = "Jack"
	p.team.assign(["black_bear", "horned_owl"])
	p.unlocked.assign(["black_bear", "horned_owl"])
	Campaign.clear_saved()
	var map := MapScreen.new()
	map.profile = p
	map.campaign = Campaign.create(p)
	map.size = Vector2(720, 1280)
	root.add_child(map)
	await process_frame
	var guide: Array = map.find_children("*", "Button", true, false).filter(func(b: Button) -> bool: return b.text == "Guide")
	_check(not guide.is_empty(), "the map has a Guide button")
	guide[0].pressed.emit()
	await process_frame
	var shown: Array = map.find_children("*", "Glossary", true, false)
	_check(shown.size() == 1, "it opens the guide")
	var zombies: Array = shown[0].find_children("*", "Button", true, false).filter(func(b: Button) -> bool: return b.text == "Zombie guide")
	zombies[0].pressed.emit()
	await process_frame
	_check(not shown[0].find_children("*", "ZombieGuide", true, false).is_empty(), "and the zombie guide is one tap away")
	print("%d failure(s)" % _fails)
	quit()
