extends SceneTree

## Titles past Lv 50 (one every 10 levels, colored on the battle card) and trinket upgrades (two
## copies make one a tier better: bigger bonuses, smaller drawbacks, still fusable).

var _fails := 0


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	root.theme = Retro.make_theme()
	Saves.use(Saves.new_slot())
	# Titles.
	_check(GameData.level_title(59).is_empty() and GameData.level_title(60).name == "Veteran" and GameData.level_title(69).name == "Veteran"
		and GameData.level_title(70).name == "Elite" and GameData.level_title(100).name == "Mythic" and GameData.level_title(250).name == "Mythic",
		"Veteran at 60, Elite at 70 ... Mythic from 100 on")
	var p := Profile.new()
	p.region = "us_appalachia"
	p.pet_species = "dog"
	p.pet_name = "Jack"
	p.team.assign(["black_bear", "horned_owl"])
	p.unlocked.assign(p.team)
	p.xp["dog"] = GameData.xp_to_reach(59)
	var lines := "\n".join(p.after_battle(p.pack_ids(), [], GameData.xp_to_reach(60) - GameData.xp_to_reach(59)))
	_check("Jack reached Lv 60! Now a Veteran!" in lines, "the level-up says so: " + lines.get_slice("\n", 1))
	var lines2 := "\n".join(p.after_battle(p.pack_ids(), [], 10))
	_check("Now a" not in lines2, "no title line without a new title")
	var card := UnitCard.new()
	root.add_child(card)
	card.setup(p.build_unit("dog"), 60)
	_check(card._name_label.get_theme_color("font_color") == GameData.LEVEL_TITLES[0].color, "the battle card colors the name")
	card.queue_free()

	# Upgrades.
	p.trinkets.assign(["duct_tape_armor", "duct_tape_armor", "lucky_bottle_cap"])
	p.equipped["black_bear"] = "duct_tape_armor"
	_check(p.upgrade_block("lucky_bottle_cap") == "Needs a second copy.", "one copy can't be upgraded")
	var better := p.upgrade_trinket("duct_tape_armor")
	var t: Dictionary = GameData.trinket(better)
	_check(better == "duct_tape_armor@1" and t.name == "Duct-Tape Armor +1", "two copies make Duct-Tape Armor +1")
	_check(is_equal_approx(t.def, 0.15 * 1.5) and is_equal_approx(t.spd, -0.05 * 0.75), "+50%% of its bonus, 25%% less drawback (DEF %.3f, SPD %.4f)" % [t.def, t.spd])
	_check(p.trinkets.count("duct_tape_armor") == 0 and p.equipped.black_bear == better, "both copies used up; the bear wears the new one")
	p.trinkets.append(better)
	var two := p.upgrade_trinket(better)
	_check(two == "duct_tape_armor@2" and GameData.trinket(two).name.ends_with("+2"), "and again: +2")
	p.trinkets.assign(["duct_tape_armor@3", "duct_tape_armor@3"])
	_check(p.upgrade_block("duct_tape_armor@3") == "Fully upgraded.", "+%d is the top" % GameData.MAX_TRINKET_TIER)
	var fused := GameData.fused_id("duct_tape_armor@3", "lucky_bottle_cap")
	_check(GameData.fuse_block("duct_tape_armor@3", "lucky_bottle_cap") == "" and is_equal_approx(GameData.trinket(fused).def, 0.15 * 2.5),
		"an upgraded trinket can still be fused: " + GameData.trinket(fused).name)
	_check(GameData.upgrade_block(fused) != "", "a fused trinket can't be upgraded")
	var bear := Profile.new()
	bear.region = "us_appalachia"
	bear.pet_species = "dog"
	bear.pet_name = "Jack"
	bear.team.assign(["black_bear", "horned_owl"])
	bear.unlocked.assign(bear.team)
	var plain_def := bear.build_unit("black_bear").def
	bear.trinkets.assign(["duct_tape_armor@3"])
	bear.equipped["black_bear"] = "duct_tape_armor@3"
	_check(bear.build_unit("black_bear").def > plain_def, "it works in a fight (DEF %d -> %d)" % [plain_def, bear.build_unit("black_bear").def])

	# The upgrade screen.
	p.trinkets.assign(["spare_battery", "spare_battery"])
	var pack := PackScreen.new()
	pack.profile = p
	root.add_child(pack)
	await process_frame
	pack._show_upgrade()
	await process_frame
	_check(pack.get_child(-1) is ColorRect, "the Upgrade screen opens")
	pack.queue_free()
	print("%d failure(s)" % _fails)
	quit()
