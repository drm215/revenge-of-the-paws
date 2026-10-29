extends Control

## Root: first-launch setup if there's no saved profile, then the campaign map and its battles.

## Auto mode stops after this many fights in a row so the player gets the map back now and then.
const AUTO_MAX_FIGHTS := 20

var _profile: Profile
var _campaign: Campaign


func _ready() -> void:
	theme = Retro.make_theme()
	var cloud := get_node_or_null("/root/Cloud")
	if cloud:
		# A newer save arrived from the cloud: start over from it.
		cloud.downloaded.connect(func() -> void: get_tree().reload_current_scene.call_deferred())
	var profile := Profile.load_saved()
	if profile:
		_show_map(profile)
	else:
		_show_onboarding(null)


func _show_onboarding(existing: Profile) -> void:
	var screen := Onboarding.new()
	screen.initial = existing
	screen.finished.connect(_show_map)
	screen.account_requested.connect(_show_account)
	_swap(screen)


func _show_map(profile: Profile, allow_auto := true) -> void:
	if _campaign == null or _profile == null or _profile.home_key() != profile.home_key():
		_campaign = Campaign.create(profile)
	_profile = profile
	if allow_auto and profile.auto_battle and _campaign.auto_target(profile.leader_level()) >= 0:
		_run_auto()
		return
	var screen := MapScreen.new()
	screen.campaign = _campaign
	screen.profile = profile
	screen.battle_requested.connect(_show_battle)
	screen.patrol_requested.connect(_show_battle.bind(true))
	screen.rest_requested.connect(func() -> void:
		_campaign.rest()
		_profile.save()
		_show_map(_profile))
	screen.setup_requested.connect(_show_onboarding.bind(profile))
	screen.pack_requested.connect(_show_pack)
	screen.account_requested.connect(_show_account)
	screen.auto_toggled.connect(func() -> void:
		_profile.auto_battle = not _profile.auto_battle
		_profile.save()
		_show_map(_profile))
	_swap(screen)


## Auto mode: instantly fights every territory (and counterattack) far enough below the pack
## leader, with the current lineup, then reports. Stops at the first retreat.
func _run_auto() -> void:
	var lines: PackedStringArray = []
	for n in AUTO_MAX_FIGHTS:
		var i := _campaign.auto_target(_profile.leader_level())
		if i < 0:
			break
		var level := _campaign.territory_level(i)
		var defending := i == _campaign.under_attack
		var result := AutoBattle.play(_profile, _campaign.battle_config(i))
		var won: bool = result.won
		var amount: int = result.xp if won else roundi(result.xp * GameData.DEFEAT_XP_SHARE)
		var fought: Array[String] = []
		fought.assign(result.fought)
		var downed: Array[String] = []
		downed.assign(result.downed)
		var notes := _profile.after_battle(fought, downed, amount, won)
		_campaign.resolve_battle(i, won)
		var line := "%s %s (Lv %d): %s\n%s" % ["Defended" if defending else "Attacked",
			_campaign.territories[i].full_name(), level, "won" if won else "lost", _campaign.last_event]
		for note in notes:
			line += "\n" + note
		lines.append(line)
		if not won:
			lines.append("Auto mode paused after a retreat. Check your pack.")
			break
	_profile.save()
	var screen := AutoReport.new()
	screen.lines = lines
	var back := func() -> void:
		if not _profile.units_with_new_points().is_empty():
			_show_upgrades()
		else:
			_show_map(_profile, false)
	screen.closed.connect(back)
	screen.stop_requested.connect(func() -> void:
		_profile.auto_battle = false
		_profile.save()
		back.call())
	_swap(screen)


func _show_account() -> void:
	var screen := AccountScreen.new()
	screen.closed.connect(func() -> void:
		var profile := Profile.load_saved()
		if profile:
			_show_map(profile)
		else:
			_show_onboarding(null))
	_swap(screen)


func _show_pack() -> void:
	var screen := PackScreen.new()
	screen.profile = _profile
	screen.closed.connect(func() -> void:
		_profile.save()
		_show_map(_profile))
	_swap(screen)


## Tech trees for the animals that just leveled, then back to the map.
func _show_upgrades() -> void:
	var screen := TechTreeScreen.new()
	screen.profile = _profile
	screen.units = _profile.units_with_new_points()
	_profile.just_leveled.clear()
	screen.done.connect(func() -> void:
		_profile.save()
		_show_map(_profile))
	_swap(screen)


## Every fight starts by readying the pack (lineup, duties, trinkets) for this territory.
func _show_battle(territory: int, patrol := false) -> void:
	var config := _campaign.patrol_config(territory) if patrol else _campaign.battle_config(territory)
	var screen := PackScreen.new()
	screen.profile = _profile
	screen.battle_config = config
	screen.closed.connect(func() -> void:
		_profile.save()
		_show_map(_profile))
	screen.fight.connect(func() -> void:
		_profile.save()
		_start_battle(territory, patrol, config))
	_swap(screen)


func _start_battle(territory: int, patrol: bool, config: Dictionary) -> void:
	var screen := BattleScreen.new()
	screen.profile = _profile
	screen.config = config
	screen.finished.connect(func(won: bool) -> void:
		if patrol:
			_campaign.resolve_patrol(territory, won)
		else:
			_campaign.resolve_battle(territory, won)
		_profile.save()  # XP and any rescued recruit
		if not _profile.units_with_new_points().is_empty():
			_show_upgrades()
		else:
			_show_map(_profile))
	_swap(screen)


func _swap(screen: Control) -> void:
	for child in get_children():
		child.queue_free()
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(screen)
