extends SceneTree

## The pack screen keeps tiles that didn't change, and what it shows always matches a screen built
## from scratch. Also: a pet's name can't put markup in the battle log.

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
	p.team.assign(["black_bear", "bobcat"])
	p.unlocked.assign(["black_bear", "bobcat", "horned_owl", "whitetail_deer"])
	p.trinkets.assign([GameData.CACHE_TRINKETS[0]])
	for id in p.unlocked + ["dog"]:
		p.xp[id] = GameData.xp_to_reach(10)
	return p


## Every tile's text, in order, the way a player reads it.
func _read(screen: PackScreen) -> Array:
	var out: Array = []
	for card: Control in screen._roster_grid.get_children():
		var bits: PackedStringArray = []
		for n in card.find_children("*", "", true, false):
			if n is Label or n is Button:
				bits.append(n.text)
			if n is Button:
				bits.append("off" if n.disabled else "on")
		out.append(" | ".join(bits))
	return out


func _screen(p: Profile, cfg: Dictionary) -> PackScreen:
	var s := PackScreen.new()
	s.profile = p
	s.battle_config = cfg
	s.size = Vector2(720, 1280)
	root.add_child(s)
	return s


## After an action: the open screen reads exactly like a brand new one. (Opening Ready the pack
## empties the lineup, so the fresh screen is given it back and every tile is built again.)
func _same_as_fresh(screen: PackScreen, p: Profile, cfg: Dictionary, what: String) -> void:
	var team := p.team.duplicate()
	var duties := p.duties.duplicate()
	var fresh := _screen(p, cfg)
	p.team = team
	p.duties = duties
	for id: String in fresh._cards.keys():
		fresh._drop_card(id)
	fresh._refresh()
	var a := _read(screen)
	var b := _read(fresh)
	_check(a == b, what + ("" if a == b else "\n  open:  %s\n  fresh: %s" % [a, b]))
	fresh.free()


func _node(screen: PackScreen, id: String) -> Control:
	return screen._cards[id].node


func _run() -> void:
	root.theme = Retro.make_theme()
	Profile.save_path = "user://cards_profile.cfg"
	Campaign.save_path = "user://cards_campaign.cfg"
	var p := _profile()
	var c := Campaign.create(p)
	for cfg: Dictionary in [{}, c.battle_config(c.territories[c.home].neighbors[0])]:
		var label := "Ready the pack" if not cfg.is_empty() else "Pack"
		var lineup := p.team.duplicate()
		var screen := _screen(p, cfg)
		p.team = lineup
		screen._refresh()
		await process_frame
		var pet := _node(screen, "dog")
		var bear := _node(screen, "black_bear")

		screen._toggle("bobcat")  # out of the lineup
		_check(_node(screen, "dog") == pet and _node(screen, "black_bear") == bear,
			label + ": taking one out leaves the fighters' tiles alone")
		_same_as_fresh(screen, p, cfg, label + ": after taking one out")
		screen._toggle("horned_owl")  # into the lineup
		_same_as_fresh(screen, p, cfg, label + ": after putting one in")
		_check(screen._roster_grid.get_child_count() == 5, label + ": no ghost tiles")

		profile_row(p, "black_bear")
		screen._refresh()
		_check(_node(screen, "black_bear") != bear, label + ": a row change redraws that tile")
		_same_as_fresh(screen, p, cfg, label + ": after a row change")

		p.equipped["dog"] = p.trinkets[0]
		screen._refresh()
		_same_as_fresh(screen, p, cfg, label + ": after a trinket change")
		p.equipped.erase("dog")
		p.xp["whitetail_deer"] = GameData.xp_to_reach(11)
		screen._refresh()
		_same_as_fresh(screen, p, cfg, label + ": after a level up")
		p.injuries["dog"] = 2
		screen._refresh()
		_same_as_fresh(screen, p, cfg, label + ": after an injury")
		p.injuries.erase("dog")
		if cfg.is_empty():
			var count := screen._roster_grid.get_child_count()
			p.send_to_stable("whitetail_deer")
			screen._refresh()
			_check(screen._roster_grid.get_child_count() == count - 1, label + ": a stabled animal's tile goes")
			_check("Stable (1)" in screen._stable_button.text, label + ": the Stable button counts it")
			_same_as_fresh(screen, p, cfg, label + ": after stabling")
		screen.free()
		p = _profile()
		c = Campaign.create(p)

	var odd := _profile()
	odd.pet_name = "[font_size=200]Rex"
	var b := Battle.new(odd, [["shambler"]], 1.0, 1.0, "t", 1)
	_check(not "[" in b.party[0].display_name, "a pet's name can't carry markup: " + b.party[0].display_name)
	print("%d failure(s)" % _fails)
	quit()


func profile_row(p: Profile, id: String) -> void:
	p.toggle_row(id)
