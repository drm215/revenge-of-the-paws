extends Control

## Root: first-launch setup if there's no saved profile, then the campaign map and its battles.

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
	if allow_auto and profile.auto_battle:
		_queue_auto(screen)


## Auto mode: after a short pause on the map, fights the next territory (or counterattack) far
## enough below the pack leader, played by the AI on the battle screen. Leaving the map or
## switching Auto off in the meantime cancels it.
func _queue_auto(screen: MapScreen) -> void:
	var target := _campaign.auto_target(_profile.leader_level())
	if target < 0:
		return
	var t := _campaign.territories[target]
	screen.announce("Auto: %s %s (Lv %d) in a moment. Tap Auto to stop." % [
		"defending" if target == _campaign.under_attack else "attacking", t.full_name(), _campaign.territory_level(target)])
	await get_tree().create_timer(GameData.AUTO_DELAY).timeout
	if is_instance_valid(screen) and screen.is_inside_tree() and not screen.is_queued_for_deletion() and _profile.auto_battle:
		_start_battle(target, false, _campaign.battle_config(target), true)


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


func _start_battle(territory: int, patrol: bool, config: Dictionary, auto := false) -> void:
	var screen := BattleScreen.new()
	screen.profile = _profile
	screen.config = config
	screen.auto = auto
	screen.finished.connect(func(won: bool) -> void:
		if patrol:
			_campaign.resolve_patrol(territory, won)
		else:
			_campaign.resolve_battle(territory, won)
		if auto and not won:
			_profile.auto_battle = false
			_campaign.last_event += "\nAuto mode switched off after the retreat."
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
