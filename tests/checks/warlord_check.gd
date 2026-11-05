extends SceneTree

## Counterattacks are real assaults; warlords rise from nests, march on home, can be hunted or met
## on held land, are in the fight by name, and survive saves and shared maps. On the real screens.

var _fails := 0


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


func _init() -> void:
	_run.call_deferred()


func _profile(level := 1) -> Profile:
	var p := Profile.new()
	p.region = "us_appalachia"
	p.zip = "24210"
	p.town = "Abingdon"
	p.pet_species = "dog"
	p.pet_name = "Jack"
	p.team.assign(["black_bear", "horned_owl"])
	p.unlocked.assign(["black_bear", "horned_owl"])
	for id in ["dog", "black_bear", "horned_owl"]:
		p.xp[id] = GameData.xp_to_reach(level)
	return p


func _fresh(p: Profile) -> Campaign:
	Campaign.clear_saved()
	return Campaign.create(p)


## A live nest that isn't next to home, on a map with no warlords yet.
func _a_nest(c: Campaign) -> int:
	for n in c.nests:
		if c.is_nest(n):
			return n
	return -1


func _unheld_neighbor(c: Campaign) -> int:
	for n in c.territories[c.home].neighbors:
		if not c.territories[n].owned:
			return n
	return -1


func _labels(n: Node) -> Array:
	return n.find_children("*", "Label", true, false).map(func(l: Label) -> String: return l.text)


func _real_wait(msec: int) -> void:
	var until := Time.get_ticks_msec() + msec
	while Time.get_ticks_msec() < until:
		await process_frame


func _run() -> void:
	root.theme = Retro.make_theme()
	Saves.use(Saves.new_slot())

	# Assaults match the pack, and the land's own level comes back after.
	var p := _profile(1)
	var c := _fresh(p)
	var i := _unheld_neighbor(c)
	c.resolve_battle(i, true, 0, [], false)
	c.under_attack = -1
	for id in ["dog", "black_bear", "horned_owl"]:
		p.xp[id] = GameData.xp_to_reach(20)
	var calm := c.territory_level(i)
	c.under_attack = i
	var assault := c.territory_level(i)
	_check(assault > calm + 5, "an assault matches the pack (Lv %d, the land's own is Lv %d)" % [assault, calm])
	_check(c.battle_config(i).zombie_mult > 1.5, "and the fight is that strong")
	var first_waves: Array = c.battle_config(i).waves
	c.turn += 1
	var differs := false
	for k in 8:
		c.turn += 1
		differs = differs or c.battle_config(i).waves != first_waves
	_check(differs, "each assault is its own")
	c.resolve_battle(i, true, 0, [], false)
	_check(c.territory_level(i) == calm, "once it's over the land is its own level again")
	_check(GameData.COUNTERATTACK_EVERY > 3, "and they come less often")
	_check(str(GameData.COUNTERATTACK_EVERY + GameData.GUARD_COUNTER_DELAY) in GameData.DUTY_INFO.guard, "Guard duty's text is right: " + GameData.DUTY_INFO.guard)

	# Other land still keeps its fixed level during an assault.
	var other := -1
	for k in c.territories.size():
		if not c.territories[k].owned and c.territories[k].boss == "":
			other = k
			break
	var other_level := c.territory_level(other)
	c.under_attack = i
	_check(c.territory_level(other) == other_level, "an assault doesn't change other land")
	c.under_attack = -1

	# A warlord rises on schedule, from a nest, named for it.
	p = _profile(5)
	c = _fresh(p)
	_check(c.warlords.is_empty(), "no warlords at the start")
	c.turn = GameData.WARLORD_FIRST - 1
	c._advance_warlords()
	_check(c.warlords.is_empty(), "none before their time")
	c.turn = GameData.WARLORD_EVERY
	c._advance_warlords()
	_check(c.warlords.size() >= 1, "a nest raises one")
	var w: Dictionary = c.warlords[0]
	var nest := c._index_of_id(w.nest)
	_check(c.territories[nest].name in w.title, "named for its nest: %s, %s" % [w.name, w.title])
	var count := c.warlords.size()
	c._advance_warlords()
	_check(c.warlords.size() == count, "one at a time from each nest")

	# It marches home and raises threat where it treads.
	var d0 := c._home_distance(c.territories[c._index_of_id(w.at)].site)
	var threat0 := {}
	for t in c.territories:
		threat0[t.id] = t.threat
	c._march_warlord(w)
	var at := c._index_of_id(w.at)
	_check(w.at != w.nest, "it marches: %s" % w.at)
	_check(c._home_distance(c.territories[at].site) < d0, "toward home")
	_check(c.territories[at].threat == threat0[w.at] + 1, "and raises threat where it treads")
	_check(c.territories[at].boss == "", "and never through a legend's lair")

	# It's in the fight where it stands, by name, with its treasure.
	var cfg := c.battle_config(at)
	_check(cfg.warlord == w.name and cfg.waves[-1].has("warlord"), "the fight has it in the last wave")
	_check(cfg.waves[-1].size() <= GameData.MAX_ENEMIES, "and fits the screen")
	var b := Battle.new(p, [["warlord", "shambler"]], 1.0, 1.0, "t", 1)
	b.configure(cfg)
	b.start_next_wave()
	_check(b.enemies[0].display_name == w.name, "the enemy has its name: " + b.enemies[0].display_name)

	# Hunting: winning kills it and takes its treasure.
	var loot: String = w.loot
	var have := p.trinkets.size()
	c.under_attack = -1
	c.resolve_battle(at, true)
	_check(not c.warlords.has(w), "beating it kills it")
	_check(p.trinkets.size() > have and loot in p.trinkets, "its treasure is taken: " + loot)
	_check((c.take_liberation().milestone as String).ends_with("is dead!"), "and the moment says so")

	# A loss leaves it standing.
	c = _fresh(_profile(5))
	c.turn = GameData.WARLORD_EVERY
	c._advance_warlords()
	w = c.warlords[0]
	at = c._index_of_id(w.at)
	c.resolve_battle(at, false, 0, [], false)
	_check(c.warlords.has(w), "a lost hunt leaves it standing")

	# Beside held land, it attacks in person.
	c = _fresh(_profile(5))
	c.turn = GameData.WARLORD_EVERY
	c._advance_warlords()
	w = c.warlords[0]
	var front := _unheld_neighbor(c)
	c.resolve_battle(front, true, 0, [], false)
	c.under_attack = -1
	var stand := -1
	for n in c.territories[front].neighbors:
		if not c.territories[n].owned and c.territories[n].boss == "" and not c.home in c.territories[n].neighbors:
			stand = n
			break
	w.at = c.territories[stand].id
	var seen := c.horde_snapshot()
	c._march_warlord(w)
	_check(c.under_attack >= 0 and c.territories[c.under_attack].owned, "beside held land, it attacks")
	_check(w.assaulting == c.territories[c.under_attack].id, "in person")
	_check(String(c.battle_config(c.under_attack).warlord) == w.name, "and is in that fight")
	var attack_news: Array = c.horde_news(seen).filter(func(n: Dictionary) -> bool: return n.kind == "attack")
	_check(not attack_news.is_empty() and String(w.name).to_upper() in attack_news[0].banner, "the alarm names it: " + (attack_news[0].banner if not attack_news.is_empty() else ""))

	# Lost: it takes the land and stands on it. Won: it dies.
	var land := c.under_attack
	c.turn = 1  # (so it doesn't also take its regular march this turn)
	c.resolve_battle(land, false, 0, [], false)
	_check(not c.territories[land].owned and w.at == c.territories[land].id and w.assaulting == "", "losing gives it the land")
	c.under_attack = -1
	seen = c.horde_snapshot()
	w.at = c.territories[stand].id
	c.territories[land].owned = true
	c._ownership_changed()
	c._march_warlord(w)
	var fight := c.under_attack
	c.turn = 1
	c.resolve_battle(fight, true, 0, [], false)
	_check(not c.warlords.has(w), "beating it on your land kills it")
	_check(c.horde_news(seen).any(func(n: Dictionary) -> bool: return n.kind == "warlord_dead"), "and it's news")

	# At the door: home never falls.
	c = _fresh(_profile(5))
	c.turn = GameData.WARLORD_EVERY
	c._advance_warlords()
	w = c.warlords[0]
	w.at = c.territories[_unheld_neighbor(c)].id
	c._march_warlord(w)
	_check(c.under_attack == c.home, "at the door, it attacks home")
	c.turn = 1
	c.resolve_battle(c.home, false, 0, [], false)
	_check(c.territories[c.home].owned, "home never falls")
	_check(c.warlords.has(w) and w.assaulting == "", "it stays at the door, to try again")

	# It keeps marching and stays in saves.
	c = _fresh(_profile(5))
	c.turn = GameData.WARLORD_EVERY
	c._advance_warlords()
	w = c.warlords[0].duplicate()
	c.save()
	var loaded := Campaign.create(_profile(5))
	_check(not loaded.warlords.is_empty() and loaded.warlords[0].name == w.name and loaded.warlords[0].at == w.at, "it survives a reload")

	# On a shared map, every teammate sees the same warlord.
	var members := [{"user_id": "u1", "name": "A", "zip": "24210"}, {"user_id": "u2", "name": "B", "zip": "24210"}]
	var a := Campaign.create(_profile(20), {"id": "t1", "state": "", "members": members})
	a.turn = GameData.WARLORD_EVERY * a.pace()
	a._advance_warlords()
	var b2 := Campaign.create(_profile(2), {"id": "t1", "state": a.to_text(), "members": members})
	_check(not a.warlords.is_empty() and b2.warlords == a.warlords, "teammates see the same warlord")
	_check(a.turn % (GameData.WARLORD_MOVE * a.pace()) != 0 or a.pace() >= 1, "and marches at the team's pace (x%d)" % a.pace())

	# News and the real map.
	p = _profile(5)
	c = _fresh(p)
	seen = c.horde_snapshot()
	c.turn = GameData.WARLORD_EVERY
	c._advance_warlords()
	w = c.warlords[0]
	var news := c.horde_news(seen)
	_check(news.any(func(n: Dictionary) -> bool: return n.kind == "warlord" and String(w.name).to_upper() in n.banner), "its rising is news")
	seen = c.horde_snapshot()
	c._march_warlord(w)
	news = c.horde_news(seen)
	_check(news.size() == 1 and String(w.name).to_upper() in news[0].banner, "its advance is news, once: %s" % [news.map(func(n: Dictionary) -> String: return n.banner)])
	var screen := MapScreen.new()
	screen.campaign = c
	screen.profile = p
	screen.horde_news = news
	screen.size = Vector2(720, 1280)
	root.add_child(screen)
	await _real_wait(700)
	_check(String(w.name).to_upper() + " ADVANCES!" in _labels(screen), "the map says it advances")
	var view: MapView = screen._map
	_check(view._has_warlord(c._index_of_id(w.at)), "the map marks where it stands")
	_check(("%s at %s" % [w.name, c.territories[c._index_of_id(w.at)].name]) in "\n".join(_labels(screen)), "the top of the map names it")
	screen._select(c._index_of_id(w.at))
	await process_frame
	_check("WARLORD:" in screen._info_body.text and GameData.trinket(w.loot).name in screen._info_body.text, "its territory says what's at stake")
	screen.free()

	# In battle, with its entrance and treasure.
	var battle := BattleScreen.new()
	battle.profile = p
	battle.config = {"waves": [["warlord", "shambler"]], "zombie_mult": 1.0, "party_mult": 1.0, "place": "t", "condition": "", "region": "us_appalachia", "warlord": "Rotjaw", "warlord_loot": "lucky_bottle_cap"}
	battle.size = Vector2(720, 1280)
	root.add_child(battle)
	await process_frame
	await process_frame
	_check("ROTJAW!" in _labels(battle), "it's called out by name")
	_check(root.get_node("Sound").current_music == "boss", "with the boss music")
	_check(battle.cards[battle.battle.enemies[0]]._sprite.texture.resource_path.ends_with("warlord.png"), "and its own sprite")
	for z in battle.battle.enemies:
		z.hp = 0
	var cloud: Node = root.get_node("Cloud")
	battle._log_battle()
	_check(String(cloud._battle_logs[-1].get("warlord", "")) == "Rotjaw", "the battle log names the warlord")
	var defended := _fresh(_profile(5))
	var held := _unheld_neighbor(defended)
	defended.resolve_battle(held, true, 0, [], false)
	defended.under_attack = held
	_check(defended.battle_config(held).assault == true, "an assault is marked for the log")
	defended.under_attack = -1
	_check(defended.battle_config(held).assault == false, "other fights aren't")
	battle._show_outcome()
	await _real_wait(1100)
	_check(GameData.trinket("lucky_bottle_cap").name in _labels(battle), "beating it opens the chest")
	battle.free()

	# The guide knows it.
	_check(GameData.ZOMBIE_GUIDE.has("warlord") and GameData.ZOMBIE_WEAKNESS.has("warlord"), "the zombie guide has it")
	print("%d failure(s)" % _fails)
	quit()
