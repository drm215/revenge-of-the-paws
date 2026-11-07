extends SceneTree

## Clearing a state (and so a region): recorded once and shared on a team; each player then gets one
## random permanent bonus and gives it to a critter of their own. On the real screens.

var _fails := 0


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


func _init() -> void:
	_run.call_deferred()


func _profile(pet := "Jack") -> Profile:
	var p := Profile.new()
	p.region = "us_mid_atlantic"
	p.zip = "20001"
	p.town = "Washington"
	p.pet_species = "dog"
	p.pet_name = pet
	p.team.assign(["black_bear", "horned_owl"])
	p.unlocked.assign(["black_bear", "horned_owl"])
	return p


func _dc(c: Campaign) -> Array[int]:
	var out: Array[int] = []
	for i in c.territories.size():
		if c._state_of(i) == "DC":
			out.append(i)
	return out


func _buttons(n: Node) -> Array:
	return n.find_children("*", "Button", true, false).filter(func(b: Button) -> bool: return b.is_visible_in_tree()).map(func(b: Button) -> String: return b.text)


func _run() -> void:
	root.theme = Retro.make_theme()
	var slot := Saves.new_slot()
	Saves.use(slot)

	# The real counts.
	_check(ZipDB.state_areas("VA") == 903 and ZipDB.state_areas("DC") == 57, "states count their real ZIP areas (VA %d, DC %d)" % [ZipDB.state_areas("VA"), ZipDB.state_areas("DC")])

	var p := _profile()
	Campaign.clear_saved()
	var c := Campaign.create(p)
	var dc := _dc(c)
	_check(dc.size() >= 5, "the DC map has DC land (%d of 57)" % dc.size())
	var first: int = dc.filter(func(k: int) -> bool: return not c.territories[k].owned)[0]
	_check(c.state_progress(first) == "" and c.state_freed("DC") < 57, "no count on screen while it's being freed")

	# Clearing it: as if this map had all of DC (the rest of the region's states too, so it clears).
	ZipDB.state_areas("DC")
	ZipDB._state_areas["DC"] = dc.size()
	for s in ["NY", "NJ", "PA", "DE", "MD"]:
		ZipDB._state_areas[s] = 0
	var last := -1
	for k in dc:
		if not c.territories[k].owned:
			last = k
	for k in dc:
		if k != last:
			c.territories[k].owned = true
	c._ownership_changed()
	c.under_attack = -1
	c.resolve_battle(last, true, 0, [], false)
	_check("state:DC" in c.cleared, "freeing the last of it clears the state")
	_check("region:us_mid_atlantic" in c.cleared, "and with every state in it cleared, the region")
	var moment := c.take_liberation()
	_check(moment.milestone_big and "CLEARED" in moment.milestone, "a big moment: " + moment.milestone)
	_check(c.state_progress(last) == "Washington, DC: cleared!", "progress says so")
	var count := c.cleared.size()
	c.territories[last].owned = false
	c._ownership_changed()
	c.resolve_battle(last, true, 0, [], false)
	_check(c.cleared.size() == count, "once only")

	# The bonus: rolled once, given to a critter of the player's choice, for good.
	var waiting := p.bonuses_waiting(c.cleared)
	_check(waiting.size() == 2, "two bonuses wait: %s" % [waiting])
	var offer := p.bonus_offer("state:DC")
	_check(p.bonus_offer("state:DC") == offer, "the roll is kept: " + GameData.bonus_text(offer))
	var region_offer := p.bonus_offer("region:us_mid_atlantic")
	var base: float = GameData.CLEAR_BONUSES.filter(func(b: Dictionary) -> bool: return b.stat == region_offer.stat)[0].amount
	_check(is_equal_approx(float(region_offer.amount), base * GameData.REGION_BONUS_SCALE), "a region's is bigger: " + GameData.bonus_text(region_offer))
	var before := p.build_unit("black_bear")
	p.bonus_offers["state:DC"] = {"stat": "atk", "amount": 0.08}
	_check(p.take_bonus("state:DC", "black_bear"), "the bear takes it")
	var after := p.build_unit("black_bear")
	_check(after.atk > before.atk, "and hits harder for good (ATK %d to %d)" % [before.atk, after.atk])
	_check(not p.take_bonus("state:DC", "horned_owl"), "it can't be given twice")
	_check(p.bonuses_waiting(c.cleared) == ["region:us_mid_atlantic"], "one left")
	_check(Profile.load_saved().bonuses.black_bear.atk == 0.08, "saved")

	# On a team: the map's clearing is shared; each player claims their own.
	var members := [{"user_id": "u1", "name": "A", "zip": "20001"}, {"user_id": "u2", "name": "B", "zip": "20001"}]
	var team_a := Campaign.create(_profile("Jack"), {"id": "t1", "state": "", "members": members})
	team_a.cleared.append("state:DC")
	var partner := _profile("Biscuit")
	var team_b := Campaign.create(partner, {"id": "t1", "state": team_a.to_text(), "members": members})
	_check("state:DC" in team_b.cleared, "teammates share what's cleared")
	_check(partner.bonuses_waiting(team_b.cleared) == ["state:DC"], "and each gets their own bonus")

	# The real screens: the map's button, the choice, back to the map.
	var me := _profile()
	me.save()
	c.save()
	change_scene_to_file("res://scenes/main.tscn")
	for k in 8:
		await process_frame
	var main: Node = current_scene
	main.get_child(-1).chosen.emit(slot)
	for k in 6:
		await process_frame
	var map: MapScreen = main.get_child(-1)
	var shown: Array = _buttons(map).filter(func(t: String) -> bool: return "Claim your bonus" in t)
	_check(not shown.is_empty(), "the map offers the bonus: %s" % [shown])
	map.bonus_requested.emit()
	await process_frame
	var screen: Node = main.get_child(-1)
	_check(screen is BonusScreen, "it opens the choice")
	var labels: Array = screen.find_children("*", "Label", true, false).map(func(l: Label) -> String: return l.text)
	_check(labels.any(func(t: String) -> bool: return "CLEARED!" in t) and labels.any(func(t: String) -> bool: return t.begins_with("+")), "showing what was cleared and the bonus")
	var picks: Array = screen.find_children("*", "Button", true, false).filter(func(b: Button) -> bool: return b.text.begins_with("Black Bear"))
	_check(not picks.is_empty(), "with the player's own critters to pick from")
	var given: int = main._profile.bonuses_waiting(main._campaign.cleared).size()
	picks[0].pressed.emit()
	await process_frame
	_check(main._profile.bonuses_waiting(main._campaign.cleared).size() == given - 1, "picking gives it")
	_check(_buttons(screen).has("Back to map"), "then back to the map")
	print("%d failure(s)" % _fails)
	quit()
