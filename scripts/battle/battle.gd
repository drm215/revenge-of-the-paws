class_name Battle
extends RefCounted

## Turn-based battle rules. No nodes or timing here: the UI (or a test) drives it by calling
## next_turn() then use_skill(), and listens to the signals for feedback.

signal log_message(text: String)
signal acting(actor: Combatant)
signal damaged(target: Combatant, amount: int, crit: bool)
signal healed(target: Combatant, amount: int)
signal status_changed(target: Combatant)
signal died(target: Combatant)

enum Outcome { ONGOING, WAVE_CLEARED, VICTORY, DEFEAT }

const DEF_SCALE := 50.0
const CRIT_MULT := 1.5
const INFECTION_DAMAGE := 0.06
const REST_HEAL := 0.3
const REVIVE_HP := 0.25
const HUNT_WEAK_CHANCE := 0.7

var party: Array[Combatant] = []
var enemies: Array[Combatant] = []
var wave_index := -1
var round_number := 0
var current: Combatant
var place := ""
var xp_earned := 0  # from every zombie and legend the pack has defeated so far
var xp_mult := 1.0  # XP per kill scales with the territory's own strength, not with pack-scaled zombies
var downed: Array[String] = []  # pack members knocked out at any point (they'll be injured)
var condition := ""
var _perk_log: PackedStringArray = []  # lineup effects, announced as the first wave starts
var rng := RandomNumberGenerator.new()

var _waves: Array
var _zombie_mult: float
var _turn_queue: Array[Combatant] = []


## `party_mult` scales party HP/ATK (held-territory reinforcements); `zombie_mult` scales zombies.
func _init(profile: Profile, waves: Array = GameData.WAVES, zombie_mult := 1.0, party_mult := 1.0,
		place_name := "", seed_value: int = -1, territory_condition := "", territory_region := "") -> void:
	if seed_value >= 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	_waves = waves
	_zombie_mult = zombie_mult
	xp_mult = zombie_mult
	place = place_name if place_name != "" else profile.town
	for unit_id in profile.pack_ids():
		var c := profile.build_unit(unit_id)
		c.scale_stats(party_mult, party_mult, 1.0)
		party.append(c)
	condition = territory_condition
	_apply_lineup(profile, territory_region)


## Injuries, fatigue, terrain, home turf and bonds: the reasons a lineup matters.
func _apply_lineup(profile: Profile, region: String) -> void:
	var suited: PackedStringArray = []
	var natives: PackedStringArray = []
	for c in party:
		var hp := 1.0
		var atk := 1.0
		var def := 1.0
		if profile.injuries.has(c.id):
			hp *= 1.0 - GameData.INJURY_PENALTY
			atk *= 1.0 - GameData.INJURY_PENALTY
			c.notes.append("Injured")
		var tired := profile.fatigue_penalty(c.id)
		if tired > 0.0:
			hp *= 1.0 - tired
			atk *= 1.0 - tired
			def *= 1.0 - tired
			c.notes.append("Tired -%d%%" % roundi(tired * 100))
		if condition != "" and condition in c.tags:
			atk *= 1.0 + GameData.CONDITION_BONUS
			def *= 1.0 + GameData.CONDITION_BONUS
			suited.append(c.display_name)
			c.notes.append(GameData.CONDITIONS[condition].name)
		if region != "" and region in GameData.native_regions(c.id):
			atk *= 1.0 + GameData.HOME_TURF_BONUS
			def *= 1.0 + GameData.HOME_TURF_BONUS
			natives.append(c.display_name)
			c.notes.append("Home turf")
		c.scale_stats(hp, atk, def)
	if condition != "":
		_perk_log.append("[color=#2ce8f5]%s: %s[/color]" % [GameData.CONDITIONS[condition].name,
			("%s +%d%%" % [", ".join(suited), roundi(GameData.CONDITION_BONUS * 100)]) if not suited.is_empty() else "nobody here is suited to it"])
	if not natives.is_empty():
		_perk_log.append("[color=#2ce8f5]Home turf: %s +%d%%[/color]" % [", ".join(natives), roundi(GameData.HOME_TURF_BONUS * 100)])
	var ids: Array[String] = []
	for c in party:
		ids.append(c.id)
	for bond in GameData.active_bonds(ids):
		var names: PackedStringArray = []
		for c in party:
			if c.id in bond.members:
				c.scale_stats(1.0, 1.0 + GameData.BOND_BONUS, 1.0 + GameData.BOND_BONUS)
				c.notes.append(bond.name)
				names.append(c.display_name)
		_perk_log.append("[color=#feae34]Bond %s: %s +%d%% ATK/DEF[/color]" % [bond.name, ", ".join(names), roundi(GameData.BOND_BONUS * 100)])


func wave_count() -> int:
	return _waves.size()


func is_last_wave() -> bool:
	return wave_index >= wave_count() - 1


func start_next_wave() -> void:
	wave_index += 1
	if wave_index > 0:
		_rest_party()
	enemies.clear()
	var wave: Array = _waves[wave_index]
	var totals := {}
	for zombie_id in wave:
		totals[zombie_id] = totals.get(zombie_id, 0) + 1
	var seen := {}
	for zombie_id in wave:
		var z := Combatant.from_data(zombie_id, GameData.enemy(zombie_id), false)
		if totals[zombie_id] > 1:
			z.display_name += " " + "ABCD"[seen.get(zombie_id, 0)]
			seen[zombie_id] = seen.get(zombie_id, 0) + 1
		z.scale_stats(_zombie_mult, _zombie_mult, 1.0)
		enemies.append(z)
	round_number = 0
	_turn_queue.clear()
	current = null
	log_message.emit("[b]Wave %d/%d[/b]: the dead shamble through %s..." % [
		wave_index + 1, wave_count(), place if place != "" else "town"])
	if wave_index == 0:
		for line in _perk_log:
			log_message.emit(line)
	for c in living(party):
		match c.wave_start:
			"guard":
				c.add_status("guard", 2)
				status_changed.emit(c)
			"weaken_foes":
				log_message.emit("%s's %s fouls the air!" % [c.display_name, GameData.TRINKETS[c.trinket].name])
				for z in enemies:
					z.add_status("weakened", 2)
					status_changed.emit(z)
	for z in enemies:
		if z.is_boss:
			log_message.emit("[color=#c99bff][b]%s appears![/b] %s[/color]" % [z.display_name, GameData.LEGENDS[z.id].lore])
	var leader := _leader(party)
	if leader:
		log_message.emit("[color=#ffd34d]%s leads the pack: allies +%d%% ATK/DEF.[/color]" % [
			leader.display_name, roundi(GameData.LEADER_AURA * 100)])


func outcome() -> Outcome:
	if living(party).is_empty():
		return Outcome.DEFEAT
	if living(enemies).is_empty():
		return Outcome.VICTORY if is_last_wave() else Outcome.WAVE_CLEARED
	return Outcome.ONGOING


## Advances to the next unit that can act and returns it, or null when the wave is over.
## Start-of-turn effects (infection, stun) resolve inside this call.
func next_turn() -> Combatant:
	while outcome() == Outcome.ONGOING:
		if _turn_queue.is_empty():
			round_number += 1
			_turn_queue = _turn_order()
		var actor: Combatant = _turn_queue.pop_front()
		if not actor.is_alive():
			continue
		current = actor
		actor.tick_cooldowns()
		if actor.regen > 0.0 and actor.hp < actor.max_hp:
			_heal(actor, maxi(1, roundi(actor.max_hp * actor.regen)))
		if actor.has_status("infected"):
			log_message.emit("%s suffers from infection." % actor.display_name)
			_apply_damage(actor, maxi(1, roundi(actor.max_hp * INFECTION_DAMAGE)), false)
			if not actor.is_alive():
				continue
		if actor.has_status("stunned"):
			log_message.emit("%s is stunned!" % actor.display_name)
			_end_turn(actor)
			continue
		return actor
	current = null
	return null


## Units in the order they'll act: the rest of this round, then the next one.
func upcoming(count: int) -> Array[Combatant]:
	var out: Array[Combatant] = []
	if current and current.is_alive():
		out.append(current)
	for c in _turn_queue:
		if c.is_alive():
			out.append(c)
	var next_round := _turn_order()
	while out.size() < count and not next_round.is_empty():
		out.append_array(next_round)
	return out.slice(0, count)


func valid_targets(actor: Combatant, skill_id: String) -> Array[Combatant]:
	match GameData.skill(skill_id).target:
		"enemy", "all_enemies":
			return living(_opponents(actor))
		"ally", "all_allies":
			return living(_allies(actor))
		_:
			return [actor]


func use_skill(actor: Combatant, skill_id: String, target: Combatant) -> void:
	var skill := actor.skill_data(skill_id)
	acting.emit(actor)
	actor.put_on_cooldown(skill_id, skill.get("cooldown", 0))
	var targets: Array[Combatant]
	match skill.target:
		"all_enemies":
			targets = living(_opponents(actor))
			log_message.emit("%s uses %s!" % [actor.display_name, skill.name])
		"all_allies":
			targets = living(_allies(actor))
			log_message.emit("%s uses %s!" % [actor.display_name, skill.name])
		"self":
			targets = [actor]
			log_message.emit("%s uses %s!" % [actor.display_name, skill.name])
		_:
			targets = [target]
			log_message.emit("%s uses %s on %s." % [actor.display_name, skill.name, target.display_name])

	var power: float = skill.get("power", 0.0)
	var heal: float = skill.get("heal", 0.0)
	for t in targets:
		if not t.is_alive():
			continue
		if power > 0.0:
			_deal_damage(actor, t, power, skill.get("crit_bonus", 0.0), skill.target == "enemy")
		if heal > 0.0:
			_heal(t, roundi(t.max_hp * heal))
		if skill.get("cleanse", false) and t.has_status("infected"):
			t.statuses.erase("infected")
			log_message.emit("%s is cured." % t.display_name)
			status_changed.emit(t)
		if t.is_alive():
			for effect: Dictionary in skill.get("apply", []):
				if effect.status in t.immune:
					continue
				if rng.randf() < effect.get("chance", 1.0):
					t.add_status(effect.status, effect.turns)
					if t != actor:
						log_message.emit("%s is %s." % [t.display_name, GameData.STATUSES[effect.status].name.to_lower()])
					status_changed.emit(t)
	_end_turn(actor)


## Zombie AI: strongest ready skill, respects Taunt, some types prey on the weakest animal.
func plan_enemy_action(actor: Combatant) -> Dictionary:
	var skill_id := actor.skills[0]
	for id in actor.skills:
		if actor.can_use(id):
			skill_id = id
	var pool := valid_targets(actor, skill_id)
	var taunting: Array[Combatant] = []
	for c in pool:
		if c.has_status("taunt"):
			taunting.append(c)
	if not taunting.is_empty():
		pool = taunting
	var target: Combatant = pool[rng.randi_range(0, pool.size() - 1)]
	if actor.traits.get("hunts_weak", false) and taunting.is_empty() and rng.randf() < HUNT_WEAK_CHANCE:
		for c in pool:
			if c.hp < target.hp:
				target = c
	return {"skill": skill_id, "target": target}


static func living(units: Array[Combatant]) -> Array[Combatant]:
	var out: Array[Combatant] = []
	for c in units:
		if c.is_alive():
			out.append(c)
	return out


func _opponents(actor: Combatant) -> Array[Combatant]:
	return enemies if actor.is_player else party


func _allies(actor: Combatant) -> Array[Combatant]:
	return party if actor.is_player else enemies


func _turn_order() -> Array[Combatant]:
	var order := living(party) + living(enemies)
	order.sort_custom(func(a: Combatant, b: Combatant) -> bool:
		if a.spd != b.spd:
			return a.spd > b.spd
		return a.is_player and not b.is_player)
	var typed: Array[Combatant] = []
	typed.assign(order)
	return typed


func _end_turn(actor: Combatant) -> void:
	if not actor.statuses.is_empty():
		actor.tick_statuses()
		status_changed.emit(actor)


func _leader(side: Array[Combatant]) -> Combatant:
	for c in side:
		if c.is_leader and c.is_alive():
			return c
	return null


## 1 + LEADER_AURA when a living leader (other than this unit) is on its side.
func _aura_mult(c: Combatant) -> float:
	var leader := _leader(_allies(c))
	return 1.0 + GameData.LEADER_AURA if leader and leader != c else 1.0


func _deal_damage(src: Combatant, dst: Combatant, power: float, crit_bonus: float, single := true) -> void:
	var atk := src.atk * _aura_mult(src)
	if src.has_status("weakened"):
		atk *= GameData.WEAKENED_ATK_MULT
	var dmg := atk * power * DEF_SCALE / (DEF_SCALE + dst.effective_def() * _aura_mult(dst))
	dmg *= rng.randf_range(0.9, 1.1)
	var crit := rng.randf() < src.crit + crit_bonus
	if crit:
		dmg *= CRIT_MULT
	if single and dst.traits.get("armored", false):
		dmg *= 0.5
	if dst.is_boss and src.is_player:
		var weak: Dictionary = GameData.LEGEND_WEAKNESS[GameData.LEGENDS[dst.id].build]
		if weak.weak in src.tags:
			dmg *= GameData.LEGEND_WEAK_MULT
		elif weak.resist in src.tags:
			dmg *= GameData.LEGEND_RESIST_MULT
	var amount := maxi(1, roundi(dmg))
	_apply_damage(dst, amount, crit)
	if src.lifesteal > 0.0 and src.is_alive() and src.hp < src.max_hp:
		_heal(src, maxi(1, roundi(amount * src.lifesteal)))
	if dst.thorns > 0.0 and src.is_alive():
		_apply_damage(src, maxi(1, roundi(amount * dst.thorns)), false)


func _apply_damage(dst: Combatant, amount: int, crit: bool) -> void:
	dst.hp = maxi(0, dst.hp - amount)
	damaged.emit(dst, amount, crit)
	if dst.is_alive():
		return
	dst.statuses.clear()
	log_message.emit("[color=%s]%s %s![/color]" % [
		"#ff8080" if dst.is_player else "#a0e080",
		dst.display_name,
		"is down" if dst.is_player else "is destroyed",
	])
	died.emit(dst)
	if dst.is_player and dst.id not in downed:
		downed.append(dst.id)
	if not dst.is_player:
		xp_earned += roundi(dst.xp_value * xp_mult)
	if dst.is_leader and outcome() == Outcome.ONGOING:
		log_message.emit("[color=#ff8080]Without %s, the pack falters![/color]" % dst.display_name)
	var blast: int = dst.traits.get("explode_on_death", 0)
	if blast > 0:
		log_message.emit("%s bursts in a cloud of gore!" % dst.display_name)
		for c in living(_opponents(dst)):
			_apply_damage(c, blast, false)


func _heal(target: Combatant, amount: int) -> void:
	var actual := mini(amount, target.max_hp - target.hp)
	target.hp += actual
	healed.emit(target, actual)


func _rest_party() -> void:
	for c in party:
		if c.is_alive():
			c.hp = mini(c.max_hp, c.hp + roundi(c.max_hp * REST_HEAL))
		else:
			c.hp = roundi(c.max_hp * REVIVE_HP)
		c.statuses.clear()
		c.cooldowns.clear()
	log_message.emit("The pack catches its breath. (+%d%% HP)" % roundi(REST_HEAL * 100))
