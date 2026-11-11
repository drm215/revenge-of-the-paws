extends Control

## Root: the save picker after the loading screen (or first-launch setup for a new game), then the
## campaign map and its battles.

var _profile: Profile
var _campaign: Campaign
var _campaign_stale := false  # the team map changed on the server: rebuild before showing it
var _rebuild_waiting := false  # a team change waits for the map's moment to end before rebuilding


func _ready() -> void:
	theme = Retro.make_theme()
	var cloud := get_node_or_null("/root/Cloud")
	if cloud:
		# A newer save arrived from the cloud: start over from it.
		cloud.downloaded.connect(func() -> void: get_tree().reload_current_scene.call_deferred())
		cloud.reset_requested.connect(_show_account)
	var team := get_node_or_null("/root/Team")
	if team:
		team.changed.connect(_on_team_changed)
		get_node("/root/Raid").late_finish.connect(_on_late_raid)
		if cloud.reset_pending:
			_show_account()  # a cloud download reloaded the game mid-reset
			return
	Saves.migrate()
	_watch_for_update()
	_show_saves()


## Installed as an app (PWA), the game runs the version it cached until a new one is switched on:
## when a deploy has been downloaded and is waiting, a bar at the top offers to restart into it.
func _watch_for_update() -> void:
	if not OS.has_feature("web"):
		return
	JavaScriptBridge.pwa_update_available.connect(_show_update_bar)
	if JavaScriptBridge.pwa_needs_update():
		_show_update_bar()


var _update_bar: CanvasLayer


func _show_update_bar() -> void:
	if _update_bar and is_instance_valid(_update_bar):
		return
	_update_bar = CanvasLayer.new()
	_update_bar.layer = 50
	add_child(_update_bar)
	var button := Button.new()
	button.text = "New version ready: tap to update"
	button.add_theme_font_size_override("font_size", 20)
	var look := StyleBoxFlat.new()
	look.bg_color = Retro.GOLD
	look.content_margin_top = 10
	look.content_margin_bottom = 10
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		button.add_theme_stylebox_override(state, look)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_disabled_color"]:
		button.add_theme_color_override(state, Retro.INK)
	button.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_update_bar.add_child(button)
	button.pressed.connect(func() -> void:
		button.disabled = true
		button.text = "Updating..."
		if _profile:
			_profile.save()
		await get_tree().create_timer(0.6).timeout  # let the save reach browser storage
		JavaScriptBridge.pwa_update())


var _horde_seen := {}  # Campaign.horde_snapshot() as the map last showed it


## Pick a saved game, start a new one, or log in to a cloud save.
func _show_saves() -> void:
	_profile = null
	_campaign = null
	_horde_seen = {}
	var raid := get_node_or_null("/root/Raid")
	if raid:
		raid.listening = false  # a late raid result needs a game to land in
	var screen := SaveScreen.new()
	screen.chosen.connect(func(id: String) -> void:
		Saves.use(id)
		var profile := Profile.load_saved()
		_use_team(profile.team_id if profile else "")
		var team := get_node_or_null("/root/Team")
		if profile and profile.team_id != "" and team and not team.on_team():
			await team.refresh()  # a team game this device hasn't loaded yet: never start it on a solo map
		if profile:
			_show_map(profile)
		else:
			_show_onboarding(null))  # an unfinished save: finish setting it up
	screen.new_game.connect(func() -> void:
		Saves.use(Saves.new_slot())
		_use_team("")  # a new game starts solo, from scratch
		_show_onboarding(null))
	screen.account_requested.connect(_show_account)
	_swap(screen)


func _show_onboarding(existing: Profile) -> void:
	var screen := Onboarding.new()
	screen.initial = existing
	screen.finished.connect(func(profile: Profile) -> void:
		_campaign = null  # a new game: rebuild the map from scratch
		_show_partner(profile))
	if existing:
		screen.cancelled.connect(func() -> void: _show_map(existing, false))
	else:
		screen.cancellable = true
		screen.cancelled.connect(func() -> void:
			# The new game was never started: tidy its empty folder. A game that has a file (one that
			# didn't open, say) is never deleted from here, nor its cloud copy.
			if not FileAccess.file_exists(Profile.save_path):
				Saves.delete(Saves.slot_of(Profile.save_path))
			_show_saves())
	screen.account_requested.connect(_show_account)
	_swap(screen)


func _show_map(profile: Profile, allow_auto := true) -> void:
	var sound := get_node_or_null("/root/Sound")
	if sound:
		sound.music("map")
	var raid_node := get_node_or_null("/root/Raid")
	if raid_node:
		raid_node.listening = true
	var moment: Dictionary = _campaign.take_liberation() if _campaign else {}
	var seen := _horde_seen
	if _campaign == null or _profile == null or _profile.home_key() != profile.home_key() or _campaign_stale:
		var message := _campaign.last_event if _campaign and _campaign_stale else ""
		_campaign = _make_campaign(profile)
		_campaign.last_event = message  # a teammate's move rebuilt the map: keep this player's news
		_campaign_stale = false
		_collect_raid()
		var gained := profile.collect_team_xp(_campaign.team_key(), int(_campaign.shared_xp.get(_campaign.my_id, 0)))
		if gained > 0:
			_campaign.last_event += "\nTeammates' battles next to your land earned your pack +%d XP each." % gained
	var goal := _campaign.week_goal()
	if goal.finished:
		var reward := profile.claim_week_goal(int(goal.week))
		if reward != "":
			_campaign.last_event += ("\n" if _campaign.last_event != "" else "") + reward
	_profile = profile
	var screen := MapScreen.new()
	screen.campaign = _campaign
	screen.profile = profile
	screen.liberation = moment
	screen.horde_news = _campaign.horde_news(seen)
	_horde_seen = _campaign.horde_snapshot()
	screen.liberation_done.connect(func() -> void:
		if _campaign_stale:
			_show_map(_profile, false))
	screen.battle_requested.connect(_show_battle)
	screen.patrol_requested.connect(_show_battle.bind(true))
	screen.sweep_requested.connect(_sweep_all)
	screen.rest_requested.connect(func() -> void:
		_campaign.rest()
		_profile.save()
		_show_map(_profile))
	screen.pack_requested.connect(_show_pack)
	screen.stable_requested.connect(_show_pack.bind(true))
	screen.account_requested.connect(_show_account)
	screen.siege_requested.connect(_show_siege)
	screen.dungeon_requested.connect(_show_dungeon)
	screen.rematch_requested.connect(_show_rematch)
	screen.bonus_requested.connect(_show_bonus)
	screen.raid_requested.connect(_show_raid.bind(-1))
	screen.saves_requested.connect(func() -> void:
		_profile.save()  # everything else is already saved after each move
		_show_saves())
	screen.chat_requested.connect(func() -> void:
		var chat := ChatScreen.new()
		chat.closed.connect(func() -> void: _show_map(_profile, false))
		_swap(chat))
	screen.auto_toggled.connect(func() -> void:
		_profile.auto_battle = not _profile.auto_battle
		_profile.save()
		_show_map(_profile))
	_swap(screen)
	_check_siege(screen)
	if allow_auto and profile.auto_battle and GameData.AUTO_MODE_ENABLED:
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


## The solo campaign, or the team's shared map with this device's unsent moves on top.
func _make_campaign(profile: Profile) -> Campaign:
	var team := get_node_or_null("/root/Team")
	if team == null or not team.on_team() or profile.zip == "":
		return Campaign.create(profile)
	var c := Campaign.create(profile, team.info)
	c.me = team.my_name(profile)
	var cloud := get_node_or_null("/root/Cloud")
	c.my_id = cloud.user_id() if cloud else ""
	for action: Dictionary in team.pending:
		c.apply(action)
	c.on_action = team.record
	return c


## A raid lobby, opening a new raid on `lair` (or -1 to join or look at the team's raid); a
## `rematch` raid on a beaten legend's lair is just for fun.
func _show_raid(lair: int, rematch := false) -> void:
	var screen := RaidScreen.new()
	screen.profile = _profile
	screen.campaign = _campaign
	screen.lair = lair
	screen.rematch = rematch
	screen.closed.connect(func() -> void: _show_map(_profile, false))
	screen.fight.connect(_start_raid_battle)
	_swap(screen)


## The raid started: every raider's battle screen plays the same fight, each player moving their own.
func _start_raid_battle() -> void:
	var raid := get_node("/root/Raid")
	var screen := BattleScreen.new()
	screen.profile = _profile
	screen.config = raid.config()
	screen.raid = true
	screen.raid_done.connect(func(outcome: Dictionary, recorded_here: bool) -> void:
		if not recorded_here:
			return  # the device that reported the result first records it on the team map
		_record_raid(outcome, raid.members().map(func(m: Dictionary) -> String: return String(m.user_id))))
	screen.finished.connect(func(_won: bool) -> void:
		_profile.save()
		if not _profile.units_with_new_points().is_empty():
			_show_upgrades()
		else:
			_show_map(_profile))
	_swap(screen)


## Records a raid's result on the team map.
func _record_raid(outcome: Dictionary, raiders: Array) -> void:
	if outcome.get("rematch", false):
		return  # a rematch doesn't move the map
	var i := _lair_of(outcome)
	if i >= 0:
		_campaign.resolve_battle(i, bool(outcome.won), int(outcome.xp), raiders, false)


func _lair_of(outcome: Dictionary) -> int:
	for i in _campaign.territories.size():
		if _campaign.territories[i].id == String(outcome.get("territory", "")):
			return i
	return -1


## A result that couldn't be sent when the fight ended has got through: the map and this player's
## rewards catch up. (A send cut off on leaving may have recorded it first, so a win is also
## recorded if the lair isn't free yet.)
func _on_late_raid(late: Dictionary, stored: Dictionary) -> void:
	if _profile == null or _campaign == null:
		return
	var result: Dictionary = stored.result
	var i := _lair_of(result)
	if bool(stored.mine) or (bool(result.get("won", false)) and i >= 0 and not _campaign.territories[i].owned):
		_record_raid(result, late.raiders)
	var lines := _profile.claim_raid(String(late.id), result, late.brought, get_node("/root/Raid").my_id())
	if not lines.is_empty():
		_campaign.last_event += "\nYour raid result got through: " + " ".join(lines)
	if get_child_count() > 0 and get_child(-1) is MapScreen:
		_show_map(_profile, false)


## A raid this player fought in ended without them (they closed the game): collect their share.
func _collect_raid() -> void:
	var raid := get_node_or_null("/root/Raid")
	if raid == null or raid.status() != "done" or not raid.is_member() or String(raid.info.id) in _profile.raids_claimed:
		return
	var brought: Array = []
	for m: Dictionary in raid.members():
		if String(m.user_id) == raid.my_id():
			var mine := Profile.from_snapshot(String(m.pack))
			brought = Array(mine.pack_ids()) if mine else []
	var lines := _profile.claim_raid(String(raid.info.id), raid.result(), brought, raid.my_id())
	if not lines.is_empty():
		_campaign.last_event += "\nThe raid you were in ended: " + " ".join(lines)


## Teammates moved (or the team changed): rebuild the map now if it's showing, else next time. A
## map in the middle of a moment (a liberation, horde news, a siege banner) is rebuilt once it ends.
func _on_team_changed() -> void:
	_campaign_stale = true
	if _rebuild_waiting or not _profile or get_child_count() == 0 or not get_child(-1) is MapScreen:
		return
	var map: MapScreen = get_child(-1)
	_rebuild_waiting = true
	while is_instance_valid(map) and map.celebrating:
		await get_tree().process_frame
	_rebuild_waiting = false
	if is_instance_valid(map) and get_child_count() > 0 and get_child(-1) == map and _campaign_stale and _profile:
		_show_map(_profile, false)


## Points Team (and so chat and raids) at the team a saved game is played with.
func _use_team(id: String) -> void:
	var team := get_node_or_null("/root/Team")
	if team:
		team.use(id)


## After a new game's setup: invite a partner, join one, or play solo.
func _show_partner(profile: Profile) -> void:
	var screen := PartnerScreen.new()
	screen.profile = profile
	screen.done.connect(func() -> void:
		_campaign = null
		_show_map(Profile.load_saved()))  # it may have joined a team
	screen.account_requested.connect(func() -> void: _show_account(_show_partner.bind(profile)))
	_swap(screen)


## The Cloud screen; `back` is where to go when it closes (the map or the save picker by default).
func _show_account(back := Callable()) -> void:
	var screen := AccountScreen.new()
	screen.closed.connect(func() -> void:
		if back.is_valid():
			back.call()
		elif _profile:
			_profile = Profile.load_saved()  # the Cloud screen may have changed this game's team
			_use_team(_profile.team_id)
			_campaign_stale = true
			_show_map(_profile)
		else:
			_show_saves())
	_swap(screen)


func _show_siege() -> void:
	var screen := SiegeScreen.new()
	screen.profile = _profile
	screen.closed.connect(func() -> void: _show_map(_profile, false))
	_swap(screen)


func _show_pack(stable_view := false) -> void:
	var screen := PackScreen.new()
	screen.profile = _profile
	screen.stable_view = stable_view
	screen.closed.connect(func() -> void:
		_profile.save()
		_show_map(_profile))
	screen.open_stable.connect(_show_pack.bind(true))
	screen.bring_back.connect(func(id: String) -> void:
		_campaign.bring_from_stable(id)
		_profile.save()
		_show_pack(true))
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
	config["raidable"] = not patrol and _campaign.is_team() and _campaign.territories[territory].boss != ""
	var screen := PackScreen.new()
	screen.profile = _profile
	screen.battle_config = config
	screen.raid_requested.connect(_show_raid.bind(territory))
	screen.closed.connect(func() -> void:
		_profile.save()
		_show_map(_profile))
	screen.fight.connect(func() -> void:
		_profile.save()
		_start_battle(territory, patrol, config))
	_swap(screen)


## A rematch with a beaten legend, for fun: ready the pack, fight, and back to the map with no XP,
## loot, injuries or map turn.
func _show_rematch(territory: int) -> void:
	var config := _campaign.rematch_config(territory)
	config["raidable"] = _campaign.is_team()
	var screen := PackScreen.new()
	screen.profile = _profile
	screen.battle_config = config
	screen.raid_requested.connect(_show_raid.bind(territory, true))
	screen.closed.connect(func() -> void:
		_profile.save()
		_show_map(_profile, false))
	screen.fight.connect(func() -> void:
		_profile.save()
		var battle := BattleScreen.new()
		battle.profile = _profile
		battle.config = config
		battle.finished.connect(func(_won: bool) -> void: _show_map(_profile, false))
		_swap(battle))
	_swap(screen)


## Sweep all: takes every territory far below the pack without a fight, one map turn each (land that
## opens up as it goes too), until none is left or the horde counterattacks. The fighters get a share
## of each one's XP, nobody tires, and the last liberation plays as usual.
func _sweep_all() -> void:
	if _campaign.sweepable().is_empty():
		return
	var tired := _profile.fatigue.duplicate()
	var names: PackedStringArray = []
	var news: PackedStringArray = []
	var gained := 0
	var attacked := _campaign.under_attack
	for k in _campaign.territories.size():
		var open := _campaign.sweepable()
		if open.is_empty():
			break
		var territory: int = open[0]
		var xp := _campaign.sweep_xp(territory)
		gained += xp
		news.append_array(_profile.after_battle(_profile.pack_ids(), [], xp, true).slice(1))
		_campaign.last_event = ""
		_campaign.resolve_battle(territory, true, xp)  # teammates share the sweep with its catch-up
		names.append(_campaign.territories[territory].full_name())
		for line in _campaign.last_event.split("\n", false):
			if not line.ends_with(" liberated!"):
				news.append(line)
		if _campaign.under_attack >= 0 and _campaign.under_attack != attacked:
			break  # the horde strikes back: that fight comes first
	_profile.fatigue = tired
	var head := ("Swept %s: +%d XP each." % [names[0], gained]) if names.size() == 1 else \
		("Swept %d territories (%s): +%d XP each." % [names.size(), ", ".join(names), gained])
	_campaign.last_event = head + ("\n" + "\n".join(news) if not news.is_empty() else "")
	_profile.save()
	if not _profile.units_with_new_points().is_empty():
		_show_upgrades()
	else:
		_show_map(_profile)


func _start_battle(territory: int, patrol: bool, config: Dictionary, auto := false) -> void:
	var screen := BattleScreen.new()
	screen.profile = _profile
	config["catch_up"] = _campaign.catch_up_mult()
	config["behind"] = _campaign.levels_behind()
	screen.config = config
	screen.auto = auto
	screen.finished.connect(func(won: bool) -> void:
		if patrol:
			_campaign.resolve_patrol(territory, won)
		else:
			_campaign.resolve_battle(territory, won, screen.xp_awarded)
		if auto and not won:
			_profile.auto_battle = false
			_campaign.last_event += "\nAuto mode switched off after the retreat."
		_hit_siege(screen.battle.kills * int(config.get("threat", 1)))
		_profile.save()  # XP and any rescued recruit
		if not _profile.units_with_new_points().is_empty():
			_show_upgrades()
		else:
			_show_map(_profile))
	_swap(screen)


## How the week's siege stands, for the map: rewards waiting on its button, and a banner when a stage
## has broken since this pack last looked (their damage or anyone else's).
func _check_siege(screen: MapScreen) -> void:
	var cloud := get_node_or_null("/root/Cloud")
	if cloud == null or not cloud.enabled() or not cloud.signed_in():
		return
	var week := GameData.siege_week(Time.get_unix_time_from_system())
	var board: Dictionary = await cloud.siege_board(week)
	if board.is_empty() or not is_instance_valid(screen) or not screen.is_inside_tree() or _profile == null:
		return
	var players := int(board.players)
	var broken := GameData.siege_stage(int(board.total), players)
	if int(board.mine) > 0:
		screen.set_siege_rewards(maxi(0, broken - _profile.siege_claimed_stages(week)))
	if broken > int(_profile.siege_seen.get(week, 0)):
		_profile.siege_seen[week] = broken
		_profile.save()
		var stage: Dictionary = GameData.SIEGE_STAGES[broken - 1]
		var siege_name := String(GameData.siege_info(week).name)
		screen.announce_siege("%s: %s!" % [siege_name.to_upper(), String(stage.name).to_upper()], GameData.siege_reward_text(broken - 1) + ". Claim it from Siege.")


## A cleared state's or region's bonus: this player picks which of their critters gets it.
func _show_bonus() -> void:
	var waiting := _profile.bonuses_waiting(_campaign.cleared)
	if waiting.is_empty():
		_show_map(_profile, false)
		return
	var screen := BonusScreen.new()
	screen.profile = _profile
	screen.key = waiting[0]
	screen.closed.connect(func() -> void: _show_map(_profile, false))
	_swap(screen)


## `region`'s dungeon: pick a starting wave, ready the pack, then wave after wave. It costs no map
## turn and leaves no injuries; its rewards are paid as the waves fall.
func _show_dungeon(region: String) -> void:
	var screen := DungeonScreen.new()
	screen.profile = _profile
	screen.region = region
	screen.closed.connect(func() -> void: _show_map(_profile, false))
	screen.start.connect(_ready_dungeon.bind(region))
	_swap(screen)


func _ready_dungeon(wave: int, region: String) -> void:
	var dungeon := GameData.dungeon(region)
	var config := {"dungeon": region, "start": wave, "waves": [GameData.dungeon_wave(region, wave)],
		"zombie_mult": GameData.dungeon_mult(wave), "party_mult": 1.0, "place": dungeon.name,
		"condition": dungeon.terrain, "region": region}
	var prep := PackScreen.new()
	prep.profile = _profile
	prep.battle_config = config
	prep.closed.connect(func() -> void:
		_profile.save()
		_show_dungeon(region))
	prep.fight.connect(func() -> void:
		_profile.save()
		var battle := BattleScreen.new()
		battle.profile = _profile
		battle.config = config
		battle.finished.connect(func(_won: bool) -> void:
			_profile.save()
			if not _profile.units_with_new_points().is_empty():
				_show_upgrades()
			else:
				_show_map(_profile, false))
		_swap(battle))
	_swap(prep)


## Every zombie destroyed hits the weekly siege for the territory's threat.
func _hit_siege(points: int) -> void:
	var cloud := get_node_or_null("/root/Cloud")
	if points <= 0 or cloud == null or not cloud.enabled():
		return
	cloud.siege_add(points, _profile.siege_name())
	_campaign.last_event += "\n+%d damage to %s (Siege)." % [points, GameData.siege_info(GameData.siege_week(Time.get_unix_time_from_system())).name]
	_campaign.save()


func _swap(screen: Control) -> void:
	for child in get_children():
		child.queue_free()
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(screen)
