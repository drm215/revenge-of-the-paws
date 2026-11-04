extends SceneTree

## Checks the five combat rules on hand-built battles.

var _fails := 0


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


func _profile() -> Profile:
	var p := Profile.new()
	p.region = "us_appalachia"
	p.team.assign(["black_bear", "bobcat", "horned_owl"])
	p.unlocked.assign(p.team)
	return p


func _init() -> void:
	var log: PackedStringArray = []

	# 7: wind-up, release, Guard soak, stun interrupt.
	var b := Battle.new(_profile(), [["brute"]], 1.0, 1.0, "test", 1)
	b.log_message.connect(func(t: String) -> void: log.append(t))
	b.start_next_wave()
	var brute: Combatant = b.enemies[0]
	brute.cooldowns.clear()
	var plan := b.plan_enemy_action(brute)
	_check(plan.skill == "rampage", "brute picks Rampage when ready")
	var hp_before: Array[int] = []
	for c in b.party:
		hp_before.append(c.hp)
	b.use_skill(brute, plan.skill, plan.target)
	_check(brute.winding == "rampage", "first turn only winds up")
	var untouched := true
	for i in b.party.size():
		untouched = untouched and b.party[i].hp == hp_before[i]
	_check(untouched, "nobody is hit during the wind-up")
	_check(b.plan_enemy_action(brute).skill == "rampage", "the wound-up attack comes next")
	b.party[0].add_status("guard", 2)
	for c in b.party:
		c.hp = c.max_hp
	b.use_skill(brute, "rampage", b.party[0])
	_check(brute.winding == "" and not brute.can_use("rampage"), "release clears the wind-up and starts the cooldown")
	var guarded_loss := 1.0 - b.party[0].hp_ratio()
	var open_loss := 1.0 - b.party[1].hp_ratio()
	print("     guarded bear lost %.0f%% HP, unguarded bobcat lost %.0f%%" % [guarded_loss * 100, open_loss * 100])
	_check(guarded_loss < open_loss, "Guard soaks the telegraphed hit")
	brute.cooldowns.clear()
	b.use_skill(brute, "rampage", b.party[0])
	brute.add_status("stunned", 1)
	b._turn_queue.assign([brute])
	b.next_turn()
	_check(brute.winding == "" and not brute.can_use("rampage"), "a stun cancels the wind-up and the cooldown runs")

	# 8: enrage.
	var e := Battle.new(_profile(), [["shambler"]], 1.0, 1.0, "test", 2)
	e.start_next_wave()
	var z: Combatant = e.enemies[0]
	var calm := e._base_damage(z, e.party[0], 1.0)
	e.round_number = Battle.ENRAGE_ROUND + 3
	_check(is_equal_approx(e._base_damage(z, e.party[0], 1.0) / calm, 1.3), "round %d: zombies +30%% ATK" % e.round_number)

	# 11: shambler horde, screamer frenzy, medic revive.
	var h := Battle.new(_profile(), [["shambler", "shambler", "shambler"]], 1.0, 1.0, "test", 3)
	h.start_next_wave()
	var lone := Battle.new(_profile(), [["shambler"]], 1.0, 1.0, "test", 3)
	lone.start_next_wave()
	var ratio := h._base_damage(h.enemies[0], h.party[0], 1.0) / lone._base_damage(lone.enemies[0], lone.party[0], 1.0)
	_check(is_equal_approx(ratio, 1.3), "3 shamblers: each +30%% ATK (got %.2f)" % ratio)
	var s := Battle.new(_profile(), [["screamer", "runner"]], 1.0, 1.0, "test", 4)
	s.start_next_wave()
	s.use_skill(s.enemies[0], "scream", s.party[0])
	_check(s.enemies[1].has_status("frenzied") and not s.enemies[0].has_status("frenzied"), "Scream frenzies the other zombies")
	var m := Battle.new(_profile(), [["medic", "runner"]], 1.0, 1.0, "test", 5)
	m.start_next_wave()
	var medic: Combatant = m.enemies[0]
	var runner: Combatant = m.enemies[1]
	medic.cooldowns.clear()
	_check(m.plan_enemy_action(medic).skill == "claw", "medic claws while nobody is down")
	m._apply_damage(runner, 9999, false)
	var xp_once := m.xp_earned
	var mp := m.plan_enemy_action(medic)
	_check(mp.skill == "reanimate" and mp.target == runner, "medic raises the destroyed runner")
	m.use_skill(medic, mp.skill, mp.target)
	_check(runner.is_alive() and runner.hp == roundi(runner.max_hp * 0.4), "runner back at 40%% HP (%d/%d)" % [runner.hp, runner.max_hp])
	m._apply_damage(runner, 9999, false)
	_check(m.xp_earned == xp_once, "no XP for killing it twice")
	medic.cooldowns.clear()
	_check(m.plan_enemy_action(medic).skill == "claw", "a zombie is raised only once")

	# 5 + 6: sit out a wave, cooldowns carry over.
	var w := Battle.new(_profile(), [["runner"], ["runner"], ["runner"]], 1.0, 1.0, "test", 6)
	w.start_next_wave()
	var bear: Combatant = w.party[0]
	w._apply_damage(bear, 99999, false)
	w.party[1].put_on_cooldown("pounce", 2)  # 3 turns left
	w._apply_damage(w.enemies[0], 9999, false)
	w.start_next_wave()
	_check(not bear.is_alive(), "knocked-out bear sits out wave 2")
	_check(w.party[1].cooldowns.get("pounce", 0) == 2, "cooldown carried over, ticked once by the rest (%d left)" % w.party[1].cooldowns.get("pounce", 0))
	w._apply_damage(w.enemies[0], 9999, false)
	w.start_next_wave()
	_check(bear.is_alive() and bear.hp == roundi(bear.max_hp * Battle.REVIVE_HP), "bear back at 25%% HP in wave 3")

	print("%d failure(s)" % _fails)
	quit(1 if _fails > 0 else 0)
