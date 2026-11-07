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
signal combo(target: Combatant, name: String)
signal weak_hit(target: Combatant)
## A legend reached the next part of its fight: 1 = called for help, 2 = enraged.
signal legend_phase(legend: Combatant, phase: int)
## A legend called `fresh` to the fight, in the place of the fallen `replaced` (or null).
signal reinforced(fresh: Combatant, replaced: Combatant)
## A legend's Last Gasp: `turns_left` of its turns until it lands (0: landing now).
signal last_gasp(legend: Combatant, turns_left: int)
## The pack's perfect-wave streak changed: `stacks` > 0 is a fresh perfect wave, 0 means it's lost.
signal perfect_changed(stacks: int)

enum Outcome { ONGOING, WAVE_CLEARED, VICTORY, DEFEAT }

const DEF_SCALE := 50.0
const CRIT_MULT := 1.5
const INFECTION_DAMAGE := 0.06
const REST_HEAL := 0.15
const REVIVE_HP := 0.25
const HUNT_WEAK_CHANCE := 0.7
const FOCUS_KILL_CHANCE := 0.8  # a single-target hit goes for an animal it can knock out
const FOCUS_HEALER_CHANCE := 0.5  # otherwise it goes after the pack's healer
const ENRAGE_ROUND := 8  # past this round of a wave, zombies gain ENRAGE_STEP ATK every round
const ENRAGE_STEP := 0.1
const WINDUP_POWER := 1.75  # a telegraphed attack hits this much harder when it lands
const BRACE_SOAK := 0.5  # an animal with Guard up takes this share of a telegraphed attack

var party: Array[Combatant] = []
var enemies: Array[Combatant] = []
var wave_index := -1
var round_number := 0
var current: Combatant
var place := ""
var xp_earned := 0  # from every zombie and legend the pack has defeated so far
var xp_mult := 1.0  # XP per kill scales with the territory's own strength, not with pack-scaled zombies
var kills := 0  # zombies and legends the pack destroyed (revived ones count once); hits the weekly siege
var downed: Array[String] = []  # pack members knocked out at any point (they'll be injured)
var knocked_out := {}  # raids: owner account id -> ids of their critters knocked out at any point
var condition := ""
var boss_hp_mult := 1.0  # team maps: legends grow with the team
var boss_atk_mult := 1.0
var _perk_log: PackedStringArray = []  # lineup effects, announced as the first wave starts
## For the battle log (report()): what each unit dealt, took and used, and how long each wave ran.
var _dealt := {}  # Combatant -> damage
var _taken := {}  # Combatant -> damage
var _uses := {}  # Combatant -> {skill id: times}
var _wave_rounds: Array[int] = []
var _legends: Array[Combatant] = []
var warlord_name := ""  # the warlord in this fight, if any
var dungeon := ""  # a dungeon run: the region whose dungeon this is; its waves never end
var dungeon_start := 1  # the dungeon wave the run began on
var _legend_phase := {}  # Combatant -> how far through its fight: 1 = called for help, 2 = enraged, 3 = Last Gasp
var _last_gasp := {}  # Combatant -> its turns left before its Last Gasp lands
var perfect := 0  # perfect waves in a row (capped at PERFECT_MAX_STACKS); the pack's ATK bonus, until hurt
var perfect_waves := 0  # how many perfect waves this fight, for the log
var _wave_hurt := false  # an animal has taken damage this wave
var rng := RandomNumberGenerator.new()

var _waves: Array
var _zombie_mult: float
var _turn_queue: Array[Combatant] = []
var _unleashing := false  # a telegraphed attack is landing right now (Guard soaks it)
var _last_hit: Combatant  # the zombie the pack's last single-target attack hit (for Follow-up)
var _last_hitter: Combatant
var _defusing := false  # a Bloater is being finished by a water animal: no death blast
var _weak_told: Array[Combatant] = []  # zombies whose weak point the log has already explained


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
		c.row = profile.row_of(unit_id)
		party.append(c)
	condition = territory_condition
	_apply_lineup(profile, territory_region, party)


## The rest of a Campaign battle config: XP scale and a legend's growth. Call before the first wave.
func configure(cfg: Dictionary) -> void:
	xp_mult = cfg.get("xp_mult", cfg.get("zombie_mult", 1.0))
	boss_hp_mult = cfg.get("boss_hp", 1.0)
	boss_atk_mult = cfg.get("boss_atk", 1.0)
	warlord_name = cfg.get("warlord", "")
	dungeon = cfg.get("dungeon", "")
	dungeon_start = cfg.get("start", 1)


## A legend raid: every player's pack, in the same order on every device. `packs`:
## [{profile, owner (account id), name}]. Each pack keeps its own leader, bonds and lineup effects.
static func raid(packs: Array, waves: Array, zombie_mult: float, place_name: String, seed_value: int,
		territory_condition := "", territory_region := "") -> Battle:
	var b := Battle.new(Profile.new(), waves, zombie_mult, 1.0, place_name, seed_value, territory_condition)
	for pack: Dictionary in packs:
		b.add_pack(pack.profile, String(pack.owner), String(pack.name), territory_region)
	return b


## Adds one player's critters to a raid, with their own lineup effects.
func add_pack(p: Profile, owner_id: String, owner_name: String, region := "") -> void:
	var units: Array[Combatant] = []
	for unit_id in p.pack_ids():
		var c := p.build_unit(unit_id)
		c.row = p.row_of(unit_id)
		c.owner = owner_id
		c.ally_of = owner_name
		units.append(c)
	party.append_array(units)
	_apply_lineup(p, region, units)


## Injuries, fatigue, terrain, home turf and bonds: the reasons a lineup matters.
func _apply_lineup(profile: Profile, region: String, units: Array[Combatant]) -> void:
	var suited: PackedStringArray = []
	var natives: PackedStringArray = []
	for c in units:
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
	if condition != "" and not units.is_empty():
		_perk_log.append("[color=#2ce8f5]%s: %s[/color]" % [GameData.CONDITIONS[condition].name,
			("%s +%d%%" % [", ".join(suited), roundi(GameData.CONDITION_BONUS * 100)]) if not suited.is_empty() else "nobody here is suited to it"])
	if not natives.is_empty():
		_perk_log.append("[color=#2ce8f5]Home turf: %s +%d%%[/color]" % [", ".join(natives), roundi(GameData.HOME_TURF_BONUS * 100)])
	var ids: Array[String] = []
	for c in units:
		ids.append(c.id)
	for bond in GameData.active_bonds(ids):
		var names: PackedStringArray = []
		for c in units:
			if c.id in bond.members:
				c.scale_stats(1.0, 1.0 + GameData.BOND_BONUS, 1.0 + GameData.BOND_BONUS)
				c.notes.append(bond.name)
				names.append(c.display_name)
		_perk_log.append("[color=#feae34]Bond %s: %s +%d%% ATK/DEF[/color]" % [bond.name, ", ".join(names), roundi(GameData.BOND_BONUS * 100)])


## A summary of the fight for the battle log: the setup, every critter's stats and what it did,
## each legend's stats and how far it was worn down, and how many rounds each wave took.
func report() -> Dictionary:
	var rounds := _wave_rounds.duplicate()
	rounds.append(round_number)
	var pack: Array = []
	var owners: Array[String] = []  # raids: which player's critter it is, by number (no names in the log)
	for c in party:
		if c.owner not in owners:
			owners.append(c.owner)
		pack.append(_unit_report(c).merged({"player": owners.find(c.owner) + 1}))
	var legends: Array = []
	for z in _legends:
		legends.append(_unit_report(z).merged({"phase": _legend_phase.get(z, 0)}))
	return {"outcome": Outcome.keys()[outcome()].to_lower(), "wave": wave_index + 1, "waves": wave_count(),
		"rounds": rounds, "zombie_mult": snappedf(_zombie_mult, 0.01), "boss_hp": boss_hp_mult,
		"boss_atk": boss_atk_mult, "condition": condition, "pack": pack, "legends": legends,
		"zombies": _waves, "xp": xp_earned, "kills": kills, "perfect_waves": perfect_waves}


## The pack's ATK bonus from perfect waves right now (0.1 = +10%).
func perfect_atk_bonus() -> float:
	return GameData.PERFECT_ATK_STEP * perfect


func _unit_report(c: Combatant) -> Dictionary:
	var out := {"id": c.id, "lvl": c.level, "row": c.row, "hp": c.hp, "max_hp": c.max_hp, "atk": c.atk,
		"def": c.def, "spd": c.spd, "crit": snappedf(c.crit, 0.01), "dealt": _dealt.get(c, 0),
		"taken": _taken.get(c, 0), "uses": _uses.get(c, {})}
	if c.is_player:
		out.merge({"trinket": c.trinket, "leader": c.is_leader, "mods": c.skill_mods,
			"notes": c.notes, "down": c.id in knocked_out.get(c.owner, [])})
	return out


func wave_count() -> int:
	return _waves.size()


func is_last_wave() -> bool:
	return dungeon == "" and wave_index >= wave_count() - 1


## The dungeon wave number of the wave being fought (a run started part way down counts from there).
func dungeon_wave() -> int:
	return dungeon_start + wave_index


func start_next_wave() -> void:
	wave_index += 1
	if wave_index > 0:
		if not _wave_hurt:
			perfect = mini(perfect + 1, GameData.PERFECT_MAX_STACKS)
			perfect_waves += 1
			log_message.emit("[color=#ffd34d][b]PERFECT WAVE![/b] Not a scratch: the pack gets +%d%% ATK until one of them is hurt.[/color]" % roundi(perfect_atk_bonus() * 100))
			perfect_changed.emit(perfect)
		_rest_party()
	_wave_hurt = false
	if dungeon != "":
		if wave_index >= _waves.size():
			_waves.append(GameData.dungeon_wave(dungeon, dungeon_wave()))
		_zombie_mult = GameData.dungeon_mult(dungeon_wave())
		xp_mult = _zombie_mult * GameData.DUNGEON_XP_SHARE
	enemies.clear()
	var wave: Array = _waves[wave_index]
	var totals := {}
	for zombie_id in wave:
		totals[zombie_id] = totals.get(zombie_id, 0) + 1
	var seen := {}
	for zombie_id in wave:
		var z := Combatant.from_data(zombie_id, GameData.enemy(zombie_id), false)
		if totals[zombie_id] > 1:
			z.display_name += " " + "ABCDEFGH"[seen.get(zombie_id, 0)]
			seen[zombie_id] = seen.get(zombie_id, 0) + 1
		z.scale_stats(_zombie_mult, _zombie_mult, 1.0)
		if zombie_id == "warlord" and warlord_name != "":
			z.display_name = warlord_name
		if zombie_id == "brute" and dungeon != "":
			var tougher := GameData.dungeon_brute_mult(dungeon_wave())
			z.scale_stats(tougher, tougher, 1.0)
		if z.is_boss:
			z.scale_stats(boss_hp_mult, boss_atk_mult, 1.0)
			_legends.append(z)
		enemies.append(z)
	if wave_index > 0:
		_wave_rounds.append(round_number)
	round_number = 0
	_turn_queue.clear()
	current = null
	_last_hit = null
	if dungeon != "":
		log_message.emit("[b]Wave %d[/b]: deeper into %s..." % [dungeon_wave(), place])
	else:
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
				log_message.emit("%s's %s fouls the air!" % [c.display_name, GameData.trinket(c.trinket).name])
				for z in enemies:
					z.add_status("weakened", 2)
					status_changed.emit(z)
	for z in enemies:
		if z.is_boss:
			log_message.emit("[color=#c99bff][b]%s appears![/b] %s[/color]" % [z.display_name, GameData.LEGENDS[z.id].lore])
	for leader in living(party).filter(func(c: Combatant) -> bool: return c.is_leader):
		log_message.emit("[color=#ffd34d]%s leads the pack: allies +%d%% ATK/DEF.[/color]" % [
			leader.display_name, roundi(GameData.LEADER_AURA * 100)])
	_announce_exposed(party)
	_announce_exposed(enemies)


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
			if round_number == ENRAGE_ROUND + 1:
				log_message.emit("[color=#f77622][b]The horde is enraged![/b] Zombies gain +%d%% ATK every round now.[/color]" % roundi(ENRAGE_STEP * 100))
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
		if _last_gasp.has(actor):  # counts on every turn it gets, stunned or not
			_last_gasp[actor] -= 1
			if _last_gasp[actor] <= 0:
				_last_gasp[actor] = GameData.LEGEND_LAST_GASP_TURNS
				_unleash_last_gasp(actor)
				_end_turn(actor)
				continue
			log_message.emit("[color=#e43b44][b]Last Gasp in %d![/b][/color]" % _last_gasp[actor])
			last_gasp.emit(actor, _last_gasp[actor])
		if actor.has_status("stunned"):
			log_message.emit("%s is stunned!" % actor.display_name)
			if actor.winding != "":
				var lost := actor.skill_data(actor.winding)
				log_message.emit("[color=#63c74d]%s's %s is interrupted![/color]" % [actor.display_name, lost.name])
				actor.put_on_cooldown(actor.winding, lost.get("cooldown", 0))
				actor.winding = ""
				status_changed.emit(actor)
			_end_turn(actor)
			if actor.is_boss and actor.is_alive():
				actor.add_status("stun_proof", GameData.LEGEND_STUN_PROOF)
				log_message.emit("[color=#c99bff]%s shakes it off: it can't be stunned for %d turns.[/color]" % [actor.display_name, GameData.LEGEND_STUN_PROOF])
				status_changed.emit(actor)
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
		"enemy":
			return reachable(actor)
		"all_enemies":
			return living(_opponents(actor))
		"ally", "all_allies":
			return living(_allies(actor))
		"dead_ally":
			var fallen: Array[Combatant] = []
			for c in _allies(actor):
				if not c.is_alive() and not c.is_boss and not c.revived:
					fallen.append(c)
			return fallen
		_:
			return [actor]


func use_skill(actor: Combatant, skill_id: String, target: Combatant) -> void:
	var skill := actor.skill_data(skill_id)
	acting.emit(actor)
	var used: Dictionary = _uses.get_or_add(actor, {})
	used[skill_id] = int(used.get(skill_id, 0)) + 1
	if skill.get("windup", false) and actor.winding != skill_id:
		# Telegraphed: this turn only winds up. It lands on the zombie's next turn unless stunned.
		actor.winding = skill_id
		log_message.emit("[color=#f77622][b]%s winds up %s![/b] Stun it to cancel; Guard halves it.[/color]" % [actor.display_name, skill.name])
		status_changed.emit(actor)
		_end_turn(actor)
		return
	_unleashing = actor.winding == skill_id
	actor.winding = ""
	if not actor.is_player:
		_last_hit = null  # Follow-up needs back-to-back hits: any zombie turn breaks the chain
	actor.put_on_cooldown(skill_id, skill.get("cooldown", 0))
	if skill.get("revive", 0.0) > 0.0:
		target.hp = maxi(1, roundi(target.max_hp * skill.revive))
		target.revived = true
		log_message.emit("[color=#a0e080]%s drags %s back up![/color]" % [actor.display_name, target.display_name])
		healed.emit(target, target.hp)
		status_changed.emit(target)
		_end_turn(actor)
		return
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
			if skill.target == "enemy" and target.row == "back" and not exposed(target) and not target.has_status("taunt"):
				log_message.emit("[color=%s]%s reaches past the front row![/color]" % ["#63c74d" if actor.is_player else "#f77622", actor.display_name])

	var power: float = skill.get("power", 0.0) * (WINDUP_POWER if _unleashing else 1.0)
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
				if effect.status in t.immune or (effect.status == "stunned" and t.has_status("stun_proof")):
					continue
				if effect.status == "infected" and _weak_point(t, actor) == "immune":
					continue  # scavengers shrug off a Plague Carrier's rot
				if rng.randf() < effect.get("chance", 1.0):
					t.add_status(effect.status, effect.turns)
					if t != actor:
						log_message.emit("%s is %s." % [t.display_name, GameData.STATUSES[effect.status].name.to_lower()])
					status_changed.emit(t)
	var rally: Dictionary = skill.get("rally", {})
	if not rally.is_empty():
		var rallied := false
		for ally in living(_allies(actor)):
			if ally != actor:
				ally.add_status(rally.status, rally.turns)
				status_changed.emit(ally)
				rallied = true
		if rallied:
			log_message.emit("The other zombies are %s (+%d%% ATK)!" % [GameData.STATUSES[rally.status].name.to_lower(),
				roundi((GameData.FRENZIED_ATK_MULT - 1.0) * 100)])
	_unleashing = false
	_end_turn(actor)


## Zombie AI: strongest ready skill, respects Taunt. Single-target hits focus fire: usually on an
## animal they can knock out, else often on the pack's healer; some types prey on the weakest animal.
func plan_enemy_action(actor: Combatant) -> Dictionary:
	var skill_id := actor.skills[0]
	for id in actor.skills:
		if actor.can_use(id) and not valid_targets(actor, id).is_empty():
			skill_id = id
	if actor.winding != "":
		skill_id = actor.winding  # a wound-up attack always comes next
	var pool := valid_targets(actor, skill_id)
	var taunting: Array[Combatant] = []
	for c in pool:
		if c.has_status("taunt"):
			taunting.append(c)
	if not taunting.is_empty():
		pool = taunting
	var target: Combatant = pool[rng.randi_range(0, pool.size() - 1)]
	if not taunting.is_empty() or GameData.skill(skill_id).target != "enemy":
		return {"skill": skill_id, "target": target}
	var power: float = GameData.skill(skill_id).get("power", 0.0)
	var kills: Array[Combatant] = []
	var healers: Array[Combatant] = []
	for c in pool:
		if power > 0.0 and _base_damage(actor, c, power) >= c.hp:
			kills.append(c)
		if _is_healer(c):
			healers.append(c)
	if not kills.is_empty() and rng.randf() < FOCUS_KILL_CHANCE:
		target = kills[rng.randi_range(0, kills.size() - 1)]
	elif not healers.is_empty() and rng.randf() < FOCUS_HEALER_CHANCE:
		target = healers[rng.randi_range(0, healers.size() - 1)]
	elif actor.traits.get("hunts_weak", false) and rng.randf() < HUNT_WEAK_CHANCE:
		for c in pool:
			if c.hp < target.hp:
				target = c
	return {"skill": skill_id, "target": target}


## True if `c` can heal its allies (not just itself).
func _is_healer(c: Combatant) -> bool:
	for id in c.skills:
		var s := c.skill_data(id)
		if s.get("heal", 0.0) > 0.0 and s.target in ["ally", "all_allies"]:
			return true
	return false


## Opponents a single-target attack can hit: the back row only while fewer than SCREEN_SIZE stand in
## front, unless the attacker reaches (birds, Runners, flying legends). A taunting unit can always be hit.
func reachable(actor: Combatant) -> Array[Combatant]:
	var foes := living(_opponents(actor))
	if _reaches(actor) or foes.filter(func(c: Combatant) -> bool: return c.row == "front").size() < GameData.SCREEN_SIZE:
		return foes
	var out: Array[Combatant] = []
	for c in foes:
		if c.row == "front" or c.has_status("taunt"):
			out.append(c)
	return out


## True if `c` stands in the back row but too few of its side stand in front to screen it.
func exposed(c: Combatant) -> bool:
	return c.row == "back" and c.is_alive() and _front_count(_allies(c)) < GameData.SCREEN_SIZE


func _front_count(side: Array[Combatant]) -> int:
	var n := 0
	for c in side:
		if c.is_alive() and c.row == "front":
			n += 1
	return n


## Says so when the back row loses its screen (or starts without one).
func _announce_exposed(side: Array[Combatant]) -> void:
	var open: PackedStringArray = []
	for c in side:
		if exposed(c):
			open.append(c.display_name)
	if open.is_empty():
		return
	var pack := side == party
	log_message.emit("[color=%s][b]%s back row is exposed![/b] Fewer than %d stand in front, so single-target attacks can reach %s.[/color]" % [
		"#f77622" if pack else "#63c74d", "Your" if pack else "The zombies'", GameData.SCREEN_SIZE, ", ".join(open)])


## The trick `src` brings against `dst`'s weak point (GameData.ZOMBIE_WEAKNESS): "damage", "armor",
## "defuse" or "immune"; "" if it has none there.
func _weak_point(src: Combatant, dst: Combatant) -> String:
	if not src.is_player or dst.is_player:
		return ""
	var w: Dictionary = GameData.ZOMBIE_WEAKNESS.get(dst.id, {})
	if w.is_empty() or w.tag not in src.tags:
		return ""
	return w.get("effect", "damage")


func _reaches(c: Combatant) -> bool:
	return c.traits.get("reach", false) or "bird" in c.tags


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


## Fastest first; ties go to the pack, then to whoever comes first in the lineup, so every device in
## a raid agrees on the order.
func _turn_order() -> Array[Combatant]:
	var order := living(party) + living(enemies)
	var place := {}
	for k in order.size():
		place[order[k]] = k
	order.sort_custom(func(a: Combatant, b: Combatant) -> bool:
		if a.spd != b.spd:
			return a.spd > b.spd
		if a.is_player != b.is_player:
			return a.is_player
		return place[a] < place[b])
	var typed: Array[Combatant] = []
	typed.assign(order)
	return typed


func _end_turn(actor: Combatant) -> void:
	if not actor.statuses.is_empty():
		actor.tick_statuses()
		status_changed.emit(actor)


## The living leader of `owner`'s pack on this side (each player's pet leads their own pack).
func _leader(side: Array[Combatant], owner_id := "") -> Combatant:
	for c in side:
		if c.is_leader and c.is_alive() and c.owner == owner_id:
			return c
	return null


## 1 + LEADER_AURA when a living leader (other than this unit) is on its side.
func _aura_mult(c: Combatant) -> float:
	var leader := _leader(_allies(c), c.owner)
	return 1.0 + GameData.LEADER_AURA if leader and leader != c else 1.0


## Damage before the roll, crits, armor and legend weak spots.
func _base_damage(src: Combatant, dst: Combatant, power: float) -> float:
	var atk := src.atk * _aura_mult(src)
	if src.has_status("weakened"):
		atk *= GameData.WEAKENED_ATK_MULT
	if src.has_status("frenzied"):
		atk *= GameData.FRENZIED_ATK_MULT
	if src.is_player:
		atk *= 1.0 + perfect_atk_bonus()
	if src.traits.get("horde", false):
		var pack_mates := 0
		for c in living(_allies(src)):
			if c != src and c.id == src.id:
				pack_mates += 1
		atk *= 1.0 + GameData.HORDE_ATK_STEP * pack_mates
	if not src.is_player and round_number > ENRAGE_ROUND:
		atk *= 1.0 + ENRAGE_STEP * (round_number - ENRAGE_ROUND)
	return atk * power * DEF_SCALE / (DEF_SCALE + dst.effective_def() * _aura_mult(dst))


func _deal_damage(src: Combatant, dst: Combatant, power: float, crit_bonus: float, single := true) -> void:
	var dmg := _base_damage(src, dst, power)
	dmg *= rng.randf_range(0.9, 1.1)
	var crit := rng.randf() < src.crit + crit_bonus
	var combos: PackedStringArray = []
	if src.is_player and single:
		if crit_bonus > 0.0 and dst.has_status("stunned"):
			crit = true
			combos.append("Opening")
		if _last_hit == dst and _last_hitter != src:
			dmg *= 1.0 + GameData.FOLLOW_UP_BONUS
			combos.append("Follow-up")
		_last_hit = dst
		_last_hitter = src
	if crit:
		dmg *= CRIT_MULT
	var trick := _weak_point(src, dst)  # this zombie type's weak point (legends have their own below)
	if trick != "" and trick != "armor":
		dmg *= GameData.ZOMBIE_WEAK_MULT
	if single and dst.traits.get("armored", false) and trick != "armor":
		dmg *= 0.5
	if single and src.row == "back" and not _reaches(src):
		dmg *= GameData.BACK_ROW_DAMAGE
	if _unleashing and dst.has_status("guard"):
		dmg *= BRACE_SOAK
	if dst.is_boss and src.is_player:
		var weak: Dictionary = GameData.LEGEND_WEAKNESS[GameData.LEGENDS[dst.id].build]
		if weak.weak in src.tags:
			dmg *= GameData.LEGEND_WEAK_MULT
		elif weak.resist in src.tags:
			dmg *= GameData.LEGEND_RESIST_MULT
	var amount := maxi(1, roundi(dmg))
	if trick != "":
		weak_hit.emit(dst)
		if dst not in _weak_told:
			_weak_told.append(dst)
			log_message.emit("[color=#2ce8f5][b]Weak spot![/b] %s vs %s: %s[/color]" % [
				src.display_name, dst.display_name, GameData.ZOMBIE_WEAKNESS[dst.id].why])
	_defusing = trick == "defuse"
	_apply_damage(dst, amount, crit)
	_dealt[src] = int(_dealt.get(src, 0)) + amount
	_defusing = false
	var knockdown := src.is_player and single and power >= GameData.KNOCKDOWN_POWER
	if knockdown and dst.is_alive() and dst.has_status("weakened") and "stunned" not in dst.immune and not dst.has_status("stun_proof"):
		dst.add_status("stunned", 1)
		status_changed.emit(dst)
		combos.append("Knockdown")
	for name in combos:
		log_message.emit("[color=#2ce8f5][b]COMBO: %s![/b][/color] %s" % [name, {
			"Opening": "a sure crit on a stunned zombie.",
			"Follow-up": "+%d%% on the zombie an ally just hit." % roundi(GameData.FOLLOW_UP_BONUS * 100),
			"Knockdown": "the weakened %s is stunned." % dst.display_name}[name]])
		combo.emit(dst, name)
	if src.lifesteal > 0.0 and src.is_alive() and src.hp < src.max_hp:
		_heal(src, maxi(1, roundi(amount * src.lifesteal)))
	if dst.thorns > 0.0 and src.is_alive():
		_apply_damage(src, maxi(1, roundi(amount * dst.thorns)), false)


func _apply_damage(dst: Combatant, amount: int, crit: bool) -> void:
	_taken[dst] = int(_taken.get(dst, 0)) + mini(amount, dst.hp)
	dst.hp = maxi(0, dst.hp - amount)
	if dst.is_player and amount > 0:
		_wave_hurt = true
		if perfect > 0:
			perfect = 0
			log_message.emit("[color=#ff8080]%s is hurt: the perfect streak is over.[/color]" % dst.display_name)
			perfect_changed.emit(0)
	damaged.emit(dst, amount, crit)
	if dst.is_alive():
		if dst.is_boss:
			_advance_legend(dst)
		return
	dst.statuses.clear()
	log_message.emit("[color=%s]%s %s![/color]" % [
		"#ff8080" if dst.is_player else "#a0e080",
		dst.display_name,
		"is down" if dst.is_player else "is destroyed",
	])
	died.emit(dst)
	if dst.row == "front" and _front_count(_allies(dst)) == GameData.SCREEN_SIZE - 1 and outcome() == Outcome.ONGOING:
		_announce_exposed(_allies(dst))
	if dst.is_player:
		dst.fell_in_wave = wave_index
		if dst.id not in downed and dst.owner == "":
			downed.append(dst.id)
		var theirs: Array = knocked_out.get_or_add(dst.owner, [])
		if dst.id not in theirs:
			theirs.append(dst.id)
	if not dst.is_player and not dst.revived:
		xp_earned += roundi(dst.xp_value * xp_mult)
		kills += 1
	if dst.is_leader and outcome() == Outcome.ONGOING:
		log_message.emit("[color=#ff8080]Without %s, the pack falters![/color]" % dst.display_name)
	var blast: int = dst.traits.get("explode_on_death", 0)
	if blast > 0 and _defusing:
		log_message.emit("[color=#63c74d]%s is doused before it can burst.[/color]" % dst.display_name)
	elif blast > 0:
		log_message.emit("%s bursts in a cloud of gore!" % dst.display_name)
		for c in living(_opponents(dst)):
			_apply_damage(c, blast, false)


## Legends change as they're worn down. Worked out here, from HP alone, so every raid device agrees.
func _advance_legend(legend: Combatant) -> void:
	var phase: int = _legend_phase.get(legend, 0)
	if phase < 1 and legend.hp_ratio() <= GameData.LEGEND_ADDS_AT:
		phase = 1
		log_message.emit("[color=#c99bff][b]%s calls for help![/b][/color]" % legend.display_name)
		for zombie_id: String in GameData.LEGEND_ADDS:
			_call_add(zombie_id)
		legend_phase.emit(legend, 1)
	if phase < 2 and legend.hp_ratio() <= GameData.LEGEND_ENRAGE_AT:
		phase = 2
		legend.atk = roundi(legend.atk * GameData.LEGEND_ENRAGE_ATK)  # (scale_stats would refill its HP)
		log_message.emit("[color=#f77622][b]%s is enraged![/b] It hits %d%% harder from now on.[/color]" % [
			legend.display_name, roundi((GameData.LEGEND_ENRAGE_ATK - 1.0) * 100)])
		status_changed.emit(legend)
		legend_phase.emit(legend, 2)
	if phase < 3 and legend.hp_ratio() <= GameData.LEGEND_LAST_GASP_AT:
		phase = 3
		_last_gasp[legend] = GameData.LEGEND_LAST_GASP_TURNS
		log_message.emit("[color=#e43b44][b]%s begins its LAST GASP![/b] In %d of its turns it hits every animal for %d%% of their HP, and nothing stops it. Kill it first![/color]" % [
			legend.display_name, GameData.LEGEND_LAST_GASP_TURNS, roundi(GameData.LEGEND_LAST_GASP_DAMAGE * 100)])
		_legend_phase[legend] = phase
		legend_phase.emit(legend, 3)
		last_gasp.emit(legend, GameData.LEGEND_LAST_GASP_TURNS)
	_legend_phase[legend] = phase


## The Last Gasp lands: every animal loses LEGEND_LAST_GASP_DAMAGE of its max HP, whatever its DEF or
## Guard. Then the count starts again.
func _unleash_last_gasp(legend: Combatant) -> void:
	log_message.emit("[color=#e43b44][b]%s's LAST GASP tears through the pack![/b][/color]" % legend.display_name)
	last_gasp.emit(legend, 0)
	for c in living(party):
		_apply_damage(c, maxi(1, roundi(c.max_hp * GameData.LEGEND_LAST_GASP_DAMAGE)), false)


## One more zombie for the legend: in a fallen zombie's place, or a free one (4 at most). Gives no XP,
## so it can't be farmed. Tougher in a raid, where the legend is too.
func _call_add(zombie_id: String) -> void:
	var slot := -1
	for k in enemies.size():
		if not enemies[k].is_alive() and not enemies[k].is_boss:
			slot = k
			break
	if slot < 0 and enemies.size() >= GameData.MAX_ENEMIES:
		return
	var z := Combatant.from_data(zombie_id, GameData.enemy(zombie_id), false)
	z.scale_stats(_zombie_mult * sqrt(boss_hp_mult), _zombie_mult, 1.0)
	z.xp_value = 0
	var replaced: Combatant = enemies[slot] if slot >= 0 else null
	if slot >= 0:
		enemies[slot] = z
	else:
		enemies.append(z)
	reinforced.emit(z, replaced)


func _heal(target: Combatant, amount: int) -> void:
	var actual := mini(amount, target.max_hp - target.hp)
	target.hp += actual
	healed.emit(target, actual)


## Between waves: the living heal a little; an animal knocked out last wave sits this one out and
## gets back up at REVIVE_HP the wave after. Cooldowns keep running (the rest counts as one turn).
func _rest_party() -> void:
	var rest := GameData.DUNGEON_REST if dungeon != "" else REST_HEAL
	log_message.emit("The pack catches its breath. (+%d%% HP)" % roundi(rest * 100))
	for c in party:
		if c.is_alive():
			c.hp = mini(c.max_hp, c.hp + roundi(c.max_hp * rest))
		elif wave_index - c.fell_in_wave >= 2:
			c.hp = roundi(c.max_hp * REVIVE_HP)
			log_message.emit("%s is back on its paws." % c.display_name)
		else:
			log_message.emit("[color=#ff8080]%s is still down and sits this wave out.[/color]" % c.display_name)
		c.statuses.clear()
		c.tick_cooldowns()
