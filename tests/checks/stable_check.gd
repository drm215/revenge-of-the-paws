extends SceneTree

## Checks the Stable rules on a throwaway profile and campaign.

var _fails := 0


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


func _init() -> void:
	Profile.save_path = "user://stable_profile.cfg"
	Campaign.save_path = "user://stable_campaign.cfg"
	Campaign.clear_saved()
	var info := ZipDB.lookup("24343")
	var p := Profile.new()
	p.region = info.region
	p.zip = "24343"
	p.town = info.place
	p.pet_species = GameData.PETS.keys()[0]
	p.pet_name = "Jack"
	var home: Array = GameData.REGIONS[p.region].animals
	p.team.assign(home.slice(0, 2))
	p.unlock(home)
	_check(p.stable.is_empty(), "pet + %d home animals fit with no Stable" % home.size())

	# An old save: 10 animals unlocked, pet at Lv 20, nothing stabled.
	var extra := ["alligator", "bobcat", "gray_wolf", "raccoon", "crow", "opossum"]
	for id in extra:
		if id not in p.unlocked:
			p.unlocked.append(id)
	for id in p.unlocked:
		p.xp[id] = GameData.xp_to_reach(5 + p.unlocked.find(id))
	p.xp[p.pet_species] = GameData.xp_to_reach(20)
	p.duties = {"scout": p.unlocked[2]}
	p.save()
	var q := Profile.load_saved()
	_check(q.active().size() == q.active_slots() and q.active_slots() == 5, "old save trimmed to pet + 5 (active %d)" % q.active().size())
	_check(q.stable.size() == q.unlocked.size() - 5, "the rest went to the Stable (%d)" % q.stable.size())
	for id in q.team:
		_check(id not in q.stable, "fighter %s stays in the pack" % id)
	var lowest_active := 99
	for id in q.active():
		if id not in q.team:
			lowest_active = mini(lowest_active, q.level_of(id))
	var highest_stabled := 0
	for id in q.stable:
		highest_stabled = maxi(highest_stabled, q.level_of(id))
	_check(highest_stabled <= lowest_active, "lowest-level reserves were stabled (stable max Lv %d <= reserve min Lv %d)" % [highest_stabled, lowest_active])
	for duty in q.duties:
		_check(q.duties[duty] not in q.stable, "duty %s is held by a pack animal" % duty)

	# XP: stabled animals earn none, reserves earn half.
	var reserve := ""
	for id in q.active():
		if id not in q.team:
			reserve = id
			break
	var stabled: String = q.stable[0]
	var before_r: int = q.xp[reserve]
	var before_s: int = q.xp[stabled]
	var fought: Array[String] = q.pack_ids()
	q.after_battle(fought, [], 100)
	_check(q.xp[reserve] - before_r == 50, "reserve earned 50 of 100 XP (%d)" % (q.xp[reserve] - before_r))
	_check(q.xp[stabled] == before_s, "stabled animal earned nothing")

	# A recruit with a full pack goes to the Stable at 50% of the strongest pack level.
	var strongest := q.strongest_pack_level()
	q.unlock(["moose"] if "moose" not in q.unlocked else ["bison"])
	var recruit: String = q.unlocked[-1]
	_check(recruit in q.stable, "recruit %s waits in the Stable when the pack is full" % recruit)
	_check(q.level_of(recruit) == maxi(1, roundi(strongest * GameData.RECRUIT_LEVEL_SHARE)), "recruit joined at Lv %d (strongest pack Lv %d)" % [q.level_of(recruit), strongest])

	# Bringing one back needs a free slot and costs a turn; sending is free.
	var c := Campaign.create(q)
	var turn := c.turn
	c.bring_from_stable(recruit)
	_check(recruit in q.stable and c.turn == turn, "can't bring one back into a full pack")
	q.send_to_stable(reserve)
	_check(reserve in q.stable and c.turn == turn, "sending a reserve is free")
	q.send_to_stable(q.team[0])
	_check(q.team[0] not in q.stable, "a fighter can't be stabled")
	c.bring_from_stable(recruit)
	_check(recruit not in q.stable and c.turn == turn + 1, "bringing one back takes a turn")
	_check(q.active().size() == q.active_slots(), "pack is full again")

	Campaign.clear_saved()
	Profile.clear_saved()
	print("%d failure(s)" % _fails)
	quit(1 if _fails > 0 else 0)
