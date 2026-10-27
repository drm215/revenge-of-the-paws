class_name Combatant
extends RefCounted

## One unit in a battle: an animal or a zombie. Pure data + small helpers, no visuals.

const GUARD_DEF_MULT := 1.6

var id: String
var display_name: String
var species: String
var role: String
var is_player: bool
var is_leader := false
var is_boss := false
var level := 1
var xp_value := 0  # XP the pack earns for defeating this unit
var trinket := ""
var lifesteal := 0.0
var thorns := 0.0
var regen := 0.0
var immune: Array = []
var wave_start := ""  # trinket effect at the start of every wave
var skill_mods := {}  # skill id -> upgrade steps from the tech tree
var tags: Array[String] = []  # GameData.tags_of(): kind, terrain affinities, role
var notes: PackedStringArray = []  # lineup effects shown on the battle card ("Injured", "Night +15%")
var mastered := false
var color: Color
var max_hp: int
var hp: int
var atk: int
var def: int
var spd: int
var crit: float
var skills: Array[String] = []
var traits: Dictionary = {}
var statuses: Dictionary = {}  # status id -> turns remaining
var cooldowns: Dictionary = {}  # skill id -> turns until ready


static func from_data(unit_id: String, data: Dictionary, player: bool) -> Combatant:
	var c := Combatant.new()
	c.id = unit_id
	c.display_name = data.name
	c.species = data.name
	c.role = data.get("role", "")
	c.is_boss = data.get("boss", false)
	c.xp_value = data.get("xp", 0)
	c.is_player = player
	c.color = data.color
	c.max_hp = data.hp
	c.hp = c.max_hp
	c.atk = data.atk
	c.def = data.def
	c.spd = data.spd
	c.crit = data.crit
	c.skills.assign(data.skills)
	c.traits = data.get("traits", {})
	# Zombies start with big skills on cooldown so they're telegraphed, not opening alpha strikes.
	if not player:
		for skill_id in c.skills:
			var cd: int = GameData.skill(skill_id).get("cooldown", 0)
			if cd > 0:
				c.cooldowns[skill_id] = cd
	return c


## Turns this unit into the player's pet: their name, buffed stats, and the leadership aura.
func make_leader(pet_name: String) -> void:
	display_name = pet_name
	is_leader = true
	scale_stats(GameData.PET_STAT_MULT, GameData.PET_STAT_MULT, GameData.PET_STAT_MULT)


func apply_level(new_level: int) -> void:
	level = new_level
	var n := level - 1
	scale_stats(1.0 + GameData.LEVEL_GROWTH.hp * n, 1.0 + GameData.LEVEL_GROWTH.atk * n, 1.0 + GameData.LEVEL_GROWTH.def * n)


## The role's signature skill, bought in the tech tree.
func learn_signature() -> void:
	var signature := GameData.signature_skill(role)
	if signature not in skills:
		skills.append(signature)


## This unit's version of a skill: upgrades, mastery and its own signature-skill name applied.
func skill_data(skill_id: String) -> Dictionary:
	if not is_player:
		return GameData.skill(skill_id)
	var s := GameData.upgraded_skill(skill_id, skill_mods.get(skill_id, {}), mastered)
	if skill_id == GameData.signature_skill(role) and GameData.SIGNATURE_NAMES.has(id):
		s.name = GameData.SIGNATURE_NAMES[id]
	return s


func upgrade_count(skill_id: String) -> int:
	var total := 0
	for k in skill_mods.get(skill_id, {}).values():
		total += k
	return total


## Stat picks from level-ups: {stat: steps}.
func apply_stat_mods(steps: Dictionary) -> void:
	var step: Dictionary = GameData.STAT_STEP
	scale_stats(1.0 + step.hp * steps.get("hp", 0), 1.0 + step.atk * steps.get("atk", 0), 1.0 + step.def * steps.get("def", 0))
	spd += step.spd * steps.get("spd", 0)
	crit += step.crit * steps.get("crit", 0)


func equip(trinket_id: String) -> void:
	var t: Dictionary = GameData.TRINKETS[trinket_id]
	trinket = trinket_id
	scale_stats(1.0 + t.get("hp", 0.0), 1.0 + t.get("atk", 0.0), 1.0 + t.get("def", 0.0))
	spd = maxi(1, roundi(spd * (1.0 + t.get("spd", 0.0))))
	crit += t.get("crit", 0.0)
	lifesteal = t.get("lifesteal", 0.0)
	thorns = t.get("thorns", 0.0)
	regen = t.get("regen", 0.0)
	immune = t.get("immune", [])
	wave_start = t.get("start", "")


func scale_stats(hp_mult: float, atk_mult: float, def_mult: float) -> void:
	max_hp = roundi(max_hp * hp_mult)
	hp = max_hp
	atk = roundi(atk * atk_mult)
	def = roundi(def * def_mult)


func is_alive() -> bool:
	return hp > 0


func hp_ratio() -> float:
	return float(hp) / max_hp


func effective_def() -> float:
	return def * (GUARD_DEF_MULT if has_status("guard") else 1.0)


func has_status(status: String) -> bool:
	return statuses.get(status, 0) > 0


func add_status(status: String, turns: int) -> void:
	statuses[status] = maxi(statuses.get(status, 0), turns)


func can_use(skill_id: String) -> bool:
	return cooldowns.get(skill_id, 0) <= 0


func put_on_cooldown(skill_id: String, cooldown: int) -> void:
	# +1 because cooldowns tick at the start of this unit's next turn.
	if cooldown > 0:
		cooldowns[skill_id] = cooldown + 1


func tick_cooldowns() -> void:
	for skill_id in cooldowns.keys():
		cooldowns[skill_id] = maxi(0, cooldowns[skill_id] - 1)


func tick_statuses() -> void:
	for status in statuses.keys():
		statuses[status] -= 1
		if statuses[status] <= 0:
			statuses.erase(status)
