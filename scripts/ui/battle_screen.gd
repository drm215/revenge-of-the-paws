class_name BattleScreen
extends Control

## Battle UI: animals line up on the left facing right, the horde on the right facing left.
## Builds its layout in code and drives a Battle turn by turn.

signal finished(won: bool)

const ENEMY_THINK_TIME := 0.6
const AFTER_ACTION_TIME := 0.45
const ORDER_PREVIEW := 7
const PARTY_SPRITE := 150.0
const ENEMY_SPRITE := {1: 160.0, 2: 140.0, 3: 124.0, 4: 104.0}

var profile: Profile
## From Campaign.battle_config(): waves, zombie_mult, party_mult, place.
var config: Dictionary
var battle: Battle
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


# --- Flow -------------------------------------------------------------------------------------

func _new_game() -> void:
	for card in cards.values():
		card.queue_free()
	cards.clear()
	_log.clear()

	battle = Battle.new(profile, config.waves, config.zombie_mult, config.party_mult, config.place, -1,
		config.get("condition", ""), config.get("region", ""))
	battle.log_message.connect(_on_log)
	battle.acting.connect(func(c: Combatant) -> void: _card(c).lunge())
	battle.damaged.connect(_on_damaged)
	battle.healed.connect(_on_healed)
	battle.status_changed.connect(func(c: Combatant) -> void: _card(c).refresh())
	battle.died.connect(func(c: Combatant) -> void: _card(c).refresh())

	for c in battle.party:
		_add_card(c, _party_col, PARTY_SPRITE)
	_start_wave()


func _start_wave() -> void:
	for c in battle.enemies:
		cards[c].queue_free()
		cards.erase(c)
	battle.start_next_wave()
	for c in battle.enemies:
		_add_card(c, _enemy_col, ENEMY_SPRITE[clampi(battle.enemies.size(), 1, 4)])
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
		if actor.is_player:
			_begin_player_turn(actor)
			return  # resumes from _execute() once the player picks a target
		await get_tree().create_timer(ENEMY_THINK_TIME).timeout
		var plan := battle.plan_enemy_action(actor)
		battle.use_skill(actor, plan.skill, plan.target)
		await get_tree().create_timer(AFTER_ACTION_TIME).timeout


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
		b.add_theme_font_size_override("font_size", Retro.px(12))
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
	_skill_desc.text = s.desc + "\n" + GameData.skill_stats(s)
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
	battle.use_skill(actor, _selected_skill, target)
	_set_active(null)
	await get_tree().create_timer(AFTER_ACTION_TIME).timeout
	_run_turns()


func _show_outcome() -> void:
	_set_active(null)
	match battle.outcome():
		Battle.Outcome.WAVE_CLEARED:
			_show_overlay("Wave cleared!", "The pack rests and patches up.\nFallen friends get back on their paws.", "Next wave", _start_wave)
		Battle.Outcome.VICTORY:
			_show_overlay("Liberated!", "%s is free of the dead.\n\n%s" % [battle.place, _award_xp(true)], "Back to map", finished.emit.bind(true))
		Battle.Outcome.DEFEAT:
			_show_overlay("The pack retreats", "The horde was too much this time. Regroup and try again.\n\n%s" % _award_xp(false), "Back to map", finished.emit.bind(false))


## XP (half on a retreat), bench XP, injuries, fatigue and foraging. The caller saves the profile.
func _award_xp(won: bool) -> String:
	var amount := battle.xp_earned if won else roundi(battle.xp_earned * GameData.DEFEAT_XP_SHARE)
	var fought: Array[String] = []
	for c in battle.party:
		fought.append(c.id)
	return "\n".join(profile.after_battle(fought, battle.downed, amount, won))


# --- Feedback ---------------------------------------------------------------------------------

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


func _add_card(c: Combatant, column: VBoxContainer, sprite_size: float) -> void:
	var card := UnitCard.new()
	card.setup(c, sprite_size)
	card.pressed.connect(_on_card_pressed)
	column.add_child(card)
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
	Retro.title(_wave_label, 16)
	_wave_label.clip_text = true
	col.add_child(_wave_label)

	_order_label.bbcode_enabled = true
	_order_label.fit_content = true
	_order_label.scroll_active = false
	_order_label.add_theme_font_size_override("normal_font_size", Retro.px(20))
	_order_label.add_theme_font_size_override("bold_font_size", Retro.px(11))
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
	_log.add_theme_font_size_override("bold_font_size", Retro.px(11))
	log_panel.add_child(_log)

	_skill_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	Retro.text(_skill_desc, 21)
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
