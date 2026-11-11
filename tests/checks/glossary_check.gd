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
	map._select(map.campaign.home)
	_check(map._info_where.text == "VA · Appalachia" and map._info_where.is_visible_in_tree(), "the info heading says where: " + map._info_where.text)
	var guide: Array = map.find_children("*", "Button", true, false).filter(func(b: Button) -> bool: return b.text == "Guide")
	_check(not guide.is_empty(), "the map has a Guide button")
	map.campaign.legends.assign(["woodbooger"])  # its lair has turned up; no other legend has
	guide[0].pressed.emit()
	await process_frame
	var shown: Array = map.find_children("*", "Glossary", true, false)
	_check(shown.size() == 1, "it opens the guide")
	var zombies: Array = shown[0].find_children("*", "Button", true, false).filter(func(b: Button) -> bool: return b.text == "Zombie guide")
	zombies[0].pressed.emit()
	await process_frame
	var zg: Array = shown[0].find_children("*", "ZombieGuide", true, false)
	_check(not zg.is_empty(), "and the zombie guide is one tap away")

	# Legends: only the ones with a lair on this map are written in.
	var texts := func(node: Node) -> Array:
		return node.find_children("*", "Label", true, false).map(func(l: Label) -> String: return l.text)
	var found: Array[String] = map.campaign.legends
	var seen: Array = texts.call(zg[0])
	_check("Legends" in seen, "the zombie guide has a Legends section")
	for id: String in GameData.LEGENDS:
		var named := seen.has(GameData.LEGENDS[id].name)
		if named != (id in found):
			_check(false, "%s is %s" % [id, "listed but not found" if named else "found but not listed"])
	_check(found.all(func(id: String) -> bool: return seen.has(GameData.LEGENDS[id].name)), "it lists the %d legend(s) found: %s" % [found.size(), ", ".join(found)])
	var none := ZombieGuide.new()
	root.add_child(none)
	await process_frame
	var empty: Array = texts.call(none)
	_check(not GameData.LEGENDS.values().any(func(l: Dictionary) -> bool: return empty.has(l.name)) and empty.any(func(t: String) -> bool: return t.begins_with("None found")),
		"with none found, no legend is shown")
	if not found.is_empty():
		var one := ZombieGuide.new()
		one.legends.assign([found[0]])
		root.add_child(one)
		await process_frame
		var lines: Array = texts.call(one)
		var legend: Dictionary = GameData.LEGENDS[found[0]]
		_check(lines.has(legend.lore) and lines.any(func(t: String) -> bool: return t.begins_with("Weak spot")) and lines.has("Drops: " + GameData.TRINKETS[legend.drop].name),
			"an entry has its lore, weak spot and drop")
	print("%d failure(s)" % _fails)
	quit()
