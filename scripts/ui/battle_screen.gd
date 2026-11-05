class_name BattleScreen
extends Control

## Battle UI: animals line up on the left facing right, the horde on the right facing left.
## Builds its layout in code and drives a Battle turn by turn.

signal finished(won: bool)
## A legend raid ended: its stored outcome, and whether this device recorded it (and so should
## record the territory's result on the team map).
signal raid_done(outcome: Dictionary, recorded_here: bool)

const ENEMY_THINK_TIME := 0.6
const AFTER_ACTION_TIME := 0.45
## Auto mode plays the pack's turns itself, a bit quicker, and moves on between waves.
const AUTO_THINK_TIME := 0.35
const AUTO_AFTER_TIME := 0.3
const AUTO_WAVE_PAUSE := 1.2
const ORDER_PREVIEW := 7
const PARTY_SPRITE := {3: 150.0, 4: 120.0, 5: 104.0, 6: 90.0, 7: 56.0, 8: 56.0, 9: 52.0, 10: 52.0, 11: 48.0, 12: 48.0}  # by party size (raids bring up to 12)
const RAID_WAVE_PAUSE := 1.5  # raids move on to the next wave by themselves, on every device
const ENEMY_SPRITE := {1: 160.0, 2: 140.0, 3: 124.0, 4: 104.0}
## Front-row cards sit this much closer to the middle of the field than back-row ones.
const ROW_SHIFT := 44

var profile: Profile
## From Campaign.battle_config(): waves, zombie_mult, party_mult, place.
var config: Dictionary
## The AI picks the pack's moves (auto mode) until the player taps "Take control".
var auto := false
## Set at the end when the AI fought at least part of the battle: earns AUTO_XP_SHARE.
var was_auto := false
var battle: Battle
var xp_awarded := 0  # what each fighter earned (teammates get a share of it)
## A legend raid (Raid autoload): every player's critters, each player controlling their own.
var raid := false
var _seq := 0  # the next move number in a raid
var cards := {}  # Combatant -> UnitCard

var _actor: Combatant
var _selected_skill := ""
var _targets: Array[Combatant] = []

var _wave_label := Label.new()
var _order_label := RichTextLabel.new()
var _enemy_col := VBoxContainer.new()
var _log := RichTextLabel.new()
var _party_col := VBoxContainer.new()
var _skill_row := HBoxContainer.new()
var _skill_desc := Label.new()
var _overlay := ColorRect.new()
var _overlay_title := Label.new()
var _overlay_body := Label.new()
var _overlay_button := Button.new()
var _overlay_action: Callable


func _ready() -> void:
	_build_ui()
	_new_game()


func _exit_tree() -> void:
	if raid:
		_raid().holding = false


# --- Flow -------------------------------------------------------------------------------------

func _new_game() -> void:
	for card in cards.values():
		card.get_parent().queue_free()
	cards.clear()
	_log.clear()

	for child in _party_col.get_children():
		child.queue_free()
	if raid:
		battle = _raid_battle()
	else:
		battle = Battle.new(profile, config.waves, config.zombie_mult, config.party_mult, config.place, -1,
			config.get("condition", ""), config.get("region", ""))
		battle.configure(config)
	battle.log_message.connect(_on_log)
	battle.acting.connect(func(c: Combatant) -> void: _card(c).lunge())
	battle.damaged.connect(_on_damaged)
	battle.healed.connect(_on_healed)
	battle.status_changed.connect(func(c: Combatant) -> void: _card(c).refresh())
	battle.died.connect(func(_c: Combatant) -> void: _refresh_cards())  # a fallen front-liner can expose the back row
	battle.combo.connect(func(c: Combatant, _name: String) -> void: _float_text(_card(c), "COMBO!", Retro.CYAN, 20))
	battle.weak_hit.connect(func(c: Combatant) -> void: _float_text(_card(c), "WEAK SPOT!", Retro.CYAN, 18))
	battle.reinforced.connect(_on_reinforced)

	# Big raids: two cards per row, and the pack's side of the field gets more room.
	var big := battle.party.size() > 4  # raids of 2+ players: compact cards, two per row
	_party_col.size_flags_stretch_ratio = 1.3 if big else 1.0
	var row: HBoxContainer
	for k in battle.party.size():
		var holder: Container = _party_col
		if big:
			if k % 2 == 0:
				row = HBoxContainer.new()
				row.add_theme_constant_override("separation", 4)
				_party_col.add_child(row)
			holder = row
		var sprite: float = minf(PARTY_SPRITE[clampi(battle.party.size(), 3, 12)], 56.0) if big else PARTY_SPRITE[clampi(battle.party.size(), 3, 12)]
		_add_card(battle.party[k], holder, sprite, 8 if big else ROW_SHIFT, big)
	if auto:
		was_auto = true
		_show_take_control()
	_start_wave()


## While auto plays, the skill row holds one button that hands the rest of the fight to the player.
func _show_take_control() -> void:
	var b := Button.new()
	b.text = "AUTO · Take control"
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(0, 84)
	b.add_theme_font_size_override("font_size", Retro.px(20))
	b.pressed.connect(func() -> void:
		auto = false
		b.queue_free())
	_skill_row.add_child(b)


func _start_wave() -> void:
	for c in battle.enemies:
		cards[c].get_parent().queue_free()
		cards.erase(c)
	battle.start_next_wave()
	for c in battle.enemies:
		var enemy_sprite: float = ENEMY_SPRITE[clampi(battle.enemies.size(), 1, 4)] * (0.65 if battle.party.size() > 4 else 1.0)
		_add_card(c, _enemy_col, enemy_sprite, ROW_SHIFT)
	var cond: String = config.get("condition", "")
	_wave_label.text = "%s%s · WAVE %d/%d" % [battle.place.to_upper(),
		(" · " + GameData.CONDITIONS[cond].name.to_upper()) if cond != "" else "", battle.wave_index + 1, battle.wave_count()]
	_overlay.hide()
	_run_turns()


func _run_turns() -> void:
	while true:
		var actor := battle.next_turn()
		_refresh_cards()
		if actor == null:
			_show_outcome()
			return
		_set_active(actor)
		if raid and actor.is_player and actor.owner != _raid().my_id():
			_await_teammate(actor)
			return  # resumes once their move arrives (or the AI plays it after a timeout)
		if actor.is_player and not auto:
			_begin_player_turn(actor)
			return  # resumes from _execute() once the player picks a target
		await get_tree().create_timer(AUTO_THINK_TIME if auto else ENEMY_THINK_TIME).timeout
		var plan := AutoBattle.pick_action(battle, actor) if actor.is_player else battle.plan_enemy_action(actor)
		battle.use_skill(actor, plan.skill, plan.target)
		await get_tree().create_timer(AUTO_AFTER_TIME if auto else AFTER_ACTION_TIME).timeout


func _begin_player_turn(actor: Combatant) -> void:
	_actor = actor
	for child in _skill_row.get_children():
		child.queue_free()
	var first_ready := ""
	for skill_id in actor.skills:
		var skill := actor.skill_data(skill_id)
		var b := Button.new()
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 84)
		b.clip_text = true
		b.add_theme_font_size_override("font_size", Retro.px(20))
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.text = skill.name + ((" +%d" % actor.upgrade_count(skill_id)) if actor.upgrade_count(skill_id) > 0 else "")
		if not actor.can_use(skill_id):
			b.disabled = true
			b.text += " (%d)" % actor.cooldowns[skill_id]
		elif first_ready == "":
			first_ready = skill_id
		b.pressed.connect(_select_skill.bind(skill_id))
		b.set_meta("skill", skill_id)
		_skill_row.add_child(b)
	_select_skill(first_ready)


func _select_skill(skill_id: String) -> void:
	_selected_skill = skill_id
	for b: Button in _skill_row.get_children():
		b.set_pressed_no_signal(b.get_meta("skill") == skill_id)
	var s := _actor.skill_data(skill_id)
	var combo := GameData.combo_hint(s)
	var bits: PackedStringArray = [s.desc, GameData.skill_stats(s)]
	if combo != "":
		bits.append(combo)
	_skill_desc.text = " · ".join(bits)
	_targets = battle.valid_targets(_actor, skill_id)
	_set_active(_actor)


func _on_card_pressed(unit: Combatant) -> void:
	if _actor == null or unit not in _targets:
		return
	_execute(unit)


func _execute(target: Combatant) -> void:
	var actor := _actor
	_actor = null
	_targets.clear()
	_skill_desc.text = ""
	for child in _skill_row.get_children():
		child.queue_free()
	if raid:
		_skill_desc.text = "Sending your move..."
		var move := {}
		while move.is_empty():
			move = await _raid().post(_seq, {"skill": _selected_skill, "target": _ref(target)})
			if move.is_empty():
				_skill_desc.text = "Can't reach the raid. Trying again..."
				await get_tree().create_timer(2.0).timeout
		_skill_desc.text = ""
		_play_move(actor, move.action)  # someone else's if the AI already played this turn for you
	else:
		battle.use_skill(actor, _selected_skill, target)
	_set_active(null)
	await get_tree().create_timer(AFTER_ACTION_TIME).timeout
	_run_turns()


func _show_outcome() -> void:
	_set_active(null)
	match battle.outcome():
		Battle.Outcome.WAVE_CLEARED when raid:
			_show_overlay("Wave cleared!", "The raid pushes on...", "Next wave", _start_wave)
			await get_tree().create_timer(RAID_WAVE_PAUSE).timeout
			if _overlay.visible:
				_start_wave()
		Battle.Outcome.VICTORY, Battle.Outcome.DEFEAT when raid:
			_finish_raid()
		Battle.Outcome.WAVE_CLEARED:
			_show_overlay("Wave cleared!", "The pack rests and patches up.\nAnyone knocked out sits the next wave out, then gets back up.", "Next wave", _start_wave)
			if auto:
				await get_tree().create_timer(AUTO_WAVE_PAUSE).timeout
				if auto and _overlay.visible:
					_start_wave()
		Battle.Outcome.VICTORY:
			_log_battle()
			_show_overlay("Liberated!", "%s is free of the dead.\n\n%s" % [battle.place, _award_xp(true)], "Back to map", finished.emit.bind(true))
		Battle.Outcome.DEFEAT:
			_log_battle()
			_show_overlay("The pack retreats", "The horde was too much this time. Regroup and try again.\n\n%s" % _award_xp(false), "Back to map", finished.emit.bind(false))


# --- Raids -----------------------------------------------------------------------------------

func _raid() -> Node:
	return get_node("/root/Raid")


## Every raider's pack in join order, from the snapshots they brought, so all devices build the
## same battle; the legend grows with the number of players.
func _raid_battle() -> Battle:
	var r := _raid()
	r.holding = true
	var cfg: Dictionary = r.config()
	var packs := []
	for m: Dictionary in r.members():
		var p := Profile.from_snapshot(String(m.pack))
		if p:
			packs.append({"profile": p, "owner": String(m.user_id), "name": String(m.name).get_slice(" · ", 0)})
	var b := Battle.raid(packs, cfg.waves, float(cfg.zombie_mult), String(cfg.place), int(r.info.seed),
		String(cfg.get("condition", "")), String(cfg.get("region", "")))
	b.xp_mult = float(cfg.get("xp_mult", cfg.zombie_mult))
	var growth := GameData.legend_growth(packs.size())
	b.boss_hp_mult = growth.x
	b.boss_atk_mult = growth.y
	return b


## A unit as move data: which side and where in it (the same on every device).
func _ref(c: Combatant) -> Dictionary:
	return {"side": "party", "i": battle.party.find(c)} if c.is_player else {"side": "enemies", "i": battle.enemies.find(c)}


func _unref(ref: Dictionary) -> Combatant:
	var side: Array[Combatant] = battle.party if String(ref.get("side", "")) == "party" else battle.enemies
	var i := int(ref.get("i", -1))
	return side[i] if i >= 0 and i < side.size() else null


## Plays raid move number _seq. A move that doesn't fit (it shouldn't happen) falls back to the AI.
func _play_move(actor: Combatant, action: Dictionary) -> void:
	var skill := String(action.get("skill", ""))
	var target := _unref(action.get("target", {}))
	if skill not in actor.skills or not actor.can_use(skill) or target == null or target not in battle.valid_targets(actor, skill):
		var plan := AutoBattle.pick_action(battle, actor)
		skill = plan.skill
		target = plan.target
	battle.use_skill(actor, skill, target)
	_seq += 1


## A teammate's critter is up: wait for their move; after Raid.turn_timeout the AI plays it.
func _await_teammate(actor: Combatant) -> void:
	var r := _raid()
	var since := Time.get_ticks_msec()
	while is_inside_tree():
		var waited := (Time.get_ticks_msec() - since) / 1000.0
		_skill_desc.text = "Waiting for %s's %s... (%d)" % [actor.ally_of, actor.display_name, maxi(0, roundi(r.turn_timeout - waited))]
		var moves: Array = await r.moves_after(_seq - 1)
		var move: Dictionary = {}
		for m: Dictionary in moves:
			if m.seq == _seq:
				move = m
		if move.is_empty() and waited > r.turn_timeout:
			var plan := AutoBattle.pick_action(battle, actor)
			move = await r.post(_seq, {"skill": plan.skill, "target": _ref(plan.target), "auto": true})
		if not is_inside_tree():
			return
		if not move.is_empty():
			_skill_desc.text = ""
			_play_move(actor, move.action)
			_set_active(null)
			await get_tree().create_timer(AFTER_ACTION_TIME).timeout
			_run_turns()
			return
		await get_tree().create_timer(1.0).timeout


## The fight is over: the first device to report it stores the outcome (XP split between the
## players, who was knocked out); every player then collects their own share.
func _finish_raid() -> void:
	var r := _raid()
	var won := battle.outcome() == Battle.Outcome.VICTORY
	var players := maxi(1, r.members().size())
	var xp := battle.xp_earned if won else roundi(battle.xp_earned * GameData.DEFEAT_XP_SHARE)
	var outcome := {"won": won, "xp": roundi(xp / float(players)), "knocked": battle.knocked_out,
		"legend": String(r.config().get("legend", "")), "territory": String(r.config().get("territory", ""))}
	var brought: Array = []
	for m: Dictionary in r.members():
		if String(m.user_id) == r.my_id():
			var mine := Profile.from_snapshot(String(m.pack))
			brought = Array(mine.pack_ids()) if mine else []
	_show_overlay("Raid over", "Reporting back to the team...", "Back to map", Callable())
	_overlay_button.disabled = true
	var stored := {}
	while stored.is_empty():
		stored = await r.finish(outcome)
		if stored.is_empty():
			# Nobody has to wait on the network: the result can follow once back online.
			_show_overlay("Raid over", "Can't reach the team right now. Still trying.\n\nYou can head back: your rewards will arrive once you're online.", "Back to map", func() -> void:
				r.finish_later(outcome, brought)
				finished.emit(false))
			_overlay_button.disabled = false
			await get_tree().create_timer(2.0).timeout
	var result: Dictionary = stored.result
	if bool(stored.mine):
		_log_battle(r.members().size())
	var lines := profile.claim_raid(String(r.info.id), result, brought, r.my_id())
	raid_done.emit(result, bool(stored.mine))
	won = bool(result.get("won", false))
	_overlay_button.disabled = false
	_show_overlay("The legend falls!" if won else "The raid falls back",
		("%s is free.\n\n" % battle.place if won else "The legend was too much this time.\n\n") + "\n".join(lines),
		"Back to map", finished.emit.bind(won))


## Sends the finished fight to the battle log (Cloud), for balancing. Raids log once, from the
## device that recorded the result.
func _log_battle(players := 1) -> void:
	var report := battle.report()
	for key in ["legend", "threat", "region", "party_mult", "territory"]:
		if config.has(key):
			report[key] = config[key]
	report.merge({"players": players, "raid": raid, "auto": was_auto, "patrol": not config.has("territory")})
	get_node("/root/Cloud").log_battle(report)


## XP (half on a retreat, half again in auto mode), bench XP, injuries, fatigue and foraging.
## The caller saves the profile.
func _award_xp(won: bool) -> String:
	var amount := battle.xp_earned if won else roundi(battle.xp_earned * GameData.DEFEAT_XP_SHARE)
	if was_auto:
		amount = roundi(amount * GameData.AUTO_XP_SHARE)
	var fought: Array[String] = []
	for c in battle.party:
		fought.append(c.id)
	xp_awarded = amount
	return "\n".join(profile.after_battle(fought, battle.downed, amount, won))


# --- Feedback ---------------------------------------------------------------------------------

## A legend's reinforcement joins the fight, on the fallen zombie's card or a new one.
func _on_reinforced(fresh: Combatant, replaced: Combatant) -> void:
	if replaced:
		cards[replaced].get_parent().queue_free()
		cards.erase(replaced)
	_add_card(fresh, _enemy_col, ENEMY_SPRITE[GameData.MAX_ENEMIES] * (0.65 if battle.party.size() > 4 else 1.0), ROW_SHIFT)
	await get_tree().process_frame  # so the new card has its place on screen
	if cards.has(fresh):
		_float_text(cards[fresh], "ARRIVES!", Retro.PINK, 18)


func _on_log(text: String) -> void:
	_log.append_text(text + "\n")


func _on_damaged(target: Combatant, amount: int, crit: bool) -> void:
	var card := _card(target)
	card.refresh()
	card.flash(Color(1.6, 0.5, 0.5))
	_float_text(card, ("CRIT %d!" if crit else "%d") % amount, Retro.YELLOW if crit else Retro.PINK, 22 if crit else 18)


func _on_healed(target: Combatant, amount: int) -> void:
	var card := _card(target)
	card.refresh()
	card.flash(Color(0.6, 1.5, 0.6))
	_float_text(card, "+%d" % amount, Retro.GREEN, 18)


func _float_text(card: UnitCard, text: String, color: Color, font_size: int) -> void:
	var label := Label.new()
	label.text = text
	Retro.title(label, font_size, color)
	label.add_theme_color_override("font_outline_color", Retro.INK)
	label.add_theme_constant_override("outline_size", 8)
	label.z_index = 10
	add_child(label)
	var start := card.global_position + Vector2(card.size.x / 2.0 - 24, 10)
	label.global_position = start
	var tween := label.create_tween().set_parallel()
	tween.tween_property(label, "global_position:y", start.y - 70, 0.9).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 0.9).set_delay(0.3)
	tween.chain().tween_callback(label.queue_free)


func _set_active(actor: Combatant) -> void:
	for c in cards:
		var mode := UnitCard.Highlight.NONE
		if c == actor:
			mode = UnitCard.Highlight.ACTIVE
		if _actor != null and c in _targets:
			mode = UnitCard.Highlight.TARGET
		cards[c].set_highlight(mode)
	_update_order()


func _update_order() -> void:
	var parts: PackedStringArray = []
	for c in battle.upcoming(ORDER_PREVIEW):
		parts.append("[color=%s]%s[/color]" % [("#" + Retro.CYAN.to_html(false)) if c.is_player else ("#" + Retro.GREEN.to_html(false)), c.display_name])
	_order_label.text = "[b]Turn:[/b] " + "  ›  ".join(parts)


func _refresh_cards() -> void:
	for card in cards.values():
		card.refresh()


func _card(c: Combatant) -> UnitCard:
	return cards[c]


## Front-row cards are nudged toward the middle of the field, back-row ones toward the edge.
func _add_card(c: Combatant, column: Container, sprite_size: float, shift: int, compact := false) -> void:
	var card := UnitCard.new()
	card.compact = compact
	card.battle = battle
	card.setup(c, sprite_size)
	card.pressed.connect(_on_card_pressed)
	var slot := MarginContainer.new()
	# Padding on the edge side pushes a card toward the middle; on the middle side, toward the edge.
	var edge_side := "margin_left" if c.is_player else "margin_right"
	var middle_side := "margin_right" if c.is_player else "margin_left"
	slot.add_theme_constant_override(edge_side, shift if c.row == "front" else 0)
	slot.add_theme_constant_override(middle_side, 0 if c.row == "front" else shift)
	slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slot.add_child(card)
	column.add_child(slot)
	cards[c] = card


func _show_overlay(title: String, body: String, button_text: String, action: Callable) -> void:
	_overlay_title.text = title
	_overlay_body.text = body
	_overlay_button.text = button_text
	_overlay_action = action
	_overlay.show()


# --- Layout -----------------------------------------------------------------------------------

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Retro.INK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	margin.add_theme_constant_override("margin_top", 40)
	add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	margin.add_child(col)

	_wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	Retro.title(_wave_label, 13)  # the bold body font: long place names wrap instead of clipping
	_wave_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_wave_label)

	_order_label.bbcode_enabled = true
	_order_label.fit_content = true
	_order_label.scroll_active = false
	_order_label.add_theme_font_size_override("normal_font_size", Retro.px(20))
	_order_label.add_theme_font_size_override("bold_font_size", Retro.px(18))
	col.add_child(_order_label)

	# Battlefield: animals (left) vs. the horde (right).
	var field := PanelContainer.new()
	var field_color: Color = GameData.CONDITION_FIELD.get(config.get("condition", ""), Retro.SWAMP)
	field.add_theme_stylebox_override("panel", Retro.box(field_color, field_color.lightened(0.15), Retro.BORDER, 0, 6))
	field.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(field)
	var sides := HBoxContainer.new()
	sides.add_theme_constant_override("separation", 8)
	field.add_child(sides)
	for side in [_party_col, _enemy_col]:
		side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		side.alignment = BoxContainer.ALIGNMENT_CENTER
		side.add_theme_constant_override("separation", 6)
		sides.add_child(side)

	var log_panel := PanelContainer.new()
	log_panel.add_theme_stylebox_override("panel", Retro.box(Retro.NIGHT, Retro.SLATE))
	log_panel.custom_minimum_size = Vector2(0, 150)
	col.add_child(log_panel)
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.custom_minimum_size = Vector2(0, 130)
	_log.add_theme_font_size_override("normal_font_size", Retro.px(20))
	_log.add_theme_font_size_override("bold_font_size", Retro.px(20))
	log_panel.add_child(_log)

	_skill_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	Retro.text(_skill_desc, 19)
	_skill_desc.max_lines_visible = 3  # the skill buttons below must stay on screen
	_skill_desc.custom_minimum_size = Vector2(0, 46)
	_skill_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART  # long stat lines must not widen the screen
	col.add_child(_skill_desc)

	_skill_row.add_theme_constant_override("separation", 8)
	_skill_row.custom_minimum_size = Vector2(0, 84)
	col.add_child(_skill_row)

	_overlay.color = Color(Retro.INK, 0.85)
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.z_index = 20
	_overlay.hide()
	add_child(_overlay)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 20)
	box.custom_minimum_size = Vector2(520, 0)
	center.add_child(box)
	_overlay_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	Retro.title(_overlay_title, 26)
	_overlay_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_overlay_title)
	_overlay_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay_body.autowrap_mode = TextServer.AUTOWRAP_WORD
	box.add_child(_overlay_body)
	_overlay_button.custom_minimum_size = Vector2(0, 90)
	_overlay_button.pressed.connect(func() -> void: _overlay_action.call())
	box.add_child(_overlay_button)
