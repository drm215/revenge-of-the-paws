extends SceneTree

## A perfect wave (no animal hurt) gives the pack ATK, stacking, until any animal takes damage.

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


func _clear_wave(b: Battle) -> void:
	for z in b.enemies:
		z.hp = 0


func _init() -> void:
	var b := Battle.new(_profile(), [["shambler"], ["shambler"], ["shambler"], ["shambler"], ["shambler"], ["shambler"]], 1.0, 1.0, "test", 1)
	var said: Array[int] = []
	b.perfect_changed.connect(func(stacks: int) -> void: said.append(stacks))
	b.start_next_wave()
	var bear: Combatant = b.party[0]
	var z: Combatant = b.enemies[0]
	var plain := b._base_damage(bear, z, 1.0)
	_check(b.perfect == 0 and b.perfect_atk_bonus() == 0.0, "no bonus to start")

	_clear_wave(b)
	b.start_next_wave()
	_check(b.perfect == 1 and said == [1], "a wave with no one hurt is perfect")
	z = b.enemies[0]
	var boosted := b._base_damage(bear, z, 1.0)
	_check(is_equal_approx(boosted, plain * (1.0 + GameData.PERFECT_ATK_STEP)), "the pack hits %d%% harder (%.1f to %.1f)" % [roundi(GameData.PERFECT_ATK_STEP * 100), plain, boosted])
	var zombie_hit := b._base_damage(z, bear, 1.0)
	b.perfect = 0
	_check(is_equal_approx(b._base_damage(z, bear, 1.0), zombie_hit), "zombies don't get it")
	b.perfect = 1

	for k in 3:
		_clear_wave(b)
		b.start_next_wave()
	_check(b.perfect == GameData.PERFECT_MAX_STACKS, "it stacks over perfect waves in a row, up to %d" % GameData.PERFECT_MAX_STACKS)
	_check(b.report().perfect_waves == 4, "the log counts them: %d" % b.report().perfect_waves)

	b._apply_damage(b.party[1], 5, false)
	_check(b.perfect == 0 and said[-1] == 0, "any animal hurt ends it")
	_check(is_equal_approx(b._base_damage(bear, b.enemies[0], 1.0), plain), "back to plain ATK")
	_clear_wave(b)
	b.start_next_wave()
	_check(b.perfect == 0, "and a wave with a hit in it isn't perfect")

	# On screen: the pack's cards glow gold while the streak lasts.
	var card := UnitCard.new()
	root.add_child(card)
	card.setup(b.party[0], 100)
	card.set_glow(true)
	_check(card.is_glowing(), "a perfect wave lights the card up")
	card.set_glow(false)
	_check(not card.is_glowing() and card._sprite.self_modulate == Color.WHITE, "and a hit puts it out")
	var fallen := UnitCard.new()
	root.add_child(fallen)
	var dead := b.party[1]
	dead.hp = 0
	fallen.setup(dead, 100)
	fallen.set_glow(true)
	_check(not fallen.is_glowing(), "the fallen don't glow")

	print("%d failure(s)" % _fails)
	quit()
