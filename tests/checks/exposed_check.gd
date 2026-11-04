extends SceneTree

var _fails := 0


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


func _init() -> void:
	var p := Profile.new()
	p.region = "us_appalachia"
	p.team.assign(["black_bear", "bobcat", "horned_owl"])
	p.unlocked.assign(p.team)
	var b := Battle.new(p, [["shambler", "screamer", "screamer"]], 1.0, 1.0, "t", 1)
	var log: PackedStringArray = []
	b.log_message.connect(func(t: String) -> void: log.append(t))
	b.start_next_wave()
	var owl: Combatant = b.party[2]
	_check(not b.exposed(owl), "owl screened by bear and bobcat")
	_check(b.exposed(b.enemies[1]), "zombie Screamers behind one Shambler are exposed")
	_check("\n".join(log).contains("The zombies' back row is exposed"), "wave start says the zombies' back row is open")
	_check(not "\n".join(log).contains("Your back row"), "but not yours")
	log.clear()
	b._apply_damage(b.party[1], 9999, false)
	_check(b.exposed(owl) and "\n".join(log).contains("Your back row is exposed"), "bobcat falls: owl exposed and announced")
	_check(owl in b.reachable(b.enemies[0]), "and a Shambler can now hit the owl")
	var card := UnitCard.new()
	card.battle = b
	card.setup(owl, 150.0)
	root.add_child(card)
	card.refresh()
	_check(card._status_label.text.contains("Exposed"), "owl card says Exposed")
	print("%d failure(s)" % _fails)
	quit()
