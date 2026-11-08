extends SceneTree

## Supply lines (30) and horde migration (33) on a real ZIP map, using test save files.

var _fails := 0


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


func _profile() -> Profile:
	var p := Profile.new()
	p.region = "us_appalachia"
	p.zip = "24210"
	p.town = "Abingdon"
	p.pet_species = "dog"
	p.pet_name = "Jack"
	p.team.assign(["black_bear", "horned_owl"])
	p.unlocked.assign(["black_bear", "horned_owl"])
	return p


func _init() -> void:
	Profile.save_path = "user://supply_profile.cfg"
	Campaign.save_path = "user://supply_campaign.cfg"
	Campaign.clear_saved()
	var p := _profile()
	var c := Campaign.create(p)
	var home := c.home
	_check(c.uses_zip_data, "real ZIP map (%d territories)" % c.territories.size())

	# --- Nests ---
	_check(c.nests.size() == 2, "two nests: %s" % [c.nests.map(func(i: int) -> String: return c.territories[i].full_name())])
	for n in c.nests:
		_check(c.territories[n].threat == GameData.MAX_THREAT and c.territories[n].boss == "" and n != home, "%s is a max-threat non-lair" % c.territories[n].full_name())

	# --- Supply: home -> a -> b, with b not next to home ---
	var a := -1
	var b := -1
	for x in c.territories[home].neighbors:
		for y in c.territories[x].neighbors:
			if y != home and y not in c.territories[home].neighbors and a < 0:
				a = x
				b = y
	c.territories[a].owned = true
	c.territories[b].owned = true
	c._ownership_changed()
	_check(not c.is_cut_off(b) and c.supplied().size() == 3, "home, a, b all linked")
	_check(c.cut_by(a) >= 1, "a is a chokepoint: losing it cuts off %d" % c.cut_by(a))
	var beyond := -1
	for y in c.territories[b].neighbors:
		if not c.territories[y].owned and not c.territories[a].neighbors.has(y) and not c.territories[home].neighbors.has(y):
			beyond = y
	_check(beyond >= 0 and c.can_attack(beyond), "can attack beyond b while linked")
	var linked_before := c.supplied().size()

	# Counterattacks go for the chokepoint most of the time.
	var hits := 0
	for k in 100:
		c.under_attack = -1
		c.last_event = ""
		c._start_counterattack()
		if c.under_attack == a:
			hits += 1
	_check(hits >= 55, "counterattack picks the chokepoint %d/100 times" % hits)
	c.under_attack = -1
	c.last_event = ""
	var tries := 0
	while c.under_attack != a and tries < 200:
		c.under_attack = -1
		c.last_event = ""
		c._start_counterattack()
		tries += 1
	_check("will be cut off" in c.last_event, "warning names the cost: " + c.last_event.strip_edges())

	# Lose the counterattack on a: b is cut off.
	c.resolve_battle(a, false)
	_check(c.is_cut_off(b) and not c.supplied().has(b), "b is cut off after a falls")
	_check("Cut off from home" in c.last_event, "event says so: " + c.last_event.replace("\n", " | "))
	_check(not c.can_attack(beyond), "can't attack from cut-off b")
	_check(c.supplied().size() < linked_before, "cut-off land stops counting toward pack strength (%d -> %d linked)" % [linked_before, c.supplied().size()])
	_check(is_equal_approx(GameData.held_bonus(0), 0.05) and is_equal_approx(GameData.held_bonus(19), 0.05) and is_equal_approx(GameData.held_bonus(20), 0.06) and is_equal_approx(GameData.held_bonus(220), 0.16) and is_equal_approx(GameData.held_bonus(1000), GameData.MAX_HELD_BONUS),
		"pack strength: +5%%, then +1%% per %d held, up to +%d%%" % [GameData.HELD_PER_PERCENT, roundi(GameData.MAX_HELD_BONUS * 100)])
	_check(c.turns_until_lost(b) == 2, "falls in 2 turns")
	c.under_attack = b
	_check(c.battle_config(b).threat == c.territories[b].threat + 1, "defending cut-off b is 1 threat harder")
	c.under_attack = -1

	# Reload keeps the countdown.
	var c2 := Campaign.create(p)
	_check(c2.is_cut_off(b) and c2.turns_until_lost(b) == 2, "countdown survives a reload")

	# Two more turns: it falls.
	c.rest()
	_check(c.territories[b].owned and c.turns_until_lost(b) == 1, "1 turn left after resting")
	c.rest()
	_check(not c.territories[b].owned and "overran" in c.last_event, "b falls: " + c.last_event.replace("\n", " | "))

	# Reconnecting in time saves it.
	c.territories[b].owned = true
	c._ownership_changed()
	c.rest()
	_check(c.is_cut_off(b), "b cut off again")
	c.resolve_battle(a, true)
	_check(not c.is_cut_off(b) and "Supply restored" in c.last_event and not c.cut_off.has(c.territories[b].id), "retaking a restores supply: " + c.last_event.replace("\n", " | "))

	# --- Migration ---
	Campaign.clear_saved()
	c = Campaign.create(_profile())
	var before := {}
	for t in c.territories:
		before[t.id] = t.threat
	for k in 12:
		c._migrate()
	var raised := 0
	var bad := 0
	for t in c.territories:
		if t.threat > before[t.id]:
			raised += 1
			if t.owned or t.boss != "" or t.threat > GameData.MAX_THREAT or c.spread.get(t.id, 0) > GameData.MAX_SPREAD:
				bad += 1
	var steps := 0
	for id in c.spread:
		steps += c.spread[id]
	_check(steps == 24 and raised > 0, "12 rounds x 2 nests (no land held) = %d threat added over %d areas" % [steps, raised])
	_check(bad == 0, "never on held land, lairs, or past the cap")
	print("     " + c.last_event.strip_edges().split("\n")[-1])
	c.save()
	var c3 := Campaign.create(_profile())
	var same := true
	for i in c.territories.size():
		if c3.territories[i].threat != c.territories[i].threat:
			same = false
	_check(same, "spread threat survives a reload")
	# Liberating a nest stops it.
	var nest := c.nests[0]
	c.resolve_battle(nest, true)
	_check(c.territories[nest].id in c.cleared_nests and not c.is_nest(nest) and "nest is destroyed" in c.last_event, "liberated nest is destroyed")
	c.territories[nest].owned = false
	c._ownership_changed()
	_check(not c.is_nest(nest), "and stays gone if the horde retakes it")
	Campaign.clear_saved()
	print("%d failure(s)" % _fails)
	quit()
