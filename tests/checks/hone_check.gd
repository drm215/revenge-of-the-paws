extends SceneTree

## Honing: once an animal's tech tree and Training are full (Lv 82), its points still buy something:
## +1% Max HP, Attack and Defense each, with no cap.

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
	p.pet_name = "Shyamalan"
	p.team.assign(["black_bear", "horned_owl"])
	p.unlocked.assign(p.team)
	p.xp["cat"] = GameData.xp_to_reach(90)

	# Fill the whole tree and all Training.
	var bought := true
	while bought:
		bought = false
		for node in GameData.tech_tree("cat"):
			if p.buy_node("cat", node.id):
				bought = true
	var full := GameData.tech_tree("cat").all(func(n: Dictionary) -> bool: return p.owns("cat", n.id))
	_check(full and p.tree.cat.size() == 81, "the tree and Training take 81 points, all of Lv 82 (%d bought)" % p.tree.cat.size())
	_check(p.points_left("cat") == 8 and p.can_buy_any("cat"), "a Lv 90 pet still has 8 points, and something to spend them on")

	var before := p.build_unit("cat")
	for k in 8:
		_check(p.buy_node("cat", GameData.HONE_ID), "hone %d" % (k + 1)) if k == 0 or k == 7 else p.buy_node("cat", GameData.HONE_ID)
	var after := p.build_unit("cat")
	_check(p.honed("cat") == 8 and p.points_left("cat") == 0, "8 points honed, none left")
	_check(absf(float(after.max_hp) / before.max_hp - 1.08) < 0.02 and absf(float(after.atk) / before.atk - 1.08) < 0.03,
		"+8%% HP and ATK (HP %d -> %d, ATK %d -> %d)" % [before.max_hp, after.max_hp, before.atk, after.atk])
	_check(not p.buy_node("cat", GameData.HONE_ID) and not p.can_buy_any("cat"), "no points, no honing")

	p.save()
	var back := Profile.load_saved()
	_check(back.honed("cat") == 8 and back.build_unit("cat").max_hp == after.max_hp, "it's saved")
	back.reset_tree("cat")
	_check(back.honed("cat") == 0 and back.points_left("cat") == 89, "a reset gives the points back")

	# On screen: the Hone card sits with Training.
	root.theme = Retro.make_theme()
	p.reset_tree("cat")
	var screen := TechTreeScreen.new()
	screen.profile = p
	screen.units.assign(["cat"])
	root.add_child(screen)
	await process_frame
	await process_frame
	var texts := screen.find_children("*", "Label", true, false).map(func(l: Label) -> String: return l.text)
	_check(texts.any(func(t: String) -> bool: return t.begins_with("Hone")), "the tech tree shows Hone")
	print("%d failure(s)" % _fails)
	quit()
