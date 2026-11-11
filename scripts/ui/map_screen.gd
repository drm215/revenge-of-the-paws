class_name MapScreen
extends Control

## Campaign map: pick a neighboring territory to attack, or answer a zombie counterattack.
## Lairs open a briefing on their legend before the fight.

signal battle_requested(index: int)
signal patrol_requested(index: int)
## Take every far-below territory without a fight (Campaign.sweepable).
signal sweep_requested
signal rest_requested
signal pack_requested
signal stable_requested
signal account_requested
signal siege_requested
signal chat_requested
## Join (or go back to) the team's legend raid.
signal raid_requested
## Back to the save picker.
signal saves_requested
## Enter the dungeon of `region` (its entrance is held).
signal dungeon_requested(region: String)
signal rematch_requested(index: int)
## Claim the bonus for a cleared state or region.
signal bonus_requested
signal auto_toggled
## The liberation and the horde's moves have finished playing.
signal liberation_done

var campaign: Campaign
var profile: Profile
var liberation := {}  # Campaign.take_liberation(): the moment to play as this screen opens
var horde_news: Array = []  # Campaign.horde_news(): the horde's moves to play after it
var celebrating := false
var _siege_button := Button.new()
var _delve := Button.new()  # home: into the region's dungeon
var _rematch := Button.new()  # a beaten legend's lair: fight it again for fun
var _bonus_button := Button.new()  # a cleared state's or region's bonus is waiting

var _map := MapView.new()
var _status := Label.new()
var _week := Label.new()  # this week's zombie mutation and goal
var _backup_warning := Button.new()  # the game isn't reaching the cloud: say so, tap to retry
var _event := Label.new()
## The map always keeps MAP_MIN_HEIGHT; the news (and team feed) above it and the territory info
## below it are only as tall as their text, up to a cap, and scroll past that.
const MAP_MIN_HEIGHT := 340.0
const HORDE_MOMENT_SEC := 1.9
const MAX_HORDE_MOMENTS := 4  # a teammate's long run of moves shouldn't hold the map for long
const NEWS_MAX_HEIGHT := 135.0
const INFO_MAX_HEIGHT := 125.0
var _info_scroll := ScrollContainer.new()
var _news := ScrollContainer.new()
var _news_box := VBoxContainer.new()
var _info_title := Label.new()
var _sweep := Button.new()  # beside Attack! on land far below the pack
var _info_where := Label.new()  # beside the title: the territory's state and region
var _info_body := Label.new()
var _action := Button.new()
var _ping := Button.new()  # team: point teammates at the selected territory
var _chat_button: Button
var _raid_button := Button.new()  # team: an open raid to join, or one this player is fighting in
var _briefing: Control


func _ready() -> void:
	_map.campaign = campaign  # before it joins the tree: it starts fetching outlines as it does
	_build_ui()
	var chat := get_node_or_null("/root/Chat")
	if chat and campaign.is_team():
		chat.received.connect(_on_chat)
		_on_chat()
	var raid := get_node_or_null("/root/Raid")
	if raid and campaign.is_team():
		raid.changed.connect(_on_raid)
		_on_raid()
	_map.territory_selected.connect(_select)
	_refresh_status()
	var cloud := get_node_or_null("/root/Cloud")
	if cloud:
		cloud.status_changed.connect(func(_text: String) -> void: _refresh_backup_warning())
		var check := Timer.new()  # minutes pass without any sync news
		check.wait_time = 30.0
		check.autostart = true
		check.timeout.connect(_refresh_backup_warning)
		add_child(check)
	_refresh_backup_warning()
	_select(campaign.under_attack if campaign.under_attack >= 0 else campaign.home)
	if campaign.under_attack >= 0 and not horde_news.any(func(n: Dictionary) -> bool: return n.kind == "attack"):
		_map.focus.call_deferred(campaign.under_attack)
	if not liberation.is_empty() or not horde_news.is_empty():
		celebrating = true
		_play_moments.call_deferred()


## What happened since the map was last up, in order. Nothing waits for it: the map works as usual
## while it plays.
func _play_moments() -> void:
	await get_tree().process_frame  # the map has its size by now
	if not liberation.is_empty():
		await _play_liberation()
	for news: Dictionary in horde_news.slice(0, MAX_HORDE_MOMENTS):
		await _play_horde(news)
	celebrating = false
	liberation_done.emit()


func _index_of(id: String) -> int:
	for i in campaign.territories.size():
		if campaign.territories[i].id == id:
			return i
	return -1


## The horde's move: the view swings over, an alarm or a rumble, and it pours in from next door.
func _play_horde(news: Dictionary) -> void:
	var at := _index_of(String(news.territory))
	if at < 0:
		return
	var sound := get_node_or_null("/root/Sound")
	if sound:
		sound.play({"attack": "alarm", "warlord": "roar", "warlord_dead": "loot"}.get(news.kind, "horde"))
	_map.pan_to(at, 0.4)
	if news.kind == "attack":
		_select(at)
	await get_tree().create_timer(0.4).timeout
	_map.play_horde(at, news.from, news.kind)
	var color: Color = {"spread": Retro.ORANGE, "warlord_dead": Retro.GOLD}.get(news.kind, Retro.RED)
	var top := _map_banner(String(news.banner), 22, color, 0.06)
	var lines: Array[Label] = [top, _map_banner(String(news.line), 14, Retro.WHITE, 0.2, top)]
	await get_tree().create_timer(HORDE_MOMENT_SEC).timeout
	_fade_banners(lines)


func _fade_banners(lines: Array[Label]) -> void:
	for line in lines:
		var fade := line.create_tween()
		fade.tween_property(line, "modulate:a", 0.0, 0.3)
		fade.tween_callback(line.queue_free)


## Green sweeps over the freed territory, with its name across the map and the milestone under it.
func _play_liberation() -> void:
	var at := _index_of(String(liberation.territory))
	var sound := get_node_or_null("/root/Sound")
	if sound:
		sound.play("liberate")
		if liberation.milestone_big:
			sound.play("loot", 0.0, -3.0)
	if at >= 0:
		_map.focus(at)
		_select(at)
		_map.play_liberation(at, liberation.from, liberation.rescued)
	var banner := _map_banner(String(liberation.banner), 24, Retro.GREEN, 0.06)
	var lines: Array[Label] = [banner]
	if String(liberation.milestone) != "":
		lines.append(_map_banner(String(liberation.milestone), 18 if liberation.milestone_big else 14, Retro.YELLOW if liberation.milestone_big else Retro.WHITE, 0.2, banner))
	await get_tree().create_timer(MapView.LIBERATION_SEC).timeout
	_fade_banners(lines)


## The Siege button shows how many stage rewards are waiting.
func set_siege_rewards(count: int) -> void:
	_siege_button.text = "Siege (%d)" % count if count > 0 else "Siege"
	if count > 0:
		_siege_button.add_theme_color_override("font_color", Retro.YELLOW)


## A stage of the week's siege has broken: once anything else has played, it's said across the map.
func announce_siege(banner: String, line: String) -> void:
	while celebrating:
		await get_tree().process_frame
	celebrating = true
	var sound := get_node_or_null("/root/Sound")
	if sound:
		sound.play("victory", 0.0, -3.0)
	var top := _map_banner(banner, 22, Retro.GOLD, 0.06)
	var lines: Array[Label] = [top, _map_banner(line, 14, Retro.WHITE, 0.2, top)]
	await get_tree().create_timer(HORDE_MOMENT_SEC + 0.8).timeout
	_fade_banners(lines)
	celebrating = false
	liberation_done.emit()


## Big text across the map that a tap passes straight through, at `y_share` of the map's height or,
## if it would overlap, just below `under` (the banner above it, which may have wrapped).
func _map_banner(text: String, font_size: int, color: Color, y_share: float, under: Label = null) -> Label:
	var label := Retro.title(Label.new(), font_size, color)
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_outline_color", Retro.INK)
	label.add_theme_constant_override("outline_size", 10)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.z_index = 5
	var backing := StyleBoxFlat.new()  # readable over the map's town names
	backing.bg_color = Color(Retro.INK, 0.72)
	backing.content_margin_top = 4
	backing.content_margin_bottom = 4
	label.add_theme_stylebox_override("normal", backing)
	label.custom_minimum_size.x = _map.size.x - 16  # before it's added, or it measures its height for no width
	_map.add_child(label)
	label.position = Vector2(8, _map.size.y * y_share)
	if under:
		label.position.y = maxf(label.position.y, under.position.y + under.get_combined_minimum_size().y + 4.0)
	label.pivot_offset = Vector2(_map.size.x / 2.0 - 8.0, 24)
	label.scale = Vector2.ONE * 2.2
	label.create_tween().tween_property(label, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return label


## The name keeps its full width (up to most of the panel); state and region take what's left.
func _fit_heading() -> void:
	var font := _info_title.get_theme_font("font")
	var w := font.get_string_size(_info_title.text, HORIZONTAL_ALIGNMENT_LEFT, -1, _info_title.get_theme_font_size("font_size")).x
	_info_title.custom_minimum_size.x = minf(ceilf(w) + 2.0, 470.0)


## Where territory `i` is, for its heading: "VA · Appalachia" (just the region off the US map).
func where(i: int) -> String:
	var parts: PackedStringArray = []
	var state := campaign._state_of(i) if campaign.uses_zip_data else ""
	if state != "":
		parts.append(state)
	var region: String = GameData.REGIONS.get(campaign.territories[i].region, {}).get("name", "")
	if region != "":
		parts.append(region)
	return " · ".join(parts)


func _select(i: int) -> void:
	_map.selected = i
	_map.refresh()
	var t := campaign.territories[i]
	_info_title.text = t.name + (("  " + t.id) if campaign.uses_zip_data else "")
	_info_where.text = where(i)
	_fit_heading()
	_action.visible = campaign.is_actionable(i)
	_delve.visible = t.owned and t.dungeon != ""
	_rematch.visible = campaign.can_rematch(i) and i != campaign.under_attack
	var sweepable := campaign.sweepable()
	_sweep.visible = not sweepable.is_empty()
	_sweep.text = "Sweep all" if sweepable.size() == 1 else "Sweep all (%d)" % sweepable.size()
	_action.set_meta("mode", "attack")
	if i == campaign.under_attack:
		_info_body.text = "Under attack! Lv %d · threat %d. Lose this fight and the territory falls." % [campaign.territory_level(i), t.threat]
		_action.text = "Defend!"
	elif campaign.home_owner(i) != "":
		_info_body.text = "%s's home: your teammate's pack began here.\nIt links your shared land like your own home does." % campaign.home_owner(i)
		_action.visible = false
	elif i == campaign.home:
		_info_body.text = "Home. Rest to heal injuries and fatigue (1 turn)."
		_action.text = "Rest"
		_action.visible = true
		_action.set_meta("mode", "rest")
	elif t.owned and campaign.is_cut_off(i):
		var left := campaign.turns_until_lost(i)
		_info_body.text = "CUT OFF from home: no held bonus, and you can't attack from here. Falls to the horde in %d turn%s unless you retake the land linking it home." % [left, "" if left == 1 else "s"]
		_action.text = "Patrol"
		_action.visible = true
		_action.set_meta("mode", "patrol")
	elif t.owned:
		_info_body.text = "Liberated. Survivors here reinforce your pack.\nPatrol for an easier fight (threat %d) that earns XP." % maxi(1, t.threat - 1)
		if campaign.state_progress(i) != "":
			_info_body.text += "\n" + campaign.state_progress(i)
		var chain := campaign.cut_by(i)
		if chain > 0:
			_info_body.text += "\nChokepoint: lose it and %d territor%s are cut off from home." % [chain, "y" if chain == 1 else "ies"]
		_action.text = "Patrol"
		_action.visible = true
		_action.set_meta("mode", "patrol")
	else:
		var cfg := campaign.battle_config(i)
		var tougher := roundi((campaign.zombie_strength(i, t.threat) - 1.0) * 100)
		_info_body.text = "Lv %d · threat %d · %d wave%s%s" % [
			campaign.territory_level(i), t.threat, cfg.waves.size(), "" if cfg.waves.size() == 1 else "s",
			(" · zombies +%d%%" % tougher) if tougher > 0 else ""]
		if t.failed_attacks > 0:
			_info_body.text += " · horde thinned to %d%%" % roundi(t.horde_strength() * 100)
		var warlord := campaign.warlord_at(i)
		if not warlord.is_empty():
			_info_title.text = String(warlord.name)
			_fit_heading()
			_info_body.text = "WARLORD: %s, %s. Win here to kill it and take its %s.\n%s" % [warlord.name, warlord.title, GameData.trinket(warlord.loot).name, _info_body.text]
		if t.boss != "":
			_info_body.text += "\nA raid boss: it matches your pack. At %d%% HP it calls for help, at %d%% it enrages, and it winds up Cataclysm (stun it to cancel, Guard to halve)." % [
				roundi(GameData.LEGEND_ADDS_AT * 100), roundi(GameData.LEGEND_ENRAGE_AT * 100)]
		elif campaign.territory_level(i) > campaign.base_level(i):
			_info_body.text += "\nThis horde matched your pack when you found it (usually Lv %d)." % campaign.base_level(i)
		if campaign.under_attack >= 0:
			_info_body.text += "\nDeal with the counterattack first."
		elif not campaign.can_attack(i):
			_info_body.text += "\nToo far. Liberate a neighboring territory first."
		if t.boss != "":
			var legend: Dictionary = GameData.LEGENDS[t.boss]
			_info_title.text = "Lair of the %s" % legend.name
			_fit_heading()
			_info_body.text = "%s\n%s" % [legend.lore, _info_body.text]
		_action.text = "Attack!"
		var loot := campaign.loot_at(i)
		if loot != "":
			_info_body.text += "\nDrops: %s (%s)" % [GameData.trinket(loot).name, GameData.trinket_effects(loot)]
		var cond: Dictionary = GameData.CONDITIONS[t.condition]
		_info_body.text += "\n%s: %s +%d%%." % [cond.name, cond.who, roundi(GameData.CONDITION_BONUS * 100)]
		if t.region != "" and GameData.REGIONS.has(t.region):
			_info_body.text += " Home turf for %s animals." % GameData.REGIONS[t.region].name
		if profile.duties.has("scout"):
			_info_body.text += "\nScouted: " + GameData.waves_text(cfg.waves)
		else:
			_info_body.text += "\nWaves unknown: put a benched animal on scout duty."
		if campaign.can_sweep(i):
			_info_body.text = "Your pack far outclasses this land: Sweep all takes it now, with all such land (1 turn each, no injuries, +%d XP each here).\n%s" % [campaign.sweep_xp(i), _info_body.text]
		if GameData.AUTO_MODE_ENABLED and profile.auto_battle and t.boss == "":
			_info_body.text += "\nAuto mode takes this one once your leader is Lv %d." % (campaign.base_level(i) + GameData.AUTO_LEVEL_GAP)
		if campaign.is_nest(i):
			_info_body.text += "\nHORDE NEST: spreads toward you every %d turns until liberated." % GameData.MIGRATE_EVERY
		elif campaign.spread.has(t.id):
			_info_body.text += "\nThe horde has spread here: threat +%d." % campaign.spread[t.id]
		if campaign.has_frontier(i):
			_info_body.text += "\nOn the frontier: liberate it to reveal what lies beyond."
		if campaign.state_progress(i) != "":
			_info_body.text += "\n" + campaign.state_progress(i)
		var survivor := campaign.pending_recruit(i)
		if survivor != "":
			var a: Dictionary = GameData.ANIMALS[survivor]
			_info_body.text += "\nSurvivor here: %s (%s). Liberate it to recruit!" % [a.name, a.role]
	_action.set_meta("territory", i)
	if _rematch.visible:
		_info_title.text = "Lair of the %s" % GameData.LEGENDS[t.boss].name
		_fit_heading()
		_info_body.text += "\nThe %s is beaten. Rematch it any time just for fun: no XP or trinkets, no injuries, no map turn." % GameData.LEGENDS[t.boss].name
	if t.dungeon != "":
		var d := GameData.dungeon(t.dungeon)
		_info_body.text += "\nDUNGEON: %s. %s" % [d.name, "Enter for endless waves and rewards (free, no injuries)." if t.owned else "Free this land to enter."]
	_ping.text = "Unping" if _map.pings.has(t.id) else "Ping"
	_fit_info()


## Shows the warning while the game being played isn't backed up (see Cloud.backup_trouble).
func _refresh_backup_warning() -> void:
	var cloud := get_node_or_null("/root/Cloud")
	var trouble: String = cloud.backup_trouble() if cloud else ""
	_backup_warning.visible = trouble != ""
	if trouble != "":
		_backup_warning.text = trouble


func _refresh_status() -> void:
	_status.text = "Pack strength +%d%%  ·  Counterattack every %d turns" % [
		roundi(campaign.held_bonus() * 100), campaign.counter_interval()]
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var parts: PackedStringArray = []
	var mutation := GameData.mutation(GameData.week_now())
	if not mutation.is_empty():
		parts.append("%s: %s" % [mutation.name, mutation.desc])
	var goal := campaign.week_goal()
	parts.append("Week goal: %s (%s)" % [goal.text, "done!" if goal.finished else "%d/%d" % [goal.done, goal.target]])
	_week.text = "  ·  ".join(parts)
	var event := campaign.last_event
	if campaign.is_liberated():
		event = "Every territory is liberated. Your neighborhood is safe!"
	_event.text = event
	_event.visible = event != ""
	_fit_news()


## A line under the latest event, e.g. auto mode saying what it's about to fight.
func announce(text: String) -> void:
	_event.text = (_event.text + "\n" + text) if _event.visible else text
	_event.visible = true
	_fit_news()


## Text rewraps when a box gets narrower or wider; refit then (not on height changes, which the
## fit itself causes).
func _on_resized(scroll: ScrollContainer, fit: Callable) -> void:
	if not is_equal_approx(scroll.get_meta("fit_width", -1.0), scroll.size.x):
		scroll.set_meta("fit_width", scroll.size.x)
		fit.call()


func _fit_news() -> void:
	_fit_scroll(_news, _news_box, NEWS_MAX_HEIGHT)


func _fit_info() -> void:
	_fit_scroll(_info_scroll, _info_body, INFO_MAX_HEIGHT)


## Makes `scroll` as tall as `content`, up to `cap`; past that it scrolls (from the top).
func _fit_scroll(scroll: ScrollContainer, content: Control, cap: float) -> void:
	await get_tree().process_frame  # labels know their wrapped height once laid out
	if not is_inside_tree():
		return
	var tall := content.get_combined_minimum_size().y if content.visible else 0.0
	scroll.custom_minimum_size.y = minf(tall, cap)
	scroll.visible = tall > 1.0
	scroll.scroll_vertical = 0


## New team chat: unread count on the Chat button, pings outlined on the map.
func _on_chat() -> void:
	var chat := get_node_or_null("/root/Chat")
	if chat == null:
		return
	var unread: int = chat.unread()
	if _chat_button:
		_chat_button.text = "Chat (%d)" % unread if unread > 0 else "Chat"
	_map.pings = _live_pings(chat.recent_pings())
	_map.refresh()
	if _map.selected >= 0:
		_ping.text = "Unping" if _map.pings.has(campaign.territories[_map.selected].id) else "Ping"


## The team's raid: a button to join an open lobby, or to deal with a fight this player left. A raid
## on a lair that's already free (a teammate beat the legend another way) is over: it's called off.
func _on_raid() -> void:
	var raid := get_node("/root/Raid")
	var legend: Dictionary = GameData.LEGENDS.get(String(raid.info.get("legend", "")), {})
	var lobby: bool = raid.status() == "lobby"
	var fighting: bool = raid.status() == "fighting" and raid.is_member()
	var live: bool = raid.status() in ["lobby", "fighting"]
	var over: bool = live and not raid.is_rematch() and _lair_is_free(raid.territory_id())
	if over:
		raid.cancel()
	_raid_button.visible = not legend.is_empty() and (lobby or fighting) and not over
	if _raid_button.visible:
		var text := "Raid on the %s was interrupted" if fighting else "Back to the raid on the %s" if raid.is_member() else "Join the raid on the %s"
		_raid_button.text = (text % legend.name).replace("raid on", "rematch with" if raid.is_rematch() else "raid on")
	_fit_news()


func _lair_is_free(territory: String) -> bool:
	for t in campaign.territories:
		if t.id == territory:
			return t.owned
	return false


## Pings whose job is done clear themselves: horde land once it's liberated, a counterattack once
## it's over.
func _live_pings(pings: Dictionary) -> Dictionary:
	var out := {}
	for i in campaign.territories.size():
		var t := campaign.territories[i]
		if not pings.has(t.id):
			continue
		var why := String(pings[t.id].why)
		if (why == "open" and t.owned) or (why == "attack" and campaign.under_attack != i):
			continue
		out[t.id] = pings[t.id].who
	return out


## Pings the selected territory for the team, or clears its ping.
func _on_ping() -> void:
	var i := _map.selected
	var t := campaign.territories[i]
	var clearing := _map.pings.has(t.id)
	var why := "attack" if i == campaign.under_attack else ("open" if not t.owned else "held")
	_ping.disabled = true
	var error: String = await get_node("/root/Chat").send(
		("cleared the ping on " if clearing else "pinged ") + t.full_name(), ("-" + t.id) if clearing else "%s@%s" % [t.id, why])
	if not is_inside_tree():
		return
	_ping.disabled = false
	_event.text = error if error != "" else ("Cleared the ping on %s." if clearing else "Pinged %s for your team.") % t.full_name()
	_event.visible = true
	_fit_news()


func _on_action() -> void:
	var i: int = _action.get_meta("territory")
	match _action.get_meta("mode", "attack"):
		"rest":
			rest_requested.emit()
			return
		"patrol":
			patrol_requested.emit(i)
			return
	var t := campaign.territories[i]
	if t.boss != "" and not t.owned:
		_show_briefing(i)
	else:
		battle_requested.emit(i)


## Everything worth knowing before taking on a legend: stats at this threat, its abilities and
## when it uses them, what escorts it, and how to beat it.
func _show_briefing(i: int) -> void:
	var t := campaign.territories[i]
	var legend: Dictionary = GameData.LEGENDS[t.boss]
	var data := GameData.enemy(t.boss)
	var cfg := campaign.battle_config(i)
	var mult: float = cfg.zombie_mult

	_briefing = ColorRect.new()
	(_briefing as ColorRect).color = Retro.INK
	_briefing.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_briefing)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	margin.add_theme_constant_override("margin_top", 36)
	_briefing.add_child(margin)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	margin.add_child(outer)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	Retro.touch_scroll(scroll)
	outer.add_child(scroll)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 8)
	scroll.add_child(col)

	var add := func(label: Label, wrap := true) -> void:
		if wrap:
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(label)
	var head := Retro.title(Label.new(), 18, MapView.LAIR)
	head.text = "Lair of the %s" % legend.name
	add.call(head)

	var sprite := TextureRect.new()
	sprite.custom_minimum_size = Vector2(0, 200)
	sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.flip_h = true
	var path := "res://art/pixel/%s.png" % t.boss
	if ResourceLoader.exists(path):
		sprite.texture = load(path)
	col.add_child(sprite)

	var lore := Retro.text(Label.new(), 24, Retro.MIST)
	lore.text = legend.lore
	add.call(lore)
	var stats := Retro.title(Label.new(), 11, Retro.WHITE)
	stats.text = "HP %d  ATK %d  DEF %d  SPD %d" % [roundi(data.hp * mult), roundi(data.atk * mult), data.def, data.spd]
	add.call(stats)

	var abilities := Retro.title(Label.new(), 13, Retro.GOLD)
	abilities.text = "Abilities"
	add.call(abilities)
	for skill_id: String in legend.skills:
		var s := GameData.skill(skill_id)
		var cd: int = s.get("cooldown", 0)
		var line := Retro.text(Label.new(), 21, Retro.MIST)
		var timing := "Its basic attack." if cd == 0 else "First used on its turn %d, then every %d turns." % [cd, cd + 1]
		line.text = "%s: %s %s" % [s.name, s.get("desc", ""), timing]
		add.call(line)

	var weak: Dictionary = GameData.LEGEND_WEAKNESS[legend.build]
	var weak_head := Retro.title(Label.new(), 13, Retro.GOLD)
	weak_head.text = "Weak spots"
	add.call(weak_head)
	var weak_line := Retro.text(Label.new(), 21, Retro.MIST)
	weak_line.text = "Weak to %s animals (+%d%% damage). Resists %s animals (-%d%%). %s" % [
		weak.weak, roundi((GameData.LEGEND_WEAK_MULT - 1.0) * 100), weak.resist,
		roundi((1.0 - GameData.LEGEND_RESIST_MULT) * 100), weak.why]
	add.call(weak_line)
	var cond: Dictionary = GameData.CONDITIONS[t.condition]
	var terrain := Retro.text(Label.new(), 21, Retro.CYAN)
	terrain.text = "%s: %s +%d%%." % [cond.name, cond.who, roundi(GameData.CONDITION_BONUS * 100)]
	add.call(terrain)

	var fight := Retro.title(Label.new(), 13, Retro.GOLD)
	fight.text = "The fight"
	add.call(fight)
	var escorts: PackedStringArray = []
	for id: String in cfg.waves[-1]:
		if id != t.boss:
			escorts.append(GameData.enemy(id).name)
	var plan := Retro.text(Label.new(), 21, Retro.MIST)
	plan.text = "%d waves. The %s waits in the last one%s. Zombies here are +%d%% tougher; your pack is level %d on average." % [
		cfg.waves.size(), legend.name, (" with " + ", ".join(escorts)) if not escorts.is_empty() else "",
		roundi((mult - 1.0) * 100), profile.pack_level()]
	add.call(plan)

	var loot := campaign.loot_at(i)
	if loot != "":
		var drop_head := Retro.title(Label.new(), 13, Retro.GOLD)
		drop_head.text = "Drops"
		add.call(drop_head)
		var drop := Retro.text(Label.new(), 21, Retro.YELLOW)
		drop.text = "%s: %s. \"%s\"" % [GameData.trinket(loot).name, GameData.trinket_effects(loot), GameData.trinket(loot).flavor]
		add.call(drop)

	var tip_head := Retro.title(Label.new(), 13, Retro.GOLD)
	tip_head.text = "Tip"
	add.call(tip_head)
	var tip := Retro.text(Label.new(), 21, Retro.GREEN)
	tip.text = GameData.BOSS_TIPS[legend.build]
	add.call(tip)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	outer.add_child(buttons)
	var back := Button.new()
	back.text = "Not yet"
	back.custom_minimum_size = Vector2(0, 84)
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back.pressed.connect(_briefing.queue_free)
	buttons.add_child(back)
	var go := Button.new()
	go.text = "Fight!"
	go.custom_minimum_size = Vector2(0, 84)
	go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	go.pressed.connect(battle_requested.emit.bind(i))
	buttons.add_child(go)


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Retro.INK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	margin.add_theme_constant_override("margin_top", 40)
	add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	margin.add_child(col)

	var title := Label.new()
	title.text = "Liberate %s" % campaign.territories[campaign.home].name
	if campaign.is_team():
		var towns: PackedStringArray = []
		for h in campaign.homes:
			if campaign.territories[h].name not in towns:  # teammates in the same town show it once
				towns.append(campaign.territories[h].name)
		title.text = "Team: " + " & ".join(towns)
	Retro.title(title, 18)
	title.clip_text = true
	col.add_child(title)
	Retro.text(_status, 22)
	col.add_child(_status)
	Retro.text(_week, 19, Color("c99bff"))
	_week.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_week)
	_backup_warning.visible = false
	_backup_warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_backup_warning.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_backup_warning.add_theme_font_size_override("font_size", Retro.px(18))
	_backup_warning.add_theme_color_override("font_color", Retro.WHITE)
	_backup_warning.add_theme_stylebox_override("normal", Retro.box(Color("8a2433"), Retro.RED, Retro.BORDER, 0, 8))
	_backup_warning.add_theme_stylebox_override("hover", Retro.box(Color("8a2433"), Retro.RED, Retro.BORDER, 0, 8))
	_backup_warning.add_theme_stylebox_override("pressed", Retro.box(Color("6e1c29"), Retro.RED, Retro.BORDER, 0, 8))
	_backup_warning.pressed.connect(func() -> void:
		_backup_warning.text = "Trying to back up..."
		var c := get_node_or_null("/root/Cloud")
		if c:
			c.retry())
	col.add_child(_backup_warning)
	var lines: PackedStringArray = []
	var names: PackedStringArray = []
	for t in campaign.territories:
		if t.boss != "" and not t.owned:  # a beaten legend's lair is just held land now
			names.append(GameData.LEGENDS[t.boss].name)
	if not names.is_empty():
		lines.append("Lairs in sight: " + ", ".join(names))
	var marching: PackedStringArray = []
	for w: Dictionary in campaign.warlords:
		if _index_of(String(w.at)) >= 0:
			marching.append("%s at %s" % [w.name, campaign.territories[_index_of(String(w.at))].name])
	if not marching.is_empty():
		lines.append(("Warlord: " if marching.size() == 1 else "Warlords: ") + ", ".join(marching))
	var rumor := campaign.dungeon_rumor()
	if not rumor.is_empty():
		lines.append("Dungeon: %s, %d mi %s" % [rumor.name, roundi(rumor.km * 0.621371), rumor.direction])
	var rumors: PackedStringArray = []
	for r in campaign.rumors():
		rumors.append("%s %d mi %s" % [GameData.LEGENDS[r.id].name, roundi(r.km * 0.621371), r.direction])
	if not rumors.is_empty():
		lines.append("Rumors from %s: %s" % [campaign.territories[campaign.rumor_origin()].name, ", ".join(rumors)])
	if not lines.is_empty():
		var legends := Label.new()
		Retro.text(legends, 20, MapView.LAIR)
		legends.text = "\n".join(lines)
		legends.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(legends)
	_news.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	Retro.touch_scroll(_news)
	col.add_child(_news)
	_news_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_news_box.add_theme_constant_override("separation", 4)
	_news.add_child(_news_box)
	_news.resized.connect(_on_resized.bind(_news, _fit_news))
	_raid_button.visible = false
	_raid_button.custom_minimum_size = Vector2(0, 64)
	_raid_button.add_theme_color_override("font_color", Retro.CYAN)
	_raid_button.pressed.connect(raid_requested.emit)
	col.add_child(_raid_button)
	var waiting := profile.bonuses_waiting(campaign.cleared)
	_bonus_button.visible = not waiting.is_empty()
	if not waiting.is_empty():
		_bonus_button.text = "%s cleared! Claim your bonus" % GameData.cleared_name(waiting[0])
	_bonus_button.custom_minimum_size = Vector2(0, 64)
	_bonus_button.add_theme_color_override("font_color", Retro.YELLOW)
	_bonus_button.pressed.connect(bonus_requested.emit)
	col.add_child(_bonus_button)
	Retro.text(_event, 20, Retro.ORANGE)
	_event.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_news_box.add_child(_event)
	if campaign.is_team() and not campaign.feed.is_empty():
		var recent: PackedStringArray = []
		for k in range(campaign.feed.size() - 1, maxi(-1, campaign.feed.size() - 4), -1):
			var entry: Dictionary = campaign.feed[k]
			recent.append("%s: %s" % [String(entry.who).get_slice(" · ", 0), entry.text])
		var team_feed := Label.new()
		Retro.text(team_feed, 19, Retro.CYAN)
		team_feed.text = "Team: " + "\n".join(recent)
		team_feed.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_news_box.add_child(team_feed)

	_map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_map.custom_minimum_size.y = MAP_MIN_HEIGHT
	_map.clip_contents = true
	col.add_child(_map)

	var legend := Label.new()
	legend.text = "Green: yours · Orange: attack (darker is tougher) · Purple: legend lair (grey once beaten)"
	Retro.text(legend, 17, Retro.FOG)
	legend.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	legend.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var legend_row := HBoxContainer.new()
	legend_row.add_theme_constant_override("separation", 10)
	col.add_child(legend_row)
	legend_row.add_child(legend)
	var guide := Button.new()
	guide.text = "Guide"
	guide.custom_minimum_size = Vector2(130, 52)
	guide.add_theme_font_size_override("font_size", Retro.px(15))
	guide.pressed.connect(func() -> void:
		var found: Array[String] = []
		if campaign:
			found = campaign.legends  # only legends with a lair on this map: never one not found yet
		Glossary.open(self, found))
	legend_row.add_child(guide)
	var sound := get_node_or_null("/root/Sound")
	if sound:
		var mute := Button.new()
		mute.text = "Sound off" if sound.muted else "Sound on"
		mute.custom_minimum_size = Vector2(130, 52)
		mute.add_theme_font_size_override("font_size", Retro.px(15))
		mute.pressed.connect(func() -> void:
			sound.set_muted(not sound.muted)
			mute.text = "Sound off" if sound.muted else "Sound on")
		legend_row.add_child(mute)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", Retro.box(Retro.NIGHT, Retro.STEEL, Retro.BORDER, 0, 8))
	col.add_child(panel)
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 4)
	panel.add_child(info)
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 14)
	info.add_child(heading)
	Retro.title(_info_title, 16, Retro.WHITE)
	_info_title.clip_text = true
	heading.add_child(_info_title)
	Retro.text(_info_where, 18, Retro.FOG)
	_info_where.clip_text = true
	_info_where.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_info_where.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	heading.add_child(_info_where)
	Retro.text(_info_body, 19)
	_info_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_body.custom_minimum_size = Vector2(0, 26)
	_info_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_info_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	Retro.touch_scroll(_info_scroll)
	info.add_child(_info_scroll)
	_info_scroll.add_child(_info_body)
	_info_scroll.resized.connect(_on_resized.bind(_info_scroll, _fit_info))
	_action.custom_minimum_size = Vector2(0, 60)
	_action.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_action.pressed.connect(_on_action)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	info.add_child(actions)
	actions.add_child(_action)
	_sweep.text = "Sweep all"
	_sweep.custom_minimum_size = Vector2(140, 60)
	_sweep.add_theme_color_override("font_color", Retro.GREEN)
	_sweep.visible = false
	_sweep.pressed.connect(func() -> void:
		if not campaign.sweepable().is_empty():
			sweep_requested.emit())
	actions.add_child(_sweep)
	_ping.text = "Ping"
	_ping.custom_minimum_size = Vector2(120, 60)
	_ping.visible = campaign.is_team()
	_ping.pressed.connect(_on_ping)
	actions.add_child(_ping)
	_delve.text = "Enter"
	_delve.custom_minimum_size = Vector2(130, 60)
	_delve.add_theme_color_override("font_color", Retro.CYAN)
	_delve.visible = false
	_delve.pressed.connect(func() -> void:
		if _map.selected >= 0:
			dungeon_requested.emit(campaign.territories[_map.selected].dungeon))
	actions.add_child(_delve)
	_rematch.text = "Rematch"
	_rematch.custom_minimum_size = Vector2(150, 60)
	_rematch.add_theme_color_override("font_color", Retro.PINK)
	_rematch.visible = false
	_rematch.pressed.connect(func() -> void:
		if _map.selected >= 0 and campaign.can_rematch(_map.selected):
			rematch_requested.emit(_map.selected))
	actions.add_child(_rematch)

	# Buttons share one row evenly; the data credit gets its own full-width line below them.
	var footer := HBoxContainer.new()
	col.add_child(footer)
	var credit := Label.new()
	credit.text = (ZipDB.ATTRIBUTION + " · " + ZctaDB.ATTRIBUTION) if campaign.uses_zip_data else ""
	Retro.text(credit, 13, Retro.STEEL)
	credit.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	credit.visible = credit.text != ""
	var pack := Button.new()
	pack.text = "Pack"
	pack.add_theme_font_size_override("font_size", Retro.px(16))
	pack.pressed.connect(pack_requested.emit)
	footer.add_child(pack)
	var stable_button := Button.new()
	stable_button.text = "Stable"
	stable_button.add_theme_font_size_override("font_size", Retro.px(16))
	stable_button.pressed.connect(stable_requested.emit)
	footer.add_child(stable_button)
	_siege_button.text = "Siege"
	_siege_button.add_theme_font_size_override("font_size", Retro.px(16))
	_siege_button.pressed.connect(siege_requested.emit)
	footer.add_child(_siege_button)
	if campaign.is_team():
		_chat_button = Button.new()
		_chat_button.text = "Chat"
		_chat_button.add_theme_font_size_override("font_size", Retro.px(16))
		_chat_button.pressed.connect(chat_requested.emit)
		footer.add_child(_chat_button)
	var cloud_button := Button.new()
	cloud_button.text = "Cloud"
	cloud_button.add_theme_font_size_override("font_size", Retro.px(16))
	cloud_button.pressed.connect(account_requested.emit)
	footer.add_child(cloud_button)
	var saves_button := Button.new()
	saves_button.text = "Saves"
	saves_button.add_theme_font_size_override("font_size", Retro.px(16))
	saves_button.pressed.connect(saves_requested.emit)
	footer.add_child(saves_button)
	if GameData.AUTO_MODE_ENABLED:
		var auto := Button.new()
		auto.text = "Auto: " + ("On" if profile.auto_battle else "Off")
		auto.add_theme_font_size_override("font_size", Retro.px(16))
		auto.pressed.connect(auto_toggled.emit)
		footer.add_child(auto)
	for button in footer.get_children():
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size = Vector2(0, 56)
	col.add_child(credit)
