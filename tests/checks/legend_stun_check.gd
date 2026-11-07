extends SceneTree

## A legend can't be stun-locked: after a stun it shakes off the next ones for LEGEND_STUN_PROOF of
## its turns (Knockdown included), then can be stunned again. Ordinary zombies can still be locked.

var _fails := 0


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


func _profile() -> Profile:
	var p := Profile.new()
	p.region = "us_appalachia"
	p.pet_species = "dog"
	p.pet_name = "Jack"
	p.team.assign(["black_bear", "red_fox"])
	p.unlocked.assign(p.team)
	for id in ["dog", "black_bear", "red_fox"]:
		p.xp[id] = GameData.xp_to_reach(20)
	return p


## Gives `who` its turn (if it's stunned, the turn passes; otherwise it just ends it).
func _its_turn(b: Battle, who: Combatant) -> void:
	b._turn_queue.assign([who])
	if b.next_turn() == who:
		b._end_turn(who)


func _init() -> void:
	var log: Array[String] = []
	var b := Battle.new(_profile(), [["wampus_cat"]], 1.0, 1.0, "lair", 7)
	b.log_message.connect(func(t: String) -> void: log.append(t))
	b.start_next_wave()
	var legend: Combatant = b.enemies[0]
	var bear: Combatant = b.party.filter(func(c: Combatant) -> bool: return c.id == "black_bear")[0]
	_check(legend.is_boss, "(a legend)")

	# Weakened, then a heavy hit: Knockdown stuns it.
	legend.add_status("weakened", 5)
	b._deal_damage(bear, legend, GameData.KNOCKDOWN_POWER, 0.0)
	_check(legend.has_status("stunned"), "Knockdown stuns a weakened legend")
	_its_turn(b, legend)
	_check(not legend.has_status("stunned") and legend.statuses.get("stun_proof", 0) == GameData.LEGEND_STUN_PROOF,
		"its stunned turn passes, and it's stun-proof for %d turns" % GameData.LEGEND_STUN_PROOF)
	_check(log.any(func(t: String) -> bool: return "shakes it off" in t), "the log says so")

	# While stun-proof: Knockdown doesn't stun it.
	b._deal_damage(bear, legend, GameData.KNOCKDOWN_POWER, 0.0)
	_check(not legend.has_status("stunned"), "a second Knockdown right after doesn't stun it")
	for k in GameData.LEGEND_STUN_PROOF:
		_check(legend.has_status("stun_proof"), "turn %d after: still stun-proof" % (k + 1))
		legend.add_status("weakened", 5)
		b._deal_damage(bear, legend, GameData.KNOCKDOWN_POWER, 0.0)
		_check(not legend.has_status("stunned"), "turn %d after: can't be stunned" % (k + 1))
		_its_turn(b, legend)
	_check(not legend.has_status("stun_proof"), "after %d of its turns it can be stunned again" % GameData.LEGEND_STUN_PROOF)
	legend.add_status("weakened", 5)
	b._deal_damage(bear, legend, GameData.KNOCKDOWN_POWER, 0.0)
	_check(legend.has_status("stunned"), "and Knockdown stuns it again")

	# An ordinary zombie: stun after stun.
	var z := Battle.new(_profile(), [["brute"]], 1.0, 1.0, "test", 8)
	z.start_next_wave()
	var brute: Combatant = z.enemies[0]
	var z_bear: Combatant = z.party.filter(func(c: Combatant) -> bool: return c.id == "black_bear")[0]
	brute.add_status("weakened", 9)
	z._deal_damage(z_bear, brute, GameData.KNOCKDOWN_POWER, 0.0)
	_its_turn(z, brute)
	z._deal_damage(z_bear, brute, GameData.KNOCKDOWN_POWER, 0.0)
	_check(brute.has_status("stunned") and not brute.has_status("stun_proof"), "ordinary zombies can still be stunned again right away")

	# Last Gasp: below 10% it counts down its turns, stunned or not, then hits every animal hard.
	var g := Battle.new(_profile(), [["wampus_cat"]], 1.0, 1.0, "lair", 9)
	var counts: Array[int] = []
	g.last_gasp.connect(func(_l: Combatant, n: int) -> void: counts.append(n))
	g.start_next_wave()
	var cat: Combatant = g.enemies[0]
	var g_bear: Combatant = g.party.filter(func(c: Combatant) -> bool: return c.id == "black_bear")[0]
	cat.hp = roundi(cat.max_hp * 0.12)
	g._deal_damage(g_bear, cat, 0.3, 0.0)
	cat.hp = roundi(cat.max_hp * 0.09)
	g._apply_damage(cat, 1, false)
	_check(g._legend_phase.get(cat, 0) == 3 and counts == [GameData.LEGEND_LAST_GASP_TURNS], "at 10%% HP its Last Gasp starts counting (%s)" % [counts])
	for c in g.party:
		c.add_status("guard", 9)
	cat.add_status("stunned", 1)
	var before: Array[int] = []
	for c in g.party:
		before.append(c.hp)
	for k in GameData.LEGEND_LAST_GASP_TURNS:
		_its_turn(g, cat)
	_check(counts.slice(1) == [2, 1, 0], "it counts down on its own turns, stunned or not, and lands: %s" % [counts])
	var hit := true
	for k in g.party.size():
		var c: Combatant = g.party[k]
		hit = hit and (not c.is_alive() or before[k] - c.hp >= roundi(c.max_hp * GameData.LEGEND_LAST_GASP_DAMAGE) - 1)
	_check(hit, "every animal loses %d%% of its max HP, Guard or not" % roundi(GameData.LEGEND_LAST_GASP_DAMAGE * 100))
	_check(g._last_gasp[cat] == GameData.LEGEND_LAST_GASP_TURNS, "and if it's still standing, it counts again")

	var terms := {}
	for section: Array in Glossary.sections():
		for entry: Array in section[1]:
			terms[entry[0]] = entry[1]
	_check(terms.has("Last Gasp"), "the Guide explains the Last Gasp")
	_check(terms.has("Stun-proof") and str(GameData.LEGEND_STUN_PROOF) in String(terms["Stun-proof"]), "the Guide explains it")
	print("%d failure(s)" % _fails)
	quit()
