extends SceneTree

## Rows: zombies can't land single-target hits on the back row while 2+ allies stand in front,
## unless a Runner reaches past or a taunt draws them; a Runner's reach is announced and on its card.

var _fails := 0


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


func _pack(team: Array) -> Profile:
	var p := Profile.new()
	p.region = "us_appalachia"
	p.pet_species = "dog"
	p.pet_name = "Jack"
	p.team.assign(team)
	p.unlocked.assign(team)
	return p


func _init() -> void:
	var waves := [["shambler", "brute", "shambler"], ["screamer", "plague", "bloater", "brute"], ["riot", "medic", "brute"]]
	var illegal := {}
	for seed_value in 200:
		var b := Battle.new(_pack(["bobcat", "horned_owl"]), waves, 1.0, 1.0, "t", seed_value)
		b.start_next_wave()
		var turns := 0
		while turns < 300:
			turns += 1
			var actor := b.next_turn()
			if actor == null:
				if b.outcome() == Battle.Outcome.WAVE_CLEARED:
					b.start_next_wave()
					continue
				break
			var plan := AutoBattle.pick_action(b, actor) if actor.is_player else b.plan_enemy_action(actor)
			var t: Combatant = plan.target
			if not actor.is_player and GameData.skill(plan.skill).target == "enemy" and t.row == "back":
				var fronts := Battle.living(b.party).filter(func(c: Combatant) -> bool: return c.row == "front").size()
				if fronts >= GameData.SCREEN_SIZE and not t.has_status("taunt") and not actor.traits.get("reach", false):
					illegal[actor.id + " " + plan.skill] = true
			b.use_skill(actor, plan.skill, t)
	_check(illegal.is_empty(), "no illegal back-row hits in 200 battles: %s" % [illegal.keys()])

	var b := Battle.new(_pack(["black_bear", "horned_owl"]), [["runner", "shambler", "shambler"]], 1.0, 1.0, "t", 1)
	var log: PackedStringArray = []
	b.log_message.connect(func(line: String) -> void: log.append(line))
	b.start_next_wave()
	var owl: Combatant = null
	var front: Combatant = null
	for c in b.party:
		if c.id == "horned_owl":
			owl = c
		elif c.row == "front":
			front = c
	b.use_skill(b.enemies[0], "lunge", owl)
	_check("reaches past the front row" in "\n".join(log), "a Runner hitting the back row is announced")
	log.clear()
	b.use_skill(b.enemies[0], "lunge", front)
	_check(not "reaches past" in "\n".join(log), "hitting the front row isn't")
	var card := UnitCard.new()
	card.battle = b
	card.setup(b.enemies[0], 150.0)
	root.add_child(card)
	card.refresh()
	_check("Reaches back row" in card.status_text(), "its card says so: " + card.status_text())
	card.free()
	print("%d failure(s)" % _fails)
	quit()
