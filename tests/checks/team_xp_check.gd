extends SceneTree

## Team XP share: 10% to teammates whose home links to the fighter's through held land.

var _fails := 0


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


func _profile(zip: String, pet: String) -> Profile:
	var p := Profile.new()
	p.region = "us_appalachia"
	p.zip = zip
	p.town = "x"
	p.pet_species = "dog"
	p.pet_name = pet
	p.team.assign(["black_bear", "horned_owl"])
	p.unlocked.assign(p.team)
	return p


func _init() -> void:
	Profile.save_path = "user://txp_profile.cfg"
	var members := [{"user_id": "u1", "name": "Jack · Appalachia", "zip": "24210"},
		{"user_id": "u2", "name": "Biscuit · Appalachia", "zip": "24201"}]
	var pb := _profile("24201", "Biscuit")
	var c := Campaign.create(pb, {"id": "t1", "state": "", "members": members})
	c.me = "Biscuit · Appalachia"
	c.my_id = "u2"
	var jack_home := c.homes[0] if c.homes[0] != c.home else c.homes[1]

	# Shortest path of territories from Bristol (B) to Abingdon (Jack).
	var prev := {c.home: -1}
	var queue: Array[int] = [c.home]
	while not queue.is_empty():
		var i: int = queue.pop_front()
		for n in c.territories[i].neighbors:
			if not prev.has(n):
				prev[n] = i
				queue.append(n)
	var path: Array[int] = []
	var k: int = prev[jack_home]
	while k != c.home:
		path.push_front(k)
		k = prev[k]
	print("     path between homes: %s" % [path.map(func(i: int) -> String: return c.territories[i].full_name())])

	_check(not c.homes_linked(jack_home), "homes start unlinked")
	# Liberate all but the last link: Jack gets nothing.
	for j in path.size() - 1:
		c.under_attack = -1
		c.resolve_battle(path[j], true, 100)
	_check(not c.shared_xp.has("u1"), "no continuous line yet: Jack gets no XP (%s)" % [c.shared_xp])
	# A lost attack on the last link: still no line.
	c.under_attack = -1
	c.resolve_battle(path[-1], false, 100)
	_check(not c.shared_xp.has("u1"), "a lost attack doesn't link them")
	# Liberating the last link joins the homes: that battle's XP is shared.
	c.under_attack = -1
	c.resolve_battle(path[-1], true, 150)
	_check(c.homes_linked(jack_home) and int(c.shared_xp.get("u1", 0)) == 15, "the battle that links the homes shares 10%%: Jack is owed %s" % [c.shared_xp.get("u1", 0)])
	_check(not c.shared_xp.has("u2"), "the fighter gets no share of their own battle")
	# Any later battle while linked shares too, wherever it is.
	var far := -1
	for i in c.territories.size():
		if c.can_attack(i) and far < 0:
			far = i
	c.under_attack = -1
	c.resolve_battle(far, false, 40)
	_check(int(c.shared_xp.get("u1", 0)) == 19, "a lost battle shares 10%% too (+4 -> %d)" % int(c.shared_xp.get("u1", 0)))

	# Survives the shared text (what goes to the server).
	var text := c.to_text()
	var back := Campaign.create(pb, {"id": "t1", "state": text, "members": members})
	_check(int(back.shared_xp.get("u1", 0)) == 19, "the owed XP is saved on the shared map")

	# Jack's device collects it once.
	var pa := _profile("24210", "Jack")
	var before: int = pa.xp.get("dog", 0)
	_check(pa.collect_team_xp(back.team_key(), 19) == 19 and int(pa.xp.get("dog", 0)) == before + 19 and int(pa.xp.get("black_bear", 0)) == 19, "Jack's pet and fighters each get +19")
	_check(pa.collect_team_xp(back.team_key(), 19) == 0, "collected only once")
	_check(pa.collect_team_xp(back.team_key(), 25) == 6, "later shares add only the new XP")

	# Patrols don't share.
	c.resolve_patrol(path[0], true)
	_check(int(c.shared_xp.get("u1", 0)) == 19, "patrols don't share XP")
	print("%d failure(s)" % _fails)
	quit()
