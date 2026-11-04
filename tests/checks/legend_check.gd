extends SceneTree

## Legends: weak spots and resistances change the damage they take, and raids make them grow.

var _fails := 0


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


func _pack() -> Profile:
	var p := Profile.new()
	p.region = "us_appalachia"
	p.pet_species = "dog"
	p.pet_name = "Jack"
	p.team.assign(["black_bear", "bobcat"])
	p.unlocked.assign(["black_bear", "bobcat"])
	return p


## What one hit from a critter tagged `tag` does to the Woodbooger, with the same dice every time.
func _hit(tag: String) -> int:
	var b := Battle.new(_pack(), [["woodbooger"]], 1.0, 1.0, "lair", 1)
	b.start_next_wave()
	var src: Combatant = b.party[0]
	src.tags.assign([tag])
	src.crit = 0.0
	var dst: Combatant = b.enemies[0]
	var before := dst.hp
	b.rng.seed = 7
	b._deal_damage(src, dst, 1.0, 0.0)
	return before - dst.hp


func _init() -> void:
	var neutral := _hit("desert")  # the Woodbooger is a giant: forest hurts it, urban doesn't
	_check(neutral > 0, "a neutral critter's hit lands: %d" % neutral)
	var ratio_weak := _hit("forest") / float(neutral)
	_check(absf(ratio_weak - GameData.LEGEND_WEAK_MULT) < 0.1, "its weak spot takes x%.2f" % ratio_weak)
	var ratio_resist := _hit("urban") / float(neutral)
	_check(absf(ratio_resist - GameData.LEGEND_RESIST_MULT) < 0.1, "what it resists takes x%.2f" % ratio_resist)

	var alone := Battle.new(_pack(), [["woodbooger"]], 1.0, 1.0, "lair", 1)
	alone.start_next_wave()
	var duo := Battle.new(_pack(), [["woodbooger"]], 1.0, 1.0, "lair", 1)
	var growth := GameData.legend_growth(2)
	duo.configure({"boss_hp": growth.x, "boss_atk": growth.y})
	duo.start_next_wave()
	_check(absf(float(duo.enemies[0].max_hp) / alone.enemies[0].max_hp - growth.x) < 0.02, "a 2-player legend has x%.1f HP" % growth.x)
	_check(absf(float(duo.enemies[0].atk) / alone.enemies[0].atk - growth.y) < 0.05, "and x%.2f attack" % growth.y)
	_check(GameData.legend_growth(1) == Vector2.ONE and GameData.legend_growth(4).x > GameData.legend_growth(3).x, "growth rises with players, none alone")

	# The legend's stats stay tuned: a solo Woodbooger isn't the pushover it was.
	var legend: Dictionary = GameData.enemy("woodbooger")
	_check(legend.hp >= 400 and legend.atk >= 23, "Woodbooger: %d HP, %d attack" % [legend.hp, legend.atk])
	print("%d failure(s)" % _fails)
	quit()
